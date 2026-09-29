import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const kit = process.argv[2];
const helper = join(kit, ".agent-stack/resources/web-qa/ask-jev.ts");
const temp = await mkdtemp(join(tmpdir(), "astack-jev-test-"));
let received;
const response = { model: "jev-test", answers: { yes: { type: "noul", noul: 1 } }, usage: { input_tokens: 1, output_tokens: 1 } };
const server = createServer((req, res) => {
  let body = "";
  req.setEncoding("utf8");
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", () => {
    received = { method: req.method, authorization: req.headers.authorization, body: JSON.parse(body) };
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(response));
  });
});

try {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = server.address().port;
  const home = join(temp, "home");
  await mkdir(join(home, ".config/astack"), { recursive: true });
  await writeFile(join(home, ".config/astack/env"), "JEV_GATEWAY_API_KEY=secret-for-test\n");
  const request = {
    state: { proposal: "change" },
    questions: {
      yes: { type: "noul", instructions: "Is it safe?" },
      choice: { type: "choice", instructions: "Which?", criteria: { a: "A", b: "B" } },
      score: { type: "score", instructions: "How much?", criteria: ["low", "high"] },
    },
  };
  const requestPath = join(temp, "request.json");
  await writeFile(requestPath, JSON.stringify(request));
  const result = await run(["--request", "-"], {
    HOME: home,
    XDG_CONFIG_HOME: join(home, ".config"),
    JEV_PROVIDER: "gateway",
    JEV_GATEWAY_URL: `http://127.0.0.1:${port}/v1/systemone`,
  }, JSON.stringify(request));
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), response);
  assert.equal(received.method, "POST");
  assert.equal(received.authorization, "Bearer secret-for-test");
  assert.deepEqual(received.body.questions, request.questions);
  assert.deepEqual(received.body.state, request.state);

  await writeFile(requestPath, JSON.stringify({ state: "bad", questions: { x: { type: "nope", instructions: "?" } } }));
  const invalid = await run(["--request", requestPath], {
    HOME: home,
    XDG_CONFIG_HOME: join(home, ".config"),
    JEV_PROVIDER: "gateway",
    JEV_GATEWAY_URL: `http://127.0.0.1:${port}/v1/systemone`,
  });
  assert.notEqual(invalid.code, 0);
  assert.match(invalid.stderr, /unsupported type/);
  console.log("PASS Jev typed request transport");
} finally {
  server.close();
  await rm(temp, { recursive: true, force: true });
}

function run(args, env, stdin = "") {
  return new Promise((resolve, reject) => {
    const child = spawn("node", ["--experimental-strip-types", helper, ...args], {
      cwd: temp,
      env: { ...process.env, ...env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(stdin);
  });
}
