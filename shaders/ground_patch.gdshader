shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// A flat patch of the countryside (field, road, river, roof...): one colour, edges fading out over `feather` world
// units, so nothing in the background has a hard line. The patch is a unit quad scaled to its size; the size comes
// from the model matrix, so the feather is the same width on a long thin road and on a big field.
uniform vec4 color : source_color = vec4(1.0);
uniform float feather = 0.45;

void fragment() {
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	vec2 e = (vec2(0.5) - abs(UV - vec2(0.5))) * size;
	ALBEDO = color.rgb;
	ALPHA = smoothstep(0.0, feather, min(e.x, e.y)) * color.a;
}
