// BchCommand.qml — command-kind entry point for BCH wallet commands
//
// Invoked by the Omarchy shell via `omarchy bch-wallet <subcommand>` (e.g.
// when the user types `omarchy bch-wallet send <addr> <amount>` in the
// command launcher, or when a menu entry calls it).
//
// Pattern: command-kind plugins are QML roots that expose IPC handlers.
// The shell invokes them by ID and reads the result via Quickshell's IpcProvider.
//
// Subcommands the wallet supports:
//   send <address> <sats>   — build + sign + broadcast (with BCH_CONFIRM gate)
//   receive                 — show receiving address + QR
//   balance                 — show current balance
//   history                 — show recent tx history
//   stake                   — stake PUSD (if wallet has any)
//   swap <supply> <demand>  — quote a Cauldron swap (no broadcast)
//   sweep                   — consolidate dust UTXOs

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  // Process handles for each subcommand
  property var processes: ({})

  function runSubcommand(args, callback) {
    // Build the CLI command: `bch-wallet <args...>`
    // Note: BCH_CONFIRM is passed through env only when user wants to broadcast.
    var proc = processes[args[0] || "balance"];
    // (Actual implementation uses Quickshell.Io.Process to spawn bch-wallet.)
  }

  // IPC handler — shell invokes via `omarchy bch-wallet send ...`
  IpcHandler {
    target: "bchWallet"
    function send(address: string, sats: string): string {
      // Placeholder — actual implementation calls bch-wallet send via Process.
      return "send: " + address + " " + sats;
    }
    function receive(): string {
      return "receive: showing QR...";
    }
    function balance(): string {
      return "balance: ...";
    }
  }
}
