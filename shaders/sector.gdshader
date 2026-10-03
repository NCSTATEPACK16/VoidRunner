shader_type spatial;
// 3.0 Phase 2: the one material every piece of world geometry draws with — the
// mid-90s software-renderer lighting model, done on the GPU:
//   * baked sector light: per-vertex COLOR written by WorldBuilder from the lamp
//     fixtures placed along the tunnel (encoded at half scale — vertex colors are
//     8-bit unorm, so 0.5 in the buffer means 1.0 light and lamps can overbright)
//   * dynamic light: up to 8 point lights (headlight, muzzle flash, explosions,
//     glowing shots, flickering arena lamps) pushed as uniform arrays by LightRig
//     — no OmniLight3D exists anywhere, so the GL Compatibility renderer never
//     pays for per-light passes
//   * light banding: the summed light is quantized into steps, the classic
//     "colormap" look where light falls off in visible rings
//   * full-bright texels: texture alpha < 1 marks light panels, screens, lava
//     cracks and glowing runes, which ignore lighting entirely
//   * v4a distance diminishing: light fades to black between dist_begin and
//     dist_end and is folded in BEFORE the banding step, so the tunnel darkens in
//     the same visible rings (the colormap look). World geometry skips Godot's
//     smooth depth fog; sprites keep it, with the same endpoints (LightRig pushes
//     them). Full-bright texels only dim to glow_floor, so a light panel or a lava
//     vein still shows far down a dark tunnel.
//   * v4a colour cycling: on materials with cycle_speed > 0, a bright crest
//     marches through the full-bright texels on TIME alone (no per-frame CPU
//     work); the palette pass snaps it to ramp shades, like a DOS palette cycle.
// Every world material is this one shader with different uniforms, so the web
// build compiles it exactly once.
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 emit_col : source_color = vec3(0.0);   // constant self-glow (door accents)
uniform float glow_gain = 1.0;          // full-bright texel intensity
uniform float light_scale = 2.0;        // vertex light decode (see header)
uniform float use_vertex_light = 1.0;   // 0 for primitive meshes with no vertex color
uniform float base_light = 0.6;         // light level used when use_vertex_light = 0
uniform vec2 uv_scroll = vec2(0.0);     // animated strips: UV units per second
uniform float bands = 12.0;             // light quantization steps; 0 = smooth
uniform float dist_begin = 18.0;        // v4a: banded distance darkness starts here
uniform float dist_end = 110.0;         // ...and reaches black here (theme fog_end)
uniform float glow_floor = 0.3;         // full-bright texels never dim below this
uniform float cycle_speed = 0.0;        // v4a: glow crest speed; 0 = no cycling
uniform vec4 dyn_pos[8];                // xyz world position, w = range (0 = slot off)
uniform vec4 dyn_col[8];                // rgb = color * energy

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV + uv_scroll * TIME);
	vec3 light = mix(vec3(base_light), COLOR.rgb * light_scale, use_vertex_light);
	for (int i = 0; i < 8; i++) {
		float range = dyn_pos[i].w;
		if (range > 0.0) {
			vec3 d = dyn_pos[i].xyz - wpos;
			float dist = length(d);
			float att = clamp(1.0 - dist / range, 0.0, 1.0);
			att *= att;
			// half-lambert so faces edge-on to a blast still catch some of it
			float ndl = clamp(dot(wnrm, d / max(dist, 0.001)), 0.0, 1.0) * 0.75 + 0.25;
			light += dyn_col[i].rgb * (att * ndl);
		}
	}
	// v4a: distance diminishing, banded together with the light (VERTEX is the
	// view-space position here, so its length is the distance from the eye)
	float df = clamp(1.0 - (length(VERTEX) - dist_begin) / max(dist_end - dist_begin, 1.0),
		0.0, 1.0);
	light *= df;
	float glow_dim = max(df, glow_floor);
	if (bands > 0.0) {
		light = floor(light * bands + 0.5) / bands;
		glow_dim = floor(glow_dim * bands + 0.5) / bands;
	}
	float glow = 1.0 - tex.a;
	vec3 col = tex.rgb * tint.rgb * light;
	vec3 lit = tex.rgb * glow_gain;
	if (cycle_speed > 0.0) {
		// a sawtooth crest keyed on the texel's own brightness and its place on the
		// face, so it travels along the glow rather than blinking it all at once
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		float wave = fract(lum * 2.0 + (UV.x + UV.y) * 1.5 - TIME * cycle_speed);
		lit *= 0.55 + 0.75 * wave;
	}
	ALBEDO = mix(col, lit * glow_dim, glow) + emit_col * df;
}
