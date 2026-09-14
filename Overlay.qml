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
  property bool accessDeniedNotified: false
  property bool opened: displayText !== ""

  readonly property bool placeRight: position.indexOf("right") !== -1
  readonly property bool placeBottom: position.indexOf("bottom") !== -1
  readonly property int edgeMargin: Style.gapsOut + Style.space(16)
  readonly property int topClearance: Style.bar.sizeHorizontal + Style.gapsOut + Style.space(16)
  readonly property int pad: Style.space(16)
  readonly property int borderWidth: Math.max(1, Style.space(2))
  readonly property int cardWidth: borderWidth + pad + Math.ceil(labelMetrics.advanceWidth) + pad + borderWidth
  readonly property int cardHeight: borderWidth + pad + fontSize + pad + borderWidth

  function applySettings(text) {
    var next = Model.parseShellJson(text, root.pluginId)
    root.fontSize = next.fontSize
    root.durationMs = next.durationMs
    root.position = next.position
  }

  function showCombo(text) {
    var label = String(text || "").replace(/^\s+|\s+$/g, "")
    if (!label) return
    root.displayText = label
    hideTimer.interval = root.durationMs
    hideTimer.restart()
  }

  function notifyAccessDenied() {
    if (root.accessDeniedNotified) return
    root.accessDeniedNotified = true
    var send = (root.omarchyPath || "/usr/share/omarchy") + "/bin/omarchy-notification-send"
    Quickshell.execDetached([
      send,
      "-u", "normal",
      "-g", "",
      "Omakeycast needs keyboard access",
      "sudo usermod -aG input $USER && log out"
    ])
  }

  function handleListenerLine(line) {
    var event = Model.parseListenerLine(line)
    if (!event) return
    if (event.type === "combo") {
      root.showCombo(event.text)
      return
    }
    if (event.type === "error" && event.code === "no-input-access")
      root.notifyAccessDenied()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.text) root.showCombo(String(payload.text))
  }

  function close() {
    root.displayText = ""
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
    id: labelMetrics
    font.family: Style.font.family
    font.pixelSize: root.fontSize
    font.bold: true
    text: root.displayText
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

        Text {
          anchors.fill: parent
          anchors.topMargin: card.borderTop + root.pad
          anchors.rightMargin: card.borderRight + root.pad
          anchors.bottomMargin: card.borderBottom + root.pad
          anchors.leftMargin: card.borderLeft + root.pad
          textFormat: Text.PlainText
          text: root.displayText
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: root.fontSize
          font.bold: true
          wrapMode: Text.NoWrap
          elide: Text.ElideRight
          maximumLineCount: 1
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
