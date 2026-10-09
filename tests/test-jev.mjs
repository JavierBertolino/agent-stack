import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const kit = process.argv[2];
const helper = join(kit, ".agent-stack/resources/web-qa/ask-jev.ts");
const webQuestions = join(kit, ".agent-stack/resources/web-qa/questions.ts");
const mobileQuestions = join(kit, ".agent-stack/resources/mobile-qa/questions-mobile.ts");
const actionSelection = join(kit, ".agent-stack/resources/jev/action-selection.ts");
const selectionValidator = join(kit, ".agent-stack/resources/jev/validate-action-selection.ts");
const temp = await mkdtemp(join(tmpdir(), "astack-jev-test-"));
const home = join(temp, "home");
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
  const env = {
    HOME: home,
    XDG_CONFIG_HOME: join(home, ".config"),
    JEV_PROVIDER: "gateway",
    JEV_GATEWAY_URL: `http://127.0.0.1:${port}/v1/systemone`,
  };
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
  const result = await run(["--request", "-"], env, JSON.stringify(request));
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), response);
  assert.equal(received.method, "POST");
  assert.equal(received.authorization, "Bearer secret-for-test");
  assert.deepEqual(received.body.questions, request.questions);
  assert.deepEqual(received.body.state, request.state);

  await writeFile(requestPath, JSON.stringify({ state: "bad", questions: { x: { type: "nope", instructions: "?" } } }));
  const invalid = await run(["--request", requestPath], env);
  assert.notEqual(invalid.code, 0);
  assert.match(invalid.stderr, /unsupported type/);
  console.log("PASS Jev typed request transport");

  // --- Bounded action selection and executable fail-closed gate ----------
  // The question exposes only the agent's descriptions/effects. Authorization
  // and preconditions stay local for validation and are never sent to Jev.
  const web = await import(webQuestions);
  const mobile = await import(mobileQuestions);
  const gate = await import(actionSelection);

  assert.equal(typeof web.buildSelectionQuestion, "function", "web selection builder missing");
  assert.equal(typeof mobile.buildMobileSelectionQuestion, "function", "mobile selection builder missing");

  const candidates = [
    {
      id: "open_task_row", description: "Open the visible task row",
      effects: "Loads the task detail view", authorized: true,
      preconditions: { "/page/visible_copy": "Tasks", "/page/rows/0/id": "task_42" },
    },
    {
      id: web.INSPECT_MORE, description: "Re-read the page",
      effects: "No state change", authorized: true, preconditions: {},
    },
    {
      id: web.STOP, description: "Stop here", effects: "Ends the checkpoint",
      authorized: true, preconditions: { "/goal_met": true },
    },
  ];
  const selection = web.buildSelectionQuestion(candidates);
  assert.equal(selection.type, "choice", "selection must be a choice question");
  assert.deepEqual(Object.keys(selection.criteria), candidates.map((c) => c.id));
  assert.match(selection.criteria.open_task_row, /Open the visible task row.*Possible effects: Loads the task detail view/);
  assert.ok(selection.criteria[web.INSPECT_MORE], "inspect_more must be representable");
  assert.ok(selection.criteria[web.STOP], "stop must be representable");
  assert.ok(!JSON.stringify(selection).includes("authorized"), "authorization must remain local");
  assert.ok(!JSON.stringify(selection).includes("preconditions"), "preconditions must remain local");
  // The evaluation library is unchanged by the selection builder.
  assert.deepEqual(Object.keys(web.buildQuestions()).includes("verdict"), true);
  assert.equal(web.buildQuestions().next_action, undefined, "selection must not enter the evaluation set");
  assert.equal(mobile.buildMobileQuestions().next_action, undefined, "selection must not enter the evaluation set");

  const mobileSelection = mobile.buildMobileSelectionQuestion([
    { id: "tap_confirmar", description: "Tap the visible Confirmar button", effects: "Dismisses the dialog", authorized: true, preconditions: { "/screen/visible_copy": "Confirmar" } },
    { id: mobile.MOBILE_INSPECT_MORE, description: "Re-read the screen", effects: "No state change", authorized: true, preconditions: {} },
    { id: mobile.MOBILE_STOP, description: "Stop here", effects: "Ends the checkpoint", authorized: true, preconditions: { "/goal_met": true } },
  ]);
  assert.equal(mobileSelection.type, "choice");
  assert.equal(Object.keys(mobileSelection.criteria).length, 3);

  // A malformed candidate set cannot be built into a question.
  assert.throws(() => web.buildSelectionQuestion([]), /candidate set/);
  assert.throws(() => web.buildSelectionQuestion([
    { id: "open_task_row", description: "x", effects: "y", authorized: true, preconditions: { "/page/x": 1 } },
    { id: "open_other", description: "other", effects: "z", authorized: true, preconditions: { "/page/y": 2 } },
  ]), /include inspect_more/);
  assert.throws(() => web.buildSelectionQuestion([
    { id: "open_task_row", description: "x", effects: "y", authorized: false, preconditions: { "/page/x": 1 } },
    { id: web.INSPECT_MORE, description: "Inspect", effects: "No change", authorized: true, preconditions: {} },
  ]), /unauthorized candidate/);
  assert.throws(() => web.buildSelectionQuestion([
    { id: "open_task_row", description: "x", effects: "y", authorized: true, preconditions: { "/page/x": 1 } },
    { id: web.INSPECT_MORE, description: "Inspect", effects: "No change", authorized: false, preconditions: {} },
  ]), /unauthorized candidate/);
  assert.throws(
    () => web.buildSelectionQuestion([
      { id: "dup", description: "a", effects: "x", authorized: true, preconditions: { "/x": 1 } },
      { id: "dup", description: "b", effects: "y", authorized: true, preconditions: { "/y": 2 } },
      { id: web.INSPECT_MORE, description: "Inspect", effects: "No change", authorized: true, preconditions: {} },
    ]),
    /duplicate candidate id/,
  );
  assert.throws(() => web.buildSelectionQuestion([
    { id: "open_task_row", description: "x", effects: "y", authorized: true, preconditions: { "/bad~2pointer": 1 } },
    { id: web.INSPECT_MORE, description: "Inspect", effects: "No change", authorized: true, preconditions: {} },
  ]), /invalid JSON Pointer/);
  console.log("PASS bounded action-selection builder");

  const selectionState = {
    test_goal: "Open the first task and read its detail",
    expected: "The task detail view is visible",
    goal_met: false,
    page: { visible_copy: "Tasks", rows: [{ id: "task_42" }] },
  };
  const selectionRequest = { state: selectionState, questions: { next_action: selection } };
  const selectionResult = await run(["--request", "-"], env, JSON.stringify(selectionRequest));
  assert.equal(selectionResult.code, 0, selectionResult.stderr);
  // The candidate set reaches Jev bounded and unchanged: exactly the three
  // opaque ids and descriptive strings; authorization metadata stays local.
  const sentSelection = received.body.questions.next_action;
  assert.equal(sentSelection.type, "choice");
  assert.deepEqual(Object.keys(sentSelection.criteria), candidates.map((c) => c.id));
  assert.deepEqual({ ...received.body.questions.next_action.criteria }, { ...selection.criteria });
  assert.ok(!JSON.stringify(received.body).includes("preconditions"));
  assert.ok(!JSON.stringify(received.body).includes("authorized"));
  assert.deepEqual(received.body.state, selectionState);
  console.log("PASS bounded candidate set forwarded to Jev");

  // An empty candidate map is refused by the transport before any request.
  const emptySelection = join(temp, "empty-selection.json");
  await writeFile(emptySelection, JSON.stringify({
    state: selectionState,
    questions: { next_action: { type: "choice", instructions: "Which one?", criteria: {} } },
  }));
  const emptyResult = await run(["--request", emptySelection], env);
  assert.notEqual(emptyResult.code, 0, "an empty candidate set must not reach Jev");
  assert.match(emptyResult.stderr, /option map/);
  console.log("PASS malformed candidate set refused");

  const recommendation = (choice, confidence = 0.91, probabilities = {
    open_task_row: 0.91, inspect_more: 0.05, stop: 0.04,
  }) => ({ answers: { next_action: { type: "choice", choice, confidence, probabilities } } });
  const validate = (responseValue, submitted = selectionState, current = selectionState, list = candidates) =>
    gate.validateActionSelection({
      response: responseValue,
      questionId: "next_action",
      candidates: list,
      submittedObservation: submitted,
      currentObservation: current,
    });

  assert.deepEqual(validate(recommendation("open_task_row")), {
    status: "execute", candidateId: "open_task_row", confidence: 0.91,
  });
  assert.equal(validate(recommendation("old_id")).status, "reject", "unknown/stale id must fail closed");
  assert.equal(validate(recommendation("open_task_row", 0.74)).status, "inspect_more", "low confidence cannot execute");
  assert.equal(validate(recommendation("open_task_row", 0.91, { open_task_row: 1 })).status, "reject", "probability keys must match the whole set");
  assert.equal(validate(recommendation("open_task_row", 0.91, { open_task_row: 0.4, inspect_more: 0.3, stop: 0.1 })).status, "reject", "probabilities must sum to one");
  assert.equal(validate(recommendation("open_task_row"), selectionState, { ...selectionState, page: { visible_copy: "Updated" } }).status, "reinspect", "changed observation must invalidate the answer");
  assert.equal(validate(recommendation("open_task_row"), selectionState, {
    ...selectionState, page: { visible_copy: "Tasks", rows: [{ id: "other" }] },
  }).status, "reinspect", "failed preconditions must invalidate the answer");
  assert.equal(validate(recommendation("inspect_more")).status, "inspect_more");
  const completed = { ...selectionState, goal_met: true };
  const stopChoice = recommendation("stop", 0.93, { open_task_row: 0.02, inspect_more: 0.05, stop: 0.93 });
  assert.equal(validate(stopChoice, completed, completed).status, "stop");
  assert.equal(validate(recommendation("open_task_row"), selectionState, selectionState, [
    { ...candidates[0], authorized: false }, candidates[1], candidates[2],
  ]).status, "reject", "the validator rejects unauthorized candidate records");
  console.log("PASS executable action-selection validation gate");

  const cliInput = {
    question_id: "next_action", response: recommendation("open_task_row"),
    candidates, submitted_observation: selectionState, current_observation: selectionState,
  };
  const cli = await runValidator(cliInput);
  assert.equal(cli.code, 0, cli.stderr);
  assert.deepEqual(JSON.parse(cli.stdout), { status: "execute", candidateId: "open_task_row", confidence: 0.91 });
  const cliReject = await runValidator({ ...cliInput, response: recommendation("old_id") });
  assert.equal(cliReject.code, 2);
  assert.equal(JSON.parse(cliReject.stdout).status, "reject");
  const thresholdOverride = await runValidator({
    ...cliInput,
    response: recommendation("open_task_row", 0.74),
    confidence_threshold: 0.01,
  });
  assert.equal(thresholdOverride.code, 2);
  assert.match(thresholdOverride.stderr, /fixed at 0.75/);
  console.log("PASS selection-validation CLI fail-closed output");
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

function runValidator(input) {
  return new Promise((resolve, reject) => {
    const child = spawn("node", ["--experimental-strip-types", selectionValidator], {
      cwd: temp,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(JSON.stringify(input));
  });
}
