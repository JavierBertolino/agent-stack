# Security Policy

## Supported versions

Only the latest GitHub Release is supported. Update with:

```sh
astack update
```

## Reporting a vulnerability

Open a GitHub Security Advisory for this repository, or open an issue
without exploit details and request a private contact. Do not publish
proof-of-concept exploits in public issues.

We aim to acknowledge reports within 3 business days and ship a fix or
mitigation as a new release.

## Scope notes

- Agent Stack never writes credentials into repositories. Jev keys live
  user-level (`~/.config/astack/env`, mode 600) and are never printed,
  logged, or committed.
- If you suspect a credential leaked into a project file or Git history,
  rotate it immediately — removing it from `main` is not enough while it
  remains in history.
