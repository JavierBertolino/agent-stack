# mobile-qa resources

Companion scripts for the standalone `mobile-qa` agent (Maestro MCP +
device/emulator). Copied to the consuming project as `scripts/mobile-qa/`
by `setup-agent-stack.sh` (`init`/`sync` create missing files only).

- `questions-mobile.ts` — typed atomic question library (functional / view /
  business + verdict/domain/severity) for use with the shared Jev caller at
  `scripts/qa/ask-jev.ts`. Pass `--questions` with a JSON file rendered from
  `buildMobileQuestions()`, or inline the state below.

State shape for the shared caller:

```json
{
  "test_goal": "Cerrar una tarea desde la lista",
  "expected": "La tarea pasa a cerrada con confirmación visible",
  "governance": { "P02": "...", "P05": "...", "copy_rule": "..." },
  "screen": {
    "hierarchy_truncated": "<inspect_screen compact JSON>",
    "visible_copy": "text on screen",
    "focused_element": "resource-id or label",
    "console_or_flow_errors": "maestro run output tail"
  },
  "trace": [{ "action": "tap Cerrar", "observed": "dialog Confirmar" }],
  "device": { "serial": "...", "model": "...", "os": "...", "build": "..." }
}
```

Device execution itself goes through the Maestro MCP tools (`list_devices`,
`inspect_screen`, `run`, `take_screenshot`); no local runner script is
needed. Requires Maestro CLI + Java on PATH and a booted emulator or
connected device with the target app installed.
