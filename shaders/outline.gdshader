shader_type spatial;
// Inverted-hull outline for axis-aligned cubes: used as each obstacle's material_overlay.
// Back faces of a slightly enlarged copy are drawn flat black behind the real cube, leaving a
// silhouette rim. Works in the Compatibility (GL) renderer.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // white while flashing
uniform float thickness = 0.07;  // rim width in world units (camera is orthographic: constant on screen)

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Push each cube corner outward along its diagonal so edges stay joined (no gaps at corners).
	world += sign(VERTEX) * thickness;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
