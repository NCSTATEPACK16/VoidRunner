extends Node
## Autoload: all-procedural audio. Every sound is synthesized into an AudioStreamWAV
## buffer once at boot (cheap, deterministic, web-safe); playback goes through a small
## pool of AudioStreamPlayers. Nothing plays until unlock() runs inside a user gesture
## (browser autoplay rules — same trick as the v2.2 web build's Start click).

const SAMPLE_RATE := 22050
const POOL_SIZE := 8

var _pool: Array[AudioStreamPlayer] = []
var _pool_cursor := 0
var _engine: AudioStreamPlayer
var _music: AudioStreamPlayer
var _unlocked := false

var _laser_cache := {}
var _boom_small: AudioStreamWAV
var _boom_big: AudioStreamWAV
var _hit: AudioStreamWAV
var _select: AudioStreamWAV
var _overheat: AudioStreamWAV
var _portal: AudioStreamWAV
var _clank: AudioStreamWAV
var _dodge: AudioStreamWAV
var _engine_loop: AudioStreamWAV


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_boom_small = _render_boom(false)
	_boom_big = _render_boom(true)
	_hit = _render_hit()
	_select = _render_select()
	_overheat = _render_overheat()
	_portal = _render_portal()
	_clank = _render_clank()
	_dodge = _render_dodge()
	_engine_loop = _render_engine_loop()
	_engine = AudioStreamPlayer.new()
	_engine.stream = _engine_loop
	_engine.volume_db = -80.0
	add_child(_engine)
	_music = AudioStreamPlayer.new()
	_music.stream = MusicGen.render_loop()
	_music.volume_db = -13.0
	add_child(_music)


func unlock() -> void:
	## Call from a user-gesture input handler (start button) before any playback.
	if _unlocked:
		return
	_unlocked = true
	_engine.play()
	_music.play()


func set_engine(speed: float, max_speed: float) -> void:
	if not _unlocked:
		return
	var amount := clampf(speed / max_speed, 0.0, 1.0)
	_engine.volume_db = linear_to_db(0.05 + amount * 0.06)
	_engine.pitch_scale = 0.8 + amount * 0.8


func stop_engine() -> void:
	_engine.volume_db = -80.0


func play_laser(freq: float) -> void:
	if not _laser_cache.has(freq):
		_laser_cache[freq] = _render_laser(freq)
	_play(_laser_cache[freq])


func play_boom(big: bool) -> void:
	_play(_boom_big if big else _boom_small)


func play_hit() -> void:
	_play(_hit)


func play_select() -> void:
	_play(_select)


func play_overheat() -> void:
	_play(_overheat)


func play_portal() -> void:
	_play(_portal)


func play_clank() -> void:
	_play(_clank)


func play_dodge() -> void:
	_play(_dodge)


func _play(stream: AudioStreamWAV) -> void:
	if not _unlocked:
		return
	var p := _pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % POOL_SIZE
	p.stream = stream
	p.play()


# ---------- synthesis ----------

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func _render_laser(f0: float) -> AudioStreamWAV:
	# Square pew sweeping down to 22% of start frequency over 0.12 s.
	var n := int(SAMPLE_RATE * 0.13)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var f := lerpf(f0, maxf(80.0, f0 * 0.22), minf(1.0, t / 0.11))
		phase += f / SAMPLE_RATE
		var env := 0.12 * exp(-t * 40.0)
		out[i] = (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * env
	return _make_wav(out)


func _render_boom(big: bool) -> AudioStreamWAV:
	# Low-pass filtered noise crunch, falling cutoff.
	var n := int(SAMPLE_RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if big else 11
	var lp := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var cutoff := lerpf(900.0 if big else 600.0, 60.0, minf(1.0, t / 0.45))
		var alpha := clampf(cutoff / (SAMPLE_RATE * 0.5), 0.0, 1.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * alpha * 4.0
		out[i] = clampf(lp, -1.0, 1.0) * (0.5 if big else 0.3) * exp(-t * 7.0)
	return _make_wav(out)


func _render_hit() -> AudioStreamWAV:
	# Saw thunk sweeping 190 -> 70 Hz.
	var n := int(SAMPLE_RATE * 0.24)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var f := lerpf(190.0, 70.0, minf(1.0, t / 0.2))
		phase += f / SAMPLE_RATE
		out[i] = (fmod(phase, 1.0) * 2.0 - 1.0) * 0.22 * exp(-t * 18.0)
	return _make_wav(out)


func _render_select() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * 0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		phase += 620.0 / SAMPLE_RATE
		out[i] = (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * 0.08 * exp(-t * 60.0)
	return _make_wav(out)


func _render_overheat() -> AudioStreamWAV:
	# Three two-tone klaxon bursts (440/310 Hz).
	var n := int(SAMPLE_RATE * 0.66)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var burst := fmod(t, 0.22)
		var f := 440.0 if burst < 0.11 else 310.0
		phase += f / SAMPLE_RATE
		var env := 0.12 * exp(-fmod(burst, 0.11) * 25.0)
		out[i] = (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * env
	return _make_wav(out)


func _render_portal() -> AudioStreamWAV:
	# Ascending triangle jingle: 330-440-550-660-880.
	var notes: Array[float] = [330.0, 440.0, 550.0, 660.0, 880.0]
	var n := int(SAMPLE_RATE * 0.75)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in notes.size():
		var start := int(k * 0.09 * SAMPLE_RATE)
		var phase := 0.0
		for i in range(start, mini(n, start + int(0.3 * SAMPLE_RATE))):
			var t := float(i - start) / SAMPLE_RATE
			phase += notes[k] / SAMPLE_RATE
			var tri := absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
			out[i] = clampf(out[i] + tri * 0.14 * exp(-t * 9.0), -1.0, 1.0)
	return _make_wav(out)


func _render_clank() -> AudioStreamWAV:
	# K3 crusher telegraph: two short metallic knocks — a detuned square pair with
	# a fast noise transient, repeated once at lower pitch.
	var n := int(SAMPLE_RATE * 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for k in 2:
		var start := int(k * SAMPLE_RATE * 0.13)
		var f0 := 520.0 if k == 0 else 390.0
		var phase := 0.0
		for i in int(SAMPLE_RATE * 0.11):
			var t := float(i) / SAMPLE_RATE
			phase += f0 * (1.0 - t * 2.0) / SAMPLE_RATE
			var env := 0.2 * exp(-t * 55.0)
			var sq := 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			var v := sq * env + rng.randf_range(-1.0, 1.0) * env * 0.5
			if start + i < n:
				out[start + i] += v
	return _make_wav(out)


func _render_dodge() -> AudioStreamWAV:
	# K4 evade whoosh: band-swept noise that rises then falls over 0.26 s.
	var n := int(SAMPLE_RATE * 0.28)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var sweep := sin(minf(1.0, t / 0.26) * PI)
		var cutoff := 300.0 + sweep * 2200.0
		var alpha := clampf(cutoff / (SAMPLE_RATE * 0.5), 0.0, 1.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * alpha * 4.0
		lp2 += (lp - lp2) * 0.4
		out[i] = clampf(lp2, -1.0, 1.0) * 0.3 * sweep
	return _make_wav(out)


func _render_engine_loop() -> AudioStreamWAV:
	# One-second looping low saw hum (pitch-scaled with speed at runtime).
	var n := SAMPLE_RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var phase := fmod(float(i) * 55.0 / SAMPLE_RATE, 1.0)
		lp += ((phase * 2.0 - 1.0) - lp) * 0.05
		out[i] = lp * 0.9
	return _make_wav(out, true)
