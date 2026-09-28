name: Issue #1 — Wire bch-bot balance into the bar widget
description: Quickshell.Io.Process call into bch-bot balance, parse JSON, display live balance.
labels: ["good first issue", "help wanted"]
assignees: []
---

# Wire `bch-bot balance` into the bar widget

## Goal

The bar widget (`BchBalanceWidget.qml`) currently shows a placeholder "loading..." text. This issue replaces that with a live BCH balance that updates every 60s.

## Acceptance criteria

- [ ] The bar widget displays the live BCH balance (e.g., "Ƀ 0.00858627") instead of "loading..."
- [ ] Updates every `refreshIntervalSec` (default 60s)
- [ ] No network code in QML — uses `Quickshell.Io.Process` to spawn `bch-bot balance` and parse the JSON output
- [ ] On error (CLI not found, parse failure), shows "—" instead of crashing the widget
- [ ] Tested in Omarchy 4.0 with the actual `bch-bot` CLI installed

## Implementation hint

The `bch-bot` CLI emits JSON like:
```json
{
  "network": "mainnet",
  "satoshis_confirmed": "858627",
  "satoshis_unconfirmed": "0",
  ...
}
```

`Quickshell.Io.Process` should run `bch-bot balance --format=json` (or similar) and the QML parses the JSON.

## Out of scope

- Send/receive modals (separate issues)
- Token balance display (separate issue)

## Resources

- [Quickshell.Io docs](https://quickshell.org/docs/types/Io/)
- `bch-bot` repo: https://github.com/lucasmcducas/bch-bot
- Wiki: https://github.com/lucasmcducas/bch-wiki-public

## Workflow

1. Comment on this issue to claim it (one assignee at a time)
2. Fork `lucasmcducas/bch-bot-omarchy` and branch from `collaborate/v0.1`
3. Implement against the acceptance criteria
4. Test in Omarchy 4.0 (with a real wallet — your own)
5. Open a PR with `Closes #1` in the body
