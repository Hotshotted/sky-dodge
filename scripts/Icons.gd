class_name Icons
extends RefCounted
## Sky Dodge's one vector icon set (docs/style.md): bold filled silhouettes and thick strokes, round proportions, no text,
## no emoji. Everything is drawn in code onto any CanvasItem: Icons.draw(item, "coin", centre, r, colour). `r` is the radius
## of the box the icon fits in; strokes are about r / 6. Two-tone only where the colour is the meaning (coin gold, flame,
## danger red). Perks, boosts, supplies, upgrades and gear all use the ids listed in ICONS (Tuning's "glyph" field).

const ICONS := ["coin", "star", "star_off", "clock", "pause", "play", "back", "home", "restart", "lock", "check", "speaker", "speaker_off", "note",
	"plane", "hangar", "logbook", "map", "chev_down", "chev_up", "cat", "medal", "can", "wind", "cloud", "heart", "shield", "hay", "flame",
	"bolt", "arrow_up", "wrench", "trophy", "sparkle", "close", "plus", "quest",
	# perks
	"glide", "cloud_diver", "lucky_whiskers", "prop_wash", "battering_ram", "fuel_miser", "hot_streak", "scavenger", "tailwind", "daredevil",
	"second_wind", "golden_touch", "flak", "pods", "tail",
	# boosts and supplies
	"double_coins", "magnet_storm", "whisker_window", "fuel_freeze", "full_tank", "patch", "crate_shower", "coin_bag",
	# upgrades and gear
	"coin_value", "can_bounty", "close_call_pay", "bonus_cap", "fuel_tank", "efficiency", "refill", "nine_lives", "reserve_tank", "magnet",
	"cloud_eye", "steady_nerves", "head_start"]

const GOLD := Color("ffc933")
const GOLD_DARK := Color("c98a0b")
const INK := Color("0a1020")

static func _poly(ci: CanvasItem, pts: Array, col: Color) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(v)
	if Geometry2D.triangulate_polygon(p).is_empty():
		return
	ci.draw_colored_polygon(p, col)

static func _tri(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var p := PackedVector2Array([a, b, c])
	ci.draw_colored_polygon(p, col)

static func _line3(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color, w: float) -> void:
	ci.draw_polyline(PackedVector2Array([a, b, c]), col, w, true)

static func _star(ci: CanvasItem, c: Vector2, r: float, fill: Color, outline: bool) -> void:
	var pts := PackedVector2Array()
	pts.resize(10)
	if outline:
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			pts[k] = c + Vector2(cos(a), sin(a)) * ((r if k % 2 == 0 else r * 0.45) + maxf(r * 0.12, 3.0))
		ci.draw_colored_polygon(pts, Color(INK, fill.a))
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		pts[k] = c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45)
	ci.draw_colored_polygon(pts, fill)

static func has(id: String) -> bool:
	return ICONS.has(id)

