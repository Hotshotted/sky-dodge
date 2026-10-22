class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?nofx=sparks,streaks,flash,popup,trail,haptic,punch,pickup,clouds,hazards,crates   turn those effects off
##   ?nofx=all                                             turn all of them off
##   ?noprewarm                                            skip the start-up pre-warm and splash
##   ?perf                                                 show a worst-frame-time readout
##   ?tune                                                 show the on-screen tuning panel (TUNE button, top-right)
##   ?debug                                                show the build stamp and the active flags (also shown with ?tune or ?perf)
##   ?map=N                                                play map N (0-3) whatever is unlocked / selected
##   ?god                                                  nothing can hurt the plane (to look at hazards)
## Combine with "&", e.g.  ?nofx=sparks&noprewarm&perf
## The build stamp and the active flags are only shown to players who ask for them (?debug, ?tune or ?perf).

const EFFECTS := ["sparks", "streaks", "flash", "popup", "trail", "haptic", "punch", "pickup", "clouds", "hazards", "crates", "kit", "sound", "music", "ground", "shadows", "coins", "shake", "threats"]

static var _loaded := false
static var _off := {}                  # effect name -> true
static var _bad: Array[String] = []    # unknown names (typos), shown in the summary
static var noprewarm := false
static var perf := false
static var debug := false
static var tune := false
static var start_map := -1
static var god := false
static var profile := false           # tests/profile_run.gd: Main times its own parts (see Main.prof)
static var pattern := ""            # ?pattern=<name>: the Countryside repeats this one pattern

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

## Should the build stamp (and the flags under it) show? Only for ?debug, ?tune or ?perf: players never see it.
static func stamp_enabled() -> bool:
	_load()
	return debug or tune or perf

static func tune_enabled() -> bool:
	_load()
	return tune

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
	if debug:
		parts.append("debug")
	if perf:
		parts.append("perf")
	if tune:
		parts.append("tune")
	if start_map >= 0:
		parts.append("map=%d" % start_map)
	if god:
		parts.append("god")
	if pattern != "":
		parts.append("pattern=" + pattern)
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
	debug = false
	tune = false
	start_map = -1
	god = false
	pattern = ""
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
			"pattern":
				pattern = val
			"noprewarm":
				noprewarm = true
			"perf":
				perf = true
			"debug":
				debug = true
			"tune":
				tune = true
			"map":
				start_map = clampi(int(val), 0, 3)
			"god":
				god = true
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
