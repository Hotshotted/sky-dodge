shader_type spatial;
// A coin lying in the play layer: a gold disc with a crisp black rim and a lighter inner ring. One shared quad for every
// pooled coin (a MultiMesh), so a whole screen of coins is one draw call.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 gold : source_color = vec4(1.0, 0.8, 0.12, 1.0);
uniform vec4 shine : source_color = vec4(1.0, 0.95, 0.55, 1.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec3 c = gold.rgb;
	if (r > 0.82) {
		c = vec3(0.0);                          // the rim
	} else if (r > 0.52 && r < 0.64) {
		c = shine.rgb;                          // the inner ring
	}
	ALBEDO = c;
}
