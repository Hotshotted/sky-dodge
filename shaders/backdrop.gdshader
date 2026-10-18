shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back;
// The ground plane under the play layer shows the countryside picture (drawn small by GroundWorld) with a little extra
// blur, in screen space. Without the picture (?nofx=ground) it is one flat colour.
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec3 fallback : source_color = vec3(0.2, 0.26, 0.34);
uniform float use_tex = 1.0;
uniform vec2 texel = vec2(0.0037, 0.0021);
uniform float radius = 1.6;

void fragment() {
	vec3 c = fallback;
	if (use_tex > 0.5) {
		vec2 o = texel * radius;
		c = texture(tex, SCREEN_UV).rgb * 0.36;
		c += texture(tex, SCREEN_UV + vec2(o.x, o.y)).rgb * 0.16;
		c += texture(tex, SCREEN_UV + vec2(-o.x, o.y)).rgb * 0.16;
		c += texture(tex, SCREEN_UV + vec2(o.x, -o.y)).rgb * 0.16;
		c += texture(tex, SCREEN_UV + vec2(-o.x, -o.y)).rgb * 0.16;
	}
	ALBEDO = c;
}
