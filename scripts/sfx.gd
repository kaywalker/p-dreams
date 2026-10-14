extends Node
## Prozedural erzeugte Soundeffekte und eine kleine Chiptune-Schleife.
## Es werden keine Audiodateien benötigt.

const RATE := 22050

var streams := {}
var music_on := true:
	set(value):
		music_on = value
		if _music:
			_music.volume_db = -9.0 if music_on else -80.0

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	music_on = music_on
	_build_effects()
	WorkerThreadPool.add_task(_build_music_threaded)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# ---------------------------------------------------------------- Erzeugung

static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


## Erzeugt einen Klang; `gen` bekommt (t, phase-Array) und liefert ein Sample.
func _make(dur: float, gen: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var state := [0.0, 0.0, 0.0]
	for i in n:
		out[i] = gen.call(float(i) / RATE, state)
	return _to_wav(out)


func _build_effects() -> void:
	streams["flipper"] = _make(0.08, func(t: float, st: Array) -> float:
		st[0] += TAU * 95.0 / RATE
		return (_noise() * exp(-t * 70.0) * 0.5 + sin(st[0]) * exp(-t * 35.0) * 0.7))

	streams["bumper"] = _make(0.28, func(t: float, st: Array) -> float:
		var f := lerpf(620.0, 180.0, minf(t / 0.2, 1.0))
		st[0] += TAU * f / RATE
		st[1] += TAU * 310.0 / RATE
		var sq := 1.0 if sin(st[1]) > 0.0 else -1.0
		return sin(st[0]) * exp(-t * 12.0) * 0.7 + sq * exp(-t * 35.0) * 0.25)

	streams["sling"] = _make(0.14, func(t: float, st: Array) -> float:
		st[0] += TAU * lerpf(260.0, 160.0, t / 0.14) / RATE
		var sq := 1.0 if sin(st[0]) > 0.0 else -1.0
		return sq * exp(-t * 28.0) * 0.4 + _noise() * exp(-t * 90.0) * 0.4)

	streams["drop"] = _make(0.12, func(t: float, st: Array) -> float:
		st[0] += TAU * 1250.0 / RATE
		st[1] = lerpf(st[1], _noise(), 0.3)
		return st[1] * exp(-t * 45.0) * 0.8 + sin(st[0]) * exp(-t * 60.0) * 0.4)

	streams["lane"] = _make(0.16, func(t: float, st: Array) -> float:
		var f := 1760.0 if t < 0.07 else 2350.0
		st[0] += TAU * f / RATE
		return (1.0 if sin(st[0]) > 0.0 else -1.0) * 0.18 * exp(-t * 10.0))

	streams["ramp"] = _make(0.6, func(t: float, st: Array) -> float:
		st[0] += TAU * lerpf(220.0, 1400.0, t / 0.6) / RATE
		st[1] += TAU * lerpf(225.0, 1420.0, t / 0.6) / RATE
		var env := minf(t * 20.0, 1.0) * (1.0 - t / 0.6)
		return ((1.0 if sin(st[0]) > 0.0 else -1.0) * 0.18 + sin(st[1]) * 0.25) * env)

	streams["saucer"] = _make(0.4, func(t: float, st: Array) -> float:
		st[0] += TAU * lerpf(160.0, 60.0, t / 0.4) / RATE
		return sin(st[0]) * exp(-t * 9.0) * 0.8 + _noise() * exp(-t * 40.0) * 0.3)

	streams["launch"] = _make(0.5, func(t: float, st: Array) -> float:
		st[1] = lerpf(st[1], _noise(), lerpf(0.05, 0.6, t / 0.5))
		return st[1] * (1.0 - t / 0.5) * 0.9)

	streams["drain"] = _make(0.9, func(t: float, st: Array) -> float:
		st[0] += TAU * lerpf(700.0, 70.0, t / 0.9) / RATE
		return (1.0 if sin(st[0]) > 0.0 else -1.0) * 0.22 * (1.0 - t / 0.9))

	streams["spinner"] = _make(0.05, func(t: float, st: Array) -> float:
		st[0] += TAU * 2600.0 / RATE
		return (1.0 if sin(st[0]) > 0.0 else -1.0) * 0.25 * exp(-t * 90.0) + _noise() * exp(-t * 120.0) * 0.3)

	streams["kickback"] = _make(0.35, func(t: float, st: Array) -> float:
		st[0] += TAU * lerpf(90.0, 40.0, t / 0.35) / RATE
		return sin(st[0]) * exp(-t * 8.0) * 0.9 + _noise() * exp(-t * 30.0) * 0.5)

	streams["multiball"] = _make(1.6, func(t: float, st: Array) -> float:
		var f := lerpf(110.0, 880.0, minf(t / 1.2, 1.0))
		st[0] += TAU * f / RATE
		st[1] += TAU * f * 1.5 / RATE
		var env := minf(t * 8.0, 1.0) * (1.0 - t / 1.6)
		var sq := 1.0 if sin(st[0]) > 0.0 else -1.0
		return (sq * 0.18 + sin(st[1]) * 0.2 + _noise() * 0.08) * env)

	streams["jackpot"] = _arpeggio([72, 76, 79, 84, 88, 91, 96], 0.09, 0.3)
	streams["extra"] = _arpeggio([67, 72, 76, 79, 84, 79, 84], 0.08, 0.28)
	streams["start"] = _arpeggio([60, 64, 67, 72], 0.1, 0.25)
	streams["complete"] = _arpeggio([76, 79, 84], 0.07, 0.25)
	streams["over"] = _arpeggio([72, 67, 64, 60, 55, 48], 0.16, 0.25)


func _arpeggio(notes: Array, step: float, vol: float) -> AudioStreamWAV:
	var dur := step * notes.size() + 0.25
	return _make(dur, func(t: float, st: Array) -> float:
		var idx := mini(int(t / step), notes.size() - 1)
		var local := t - idx * step
		st[0] += TAU * _midi(notes[idx]) / RATE
		var duty := 0.5 + 0.5 * sin(t * 9.0) * 0.5
		var x := fmod(st[0] / TAU, 1.0)
		var sq := 1.0 if x < duty else -1.0
		var env := exp(-local * 6.0) if idx < notes.size() - 1 else exp(-local * 4.0)
		return sq * vol * env)


# ---------------------------------------------------------------- Musik

func _build_music_threaded() -> void:
	var bpm := 132.0
	var step := 60.0 / bpm / 4.0
	var chords := [
		[69, 72, 76, 81], [65, 69, 72, 77], [60, 64, 67, 72], [62, 67, 71, 74],
	]
	var bass := [45, 41, 48, 43]
	var arp_order := [0, 1, 2, 3, 2, 1, 0, 2]
	var lead := [
		81, -1, 79, 81, -1, 84, -1, 81, 79, -1, 76, -1, 74, 76, -1, -1,
		77, -1, 76, 77, -1, 81, -1, 77, 76, -1, 72, -1, 69, 72, -1, -1,
		76, -1, 74, 76, -1, 79, -1, 76, 72, -1, 74, -1, 76, 79, -1, -1,
		74, -1, 76, 79, -1, 83, -1, 81, 79, -1, 74, -1, 71, 74, -1, -1,
	]
	var steps_total := 16 * 8
	var n := int(steps_total * step * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ph_b := 0.0
	var ph_a := 0.0
	var ph_l := 0.0
	var ph_k := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := int(t / step)
		var local := t - s * step
		var bar := s / 16
		var chord: Array = chords[(bar / 2) % 4]
		# Bass: Achtel, Grundton / Oktave im Wechsel.
		var bnote: float = bass[(bar / 2) % 4] + (12 if (s / 2) % 2 == 1 else 0)
		ph_b += _midi(bnote) / RATE
		var bx := fmod(ph_b, 1.0)
		var bass_v := (1.0 if bx < 0.5 else -1.0) * 0.16 * exp(-fmod(t, step * 2.0) * 5.0)
		# Arpeggio: Sechzehntel.
		var anote: float = chord[arp_order[s % 8]] + 12
		ph_a += _midi(anote) / RATE
		var ax := fmod(ph_a, 1.0)
		var arp_v := (1.0 if ax < 0.25 else -1.0) * 0.05 * exp(-local * 18.0)
		# Melodie ab Takt 3, nur in der zweiten Hälfte der Schleife voll.
		var lead_v := 0.0
		var lnote: int = lead[s % 64]
		if lnote > 0 and bar >= 2:
			ph_l += _midi(lnote) / RATE
			var lx := fmod(ph_l, 1.0)
			var tri := 4.0 * absf(lx - 0.5) - 1.0
			lead_v = tri * 0.14 * minf(1.0, local * 60.0) * exp(-local * 2.5)
		# Kick auf jeder Viertel, Hi-Hat auf den Offbeats.
		var drum := 0.0
		var beat_local := fmod(t, step * 4.0)
		if beat_local < 0.12:
			ph_k += lerpf(140.0, 45.0, beat_local / 0.12) / RATE
			drum += sin(ph_k * TAU) * 0.35 * (1.0 - beat_local / 0.12)
		if s % 4 == 2 and local < 0.04:
			drum += rng.randf_range(-1.0, 1.0) * 0.07 * (1.0 - local / 0.04)
		out[i] = bass_v + arp_v + lead_v + drum
	var wav := _to_wav(out, true)
	call_deferred("_music_ready", wav)


func _music_ready(wav: AudioStreamWAV) -> void:
	_music.stream = wav
	_music.play()
