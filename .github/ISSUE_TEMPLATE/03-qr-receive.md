name: Issue #3 — QR code generator for receive
description: omarchy bch-wallet receive shows QR for the current receiving address.
labels: ["good first issue", "help wanted"]
assignees: []
---

# QR code generator for receive

## Goal

`omarchy bch-wallet receive` (the IPC command) returns a QR code that encodes the wallet's current receiving address. The user can scan it with any BCH wallet to send funds to you.

## Acceptance criteria

- [ ] IPC handler `bch-wallet receive` returns a QR code (PNG/SVG/text)
- [ ] QR encodes the wallet's current receiving address from `bch-bot address`
- [ ] Format selectable: terminal (Unicode block), image (PNG), or SVG
- [ ] Tested in Omarchy 4.0 shell with `omarchy bch-wallet receive`

## Implementation hint

The `bch-bot` CLI's `address` command prints the current receiving address. The QR can be generated using one of:
- `qrencode` (CLI tool, common on Arch) — produces PNG/SVG
- A pure-JS library (no new runtime deps preferred)
- Inline Unicode block rendering for terminal-only

## Out of scope

- Animated QR (separate)
- URI schemes (separate, future)

## Resources

- Issue #1 (depends on this)
- `bch-bot` repo: https://github.com/lucasmcducas/bch-bot
- Wiki: https://github.com/lucasmcducas/bch-wiki-public

## Workflow

1. Comment on this issue to claim it
2. Fork and branch from `collaborate/v0.1`
3. Implement against the acceptance criteria
4. Test in Omarchy 4.0
5. Open a PR with `Closes #3`
