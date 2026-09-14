import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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

  property bool overlaysEnabled: Model.DEFAULTS.enabled
  property int fontSize: Model.DEFAULTS.fontSize
  property int durationMs: Model.DEFAULTS.duration * 1000
  property string position: Model.DEFAULTS.position
  property string displayText: ""
  property bool evdevLive: false
  property var hyprEntries: []
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
    var wasEnabled = root.overlaysEnabled
    root.overlaysEnabled = next.enabled
    root.fontSize = next.fontSize
    root.durationMs = next.durationMs
    root.position = next.position
    if (!root.overlaysEnabled) root.close()
    if (wasEnabled !== root.overlaysEnabled) root.syncCompanionBinds()
  }

  function showCombo(text) {
    if (!root.overlaysEnabled) return
    var label = String(text || "").replace(/^\s+|\s+$/g, "")
    if (!label) return
    root.displayText = label
    hideTimer.interval = root.durationMs
    hideTimer.restart()
  }

  function setEvdevLive(next) {
    var enabled = next === true
    if (root.evdevLive === enabled) return
    root.evdevLive = enabled
    root.syncCompanionBinds()
  }

  function applyHyprBinds(text) {
    root.hyprEntries = Model.hyprBindEntries(text)
    root.syncCompanionBinds()
  }

  function syncCompanionBinds() {
    var lua = Model.companionLua((!root.overlaysEnabled || root.evdevLive) ? [] : root.hyprEntries)
    if (evalProc.running) evalProc.running = false
    evalProc.command = ["hyprctl", "eval", lua]
    evalProc.running = true
  }

  function handleListenerLine(line) {
    var event = Model.parseListenerLine(line)
    if (!event) return
    if (event.type === "combo") {
      if (root.evdevLive) root.showCombo(event.text)
      return
    }
    if (event.type === "status" && event.keyboards > 0) {
      root.setEvdevLive(true)
      return
    }
    if (event.type === "error" && event.code === "no-input-access")
      root.setEvdevLive(false)
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

  Component.onCompleted: bindQuery.running = true
  Component.onDestruction: {
    if (evalProc.running) evalProc.running = false
    evalProc.command = ["hyprctl", "eval", Model.companionLua([])]
    evalProc.running = true
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
    id: bindQuery
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHyprBinds(text)
    }
  }

  Process {
    id: evalProc
    command: ["hyprctl", "eval", "--"]
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      if (String(event.name) === "configreloaded") bindQuery.running = true
    }
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
    function combo(text: string): string {
      root.showCombo(text)
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
