const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.deepEqual(Model.parseSettings(null), {
  enabled: true,
  duration: 2,
  durationMs: 2000,
  fontSize: 28,
  position: "bottom-right"
})

assert.equal(Model.parseSettings({ duration: 1.5 }).durationMs, 1500)
assert.equal(Model.parseSettings({ duration: 0 }).duration, 0.25)
assert.equal(Model.parseSettings({ duration: 99 }).duration, 30)
assert.equal(Model.parseSettings({ fontSize: 18.6 }).fontSize, 19)
assert.equal(Model.parseSettings({ fontSize: 4 }).fontSize, 12)
assert.equal(Model.parseSettings({ position: "TOP_LEFT" }).position, "top-left")
assert.equal(Model.parseSettings({ position: "center" }).position, "bottom-right")
assert.equal(Model.parseSettings({ enabled: false }).enabled, false)
assert.equal(Model.parseSettings({ enabled: "false" }).enabled, true)

const shell = JSON.stringify({
  version: 1,
  plugins: [
    { id: "other.plugin", duration: 9 },
    { id: Model.PLUGIN_ID, enabled: false, duration: 3, fontSize: 40, position: "bottom-left" }
  ]
})
const fromShell = Model.parseShellJson(shell)
assert.equal(fromShell.enabled, false)
assert.equal(fromShell.duration, 3)
assert.equal(fromShell.fontSize, 40)
assert.equal(fromShell.position, "bottom-left")
assert.deepEqual(Model.parseShellJson("not-json"), Model.parseSettings(null))
assert.deepEqual(Model.parseShellJson('{"plugins":[]}'), Model.parseSettings(null))

const fromBar = Model.parseShellJson(JSON.stringify({
  version: 1,
  bar: {
    layout: {
      right: [{ id: Model.PLUGIN_ID, duration: 4, fontSize: 32, position: "top-left" }]
    }
  },
  plugins: [{ id: Model.PLUGIN_ID, duration: 9 }]
}))
assert.equal(fromBar.duration, 4)
assert.equal(fromBar.fontSize, 32)
assert.equal(fromBar.position, "top-left")

const fromPluginsWhenBarBare = Model.parseShellJson(JSON.stringify({
  version: 1,
  bar: { layout: { right: [{ id: Model.PLUGIN_ID }] } },
  plugins: [{ id: Model.PLUGIN_ID, duration: 3, fontSize: 40, position: "bottom-left" }]
}))
assert.equal(fromPluginsWhenBarBare.duration, 3)
assert.equal(fromPluginsWhenBarBare.fontSize, 40)
assert.equal(fromPluginsWhenBarBare.position, "bottom-left")

const payload = Model.settingsPayload({ duration: 3 }, { fontSize: 40 }, Model.PLUGIN_ID)
assert.equal(payload.id, Model.PLUGIN_ID)
assert.equal(payload.duration, 3)
assert.equal(payload.fontSize, 40)
assert.equal(payload.position, "bottom-right")
assert.equal(payload.enabled, true)
assert.equal(Model.settingsPayload({ enabled: false }, {}, Model.PLUGIN_ID).enabled, false)
assert.equal(Model.formatDuration(2), "2s")
assert.equal(Model.formatDuration(1.5), "1.5s")
assert.equal(Model.POSITION_OPTIONS.length, 4)
assert.deepEqual(Model.PANEL_SECTIONS, ["header", "duration", "fontSize", "position", "preview"])
assert.equal(Model.nextPanelSection("header", 1), "duration")
assert.equal(Model.nextPanelSection("preview", 1), "preview")
assert.equal(Model.nextPanelSection("header", -1), "header")
assert.equal(Model.nextPanelSection("unknown", 1), "header")
assert.equal(Model.nudgeDuration(2, 1), 2.5)
assert.equal(Model.nudgeDuration(10, 1), 10)
assert.equal(Model.nudgeDuration(0.5, -1), 0.5)
assert.equal(Model.nudgeFontSize(28, 1), 29)
assert.equal(Model.nudgeFontSize(64, 1), 64)
assert.equal(Model.nudgeFontSize(12, -1), 12)
assert.equal(Model.cyclePosition("bottom-right", 1), "bottom-left")
assert.equal(Model.cyclePosition("top-left", 1), "top-left")
assert.equal(Model.cyclePosition("bottom-right", -1), "bottom-right")
assert.equal(Model.panelKeyLetter(80, "", 0), "p")
assert.equal(Model.panelKeyLetter(74, "", 0), "j")
assert.equal(Model.panelKeyLetter(0, "O", 0), "o")
assert.equal(Model.panelKeyLetter(0, "", 36), "j")
assert.equal(Model.panelKeyLetter(0, "", 25), "p")
assert.equal(Model.panelKeyLetter(0, "", 44), "j")

