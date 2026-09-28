class_name MusicGen
extends RefCounted
## Phase G5 → 3.0 phase 6: original music, composed and synthesized entirely in
## code (pre-rendered, not generated per frame — that matters on the
## single-threaded web export).
##
## 3.0 rewrites the voices as 2-operator FM, the sound of mid-90s DOS sound
## cards: a plucky slap bass (modulator index snapping shut after the attack), a
## brassy legato lead that brightens as it swells and picks up vibrato, bell-like
## arps (modulator an octave up), a three-note pad that follows the chords, and
## kick / snare / hat built from noise and pitch sweeps. The song grew from one
## 2-bar riff played twice into eight 2-bar phrases (~27 s at 140 BPM):
##   A (the original riff) · A2 (its answer) · B (lift to C and D) ·
##   B2 (Am to B, the dominant) · C (breakdown: bells over the pad) ·
##   C2 (build with a snare roll) · A · A3 (turnaround back to the top)
##
## It renders as three sample-aligned STEMS on synced players — 0 BASE (bass,
## pad, downbeat kicks), 1 COMBAT (lead, snare, hats), 2 FRENZY (arps, extra
## percussion). AudioSys layers them by intensity, which is exactly the old
## three-mix crossfade (a mix was always base + the layers above it), but every
## voice is synthesized once instead of three times. The render is a resumable
## job: AudioSys feeds it a few milliseconds per frame behind the title screen,
## so boot never waits on the soundtrack.

const RATE := 22050
const BPM := 140.0
const SPS := 2362             # samples per 16th step (60 / 140 / 4 * 22050)
const STEPS := 32             # per phrase (2 bars)
const R := -99                # rest
const T := -98                # tie: hold the lead's current note

const E2 := 82.41             # bass root
const E3 := 164.81            # pad root
const E4 := 329.63            # lead root
const E5 := 659.26            # arp root

## Phrase order; indexes into the pattern tables below.
const SONG := [0, 1, 2, 3, 4, 5, 0, 6]

# Bass, in semitones from E2 (R = rest). A single hit rings with a slap decay.
const BASS := [
	[0, R, 0, 12, 0, R, 0, 10, 0, R, 0, 12, 0, R, 3, 5,          # A: the riff
	 0, R, 0, 12, 0, R, 0, 10, -2, R, -2, 10, -2, R, 1, 3],
	[0, R, 0, 12, 0, R, 0, 10, 0, R, 0, 12, 0, R, 3, 5,          # A2
	 0, R, 0, 12, 0, R, 0, 10, -2, R, -2, 10, -2, R, 1, 3],
	[-4, R, -4, 8, -4, R, -4, 3, -4, R, -4, 8, -4, R, -4, 6,     # B: C ... D
	 -2, R, -2, 10, -2, R, -2, 5, -2, R, -2, 10, -2, R, 0, 2],
	[5, R, 5, 17, 5, R, 5, 12, 5, R, 5, 17, 5, R, 3, 5,          # B2: Am ... B
	 7, R, 7, 19, 7, R, 7, 14, 7, R, 7, 19, 7, 6, 5, 3],
	[0, R, R, R, R, R, R, R, 0, R, R, R, R, R, R, R,             # C: breakdown
	 -4, R, R, R, R, R, R, R, -2, R, R, R, R, R, R, R],
	[0, R, 0, R, 0, R, 0, R, 0, R, 0, R, 0, R, 0, R,             # C2: build
	 -4, R, -4, R, -4, R, -4, R, -2, R, -2, R, -2, -2, -2, -2],
	[0, R, 0, 12, 0, R, 0, 10, 0, R, 0, 12, 0, R, 3, 5,          # A3: turnaround
	 0, R, 0, 12, 0, R, 0, 10, -2, R, -2, 10, 7, 5, 3, 2],
]
# Lead, in semitones from E4 (T = hold, R = release).
const LEAD := [
	[12, T, T, 15, T, 17, T, T, 12, T, T, 10, T, T, T, R,
	 12, T, T, 15, T, 19, T, 17, T, T, 15, T, 13, T, 12, T],
	[19, T, T, 17, T, 15, T, T, 14, T, T, 12, T, T, T, R,
	 12, T, T, 15, T, 17, T, 19, T, T, 20, T, 19, T, T, R],
	[20, T, T, T, 19, T, 15, T, 12, T, 15, T, 19, T, 20, T,
	 22, T, T, T, 20, T, 19, T, 17, T, T, T, 14, T, T, R],
	[17, T, 20, T, 24, T, T, T, 22, T, 20, T, 17, T, T, R,
	 19, T, T, T, 23, T, T, T, 26, T, T, T, 23, T, 19, T],
	[R, R, R, R, R, R, R, R, R, R, R, R, R, R, R, R,
	 R, R, R, R, R, R, R, R, R, R, R, R, R, R, R, R],
	[12, T, T, T, T, T, T, T, 15, T, T, T, T, T, T, R,
	 17, T, T, T, T, T, T, T, 19, T, T, T, 22, T, 23, T],
	[19, T, T, 17, T, 15, T, T, 14, T, T, 12, T, T, T, R,
	 15, T, 14, T, 12, T, 11, T, 12, T, T, T, T, T, R, R],
]
## Chord per bar of each phrase: [root semitones from E, 1 = major / 0 = minor].
const CHORDS := [
	[[0, 0], [0, 0]], [[0, 0], [0, 0]], [[-4, 1], [-2, 1]], [[5, 0], [7, 1]],
	[[0, 0], [-4, 1]], [[0, 0], [-4, 1]], [[0, 0], [7, 1]],
]
const PHRASE_BREAK := 4       # C: no kit, no lead — bells over the pad
const PHRASE_BUILD := 5       # C2: the snare rolls in