## Draw icon `id` in the box of radius r around c, in colour col (white by default; gold / red where the meaning is the colour).
static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color = Color.WHITE) -> void:
	var w := maxf(r * 0.17, 3.0)
	var a := col.a
	var ink := Color(INK, a)
	var gold := Color(GOLD, a)
	match id:
		"coin":
			ci.draw_circle(c, r, Color(INK, a))
			ci.draw_circle(c, r - maxf(r * 0.1, 3.0), gold)
			ci.draw_arc(c, r * 0.6, 0.0, TAU, 20, Color(GOLD_DARK, a), w * 0.8, true)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.3), Color(GOLD_DARK, a), w * 0.8, true)
		"star":
			_star(ci, c, r, gold, true)
		"star_off":
			_star(ci, c, r, Color(0.28, 0.3, 0.38, a), true)
		"clock":
			ci.draw_arc(c, r * 0.9, 0.0, TAU, 28, col, w, true)
			ci.draw_line(c, c + Vector2(0, -r * 0.6), col, w, true)
			ci.draw_line(c, c + Vector2(r * 0.4, r * 0.2), col, w, true)
		"pause":
			ci.draw_rect(Rect2(c.x - r * 0.55, c.y - r * 0.7, r * 0.42, r * 1.4), col)
			ci.draw_rect(Rect2(c.x + r * 0.13, c.y - r * 0.7, r * 0.42, r * 1.4), col)
		"play":
			_tri(ci, c + Vector2(-r * 0.5, -r * 0.75), c + Vector2(-r * 0.5, r * 0.75), c + Vector2(r * 0.8, 0), col)
		"back":
			_line3(ci, c + Vector2(r * 0.4, -r * 0.7), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.4, r * 0.7), col, w * 1.6)
		"chev_down":
			_line3(ci, c + Vector2(-r * 0.7, -r * 0.3), c + Vector2(0, r * 0.4), c + Vector2(r * 0.7, -r * 0.3), col, w * 1.4)
		"chev_up":
			_line3(ci, c + Vector2(-r * 0.7, r * 0.3), c + Vector2(0, -r * 0.4), c + Vector2(r * 0.7, r * 0.3), col, w * 1.4)
		"home":
			_tri(ci, c + Vector2(-r * 0.95, -r * 0.05), c + Vector2(0, -r * 0.9), c + Vector2(r * 0.95, -r * 0.05), col)
			ci.draw_rect(Rect2(c.x - r * 0.62, c.y - r * 0.05, r * 1.24, r * 0.88), col)
			ci.draw_rect(Rect2(c.x - r * 0.17, c.y + r * 0.3, r * 0.34, r * 0.53), Color(INK, a))
		"restart":
			ci.draw_arc(c, r * 0.68, -PI * 0.15, PI * 1.5, 24, col, w * 1.5, true)
			_tri(ci, c + Vector2(r * 0.98, -r * 0.05), c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.88, -r * 0.85), col)
		"lock":
			ci.draw_rect(Rect2(c.x - r * 0.65, c.y - r * 0.1, r * 1.3, r * 0.95), col)
			ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.45, PI, TAU, 12, col, w * 1.3, true)
		"check":
			_line3(ci, c + Vector2(-r * 0.7, 0.0), c + Vector2(-r * 0.2, r * 0.55), c + Vector2(r * 0.8, -r * 0.55), col, w * 1.8)
		"close":
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), col, w * 1.6, true)
			ci.draw_line(c + Vector2(r * 0.6, -r * 0.6), c + Vector2(-r * 0.6, r * 0.6), col, w * 1.6, true)
		"plus":
			ci.draw_line(c + Vector2(-r * 0.7, 0), c + Vector2(r * 0.7, 0), col, w * 1.8)
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.7), col, w * 1.8)
		"quest":
			ci.draw_arc(c + Vector2(0, -r * 0.25), r * 0.5, PI * 1.05, PI * 2.45, 14, col, w * 1.5, true)
			ci.draw_line(c + Vector2(0, r * 0.2), c + Vector2(0, r * 0.35), col, w * 1.5)
			ci.draw_circle(c + Vector2(0, r * 0.75), w * 0.9, col)
		"plane":
			ci.draw_line(c + Vector2(0, -r * 0.9), c + Vector2(0, r * 0.8), col, w * 1.9, true)
			_tri(ci, c + Vector2(-r * 0.98, r * 0.12), c + Vector2(r * 0.98, r * 0.12), c + Vector2(0, -r * 0.35), col)
			_tri(ci, c + Vector2(-r * 0.42, r * 0.88), c + Vector2(r * 0.42, r * 0.88), c + Vector2(0, r * 0.5), col)
		"speaker":
			_poly(ci, [c + Vector2(-r * 0.9, -r * 0.3), c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.15, -r * 0.8), c + Vector2(r * 0.15, r * 0.8), c + Vector2(-r * 0.4, r * 0.3), c + Vector2(-r * 0.9, r * 0.3)], col)
			ci.draw_arc(c + Vector2(r * 0.15, 0), r * 0.55, -PI * 0.35, PI * 0.35, 8, col, w, true)
			ci.draw_arc(c + Vector2(r * 0.15, 0), r * 0.95, -PI * 0.35, PI * 0.35, 8, col, w, true)
		"speaker_off":
			_poly(ci, [c + Vector2(-r * 0.9, -r * 0.3), c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.15, -r * 0.8), c + Vector2(r * 0.15, r * 0.8), c + Vector2(-r * 0.4, r * 0.3), c + Vector2(-r * 0.9, r * 0.3)], col)
			ci.draw_line(c + Vector2(r * 0.4, -r * 0.45), c + Vector2(r * 0.95, r * 0.45), col, w, true)
			ci.draw_line(c + Vector2(r * 0.95, -r * 0.45), c + Vector2(r * 0.4, r * 0.45), col, w, true)
		"note":
			ci.draw_circle(c + Vector2(-r * 0.4, r * 0.55), r * 0.38, col)
			ci.draw_line(c + Vector2(-r * 0.05, r * 0.5), c + Vector2(-r * 0.05, -r * 0.8), col, w * 1.3)
			_tri(ci, c + Vector2(-r * 0.05, -r * 0.8), c + Vector2(r * 0.7, -r * 0.4), c + Vector2(-r * 0.05, -r * 0.2), col)
		"hangar":   # a shed with a round roof and a door
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.95, PI, TAU, 16, col, w * 1.2, true)
			ci.draw_rect(Rect2(c.x - r * 0.95, c.y + r * 0.1, r * 1.9, r * 0.8), col)
			ci.draw_rect(Rect2(c.x - r * 0.5, c.y + r * 0.25, r * 1.0, r * 0.65), Color(INK, a))
		"logbook":
			ci.draw_rect(Rect2(c.x - r * 0.75, c.y - r * 0.9, r * 1.5, r * 1.8), col)
			ci.draw_rect(Rect2(c.x - r * 0.75, c.y - r * 0.9, r * 0.28, r * 1.8), Color(0, 0, 0, 0.28 * a))
			for k in 3:
				ci.draw_line(c + Vector2(-r * 0.2, -r * 0.45 + k * r * 0.45), c + Vector2(r * 0.5, -r * 0.45 + k * r * 0.45), Color(INK, a), w * 0.7)
		"map":   # a flag on a pole
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.9), c + Vector2(-r * 0.6, r * 0.9), col, w * 1.3)
			_poly(ci, [c + Vector2(-r * 0.6, -r * 0.85), c + Vector2(r * 0.85, -r * 0.4), c + Vector2(-r * 0.6, r * 0.05)], col)
		"cat":   # Whiskers: a round face, two ears, eyes and whiskers
			ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.8, col)
			_tri(ci, c + Vector2(-r * 0.75, -r * 0.1), c + Vector2(-r * 0.5, -r * 0.95), c + Vector2(-r * 0.1, -r * 0.45), col)
			_tri(ci, c + Vector2(r * 0.75, -r * 0.1), c + Vector2(r * 0.5, -r * 0.95), c + Vector2(r * 0.1, -r * 0.45), col)
			ci.draw_circle(c + Vector2(-r * 0.3, 0.0), r * 0.1, ink)
			ci.draw_circle(c + Vector2(r * 0.3, 0.0), r * 0.1, ink)
			_tri(ci, c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), c + Vector2(0, r * 0.32), Color(1.0, 0.55, 0.6, a))
		"medal":
			_tri(ci, c + Vector2(-r * 0.6, -r * 0.95), c + Vector2(0, -r * 0.1), c + Vector2(-r * 0.05, -r * 0.95), Color(0.4, 0.6, 1.0, a))
			_tri(ci, c + Vector2(r * 0.6, -r * 0.95), c + Vector2(0, -r * 0.1), c + Vector2(r * 0.05, -r * 0.95), Color(1.0, 0.4, 0.4, a))
			ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.55, ink)
			ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.45, gold)
			_star(ci, c + Vector2(0, r * 0.35), r * 0.25, Color(GOLD_DARK, a), false)
		"can":   # a fuel can
			_poly(ci, [c + Vector2(-r * 0.7, -r * 0.4), c + Vector2(-r * 0.3, -r * 0.85), c + Vector2(r * 0.3, -r * 0.85), c + Vector2(r * 0.7, -r * 0.4), c + Vector2(r * 0.7, r * 0.9), c + Vector2(-r * 0.7, r * 0.9)], col)
			ci.draw_rect(Rect2(c.x + r * 0.05, c.y - r * 1.0, r * 0.45, r * 0.25), col)
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.1), c + Vector2(r * 0.4, r * 0.1), Color(INK, a), w * 0.8)
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.5), c + Vector2(r * 0.4, r * 0.5), Color(INK, a), w * 0.8)
		"wind", "tailwind":
			ci.draw_line(c + Vector2(-r * 0.95, -r * 0.35), c + Vector2(r * 0.45, -r * 0.35), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-r * 0.95, r * 0.25), c + Vector2(r * 0.8, r * 0.25), col, w * 1.2, true)
			ci.draw_arc(c + Vector2(r * 0.45, -r * 0.6), r * 0.25, PI * 0.5, PI * 2.0, 8, col, w * 1.2, true)
			if id == "tailwind":
				_tri(ci, c + Vector2(r * 0.95, r * 0.25), c + Vector2(r * 0.5, -r * 0.05), c + Vector2(r * 0.5, r * 0.55), col)
		"cloud", "cloud_diver":
			ci.draw_circle(c + Vector2(-r * 0.4, r * 0.05), r * 0.45, col)
			ci.draw_circle(c + Vector2(r * 0.2, -r * 0.25), r * 0.55, col)
			ci.draw_circle(c + Vector2(r * 0.55, r * 0.15), r * 0.38, col)
			ci.draw_rect(Rect2(c.x - r * 0.4, c.y + r * 0.05, r * 0.95, r * 0.48), col)
			if id == "cloud_diver":
				_line3(ci, c + Vector2(-r * 0.3, r * 0.75), c + Vector2(0, r * 1.05), c + Vector2(r * 0.3, r * 0.75), Color(0.35, 0.55, 1.0, a), w * 1.2)
		"heart", "nine_lives":
			ci.draw_circle(c + Vector2(-r * 0.4, -r * 0.25), r * 0.5, col)
			ci.draw_circle(c + Vector2(r * 0.4, -r * 0.25), r * 0.5, col)
			_poly(ci, [c + Vector2(-r * 0.86, -r * 0.0), c + Vector2(r * 0.86, 0.0), c + Vector2(0, r * 0.95)], col)
		"shield":
			_poly(ci, [c + Vector2(-r * 0.8, -r * 0.8), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, r * 0.1), c + Vector2(0, r * 0.95), c + Vector2(-r * 0.8, r * 0.1)], col)
			_line3(ci, c + Vector2(-r * 0.3, -r * 0.05), c + Vector2(-r * 0.05, r * 0.25), c + Vector2(r * 0.4, -r * 0.35), Color(INK, a), w)
		"hay":
			ci.draw_circle(c, r * 0.8, Color(0.95, 0.78, 0.3, a))
			ci.draw_arc(c, r * 0.8, 0.0, TAU, 20, ink, w * 0.8, true)
			ci.draw_arc(c, r * 0.45, 0.0, TAU, 16, Color(0.7, 0.5, 0.15, a), w * 0.7, true)
		"flame", "hot_streak":
			var fc := Color(1.0, 0.55, 0.15, a)
			ci.draw_circle(c + Vector2(0, r * 0.25), r * 0.62, fc)
			_tri(ci, c + Vector2(-r * 0.55, r * 0.1), c + Vector2(r * 0.55, r * 0.1), c + Vector2(r * 0.05, -r * 0.98), fc)
			ci.draw_circle(c + Vector2(0, r * 0.4), r * 0.3, Color(1.0, 0.9, 0.4, a))
		"bolt", "daredevil", "close_call_pay":
			_poly(ci, [c + Vector2(r * 0.15, -r * 0.95), c + Vector2(-r * 0.6, r * 0.1), c + Vector2(-r * 0.05, r * 0.1), c + Vector2(-r * 0.2, r * 0.95), c + Vector2(r * 0.6, -r * 0.2), c + Vector2(r * 0.05, -r * 0.2)], Color(1.0, 0.85, 0.2, a) if id != "bolt" else col)
		"arrow_up", "bonus_cap":
			_tri(ci, c + Vector2(-r * 0.75, -r * 0.05), c + Vector2(r * 0.75, -r * 0.05), c + Vector2(0, -r * 0.95), col)
			ci.draw_rect(Rect2(c.x - r * 0.28, c.y - r * 0.05, r * 0.56, r * 0.85), col)
			if id == "bonus_cap":
				ci.draw_line(c + Vector2(-r * 0.8, r * 1.0), c + Vector2(r * 0.8, r * 1.0), col, w)
		"wrench":
			ci.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.35, -r * 0.35), col, w * 1.7, true)
			ci.draw_arc(c + Vector2(r * 0.45, -r * 0.45), r * 0.5, PI * 0.9, PI * 2.6, 12, col, w * 1.5, true)
		"trophy":
			ci.draw_rect(Rect2(c.x - r * 0.55, c.y - r * 0.8, r * 1.1, r * 0.9), col)
			ci.draw_arc(c + Vector2(-r * 0.55, -r * 0.4), r * 0.35, PI * 0.5, PI * 1.5, 8, col, w, true)
			ci.draw_arc(c + Vector2(r * 0.55, -r * 0.4), r * 0.35, -PI * 0.5, PI * 0.5, 8, col, w, true)
			ci.draw_rect(Rect2(c.x - r * 0.12, c.y + r * 0.1, r * 0.24, r * 0.5), col)
			ci.draw_rect(Rect2(c.x - r * 0.5, c.y + r * 0.6, r * 1.0, r * 0.25), col)
		"sparkle":
			_poly(ci, [c + Vector2(0, -r), c + Vector2(r * 0.22, -r * 0.22), c + Vector2(r, 0), c + Vector2(r * 0.22, r * 0.22), c + Vector2(0, r), c + Vector2(-r * 0.22, r * 0.22), c + Vector2(-r, 0), c + Vector2(-r * 0.22, -r * 0.22)], col)
		"glide":   # a gull-winged glider
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.98, r * 0.2), c + Vector2(-r * 0.5, -r * 0.25), c + Vector2(0, r * 0.05), c + Vector2(r * 0.5, -r * 0.25), c + Vector2(r * 0.98, r * 0.2)]), col, w * 1.7, true)
			ci.draw_line(c + Vector2(0, r * 0.05), c + Vector2(0, r * 0.8), col, w * 1.7, true)
			ci.draw_line(c + Vector2(-r * 0.3, r * 0.8), c + Vector2(r * 0.3, r * 0.8), col, w * 1.3, true)
		"lucky_whiskers", "whisker_window":
			ci.draw_circle(c + Vector2(0, r * 0.05), r * 0.38, col)
			for sgn in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(sgn * r * 0.4, r * 0.0), c + Vector2(sgn * r * 0.98, -r * 0.35), col, w, true)
				ci.draw_line(c + Vector2(sgn * r * 0.4, r * 0.1), c + Vector2(sgn * r * 1.0, r * 0.1), col, w, true)
				ci.draw_line(c + Vector2(sgn * r * 0.4, r * 0.2), c + Vector2(sgn * r * 0.98, r * 0.55), col, w, true)
			_tri(ci, c + Vector2(-r * 0.12, -r * 0.1), c + Vector2(r * 0.12, -r * 0.1), c + Vector2(0, r * 0.05), Color(INK, a))
			if id == "lucky_whiskers":
				_star(ci, c + Vector2(r * 0.55, -r * 0.62), r * 0.28, gold, false)
		"prop_wash":   # a propeller and its swirl
			ci.draw_circle(c, r * 0.17, col)
			for k in 2:
				var ang := k * PI + 0.5
				ci.draw_line(c, c + Vector2(cos(ang), sin(ang)) * r * 0.8, col, w * 2.0, true)
			ci.draw_arc(c, r * 0.95, PI * 0.9, PI * 1.9, 10, col, w * 0.8, true)
		"flak", "pods", "tail":   # a gun barrel and its burst: forward, sideways or backward
			var dir := Vector2(0, -1) if id == "flak" else (Vector2(1, 0) if id == "pods" else Vector2(0, 1))
			var side := Vector2(-dir.y, dir.x)
			ci.draw_line(c - dir * r * 0.55, c + dir * r * 0.25, col, w * 2.4, true)
			ci.draw_circle(c - dir * r * 0.6, r * 0.28, col)
			_tri(ci, c + dir * r * 0.95, c + dir * r * 0.4 + side * r * 0.42, c + dir * r * 0.4 - side * r * 0.42, Color(1.0, 0.8, 0.25, a))
			if id == "pods":
				ci.draw_line(c - dir * r * 0.55 + side * r * 0.0 - Vector2(0, r * 0.5), c - dir * r * 0.55 + Vector2(0, r * 0.5), col, w * 1.2, true)
		"battering_ram":   # a block hit by an arrow
			ci.draw_rect(Rect2(c.x + r * 0.15, c.y - r * 0.7, r * 0.8, r * 1.4), col)
			ci.draw_line(c + Vector2(-r * 0.95, 0), c + Vector2(r * 0.1, 0), col, w * 1.7, true)
			_tri(ci, c + Vector2(r * 0.25, 0), c + Vector2(-r * 0.3, -r * 0.55), c + Vector2(-r * 0.3, r * 0.55), col)
		"fuel_miser":   # a can with a down arrow
			draw(ci, "can", c + Vector2(-r * 0.15, 0), r * 0.85, col)
			_tri(ci, c + Vector2(r * 0.55, r * 0.1), c + Vector2(r * 1.0, r * 0.1), c + Vector2(r * 0.78, r * 0.55), Color(0.4, 0.95, 0.5, a))
		"scavenger", "coin_bag":
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.65, col)
			_poly(ci, [c + Vector2(-r * 0.3, -r * 0.3), c + Vector2(r * 0.3, -r * 0.3), c + Vector2(r * 0.15, -r * 0.7), c + Vector2(-r * 0.15, -r * 0.7)], col)
			ci.draw_line(c + Vector2(-r * 0.3, -r * 0.35), c + Vector2(r * 0.3, -r * 0.35), Color(INK, a), w * 0.8)
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.28, gold)
		"second_wind":
			ci.draw_arc(c, r * 0.65, -PI * 0.15, PI * 1.5, 22, col, w * 1.5, true)
			_tri(ci, c + Vector2(r * 0.98, -r * 0.05), c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.88, -r * 0.85), col)
			ci.draw_circle(c, r * 0.18, col)
		"golden_touch":
			draw(ci, "coin", c + Vector2(-r * 0.1, r * 0.1), r * 0.75, col)
			_star(ci, c + Vector2(r * 0.6, -r * 0.6), r * 0.34, Color.WHITE, true)
		"double_coins":
			draw(ci, "coin", c + Vector2(-r * 0.3, r * 0.2), r * 0.6, col)
			draw(ci, "coin", c + Vector2(r * 0.3, -r * 0.2), r * 0.6, col)
		"coin_value":
			draw(ci, "coin", c, r, col)
		"can_bounty":
			draw(ci, "can", c + Vector2(-r * 0.2, r * 0.05), r * 0.85, col)
			draw(ci, "coin", c + Vector2(r * 0.55, -r * 0.5), r * 0.4, col)
		"magnet", "magnet_storm":
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.6, PI, TAU, 14, col, w * 2.4, true)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.1), c + Vector2(-r * 0.6, r * 0.8), col, w * 2.4)
			ci.draw_line(c + Vector2(r * 0.6, r * 0.1), c + Vector2(r * 0.6, r * 0.8), col, w * 2.4)
			ci.draw_rect(Rect2(c.x - r * 0.84, c.y + r * 0.55, r * 0.48, r * 0.3), Color(1.0, 0.4, 0.4, a))
			ci.draw_rect(Rect2(c.x + r * 0.36, c.y + r * 0.55, r * 0.48, r * 0.3), Color(0.4, 0.6, 1.0, a))
		"fuel_freeze":   # a snowflake
			for k in 3:
				var ang := k * PI / 3.0
				ci.draw_line(c - Vector2(cos(ang), sin(ang)) * r * 0.9, c + Vector2(cos(ang), sin(ang)) * r * 0.9, col, w * 1.2, true)
		"full_tank", "fuel_tank", "reserve_tank":
			draw(ci, "can", c, r, col)
			if id == "full_tank":
				ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.12, Color(INK, a))
			if id == "reserve_tank":
				ci.draw_line(c + Vector2(r * 0.05, -r * 0.25), c + Vector2(r * 0.05, r * 0.45), Color(INK, a), w)
				ci.draw_line(c + Vector2(-r * 0.3, r * 0.1), c + Vector2(r * 0.4, r * 0.1), Color(INK, a), w)
		"patch":   # a plaster
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.6, -r * 0.6), col, w * 3.2, true)
			ci.draw_circle(c, r * 0.14, Color(INK, a))
		"crate_shower":
			ci.draw_rect(Rect2(c.x - r * 0.7, c.y - r * 0.5, r * 1.4, r * 1.2), col)
			ci.draw_rect(Rect2(c.x - r * 0.7, c.y - r * 0.5, r * 1.4, r * 1.2), Color(INK, a), false, w * 0.8)
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.5), c + Vector2(r * 0.7, r * 0.7), Color(INK, a), w * 0.7)
			ci.draw_line(c + Vector2(r * 0.7, -r * 0.5), c + Vector2(-r * 0.7, r * 0.7), Color(INK, a), w * 0.7)
		"efficiency":   # a leaf
			_poly(ci, [c + Vector2(-r * 0.8, r * 0.7), c + Vector2(-r * 0.7, -r * 0.2), c + Vector2(-r * 0.1, -r * 0.8), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.7, r * 0.1), c + Vector2(r * 0.1, r * 0.7)], col)
			ci.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.4, -r * 0.4), Color(INK, a), w * 0.7)
		"refill":
			draw(ci, "can", c + Vector2(-r * 0.15, 0.0), r * 0.8, col)
			ci.draw_arc(c + Vector2(r * 0.5, -r * 0.3), r * 0.4, PI * 0.3, PI * 1.9, 10, Color(0.5, 1.0, 0.6, a), w * 1.2, true)
		"cloud_eye":   # an eye
			ci.draw_arc(c + Vector2(0, r * 0.6), r * 1.0, -PI * 0.75, -PI * 0.25, 12, col, w * 1.3, true)
			ci.draw_arc(c + Vector2(0, -r * 0.6), r * 1.0, PI * 0.25, PI * 0.75, 12, col, w * 1.3, true)
			ci.draw_circle(c, r * 0.35, col)
			ci.draw_circle(c, r * 0.15, Color(INK, a))
		"steady_nerves":   # a steady hand: a level
			ci.draw_arc(c + Vector2(0, r * 0.3), r * 0.9, PI * 1.1, PI * 1.9, 12, col, w * 1.3, true)
			ci.draw_line(c + Vector2(0, r * 0.3), c + Vector2(r * 0.45, -r * 0.4), col, w * 1.4, true)
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.16, col)
		"head_start":   # chevrons forward
			for k in 2:
				_line3(ci, c + Vector2(-r * 0.7 + k * r * 0.65, -r * 0.7), c + Vector2(-r * 0.1 + k * r * 0.65, 0), c + Vector2(-r * 0.7 + k * r * 0.65, r * 0.7), col, w * 1.5)
		_:
			ci.draw_circle(c, r * 0.5, col)

## The look of an item's id for the places that only have a perk / boost / gear id (same names as Tuning's ids).
static func for_id(id: String) -> String:
	return id if ICONS.has(id) else "quest"
