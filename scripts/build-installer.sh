#!/usr/bin/env python3
"""build-installer.sh — synchronize embedded installer fallback data.

Author neutral sources once under .agent-stack. This script refreshes the
embedded fallback roles, skills, and defaults inside scripts/setup-agent-stack.sh.

Usage:
  scripts/build-installer.sh [--kit-root PATH] [--check]

--check exits 1 when the embedded fallback data is stale.
"""

import argparse
import difflib
import subprocess
import sys
from pathlib import Path

SKILLS = ["project-context", "linear-workflow", "governance-bootstrap",
          "openspec-workflow", "ux-design", "implementation",
          "ui-review", "git-delivery"]

SKILL_MARKERS = {
    "project-context": "SKILL_PROJECT_CONTEXT_EOF",
    "linear-workflow": "SKILL_LINEAR_WORKFLOW_EOF",
    "governance-bootstrap": "SKILL_GOVERNANCE_BOOTSTRAP_EOF",
    "openspec-workflow": "SKILL_OPENSPEC_WORKFLOW_EOF",
    "ux-design": "SKILL_UX_DESIGN_EOF",
    "implementation": "SKILL_IMPLEMENTATION_EOF",
    "ui-review": "SKILL_UI_REVIEW_EOF",
    "git-delivery": "SKILL_GIT_DELIVERY_EOF",
}

ROLE_MARKERS = {
    "resolver": "ROLE_RESOLVER_EOF",
    "designer": "ROLE_DESIGNER_EOF",
    "design-qa": "ROLE_DESIGN_QA_EOF",
    "developer": "ROLE_DEVELOPER_EOF",
    "web-qa": "ROLE_WEB_QA_EOF",
    "mobile-qa": "ROLE_MOBILE_QA_EOF",
}

ROLE_STARTS = {
    "resolver": "    resolver) cat > \"$target\" <<'ROLE_RESOLVER_EOF'\n",
    "designer": "    designer) cat > \"$target\" <<'ROLE_DESIGNER_EOF'\n",
    "design-qa": "    design-qa) cat > \"$target\" <<'ROLE_DESIGN_QA_EOF'\n",
    "developer": "    developer) cat > \"$target\" <<'ROLE_DEVELOPER_EOF'\n",
    "web-qa": "    web-qa) cat > \"$target\" <<'ROLE_WEB_QA_EOF'\n",
    "mobile-qa": "    mobile-qa) cat > \"$target\" <<'ROLE_MOBILE_QA_EOF'\n",
}


def replace_body(text, start_pat, end_marker, body):
    start = text.find(start_pat)
    if start == -1:
        raise SystemExit("build error: block start not found: %r" % start_pat)
    body_start = start + len(start_pat)
    end = text.find(end_marker, body_start)
    if end == -1:
        raise SystemExit("build error: block end not found: %r" % end_marker)
    return text[:body_start] + body + text[end:]


def sync_roles(text, kit):
    for role, marker in ROLE_MARKERS.items():
        body = (kit / ".agent-stack" / "roles" / (role + ".md")).read_text()
        if not body.endswith("\n"):
            body += "\n"
        text = replace_body(text, ROLE_STARTS[role], marker, body)
    return text


def sync_skills(text, kit):
    for skill in SKILLS:
        marker = SKILL_MARKERS[skill]
        start_pat = "    %s) cat > \"$target\" <<'%s'\n" % (skill, marker)
        body = (kit / ".agent-stack" / "skills" / skill / "SKILL.md").read_text()
        if not body.endswith("\n"):
            body += "\n"
        text = replace_body(text, start_pat, marker, body)
    manifest = (kit / ".agent-stack" / "skills" / "manifest.json").read_text()
    if not manifest.endswith("\n"):
        manifest += "\n"
    text = replace_body(text, "cat > \"$1\" <<'SKILLS_MANIFEST_EOF'\n",
                          "SKILLS_MANIFEST_EOF", manifest)
    return text


def sync_defaults(text, kit):
    defaults = (kit / ".agent-stack" / "defaults.conf").read_text()
    if not defaults.endswith("\n"):
        defaults += "\n"
    return replace_body(text, "cat > \"$1\" <<'DEFAULTS_EOF'\n", "DEFAULTS_EOF", defaults)


def check_syntax(path):
    result = subprocess.run(["sh", "-n", str(path)], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("build error: syntax check failed for %s:\n%s"
                         % (path, result.stderr))


def main():
    parser = argparse.ArgumentParser(description="Build the standalone installer")
    parser.add_argument("--kit-root", default=".")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    kit = Path(args.kit_root)
    main_script = kit / "scripts" / "setup-agent-stack.sh"

    original = main_script.read_text()
    text = sync_roles(original, kit)
    text = sync_skills(text, kit)
    text = sync_defaults(text, kit)

    if original != text:
        if args.check:
            sys.stdout.write("".join(difflib.unified_diff(
                original.splitlines(),
                text.splitlines(),
                str(main_script),
                str(main_script),
                lineterm="",
            )))
            sys.exit(1)
        main_script.write_text(text)
        check_syntax(main_script)
        print("build-installer: synchronized embedded fallback data")
    else:
        print("build-installer: embedded fallback data is synchronized")


if __name__ == "__main__":
    main()
