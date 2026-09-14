// Settings and listener-line parsing for Omakeycast. Kept Qt-free so it can
// be unit-tested under node.

var PLUGIN_ID = "io.github.fredimachado.omakeycast"

var DEFAULTS = {
  duration: 2,
  fontSize: 28,
  position: "bottom-right"
}

var POSITIONS = ["bottom-right", "bottom-left", "top-right", "top-left"]

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
    parseListenerLine: parseListenerLine
  }
}
