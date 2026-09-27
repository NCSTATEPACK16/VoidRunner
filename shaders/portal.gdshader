shader_type spatial;
// 3.0 Phase 2: the exit gate. The disc (solid = 0) is a three-armed vortex that
// spins into a white-hot core; the torus around it (solid = 1) is a pulsing
// accent-colored frame. The palette quantizer turns the smooth spiral into
// chunky DOS color bands. One shader, two materials, both warmed at briefing.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec4 col_a : source_color = vec4(0.13, 0.77, 0.85, 1.0);
uniform vec4 col_b : source_color = vec4(0.02, 0.10, 0.35, 1.0);
uniform float solid = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float arms = sin(a * 3.0 - r * 9.0 + TIME * 5.0);
	float core = smoothstep(0.38, 0.0, r);
	vec3 swirl = mix(col_b.rgb, col_a.rgb, smoothstep(-0.25, 0.65, arms)) + vec3(core);
	float edge = (1.0 - smoothstep(0.84, 1.0, r)) * 0.92;
	vec3 frame = col_a.rgb * (0.85 + 0.25 * sin(TIME * 6.0));
	ALBEDO = mix(swirl, frame, solid);
	ALPHA = mix(edge, 1.0, solid);
}
