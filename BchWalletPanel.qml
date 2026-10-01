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

Panel {
  id: root
  moduleName: "io.github.lucasmcducas.bch-wallet"
  ipcTarget: "io.github.lucasmcducas.bch-wallet"
  manageIpc: true

  // ------------------------------------------------------------------- state

  // view: home | send | receive | swap
  property string view: "home"
  property string status: "idle"      // idle | busy | ok | error
  property string errorMessage: ""

  property string balanceBch: "0.00000000"
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
  property var swapQuote: null

  // Which flow a running command belongs to, so one Process can serve all of
  // them: balance | address | send-preview | send-confirm | swap-quote |
  // swap-execute.
  property string pendingKind: ""

  // Captured stdout, read once the process has exited. A Process has no
  // user-defined properties, so the result cannot be stashed on it.
  property string lastStdout: ""

  // ------------------------------------------------------------------ helpers

  readonly property color fg: barForeground
  readonly property color dim: Qt.darker(fg, 1.5)

  function reset() {
    view = "home"
    status = "idle"
    errorMessage = ""
    sendPreview = null
    sendConfirmed = false
    swapQuote = null
  }

  // Runs a bch-bot subcommand and routes the result to `applyResult`.
  // `env` is a list of KEY=VALUE pairs prefixed onto the command with env(1),
  // which keeps BCH_CONFIRM visible in the command line rather than hidden in
  // a side channel.
  //
  // The result is a tagged union rather than a callback: a callback stashed on
  // the Process would need a property the type does not have, and a plain
  // string cannot say which view it belongs to.
  function run(cmd, kind, env) {
    if (status === "busy") return
    status = "busy"
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

  function getQuote() {
    if (!swapSell || !swapBuy || !swapAmount)
      return fail("enter the asset to sell, the asset to buy, and an amount")
    run(["bch-bot", "swap", swapSell.trim(), swapBuy.trim(), swapAmount.trim(),
      "--quote-only"], "swap-quote")
  }

  function executeSwap() {
    if (!swapQuote) return
    run(["bch-bot", "swap", swapSell.trim(), swapBuy.trim(), swapAmount.trim()],
      "swap-execute", ["BCH_CONFIRM=yes"])
  }

  // Route one command's stdout to the flow that asked for it. A single Process
  // serves every view; `pendingKind` is what keeps their results apart.
  function applyResult(kind, text) {
    var parsed = parseJson(text)
    if (kind === "balance") {
      if (!parsed) return fail("could not read the balance from bch-bot")
      balanceBch = String(parsed.bch_confirmed || "0.00000000")
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
      onStreamFinished: function (text) {
        root.lastStdout = String(text || "")
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: function (text) {
        var message = String(text || "").trim()
        if (message === "") return
        // bch-bot writes a plaintext-wallet warning to stderr on SUCCESS, so
        // this is only surfaced when the command actually failed.
        if (process.running || process.exitCode === 0) return
        if (!root.errorMessage) root.errorMessage = message.split("\n")[0]
      }
    }

    onExited: function (exitCode) {
      var kind = root.pendingKind
      root.pendingKind = ""
      if (exitCode !== 0) {
        // bch-bot prints usage to stdout on a bad-argument error, so an error
        // with no useful message is almost always a bad field.
        var detail = root.errorMessage || ("bch-bot exited " + exitCode)
        root.status = "error"
        root.errorMessage = detail
        if (/no wallet/i.test(detail)) root.reset()
        return
      }
      root.applyResult(kind, root.lastStdout)
      root.lastStdout = ""
      if (root.status === "busy") root.status = "ok"
    }
  }

  // ------------------------------------------------------------------ layout

  ColumnLayout {
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

      Text {
        text: "Balance"
        color: root.dim
        font.pixelSize: Style.font.body
      }

      Text {
        text: root.balanceBch + " BCH"
        color: root.fg
        font.pixelSize: Style.font.title
        font.family: Style.font.family
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

      Text {
        visible: root.receiveAddress !== ""
        text: "Copy the address above, or scan it as a QR code from another wallet."
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
        text: "Amount (BCH)"
        color: root.dim
        font.pixelSize: Style.font.bodySmall
      }

      TextField {
        Layout.fillWidth: true
        placeholderText: "0.001"
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
            { label: "Amount", value: root.sendAmount + " BCH" },
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
            { label: "Service fee", value: "0.00000000 BCH" },
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
        onClicked: root.close()
      }
    }
  }

  Component.onCompleted: loadBalance()
}
