// Minimal Jev caller for the web-qa agent. Zero dependencies (Node 20+).
// Reads TYPESAFE_API_KEY from the environment — never from args or files.
//
// Usage:
//   node --experimental-strip-types scripts/qa/ask-jev.ts \
//     --state state.json [--questions questions.json] \
//     [--dims functional,view,business] [--model jev-latest]
//
// State shape: { test_goal, expected, governance, page, trace }.
// Prints the raw systemOne response JSON to stdout.

import { readFileSync } from "node:fs";

interface Args {
  state: string;
  questions?: string;
  dims: string;
  model: string;
}

function parseArgs(argv: string[]): Args {
  const out: Args = { state: "", dims: "functional,view,business", model: "jev-latest" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--state") out.state = argv[++i] ?? "";
    else if (a === "--questions") out.questions = argv[++i];
    else if (a === "--dims") out.dims = argv[++i] ?? out.dims;
    else if (a === "--model") out.model = argv[++i] ?? out.model;
    else if (a === "-h" || a === "--help") {
      console.log("usage: ask-jev.ts --state state.json [--questions q.json] [--dims functional,view,business] [--model jev-latest]");
      process.exit(0);
    } else {
      throw new Error(`unknown argument: ${a}`);
    }
  }
  if (!out.state) throw new Error("--state state.json is required");
  return out;
}

function defaultCriteria(name: string): unknown {
  // Mirrors questions.ts so --questions can be omitted for the standard library.
  const functional = ["task_completed", "action_had_visible_effect", "error_blocked_task", "persisted_after_reload"];
  const view = ["one_primary_action", "impact_before_confirm", "copy_plain_and_actionable", "status_explains_next_step"];
  const business = ["payment_classified", "no_synthetic_cash", "trace_present", "register_gate_respected"];
  if (functional.includes(name) || view.includes(name) || business.includes(name)) return undefined;
  if (name === "verdict")
    return {
      pass: "Goal achieved, no governance violation, no blocking error.",
      blocking: "Correctness, money, permission, or governance violation.",
      nit: "Polish or subjective improvement only.",
      unverified: "Cannot be decided from the supplied state and trace.",
    };
  if (name === "domain")
    return { functional: "Action success and errors.", view: "Copy and guidance.", business_logic: "Money and register rules." };
  if (name === "severity")
    return ["Cosmetic polish.", "Confusing but completable.", "Blocks the task or risks money, stock, permission, or audit."];
  return undefined;
}

function defaultInstructions(name: string): string {
  const map: Record<string, string> = {
    task_completed: "Does `page.visible_copy` and `trace` show the goal in `test_goal` completed?",
    action_had_visible_effect: "Did the last action in `trace` produce the expected change in `expected`?",
    error_blocked_task: "Does `page.console_errors` or `page.visible_copy` show an error blocking `test_goal`?",
    persisted_after_reload: "Does `trace` show the result of `test_goal` surviving reload?",
    one_primary_action: "Does `page` present one primary action for `test_goal` per `governance.P02`?",
    impact_before_confirm: "Does `page.visible_copy` show impact before confirmation per `governance.P05`?",
    copy_plain_and_actionable: "Is `page.visible_copy` plain language describing the action result per `governance.copy_rule`?",
    status_explains_next_step: "Does status in `page.visible_copy` explain situation and next step per `governance.P04`?",
    payment_classified: "Is payment origin explicit (in-register vs external vs on-account) per `governance.payment_classification`?",
    no_synthetic_cash: "Does `trace` avoid synthetic register-cash effects per `governance.no_synthetic_cash`?",
    trace_present: "Is the money action traceable per `governance.traceability`?",
    register_gate_respected: "Are cash actions gated on open register while non-cash are not blocked, per `governance.register_gate`?",
    verdict: "Which QA outcome best fits `page` and `trace` for `test_goal`?",
    domain: "Which dimension owns the primary finding for `test_goal`?",
    severity: "How severe is the primary finding for `test_goal`?",
  };
  return map[name] ?? name;
}

function defaultType(name: string): "noul" | "choice" | "score" {
  if (name === "verdict" || name === "domain") return "choice";
  if (name === "severity") return "score";
  return "noul";
}

function buildDefaultQuestions(dims: string): Record<string, object> {
  const want = dims.split(",").map((s) => s.trim());
  const names: string[] = ["verdict", "domain", "severity"];
  const groups: Record<string, string[]> = {
    functional: ["task_completed", "action_had_visible_effect", "error_blocked_task", "persisted_after_reload"],
    view: ["one_primary_action", "impact_before_confirm", "copy_plain_and_actionable", "status_explains_next_step"],
    business: ["payment_classified", "no_synthetic_cash", "trace_present", "register_gate_respected"],
  };
  for (const d of want) names.unshift(...(groups[d] ?? []));
  const out: Record<string, object> = {};
  for (const n of names) {
    const q: Record<string, unknown> = { type: defaultType(n), instructions: defaultInstructions(n) };
    const c = defaultCriteria(n);
    if (c !== undefined) q.criteria = c;
    out[n] = q;
  }
  return out;
}

async function postWithRetry(url: string, init: RequestInit, attempts = 4): Promise<Response> {
  let delay = 500;
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, init);
      if (res.status === 429 || res.status === 529 || res.status >= 500) {
        lastErr = new Error(`retryable status ${res.status}`);
      } else {
        return res;
      }
    } catch (e) {
      lastErr = e;
    }
    await new Promise((r) => setTimeout(r, delay));
    delay *= 2;
  }
  throw lastErr instanceof Error ? lastErr : new Error("request failed");
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = process.env.TYPESAFE_API_KEY ?? "";
  if (!apiKey) {
    console.error("TYPESAFE_API_KEY is not set. Run: as auth jev");
    process.exit(2);
  }
  const state = JSON.parse(readFileSync(args.state, "utf8"));
  const questions = args.questions
    ? JSON.parse(readFileSync(args.questions, "utf8"))
    : buildDefaultQuestions(args.dims);

  const res = await postWithRetry("https://api.typesafe.ai/v1/systemone", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ state, model: args.model, questions }),
  });
  const text = await res.text();
  if (!res.ok) {
    console.error(`typesafe error ${res.status}: ${text}`);
    process.exit(1);
  }
  console.log(text);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
