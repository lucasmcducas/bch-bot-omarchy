# BCH Wallet — Omarchy Plugin

A self-custodial Bitcoin Cash (BCH) wallet in your Omarchy bar widget.

## What it does

- **Bar widget** — shows your live BCH balance + recent activity at a glance
- **Hotkey-driven commands** — `omarchy bch-wallet send <addr> <sats>` from anywhere
- **Self-custodial** — you hold your own keys; no accounts, no KYC, no OAuth
- **CashTokens-aware** — sees FT and NFT holdings alongside BCH
- **Cauldron AMM integration** — quote swaps without leaving the shell

## Installation

This plugin depends on two things:
1. The plugin itself (the UI shell)
2. The `bch-bot` CLI (the wallet engine)

### One-command install (Arch / Omarchy)

```bash
yay -S bch-bot                                          # AUR: wallet CLI
omarchy plugin add https://github.com/lucasmcducas/bch-bot-omarchy.git --enable
```

(`omarchy plugin install` is an alias for `omarchy plugin add`.)

That's it — two commands. The plugin detects the wallet on startup and shows your BCH balance in the bar.

### If `yay -S bch-bot` isn't available yet (AUR submission pending)

```bash
# 1. Install the wallet from source
git clone https://github.com/lucasmcducas/bch-bot-public.git
cd bch-bot-public
npm ci
npm link                                                # makes 'bch-bot' available globally

# 2. Add the plugin (clone + validate + enable in one step)
omarchy plugin add https://github.com/lucasmcducas/bch-bot-omarchy.git --enable
```

Or, for testing, install without `--enable` and validate manually:

```bash
omarchy plugin clone https://github.com/lucasmcducas/bch-bot-omarchy.git
omarchy plugin validate ~/.config/omarchy/plugins/io.github.lucasmcducas.bch-wallet
omarchy plugin enable io.github.lucasmcducas.bch-wallet --section right
```

### What you should see

The widget shows a 💰 icon in the bar's right section:

- **Balance shown** — the confirmed BCH balance beside the icon, e.g. `0.00858627`
- **Zero balance** — the icon dims and the label reads `0`
- **`bch-bot` not installed** — the slot hides itself entirely rather than showing a
  permanent error icon; hover is not possible once hidden, so reinstall and
  reload the shell
- **CLI present but failing** — the icon dims and hover explains why (no network,
  unreadable wallet)

Click the icon to refresh immediately. Middle-click opens
`bch-bot balance` in a floating terminal.

### QML validation

```bash
qmllint BchBalanceWidget.qml
```

`qmllint` ships with `qtdeclarative5-dev-tools` (Arch) or equivalent elsewhere.

Be aware of what it does *not* check: it is a syntax verifier, so it reports a
malformed file but happily passes a file that calls a method which does not
exist. The first version of this widget used `Scope` as its root and read
stdout from an `onExited` second argument — both wrong against the real shell,
and both passed `qmllint`. The structural check that does catch this class of
bug is running the plugin on a real Omarchy install.

### Step 1: Install the bch-bot CLI (do this first)

The plugin needs the `bch-bot` CLI to be on your `$PATH`. Install it via one of:

**Option A — from AUR (recommended for Arch/Omarchy users)**
```bash
yay -S bch-bot
```

> Not submitted yet — see the note under Option B.

**Option B — from source (recommended for now; AUR submission is pending)**
```bash
git clone https://github.com/lucasmcducas/bch-bot-public.git
cd bch-bot-public
npm ci
npm link                                                # makes 'bch-bot' available globally
```

Note that `bch-bot` is not in the AUR yet — the PKGBUILD is written and pinned
but has not been submitted, so `yay -S bch-bot` will not find it. Use the source
install above for now.

**Option C — local install for development**
```bash
git clone https://github.com/lucasmcducas/bch-bot-public.git ~/bch-bot
cd ~/bch-bot && npm ci
echo 'export PATH="$HOME/bch-bot/bin:$PATH"' >> ~/.bashrc
```

