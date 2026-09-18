#!/usr/bin/env python3
"""validate-contracts.py — validate JSON documents against Agent Stack contracts.

Usage:
  validate-contracts.py --kit-root PATH --type handoff|report|run-state|event <file>...

For run-state, pass the run's state.json; events.jsonl is validated with
--type event. Exits 0 when every file validates, 1 otherwise.

The validator implements the JSON-Schema subset used by the contracts:
type (including type lists), required, properties, items, enum, const,
minLength, minItems, minimum.
"""

import argparse
import json
import os
import sys

import importlib.util

_helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run-state.py")
_spec = importlib.util.spec_from_file_location("run_state_helper", _helper)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
_check = _mod._check


TYPES = {
    "handoff": "handoff.schema.json",
    "report": "report.schema.json",
    "run-state": "run-state.schema.json",
    "event": "event.schema.json",
}


def main():
    parser = argparse.ArgumentParser(description="Validate Agent Stack contract JSON")
    parser.add_argument("--kit-root", required=True)
    parser.add_argument("--type", required=True, choices=sorted(TYPES))
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()

    schema_path = os.path.join(args.kit_root, ".agent-stack", "contracts",
                               TYPES[args.type])
    with open(schema_path) as fh:
        schema = json.load(fh)

    failures = 0
    for path in args.files:
        errors = []
        if path.endswith(".jsonl"):
            with open(path) as fh:
                for lineno, line in enumerate(fh, 1):
                    line = line.strip()
                    if line:
                        try:
                            errors += _check(schema, json.loads(line),
                                             "%s:%d" % (path, lineno))
                        except json.JSONDecodeError as exc:
                            errors.append("%s:%d: invalid JSON (%s)" % (path, lineno, exc))
        else:
            with open(path) as fh:
                try:
                    errors += _check(schema, json.load(fh), path)
                except json.JSONDecodeError as exc:
                    errors.append("%s: invalid JSON (%s)" % (path, exc))
        if errors:
            failures += 1
            print("FAIL %s" % path)
            for error in errors:
                print("  %s" % error)
        else:
            print("ok %s" % path)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
