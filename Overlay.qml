import QtQuick
import QtQuick.Layouts
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
  property bool evdevLive: false
  property var hyprEntries: []
  property int nextChordId: 1
  property bool opened: chordModel.count > 0

  readonly property bool placeRight: position.indexOf("right") !== -1
  readonly property bool placeBottom: position.indexOf("bottom") !== -1
  readonly property int edgeMargin: Style.gapsOut + Style.space(16)
  readonly property int topClearance: Style.bar.sizeHorizontal + Style.gapsOut + Style.space(16)
  readonly property int pad: Style.space(16)
  readonly property int borderWidth: Math.max(1, Style.space(2))
  readonly property int stackSpacing: Style.space(8)
  readonly property int cardHeight: borderWidth + pad + fontSize + pad + borderWidth

  function applySettings(text) {
    var next = Model.parseShellJson(text, root.pluginId)
    var wasEnabled = root.overlaysEnabled
    root.overlaysEnabled = next.enabled
    root.fontSize = next.fontSize
    root.durationMs = next.durationMs
    root.position = next.position
    if (!root.overlaysEnabled) root.close()
    else if (chordModel.count > 0)
      root.applyChordList(Model.trimChords(root.snapshot(), root.maxStackedChords()))
    if (wasEnabled !== root.overlaysEnabled) root.syncCompanionBinds()
  }

  function snapshot() {
    var out = []
    for (var i = 0; i < chordModel.count; i++) {
      var row = chordModel.get(i)
      out.push({
        id: row.token,
        text: String(row.text || ""),
        durationMs: row.durationMs,
        shownAt: row.shownAt
      })
    }
    out.sort(function(a, b) { return Number(a.shownAt) - Number(b.shownAt) })
    return out
  }

  function maxStackedChords() {
    var limit = 0
    try {
      var screens = Quickshell.screens
      var count = screens ? screens.length : 0
      for (var i = 0; i < count; i++) {
        var screen = screens[i]
        if (!screen || !(screen.height > 0)) continue
        var available = screen.height - root.topClearance - root.edgeMargin
        var n = Model.stackedChordLimit(available, root.cardHeight, root.stackSpacing)
        if (limit === 0 || n < limit) limit = n
      }
    } catch (e) {
      limit = 0
    }
    return limit > 0 ? limit : 8
  }

  // Keep existing delegates when a chord is added or an older one expires.
  // Replacing the whole model would restart every card.
  function applyChordList(next) {
    var rows = (next || []).slice()
    // Column lays children out from the top. On a bottom corner the newest
    // chord is last so it sits on the edge; on a top corner it is first.
    if (!root.placeBottom) rows.reverse()
    var i = 0
    var n = 0
    while (i < chordModel.count && n < rows.length) {
      if (Number(chordModel.get(i).token) === Number(rows[n].id)) {
        i++
        n++
        continue
      }
      chordModel.remove(i)
    }
    while (chordModel.count > n)
      chordModel.remove(chordModel.count - 1)
    for (; n < rows.length; n++) {
      chordModel.append({
        token: rows[n].id,
        text: rows[n].text,
        durationMs: rows[n].durationMs,
        shownAt: rows[n].shownAt
      })
    }
  }

  function showCombo(text) {
    if (!root.overlaysEnabled) return
    var pushed = Model.pushChord(root.snapshot(), text, root.durationMs, Date.now(), root.nextChordId)
    if (!pushed.accepted) return
    root.nextChordId += 1
    root.applyChordList(Model.trimChords(pushed.chords, root.maxStackedChords()))
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
    chordModel.clear()
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

  ListModel {
    id: chordModel
  }

  Timer {
    interval: 100
    repeat: true
    running: chordModel.count > 0
    onTriggered: {
      var next = Model.expireChords(root.snapshot(), Date.now())
      if (next.length !== chordModel.count)
        root.applyChordList(next)
    }
  }

  Timer {
    id: listenerRestart
    interval: 1000
    onTriggered: {
      if (!listener.running) listener.running = true
    }
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

      // Newest chord sits in the corner. Older ones step away from it and
      // leave on their own timer. A column does the stacking; placing each
      // card by index left them on top of one another.
      ColumnLayout {
        id: stack
        spacing: root.stackSpacing
        anchors.right: root.placeRight ? parent.right : undefined
        anchors.left: root.placeRight ? undefined : parent.left
        anchors.bottom: root.placeBottom ? parent.bottom : undefined
        anchors.top: root.placeBottom ? undefined : parent.top
        anchors.rightMargin: root.placeRight ? root.edgeMargin : 0
        anchors.leftMargin: root.placeRight ? 0 : root.edgeMargin
        anchors.bottomMargin: root.placeBottom ? root.edgeMargin : 0
        anchors.topMargin: root.placeBottom ? 0 : root.topClearance

        Repeater {
          model: chordModel

          delegate: Item {
            id: slot
            required property int index
            required property string text

            readonly property int cardWidth: Math.max(1, root.borderWidth + root.pad + Math.ceil(labelMetrics.advanceWidth) + root.pad + root.borderWidth)
            property bool settled: false

            z: index
            Layout.alignment: root.placeRight ? Qt.AlignRight : Qt.AlignLeft
            Layout.preferredWidth: cardWidth
            Layout.preferredHeight: root.cardHeight
            implicitWidth: cardWidth
            implicitHeight: root.cardHeight

            Component.onCompleted: Qt.callLater(function() { slot.settled = true })

            Behavior on y {
              enabled: slot.settled
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            TextMetrics {
              id: labelMetrics
              font.family: Style.font.family
              font.pixelSize: root.fontSize
              font.bold: true
              text: slot.text
            }

            BorderSurface {
              id: card
              anchors.top: parent.top
              anchors.right: root.placeRight ? parent.right : undefined
              anchors.left: root.placeRight ? undefined : parent.left
              width: slot.cardWidth
              height: root.cardHeight
              color: Util.alpha(Color.background, 0.97)
              borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, root.borderWidth)
              radius: Style.cornerRadius
              opacity: 0

              Component.onCompleted: card.opacity = 1

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
                text: slot.text
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
    }
  }
}
