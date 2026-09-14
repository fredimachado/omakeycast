import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : Model.PLUGIN_ID
  readonly property string listenerPath: {
    var url = String(Qt.resolvedUrl("listen-keys.py"))
    if (url.indexOf("file://") === 0)
      return decodeURIComponent(url.substring(7))
    return url
  }

  property int fontSize: Model.DEFAULTS.fontSize
  property int durationMs: Model.DEFAULTS.duration * 1000
  property string position: Model.DEFAULTS.position
  property string displayText: ""
  property bool accessError: false
  property bool opened: displayText !== ""

  readonly property bool placeRight: position.indexOf("right") !== -1
  readonly property bool placeBottom: position.indexOf("bottom") !== -1
  readonly property int edgeMargin: Style.gapsOut + Style.space(16)
  readonly property int topClearance: Style.bar.sizeHorizontal + Style.gapsOut + Style.space(16)
  readonly property int pad: Style.space(16)
  readonly property int borderWidth: Math.max(1, Style.space(2))
  readonly property int contentWidth: Math.ceil(Math.max(titleMetrics.advanceWidth, detailMetrics.advanceWidth))
  readonly property int contentHeight: accessError
    ? fontSize + Style.space(4) + Math.max(12, Math.round(fontSize * 0.45))
    : fontSize
  readonly property int cardWidth: borderWidth + pad + contentWidth + pad + borderWidth
  readonly property int cardHeight: borderWidth + pad + contentHeight + pad + borderWidth
  readonly property string errorTitle: "Keyboard access denied"
  readonly property string errorDetail: "sudo usermod -aG input $USER && log out"

  function applySettings(text) {
    var next = Model.parseShellJson(text, root.pluginId)
    root.fontSize = next.fontSize
    root.durationMs = next.durationMs
    root.position = next.position
  }

  function showCombo(text) {
    var label = String(text || "").replace(/^\s+|\s+$/g, "")
    if (!label) return
    root.accessError = false
    root.displayText = label
    hideTimer.interval = root.durationMs
    hideTimer.restart()
  }

  function showError(code) {
    if (String(code) !== "no-input-access") return
    root.accessError = true
    root.displayText = root.errorTitle
    hideTimer.stop()
  }

  function handleListenerLine(line) {
    var event = Model.parseListenerLine(line)
    if (!event) return
    if (event.type === "combo") {
      root.showCombo(event.text)
      return
    }
    if (event.type === "error") {
      root.showError(event.code)
      return
    }
    if (event.type === "status" && event.keyboards > 0 && root.accessError)
      root.close()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.text) root.showCombo(String(payload.text))
  }

  function close() {
    root.displayText = ""
    root.accessError = false
    hideTimer.stop()
  }

  function toggle() {
    if (root.opened) root.close()
  }

  Timer {
    id: hideTimer
    interval: root.durationMs
    onTriggered: root.close()
  }

  Timer {
    id: listenerRestart
    interval: 1000
    onTriggered: {
      if (!listener.running) listener.running = true
    }
  }

  TextMetrics {
    id: titleMetrics
    font.family: Style.font.family
    font.pixelSize: root.fontSize
    font.bold: true
    text: root.accessError ? root.errorTitle : root.displayText
  }

  TextMetrics {
    id: detailMetrics
    font.family: Style.font.family
    font.pixelSize: Math.max(12, Math.round(root.fontSize * 0.45))
    text: root.accessError ? root.errorDetail : ""
  }

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applySettings(text())
    onLoadFailed: root.applySettings("{}")
    onFileChanged: reload()
  }

  Process {
    id: listener
    running: root.listenerPath.indexOf("listen-keys.py") !== -1
    command: ["/usr/bin/setpriv", "--pdeathsig", "TERM", "/usr/bin/python3", "-u", root.listenerPath]
    stdout: SplitParser {
      onRead: function(line) { root.handleListenerLine(line) }
    }
    onExited: listenerRestart.restart()
  }

  IpcHandler {
    target: "omakeycast"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string {
      root.close()
      return "ok"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "omakeycast"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      BorderSurface {
        id: card
        width: Math.max(1, root.cardWidth)
        height: Math.max(1, root.cardHeight)
        x: root.placeRight ? parent.width - width - root.edgeMargin : root.edgeMargin
        y: root.placeBottom ? parent.height - height - root.edgeMargin : root.topClearance
        color: Util.alpha(Color.background, 0.97)
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, root.borderWidth)
        radius: Style.cornerRadius
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.borderTop + root.pad
          anchors.rightMargin: card.borderRight + root.pad
          anchors.bottomMargin: card.borderBottom + root.pad
          anchors.leftMargin: card.borderLeft + root.pad
          spacing: Style.space(4)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.accessError ? root.errorTitle : root.displayText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: root.fontSize
            font.bold: true
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            maximumLineCount: 1
          }

          Text {
            visible: root.accessError
            width: parent.width
            textFormat: Text.PlainText
            text: root.errorDetail
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Math.max(12, Math.round(root.fontSize * 0.45))
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }
    }
  }
}
