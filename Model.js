// Settings and listener-line parsing for Omakeycast. Kept Qt-free so it can
// be unit-tested under node.

var PLUGIN_ID = "io.github.fredimachado.omakeycast"

var DEFAULTS = {
  duration: 2,
  fontSize: 28,
  position: "bottom-right"
}

var POSITIONS = ["bottom-right", "bottom-left", "top-right", "top-left"]

var HL_SHIFT = 1
var HL_CTRL = 4
var HL_ALT = 8
var HL_SUPER = 64

var HYPR_KEY_LABELS = {
  RETURN: "Return",
  ENTER: "Return",
  ESCAPE: "Escape",
  SPACE: "Space",
  TAB: "Tab",
  BACKSPACE: "Backspace",
  DELETE: "Delete",
  INSERT: "Insert",
  HOME: "Home",
  END: "End",
  PAGEUP: "PageUp",
  PAGEDOWN: "PageDown",
  LEFT: "Left",
  RIGHT: "Right",
  UP: "Up",
  DOWN: "Down",
  PRINT: "Print",
  PERIOD: ".",
  COMMA: ",",
  SLASH: "/",
  MINUS: "-",
  EQUAL: "=",
  SEMICOLON: ";",
  APOSTROPHE: "'",
  GRAVE: "`",
  BACKSLASH: "\\",
  XF86AudioRaiseVolume: "VolumeUp",
  XF86AudioLowerVolume: "VolumeDown",
  XF86AudioMute: "Mute",
  XF86AudioMicMute: "MicMute",
  XF86AudioPlay: "Play",
  XF86AudioPause: "Pause",
  XF86AudioNext: "Next",
  XF86AudioPrev: "Previous",
  XF86MonBrightnessUp: "BrightnessUp",
  XF86MonBrightnessDown: "BrightnessDown"
}

function formatCombo(superDown, ctrlDown, altDown, shiftDown, key) {
  var parts = []
  if (superDown) parts.push("Super")
  if (ctrlDown) parts.push("Ctrl")
  if (altDown) parts.push("Alt")
  if (shiftDown) parts.push("Shift")
  parts.push(String(key || ""))
  return parts.join(" + ")
}

function hyprKeyLabel(key) {
  var raw = String(key || "")
  if (!raw) return ""
  if (HYPR_KEY_LABELS[raw]) return HYPR_KEY_LABELS[raw]
  var upper = raw.toUpperCase()
  if (HYPR_KEY_LABELS[upper]) return HYPR_KEY_LABELS[upper]
  if (raw.indexOf("XF86") === 0) return raw.slice(4)
  if (/^[A-Z]{2,}$/.test(raw)) return raw.charAt(0) + raw.slice(1).toLowerCase()
  return raw
}

function hyprKeysSpec(modmask, key) {
  var parts = []
  if (modmask & HL_SUPER) parts.push("SUPER")
  if (modmask & HL_CTRL) parts.push("CTRL")
  if (modmask & HL_ALT) parts.push("ALT")
  if (modmask & HL_SHIFT) parts.push("SHIFT")
  parts.push(String(key))
  return parts.join(" + ")
}

function luaQuote(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'
}

function shellSingleQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

function hyprBindEntries(raw) {
  var binds = []
  try {
    binds = JSON.parse(raw || "[]")
  } catch (e) {
    return []
  }
  if (!Array.isArray(binds)) return []

  var seen = ({})
  var out = []
  for (var i = 0; i < binds.length; i++) {
    var bind = binds[i]
    if (!bind || bind.mouse === true || bind.catch_all === true) continue
    if (String(bind.submap || "") !== "") continue
    if (String(bind.description || "") === "Omakeycast") continue
    var mask = parseInt(bind.modmask, 10) || 0
    if (!(mask & (HL_SUPER | HL_CTRL | HL_ALT))) continue
    var key = String(bind.key || "")
    if (!key || key.indexOf("mouse:") === 0) continue
    var id = mask + "\0" + key
    if (seen[id]) continue
    seen[id] = true
    out.push({
      keys: hyprKeysSpec(mask, key),
      label: formatCombo(!!(mask & HL_SUPER), !!(mask & HL_CTRL), !!(mask & HL_ALT), !!(mask & HL_SHIFT), hyprKeyLabel(key))
    })
  }
  return out
}

