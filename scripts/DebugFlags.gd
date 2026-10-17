class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?nofx=sparks,streaks,flash,popup,trail,haptic,punch,pickup   turn those effects off
##   ?nofx=all                                             turn all of them off
##   ?noprewarm                                            skip the start-up pre-warm and splash
##   ?perf                                                 show a worst-frame-time readout
## Combine with "&", e.g.  ?nofx=sparks&noprewarm&perf
## The active flags are printed under the build stamp.

const EFFECTS := ["sparks", "streaks", "flash", "popup", "trail", "haptic", "punch", "pickup"]

static var _loaded := false
static var _off := {}                  # effect name -> true
static var _bad: Array[String] = []    # unknown names (typos), shown in the summary
static var noprewarm := false
static var perf := false

## True if the named near-miss effect has been switched off.
static func off(effect: String) -> bool:
	_load()
	return _off.has(effect)

static func prewarm_enabled() -> bool:
	_load()
	return not noprewarm

static func perf_enabled() -> bool:
	_load()
	return perf

## One-line description of the active flags ("" when none), shown next to the build stamp.
static func summary() -> String:
	_load()
	var parts: Array[String] = []
	if not _off.is_empty():
		var names: Array[String] = []
		for e in EFFECTS:
			if _off.has(e):
				names.append(e)
		parts.append("nofx=" + ",".join(names))
	if noprewarm:
		parts.append("noprewarm")
	if perf:
		parts.append("perf")
	for b in _bad:
		parts.append("?" + b)
	return " ".join(parts)

static func _load() -> void:
	if _loaded:
		return
	var args: Array[String] = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search")
		if q is String:
			for part in (q as String).trim_prefix("?").split("&", false):
				args.append(part)
	for a in OS.get_cmdline_user_args():
		args.append(a.trim_prefix("--"))
	parse(args)

## Parse "key" / "key=value" strings. Public so tests can feed it.
static func parse(args: Array[String]) -> void:
	_loaded = true
	_off.clear()
	_bad.clear()
	noprewarm = false
	perf = false
	for a in args:
		var kv := a.split("=", true, 1)
		var key := kv[0].uri_decode().to_lower()
		var val := kv[1].uri_decode().to_lower() if kv.size() > 1 else ""
		match key:
			"nofx":
				for name in val.split(",", false):
					if name == "all":
						for e in EFFECTS:
							_off[e] = true
					elif EFFECTS.has(name):
						_off[name] = true
					else:
						_bad.append(name)
			"noprewarm":
				noprewarm = true
			"perf":
				perf = true
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
