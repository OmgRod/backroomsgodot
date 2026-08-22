shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// CRT geometry
uniform float warp_amount : hint_range(0.0, 0.15) = 0.035;
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.65;

// Scanlines
uniform float scanline_count : hint_range(50.0, 1200.0) = 480.0;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.22;
uniform float scanline_softness : hint_range(0.0, 1.0) = 0.35;

// CRT phosphors
uniform float phosphor_strength : hint_range(0.0, 1.0) = 0.16;
uniform float phosphor_size : hint_range(1.0, 8.0) = 3.0;

// Signal distortion
uniform float signal_wobble : hint_range(0.0, 0.02) = 0.0025;
uniform float horizontal_jitter : hint_range(0.0, 0.02) = 0.0015;

// RGB separation
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0015;

// Glow
uniform float bloom_strength : hint_range(0.0, 1.0) = 0.12;

// CRT brightness
uniform float brightness : hint_range(0.5, 2.0) = 1.05;
uniform float flicker : hint_range(0.0, 0.1) = 0.015;

// Very subtle noise
uniform float noise_amount : hint_range(0.0, 0.1) = 0.012;


// ------------------------------------------------------------
// Random
// ------------------------------------------------------------

float random(vec2 p) {
    return fract(
        sin(dot(p, vec2(12.9898, 78.233))) *
        43758.5453123
    );
}


// ------------------------------------------------------------
// CRT barrel distortion
// ------------------------------------------------------------

vec2 crt_warp(vec2 uv) {
    vec2 centered = uv - 0.5;

    float r2 = dot(centered, centered);

    centered *= 1.0 + r2 * warp_amount * 4.0;

    return centered + 0.5;
}


// ------------------------------------------------------------
// Horizontal signal distortion
// ------------------------------------------------------------

float line_noise(float y) {
    return random(vec2(floor(y * scanline_count), TIME * 0.15));
}

vec2 signal_distort(vec2 uv) {

    // Slow horizontal CRT wobble
    float wobble =
        sin(uv.y * 18.0 + TIME * 1.7) *
        sin(uv.y * 7.0 - TIME * 0.8) *
        signal_wobble;

    // Small per-line horizontal displacement
    float line_jitter =
        (line_noise(uv.y) - 0.5) *
        horizontal_jitter;

    uv.x += wobble + line_jitter;

    return uv;
}


// ------------------------------------------------------------
// RGB phosphor pattern
// ------------------------------------------------------------

vec3 phosphor_pattern(vec2 uv) {

    float pixel_x = floor(uv.x * 1920.0 / phosphor_size);

    float subpixel = mod(pixel_x, 3.0);

    vec3 mask = vec3(0.55);

    if (subpixel < 1.0) {
        mask.r += phosphor_strength;
    }
    else if (subpixel < 2.0) {
        mask.g += phosphor_strength;
    }
    else {
        mask.b += phosphor_strength;
    }

    return mask;
}


// ------------------------------------------------------------
// Scanlines
// ------------------------------------------------------------

float scanlines(vec2 uv) {

    float line = uv.y * scanline_count;

    // Smooth CRT scanline pattern
    float s = sin(line * 3.14159265);

    // Convert sine into dark bands
    float darkness = s * 0.5 + 0.5;

    // Softer scanlines
    darkness = mix(
        darkness,
        smoothstep(
            0.0,
            1.0,
            darkness
        ),
        scanline_softness
    );

    return 1.0 - darkness * scanline_intensity;
}


// ------------------------------------------------------------
// Vignette
// ------------------------------------------------------------

float vignette(vec2 uv) {

    vec2 centered = uv - 0.5;

    float distance_from_center =
        dot(centered, centered) * 4.0;

    return 1.0 -
        smoothstep(
            0.15,
            1.0,
            distance_from_center
        ) * vignette_intensity;
}


// ------------------------------------------------------------
// Fake CRT glow
// ------------------------------------------------------------

vec3 crt_glow(vec2 uv) {

    vec2 pixel = 1.0 / vec2(1920.0, 1080.0);

    vec3 glow = vec3(0.0);

    glow += texture(
        SCREEN_TEXTURE,
        uv + vec2(pixel.x * 2.0, 0.0)
    ).rgb;

    glow += texture(
        SCREEN_TEXTURE,
        uv - vec2(pixel.x * 2.0, 0.0)
    ).rgb;

    glow += texture(
        SCREEN_TEXTURE,
        uv + vec2(0.0, pixel.y * 2.0)
    ).rgb;

    glow += texture(
        SCREEN_TEXTURE,
        uv - vec2(0.0, pixel.y * 2.0)
    ).rgb;

    glow *= 0.25;

    return glow;
}


// ------------------------------------------------------------
// Fragment
// ------------------------------------------------------------

void fragment() {

    // CRT screen curvature
    vec2 uv = crt_warp(SCREEN_UV);

    // Black curved edges
    if (
        uv.x < 0.0 ||
        uv.x > 1.0 ||
        uv.y < 0.0 ||
        uv.y > 1.0
    ) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    }


    // Signal movement
    uv = signal_distort(uv);


    // --------------------------------------------------------
    // RGB CRT sampling
    // --------------------------------------------------------

    float r = texture(
        SCREEN_TEXTURE,
        uv + vec2(chromatic_aberration, 0.0)
    ).r;

    float g = texture(
        SCREEN_TEXTURE,
        uv
    ).g;

    float b = texture(
        SCREEN_TEXTURE,
        uv - vec2(chromatic_aberration, 0.0)
    ).b;

    vec3 color = vec3(r, g, b);


    // --------------------------------------------------------
    // CRT phosphor mask
    // --------------------------------------------------------

    color *= phosphor_pattern(uv);


    // --------------------------------------------------------
    // Scanlines
    // --------------------------------------------------------

    color *= scanlines(uv);


    // --------------------------------------------------------
    // Glow between phosphors
    // --------------------------------------------------------

    vec3 glow = crt_glow(uv);

    // Only let brighter pixels contribute significantly
    float glow_amount =
        max(max(glow.r, glow.g), glow.b);

    glow *= glow_amount * bloom_strength;

    color += glow;


    // --------------------------------------------------------
    // CRT flicker
    // --------------------------------------------------------

    float flicker_amount =
        1.0 +
        sin(TIME * 48.0) *
        flicker;

    color *= flicker_amount;


    // --------------------------------------------------------
    // Very subtle analog noise
    // --------------------------------------------------------

    float noise =
        random(
            floor(uv * vec2(1920.0, 1080.0)) +
            TIME * 20.0
        );

    color +=
        (noise - 0.5) *
        noise_amount;


    // --------------------------------------------------------
    // Vignette
    // --------------------------------------------------------

    color *= vignette(uv);


    // --------------------------------------------------------
    // CRT brightness / slight gamma
    // --------------------------------------------------------

    color *= brightness;

    color = pow(
        max(color, vec3(0.0)),
        vec3(0.95)
    );


    COLOR = vec4(color, 1.0);
}