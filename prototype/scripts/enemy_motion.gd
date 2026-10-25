extends RefCounted
## Autorskie klipy riga w natywnej AnimationLibrary. Pozycje kończyn są ułamkiem wysokości bioder;
## Enemy3D retargetuje je do anatomii przez IK. Kontakt jest znacznikiem czasu, nie komendą zadania obrażeń.
const PATH := "res://art/enemy3d/motion.tres"
const KIND := {"wolek": "smash", "rzeznik": "cleave", "slepiec": "claw", "stalker": "grab", "mimik": "reveal_grab",
	"podsluchacz": "scream", "kaplan": "ritual", "skoczek": "pounce", "zerca": "snatch", "trzosek": "bite", "cma": "dive"}
const TIMING := {"smash": [0.60, 0.76], "cleave": [0.50, 0.64], "claw": [0.35, 0.46], "grab": [0.40, 0.68],
	"reveal_grab": [0.40, 0.55], "scream": [0.90, 0.60], "ritual": [0.70, 0.82], "pounce": [0.30, 0.38],
	"snatch": [0.40, 0.56], "bite": [0.28, 0.42], "dive": [0.20, 0.40], "charge": [0.70, 0.25], "throw": [0.60, 0.52], "landing": [0.0, 0.24]}
## Klatki: [ułamek zapowiedzi lub odzyskania równowagi, kanały riga]. Ujemny czas = przed kontaktem.
const KEYS := {
	"landing": [[-1.0,{"drop": 0.0,"lean": 0.0,"pitch": 0.0}],[0.25,{"drop": 0.09,"lean": 6.0,"pitch": -7.0}],[0.58,{"drop": 0.03,"lean": 2.0,"pitch": -2.0}]],
	# Ciężkie ciosy mają pracę całego ciała i jawny obrót dłoni. Stopy pozostają
	# podporą; ciężar przesuwa miednica, a odzyskanie równowagi trwa dłużej niż zamach.
	# Wołek (smash): pięści splecione wysoko i za głową — z boku, w kamerze gry, muszą wystawać ponad garb, a nie chować się nad barkami;
	# krótkie zawieszenie w szczycie, potem młot obiema pięściami w grunt przed sobą z wykrokiem przedniej nogi (fR).
	"smash": [[-1.0,{"lean": 1.0,"drop": 0.01,"shift": 0.0,"pelvis_yaw": 0.0,"chest_yaw": 0.0,"wristR": 0.0,"wristL": 0.0,"hR": Vector3(0.33,1.02,1.04),"hL": Vector3(0.30,1.02,-1.04),"fR": Vector3.ZERO}],
		[-0.72,{"lean": -3.0,"drop": 0.09,"shift": -0.04,"hR": Vector3(-0.02,1.55,0.92),"hL": Vector3(0.02,1.52,-0.92),"wristR": -30.0,"wristL": -28.0}],
		[-0.40,{"lean": -14.0,"drop": 0.0,"shift": -0.08,"hR": Vector3(-0.30,2.62,0.42),"hL": Vector3(-0.27,2.58,-0.42),"wristR": -100.0,"wristL": -98.0,"fR": Vector3(0.0,0.10,0.0)}],
		[-0.20,{"lean": -15.0,"drop": 0.0,"shift": -0.08,"hR": Vector3(-0.32,2.66,0.40),"hL": Vector3(-0.29,2.62,-0.40),"wristR": -105.0,"wristL": -102.0,"fR": Vector3(0.06,0.12,0.0)}],
		[-0.08,{"lean": 2.0,"drop": 0.03,"shift": 0.03,"hR": Vector3(0.50,2.15,0.36),"hL": Vector3(0.47,2.12,-0.36),"wristR": -30.0,"wristL": -30.0,"fR": Vector3(0.20,0.05,0.0)}],
		[0.0,{"lean": 26.0,"drop": 0.15,"shift": 0.12,"hR": Vector3(1.08,0.58,0.32),"hL": Vector3(1.05,0.58,-0.32),"wristR": 60.0,"wristL": 58.0,"fR": Vector3(0.24,0.0,0.0)}],
		[0.13,{"lean": 28.0,"drop": 0.18,"shift": 0.12,"hR": Vector3(1.02,0.48,0.34),"hL": Vector3(0.99,0.48,-0.34),"wristR": 55.0,"wristL": 52.0,"fR": Vector3(0.24,0.0,0.0)}],
		[0.48,{"lean": 14.0,"drop": 0.08,"shift": 0.05,"hR": Vector3(0.62,0.90,0.85),"hL": Vector3(0.58,0.90,-0.85),"wristR": 20.0,"wristL": 18.0,"fR": Vector3(0.12,0.0,0.0)}],
		[0.84,{"lean": 3.0,"drop": 0.02,"shift": 0.005,"hR": Vector3(0.35,1.02,1.04),"hL": Vector3(0.32,1.02,-1.04),"wristR": 2.0,"wristL": 2.0,"fR": Vector3(0.02,0.0,0.0)}]],
	"cleave": [[-1.0,{"lean": 2.0,"drop": 0.01,"shift": 0.0,"sway": 0.0,"pelvis_yaw": 0.0,"chest_yaw": 0.0,"wristR": 0.0,"wristL": 0.0,"hR": Vector3(0.09,0.88,0.72),"hL": Vector3(0.16,0.89,-0.72)}],
		[-0.68,{"lean": -3.0,"drop": 0.04,"shift": -0.04,"sway": 0.015,"pelvis_yaw": -5.0,"chest_yaw": -12.0,"hR": Vector3(-0.10,1.48,0.79),"hL": Vector3(0.22,1.10,-0.71),"wristR": -65.0,"wristL": 8.0}],
		[-0.25,{"lean": -6.0,"drop": 0.01,"shift": -0.035,"pelvis_yaw": -7.0,"chest_yaw": -18.0,"hR": Vector3(0.15,2.30,0.47),"hL": Vector3(0.32,1.20,-0.68),"wristR": -155.0,"wristL": 12.0}],
		[-0.10,{"lean": 5.0,"shift": 0.03,"pelvis_yaw": 3.0,"chest_yaw": 1.0,"hR": Vector3(0.58,1.95,0.44),"hL": Vector3(0.27,1.13,-0.73),"wristR": -25.0}],
		[0.0,{"lean": 17.0,"drop": 0.065,"shift": 0.09,"sway": -0.015,"pelvis_yaw": 7.0,"chest_yaw": 12.0,"hR": Vector3(1.15,1.18,0.44),"hL": Vector3(0.16,1.05,-0.76),"wristR": 72.0,"wristL": -8.0}],
		[0.14,{"lean": 22.0,"drop": 0.085,"shift": 0.10,"pelvis_yaw": 8.0,"chest_yaw": 15.0,"hR": Vector3(0.90,0.84,0.49),"hL": Vector3(0.12,0.97,-0.76),"wristR": 28.0}],
		[0.48,{"lean": 12.0,"drop": 0.045,"shift": 0.04,"pelvis_yaw": 4.0,"chest_yaw": 6.0,"hR": Vector3(0.35,0.88,0.67),"hL": Vector3(0.15,0.90,-0.72),"wristR": 8.0,"wristL": 0.0}],
		[0.84,{"lean": 3.0,"drop": 0.015,"shift": 0.004,"sway": 0.0,"pelvis_yaw": 0.0,"chest_yaw": 0.0,"hR": Vector3(0.11,0.88,0.72),"hL": Vector3(0.16,0.89,-0.72),"wristR": 1.0}]],
	"claw": [[-1.0,{"lean": 4.0,"hR": Vector3(0.08,0.85,0.44),"hL": Vector3(0.22,0.85,-0.44)}],
		[-0.40,{"lean": 1.0,"drop": 0.03,"hR": Vector3(-0.20,1.48,0.62),"hL": Vector3(0.38,1.15,-0.38)}],
		[0.0,{"lean": 15.0,"drop": 0.08,"hR": Vector3(0.88,1.22,0.18),"hL": Vector3(0.56,1.08,-0.34),"fR": Vector3(0.15,0,0),"fL": Vector3(-0.10,0,0)}],
		[0.18,{"lean": 19.0,"hR": Vector3(0.70,1.10,-0.04)}], [0.70,{"lean": 7.0,"drop": 0.03,"hR": Vector3(0.25,0.96,0.34)}]],
	"grab": [[-1.0,{"lean": 4.0,"drop": 0.02,"hR": Vector3(0.12,0.82,0.38),"hL": Vector3(0.12,0.82,-0.38)}],
		[-0.45,{"lean": 2.0,"hR": Vector3(0.58,1.35,0.38),"hL": Vector3(0.58,1.35,-0.38)}],
		[0.0,{"lean": 12.0,"drop": 0.08,"hR": Vector3(1.02,1.28,0.20),"hL": Vector3(1.02,1.28,-0.20),"fR": Vector3(0.18,0,0),"fL": Vector3(-0.10,0,0)}],
		[0.22,{"lean": 10.0,"hR": Vector3(0.88,1.24,0.13),"hL": Vector3(0.88,1.24,-0.13)}],
		[0.67,{"lean": 5.0,"drop": 0.03,"hR": Vector3(0.38,1.02,0.32),"hL": Vector3(0.38,1.02,-0.32)}]],
	"reveal_grab": [[-1.0,{"lean": 0.0,"drop": 0.0,"hR": Vector3(0.05,0.75,0.35),"hL": Vector3(0.05,0.75,-0.35)}],
		[-0.50,{"lean": -5.0,"head": 1.3,"hR": Vector3(0.22,1.32,0.42),"hL": Vector3(0.22,1.32,-0.42)}],
		[0.0,{"lean": 14.0,"drop": 0.06,"hR": Vector3(0.95,1.18,0.18),"hL": Vector3(0.95,1.18,-0.18)}],
		[0.20,{"hR": Vector3(0.80,1.12,0.10),"hL": Vector3(0.80,1.12,-0.10)}]],
	"scream": [[-1.0,{"lean": 3.0,"hR": Vector3(0.05,0.70,0.35),"hL": Vector3(0.05,0.70,-0.35)}],
		[-0.55,{"lean": -5.0,"hR": Vector3(0.26,1.38,0.31),"hL": Vector3(0.26,1.38,-0.31)}],
		[-0.15,{"lean": -12.0,"hR": Vector3(0.15,1.56,0.24),"hL": Vector3(0.15,1.56,-0.24)}],
		[0.0,{"lean": -18.0,"hR": Vector3(0.35,1.50,0.52),"hL": Vector3(0.35,1.50,-0.52),"head": 1.1}],
		[0.20,{"lean": -14.0,"hR": Vector3(0.30,1.42,0.46),"hL": Vector3(0.30,1.42,-0.46)}]],
	"ritual": [[-1.0,{"lean": 1.0,"hR": Vector3(0.05,0.76,0.35),"hL": Vector3(0.05,0.76,-0.35)}],
		[-0.55,{"lean": -3.0,"hR": Vector3(0.14,1.72,0.30),"hL": Vector3(0.14,1.72,-0.30)}],
		[-0.18,{"lean": -7.0,"hR": Vector3(0.18,1.84,0.25),"hL": Vector3(0.18,1.84,-0.25)}],
		[0.0,{"lean": -12.0,"hR": Vector3(0.62,1.46,0.60),"hL": Vector3(0.62,1.46,-0.60)}],
		[0.30,{"lean": -6.0,"hR": Vector3(0.46,1.35,0.50),"hL": Vector3(0.46,1.35,-0.50)}]],
	"pounce": [[-1.0,{"lean": 0.0,"shift": 0.0,"lift": 0.0,"arm": 0.0,"leg": 0.0}],[-0.35,{"lean": -12.0,"shift": -0.10,"arm": 24.0,"leg": 20.0}],
		[0.0,{"lean": 16.0,"shift": 0.14,"arm": -46.0,"leg": -20.0}], [0.20,{"lean": 19.0,"arm": -34.0,"leg": -12.0}], [0.65,{"lean": 4.0,"shift": 0.04,"arm": -6.0,"leg": 5.0}]],
	"snatch": [[-1.0,{"lean": 0.0,"shift": 0.0,"lift": 0.0,"arm": 0.0,"leg": 0.0}],[-0.45,{"lean": -8.0,"shift": -0.06,"arm": 16.0}],
		[0.0,{"lean": 12.0,"shift": 0.11,"arm": -35.0,"leg": -10.0}], [0.22,{"lean": 8.0,"arm": -24.0}], [0.70,{"lean": 3.0,"shift": 0.02,"arm": -5.0,"leg": 0.0}]],
	"bite": [[-1.0,{"pitch": 0.0,"arch": 0.0,"shift": 0.0}],[-0.45,{"pitch": 12.0,"arch": 6.0,"shift": -0.05}],
		[0.0,{"pitch": -15.0,"arch": -8.0,"shift": 0.16}], [0.15,{"pitch": -18.0,"arch": -10.0,"shift": 0.12}], [0.65,{"pitch": -3.0,"arch": -2.0,"shift": 0.03}]],
	"dive": [[-1.0,{"roll": 0.0,"shift": 0.0,"lift": 0.0,"wing": 30.0}],[-0.40,{"roll": 10.0,"shift": -0.04,"lift": 0.08,"wing": 58.0}],
		[0.0,{"roll": -32.0,"shift": 0.22,"lift": -0.14,"wing": 18.0}], [0.20,{"roll": -25.0,"shift": 0.18,"lift": -0.10,"wing": -16.0}]],
	"charge": [[-1.0,{"lean": 5.0,"drop": 0.02,"hR": Vector3(0.1,0.75,0.44),"hL": Vector3(0.1,0.75,-0.44)}],
		[-0.45,{"lean": 17.0,"drop": 0.09,"hR": Vector3(-0.08,0.85,0.44),"hL": Vector3(-0.08,0.85,-0.44)}],
		[0.0,{"lean": 27.0,"drop": 0.10,"hR": Vector3(-0.25,0.85,0.44),"hL": Vector3(-0.25,0.85,-0.44)}]],
	"throw": [[-1.0,{"lean": 0.0,"hR": Vector3(0.12,0.78,0.40),"hL": Vector3(0.12,0.78,-0.40)}],
		[-0.50,{"lean": -9.0,"hR": Vector3(-0.22,1.64,0.30),"hL": Vector3(-0.22,1.64,-0.30)}],
		[0.0,{"lean": 15.0,"hR": Vector3(0.95,1.48,0.23),"hL": Vector3(0.95,1.48,-0.23)}], [0.25,{"lean": 18.0,"hR": Vector3(0.70,1.18,0.28),"hL": Vector3(0.70,1.18,-0.28)}]]}
