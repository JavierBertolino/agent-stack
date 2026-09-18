// Minimal Jev caller for the web-qa and mobile-qa agents.
// Zero dependencies (Node 20+). Credentials come from the environment —
// never from args or files. Configure them with: astack auth jev
//
// Providers (JEV_PROVIDER):
//   typesafe (default) — TypeSafe direct, TYPESAFE_API_KEY,
//                        https://api.typesafe.ai/v1/systemone
//   vercel             — Vercel AI Gateway, AI_GATEWAY_API_KEY,
//                        Jev model typesafe-ai/jev-latest. Direct TypeSafe
//                        boolean-style `noul` questions are normalized to the
//                        Vercel evaluation protocol's supported `boolean` type.
//   gateway            — Cloudflare AI Gateway or compatible gateway,
//                        JEV_GATEWAY_URL + JEV_GATEWAY_API_KEY + JEV_MODEL.
//                        The endpoint must expose a Jev/evaluation request
//                        contract compatible with the System One payload.
//   openrouter         — preview only; no verified System One-compatible
//                        transport exists yet.
//
// Usage:
//   node --experimental-strip-types scripts/qa/ask-jev.ts \
//     --state state.json [--questions questions.json] \
//     [--dims functional,view,business] [--model jev-latest]
//
// State shape: { test_goal, expected, governance, page, trace }.
// Prints the raw evaluation response JSON to stdout.

import { readFileSync } from "node:fs";

interface Args {
  state: string;
  questions?: string;
  dims: string;
  model: string;
}

function parseArgs(argv: string[]): Args {
  const out: Args = { state: "", dims: "functional,view,business", model: process.env.JEV_MODEL ?? "jev-latest" };
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

const BUSINESS_QUESTIONS = [
  "business_rule_respected",
  "forbidden_side_effects_avoided",
  "state_transition_valid",
  "traceability_present",
];

function defaultCriteria(name: string): unknown {
  // Mirrors questions.ts so --questions can be omitted for the standard library.
  const functional = ["task_completed", "action_had_visible_effect", "error_blocked_task", "persisted_after_reload"];
  const view = ["one_primary_action", "impact_before_confirm", "copy_plain_and_actionable", "status_explains_next_step"];
  if (functional.includes(name) || view.includes(name) || BUSINESS_QUESTIONS.includes(name)) return undefined;
  if (name === "verdict")
    return {
      pass: "Goal achieved, no governance violation, no blocking error.",
      blocking: "Correctness, permission, data-integrity, or governance violation.",
      nit: "Polish or subjective improvement only.",
      unverified: "Cannot be decided from the supplied state and trace.",
    };
  if (name === "domain")
    return { functional: "Action success and errors.", view: "Copy and guidance.", business_logic: "Business rules, side effects, state transitions, traceability." };
  if (name === "severity")
    return ["Cosmetic polish.", "Confusing but completable.", "Blocks the task or risks correctness, permissions, data integrity, or required auditability."];
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
    business_rule_respected: "Does the observed behavior comply with the explicit business constraints in governance and the expected result for `test_goal`?",
    forbidden_side_effects_avoided: "Does `trace` avoid side effects outside the allowed scope for `test_goal`?",
    state_transition_valid: "Does the observed state transition follow the allowed workflow and invariants for `test_goal`?",
    traceability_present: "For sensitive or auditable actions, does `trace` preserve the actor, action, timestamp, reason, and relevant object identifiers required by the project's governance?",
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
    business: BUSINESS_QUESTIONS,
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

interface ResolvedProvider {
  endpoint: string;
  apiKey: string;
  model: string;
  normalizeForVercel: boolean;
}

function resolveProvider(model: string): ResolvedProvider {
  const provider = (process.env.JEV_PROVIDER ?? "typesafe").trim().toLowerCase();
  if (provider === "openrouter") {
    console.error(
      "OpenRouter exposes Jev, but Agent Stack does not yet have a verified\n" +
      "System One-compatible transport for this route.\n\n" +
      "Choose TypeSafe direct, Vercel AI Gateway, or a compatible gateway:\n\n" +
      "  astack auth jev"
    );
    process.exit(2);
  }
  if (provider === "vercel") {
    const apiKey = process.env.AI_GATEWAY_API_KEY ?? "";
    if (!apiKey) {
      console.error("AI_GATEWAY_API_KEY is not set. Run:\n\n  astack auth jev");
      process.exit(2);
    }
    return {
      endpoint: process.env.JEV_GATEWAY_URL || "https://ai-gateway.vercel.sh/v1/systemone",
      apiKey,
      model: process.env.JEV_MODEL || (model === "jev-latest" ? "typesafe-ai/jev-latest" : model),
      normalizeForVercel: true,
    };
  }
  if (provider === "gateway") {
    const endpoint = process.env.JEV_GATEWAY_URL ?? "";
    const apiKey = process.env.JEV_GATEWAY_API_KEY ?? "";
    if (!endpoint || !apiKey) {
      console.error("JEV_GATEWAY_URL and JEV_GATEWAY_API_KEY must both be set. Run:\n\n  astack auth jev");
      process.exit(2);
    }
    return { endpoint, apiKey, model: process.env.JEV_MODEL || model, normalizeForVercel: false };
  }
  const apiKey = process.env.TYPESAFE_API_KEY ?? "";
  if (!apiKey) {
    console.error("Jev is not configured.\n\nRun:\n\n  astack auth jev");
    process.exit(2);
  }
  return {
    endpoint: process.env.JEV_GATEWAY_URL || "https://api.typesafe.ai/v1/systemone",
    apiKey,
    model: process.env.JEV_MODEL || model,
    normalizeForVercel: false,
  };
}

function normalizeQuestionsForVercel(questions: Record<string, object>): Record<string, object> {
  // The Vercel evaluation protocol supports a `boolean` question type where
  // TypeSafe direct uses boolean-style `noul` questions.
  const out: Record<string, object> = {};
  for (const [name, q] of Object.entries(questions)) {
    const question = q as Record<string, unknown>;
    if (question["type"] === "noul") {
      out[name] = { ...question, type: "boolean" };
    } else {
      out[name] = question;
    }
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
  const provider = resolveProvider(args.model);
  const state = JSON.parse(readFileSync(args.state, "utf8"));
  let questions: Record<string, object> = args.questions
    ? JSON.parse(readFileSync(args.questions, "utf8"))
    : buildDefaultQuestions(args.dims);
  if (provider.normalizeForVercel) {
    questions = normalizeQuestionsForVercel(questions);
  }

  const res = await postWithRetry(provider.endpoint, {
    method: "POST",
    headers: { Authorization: `Bearer ${provider.apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ state, model: provider.model, questions }),
  });
  const text = await res.text();
  if (!res.ok) {
    console.error(`jev error ${res.status}: ${text}`);
    process.exit(1);
  }
  console.log(text);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
