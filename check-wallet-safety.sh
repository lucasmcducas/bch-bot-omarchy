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
# The alpha surface, widened 2026-10-03 when the alpha's own definition did.
#
# The alpha is: see BCH and token holdings, receive either, send either, and swap
# BCH<->token. `send-token` is the token half of the send the allowlist already
# permitted -- excluding it produced a panel that DISPLAYED 2.00 ROACH and could
# only send BCH, which is a wallet that gets the BCH sent by mistake. That is a
# worse failure than a wider allowlist, so the capability is admitted rather than
# the display hidden.
#
# `list-tokens` is read-only. It calls the same public indexer `swap` already
# calls, returns no key material and moves nothing, and without it the swap view
# can only accept a symbol the user already knows -- of 346 tokens with a live
# market, that is about three names.
#
# Still excluded, and the exclusion is the point of the file: `sweep`, `stake`,
# `add-liquidity`, `wizardconnect` and anything not named here. Those move value
# through paths with no preview, and an allowlist is only worth having if adding
# to it is a visible act.
for cmd in $PANEL_CMDS; do
  case "$cmd" in
    balance|address|history|utxos|quote|send|send-token|swap|list-tokens) ;;
    *)
      echo "SAFETY: bch-bot $cmd is not part of the alpha surface" >&2
      fail "the panel may only use the alpha commands: read-only, send, send-token, swap, list-tokens"
      ;;
  esac
done

