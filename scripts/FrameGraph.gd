class_name FrameGraph
extends Control
## ?perf: a small rolling graph of the last frames' real times (ms): one bar per frame, green up to 20 ms, yellow up to
## 33 ms (a missed 30 fps), red above, with guide lines at 16.7 / 33 / 50 ms. Spikes show up as they happen.
## One control, created once; pushing a frame allocates nothing.

const N := 150           # frames shown
const TOP_MS := 50.0     # the top of the graph
var _ms := PackedFloat32Array()
var _head := 0
var worst := 0.0         # worst frame in the window

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(450.0, 120.0)
	size = custom_minimum_size
	_ms.resize(N)

func push(ms: float) -> void:
	_ms[_head] = ms
	_head = (_head + 1) % N
	worst = 0.0
	for v in _ms:
		worst = maxf(worst, v)
	queue_redraw()

func _draw() -> void:
	var w := size.x / N
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.45))
	for i in N:
		var v := _ms[(_head + i) % N]
		if v <= 0.0:
			continue
		var bar := minf(v / TOP_MS, 1.0) * h
		var col := Color(0.35, 0.9, 0.45) if v <= 20.0 else (Color(1.0, 0.85, 0.2) if v <= 33.4 else Color(1.0, 0.3, 0.25))
		draw_rect(Rect2(i * w, h - bar, maxf(w - 0.5, 1.0), bar), col)
	for g in [16.7, 33.3, 50.0]:
		var y: float = h - minf(g / TOP_MS, 1.0) * h
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1, 1, 1, 0.35), 1.0)
