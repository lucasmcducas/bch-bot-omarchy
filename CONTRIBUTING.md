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

1. **Pass `audit-public.sh`** — no mainnet wallet paths, no specific dollar figures, no third-party destinations.
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
  Declares **`kinds: ["bar-widget"]` only**.
- `BchBalanceWidget.qml` — the entry point. A `BarWidget` that shows the balance in the
  bar *and hosts the wallet popup* in a `KeyboardPanel` child. No wallet logic, no keys,
  no signing in QML.
- `BchWalletPanel.qml` — the popup's content: receive, send, swap. A plain `Item`,
  because the `KeyboardPanel` already owns the window and the open/close lifecycle.
- `README.md` — install + remove instructions, security disclosure.
- `SECURITY.md` — addresses each marketplace baseline pattern.
- `LICENSE` — MIT.
- `audit-public.sh` — pre-push gate: fails on strings that must not be public.
- `check-wallet-safety.sh` — pre-push gate: fails if QML can reach a key.
- `COLLABORATION.md` — the team plan.

### Why there is no `panel` kind

A bar-anchored popup has to live **inside the bar slot that owns it**. `Bar.qml`
resolves one by walking `moduleSlots` and looking for an item with
`open`/`close`/`opened` on the slot's `activeItem`. A separate `panel` entry
point is loaded by the shell's own panel loader instead — a different object,
in a different lifecycle, that the bar never looks at. The result is a plugin
that summons successfully and paints nothing.

Every first-party panel that opens from a bar icon is declared this way:
`network`, `bluetooth`, `monitor` and `power` all declare
`kinds: ["bar-widget"]` with their `Panel.qml` as the `barWidget` entry point,
and the popup window is a `KeyboardPanel` child of that file. `KeyboardPanel`
supplies the layer-shell window, the anchored-to-icon position, the
outside-click region mask that leaves the bar clickable, the fade, and popout
coordination.

The same applies to the manifest's `entryPoints`: adding a `panel` entry point
alongside a `bar-widget` one makes the panel unreachable.

## The QML/CLI boundary (enforced, not documented)

**The QML is a view. The CLI owns every key, every signature, and every
broadcast.** That is what stops a compromised or buggy shell from spending
anything, and it is why the widget spawns `bch-bot` rather than reimplementing a
wallet.

`check-wallet-safety.sh` enforces it and fails the push if any of these appear
in a `.qml` file:

| Check | Why |
|---|---|
| `BCH_CONFIRM` anywhere | the broadcast gate belongs to the CLI; a widget that can set it can spend without asking |
| `mnemonic`, `privateKey`, `xpriv`, `wallet.json`, `BCH_WALLET_PASSPHRASE` | keys must never be read by the view layer |
| a `["bch-bot", "<cmd>"]` invocation where `<cmd>` moves value | only read-only subcommands (`balance`, `address`, `history`, `utxos`, `quote`) may be spawned from QML |
| `cashaddr` / `bitcoincash:` handling | address parsing and validation live in the CLI, which is the layer with tests over them |
| a hardcoded `NNNN BCH` figure | a fabricated balance renders as a real one with no wallet behind it |

Run both gates before every push:

```bash
./audit-public.sh && ./check-wallet-safety.sh
```

If a future change genuinely needs one of these, the answer is to add a
subcommand to the CLI — not to relax the gate. A rule written in prose is
out-competed by whatever the code already does; a rule that fails the build
cannot be.

## Style

- QML: follow `BchBalanceWidget.qml`. Its shape mirrors the first-party widgets in
  `omacom/omarchy` under `shell/plugins/bar/widgets/` — check there before inventing
  a pattern.
- Comments: explain *why* in 1-3 lines, not what.
- Indent: 2 spaces (matches Omarchy convention).
- Commit messages: imperative present tense ("fix", not "fixed").

## Review SLA

PRs are reviewed by maintainers within ~3 days. The first wave of community PRs (issues #1-#5) is the priority.

## License

By contributing, you agree that your contributions are MIT-licensed.
