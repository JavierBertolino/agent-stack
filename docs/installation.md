# Installation

## One-line install

```sh
curl -fsSL https://github.com/JavierBertolino/agent-stack/releases/latest/download/install.sh | sh
```

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

`agent-stack` remains as an unadvertised backwards-compatibility alias;
all documentation uses `astack`.