function companionLua(entries) {
  var lines = [
    "_G.omakeycast = _G.omakeycast or {}",
    "if type(_G.omakeycast.binds) == \"table\" then",
    "  for _, kb in ipairs(_G.omakeycast.binds) do pcall(function() kb:remove() end) end",
    "end",
    "_G.omakeycast.binds = {}"
  ]
  if (!entries || entries.length === 0) return lines.join("\n") + "\n"

  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!entry || !entry.keys || !entry.label) continue
    var cmd = "omarchy-shell omakeycast combo " + shellSingleQuote(entry.label)
    lines.push("do")
    lines.push("  local ok, kb = pcall(function()")
    lines.push("    return hl.bind(" + luaQuote(entry.keys) + ", hl.dsp.exec_cmd(" + luaQuote(cmd) + "), { non_consuming = true, description = \"Omakeycast\" })")
    lines.push("  end)")
    lines.push("  if ok and kb then _G.omakeycast.binds[#_G.omakeycast.binds + 1] = kb end")
    lines.push("end")
  }
  return lines.join("\n") + "\n"
}

function clamp(value, min, max, fallback) {
  var n = typeof value === "number" ? value : parseFloat(String(value))
  if (!isFinite(n)) n = fallback
  return Math.max(min, Math.min(max, n))
}

function normalizePosition(value) {
  var key = String(value || "").replace(/_/g, "-").toLowerCase()
  return POSITIONS.indexOf(key) !== -1 ? key : DEFAULTS.position
}

function parseSettings(raw) {
  var duration = clamp(raw && raw.duration, 0.25, 30, DEFAULTS.duration)
  var fontSize = Math.round(clamp(raw && raw.fontSize, 12, 96, DEFAULTS.fontSize))
  return {
    duration: duration,
    durationMs: Math.round(duration * 1000),
    fontSize: fontSize,
    position: normalizePosition(raw && raw.position)
  }
}

function pluginEntry(config, pluginId) {
  var id = String(pluginId || PLUGIN_ID)
  if (!config || !Array.isArray(config.plugins)) return null
  for (var i = 0; i < config.plugins.length; i++) {
    var entry = config.plugins[i]
    if (entry && String(entry.id || "") === id) return entry
  }
  return null
}

function parseShellJson(text, pluginId) {
  var config = null
  try {
    config = JSON.parse(text || "{}")
  } catch (e) {
    return parseSettings(null)
  }
  return parseSettings(pluginEntry(config, pluginId))
}

function parseListenerLine(line) {
  var text = String(line || "").replace(/^\s+|\s+$/g, "")
  if (!text) return null
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object") return null
  var type = String(parsed.type || "")
  if (type === "combo") {
    var combo = String(parsed.text || "").replace(/^\s+|\s+$/g, "")
    if (!combo) return null
    return { type: "combo", text: combo }
  }
  if (type === "error") {
    return { type: "error", code: String(parsed.code || "unknown") }
  }
  if (type === "status") {
    return { type: "status", keyboards: parseInt(parsed.keyboards, 10) || 0 }
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    DEFAULTS: DEFAULTS,
    POSITIONS: POSITIONS,
    parseSettings: parseSettings,
    parseShellJson: parseShellJson,
    parseListenerLine: parseListenerLine,
    formatCombo: formatCombo,
    hyprKeyLabel: hyprKeyLabel,
    hyprBindEntries: hyprBindEntries,
    companionLua: companionLua
  }
}
