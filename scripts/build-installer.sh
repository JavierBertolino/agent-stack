#!/usr/bin/env python3
"""build-installer.sh — build the standalone distribution reproducibly.

Author neutral sources once (.agent-stack/roles, .agent-stack/skills,
.agent-stack/defaults.conf); this script regenerates the embedded fallback
data inside scripts/setup-agent-stack.sh from those sources and derives the
standalone setup.sh through a one-line transform (KIT_ROOT points at the
distribution directory itself instead of the parent).

Usage:
  scripts/build-installer.sh [--kit-root PATH] [--check]

  --check exits 1 when the generated output would differ from what is
  committed (used by CI to enforce reproducibility).

Installer logic lives only in scripts/setup-agent-stack.sh. setup.sh is
pure generated output plus the KIT_ROOT transform; never edit it by hand.
"""

import argparse
import difflib
import subprocess
import sys
from pathlib import Path

KIT_LINE_FROM = 'KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)'
KIT_LINE_TO = 'KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR" && pwd)'

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
    standalone = kit / "setup.sh"

    text = main_script.read_text()
    text = sync_roles(text, kit)
    text = sync_skills(text, kit)
    text = sync_defaults(text, kit)

    if KIT_LINE_FROM not in text:
        raise SystemExit("build error: KIT_ROOT source line not found")
    standalone_text = text.replace(KIT_LINE_FROM, KIT_LINE_TO, 1)

    changed = []
    if main_script.read_text() != text:
        changed.append(str(main_script))
        if not args.check:
            main_script.write_text(text)
    if standalone.read_text() != standalone_text:
        changed.append(str(standalone))
        if not args.check:
            standalone.write_text(standalone_text)

    if not args.check:
        check_syntax(main_script)
        check_syntax(standalone)

    if changed:
        print("build-installer: updated %s" % ", ".join(changed))
        if args.check:
            for path in changed:
                old = (main_script.read_text() if "setup-agent-stack" in path
                       else standalone.read_text()).splitlines()
                new = (text if "setup-agent-stack" in path
                       else standalone_text).splitlines()
                sys.stdout.write("".join(difflib.unified_diff(
                    old, new, path, path, lineterm="")))
            sys.exit(1)
    else:
        print("build-installer: outputs are reproducible (no changes)")


if __name__ == "__main__":
    main()
