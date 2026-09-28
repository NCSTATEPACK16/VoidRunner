shader_type canvas_item;
// 3.0 Phase 1: bakes the palette lookup table ONCE (PaletteLUT renders this into
// a 512x512 SubViewport a single time). The table is 64 blue slices laid out on
// an 8x8 grid, each slice 64x64 texels (red -> x, green -> y). Every texel holds
// the palette entry nearest to its (r, g, b) cell, so the per-frame quantize in
// palette_dither.gdshader is one texture fetch instead of a 256-entry search per
// pixel. The palette comes in as a 256x1 texture, not a uniform array: a minimal
// WebGL2 only guarantees 224 fragment uniform vectors.
//
// Addressing is UV-based on both ends (this rect's UV here, texture() at texel
// centres in the dither shader), so it is immune to render-target row order.

uniform sampler2D palette_tex : filter_nearest;
uniform int palette_size = 256;

void fragment() {
	ivec2 px = ivec2(floor(UV * 512.0));
	ivec2 slice = px / 64;
	ivec2 inner = px - slice * 64;
	vec3 c = vec3(float(inner.x), float(inner.y), float(slice.y * 8 + slice.x)) / 63.0;
	float best = 1e9;
	vec3 best_col = vec3(0.0);
	for (int i = 0; i < palette_size; i++) {
		vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
		vec3 d = c - p;
		// luma-weighted distance: keeps dark blues from snapping to black and
		// greens from snapping to grey, which a plain RGB distance does
		float dist = d.r * d.r * 0.30 + d.g * d.g * 0.59 + d.b * d.b * 0.11;
		if (dist < best) {
			best = dist;
			best_col = p;
		}
	}
	COLOR = vec4(best_col, 1.0);
}
