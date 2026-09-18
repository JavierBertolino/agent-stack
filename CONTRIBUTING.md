# Contributing to Agent Stack

Thanks for contributing.

## Development setup

Agent Stack is intentionally lightweight. The core installer is POSIX `sh`; validation helpers use Python standard library; Jev QA helpers use Node.js.

Run the full test suite before opening a pull request:

```sh
sh tests/run.sh
python3 scripts/build-installer.sh --kit-root "$PWD" --check
```

## Source of truth

Author canonical roles, skills, contracts, defaults, and resources under `.agent-stack/`.

`setup.sh` is generated. Do not edit it manually:

```sh
python3 scripts/build-installer.sh --kit-root "$PWD"
```

## Pull requests

Keep changes scoped and explain:

- the user-facing behavior that changes;
- which platforms or integrations are affected;
- how the change was verified;
- whether generated installer output changed.

Avoid introducing project-specific business rules, private repository names, local filesystem paths, credentials, or organization-specific assumptions into the core kit.

## Releases

Agent Stack uses semantic versioning. Maintainers update `AGENT_STACK_VERSION`, merge the release changes, then push the matching `vX.Y.Z` tag. GitHub Actions tests and publishes the release artifacts.
