const assert = require("node:assert/strict")
const Model = require("../Model.js")

assert.deepEqual(Model.parseSettings(null), {
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

const shell = JSON.stringify({
  version: 1,
  plugins: [
    { id: "other.plugin", duration: 9 },
    { id: Model.PLUGIN_ID, duration: 3, fontSize: 40, position: "bottom-left" }
  ]
})
const fromShell = Model.parseShellJson(shell)
assert.equal(fromShell.duration, 3)
assert.equal(fromShell.fontSize, 40)
assert.equal(fromShell.position, "bottom-left")
assert.deepEqual(Model.parseShellJson("not-json"), Model.parseSettings(null))
assert.deepEqual(Model.parseShellJson('{"plugins":[]}'), Model.parseSettings(null))

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
assert.equal(Model.companionLua([]).includes("_G.omakeycast.binds = {}"), true)

console.log("model tests ok")
