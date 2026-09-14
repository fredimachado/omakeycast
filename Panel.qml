import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.fredimachado.omakeycast"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var parsed: Model.parseSettings(settings)
  readonly property color foreground: bar ? bar.foreground : Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function persistSettings(values) {
    var entry = Model.settingsPayload(root.settings, values, root.moduleName)
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    previewTimer.restart()
  }

  function preview() {
    if (previewProc.running) previewProc.running = false
    previewProc.command = ["omarchy-shell", "omakeycast", "show", '{"text":"Super + Return"}']
    previewProc.running = true
  }

  Process {
    id: previewProc
  }

  Timer {
    id: previewTimer
    interval: 220
    onTriggered: root.preview()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: positionDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "p" || t === "P") root.preview()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Text {
          width: parent.width
          text: "Omakeycast"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: "How long combos stay on screen, how large they are, and which corner they use."
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(durationHeader.implicitHeight, durationValue.implicitHeight)

            PanelSectionHeader {
              id: durationHeader
              text: "DURATION"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: durationValue
              textFormat: Text.PlainText
              text: Model.formatDuration(durationSlider.dragging ? durationSlider.liveValue : root.parsed.duration)
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: durationSlider
            bar: root.bar
            width: parent.width
            minimum: 0.5
            maximum: 10
            step: 0.5
            value: Math.max(0.5, Math.min(10, root.parsed.duration))
            onReleased: function(v) { root.persistSettings({ duration: Math.round(v * 2) / 2 }) }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(fontHeader.implicitHeight, fontValue.implicitHeight)

            PanelSectionHeader {
              id: fontHeader
              text: "FONT SIZE"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: fontValue
              textFormat: Text.PlainText
              text: Math.round(fontSlider.dragging ? fontSlider.liveValue : root.parsed.fontSize) + "px"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: fontSlider
            bar: root.bar
            width: parent.width
            minimum: 12
            maximum: 64
            step: 1
            integer: true
            value: Math.max(12, Math.min(64, root.parsed.fontSize))
            onReleased: function(v) { root.persistSettings({ fontSize: Math.round(v) }) }
          }
        }

        Dropdown {
          id: positionDropdown
          width: parent.width
          label: "Position"
          fontFamily: root.fontFamily
          foreground: root.foreground
          options: Model.POSITION_OPTIONS
          value: root.parsed.position
          onChanged: function(v) { root.persistSettings({ position: v }) }
        }

        Button {
          width: parent.width
          text: "Preview"
          fontFamily: root.fontFamily
          foreground: root.foreground
          bordered: true
          onClicked: root.preview()
        }
      }
    }
  }
}
