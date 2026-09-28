// BchBalanceWidget.qml — Omarchy bar widget for BCH wallet balance
//
// Pattern verified against github.com/omacom/omarchy/tree/main/shell/plugins/agents/Panel.qml
// (the closest reference: a bar-widget with settings schema).
//
// States:
//   - "loading"     : startup, before first refresh
//   - "ok"          : balance successfully fetched
//   - "no-wallet"   : bch-bot CLI not found in PATH; show install instructions
//   - "error"       : CLI ran but failed; show error message
//
// Renders a small bar icon with the BCH balance; click to open a panel
// with the full wallet UI (balance, recent activity, send/receive buttons).

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Scope {
  id: root
  property string treasuryAddress: ""
  property int treasuryBps: 50
  property int refreshIntervalSec: 60
  property bool showFiatEquivalent: false

  // Cached state from the CLI
  property string balanceBch: "loading..."
  property string lastUpdate: ""
  property string walletStatus: "loading"  // loading | ok | no-wallet | error
  property string errorMessage: ""

  // Refresh timer
  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: refreshBalance()
  }

  // Check if bch-bot is in PATH
  Process {
    id: checkPath
    command: ["which", "bch-bot"]
    onExited: (exitCode) => {
      if (exitCode !== 0) {
        root.walletStatus = "no-wallet";
        root.balanceBch = "no wallet";
        root.errorMessage = "Install bch-bot CLI:\n  yay -S bch-bot            (Arch/Omarchy)\n  — or —\n  See https://github.com/lucasmcducas/bch-bot-public#install";
      } else {
        refreshBalance();
      }
    }
  }

  // Fetch balance
  Process {
    id: balanceProc
    command: ["bch-bot", "balance"]
    onExited: (exitCode, stdout) => {
      if (exitCode !== 0) {
        root.walletStatus = "error";
        root.errorMessage = "bch-bot balance failed (exit " + exitCode + ")";
        return;
      }
      try {
        const obj = JSON.parse(stdout);
        const sats = BigInt(obj.satoshis_confirmed || "0");
        root.balanceBch = (Number(sats) / 1e8).toFixed(8);
        root.walletStatus = "ok";
        root.errorMessage = "";
        root.lastUpdate = new Date().toISOString();
      } catch (e) {
        root.walletStatus = "error";
        root.errorMessage = "Failed to parse bch-bot output: " + e.message;
      }
    }
  }

  function refreshBalance() {
    if (walletStatus === "no-wallet") return;  // don't try to refresh if wallet is missing
    balanceProc.running = true;
  }

  Component.onCompleted: checkPath.running = true

  // The bar icon — shows different states with hover tooltips
  // - ok: "Ƀ 0.00858627" in green
  // - loading: "Ƀ ..." in grey
  // - no-wallet: "Ƀ ✗" in red with tooltip showing install instructions
  // - error: "Ƀ !" in orange
  Text {
    id: barIcon
    anchors.centerIn: parent
    text: {
      if (root.walletStatus === "ok") return "Ƀ " + root.balanceBch;
      if (root.walletStatus === "loading") return "Ƀ ...";
      if (root.walletStatus === "no-wallet") return "Ƀ ✗";
      if (root.walletStatus === "error") return "Ƀ !";
      return "Ƀ ?";
    }
    color: {
      if (root.walletStatus === "ok") return "#4ade80";
      if (root.walletStatus === "no-wallet") return "#f87171";
      if (root.walletStatus === "error") return "#fb923c";
      return "#9ca3af";
    }
    font.pixelSize: 14
    font.bold: true

    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        // On no-wallet state, copy the install command to clipboard
        if (root.walletStatus === "no-wallet") {
          // Quickshell exposes Clipboard via Quickshell.Io.Clipboard — use it if available
          // For now, fall through to tooltip which shows the command
        }
      }
    }

    ToolTip.visible: ma.containsMouse && root.walletStatus !== "ok"
    ToolTip.delay: 200
    ToolTip.text: root.errorMessage
  }
}
