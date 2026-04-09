shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 flash_color : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform sampler2D noise_tex;
uniform float flash_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float flash_speed = 25.0;
uniform float scale_modifier = 1.0;

varying float v_noise;

void vertex() {
	// Simple billboarding or scaling logic can be added here
	// For muzzle flashes, we often want them to grow and shrink rapidly
	float time_factor = sin(TIME * flash_speed);
	VERTEX *= (1.0 + time_factor * 0.2) * scale_modifier;
}

void fragment() {
	// Create circular mask
	float dist = distance(UV, vec2(0.5));
	float circle = smoothstep(0.5, 0.1, dist);
	
	// Sample noise for the "jagged" fire look
	vec2 uv_centered = UV - 0.5;
	float angle = atan(uv_centered.y, uv_centered.x);
	float noise = texture(noise_tex, vec2(angle * 0.15, TIME * flash_speed * 0.05)).r;
	
	// Combine components
	float energy = circle * noise * flash_intensity;
	
	// Add a core glow
	float core = smoothstep(0.2, 0.0, dist) * 2.0;
	
	ALBEDO = flash_color.rgb * (energy + core);
	ALPHA = clamp(energy + core, 0.0, 1.0) * flash_color.a;
}