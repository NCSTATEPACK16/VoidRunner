shader_type canvas_item;
// 3.0 Phase 4: the monitor. A full-window pass over everything (game view,
// menus, touch controls) at native window resolution:
//   mode 1 SCANLINES — every one of the 200 virtual rows gets a darker lower
//          band, so the picture reads as a 1995 CRT at any window size
//   mode 2 CRT       — scanlines + barrel curvature + RGB aperture mask +
//          vignette
// Row maths use this rect's own UV, which spans exactly the 320x200 design area
// under canvas_items stretch, so scanlines stay locked to game pixels even when
// the window letterboxes. Curvature is applied in that space and carried back to
// screen space through the rect's UV -> SCREEN_UV derivatives.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float mode = 1.0;
uniform float virtual_rows = 200.0;
uniform float scan_depth = 0.26;

vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	vec2 off = abs(c.yx) / vec2(6.5, 5.2);
	c += c * off * off;
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = UV;
	vec2 suv = SCREEN_UV;
	if (mode > 1.5) {
		vec2 cuv = barrel(uv);
		if (cuv.x < 0.0 || cuv.x > 1.0 || cuv.y < 0.0 || cuv.y > 1.0) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		} else {
			// UV -> SCREEN_UV scale per axis (signed: a flipped axis stays flipped)
			float ux = dFdx(UV.x);
			float uy = dFdy(UV.y);
			vec2 k = vec2(dFdx(SCREEN_UV.x) / (abs(ux) > 1e-7 ? ux : 1e-7),
				dFdy(SCREEN_UV.y) / (abs(uy) > 1e-7 ? uy : 1e-7));
			suv = SCREEN_UV + (cuv - uv) * k;
			uv = cuv;
			vec3 col = texture(screen_tex, suv).rgb;
			float row = fract(uv.y * virtual_rows);
			col *= 1.0 - scan_depth * smoothstep(0.45, 1.0, row);
			float px = mod(FRAGCOORD.x, 3.0);
			vec3 grille = vec3(px < 1.0 ? 1.0 : 0.8, (px >= 1.0 && px < 2.0) ? 1.0 : 0.8,
				px >= 2.0 ? 1.0 : 0.8);
			col *= grille * 1.14;
			vec2 v = uv * (1.0 - uv.yx);
			col *= clamp(pow(v.x * v.y * 20.0, 0.2), 0.0, 1.0);
			COLOR = vec4(col, 1.0);
		}
	} else {
		vec3 col = texture(screen_tex, suv).rgb;
		float row = fract(uv.y * virtual_rows);
		col *= 1.0 - scan_depth * smoothstep(0.45, 1.0, row);
		COLOR = vec4(col, 1.0);
	}
}
