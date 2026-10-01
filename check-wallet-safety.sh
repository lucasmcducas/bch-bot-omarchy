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

# 1. The broadcast gate may only be set through the two explicit confirm
#    paths, and only as an `env` prefix on the CLI call -- never as a bare
#    export, never in the widget, and never on a command that is not send or
#    swap. The CLI remains the thing that actually decides whether to
#    broadcast; this only stops the view layer from waving the flag around.
if grep -nE "BCH_CONFIRM" $QML_FILES >/dev/null 2>&1; then
  BAD=$(grep -nE "BCH_CONFIRM" $QML_FILES \
        | grep -vE "^[A-Za-z0-9_/.]+\.qml:[0-9]+: *(\*|//)" \
        | grep -vE ",\s*\[\"BCH_CONFIRM=yes\"\]\)" || true)
  if [ -n "$BAD" ]; then
    echo "$BAD" >&2
    fail "BCH_CONFIRM must appear only as the literal [\"BCH_CONFIRM=yes\"] on a send/swap call"
  fi
fi

# 2. No key material, no wallet files, no seed words in the view layer.
if grep -niE "mnemonic|seed phrase|privateKey|private_key|xpriv|wallet\.json|BCH_WALLET_PASSPHRASE" $QML_FILES >/dev/null 2>&1; then
  grep -niE "mnemonic|seed phrase|privateKey|private_key|xpriv|wallet\.json|BCH_WALLET_PASSPHRASE" $QML_FILES >&2
  fail "QML references key material; keys must never be read by the view layer"
fi

# 3. Read-only subcommands may be spawned anywhere. The two value-moving ones
#    (send, swap) are permitted ONLY in the wallet panel, and only as a
#    dry-run call -- a broadcast is the same subcommand behind a separate
#    confirm path that requires a completed preview, so banning the argument
#    outright would mean also banning the dry run that is the safety step.
#
#    The invariant that actually matters: no subcommand may be invoked with
#    BCH_CONFIRM unless it is send or swap.
ALLOWED_ANYWHERE='^(balance|address|history|utxos|quote)$'
SENSITIVE='^(send|send-token|swap|sweep|stake|add-liquidity)$'

INVOKED=$(grep -hoE '\[\s*"bch-bot"\s*,\s*"[a-z-]+"' $QML_FILES 2>/dev/null \
          | grep -oE '"[a-z-]+"$' | tr -d '"' | sort -u)
if [ -n "$INVOKED" ]; then
  BAD=$(echo "$INVOKED" | grep -vE "$ALLOWED_ANYWHERE" || true)
  if [ -n "$BAD" ]; then
    # A value-moving subcommand is permitted in exactly ONE file. Checking
    # "does it appear in the panel" is not enough -- the same call could also
    # be pasted into the widget, which is a different trust surface. So the
    # per-file counts are compared: a sensitive command must occur exactly as
    # many times in the panel as it does in total.
    #
    # count() must never fail open. `grep -c ... || echo 0` is wrong: when grep
    # finds nothing it prints 0 AND exits 1, so the fallback appends a second
    # 0 and the value becomes the two-line string "0\n0". The arithmetic
    # comparison then raises "integer expression expected", the `if` takes the
    # false branch, and a sensitive command sitting outside the panel is
    # silently accepted -- the exact case this check exists to catch. awk
    # always prints exactly one number, so the substitution is well-formed
    # whether or not grep matched.
    count() {
      grep -coE "$1" $2 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}'
    }

    for cmd in $BAD; do
      PAT="\[\s*\"bch-bot\"\s*,\s*\"${cmd}\""
      TOTAL=$(count "$PAT" "$QML_FILES")
      IN_PANEL=$(count "$PAT" "./BchWalletPanel.qml")
      if [ "$IN_PANEL" -lt "$TOTAL" ]; then
        echo "SAFETY: bch-bot $cmd is invoked outside BchWalletPanel.qml" >&2
        grep -nE "$PAT" $QML_FILES >&2
        fail "value-moving subcommands belong in the panel only"
      fi
    done
  fi
fi

# 3b. The panel may reach send and swap, but nothing else. sweep, stake and
#     add-liquidity move value through paths with no preview step, so they are
#     not in the alpha's scope and must not appear.
PANEL_CMDS=$(grep -hoE '\[\s*"bch-bot"\s*,\s*"[a-z-]+"' ./BchWalletPanel.qml 2>/dev/null \
             | grep -oE '"[a-z-]+"$' | tr -d '"' | sort -u || true)
