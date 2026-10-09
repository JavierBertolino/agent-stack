// Shared, host-neutral candidate construction and fail-closed Jev decision
// validation for web-qa and mobile-qa. Jev recommends; this module never
// executes browser or device actions.

export const INSPECT_MORE = "inspect_more";
export const STOP = "stop";
export const ACTION_SELECTION_CONFIDENCE_THRESHOLD = 0.75;
export const MAX_ACTION_CANDIDATES = 15;

export interface ActionCandidate {
  id: string;
  description: string;
  effects: string;
  /** The agent's local authorization check; never inferred from Jev. */
  authorized: boolean;
  /** JSON Pointer -> exact value observed when the candidate was built. */
  preconditions: Record<string, unknown>;
}

export interface ActionSelectionQuestion {
  type: "choice";
  instructions: string;
  criteria: Record<string, string>;
}

export type ActionSelectionDecision =
  | { status: "execute"; candidateId: string; confidence: number }
  | { status: "inspect_more"; confidence?: number; reason: string }
  | { status: "stop"; candidateId: string; confidence: number }
  | { status: "reinspect"; reason: string }
  | { status: "reject"; reason: string };

const CANDIDATE_ID = /^[a-z][a-z0-9_]{0,39}$/;

/**
 * Build the bounded Choice sent to Jev. Preconditions and authorization are
 * retained only in the agent's local candidate records; Jev sees descriptions
 * and effects, not executable parameters or permissions.
 */
export function buildActionSelectionQuestion(
  candidates: ActionCandidate[],
  surface: "page" | "screen",
): ActionSelectionQuestion {
  const error = validateCandidateSet(candidates);
  if (error) throw new Error(error);

  const criteria: ActionSelectionQuestion["criteria"] = Object.create(null);
  for (const candidate of candidates) {
    criteria[candidate.id] = `${candidate.description} Possible effects: ${candidate.effects}`;
  }

  return {
    type: "choice",
    instructions:
      `Which single candidate best advances \`test_goal\` toward \`expected\` given the observed ${surface}, with the least unnecessary work? ` +
      "Choose `inspect_more` if evidence is insufficient. Choose `stop` only when the goal is met, blocked, or the test budget is exhausted. A recommendation is not authorization.",
    criteria,
  };
}

/**
 * Validate a raw System One response against the exact current candidate set
 * and observations. A non-executable status is always fail-closed.
 */
export function validateActionSelection(input: {
  response: unknown;
  questionId?: string;
  candidates: ActionCandidate[];
  submittedObservation: unknown;
  currentObservation: unknown;
}): ActionSelectionDecision {
  const candidatesError = validateCandidateSet(input.candidates);
  if (candidatesError) return { status: "reject", reason: candidatesError };

  if (!sameJson(input.submittedObservation, input.currentObservation)) {
    return { status: "reinspect", reason: "observation changed after Jev was asked" };
  }

  const response = asRecord(input.response);
  const answers = asRecord(response?.answers);
  const answer = asRecord(answers?.[input.questionId ?? "next_action"]);
  if (!answer || answer.type !== "choice") {
    return { status: "reject", reason: "missing or invalid Choice answer" };
  }

  const candidateIds = input.candidates.map((candidate) => candidate.id);
  const probabilities = asRecord(answer.probabilities);
  if (!probabilities || !sameStringSet(Object.keys(probabilities), candidateIds)) {
    return { status: "reject", reason: "Choice probabilities do not match the current candidate set" };
  }
  let probabilityTotal = 0;
  for (const value of Object.values(probabilities)) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
      return { status: "reject", reason: "Choice probabilities contain an invalid value" };
    }
    probabilityTotal += value;
  }
  if (Math.abs(probabilityTotal - 1) > 0.01) {
    return { status: "reject", reason: "Choice probabilities do not sum to 1" };
  }

  if (typeof answer.choice !== "string") {
    return { status: "reject", reason: "Choice answer has no selected candidate id" };
  }
  const candidate = input.candidates.find((item) => item.id === answer.choice);
  if (!candidate) {
    return { status: "reject", reason: "selected id is not in the current candidate set" };
  }
  if (typeof answer.confidence !== "number" || !Number.isFinite(answer.confidence) ||
      answer.confidence < 0 || answer.confidence > 1) {
    return { status: "reject", reason: "Choice answer has invalid confidence" };
  }
  if (answer.confidence < ACTION_SELECTION_CONFIDENCE_THRESHOLD) {
    return { status: "inspect_more", confidence: answer.confidence, reason: "low-confidence recommendation" };
  }

  if (candidate.id === INSPECT_MORE) {
    return { status: "inspect_more", confidence: answer.confidence, reason: "Jev selected inspect_more" };
  }

  if (candidate.authorized !== true) {
    return { status: "reject", reason: "selected candidate is not authorized" };
  }
  const preconditionError = validatePreconditions(candidate.preconditions, input.currentObservation);
  if (preconditionError) return { status: "reinspect", reason: preconditionError };

  if (candidate.id === STOP) {
    return { status: "stop", candidateId: candidate.id, confidence: answer.confidence };
  }
  return { status: "execute", candidateId: candidate.id, confidence: answer.confidence };
}

