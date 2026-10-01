# Known gaps (auditors: read this before reporting)

Findings I found myself, recorded so they are not lost and not double-fixed.
Each is unfixed unless it says otherwise.

## 1. The swap path has no slippage protection in the UI — UNFIXED

`BchWalletPanel.qml:154-161` invokes the CLI as:

- quote:   `bch-bot swap <sell> <buy> <amount> --quote-only`
- execute: `bch-bot swap <sell> <buy> <amount>`

`--min-output` is **never passed**. Consequences:

- The quote the user confirms and the transaction that gets signed are not tied
  together by a floor. Between quote and broadcast the price can move, the swap
  fills worse than what was displayed, and nothing rejects it.
- `lib/router.mjs:225-230` supports `min_output` and enforces it
  (`:260-261` rejects a build below the floor), so the protection exists — it
  is just never used by the UI.
- `scripts/swap.mjs:87,153` hardcodes `side: 'sell'`. **This is correct.** The
  CLI's amount is always denominated in the sell asset, so sell-side quoting is
  the right semantic; there is no buy/sell bug here. `router.mjs:228` correctly
  throws if a floor is passed with any other side.

Two candidate fixes — pick one, do not do both:

| | Change | Blast radius |
|---|---|---|
| A | Default `--min-output` in `swap.mjs` to ~99% of quoted output | Every CLI caller gets protection for free; no UI change |
| B | Add a slippage field to the panel, pass `--min-output` through | User-visible, but the floor can be set to 0 and the user must understand it |

A is safer and smaller. B is the honest UX if the user is told the worst price
they will accept. The real fix is A with B's disclosure.

## 2. Receive address is generated on demand, not cached

`loadAddress()` calls `bch-bot address --json` each time the panel opens. The
CLI derives a fresh address per call from the index. That is *correct* for a
non-receiving wallet (each receive is a fresh UTXO, so address reuse cannot link
them) but it means the panel does not show a stable address to check against a
sender's expectation. Worth a decision: fresh-per-open, or a rotating set.

## 3. Send flow re-verifies nothing between preview and broadcast

`previewSend()` and `confirmSend()` are two separate `bch-bot send` invocations.
The CLI re-derives the inputs and re-signs on the confirm call, so the
transaction the user saw in the preview is *not* the transaction that gets
broadcast — only the outputs and the fee total are guaranteed to match. The
gate is `verifyBuildAgainstQuote`-shaped for swaps, but the send path has no
equivalent "same inputs, same outputs" assertion across the two calls.
