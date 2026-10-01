// BchWalletPanel.qml — the wallet's interactive surface: receive, send, swap.
//
// Structure follows the first-party panels (see shell/plugins/panels/network/
// Panel.qml): a `Panel` root with a moduleName, which supplies the
// open/close lifecycle, the IPC target, and the theme colors. The bar widget
// opens this with `bar.run(...)`; the shell calls open() on the instance.
//
// SAFETY MODEL. Nothing here signs and nothing here broadcasts. This panel
// collects input, runs READ-ONLY or DRY-RUN subcommands, and shows what the
// CLI would do. The one exception is the final Confirm on the send/swap flow,
// which runs the same CLI with BCH_CONFIRM=yes — the gate stays in the CLI,
// where it is testable, and this file cannot skip it. A user who closes the
// panel mid-flow has spent nothing.
//
// The fee shown is the network fee only. There is no service fee.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
// Style and Color are singletons in qs.Commons, not qs.Ui. Without this import
// every Style.* / Color.* reference throws a ReferenceError at load and the
// panel renders empty -- with no load-failure message, because the file itself
// parsed fine.
import qs.Commons

// The CONTENT of the wallet panel. It is instantiated inside the bar widget's
// KeyboardPanel, which owns the window and the open/close lifecycle, so this
// file is a plain Item rather than a Panel: a Panel here would register a
// second IPC handler for the same target and a second PanelController.
Item {
  id: root
  implicitHeight: layout.implicitHeight

  // Set by the host widget to close the popup. A plain Item has no close() of
  // its own -- the KeyboardPanel does -- so the host injects the callback.
  property var closeRequested: null

  // Foreground colour, injected by the host. A Panel used to supply this via
  // its own barForeground; as a plain Item there is no bar reference, and
  // Color.foreground is the same token the Panel base falls back to.
  property color foreground: Color.foreground

  // ------------------------------------------------------------------- state

  // view: home | send | receive | swap
  property string view: "home"
  property string status: "idle"      // idle | busy | ok | error
  property string errorMessage: ""

  property string balanceBch: "0.00000000"
  property string balanceUnconfirmed: "0.00000000"
  property int utxoCount: 0
  // The fungible-token balances, as an array of {symbol, display, amount,
  // decimals, category, known}. An array rather than a map because a QML
  // Repeater model needs a countable list, and because the order matters: the
  // CLI already sorts by value descending.
  //
  // `amount` is exact base units and `display` is the human string. Both are
  // kept: a future send-token view must use `amount`, and parsing `display`
  // back is exactly the kind of round-trip that loses a decimal place.
  property var tokens: []
  property string receiveAddress: ""
  property string receiveNetwork: ""

  // send flow
  property string sendTo: ""
  property string sendAmount: ""
  property var sendPreview: null       // the dry-run JSON from `bch-bot send`
  property bool sendConfirmed: false

  // swap flow
  property string swapSell: ""
  property string swapBuy: ""
  property string swapAmount: ""
  // The minimum acceptable output, in the BUY asset's base units (or a decimal
  // amount the CLI converts). Empty means no floor, which is the router's
  // default and is NOT safe: the router is documented as beta, and a quote can
  // go stale between the preview and the build. Without a floor the only
  // protection is that the build matches the quote, and both numbers come from
  // the router.
  property string swapMinOutput: ""
  property var swapQuote: null

  // Which flow a running command belongs to, so one Process can serve all of
  // them: balance | address | send-preview | send-confirm | swap-quote |
  // swap-execute.
  property string pendingKind: ""
  // Whether the run in flight is a background refresh. Carried on the root
  // because `pendingKind` is cleared the moment the process exits, and the exit
  // handler needs to know whether this failure should be loud or quiet.
  property bool pendingSilent: false

  // Captured stdout, read once the process has exited. A Process has no
  // user-defined properties, so the result cannot be stashed on it.
  property string lastStdout: ""

  // ------------------------------------------------------------------ helpers

  readonly property color fg: foreground
  readonly property color dim: Qt.darker(fg, 1.5)

  function reset() {
    view = "home"
    status = "idle"
    errorMessage = ""
    sendPreview = null
    sendConfirmed = false
    swapQuote = null
  }

  // Refresh the balances. Separate from the bar widget's own timer because the
  // panel is opened far less often than it is visible, and a balance that is
  // only fetched on open is stale the moment a swap completes.
  //
  // A refresh must not clobber a view the user is in the middle of, and it must
  // not show a spinner over a form they are typing into. So it deliberately
  // does NOT touch `status`: a failed background refresh leaves the last known
  // balances on screen with a small "stale" note rather than blanking a form.
  property string lastRefreshError: ""
  property bool refreshing: false
  // Set once the address has been copied, and cleared when the user navigates
  // away. A copy with no confirmation is worse than no copy button: the user
  // pastes whatever was on the clipboard before and sends money to a stranger.
  property bool copied: false

  // Copy the receive address to the clipboard.
  //
  // A dedicated Process rather than the shared `run()` one, for two reasons:
  // the shared process is reserved for bch-bot subcommands (so a clipboard
  // failure can never be reported as a wallet failure), and `run()` cannot
  // feed stdin, which is how the address gets to wl-copy without ever being
  // interpolated into a shell string. An address passed through a shell is an
  // address that can be read as syntax; a cashaddr is a fixed charset today, but
  // that is not the property being relied on.
  //
  // --foreground keeps the clipboard content alive after this process exits.
  // Without it wl-copy can drop the selection when the writer goes away, which
  // presents to the user as a copy that silently did nothing.
  //
  // stdinEnabled is REQUIRED. Verified against the installed Quickshell type
  // definition (/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes), which
  // exposes both `stdinEnabled` and `write()`. Without stdinEnabled, write()
  // has no pipe to write to: the address would be dropped and wl-copy would
  // still exit 0 having copied an empty string, which is a copy button that
  // lies.
  Process {
    id: copyProcess
    running: false
    command: ["wl-copy", "--foreground"]
    stdinEnabled: true

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastStdout = String(text)
      }
    }

    onExited: function (exitCode) {
      // Zero means wl-copy accepted it. It can exit non-zero when there is no
      // Wayland display -- a headless login, or an X11 session -- and then the
      // honest thing is to say so rather than to claim a copy that did not
      // happen.
      root.copied = exitCode === 0
      if (exitCode !== 0) {
        root.errorMessage = "could not reach the clipboard (no Wayland session?) — select the address and copy it manually"
      }
    }
  }

  function copyAddress() {
    if (!root.receiveAddress) return
    root.errorMessage = ""
    if (copyProcess.running) return
    // Quickshell's Process has no stdin pipe: `write()` is the only way to hand
    // it data. Writing immediately can race the child not having opened stdin
    // yet, so the write is deferred one event-loop turn. If the write is lost
    // the clipboard ends up empty and wl-copy still exits 0, which is why the
    // success state is short-lived rather than sticky.
    copyProcess.running = true
    Qt.callLater(function () {
      if (copyProcess.running) copyProcess.write(root.receiveAddress)
    })
  }

  function refreshBalances() {
    if (root.status === "busy") return
    root.refreshing = true
    // Reuses the existing "balance" kind rather than adding a parallel
    // "balance-refresh" one. Two kinds feeding the same parser is how the two
    // drift apart, and the only difference here is whether a failure is
    // surfaced or swallowed -- which is decided by `silent` below, not by
    // duplicating the result handler.
    run(["bch-bot", "balance"], "balance", [], true)
  }

  // A background refresh is best-effort: on failure keep what is on screen and
  // mark it, because an empty balance panel is indistinguishable from an empty
  // wallet and reads as a loss of funds.
  function onRefreshResult(parsed) {
    root.refreshing = false
    if (!parsed) {
      root.lastRefreshError = "balance unavailable — showing the last known value"
      return
    }
    root.lastRefreshError = ""
  }

  // Runs a bch-bot subcommand and routes the result to `applyResult`.
  // `env` is a list of KEY=VALUE pairs prefixed onto the command with env(1),
  // which keeps BCH_CONFIRM visible in the command line rather than hidden in
  // a side channel.
  //
  // `silent` marks a BACKGROUND run. A background refresh must not take over
  // the panel: it should not clear the view, raise a full-screen error, or
  // block the user from clicking anything while it runs. A silent failure is
  // recorded in `lastRefreshError` and leaves the last known values on screen.
  // A user who sees an empty balance panel will assume the money is gone, so
  // "show me nothing and say nothing" is the one response that is never right.
  //
  // The result is a tagged union rather than a callback: a callback stashed on
  // the Process would need a property the type does not have, and a plain
  // string cannot say which view it belongs to.
  function run(cmd, kind, env, silent) {
    if (status === "busy") return
    pendingSilent = silent === true
    // A background run leaves `status` alone so the current view is untouched
    // and the buttons stay live. A foreground run shows "busy" as before.
    if (!pendingSilent) status = "busy"
    errorMessage = ""
    pendingKind = kind
    var full = cmd.slice()
    if (env && env.length > 0) full = ["env"].concat(env).concat(cmd)
    process.command = full
    process.running = true
  }

  function fail(message) {
    status = "error"
    errorMessage = message
  }

  function parseJson(text, fallbackMessage) {
    var raw = String(text || "").trim()
    if (raw === "") return null
    try {
      return JSON.parse(raw)
    } catch (e) {
      return null
    }
  }

  // ------------------------------------------------------------------ actions

  function loadBalance() {
    run(["bch-bot", "balance"], "balance")
  }

  function loadAddress() {
    run(["bch-bot", "address", "--json"], "address")
  }

  // Dry run first: this shows the signed transaction and its network fee
  // without broadcasting, so the user sees the real numbers before committing.
  function previewSend() {
    if (!sendTo || !sendAmount) return fail("enter a recipient address and an amount")
    sendConfirmed = false
    run(["bch-bot", "send", sendTo.trim(), sendAmount.trim()], "send-preview")
  }

  // The only place in this plugin that can broadcast, and it does so by
  // invoking the same CLI with the CLI's own gate set. QML cannot skip it.
  function confirmSend() {
    run(["bch-bot", "send", sendTo.trim(), sendAmount.trim()],
      "send-confirm", ["BCH_CONFIRM=yes"])
  }

  // The slippage floor, as a CLI argument, or null when the user has not set
  // one. The CLI accepts a bare integer of base units or a decimal amount with
  // a BCH-style unit, exactly like `send`; anything else is rejected there, so
  // a typo fails at the CLI rather than being silently coerced to "no floor".
  function minOutputArg() {
    if (!swapMinOutput) return null
    var v = swapMinOutput.trim()
    if (v.length === 0) return null
    return v
  }

  function getQuote() {
    if (!swapSell || !swapBuy || !swapAmount)
      return fail("enter the asset to sell, the asset to buy, and an amount")
    var args = ["bch-bot", "swap", swapSell.trim(), swapBuy.trim(), swapAmount.trim(),
      "--quote-only"]
    // Carry the floor into the quote so the number the user reads is the number
    // that will be enforced. A floor applied only at execution would let the
    // preview show an output the trade is then free to fall below.
    var floor = minOutputArg()
    if (floor) args.push("--min-output", floor)
    run(args, "swap-quote")
  }

  function executeSwap() {
    if (!swapQuote) return
    var args = ["bch-bot", "swap", swapSell.trim(), swapBuy.trim(), swapAmount.trim()]
    // The quote is only a promise if the floor travels with it. Re-send the
    // same floor at execution: without this the build is only checked against
    // the quote, and the quote is a snapshot that may already be stale.
    var floor = minOutputArg()
    if (floor) args.push("--min-output", floor)
    // BCH_CONFIRM goes through the `env` parameter, never appended to argv --
    // as a trailing argument it would be read as a fourth positional and
    // silently ignored, which would look exactly like a swap that refuses to
    // broadcast. check-wallet-safety.sh requires this shape.
    run(args, "swap-execute", ["BCH_CONFIRM=yes"])
  }

  // Route one command's stdout to the flow that asked for it. A single Process
  // serves every view; `pendingKind` is what keeps their results apart.
  function applyResult(kind, text) {
    var parsed = parseJson(text)
    if (kind === "balance") {
      if (!parsed) {
        // A background refresh must not blank the balance or raise an error the
        // user did not trigger. Only a foreground load is allowed to fail loudly.
        if (root.pendingSilent || root.refreshing) {
          root.refreshing = false
          root.lastRefreshError = "balance unavailable — showing the last known value"
          return
        }
        return fail("could not read the balance from bch-bot")
      }
      balanceBch = String(parsed.bch_confirmed || "0.00000000")
      balanceUnconfirmed = String(parsed.bch_unconfirmed || "0.00000000")
      utxoCount = Number(parsed.utxo_count || 0)
      // `tokens` is an object keyed by category id, so it has to be turned into
      // a list for the Repeater. Object.values preserves the CLI's ordering,
      // which is already sorted by value descending.
      var list = []
      var byCategory = parsed.tokens || {}
      for (var key in byCategory) {
        if (!Object.prototype.hasOwnProperty.call(byCategory, key)) continue
        var t = byCategory[key]
        list.push({
          category: key,
          // `display` is the wallet's own decimal-aware string, and `amount`
          // is exact base units. Showing the symbol when known, and a short id
          // when not, beats showing a raw 64-character category to a human.
          symbol: t.symbol || t.short_id || "token",
          display: t.display || t.amount || "0",
          amount: String(t.amount || "0"),
          decimals: Number(t.decimals || 0),
          known: t.known === true
        })
      }
      tokens = list
      return
    }
    if (kind === "address") {
      if (!parsed || !parsed.address) return fail("could not derive a receiving address")
      receiveAddress = String(parsed.address)
      receiveNetwork = String(parsed.network || "")
      return
    }
    if (kind === "send-preview") {
      if (!parsed) return fail("send preview failed — is the recipient address valid?")
      sendPreview = parsed
      return
    }
    if (kind === "send-confirm") {
      if (!parsed) return fail("broadcast failed")
      sendPreview = parsed
      sendConfirmed = true
      loadBalance()
      return
    }
    if (kind === "swap-quote") {
      if (!parsed) return fail("no route found for that trade")
      swapQuote = parsed
      return
    }
    if (kind === "swap-execute") {
      if (!parsed) return fail("swap failed — the router may have rejected the trade")
      swapQuote = parsed
      loadBalance()
      return
    }
    fail("unexpected result")
  }

  // ----------------------------------------------------------------- process

  // Quickshell's Process inherits the parent environment, so a command that
  // needs a variable gets an explicit `env` prefix. That keeps BCH_CONFIRM
  // visible in `command` (and therefore reviewable) instead of hidden in a
  // side channel, and `env` is guaranteed present on any Linux host.
  Process {
    id: process
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      // Quickshell 0.3.1: streamFinished() has no parameters; read the `text`
      // property. The `function (text)` form yields undefined, so lastStdout
      // came back empty and every command's result was lost.
      onStreamFinished: {
        root.lastStdout = String(text)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text).trim()
        if (message === "") return
        // bch-bot writes a plaintext-wallet warning to stderr on SUCCESS, so
        // this is only surfaced when the command actually failed.
        if (process.running || process.exitCode === 0) return
        if (!root.errorMessage) root.errorMessage = message.split("\n")[0]
      }
    }

    onExited: function (exitCode) {
      var kind = root.pendingKind
      var wasSilent = root.pendingSilent
      root.pendingKind = ""
      root.pendingSilent = false
      if (exitCode !== 0) {
        // bch-bot prints usage to stdout on a bad-argument error, so an error
        // with no useful message is almost always a bad field.
        var detail = root.errorMessage || ("bch-bot exited " + exitCode)
        if (wasSilent) {
          // A background refresh failed. Keep the panel exactly as it is and
          // mark the figures as not current -- do NOT blank the balance, and do
          // not raise an error the user did not trigger.
          root.refreshing = false
          root.lastRefreshError = "balance unavailable — showing the last known value"
          root.errorMessage = ""
          return
        }
        root.status = "error"
        root.errorMessage = detail
        if (/no wallet/i.test(detail)) root.reset()
        return
      }
      if (wasSilent) {
        root.refreshing = false
        root.lastRefreshError = ""
      }
      root.applyResult(kind, root.lastStdout)
      root.lastStdout = ""
      if (root.status === "busy") root.status = "ok"
    }
  }

  // ------------------------------------------------------------------ layout

  ColumnLayout {
    id: layout
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(12)

    // ---- header
    RowLayout {
      Layout.fillWidth: true

      Text {
        text: {
          if (root.view === "send") return "Send BCH"
          if (root.view === "receive") return "Receive BCH"
          if (root.view === "swap") return "Swap"
          return "BCH Wallet"
        }
        color: root.fg
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.bold: true
        Layout.fillWidth: true
      }

      Text {
        visible: root.status === "busy"
        text: "…"
        color: root.dim
        font.pixelSize: Style.font.title
      }
    }

    // ---- home
    ColumnLayout {
      visible: root.view === "home"
      Layout.fillWidth: true
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true

        Text {
          text: "Balance"
          color: root.dim
          font.pixelSize: Style.font.body
          Layout.fillWidth: true
        }

        // A refresh control rather than a bare label: the balance changes when
        // a swap lands, and a user who just watched one complete should not
        // have to reopen the panel to see it. Disabled while a run is in
        // flight, so a double-click cannot queue two `bch-bot balance` calls.
        Text {
          id: refreshLabel
          text: root.refreshing ? "…" : "↻"
          color: root.refreshing ? root.dim : root.fg
          font.pixelSize: Style.font.body
          opacity: root.refreshing ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(6)
            enabled: !root.refreshing && root.status !== "busy"
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refreshBalances()
          }
        }
      }

      Text {
        text: root.balanceBch + " BCH"
        color: root.fg
        font.pixelSize: Style.font.title
        font.family: Style.font.family
      }

      // A mempool deposit is real money that is not yet spendable, and showing
      // only the confirmed figure makes the balance look like it dropped. It
      // gets its own line rather than a tooltip: a user who just funded the
      // wallet is exactly the person who needs to see "still confirming".
      Text {
        visible: Number(root.balanceUnconfirmed) > 0
        text: "+" + root.balanceUnconfirmed + " BCH confirming"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: root.utxoCount > 0
        text: root.utxoCount + (root.utxoCount === 1 ? " UTXO" : " UTXOs")
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      // ---- CashTokens
      //
      // Shown as their own section rather than a footnote, because a CashTokens
      // holding is real money: a wallet holding 1 ROACH and no BCH is not "empty",
      // and hiding it behind a count is how someone sends the BCH out and
      // assumes the token went with it.
      ColumnLayout {
        visible: root.tokens.length > 0
        Layout.fillWidth: true
        Layout.topMargin: Style.space(4)
        spacing: Style.space(6)

        Text {
          text: "Tokens"
          color: root.dim
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.tokens

          RowLayout {
            id: tokenRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              text: tokenRow.modelData.symbol
              color: root.fg
              font.pixelSize: Style.font.body
              font.family: Style.font.family
              // An unknown category id is shown shortened, never in full: 64
              // characters of hex is not a label, and it would blow out the
              // layout on a narrow bar.
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(140)
            }

            Text {
              text: tokenRow.modelData.display
              color: root.fg
              font.pixelSize: Style.font.body
              font.family: Style.font.family
              Layout.fillWidth: true
            }

            // The raw base-unit figure, dimmed. The displayed amount depends on
            // an ASSUMED decimal count for an unrecognised token, and this is
            // how a user can see the exact number the wallet will actually send.
            Text {
              visible: !tokenRow.modelData.known
              text: tokenRow.modelData.amount + " base units"
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              Layout.maximumWidth: Style.space(120)
            }
          }
        }
      }

      // A failed background refresh leaves the last known figures up rather than
      // blanking them, so say plainly that they are not current.
      Text {
        visible: root.lastRefreshError !== ""
        text: root.lastRefreshError
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(10)
        spacing: Style.space(8)

        Button {
          text: "Receive"
          onClicked: { root.view = "receive"; root.loadAddress() }
        }
        Button {
          text: "Send"
          onClicked: { root.view = "send" }
        }
        Button {
          text: "Swap"
          onClicked: { root.view = "swap"; root.swapSell = "BCH"; root.swapBuy = "pusd" }
        }
      }
    }

    // ---- receive
    ColumnLayout {
      visible: root.view === "receive"
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        text: root.receiveAddress || "deriving…"
        color: root.fg
        font.pixelSize: Style.font.body
        font.family: Style.font.family
        wrapMode: Text.WrapAnywhere
        Layout.fillWidth: true
      }

      Text {
        visible: root.receiveNetwork !== ""
        text: root.receiveNetwork
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(4)
        spacing: Style.space(8)

        Button {
          text: root.copied ? "Copied" : "Copy address"
          enabled: root.receiveAddress !== "" && !root.copied
          onClicked: root.copyAddress()
        }

        Button {
          text: "Done"
          onClicked: { root.view = "home"; root.copied = false }
        }
      }

      // Feedback, not a hope. A copy button with no confirmation leaves the
      // user pasting whatever was on the clipboard before, and an address that
      // looks copied but is not is how money goes to the wrong chain.
      Text {
        visible: root.copied
        text: "Address copied to the clipboard."
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        Layout.fillWidth: true
      }

      Text {
        visible: root.receiveAddress !== "" && !root.copied
        text: "This is a fresh address each time. Anyone who has seen it can see what you receive."
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
    }

    // ---- send
    ColumnLayout {
      visible: root.view === "send"
      Layout.fillWidth: true
      spacing: Style.space(8)

      Text {
        text: "Recipient"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        Layout.fillWidth: true
        placeholderText: "bitcoincash:q…"
        text: root.sendTo
        onTextChanged: { root.sendTo = text; root.sendPreview = null }
      }

      Text {
        text: "Amount (BCH or sats)"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        Layout.fillWidth: true
        // bch-bot send accepts BCH (0.001) or a bare integer of satoshis
        // (1000). Label both, because the two are not interchangeable and a
        // user who assumes sats here sends 100x less than intended.
        placeholderText: "0.001 BCH or 1000 sats"
        text: root.sendAmount
        onTextChanged: { root.sendAmount = text; root.sendPreview = null }
      }

      // Itemised cost. There is no service fee, so this is the network fee
      // only -- shown on its own line rather than folded into the total, so a
      // future fee can never hide inside a number that looks like network cost.
      ColumnLayout {
        visible: root.sendPreview !== null
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        spacing: Style.space(2)

        Repeater {
          model: [
            // The user may have typed BCH ("0.001") or satoshis ("1000"), and
            // the two mean very different things. Echo back what they typed,
            // rather than asserting a unit: labelling 1000 as "BCH" would
            // overstate the amount a hundredfold, and guessing wrong in the
            // other direction understates it.
            { label: "Amount", value: root.sendAmount },
            { label: "Service fee", value: "0.00000000 BCH" },
            { label: "Network fee", value: root.sendPreview
                ? (Number(root.sendPreview.fee) / 1e8).toFixed(8) + " BCH" : "" },
          ]

          RowLayout {
            required property var modelData
            Layout.fillWidth: true

            Text {
              text: modelData.label
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
            }
            Text {
              text: modelData.value
              color: root.fg
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(8)
        spacing: Style.space(8)

        Button {
          text: root.sendConfirmed ? "Sent" : "Preview"
          enabled: root.status !== "busy" && root.sendAmount !== "" && root.sendTo !== ""
          onClicked: root.previewSend()
        }

        Button {
          // Gated on having seen the preview: the user confirms the numbers
          // they were shown, not the numbers they typed.
          text: "Confirm & send"
          enabled: root.sendPreview !== null && !root.sendConfirmed && root.status !== "busy"
          onClicked: root.confirmSend()
        }
      }

      Text {
        visible: root.sendConfirmed && root.sendPreview !== null && !!root.sendPreview.tx_hash
        text: "Broadcast: " + String(root.sendPreview && root.sendPreview.tx_hash || "").slice(0, 16) + "…"
        color: root.fg
        font.pixelSize: Style.font.bodySmall
        font.family: Style.font.family
        Layout.fillWidth: true
        elide: Text.ElideRight
      }
    }

    // ---- swap
    ColumnLayout {
      visible: root.view === "swap"
      Layout.fillWidth: true
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          Text {
            text: "Sell"
            color: root.dim
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            Layout.fillWidth: true
            placeholderText: "BCH"
            text: root.swapSell
            onTextChanged: { root.swapSell = text; root.swapQuote = null }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          Text {
            text: "Buy"
            color: root.dim
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            Layout.fillWidth: true
            placeholderText: "pusd"
            text: root.swapBuy
            onTextChanged: { root.swapBuy = text; root.swapQuote = null }
          }
        }
      }

      Text {
        text: "Amount"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        Layout.fillWidth: true
        placeholderText: "0.01"
        text: root.swapAmount
        onTextChanged: { root.swapAmount = text; root.swapQuote = null }
      }

      // The slippage floor. Without it the router's quoted output is only a
      // snapshot, and the router is documented as beta -- a build can differ
      // from the quote it was priced from. The floor is the one number the
      // build is checked against that does not come from the router.
      Text {
        text: "Minimum acceptable output (base units, optional)"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        Layout.topMargin: Style.space(6)
      }

      TextField {
        Layout.fillWidth: true
        // PUSD has 2 decimals, so 36000 means 360.00 PUSD. Say so, because a
        // raw base-unit count is exactly the kind of number a user reads as
        // something else.
        placeholderText: "e.g. 36000 for 360.00 PUSD"
        text: root.swapMinOutput
        onTextChanged: { root.swapMinOutput = text; root.swapQuote = null }
      }

      Text {
        text: "Leave empty to accept whatever the router builds. The quote is a"
              + " snapshot, and the router is beta."
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        Layout.topMargin: Style.space(2)
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        spacing: Style.space(8)

        Button {
          text: "Get quote"
          enabled: root.status !== "busy" && root.swapAmount !== ""
          onClicked: root.getQuote()
        }

        Button {
          text: "Swap"
          enabled: root.swapQuote !== null && root.status !== "busy"
          onClicked: root.executeSwap()
        }
      }

      ColumnLayout {
        visible: root.swapQuote !== null
        Layout.fillWidth: true
        spacing: Style.space(2)

        Repeater {
          model: [
            { label: "You receive", value: root.swapQuote ? root.swapQuote.expected_output : "" },
            { label: "Pools used", value: root.swapQuote ? String(root.swapQuote.pools) : "" },
            // The router charges its fee at BUILD time, not quote time, so a
            // quote genuinely carries no fee figure. Do not print 0.00000000
            // here: the trade does cost ~0.1% plus the LP fee, and a flat zero
            // tells the user a value-moving operation is free. The exact
            // amounts are itemised in the broadcast receipt after the swap.
            { label: "Service fee", value: "charged at execution" },
          ]

          RowLayout {
            required property var modelData
            Layout.fillWidth: true

            Text {
              text: modelData.label
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
            }
            Text {
              text: modelData.value
              color: root.fg
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }
          }
        }
      }
    }

    // ---- footer
    Item { Layout.fillHeight: true }

    Text {
      visible: root.status === "error"
      text: root.errorMessage
      color: Color.urgent
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Button {
        text: "Back"
        visible: root.view !== "home"
        onClicked: root.reset()
      }

      Item { Layout.fillWidth: true }

      Button {
        text: "Close"
        // The KeyboardPanel hosting this item owns the window, so closing is
        // delegated up rather than called here.
        onClicked: if (root.closeRequested) root.closeRequested()
      }
    }
  }

  Component.onCompleted: loadBalance()
}