static var _cache: Array[AudioStreamWAV] = []

var _bytes: Array[PackedByteArray] = []
var _step := 0
var _rng := RandomNumberGenerator.new()
# voice state (phases in cycles, envelopes as per-sample multipliers)
var _bass_f := 0.0
var _bass_ph := 0.0
var _bass_amp := 0.0
var _bass_idx := 0.0
var _lead_f := 0.0
var _lead_ph := 0.0
var _lead_amp := 0.0
var _lead_goal := 0.0
var _lead_t := 0.0
var _arp_f := 0.0
var _arp_ph := 0.0
var _arp_amp := 0.0
var _arp_idx := 0.0
var _pad0 := 0.0
var _pad1 := 0.0
var _pad2 := 0.0
var _kick_t := -1.0           # < 0 = idle
var _kick_ph := 0.0
var _kick_amp := 0.0
var _kick_stem := 0
var _snare_t := -1.0
var _snare_amp := 0.0
var _snare_stem := 1
var _hat_t := -1.0
var _hat_amp := 0.0
var _hat_decay := 0.0
var _hat_stem := 1
var _noise_prev := 0.0


func _init() -> void:
	_rng.seed = 1995
	var n := total_steps() * SPS
	for s in 3:
		var b := PackedByteArray()
		b.resize(n * 2)
		_bytes.append(b)


static func total_steps() -> int:
	return SONG.size() * STEPS


## Render steps until `budget_usec` is spent; true once the whole song is done.
func step(budget_usec: int) -> bool:
	var t_end := Time.get_ticks_usec() + budget_usec
	while _step < total_steps():
		_render_step(_step)
		_step += 1
		if Time.get_ticks_usec() >= t_end:
			break
	return _step >= total_steps()


## The three finished stems as looping streams (call once step() returns true).
func streams() -> Array[AudioStreamWAV]:
	var out: Array[AudioStreamWAV] = []
	for b in _bytes:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		wav.stereo = false
		wav.data = b
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = b.size() / 2
		out.append(wav)
	_cache = out
	return out


## Synchronous render for tests and tools: stem 0 BASE, 1 COMBAT, 2 FRENZY.
## Cached, so the AudioSys job and later calls share one render.
static func render_loop(stem := 0) -> AudioStreamWAV:
	if _cache.is_empty():
		var job := MusicGen.new()
		while not job.step(1000000):
			pass
		job.streams()
	return _cache[clampi(stem, 0, 2)]


