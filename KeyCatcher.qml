import QtQuick
import "Model.js" as Model

// Same contract as qs.Ui.PanelKeyCatcher (Audio/Display/Dropbox), with one
// extra: letter keys match event.key and evdev scan codes, not only
// event.text. Layer-shell often delivers j/k/h/l with empty text.
Item {
  id: root

  property bool blocked: false

  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal closeRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return

    var letter = Model.panelKeyLetter(event.key, event.text, event.nativeScanCode)

    if (event.key === Qt.Key_Escape) {
      closeRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down || letter === "j") {
      moveRequested(0, 1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Up || letter === "k") {
      moveRequested(0, -1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Right || letter === "l") {
      moveRequested(1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Left || letter === "h") {
      moveRequested(-1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Space) {
      activateRequested(); event.accepted = true; return
    }
    if (letter) {
      textKey(letter)
      event.accepted = true
    }
  }
}
