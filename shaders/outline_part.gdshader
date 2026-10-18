shader_type spatial;
// Inverted-hull outline for the Countryside kit's low-poly parts (boxes, cylinders, domes ...).
// Each part is built at its real size (never scaled), centred on its own origin, so pushing every vertex
// outward by `thickness` in the part's own space gives an even rim, and rotating parts keep their rim.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // white while flashing
uniform float thickness = 0.07;

void vertex() {
	vec3 v = VERTEX + sign(VERTEX) * thickness;
	vec3 world = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
