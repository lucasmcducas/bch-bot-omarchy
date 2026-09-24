# BCH Wallet — Omarchy Plugin

A self-custodial Bitcoin Cash (BCH) wallet in your Omarchy bar widget. **The first spendable crypto plugin in the Omarchy marketplace.**

## What it does

- **Bar widget** — shows your live BCH balance + recent activity at a glance
- **Hotkey-driven commands** — `omarchy bch-wallet send <addr> <sats>` from anywhere
- **Self-custodial** — you hold your own keys; no accounts, no KYC, no OAuth
- **CashTokens-aware** — sees FT and NFT holdings alongside BCH
- **Cauldron AMM integration** — quote swaps without leaving the shell
- **0.5% treasury fee** — per-tx, visible in the send confirmation, set to your own address or 0 if you self-host

## Installation

This plugin is shipped as an Omarchy marketplace plugin. The shell handles installation:

```bash
omarchy plugin install bch-wallet
```

To install from this source repository directly (for testing):

```bash
git clone https://github.com/lucasmcducas/bch-wallet-omarchy.git \
  ~/.config/omarchy/plugins/bch-wallet
```

This plugin depends on the **bch-bot** CLI being installed separately:

```bash
# Arch / Omarchy
pacman -S bch-bot   # or yay -S bch-bot from AUR

# macOS / dev
git clone https://github.com/lucasmcducas/bch-bot.git
cd bch-bot && npm ci && npm link
```

## First-run setup

1. Create a wallet:
   ```bash
   bch-bot create-wallet
   ```
2. **Set the encryption passphrase** (recommended):
   ```bash
   export BCH_WALLET_PASSPHRASE="your-strong-passphrase"
   bch-bot encrypt-wallet
   ```
3. Re-export the passphrase in your shell rc, or store it in a keyring (the plugin does NOT store it — the wallet refuses to load without it).

## Removal

```bash
omarchy plugin remove bch-wallet
# optionally clean up wallet
rm -rf ~/.bch-wallet
```

The plugin does not modify any user configuration outside its own scope. The wallet directory (`BCH_WALLET_DIR`, default `~/.bch-wallet`) and the settings schema are not touched by the plugin.

## Subcommands

| Command | Description |
|---|---|
| `omarchy bch-wallet balance` | Show current BCH balance + token holdings |
| `omarchy bch-wallet receive` | Show receiving address + QR code |
| `omarchy bch-wallet send <addr> <sats>` | Build a send tx (broadcast requires `BCH_CONFIRM=yes`) |
| `omarchy bch-wallet send-token <addr> <cat> <amt>` | Send a CashTokens FT |
| `omarchy bch-wallet history` | Recent transactions |
| `omarchy bch-wallet sweep` | Consolidate dust UTXOs |
| `omarchy bch-wallet stake` | Stake PUSD (if any) |
| `omarchy bch-wallet swap <supply> <demand> <amount>` | Quote a Cauldron swap |

## Security

This plugin:
- Does **not** store private keys in QML. Keys live in `~/.bch-wallet/wallet.json`, encrypted at rest with scrypt + aes-256-gcm (lib/wallet-encryption.mjs).
- Does **not** execute code from the network. All commands invoke the local `bch-bot` CLI.
- Does **not** modify user configuration outside its own plugin dir.
- Has **no** install/uninstall scripts in the marketplace sense — the shell handles git clone into the plugins dir.

The plugin's security posture relies on the bch-bot CLI's security. See [bch-bot/SECURITY.md](https://github.com/lucasmcducas/bch-bot/blob/main/SECURITY.md) for the upstream threat model.

### Treasury fee disclosure

The 0.5% per-tx fee (configurable 0-1000 bps in plugin settings) is added as a separate output to every transaction. The fee:
- Is **visible** in the send confirmation modal in `BchBalanceWidget.qml`'s send UI
- Is **disabled** when `treasuryAddress` is empty or `treasuryBps` is 0
- Can be **redirected** to your own BCH address (for forks / self-hosters)
- Goes to `bitcoincash:qpjfw956u6rc88n8ul4xxyu9fu2v94s2eylh9vtzhv` by default

The default treasury address is published in this README and in the manifest's `barWidget.defaults`. It is **not** obfuscated.

## External dependencies

| Dependency | Why | Source |
|---|---|---|
| `bch-bot` CLI | Wallet logic | `github.com/lucasmcducas/bch-bot` |
| Node.js >= 22 | Runtime for bch-bot | nodejs.org |
| libauth 3.0.0 | BCH signing primitives (transitively) | bitcoincashjs/libauth |
| @cashlab/* | Cauldron AMM integration (transitively) | cashlab npm |

All transitive deps are exactly pinned in `bch-bot/package.json`. The bch-bot repo's CI verifies them.

## License

MIT — see [LICENSE](LICENSE).

## Author

Luke McDucas (`@lucasmcducas` on GitHub). Bug reports welcome via GitHub issues.
