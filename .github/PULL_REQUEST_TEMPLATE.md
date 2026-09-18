# Pull request

## Summary

<!-- What changes, and why. -->

## Verification

<!-- Commands run and their results. -->

- [ ] `sh tests/run.sh`
- [ ] `python3 scripts/build-installer.sh --kit-root "$PWD" --check`
- [ ] `astack doctor` on a scratch project (paste any failures)

## Checklist

- [ ] Neutral sources edited under `.agent-stack/` (no hand-edits to `setup.sh`)
- [ ] No credentials, local paths, or project-specific names added
- [ ] Docs updated (`README.md` / `docs/` / `CHANGELOG.md` as needed)
- [ ] Public CLI help uses `astack`, not `agent-stack`