func _render_step(s: int) -> void:
	var phrase: int = SONG[s / STEPS]
	var ps := s % STEPS
	var bar_step := s % 16
	var chord: Array = CHORDS[phrase][ps / 16]
	var root: int = chord[0]
	var third := 4 if chord[1] == 1 else 3
	# --- note events at the step boundary ---
	var bn: int = BASS[phrase][ps]
	if bn != R:
		_bass_f = E2 * pow(2.0, bn / 12.0)
		_bass_amp = 0.12
		_bass_idx = 3.2
	var ln: int = LEAD[phrase][ps]
	if ln == R:
		_lead_goal = 0.0
	elif ln != T:
		_lead_f = E4 * pow(2.0, ln / 12.0)
		_lead_goal = 0.055
		_lead_t = 0.0
	# FRENZY bells: a rising chord arpeggio on every 16th
	var arp_shape := [0, third, 7, 12]
	_arp_f = E5 * pow(2.0, (root + arp_shape[s % 4]) / 12.0)
	_arp_amp = 0.05
	_arp_idx = 2.4
	var pf0 := E3 * pow(2.0, root / 12.0) / RATE
	var pf1 := E3 * pow(2.0, (root + 7) / 12.0) / RATE
	var pf2 := E3 * pow(2.0, (root + third) / 12.0) / RATE
	# drums — the breakdown keeps only its downbeat kick; the build rolls in
	var brk := phrase == PHRASE_BREAK
	if bar_step == 0 or (bar_step == 8 and not brk):
		_trigger_kick(0, 0.26)
	elif bar_step == 10 and not brk and phrase != PHRASE_BUILD:
		_trigger_kick(1, 0.18)       # COMBAT syncopation
	if not brk:
		if bar_step == 4 or bar_step == 12:
			_trigger_snare(1, 0.11)
		elif phrase == PHRASE_BUILD and ps >= 24 and (ps >= 28 or ps % 2 == 0):
			_trigger_snare(1, 0.04 + 0.012 * (ps - 24))   # the roll swells
		elif bar_step == 7 or bar_step == 15:
			_trigger_snare(2, 0.04)  # FRENZY ghost notes
		if bar_step % 4 == 2:
			_trigger_hat(2 if bar_step == 14 else 1, 0.045, 18.0 if bar_step == 14 else 90.0)
		elif bar_step % 2 == 1:
			_trigger_hat(2, 0.022, 110.0)
	# --- samples ---
	var base_i := s * SPS
	var bass_dec := exp(-6.0 / RATE)
	var bass_idx_dec := exp(-30.0 / RATE)
	var arp_dec := exp(-14.0 / RATE)
	var arp_idx_dec := exp(-18.0 / RATE)
	var lead_k := 1.0 - exp(-1.0 / (0.025 * RATE))
	var inv := 1.0 / RATE
	var b0 := _bytes[0]
	var b1 := _bytes[1]
	var b2 := _bytes[2]
	var loop_n := total_steps() * SPS
	for i in SPS:
		var v0 := 0.0
		var v1 := 0.0
		var v2 := 0.0
		# FM slap bass: 1:1 ratio, index snapping shut after the attack
		if _bass_amp > 0.0005:
			_bass_ph += _bass_f * inv
			var bp := TAU * _bass_ph
			v0 += _bass_amp * sin(bp + (0.7 + _bass_idx) * sin(bp))
			_bass_amp *= bass_dec
			_bass_idx *= bass_idx_dec
		# pad: root, fifth and a softer third, fading at the ends of the loop so
		# the wrap never clicks
		var gi := base_i + i
		var pad_env := minf(1.0, minf(gi, loop_n - gi) / 441.0)
		_pad0 += pf0
		_pad1 += pf1
		_pad2 += pf2
		v0 += (sin(TAU * _pad0) + sin(TAU * _pad1) * 0.8 + sin(TAU * _pad2) * 0.5) \
			* 0.022 * pad_env
		# brass lead: swells in, brightens with its level, vibrato after 0.2 s
		_lead_amp += (_lead_goal - _lead_amp) * lead_k
		if _lead_amp > 0.0005:
			_lead_t += inv
			var vib := 1.0 + 0.006 * sin(TAU * 5.5 * _lead_t) * minf(1.0, _lead_t / 0.3)
			_lead_ph += _lead_f * vib * inv
			var lp := TAU * _lead_ph
			v1 += _lead_amp * sin(lp + (0.8 + _lead_amp * 30.0) * sin(lp))
		# FM bells: modulator an octave up, fast index decay
		if _arp_amp > 0.0005:
			_arp_ph += _arp_f * inv
			var ap := TAU * _arp_ph
			v2 += _arp_amp * sin(ap + _arp_idx * sin(2.0 * ap))
			_arp_amp *= arp_dec
			_arp_idx *= arp_idx_dec
		# kit: one noise draw per sample feeds every drum
		var nz := _rng.randf_range(-1.0, 1.0)
		if _kick_t >= 0.0:
			_kick_ph += (45.0 + 115.0 * exp(-_kick_t * 32.0)) * inv
			var kv := _kick_amp * exp(-_kick_t * 13.0) * sin(TAU * _kick_ph) \
				+ nz * _kick_amp * 0.3 * exp(-_kick_t * 280.0)
			if _kick_stem == 0:
				v0 += kv
			else:
				v1 += kv
			_kick_t += inv
			if _kick_t > 0.3:
				_kick_t = -1.0
		if _snare_t >= 0.0:
			var sv := _snare_amp * (nz * exp(-_snare_t * 20.0)
				+ 0.6 * sin(TAU * 185.0 * _snare_t) * exp(-_snare_t * 28.0))
			if _snare_stem == 1:
				v1 += sv
			else:
				v2 += sv
			_snare_t += inv
			if _snare_t > 0.25:
				_snare_t = -1.0
		if _hat_t >= 0.0:
			var hv := (nz - _noise_prev) * _hat_amp * exp(-_hat_t * _hat_decay)
			if _hat_stem == 1:
				v1 += hv
			else:
				v2 += hv
			_hat_t += inv
			if _hat_t > 0.2:
				_hat_t = -1.0
		_noise_prev = nz
		var o := (base_i + i) * 2
		b0.encode_s16(o, int(clampf(v0, -1.0, 1.0) * 32767.0))
		b1.encode_s16(o, int(clampf(v1, -1.0, 1.0) * 32767.0))
		b2.encode_s16(o, int(clampf(v2, -1.0, 1.0) * 32767.0))


func _trigger_kick(stem: int, amp: float) -> void:
	_kick_t = 0.0
	_kick_ph = 0.0
	_kick_amp = amp
	_kick_stem = stem


func _trigger_snare(stem: int, amp: float) -> void:
	_snare_t = 0.0
	_snare_amp = amp
	_snare_stem = stem


func _trigger_hat(stem: int, amp: float, decay: float) -> void:
	_hat_t = 0.0
	_hat_amp = amp
	_hat_decay = decay
	_hat_stem = stem