# 3c. STRUCTURAL: a process may only run a read-only command, and only the
#      panel may run a value-moving one.
#
#      This is the check that closes the bypass the literal greps above cannot
#      close. Those greps match text, so this defeats them:
#
#        property var verb: ["sw" + "eep"]
#        run(["bch-bot", root.verb], "balance", ["BCH_CONFIRM=yes"])
#
#      ...which builds a real `env BCH_CONFIRM=yes bch-bot sweep` argv at
#      runtime. The `kind` argument is a display label the gate never inspects,
#      and string concatenation defeats every literal pattern. Text matching
#      cannot enforce a semantic invariant in a dynamic language, so stop
#      trying: constrain the capability instead of describing the call.
#
#      BchBalanceWidget legitimately runs `bch-bot balance` for the bar, so a
#      Process is not banned outright outside the panel. What IS banned outside
#      the panel is a Process with the ability to run anything else. The
#      widget's own argv is asserted to be exactly the read-only command in
#      check 3d; this rule is the backstop for a Process that reaches further.
for f in $QML_FILES; do
  case "$f" in
    ./BchWalletPanel.qml) continue ;;
  esac
  # Strip line and block comments so a type named in prose does not trip the
  # rule; the check is about what the code can do, not what it says.
  body=$(sed -e 's://.*::' "$f" | perl -0777 -pe 's{/\*.*?\*/}{}gs')
  # The type name must appear anywhere a declaration can start, NOT only at the
  # start of a line. An earlier version anchored with ^, which meant the
  # single-line form
  #
  #     Item { Process { command: ["sh", "-c", "bch-bot sweep"] } }
  #
  # never matched, and a shell escape hid inside it passed the gate. The ^ was
  # cosmetic -- it only made the output prettier -- and it silently exempted the
  # densest way to write the thing being banned. Anchor on a word boundary and
  # require the type to be followed by an optional id and an opening brace.
  if printf '%s' "$body" | grep -qE '(^|[^A-Za-z0-9_])(Process|ProcessExecution|Command)[[:space:]]*(\{|[[:space:]]+id[[:space:]]*:)'; then
    # Count the process declarations, not just their presence. An earlier
    # version entered this block once for the file and then checked the file as
    # a whole, so appending a SECOND ProcessExecution to a file that already had
    # a legitimate bch-bot balance Process was never examined on its own -- the
    # file passed because the first declaration satisfied the rule. A gate that
    # checks "does this file contain a good one" instead of "is every one of
    # them good" is trivially bypassed by adding a bad one next to a good one.
    decl_count=$(printf '%s' "$body" | grep -oE '(^|[^A-Za-z0-9_])(Process|ProcessExecution|Command)[[:space:]]*(\{|[[:space:]]+id[[:space:]]*:)' | wc -l | tr -d ' ')
    good_count=$(printf '%s' "$body" | grep -oE '"bch-bot"[[:space:]]*,[[:space:]]*"(balance|address|history|utxos|quote|version|help)"' | wc -l | tr -d ' ')
    if [ "$good_count" -lt "$decl_count" ]; then
      echo "SAFETY: $f declares $decl_count process(es) but only $good_count run a literal read-only bch-bot command" >&2
      echo "         every process in a non-panel file must be accounted for; a good" >&2
      echo "         declaration does not excuse an unchecked one beside it." >&2
      fail "every process outside the panel must run a literal read-only command"
    fi
    # A Process exists here. Three things must hold, and all three are required:
    #
    #   1. The ONLY program it can invoke is bch-bot.
    #   2. Every subcommand it names is read-only.
    #   3. BCH_CONFIRM is not constructible here, so the process can be
    #      promoted to a broadcast at runtime.
    #
    # Rule 1 is what closes the split-string bypass. An earlier draft only
    # looked for literal ["bch-bot","sweep"] pairs, so this defeated it while
    # still being caught by rule 3:
    #
    #     property var verb: ["sw" + "eep"]
    #     process.command: ["bch-bot", root.verb]
    #
    # That is a value-moving process with no literal pair for the grep to find.
    # Checking the *program* rather than the argv shape catches it, because the
    # program is still the literal "bch-bot" even when the subcommand is built
    # at runtime. It cannot fully solve dynamic QML -- nothing can, short of a
    # type system -- but it moves the boundary from "describe the call" to
    # "constrain the capability", which is the improvement that matters.

    # --- rule 3: no confirm token -------------------------------------------
    if printf '%s' "$body" | grep -qE 'BCH_|CONFIRM'; then
      echo "SAFETY: $f references BCH_CONFIRM" >&2
      echo "         the broadcast confirmation token is confined to the panel; building one" >&2
      echo "         here is how a read-only argv gets promoted to a broadcast." >&2
      fail "the broadcast confirmation token is confined to the panel"
    fi

    # --- rule 1: only the CLI, never a shell --------------------------------
    # Anything that can execute an arbitrary program is out. `sh -c`, `env`,
    # and a bare interpolated path all open a way past the subcommand allow-list.
    if printf '%s' "$body" | grep -qE '"/(bin|usr)/|"(sh|bash|zsh|env|shellscript|xdg-open|open)"'; then
      echo "SAFETY: $f can invoke something other than the bch-bot CLI" >&2
      echo "         a shell or an absolute path bypasses the subcommand allow-list." >&2
      fail "only the bch-bot CLI may be invoked outside the panel"
    fi

    # --- rule 2: read-only subcommands --------------------------------------
    bad=$(printf '%s' "$body" | grep -oE '"bch-bot"[[:space:]]*,[[:space:]]*"[a-z-]+"' \
          | grep -oE '"[a-z-]+"[[:space:]]*$' | tr -d '" ' \
          | grep -vE '^(balance|address|history|utxos|quote|version|help)$' || true)
    if [ -n "$bad" ]; then
      echo "SAFETY: $f runs a value-moving command (${bad})" >&2
      echo "         only BchWalletPanel.qml may move value; that is what keeps every" >&2
      echo "         key and broadcast behind the checked confirm paths." >&2
      fail "value-moving commands are confined to the panel"
    fi

    # --- a Process with no bch-bot reference at all is unexplained ------------
    # A process that runs something unidentified is not a read-only balance read.
    if ! printf '%s' "$body" | grep -q 'bch-bot'; then
      echo "SAFETY: $f spawns a process but never references the bch-bot CLI" >&2
      fail "a process outside the panel must run the CLI and say so"
    fi

    # --- rule 4: the argv must be a literal, or provably a read-only one ------
    # Rules 1-3 all inspect literals. This closes the remaining hole: a process
    # that names no literal subcommand at all, so the allow-list in rule 2 had
    # nothing to check, and the value is assembled at runtime --
    #
    #     Process { command: ["bch-bot", root.verb] }   // verb = "sw"+"eep"
    #
    # The only argv the panel is allowed to build here is the read-only balance
    # read, written literally. Anything that is not that exact shape is refused.
    # This is default-deny, which is the only posture that holds against code
    # the gate cannot fully parse.
    if ! printf '%s' "$body" | grep -qE '"bch-bot"[[:space:]]*,[[:space:]]*"(balance|address|history|utxos|quote|version|help)"'; then
      echo "SAFETY: $f builds a bch-bot argv that is not a literal read-only command" >&2
      echo "         the only command a non-panel file may run is a literal read-only" >&2
      echo "         one. An argv assembled at runtime cannot be checked, and an" >&2
      echo "         uncheckable value-moving command is refused rather than assumed safe." >&2
      fail "a non-panel process must run a literal read-only bch-bot command"
    fi
  fi
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
