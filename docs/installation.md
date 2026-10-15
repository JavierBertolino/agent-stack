# Installation

## npm

Node.js 18 or newer:

```sh
npx agent-stack init
npm install -g agent-stack
```

`npx agent-stack init` asks for coding agents and integrations, then the shell renderer writes the project files. See [Node CLI](node-cli.md) for what is still in shell.

## One-line install

```sh
curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh
```

The curl installer checks for Node.js 18, downloads the release archive, and installs `astack`. If Node.js is missing, it stops and tells you how to install it.

The installer:

1. Detects the OS and architecture.
2. Downloads the latest versioned GitHub Release artifact (never `main`).
3. Verifies the SHA-256 checksum (aborts on mismatch).
4. Installs Agent Stack versioned under `~/.local/share/astack`.
5. Installs the `astack` executable into `~/.local/bin`.
6. Prints concise next steps.

No GitHub authentication is required. To pin a version:

```sh
curl -fsSL .../install.sh | ASTACK_VERSION=0.1.0 sh
```

To install elsewhere:

```sh
curl -fsSL .../install.sh | sh -s -- --prefix=/opt
```

## Versioned layout

```text
~/.local/
├── bin/
│   └── astack                # the real executable
└── share/
    └── astack/
        ├── current -> versions/0.1.0
        └── versions/
            └── 0.1.0/
```

`astack` resolves the kit through the `current` symlink. An update
installs the new version beside the old one, sanity-checks it, then
switches `current`, leaving the previous version available for rollback.

## Next steps

```sh
cd my-project
astack init
astack doctor
```

`astack uninstall` removes generated files. It asks first, or accepts
`--yes`. Project guides (`UX_AGENTS.md`, `UI_AGENTS.md`) stay.

`agent-stack` remains as an unadvertised backwards-compatibility alias;
all documentation uses `astack`.