static var _library: AnimationLibrary

static func action(kind: String) -> String:
	return String(KIND.get(kind, ""))

static func library() -> AnimationLibrary:
	if _library == null and ResourceLoader.exists(PATH): _library = load(PATH)
	return _library

static func contact(name: String) -> float:
	return float(TIMING[name][0]) if TIMING.has(name) else 0.0

static func recovery(name: String) -> float:
	return float(TIMING[name][1]) if TIMING.has(name) else 0.42

static func sample(name: String, time: float) -> Dictionary:
	var lib := library()
	if lib == null or not lib.has_animation(name): return {}
	var clip := lib.get_animation(name)
	var out := {}
	for track in clip.get_track_count():
		out[String(clip.track_get_path(track).get_concatenated_subnames())] = clip.value_track_interpolate(track, clampf(time, 0.0, clip.length))
	return out

## Generator tworzy zasób, runtime go tylko wczytuje. Końcowa klatka wraca do pierwszej pozy.
static func build() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for name in KEYS:
		var clip := Animation.new()
		clip.length = contact(name) + recovery(name)
		clip.set_meta("contact", contact(name))
		clip.set_meta("recovery", recovery(name))
		var tracks := {}
		var first: Dictionary = KEYS[name][0][1]
		for entry in KEYS[name]:
			for channel in entry[1]:
				if not tracks.has(channel):
					var track := clip.add_track(Animation.TYPE_VALUE)
					clip.track_set_path(track, NodePath(":" + channel))
					clip.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
					tracks[channel] = track
		for channel in tracks:
			var initial = first.get(channel, Vector3.ZERO if channel in ["hR","hL","fR","fL"] else 0.0)
			clip.track_insert_key(tracks[channel], 0.0, initial)
			for entry in KEYS[name]:
				if entry[1].has(channel):
					var t: float = contact(name) * (1.0 + float(entry[0])) if float(entry[0]) < 0.0 else contact(name) + recovery(name) * float(entry[0])
					clip.track_insert_key(tracks[channel], t, entry[1][channel])
			clip.track_insert_key(tracks[channel], clip.length, initial)
			if name in ["smash", "cleave"]: _bounded_track(clip, tracks[channel])
		lib.add_animation(name, clip)
	return lib

