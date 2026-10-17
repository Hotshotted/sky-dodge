shader_type spatial;
// Inverted-hull outline for axis-aligned cubes: used as the next_pass of an obstacle material.
// Back faces of a slightly enlarged copy are drawn flat black behind the real cube, leaving a
// silhouette rim. Works in the Compatibility (GL) renderer.
render_mode unshaded, cull_front, depth_draw_never, blend_mix;

uniform float thickness = 0.07;      // rim width in world units at the camera
uniform float distance_gain = 0.05;  // extra width per unit of camera distance (keeps it readable far away)
uniform float alpha = 1.0;           // follows the row's fade

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = -(VIEW_MATRIX * vec4(world, 1.0)).z;
	// Push each cube corner outward along its diagonal so edges stay joined (no gaps at corners).
	world += sign(VERTEX) * thickness * (1.0 + max(dist, 0.0) * distance_gain);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = alpha;
}
