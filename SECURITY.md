# Security Notes

This document addresses the Omarchy Plugin Marketplace **Automated Security Baseline** (`github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md`) for the BCH Wallet plugin.

The marketplace baseline is a **deterministic, snapshot-based, narrow check** that reads selected files from the exact commit SHA. It identifies specific static patterns. It does not run plugin code.

## What the baseline catches (and how this plugin avoids each)

### `curl-pipe-shell` — `curl`/`wget` piped to a shell

**Mitigation:** This plugin does not download or execute code from the network. All wallet logic is in the `bch-bot` CLI, which uses pinned npm dependencies (`package-lock.json` committed) and does not perform `curl | sh` patterns. Search the repo for `curl`, `wget`, `| sh`, `| bash` — none present.

### `cargo-git-unpinned` — `cargo install --git` without a 40-char `--rev`

**Not applicable.** This plugin contains no Rust code.

### `remote-git-execution-unpinned` — code from an external git repo executed without a pinned commit

**Mitigation:** The plugin depends on the `bch-bot` CLI, which is invoked as a local binary. The CLI itself depends on npm packages with exact pins (no caret ranges). The plugin does not `git clone` external repos at runtime.

### `passwordless-sudoers` — dangerous `NOPASSWD` sudoers

**Not applicable.** This plugin runs as the invoking user. It does not touch `/etc/sudoers.d/` or any privileged configuration.

### `bundled-executable-binary` — ELF/PE/Mach-O binaries in the plugin tree

**Mitigation:** This plugin contains only QML, JSON, and Markdown files. No compiled binaries. The plugin relies on the user's separately-installed `bch-bot` CLI binary, which is not part of this repo.

### `dangerous-tmp-shared-state` — privileged process control via predictable shared `/tmp` paths

**Not applicable.** This plugin does not spawn privileged processes. All IPC is via Quickshell's `IpcHandler` and shell `Process` calls into the user-level `bch-bot` CLI.

## Privilege and capability disclosure

- **No root / sudo** — the plugin runs as the invoking user only.
- **No network access from QML** — QML calls the local `bch-bot` CLI; the CLI handles all network I/O.
- **No file modifications outside plugin scope** — the plugin does not modify `~/.config/omarchy/` outside its own settings schema (managed by the shell).
- **No write access to user documents** — only reads the wallet dir (`~/.bch-wallet/` by default, configurable via `BCH_WALLET_DIR`).

## Reporting security concerns

Please report suspected security issues via:
- **GitHub security advisory** at `github.com/lucasmcducas/bch-bot-omarchy/security/advisories/new` (private)
- Or via the upstream `bch-bot` repo at `github.com/lucasmcducas/bch-bot-public/security/advisories/new`
- Or via the Omarchy marketplace's private report form at `github.com/omacom/omarchy-plugin-marketplace/security/advisories/new`

Do not disclose suspected issues in public issues.

## Known limitations

- The plugin depends on the user having `bch-bot` installed. If the CLI is missing, the plugin's bar widget will show a red icon with install instructions. The plugin does not auto-install the CLI (this would require install scripts, which the marketplace security baseline discourages).
- The plugin has not yet been audited. The bch-bot core has been verified via 216+ unit tests including round-trip encryption tests.
