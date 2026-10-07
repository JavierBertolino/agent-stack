// Stdin/stdout adapter for the shared action-selection gate. This validates
// Jev's recommendation but never invokes an MCP tool or performs an action.
import { readFileSync } from "node:fs";
import { validateActionSelection, type ActionCandidate } from "./action-selection.ts";

const MAX_INPUT_BYTES = 5 * 1024 * 1024;

function main(): void {
  const text = readFileSync(0, "utf8");
  if (Buffer.byteLength(text, "utf8") > MAX_INPUT_BYTES) {
    throw new Error("selection validation input exceeds 5 MiB");
  }
  const input = JSON.parse(text) as Record<string, unknown>;
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("input must be a JSON object");
  }
  if ("confidence_threshold" in input) {
    throw new Error("action confidence threshold is fixed at 0.75");
  }
  const decision = validateActionSelection({
    response: input.response,
    questionId: typeof input.question_id === "string" ? input.question_id : "next_action",
    candidates: input.candidates as ActionCandidate[],
    submittedObservation: input.submitted_observation,
    currentObservation: input.current_observation,
  });
  console.log(JSON.stringify(decision));
  if (decision.status === "reject" || decision.status === "reinspect") process.exitCode = 2;
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : "invalid selection input");
  process.exitCode = 2;
}
