shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float scanline_count : hint_range(0.0, 1080.0) = 300.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.25;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.003;
uniform float noise_amount : hint_range(0.0, 0.2) = 0.05;
uniform float warp_amount : hint_range(0.0, 0.1) = 0.02;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;

// Random noise generator
float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Curved CRT screen warp deformation
vec2 warp(vec2 uv) {
	vec2 dc = abs(0.5 - uv);
	dc *= dc;
	uv.x += uv.x < 0.5 ? +dc.y * warp_amount : -dc.y * warp_amount;
	uv.y += uv.y < 0.5 ? +dc.x * warp_amount : -dc.x * warp_amount;
	return uv;
}

void fragment() {
	vec2 uv = warp(SCREEN_UV);
	
	// Out-of-bounds check for curved edges
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// 1. Chromatic Aberration (Color Fringing)
		float r = texture(SCREEN_TEXTURE, uv + vec2(chromatic_aberration, 0.0)).r;
		float g = texture(SCREEN_TEXTURE, uv).g;
		float b = texture(SCREEN_TEXTURE, uv - vec2(chromatic_aberration, 0.0)).b;
		vec3 color = vec3(r, g, b);
		
		// 2. Scanlines
		float scanline = sin(uv.y * scanline_count * 3.14159) * 0.5 + 0.5;
		color -= scanline * scanline_intensity * color;
		
		// 3. Static Grain Noise
		float static_noise = random(uv + vec2(TIME * 0.1, TIME * 0.2));
		color += (static_noise - 0.5) * noise_amount;
		
		// 4. CRT Vignette
		vec2 vignette_uv = uv * (1.0 - uv.yx);
		float vignette = vignette_uv.x * vignette_uv.y * 15.0;
		vignette = pow(vignette, vignette_intensity);
		color *= vignette;
		
		COLOR = vec4(color, 1.0);
	}
}