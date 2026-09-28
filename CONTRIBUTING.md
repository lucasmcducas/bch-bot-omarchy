# Contributing to BCH Wallet Omarchy Plugin

This plugin is built collaboratively by BCH community members. See [COLLABORATION.md](COLLABORATION.md) for the full model.

## Quick start

```bash
# 1. Fork the repo on GitHub (click "Fork" on the upstream repo page)

# 2. Clone your fork
git clone https://github.com/<your-handle>/bch-bot-omarchy.git
cd bch-bot-omarchy
git remote add upstream https://github.com/lucasmcducas/bch-bot-omarchy.git
git fetch upstream
git checkout -b collaborate/v0.1 upstream/collaborate/v0.1
git checkout -b feature/<issue-number>-<short-name>

# 3. Read the docs your LLM needs
#    Point your LLM at:
#      - COLLABORATION.md (the model)
#      - https://github.com/lucasmcducas/bch-wiki-public/blob/main/entities/omarchy-plugin-marketplace.md
#      - SECURITY.md (the marketplace baseline)
#      - https://github.com/lucasmcducas/bch-wiki-public (the full wiki)

# 4. Make the change
#    - QML goes in the repo root
#    - The plugin ID is "io.github.lucasmcducas.bch-wallet" — do not change
#    - Keep changes scoped to one issue per PR

# 5. Run the audit before committing
./audit-public.sh   # must pass

# 6. Commit + push + open PR
git add -A
git commit -m "fix(#1): wire bch-bot balance into bar widget via Quickshell.Io"
git push origin feature/1-balance-display
gh pr create \
  --repo lucasmcducas/bch-bot-omarchy \
  --base collaborate/v0.1 \
  --head <your-handle>:feature/1-balance-display \
  --title "[Plugin]: wire bch-bot balance into bar widget" \
  --body "Closes #1\n\n## What\n\n... \n\n## How tested\n\n..."
```

## PR requirements

Every PR must:

1. **Pass `audit-public.sh`** — no treasury addresses, no mainnet wallet paths, no specific dollar figures.
2. **Reference an issue** — open or closed. PRs without a linked issue get rejected.
3. **Have a clear title** — `[Plugin]: <one-line summary>` (matches the issue template).
4. **Have tested the change** — either with `npm test` (if JS changes) or by running in Omarchy 4.0 with a screenshot.
5. **Not introduce marketplace-security-baseline violations** — see SECURITY.md.
6. **Not change the plugin ID or namespace** — the public plugin ID is `io.github.lucasmcducas.bch-wallet` and stays that way. Different IDs require a new repo.

## What NOT to do

- **Do not commit wallet files.** The plugin has no wallet. The `bch-bot` repo has the wallet code (separate repo).
- **Do not commit your `wallet.json`.** It's encrypted but still your keys.
- **Do not introduce npm dependencies with caret ranges.** Exact pins only.
- **Do not introduce bundled binaries.** The marketplace security baseline blocks this.
- **Do not introduce curl-pipe-shell patterns.** Same reason.

## Architecture

- `manifest.json` — schemaVersion 1, namespaced id, kinds, entryPoints, optional kind-specific config block.
- `BchBalanceWidget.qml` — bar widget root.
- `BchCommand.qml` — IPC command root.
- `README.md` — install + remove instructions, security disclosure.
- `SECURITY.md` — addresses each marketplace baseline pattern.
- `LICENSE` — MIT.
- `audit-public.sh` — pre-commit gate.
- `COLLABORATION.md` — the team plan.

## Style

- QML: follow existing patterns in `BchBalanceWidget.qml` and `BchCommand.qml`.
- Comments: explain *why* in 1-3 lines, not what.
- Indent: 2 spaces (matches Omarchy convention).
- Commit messages: imperative present tense ("fix", not "fixed").

## Review SLA

PRs are reviewed by maintainers within ~3 days. The first wave of community PRs (issues #1-#5) is the priority.

## License

By contributing, you agree that your contributions are MIT-licensed.