### Step 2: Add the plugin

After the wallet CLI is on your `$PATH`, add the plugin via the Omarchy shell:

```bash
omarchy plugin add https://github.com/lucasmcducas/bch-bot-omarchy.git --enable
```

The shell:
- Clones the repo into `~/.config/omarchy/plugins/io.github.lucasmcducas.bch-wallet/`
- Reads the manifest at the root
- Validates the manifest against the schema (schemaVersion, kinds, entryPoints)
- Enables the plugin (the `--enable` flag) and prompts for bar section placement

To clone without enabling (for testing or reviewing first):

```bash
omarchy plugin clone https://github.com/lucasmcducas/bch-bot-omarchy.git
```

To validate manually:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.lucasmcducas.bch-wallet
```

To enable after manual review:

```bash
omarchy plugin enable io.github.lucasmcducas.bch-wallet --section right
```

### Step 3: Restart Omarchy (or reload the shell)

After installing the CLI, restart Omarchy (or reload the shell) so the widget
picks it up. The widget spawns `bch-bot balance` once at load and then on its
refresh interval, so a CLI installed after the shell started is not noticed
until a reload.

You should see:
- The 💰 icon with your balance once `bch-bot` is on `$PATH` and a wallet exists
- No slot at all if `bch-bot` is not installed

## Removal

```bash
omarchy plugin disable io.github.lucasmcducas.bch-wallet
omarchy plugin remove io.github.lucasmcducas.bch-wallet
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

## Plugin manifest schema

Plugins are git repos with a `manifest.json` at the root. The shell clones them into `~/.config/omarchy/plugins/<manifest-id>/` and validates against this schema:

```json
{
  "schemaVersion": 1,                    // only 1 supported
  "id": "io.github.<yourname>.<plugin>",  // namespaced, lowercase, no 'omarchy.*' reserved
  "name": "...",
  "version": "0.1.0",
  "author": "...",
  "license": "MIT",
  "description": "...",
  "kinds": ["bar-widget"],
  "entryPoints": {
    "barWidget": "BchBalanceWidget.qml"
  },
  "barWidget": {
    "displayName": "...",
    "description": "...",
    "category": "Productivity",
    "aliases": ["..."],
    "defaults": { ... },
    "schema": [ ... ]
  }
}
```

Required fields: `schemaVersion`, `id`, `name`, `version`, `kinds`, `entryPoints`. Run `omarchy plugin validate <path>` to check your manifest before publishing.

## Security

This plugin:
- Does **not** store private keys in QML. Keys live in `~/.bch-wallet/wallet.json`, encrypted at rest with scrypt + aes-256-gcm.
- Does **not** execute code from the network. All commands invoke the local `bch-bot` CLI.
- Does **not** modify user configuration outside its own scope.
- Has **no** install/uninstall scripts in the marketplace sense — the shell handles git clone into the plugins dir.

The plugin's security posture relies on the bch-bot CLI's security. See [bch-bot/SECURITY.md](https://github.com/lucasmcducas/bch-bot-public/blob/main/SECURITY.md) for the upstream threat model.

## External dependencies

| Dependency | Why | Source |
|---|---|---|
| `bch-bot` CLI | Wallet logic | `github.com/lucasmcducas/bch-bot-public` |
| Node.js >= 22 | Runtime for bch-bot | nodejs.org |
| libauth 3.0.0 | BCH signing primitives (transitively) | bitcoincashjs/libauth |
| @cashlab/* | Cauldron AMM integration (transitively) | cashlab npm |

All transitive deps are exactly pinned in `bch-bot/package.json`. The bch-bot repo's CI verifies them.

## License

MIT — see [LICENSE](LICENSE).

## Author

Luke McDucas (`@lucasmcducas` on GitHub). Bug reports welcome via GitHub issues.
