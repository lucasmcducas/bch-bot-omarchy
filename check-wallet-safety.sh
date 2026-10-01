#!/bin/bash
# check-wallet-safety.sh — fails the build if the QML layer can reach a key.
#
# The invariant this encodes: the QML is a view. Every private key, every
# signature, and every broadcast decision belongs to the bch-bot CLI. That is
# not a style preference -- it is what keeps a compromised or buggy shell from
# signing anything, and it is the reason the plugin shells out to a CLI instead
# of reimplementing a wallet in QML.
#
# These are checks rather than documentation on purpose. A rule written in a
# README is out-competed by whatever the surrounding code already does; a rule
# that fails here cannot be.

set -uo pipefail

EXIT=0
fail() {
  echo "SAFETY: $*" >&2
  EXIT=1
}

QML_FILES=$(find . -name '*.qml' -not -path './.git/*' 2>/dev/null)
if [ -z "$QML_FILES" ]; then
  echo "check-wallet-safety: no QML files found -- nothing to check"
  exit 0
fi

# 1. The QML must never set the broadcast gate. Only the CLI may, and only
#    after a human has confirmed. A widget that can set BCH_CONFIRM is a widget
#    that can spend without asking.
if grep -nE "BCH_CONFIRM" $QML_FILES >/dev/null 2>&1; then
  grep -nE "BCH_CONFIRM" $QML_FILES >&2
  fail "QML references BCH_CONFIRM; the broadcast gate belongs to the CLI only"
fi

# 2. No key material, no wallet files, no seed words in the view layer.
if grep -niE "mnemonic|seed phrase|privateKey|private_key|xpriv|wallet\.json|BCH_WALLET_PASSPHRASE" $QML_FILES >/dev/null 2>&1; then
  grep -niE "mnemonic|seed phrase|privateKey|private_key|xpriv|wallet\.json|BCH_WALLET_PASSPHRASE" $QML_FILES >&2
  fail "QML references key material; keys must never be read by the view layer"
fi

# 3. Only read-only subcommands may be spawned. `send`, `send-token`, `swap`,
#    `sweep`, `stake` and `add-liquidity` all move value or sign, and belong
#    behind a CLI flow the user drives deliberately.
#
#    Only genuine invocations count: a `command:` array entry, or a string run
#    through bar.run(). Matching the bare words "bch-bot send" would also match
#    an error message or a comment, and a gate that cries wolf gets ignored.
ALLOWED='^(balance|address|history|utxos|quote)$'
INVOKED=$(grep -hoE '\[\s*"bch-bot"\s*,\s*"[a-z-]+"' $QML_FILES 2>/dev/null \
          | grep -oE '"[a-z-]+"$' | tr -d '"' | sort -u)
if [ -n "$INVOKED" ]; then
  BAD=$(echo "$INVOKED" | grep -vE "$ALLOWED" || true)
  if [ -n "$BAD" ]; then
    echo "SAFETY: value-moving subcommand(s) reachable from QML:" >&2
    echo "$BAD" | sed 's/^/  bch-bot /' >&2
    fail "the view layer may only spawn read-only subcommands"
  fi
fi

# 4. Wallet logic must not be reimplemented in QML. Address validation and
#    amount arithmetic belong to the CLI, which is the only layer with tests
#    covering them. A regex for a cashaddr here would be an untested copy.
if grep -niE "cashaddr|bitcoincash:|bchtest:|bitcoin:" $QML_FILES >/dev/null 2>&1; then
  grep -niE "cashaddr|bitcoincash:|bchtest:|bitcoin:" $QML_FILES >&2
  fail "QML handles addresses directly; parsing and validation belong to the CLI"
fi

# 5. The plugin must not fabricate a balance. A hardcoded satoshi figure in the
#    view layer would render as a real balance with no wallet behind it.
if grep -nE "[0-9]{4,}\s*(BCH|sat)" $QML_FILES >/dev/null 2>&1; then
  grep -nE "[0-9]{4,}\s*(BCH|sat)" $QML_FILES >&2
  fail "QML contains a hardcoded balance"
fi

if [ $EXIT -eq 0 ]; then
  echo "check-wallet-safety: clean (QML cannot reach a key)"
fi
exit $EXIT
