class_name Goals
extends Node3D
## In-world goals: gates that scroll into view at the distances worth reaching this run: your BEST (a flag), the next
## medal and the next map unlock. They are scenery you can fly through (nothing collides). Passing one fires `reached`
## once, for the celebration. Three gates are built at start-up and reused; setup() only sets their texts and colours.

signal reached(kind: String, label: String, color: Color)

const POOL := 3
const HALF_WIDTH := 4.7
const COLORS := {"best": Color(1.0, 0.82, 0.2), "bronze": Color(0.8, 0.5, 0.25), "silver": Color(0.85, 0.88, 0.97), "gold": Color(1.0, 0.85, 0.2), "unlock": Color(0.4, 0.85, 1.0)}

var _gates: Array[Dictionary] = []
var _goals: Array[Dictionary] = []    # {kind, meters, text, label, color, done} (reused)
var count := 0

func _ready() -> void:
	for i in POOL:
		var root := Node3D.new()
		root.visible = false
		var mats: Array[StandardMaterial3D] = []
		var pole_mat := _mat(Color(0.9, 0.9, 0.95))
		for sgn in [-1.0, 1.0]:
			_box(root, Vector3(0.16, 1.5, 0.16), Vector3(sgn * HALF_WIDTH, 0.7, 0.0), pole_mat)
		var stripe_mats: Array[StandardMaterial3D] = []
		for k in 8:   # a banner across the lane, striped in the goal's colour
			var sm := _mat(Color.WHITE)
			_box(root, Vector3(2.0 * HALF_WIDTH / 8.0, 0.1, 0.34), Vector3(-HALF_WIDTH + (k + 0.5) * 2.0 * HALF_WIDTH / 8.0, 1.3, 0.0), sm)
			stripe_mats.append(sm)
		var flag_mat := _mat(Color.WHITE)
		_box(root, Vector3(2.0, 0.03, 0.9), Vector3(-HALF_WIDTH + 1.15, 0.95, 0.0), flag_mat)   # the flag
		var label := Label3D.new()
		label.font_size = 96
		label.pixel_size = 0.011
		label.outline_size = 20
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 2.0, 0.0)
		label.no_depth_test = true
		root.add_child(label)
		add_child(root)
		_gates.append({"root": root, "stripes": stripe_mats, "flag": flag_mat, "label": label})
		_goals.append({"kind": "", "meters": 0.0, "text": "", "color": Color.WHITE, "done": true})

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = c * 0.35
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

## Start of a run: `list` = [{kind, meters, text}] (at most POOL).
func setup(list: Array) -> void:
	count = mini(list.size(), POOL)
	for i in POOL:
		var g := _goals[i]
		var gate := _gates[i]
		if i < count:
			g["kind"] = list[i]["kind"]
			g["meters"] = float(list[i]["meters"])
			g["text"] = list[i]["text"]
			g["color"] = COLORS[list[i]["color"]]
			g["done"] = false
			(gate["label"] as Label3D).text = g["text"]
			(gate["label"] as Label3D).modulate = g["color"]
			(gate["flag"] as StandardMaterial3D).albedo_color = g["color"]
			(gate["flag"] as StandardMaterial3D).emission = g["color"] * 0.35
			for k in 8:
				var sm := (gate["stripes"] as Array)[k] as StandardMaterial3D
				sm.albedo_color = g["color"] if k % 2 == 0 else Color(0.95, 0.95, 0.98)
				sm.emission = sm.albedo_color * 0.35
		else:
			g["done"] = true
		(gate["root"] as Node3D).visible = false

## Every frame: `meters_now` flown, the plane's z, the top of the screen. Gates scroll with the world.
func update(meters_now: float, plane_z: float, top_z: float) -> void:
	for i in count:
		var g := _goals[i]
		var root := _gates[i]["root"] as Node3D
		var ahead := (float(g["meters"]) - meters_now) / Tuning.meters_per_unit   # world units to the gate
		var z := plane_z - ahead
		root.position = Vector3(0.0, 0.0, z)
		root.visible = z > top_z - 3.0 and z < plane_z + 10.0
		if not g["done"] and ahead <= 0.0:
			g["done"] = true
			reached.emit(g["kind"], g["text"], g["color"])

func hide_all() -> void:
	for gate in _gates:
		(gate["root"] as Node3D).visible = false

## Pre-warm: every gate in view with long texts (glyphs), then hide.
func prewarm_show(plane_z: float) -> void:
	for i in POOL:
		var gate := _gates[i]
		(gate["label"] as Label3D).text = ["BEST 12,345 m", "SILVER 1,500 m GOLD BRONZE", "COAST MOUNTAINS STORMFRONT COUNTRYSIDE 3,000 m"][i]
		(gate["root"] as Node3D).position = Vector3(0.0, 0.0, plane_z - 3.0 - 3.5 * i)
		(gate["root"] as Node3D).visible = true
