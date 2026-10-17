class_name Collision
extends RefCounted
## 2D geometry (x, z plane) for capsule-vs-rectangle collision. A capsule is a segment a-b
## plus a radius, i.e. a rectangle with fully rounded ends.

## Distance from point p to the segment a-b.
static func point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.000001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Distance from point p to an axis-aligned rectangle centred on the origin with half size h
## (0 when p is inside).
static func point_rect(p: Vector2, h: Vector2) -> float:
	return Vector2(maxf(absf(p.x) - h.x, 0.0), maxf(absf(p.y) - h.y, 0.0)).length()

## True if the segment a-b touches the rectangle (Liang-Barsky clipping).
static func segment_hits_rect(a: Vector2, b: Vector2, h: Vector2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var da: float = d[axis]
		var pa: float = a[axis]
		var lim: float = h[axis]
		if absf(da) < 0.000001:
			if absf(pa) > lim:
				return false
		else:
			var ta := (-lim - pa) / da
			var tb := (lim - pa) / da
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true

## Distance between the segment a-b and the rectangle (0 if they overlap).
static func segment_rect(a: Vector2, b: Vector2, h: Vector2) -> float:
	if segment_hits_rect(a, b, h):
		return 0.0
	var best := minf(point_rect(a, h), point_rect(b, h))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			best = minf(best, point_segment(Vector2(sx * h.x, sz * h.y), a, b))
	return best