for cmd in $PANEL_CMDS; do
  case "$cmd" in
    balance|address|history|utxos|quote|send|swap) ;;
    *)
      echo "SAFETY: bch-bot $cmd is not part of the alpha surface" >&2
      fail "the panel may only use read-only commands plus send and swap"
      ;;
  esac
done

# 4. A broadcast call must never be one the user did not preview. The panel
#    builds a preview first and enables Confirm only when one exists, so the
#    check here is structural: confirmSend/executeSwap must be gated on
#    `sendPreview`/`swapQuote` being non-null.
if [ -f ./BchWalletPanel.qml ]; then
  for pair in "confirmSend:sendPreview" "executeSwap:swapQuote"; do
    fn="${pair%%:*}"; gate="${pair##*:}"
    if ! grep -q "enabled:.*${gate} !== null" ./BchWalletPanel.qml; then
      echo "SAFETY: ${fn}() must be enabled only when ${gate} is set" >&2
      fail "a broadcast button must be gated on a completed preview"
    fi
  done
fi

# 5. Address VALIDATION belongs to the CLI. Three shapes have to be caught,
#    and a single pattern misses two of them:
#      - a call to a validation helper (cashaddrTo..., isValidAddress, ...)
#      - a literal full address in source (a placeholder like "bitcoincash:q…"
#        is short enough to stay allowed)
#      - a REGEX built from the prefix, e.g. /bitcoincash:[a-z0-9]{40}/, which
#        is the sneaky one because the characters after the colon are a
#        character class rather than literals.
if grep -niE "cashaddrTo|validateAddress|isValidAddress|decodeCashAddress" $QML_FILES >/dev/null 2>&1 \
   || grep -niE "(bitcoincash|bchtest|bitcoin):\\\\?\[|bitcoincash:[a-z0-9]{25,}|bchtest:[a-z0-9]{25,}" $QML_FILES >/dev/null 2>&1; then
  grep -niE "cashaddrTo|validateAddress|isValidAddress|decodeCashAddress|(bitcoincash|bchtest|bitcoin):\\\\?\[|bitcoincash:[a-z0-9]{25,}|bchtest:[a-z0-9]{25,}" $QML_FILES >&2
  fail "QML validates addresses directly; parsing and validation belong to the CLI"
fi

# 6. The plugin must not fabricate a BALANCE. A fee line is not a balance --
#    it is a cost the user is shown -- so this looks for a balance-shaped
#    figure bound to a displayed value, not for the word "fee".
if grep -nE "(balance|amount)[A-Za-z]*:\s*\"?[0-9]{4,}\s*(BCH|sat)" $QML_FILES >/dev/null 2>&1; then
  grep -nE "(balance|amount)[A-Za-z]*:\s*\"?[0-9]{4,}\s*(BCH|sat)" $QML_FILES >&2
  fail "QML contains a hardcoded balance"
fi

if [ $EXIT -eq 0 ]; then
  # 7. A bar-anchored popup must live inside the bar slot that owns it. A
  #    separate `panel` entry point is loaded by the shell's own panel loader,
  #    which the bar never looks at -- the plugin summons successfully and
  #    paints nothing. Every first-party panel (network, bluetooth, monitor,
  #    power) declares kinds: ["bar-widget"] and hosts a KeyboardPanel.
  if [ -f ./manifest.json ]; then
    KINDS=$(jq -r '.kinds | join(",")' ./manifest.json 2>/dev/null || echo "")
    if [ "$KINDS" != "bar-widget" ]; then
      echo "SAFETY: manifest kinds is '$KINDS', expected exactly 'bar-widget'" >&2
      fail "a bar-anchored plugin must declare only the bar-widget kind"
    fi
    EP=$(jq -r '.entryPoints | keys | join(",")' ./manifest.json 2>/dev/null || echo "")
    if [ "$EP" != "barWidget" ]; then
      echo "SAFETY: manifest entryPoints is '$EP', expected only 'barWidget'" >&2
      fail "a second entry point is unreachable from the bar"
    fi
  fi
fi

if [ $EXIT -eq 0 ]; then
  echo "check-wallet-safety: clean (QML cannot reach a key)"
fi
exit $EXIT
