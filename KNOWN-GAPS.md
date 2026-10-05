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

## 2. Receive address is generated on demand, not cached — DECIDED, kept open

`loadAddress()` calls `bch-bot address --json` each time Receive is opened. The
CLI derives a fresh address per call from the index. That is *correct* for a
non-receiving wallet (each receive is a fresh UTXO, so address reuse cannot link
them) and it is now the intended behaviour rather than an open question, because
the receive view is built around it: the QR, the clipboard and the displayed text
are all generated from whichever address the current call returned, and the
verification asserts all three agree with each other rather than with a
remembered value.

What remains is the UX cost, and it is a documentation task rather than a bug:
there is **no stable address**, so a user cannot be told "our address is X" and
have it stay true. If a stable address is ever wanted, the correct shape is a
**rotating set** disclosed as such — not a single cached address, which would
regress the unlinkability the fresh derivation provides.

## 3. Send flow re-verifies nothing between preview and broadcast

`previewSend()` and `confirmSend()` are two separate `bch-bot send` invocations.
The CLI re-derives the inputs and re-signs on the confirm call, so the
transaction the user saw in the preview is *not* the transaction that gets
broadcast — only the outputs and the fee total are guaranteed to match. The
gate is `verifyBuildAgainstQuote`-shaped for swaps, but the send path has no
equivalent "same inputs, same outputs" assertion across the two calls.

## 4. Live infra: broadcast.cauldron.quest is down — UNFIXED, external

Measured 2026-10-01 from both hosts.

| Endpoint | State |
|---|---|
| `indexer.riften.net` (HTTPS) | reachable — `resolveToken` works live |
| `router.riften.net` (WSS) | reachable — **live quotes work** |
| `rostrum.cauldron.quest:50004` | TCP OK |
| `broadcast.cauldron.quest/broadcast` | **TLS handshake fails** |

The broadcast host answers TCP on 443 and then fails the handshake:
`openssl s_client` reports `no peer certificate available`, and curl reports
`tlsv1 alert internal error` in 0.1s. That is the server's TLS config, not our
network — the A record (89.106.200.1) resolves fine and `router.riften.net` on
the same Cloudflare range serves normally.

**Impact:** quote works, broadcast does not. A funded end-to-end swap test
cannot complete until this is fixed upstream. `BCH_CAULDRON_BROADCAST` overrides
the URL, so there is no code change needed once the host is healthy again.

## 5. `priceBefore` disagrees with `outputAmount` by ~89% — UNFIXED, external

A live quote for 1 BCH → PUSD returned:

```
inputAmount   99999735   (0.99999735 BCH)
outputAmount  36141      (361.41 PUSD, PUSD has 2 decimals)
priceBefore   3434.87
poolCount     68
```

`outputAmount / inputAmount` = **361.41**, but `priceBefore` says **3434.87** —
a factor of ~9.5x apart. The output is the trustworthy number: the ratio is
stable across input sizes (0.1 / 1 / 2 BCH all give ~360-362), and the reverse
quote agrees on the same order of magnitude.

`priceBefore` is a straight pass-through of the router's `market_pre_price`
(`lib/router.mjs:179`), so the two fields are in **different units** and we are
relaying the mismatch. Either the router reports the pool's marginal price in a
different scale, or it is simply stale/wrong.

**Impact today: none user-facing.** The panel does not render `price_before` or
`price_after` (verified — no reference in the QML). It is only in `swap.mjs`'s
`--quote-only` JSON, so a future UI that shows it would show a wrong number.
Do not display either price field without first reconciling units.