function validateCandidateSet(candidates: unknown): string | undefined {
  if (!Array.isArray(candidates) || candidates.length < 2 || candidates.length > MAX_ACTION_CANDIDATES) {
    return `candidate set must contain 2 to ${MAX_ACTION_CANDIDATES} options`;
  }
  const ids = new Set<string>();
  for (const value of candidates) {
    const candidate = asRecord(value);
    if (!candidate || typeof candidate.id !== "string" || !CANDIDATE_ID.test(candidate.id)) {
      return "each candidate needs an opaque snake_case id";
    }
    if (ids.has(candidate.id)) return `duplicate candidate id: ${candidate.id}`;
    ids.add(candidate.id);
    if (typeof candidate.description !== "string" || !candidate.description.trim()) {
      return `candidate ${candidate.id} needs a description`;
    }
    if (typeof candidate.effects !== "string" || !candidate.effects.trim()) {
      return `candidate ${candidate.id} needs possible effects`;
    }
    if (typeof candidate.authorized !== "boolean") {
      return `candidate ${candidate.id} needs an explicit authorization result`;
    }
    if (candidate.id !== INSPECT_MORE && !isNonEmptyRecord(candidate.preconditions)) {
      return `candidate ${candidate.id} needs observable preconditions`;
    }
    if (candidate.authorized !== true) {
      return `unauthorized candidate must not be offered: ${candidate.id}`;
    }
    if (!isRecord(candidate.preconditions)) {
      return `candidate ${candidate.id} preconditions must be a JSON Pointer map`;
    }
    for (const pointer of Object.keys(candidate.preconditions)) {
      if (!parsePointer(pointer)) return `candidate ${candidate.id} has an invalid JSON Pointer: ${pointer}`;
    }
  }
  if (!ids.has(INSPECT_MORE)) return `candidate set must include ${INSPECT_MORE}`;
  return undefined;
}

function validatePreconditions(preconditions: Record<string, unknown>, observation: unknown): string | undefined {
  for (const [pointer, expected] of Object.entries(preconditions)) {
    const actual = readPointer(observation, pointer);
    if (!actual.found || !sameJson(actual.value, expected)) {
      return `precondition no longer matches observed state: ${pointer}`;
    }
  }
  return undefined;
}

function readPointer(value: unknown, pointer: string): { found: boolean; value?: unknown } {
  const parts = parsePointer(pointer);
  if (!parts) return { found: false };
  let current: unknown = value;
  for (const part of parts) {
    if (Array.isArray(current)) {
      if (!/^(0|[1-9][0-9]*)$/.test(part) || Number(part) >= current.length) return { found: false };
      current = current[Number(part)];
    } else if (isRecord(current) && Object.prototype.hasOwnProperty.call(current, part)) {
      current = current[part];
    } else {
      return { found: false };
    }
  }
  return { found: true, value: current };
}

function parsePointer(pointer: string): string[] | undefined {
  if (pointer === "") return [];
  if (!pointer.startsWith("/")) return undefined;
  const parts = pointer.slice(1).split("/");
  const decoded: string[] = [];
  for (const part of parts) {
    if (/~(?![01])/.test(part)) return undefined;
    decoded.push(part.replace(/~1/g, "/").replace(/~0/g, "~"));
  }
  return decoded;
}

function sameStringSet(left: string[], right: string[]): boolean {
  return left.length === right.length && new Set(left).size === left.length &&
    left.every((value) => right.includes(value));
}

function sameJson(left: unknown, right: unknown): boolean {
  try {
    return stableJson(left) === stableJson(right);
  } catch {
    return false;
  }
}

function stableJson(value: unknown): string {
  if (value === null || typeof value !== "object") {
    const encoded = JSON.stringify(value);
    if (encoded === undefined) throw new Error("not JSON");
    return encoded;
  }
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${stableJson(record[key])}`).join(",")}}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyRecord(value: unknown): value is Record<string, unknown> {
  return isRecord(value) && Object.keys(value).length > 0;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return isRecord(value) ? value : undefined;
}
