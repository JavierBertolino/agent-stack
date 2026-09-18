# Updating

`update` and `upgrade` mean different things.

## `astack update` — the installed CLI and kit

```sh
astack update
astack update --check
```

`--check` prints whether a newer release exists without changing
anything. A real update downloads the new release, verifies checksums,
installs into a new version directory, sanity-checks it, and switches
`current`, leaving the previous version available. It never touches the
current project — if the project was initialized with an older version,
the output says so and points at `astack upgrade`.

## `astack upgrade` — the current project

```sh
astack upgrade
astack upgrade --check
```

Upgrades the current project's managed files to the already installed
kit via three-way merge: unchanged managed sources update cleanly,
customizations survive with visible `.kit-new` files, and project
`config.conf` is never modified. The project records the kit version it
was initialized with (`.agent-stack/.kit-version`), so the upgrade can
report `old → new`.

After upgrading, re-rendered platform mirrors are synchronized
automatically.
