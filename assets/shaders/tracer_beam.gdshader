shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 core_color : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float core_sharpness : hint_range(0.5, 8.0) = 3.5;
uniform float tip_softness : hint_range(0.02, 0.25) = 0.1;

void fragment() {
	float radial = abs(UV.x - 0.5) * 2.0;
	float core = pow(clamp(1.0 - radial, 0.0, 1.0), core_sharpness);
	float tip_a = smoothstep(0.0, tip_softness, UV.y);
	float tip_b = smoothstep(1.0, 1.0 - tip_softness, UV.y);
	float tip = tip_a * tip_b;
	float glow = core * 2.2 + 0.25;
	vec3 rgb = core_color.rgb * glow * tip;
	float a = clamp(core * tip * fade, 0.0, 1.0);
	ALBEDO = rgb;
	ALPHA = a;
}
