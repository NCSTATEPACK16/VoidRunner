shader_type spatial;
// 3.0 Phase 3: the "3D Studio" look for SpriteForge bakes — the way mid-90s
// sprites were made: model it, light it with a hard key + cool fill + rim, render
// it, palettize it. Everything is in VIEW space with fixed light directions, so
// all 8 yaw angles of a model get identical lighting from the viewer's point of
// view (upper-left key), exactly like a turntable render. Never drawn in-game —
// it only ever renders into SpriteForge's bake viewports at boot.
render_mode unshaded, cull_back;

uniform vec4 base : source_color = vec4(0.6, 0.65, 0.75, 1.0);
// rgb = emission color, a = how much the part glows (1 = pure light, no shading)
uniform vec4 emit : source_color = vec4(0.0);
uniform float spec = 0.7;      // specular strength
uniform float gloss = 28.0;    // specular tightness
uniform float chrome = 0.3;    // fake environment reflection (sky above, dark floor)
uniform float rim = 0.55;      // cool back-light on silhouette edges

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 key = normalize(vec3(-0.55, 0.65, 0.55));
	vec3 fill = normalize(vec3(0.7, -0.35, 0.45));
	float kd = max(dot(n, key), 0.0);
	float fd = max(dot(n, fill), 0.0);
	vec3 col = base.rgb * (0.24 + 1.05 * kd * vec3(1.0, 0.95, 0.86)
		+ 0.38 * fd * vec3(0.45, 0.55, 1.0));
	vec3 r = reflect(-v, n);
	float env = smoothstep(-0.25, 0.65, r.y);
	vec3 env_col = mix(vec3(0.10, 0.08, 0.14), vec3(0.95, 0.97, 1.0), env);
	col = mix(col, env_col * base.rgb * 1.35, chrome);
	float s = pow(max(dot(reflect(-key, n), v), 0.0), gloss) * spec;
	col += vec3(1.0, 0.97, 0.9) * s;
	float fr = pow(1.0 - max(dot(n, v), 0.0), 3.0);
	col += vec3(0.5, 0.65, 1.0) * fr * rim;
	col = mix(col, emit.rgb, emit.a);
	ALBEDO = col;
}
