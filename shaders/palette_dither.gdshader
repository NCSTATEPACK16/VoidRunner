shader_type canvas_item;
// Phase G2 -> 3.0: quantize the finished frame to the 256-color game palette with
// 4x4 ordered (Bayer) dithering — the one shader that does the most for "1995
// software renderer" believability. Applied on a full-screen ColorRect in a
// CanvasLayer above the 3D view + HUD, below the menu overlays.
//
// 3.0: the nearest-color search moved out of this shader. PaletteLUT bakes a
// 512x512 lookup table once on the GPU (palette_lut.gdshader); here each pixel
// is one texture fetch, so a 256-color palette costs less per frame than the old
// 40-color loop did.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D lut_tex : filter_nearest;
uniform float spread = 0.07;
// Amber "terminal" mode: collapse the frame to a dithered amber-phosphor ramp,
// the classic black-and-amber financial/monochrome terminal look. 0 = off.
uniform float amber = 0.0;
uniform vec3 amber_tint = vec3(1.0, 0.60, 0.11);

const int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);

vec3 quantize(vec3 c) {
	vec3 q = floor(clamp(c, 0.0, 1.0) * 63.0 + 0.5);   // 0..63 per channel
	vec2 cell = vec2(mod(q.b, 8.0), floor(q.b / 8.0)) * 64.0 + q.rg;
	return texture(lut_tex, (cell + 0.5) / 512.0).rgb;
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	ivec2 px = ivec2(FRAGCOORD.xy);
	float b = float(bayer[(px.y % 4) * 4 + (px.x % 4)]) / 16.0 - 0.5;
	if (amber > 0.5) {
		// luminance -> dithered, stepped amber ramp (few levels = phosphor terminal)
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		l = clamp(l + b * 0.10, 0.0, 1.0);
		float steps = 6.0;
		l = floor(l * steps) / (steps - 1.0);
		vec3 hot = mix(amber_tint, vec3(1.0, 0.92, 0.72), max(l - 0.85, 0.0) / 0.15);
		COLOR = vec4(hot * l, 1.0);
	} else {
		COLOR = vec4(quantize(col + b * spread), 1.0);
	}
}
