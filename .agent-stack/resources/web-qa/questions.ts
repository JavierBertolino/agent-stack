// Shared Jev question library for the standalone web-qa agent.
// Atomic, single-judgment questions composed in code. Add dimensions here,
// never broad "is the UX good?" questions.

export type Dim = "functional" | "view" | "business";

export interface QuestionDef {
  type: "noul" | "choice" | "score";
  instructions: string;
  criteria?: unknown;
}

export const DIMENSIONS: Dim[] = ["functional", "view", "business"];

export function buildQuestions(dims: Dim[] = DIMENSIONS): Record<string, QuestionDef> {
  const q: Record<string, QuestionDef> = {};
  const want = (d: Dim) => dims.includes(d);

  if (want("functional")) {
    q.task_completed = {
      type: "noul",
      instructions:
        "Does `page.visible_copy` and `trace` show the goal in `test_goal` completed with a visible success state?",
    };
    q.action_had_visible_effect = {
      type: "noul",
      instructions:
        "Did the last action in `trace` produce the expected visible change described in `expected`?",
    };
    q.error_blocked_task = {
      type: "noul",
      instructions:
        "Does `page.console_errors` or `page.visible_copy` show an error that blocks `test_goal`?",
    };
    q.persisted_after_reload = {
      type: "noul",
      instructions:
        "Does `trace` show the result of `test_goal` surviving a reload or re-query?",
      criteria: {
        true: "Evidence of persistence is present in the trace.",
        false: "No persistence evidence, or persistence was not checked.",
      },
    };
  }

  if (want("view")) {
    q.one_primary_action = {
      type: "noul",
      instructions:
        "Does `page` present one primary action for `test_goal` per `governance.P02`?",
    };
    q.impact_before_confirm = {
      type: "noul",
      instructions:
        "Before any sensitive confirmation, does `page.visible_copy` show object, change, amount/currency, affected party, and recovery path per `governance.P05`?",
    };
    q.copy_plain_and_actionable = {
      type: "noul",
      instructions:
        "Is `page.visible_copy` plain everyday language that describes the result of the action, with no unexplained technical jargon, per `governance.copy_rule`?",
    };
    q.status_explains_next_step = {
      type: "noul",
      instructions:
        "Does the status shown in `page.visible_copy` explain the situation and the next step, not just a badge or color, per `governance.P04`?",
    };
  }

  if (want("business")) {
    q.business_rule_respected = {
      type: "noul",
      instructions:
        "Does `trace` comply with the explicit business constraints in `governance` and the expected outcome for `test_goal`?",
    };
    q.forbidden_side_effects_avoided = {
      type: "noul",
      instructions:
        "Does `trace` avoid side effects that are forbidden or outside the scope described by `governance` and `expected`?",
    };
    q.state_transition_valid = {
      type: "noul",
      instructions:
        "Does the observed state transition match the allowed workflow and invariants described by `governance`?",
    };
    q.traceability_present = {
      type: "noul",
      instructions:
        "When the action is auditable or sensitive, does `trace` preserve the actor, action, timestamp, reason, and relevant object identifiers required by `governance`?",
    };
  }

  q.verdict = {
    type: "choice",
    instructions: "Which QA outcome best fits `page` and `trace` for `test_goal`?",
    criteria: {
      pass: "Goal achieved, no governance violation, no blocking error.",
      blocking: "Correctness, money, permission, or governance violation.",
      nit: "Polish or subjective improvement only.",
      unverified: "Cannot be decided from the supplied state and trace.",
    },
  };
  q.domain = {
    type: "choice",
    instructions: "Which dimension owns the primary finding for `test_goal`?",
    criteria: {
      functional: "Navigation, action success, errors, persistence.",
      view: "Copy, layout, status, guidance, accessibility signals.",
      business_logic: "Explicit business rules, valid state transitions, side effects, and traceability.",
    },
  };
  q.severity = {
    type: "score",
    instructions: "How severe is the primary finding for `test_goal`?",
    criteria: ["Cosmetic polish.", "Confusing but completable.", "Blocks the task or risks correctness, permissions, data integrity, or required auditability."],
  };

  return q;
}
