shader_type canvas_item;
// Phase G2: quantize the finished frame to the game palette with 4x4 ordered
// (Bayer) dithering — the one shader that does the most for "1995 software
// renderer" believability. Applied on a full-screen ColorRect in a CanvasLayer
// above the 3D view + HUD, below the menu overlays.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float spread = 0.10;
uniform int palette_size = 40;
uniform vec3 palette[64];
// Amber "terminal" mode: collapse the frame to a dithered amber-phosphor ramp,
// the classic black-and-amber financial/monochrome terminal look. 0 = off.
uniform float amber = 0.0;
uniform vec3 amber_tint = vec3(1.0, 0.60, 0.11);

const int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	ivec2 px = ivec2(FRAGCOORD.xy);
	float b = float(bayer[(px.y % 4) * 4 + (px.x % 4)]) / 16.0 - 0.5;
	if (amber > 0.5) {
		// luminance -> dithered, stepped amber ramp (few levels = phosphor terminal)
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		l = clamp(l + b * spread, 0.0, 1.0);
		float steps = 6.0;
		l = floor(l * steps) / (steps - 1.0);
		vec3 hot = mix(amber_tint, vec3(1.0, 0.92, 0.72), max(l - 0.85, 0.0) / 0.15);
		COLOR = vec4(hot * l, 1.0);
	} else {
		col += b * spread;
		float best = 1e9;
		vec3 best_col = palette[0];
		for (int i = 0; i < palette_size; i++) {
			vec3 d = col - palette[i];
			float dist = dot(d, d);
			if (dist < best) {
				best = dist;
				best_col = palette[i];
			}
		}
		COLOR = vec4(best_col, 1.0);
	}
}
