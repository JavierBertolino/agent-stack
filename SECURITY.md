# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.

Use GitHub's private security advisory flow for this repository.

Include enough information to reproduce the issue and describe the potential impact.

## Scope

Security-sensitive areas include:

- the public bootstrap installer;
- `astack update` and release verification;
- credential handling for Jev providers;
- generated MCP configuration;
- shell command construction;
- files written outside the target project;
- any behavior that could overwrite human-owned project files.

Agent Stack must never commit, print, or persist provider credentials inside a consuming repository.