## Monotoniczny Hermite, wypieczony w 120 Hz. Swobodny spline kubiczny
## przestrzeliwał cele IK i kąty nadgarstka przy nierównych odstępach klatek.
static func _slope(times: Array[float], values: Array[float], index: int) -> float:
	if index == 0 or index == times.size() - 1: return 0.0
	var before := times[index] - times[index - 1]
	var after := times[index + 1] - times[index]
	var a := (values[index] - values[index - 1]) / before
	var b := (values[index + 1] - values[index]) / after
	if a * b <= 0.0: return 0.0
	var w1 := 2.0 * after + before
	var w2 := after + 2.0 * before
	return (w1 + w2) / (w1 / a + w2 / b)

static func _hermite(times: Array[float], values: Array[float], time: float) -> float:
	var i := 0
	while i < times.size() - 2 and time > times[i + 1]: i += 1
	var duration := times[i + 1] - times[i]
	var u := clampf((time - times[i]) / duration, 0.0, 1.0)
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * values[i] + (u3 - 2.0 * u2 + u) * duration * _slope(times, values, i) + (-2.0 * u3 + 3.0 * u2) * values[i + 1] + (u3 - u2) * duration * _slope(times, values, i + 1)

static func _bounded_track(clip: Animation, track: int) -> void:
	var times: Array[float] = []
	var components: Array = [[], [], []]
	var vector := clip.track_get_key_value(track, 0) is Vector3
	for key in clip.track_get_key_count(track):
		times.append(clip.track_get_key_time(track, key))
		var value = clip.track_get_key_value(track, key)
		for axis in (3 if vector else 1): components[axis].append(float(value[axis]) if vector else float(value))
	var samples: Array[float] = times.duplicate()
	for frame in ceili(clip.length * 120.0): samples.append(minf(frame / 120.0, clip.length))
	samples.sort()
	for key in range(clip.track_get_key_count(track) - 1, -1, -1): clip.track_remove_key(track, key)
	clip.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for time in samples:
		var value := Vector3.ZERO
		for axis in (3 if vector else 1):
			var values: Array[float] = []
			values.assign(components[axis])
			value[axis] = _hermite(times, values, time)
		clip.track_insert_key(track, time, value if vector else value.x)
