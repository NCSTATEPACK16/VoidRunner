class_name MusicGen
## Phase G5: original tracker-style music, composed and synthesized entirely in
## code at boot into one looping AudioStreamWAV (pre-rendering avoids per-frame
## generator callbacks, which matters on the single-threaded web export).
## 140 BPM, 8 bars of 16 steps: square bass arpeggio, noise kick/hat, square lead.

const RATE := 22050
const BPM := 140.0

# A harmonic-minor-ish loop in E: step values are semitones from E2 (-1 = rest).
const BASS := [
	0, -1, 0, 12, 0, -1, 0, 10, 0, -1, 0, 12, 0, -1, 3, 5,
	0, -1, 0, 12, 0, -1, 0, 10, -2, -1, -2, 10, -2, -1, 1, 3,
]
const LEAD := [
	12, -1, -1, 15, -1, 17, -1, -1, 12, -1, -1, 10, -1, -1, -1, -1,
	12, -1, -1, 15, -1, 19, -1, 17, -1, -1, 15, -1, 13, -1, 12, -1,
]
const KICK_STEPS := [0, 4, 8, 12]
const HAT_STEPS := [2, 6, 10, 14]


static func render_loop() -> AudioStreamWAV:
	var step_len := 60.0 / BPM / 4.0
	var steps := BASS.size() * 2   # play the 32-step pattern twice
	var total := int(steps * step_len * RATE)
	var samples := PackedFloat32Array()
	samples.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1995
	var bass_phase := 0.0
	var lead_phase := 0.0
	for i in total:
		var t := float(i) / RATE
		var step_f := t / step_len
		var step := int(step_f) % BASS.size()
		var in_step := fmod(t, step_len)
		var v := 0.0
		# bass: square arpeggio an octave below
		var bass_note: int = BASS[step]
		if bass_note >= 0:
			var f := 82.41 * pow(2.0, bass_note / 12.0)   # E2
			bass_phase += f / RATE
			v += (1.0 if fmod(bass_phase, 1.0) < 0.5 else -1.0) * 0.10 * exp(-in_step * 8.0)
		# lead: thinner square, slight detune shimmer
		var lead_note: int = LEAD[step]
		if lead_note >= 0:
			var lf := 329.63 * pow(2.0, lead_note / 12.0)  # E4
			lead_phase += lf / RATE
			var duty := 0.3 + 0.05 * sin(t * 5.0)
			v += (1.0 if fmod(lead_phase, 1.0) < duty else -1.0) * 0.055 * exp(-in_step * 5.0)
		# drums: noise bursts
		var bar_step := step % 16
		if bar_step in KICK_STEPS and in_step < 0.09:
			v += rng.randf_range(-1.0, 1.0) * 0.22 * exp(-in_step * 55.0)
			v += sin(TAU * lerpf(120.0, 40.0, in_step / 0.09) * in_step) * 0.25 * exp(-in_step * 30.0)
		if bar_step in HAT_STEPS and in_step < 0.03:
			v += rng.randf_range(-1.0, 1.0) * 0.07 * exp(-in_step * 160.0)
		samples[i] = clampf(v, -1.0, 1.0)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(samples[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total
	return wav
