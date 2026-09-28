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

This plugin depends on two things:
1. The plugin itself (the UI shell)
2. The `bch-bot` CLI (the wallet engine)

### Step 1: Install the bch-bot CLI (do this first)

The plugin needs the `bch-bot` CLI to be on your `$PATH`. Install it via one of:

**Option A — from source (recommended for now; AUR submission is pending)**
```bash
git clone https://github.com/lucasmcducas/bch-bot-public.git
cd bch-bot-public
npm ci
# Add to PATH (one of these):
npm link                                   # makes 'bch-bot' available globally
# OR
echo 'export PATH="$HOME/bch-bot-public/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Option B — from AUR (will work once the package is submitted)**
```bash
yay -S bch-bot
```

**Option C — local install for development**
```bash
git clone https://github.com/lucasmcducas/bch-bot.git ~/bch-bot
cd ~/bch-bot && npm ci
echo 'export PATH="$HOME/bch-bot/bin:$PATH"' >> ~/.bashrc
```

### Step 2: Install the plugin

After the wallet CLI is on your `$PATH`, install the plugin via the Omarchy marketplace:

```bash
omarchy plugin install bch-wallet
```

The Omarchy shell:
- Pulls the plugin from https://github.com/lucasmcducas/bch-bot-omarchy
- Reads the manifest
- Registers the bar widget

To install from source directly (for testing):

```bash
git clone https://github.com/lucasmcducas/bch-bot-omarchy.git \
  ~/.config/omarchy/plugins/bch-wallet
```

### Step 3: Restart Omarchy (or reload the shell)

The plugin runs `which bch-bot` on startup. After installing the CLI, restart Omarchy (or send a reload signal) so the widget re-detects the CLI.

You should see:
- Red "Ƀ ✗" with hover tooltip if bch-bot is missing
- Green "Ƀ 0.00858627" once bch-bot is on `$PATH` and the wallet is loaded

## Removal

```bash
omarchy plugin remove bch-wallet
# optionally clean up wallet
rm -rf ~/.bch-wallet
```

The plugin does not modify any user configuration outside its own scope. The wallet directory (`BCH_WALLET_DIR`, default `~/.bch-wallet`) and the settings schema are not touched by the plugin.

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
- Does **not** store private keys in QML. Keys live in `~/.bch-wallet/wallet.json`, encrypted at rest with scrypt + aes-256-gcm.
- Does **not** execute code from the network. All commands invoke the local `bch-bot` CLI.
- Does **not** modify user configuration outside its own scope.
- Has **no** install/uninstall scripts in the marketplace sense — the shell handles git clone into the plugins dir.

The plugin's security posture relies on the bch-bot CLI's security. See [bch-bot/SECURITY.md](https://github.com/lucasmcducas/bch-bot/blob/main/SECURITY.md) for the upstream threat model.

### Treasury fee disclosure

The per-tx fee (default 0.5%, configurable 0-1000 bps in plugin settings) is added as a separate output to every transaction. The fee:
- Is **visible** in the send confirmation modal before broadcast
- Is **disabled** when `treasuryAddress` is empty or `treasuryBps` is 0
- Can be **redirected** to your own BCH address (for forks / self-hosters)
- Defaults to **disabled** (`treasuryAddress: ""`) so the plugin ships with no built-in fee routing — users must opt in by setting their own address

The treasury address is **not** hardcoded in the public plugin. Users who want to support the maintainer can opt in via the plugin settings.

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
