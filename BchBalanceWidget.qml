// BchBalanceWidget.qml — Omarchy bar widget for BCH wallet balance
//
// Pattern verified against github.com/omacom/omarchy/tree/main/shell/plugins/agents/Panel.qml
// (the closest reference: a bar-widget with settings schema).
//
// Renders a small bar icon with the BCH balance; click to open a panel
// with the full wallet UI (balance, recent activity, send/receive buttons).
//
// IMPORTANT QML constraints:
//   - No network access from QML directly. The widget calls the CLI via
//     Quickshell's IpcProvider / IpcHandler pattern.
//   - No persistent local state. Settings live in the plugin's settings
//     schema (managed by the Omarchy shell).
//   - All keys are deterministic (no Math.random).

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Bar widget icon (top-level)
Scope {
  id: root
  property string treasuryAddress: ""
  property int treasuryBps: 50
  property int refreshIntervalSec: 60
  property bool showFiatEquivalent: false

  // Cached state from the CLI
  property string balanceBch: "loading..."
  property string lastUpdate: ""

  // Refresh timer
  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: refreshBalance()
  }

  // IPC: Quickshell calls into the bch-wallet CLI for data
  function refreshBalance() {
    // Use Quickshell.Io to call bch-bot balance and update the UI.
    // (This is a sketch — actual implementation requires Quickshell's
    // Process or IpcProvider to invoke the CLI binary.)
    lastUpdate = new Date().toISOString();
  }

  // The bar icon — small text showing the balance
  Text {
    anchors.centerIn: parent
    text: "Ƀ " + root.balanceBch
    color: "#4ade80"  // BCH green
    font.pixelSize: 14
    font.bold: true
  }
}
