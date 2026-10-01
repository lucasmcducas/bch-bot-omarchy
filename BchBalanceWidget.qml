// BchBalanceWidget.qml — Omarchy bar widget for the BCH wallet.
//
// Structure follows the first-party bar widgets (see
// shell/plugins/bar/widgets/Microphone.qml and SystemUpdate.qml in
// omacom/omarchy): a BarWidget root with a moduleName, one BarIconButton, a
// Timer for the refresh cadence, and a Process for the work. The host injects
// `bar`, which supplies theme colors, sizing, and the tooltip host -- a bare
// Item/Scope has none of that and renders nothing in the bar.
//
// The wallet itself is never touched from QML. This file spawns `bch-bot
// balance`, which prints one JSON object on stdout and owns every key,
// network call, and error message. Keeping signing and key handling in the
// CLI means a compromised or buggy shell cannot reach a private key.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.lucasmcducas.bch-wallet"

  // ---------------------------------------------------------------- settings

  // Clamped so a settings typo cannot spin the network every second.
  readonly property int refreshIntervalSec: Math.max(
    15, Math.min(3600, Number(setting("refreshIntervalSec", 60))))

  // ------------------------------------------------------------------ state

  // loading | ok | no-wallet | error
  property string status: "loading"
  property string balanceBch: ""
  property string utxoCount: "0"
  property string tokenCount: "0"
  property string errorMessage: ""

  // A missing CLI is a state the user cannot fix from the bar, and a slot
  // that reads "no wallet" on every login trains people to ignore the bar.
  // Stay hidden until the CLI answers; the reason is still on hover.
  readonly property bool slotVisible: status !== "no-wallet"

  // ----------------------------------------------------------------- display

  visible: slotVisible

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  readonly property string tooltip: {
    if (status === "ok") {
      var lines = ["Bitcoin Cash — " + balanceBch + " BCH",
        utxoCount + (utxoCount === "1" ? " UTXO" : " UTXOs")];
      if (tokenCount !== "0")
        lines.push(tokenCount + (tokenCount === "1" ? " token type" : " token types"));
      lines.push("Click to refresh · middle-click for the terminal");
      return lines.join("\n");
    }
    if (status === "no-wallet")
      return "bch-bot CLI not found.\nInstall it, then restart the shell:\n  yay -S bch-bot";
    if (status === "error")
      return "Balance unavailable\n" + errorMessage + "\nClick to retry";
    return "Bitcoin Cash — loading…";
  }

  // ------------------------------------------------------- pending-run slots

  // StdioCollector.onStreamFinished and Process.onExited both fire for a single
  // run, so the parsed result is staged here and committed once the process has
  // fully exited. Writing straight to `status` from the collector would let a
  // late collector overwrite a newer run's result, or commit a half-parsed
  // result while the process is still alive.
  property string pendingStatus: ""
  property string pendingBalance: ""
  property string pendingError: ""
  property string pendingUtxos: "0"
  property string pendingTokens: "0"

  // ------------------------------------------------------------------ process

  // bch-bot balance prints a JSON object to stdout and exits 1 on any failure
  // (no wallet, network down, bad address). Exit code is the reliable signal;
  // stdout is only meaningful on success.
  Process {
    id: balanceProcess
    running: false

    command: ["bch-bot", "balance"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        var raw = String(text || "").trim()
        if (raw === "") {
          root.pendingStatus = "error"
          root.pendingError = "no output"
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.pendingBalance = String(parsed.bch_confirmed || "0.00000000")
          root.pendingUtxos = String(parsed.utxo_count === undefined ? "0" : parsed.utxo_count)
          root.pendingTokens = String(parsed.token_categories_ft === undefined
            ? "0" : parsed.token_categories_ft)
          root.pendingStatus = "ok"
          root.pendingError = ""
        } catch (e) {
          root.pendingStatus = "error"
          root.pendingError = "could not parse bch-bot output"
        }
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(text) {
        var message = String(text || "").trim()
        if (message !== "") root.pendingError = message.split("\n")[0]
      }
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var message = root.pendingError || ("bch-bot balance exited " + exitCode)
        // Only claim "no wallet" when the CLI actually said so. Treating any
        // non-zero exit as a missing wallet would hide network outages behind
        // a reinstall prompt.
        root.status = /no wallet/i.test(message) ? "no-wallet" : "error"
        root.errorMessage = message
      } else if (root.pendingStatus === "ok") {
        root.balanceBch = root.pendingBalance
        root.utxoCount = root.pendingUtxos
        root.tokenCount = root.pendingTokens
        root.status = "ok"
        root.errorMessage = ""
      } else {
        root.status = "error"
        root.errorMessage = root.pendingError || "bch-bot produced no balance"
      }

      root.pendingStatus = ""
      root.pendingBalance = ""
      root.pendingError = ""
    }
  }

  // ------------------------------------------------------------------ actions

  function refresh() {
    if (balanceProcess.running) return
    root.pendingStatus = ""
    root.pendingBalance = ""
    root.pendingError = ""
    balanceProcess.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  // ------------------------------------------------------------------ content

  // Icon and label sit in an explicit row: the bar places each widget in its
  // own slot, and a bare anchored Text has no row to sit in.
  Row {
    id: row
    spacing: 6

    BarIconButton {
      id: button
      bar: root.bar
      text: "💰"
      active: root.status === "ok" && root.balanceBch !== "" && root.balanceBch !== "0.00000000"
      dimmed: root.status !== "ok"
      tooltipText: root.tooltip

      onPressed: function(pressedButton) {
        if (pressedButton === Qt.MiddleButton) {
          // Middle-click is the first-party convention for opening the real
          // app behind a widget (SystemUpdate launches omarchy-update).
          if (root.bar)
            root.bar.run("omarchy-launch-floating-terminal-with-presentation bch-bot balance")
          return
        }
        root.refresh()
      }
    }

    // Eight decimals is a wallet address, not a glanceable figure; truncating
    // keeps the bar stable and the tooltip keeps the exact value.
    Text {
      id: label
      visible: root.status === "ok"
      anchors.verticalCenter: button.verticalCenter

      text: root.balanceBch === "0.00000000" ? "0" : root.balanceBch
      color: root.bar ? root.bar.barForeground : "#ffffff"
      font.pixelSize: Math.round(root.barSize * 0.42)
      font.family: root.bar ? root.bar.fontFamily : "sans-serif"
      elide: Text.ElideRight
      maximumLineCount: 1
    }
  }
}
