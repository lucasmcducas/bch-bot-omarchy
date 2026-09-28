name: Issue #2 — Send modal with treasury fee disclosure
description: Click bar icon → modal shows recipient, amount, fee, total; confirm button calls bch-bot send.
labels: ["good first issue", "help wanted"]
assignees: []
---

# Send modal with treasury fee disclosure

## Goal

Clicking the bar widget opens a modal where the user can:
1. Enter a recipient address + amount
2. See the treasury fee, network fee, and total
3. Confirm (which calls `bch-bot send` with `BCH_CONFIRM=yes`)

## Acceptance criteria

- [ ] Modal opens on bar widget click
- [ ] Fields: recipient address, amount (sats)
- [ ] Display row: amount, treasury fee (if enabled), network fee, total — all in sats
- [ ] Treasury fee line is visible (or "fee disabled" if `treasuryAddress` is empty)
- [ ] Confirm button calls `bch-bot send <addr> <amount>` via Quickshell.Io.Process with `BCH_CONFIRM=yes`
- [ ] On success: close modal, show txid in a toast
- [ ] On failure: show error message in the modal (don't close)
- [ ] Address validation: cashaddr format only (P2PKH starts with bitcoincash:q...)

## Implementation hint

The `bch-bot` CLI's `send` command supports a dry-run mode (default) that returns the constructed tx without broadcasting. The modal can show fees from a dry-run, then on confirm re-run with `BCH_CONFIRM=yes`.

## Out of scope

- Address book (separate)
- Multi-output transactions (separate)

## Resources

- Issue #1 (depends on this; do that first)
- `bch-bot` repo: https://github.com/lucasmcducas/bch-bot-public
- Wiki: https://github.com/lucasmcducas/bch-wiki-public

## Workflow

1. Comment on this issue to claim it
2. Fork and branch from `collaborate/v0.1`
3. Implement against the acceptance criteria
4. Test in Omarchy 4.0 (with a chipnet wallet first, then mainnet)
5. Open a PR with `Closes #2`