assert.deepEqual(Model.parseListenerLine('{"type":"combo","text":"Ctrl + A"}'), {
  type: "combo",
  text: "Ctrl + A"
})
assert.deepEqual(Model.parseListenerLine('{"type":"error","code":"no-input-access"}'), {
  type: "error",
  code: "no-input-access"
})
assert.equal(Model.parseListenerLine('{"type":"combo","text":"  "}'), null)
assert.equal(Model.parseListenerLine("not-json"), null)
assert.equal(Model.parseListenerLine(""), null)

assert.equal(Model.hyprKeyLabel("RETURN"), "Return")
assert.equal(Model.hyprKeyLabel("XF86AudioRaiseVolume"), "VolumeUp")
assert.equal(Model.formatCombo(true, true, false, false, "Return"), "Super + Ctrl + Return")

const hyprBinds = JSON.stringify([
  { mouse: false, catch_all: false, submap: "", description: "Terminal", modmask: 64, key: "RETURN" },
  { mouse: false, catch_all: false, submap: "", description: "Clipboard manager", modmask: 68, key: "V" },
  { mouse: false, catch_all: false, submap: "", description: "Terminal", modmask: 64, key: "RETURN" },
  { mouse: false, catch_all: false, submap: "", description: "Omakeycast", modmask: 64, key: "K" },
  { mouse: true, catch_all: false, submap: "", description: "Move", modmask: 64, key: "mouse:272" },
  { mouse: false, catch_all: false, submap: "", description: "Volume up", modmask: 0, key: "XF86AudioRaiseVolume" },
  { mouse: false, catch_all: false, submap: "resize", description: "Bigger", modmask: 64, key: "RIGHT" }
])
const entries = Model.hyprBindEntries(hyprBinds)
assert.equal(entries.length, 2)
assert.deepEqual(entries[0], { keys: "SUPER + RETURN", label: "Super + Return" })
assert.deepEqual(entries[1], { keys: "SUPER + CTRL + V", label: "Super + Ctrl + V" })
assert.deepEqual(Model.hyprBindEntries("not-json"), [])

const lua = Model.companionLua(entries)
assert.equal(lua.includes('hl.bind("SUPER + RETURN"'), true)
assert.equal(lua.includes("omarchy-shell omakeycast combo 'Super + Return'"), true)
assert.equal(lua.includes("non_consuming = true"), true)
assert.equal(lua.includes("repeating = false"), true)
assert.equal(Model.companionLua([]).includes("_G.omakeycast.binds = {}"), true)

const first = Model.pushChord([], "  Super + A  ", 2000, 0, 1)
assert.equal(first.accepted, true)
assert.equal(first.chords.length, 1)
assert.deepEqual(first.chords[0], { id: 1, text: "Super + A", durationMs: 2000, shownAt: 0 })
const second = Model.pushChord(first.chords, "Super + B", 1500, 400, 2)
assert.equal(first.chords.length, 1)
assert.deepEqual(second.chords.map(function(chord) { return chord.text }), ["Super + A", "Super + B"])
assert.equal(second.chords[0].shownAt, 0)
assert.equal(second.chords[1].id, 2)
assert.equal(Model.pushChord(second.chords, "   ", 2000, 500, 3).accepted, false)

const live = [
  { id: 1, text: "A", durationMs: 1000, shownAt: 0 },
  { id: 2, text: "B", durationMs: 500, shownAt: 200 },
  { id: 3, text: "C", durationMs: 1000, shownAt: 400 }
]
assert.deepEqual(Model.expireChords(live, 700).map(function(chord) { return chord.id }), [1, 3])
assert.deepEqual(Model.expireChords(live, 1000).map(function(chord) { return chord.id }), [3])
assert.deepEqual(Model.expireChords(live, 1400).map(function(chord) { return chord.id }), [])
assert.deepEqual(Model.trimChords(live, 2).map(function(chord) { return chord.id }), [2, 3])
assert.equal(Model.trimChords(live, 0).length, 1)
assert.equal(Model.stackedChordLimit(200, 60, 8), 3)
assert.equal(Model.stackedChordLimit(60, 60, 8), 1)
assert.equal(Model.stackedChordLimit(0, 60, 8), 1)

console.log("model tests ok")
