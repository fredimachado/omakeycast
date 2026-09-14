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

  // Single cursor shared by keyboard and mouse, matching Audio/Display:
  // first hjkl/arrow reveals the highlight, later keys move or nudge.
  property string focusSection: "header"
  property bool cursorActive: false

  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property bool durationHasCursor: cursorActive && focusSection === "duration"
  readonly property bool fontHasCursor: cursorActive && focusSection === "fontSize"
  readonly property bool positionHasCursor: cursorActive && focusSection === "position"
  readonly property bool previewHasCursor: cursorActive && focusSection === "preview"

  onOpenedChanged: {
    if (root.opened) return
    root.cursorActive = false
    root.focusSection = "header"
    positionDropdown.close()
  }

  function open() {
    root.controller.show()
  }

  function close() {
    positionDropdown.close()
    root.cursorActive = false
    root.focusSection = "header"
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
    if (entry.enabled) {
      previewTimer.restart()
      return
    }
    previewTimer.stop()
    if (values && values.enabled === false) root.hideOverlay()
  }

  function hideOverlay() {
    if (hideProc.running) hideProc.running = false
    hideProc.command = ["omarchy-shell", "omakeycast", "close"]
    hideProc.running = true
  }

  function preview() {
    if (!root.parsed.enabled) return
    if (previewProc.running) previewProc.running = false
    previewProc.command = ["omarchy-shell", "omakeycast", "show", '{"text":"Super + Return"}']
    previewProc.running = true
  }

  function setCursor(section) {
    root.cursorActive = true
    root.focusSection = section
  }

  function moveCursor(delta) {
    root.focusSection = Model.nextPanelSection(root.focusSection, delta)
  }

  function persistIfChanged(values) {
    if (!values) return
    for (var key in values) {
      if (values[key] !== root.parsed[key]) {
        root.persistSettings(values)
        return
      }
    }
  }

  function nudgeFocused(delta) {
    if (root.focusSection === "duration") {
      root.persistIfChanged({ duration: Model.nudgeDuration(root.parsed.duration, delta) })
      return
    }
    if (root.focusSection === "fontSize") {
      root.persistIfChanged({ fontSize: Model.nudgeFontSize(root.parsed.fontSize, delta) })
      return
    }
    if (root.focusSection === "position")
      root.persistIfChanged({ position: Model.cyclePosition(root.parsed.position, delta) })
  }

  function activateCursor() {
    if (root.focusSection === "header") {
      root.persistSettings({ enabled: !root.parsed.enabled })
      return
    }
    if (root.focusSection === "position") {
      positionDropdown.toggle()
      return
    }
    if (root.focusSection === "preview") root.preview()
  }

  Process {
    id: previewProc
  }

  Process {
    id: hideProc
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
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.nudgeFocused(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "o" || t === "O") {
          root.persistSettings({ enabled: !root.parsed.enabled })
          return
        }
        if ((t === "p" || t === "P") && root.parsed.enabled) root.preview()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(titleLabel.implicitHeight, overlaySwitch.implicitHeight)

          HoverHandler {
            onHoveredChanged: if (hovered) root.setCursor("header")
          }

          Text {
            id: titleLabel
            anchors.left: parent.left
            anchors.right: overlaySwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Omakeycast"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          ToggleSwitch {
            id: overlaySwitch
            checked: root.parsed.enabled
            foreground: root.foreground
            hasCursor: root.headerHasCursor
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.persistSettings({ enabled: !root.parsed.enabled })
            onHovered: function(isHovered) { if (isHovered) root.setCursor("header") }

            PanelToolTip {
              visible: overlaySwitch.containsMouse
              text: overlaySwitch.checked ? "Overlays on" : "Overlays off"
              fontFamily: root.fontFamily
            }
          }
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

          CursorSurface {
            id: durationRow
            width: parent.width
            height: durationSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.durationHasCursor
            foreground: root.foreground
            outline: true

            PanelSlider {
              id: durationSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0.5
              maximum: 10
              step: 0.5
              value: Math.max(0.5, Math.min(10, root.parsed.duration))
              onReleased: function(v) { root.persistSettings({ duration: Math.round(v * 2) / 2 }) }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) root.setCursor("duration")
            }
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

          CursorSurface {
            id: fontRow
            width: parent.width
            height: fontSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.fontHasCursor
            foreground: root.foreground
            outline: true

            PanelSlider {
              id: fontSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 12
              maximum: 64
              step: 1
              integer: true
              value: Math.max(12, Math.min(64, root.parsed.fontSize))
              onReleased: function(v) { root.persistSettings({ fontSize: Math.round(v) }) }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) root.setCursor("fontSize")
            }
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
          hasCursor: root.positionHasCursor
          onChanged: function(v) { root.persistSettings({ position: v }) }
          onHovered: function(isHovered) { if (isHovered) root.setCursor("position") }
        }

        Button {
          width: parent.width
          text: "Preview"
          fontFamily: root.fontFamily
          foreground: root.foreground
          bordered: true
          enabled: root.parsed.enabled
          hasCursor: root.previewHasCursor
          onClicked: root.preview()
          onHovered: function(isHovered) { if (isHovered) root.setCursor("preview") }
        }
      }
    }
  }
}
