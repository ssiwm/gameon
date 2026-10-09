extends Node
## AudioDirector — autoload `Audio`. Jedyne miejsce w projekcie, które wie
## o plikach WAV; reszta kodu woła tylko Audio.play(...) / Audio.play_at(...).
##
## Wersja 2 (overhaul „AAA"). Co robi ten skrypt, a czego nie robi sam bus layout:
##
##   1. PROPAGACJA PRZEZ ŚCIANY (GDD §13). Trzy promienie źródło→słuchawka (środkowy
##      + dwa boczne): ile jest zasłoniętych, taki próg okluzji (0 = czysto, 1 = lekko,
##      2 = mocno, 3 = całkiem za ścianą) i taki bus z filtrem dolnoprzepustowym
##      (OccLight/OccHeavy/OccBlocked). Boczne promienie dają „dyfrakcję": źródło
##      za rogiem brzmi inaczej niż źródło za grubą ścianą. Pętle pozycyjne (szept
##      stalkera) są przeliczane co 0,2 s z histerezą, żeby próg nie migotał.
##
##   2. POGŁOS ŚRODOWISKOWY. Wachlarz promieni wokół słuchawki mierzy „zamknięcie"
##      (ile promieni uderza w ścianę) i średnią odległość; z tego rośnie wet/room_size
##      efektu Reverb na szynie SFX. Te same próbki brzmią inaczej w lesie i w korytarzu —
##      dlatego assety mają tylko krótki ogon źródła (bake), a halę dokłada silnik.
##
##   3. MUZYKA STEMOWA. Cztery stemy grają CAŁY CZAS w idealnej synchronizacji
##      (start pod AudioServer.lock()), a Uwaga steruje tylko ich głośnością:
##      wejście stemu jest kwantyzowane do beatu (nie „w pół taktu"), wyjście
##      opóźnione (hold), żeby muzyka nie milkła w sekundę po walce. Zmiany głośności
##      idą liniowo w amplitudzie (nie w dB), więc crossfade jest równomierny.
##
##   4. MIKS DYNAMICZNY. Sidechain muzyki/ambientu pod SFX robi bus layout (kompresory),
##      a tu: ducking na stingery, „ogłuszenie" (LP na Music/Ambience/SFX + szum w uszach)
##      po wybuchu obok i po trafieniu, serce sterowane Uwagą.
##
##   5. ZARZĄDZANIE GŁOSAMI. Priorytety, limity równoczesnych instancji i minimalny
##      odstęp na rodzinę dźwięków, kradzież najniższego priorytetu, brak powtórzeń
##      tego samego wariantu z rzędu, drobny jitter głośności.
##
##   6. EMITERY AMBIENTU. Losowe zdarzenia wokół gracza (podmuch, skrzypienie, odległy
##      huk, odległy zew) — gęstsze przy wysokiej Uwadze — żeby świat „żył".
##
## Napisy dla niesłyszących: sygnał `caption` (manifest: CAPTIONS).

signal caption(text: String, pos: Vector2, priority: int)

const Surfaces := preload("res://scripts/surfaces.gd")
const Weather := preload("res://scripts/weather.gd")
const Manifest := preload("res://scripts/audio_manifest.gd")

const BUS_MUSIC := "Music"
const BUS_AMB := "Ambience"
const BUS_PLAYER := "Player"
const BUS_WEAPONS := "Weapons"
const BUS_WORLD := "World"
const BUS_STALKER := "Stalker"
const BUS_UI := "UI"
const BUS_SFX := "SFX"
const BUS_OCC_LIGHT := "OccLight"
const BUS_OCC_HEAVY := "OccHeavy"
const BUS_OCC_BLOCKED := "OccBlocked"
## Zgodność wsteczna: dawny pojedynczy bus okluzji.
const BUS_OCCLUDED := BUS_OCC_HEAVY
const OCC_BUSES := [BUS_OCC_LIGHT, BUS_OCC_HEAVY, BUS_OCC_BLOCKED]

## Warstwa kolizji ścian (World w main.tscn ustawia collision_layer = 1).
const OCCLUSION_MASK := 1
## Siatka kwantowania pozycji w cache'u przeszkód (jeden raz na klatkę na komórkę).
const OCCL_CELL := 24.0
## Rozstaw bocznych promieni okluzji (px) — „szerokość" ściany, którą dźwięk omija.
const OCCL_FLANK := 18.0

const ONESHOT_POOL := 32
const POSITIONAL_POOL := 28
const MAX_DISTANCE := 1600.0

# Serce: próg, od którego bije szybciej (GDD: Uwaga napędza strach).
const HEART_FAST_AT := 0.45
const HEART_SLOW_KEY := "heart_slow_loop"
const HEART_FAST_KEY := "heart_fast_loop"

## Rodzina dźwięku -> [priorytet 0-100, max równoczesnych, min odstęp ms]. Dopasowanie
## po NAJDŁUŻSZYM prefiksie; wszystko inne dostaje DEFAULT_VOICE.
const VOICE := {
	"stalker_shriek": [100, 2, 0], "player_down": [95, 1, 0], "explosion": [92, 3, 0],
	"sting": [90, 2, 0], "stalker_growl": [85, 2, 700], "revive": [80, 1, 0],
	"player_hurt": [80, 2, 120], "stalker_step": [70, 3, 140], "spread12_shot": [75, 4, 0],
	"p64_shot": [65, 5, 0], "m83_shot": [60, 8, 0], "ui_": [55, 3, 0], "warn_pulse": [55, 1, 300],
	"oc_load": [55, 1, 0], "radio_beep": [50, 2, 0], "impact_flesh": [45, 5, 30],
	"land_hard": [40, 2, 100], "dry_fire": [40, 1, 90], "effort": [38, 1, 200],
	"impact_hard": [35, 6, 25], "step_": [30, 6, 0], "ricochet": [30, 3, 60],
	"whizz": [25, 3, 70], "amb_": [20, 3, 0], "foley_gear": [10, 2, 120], "shell_": [8, 4, 60],
}
const DEFAULT_VOICE := [40, 6, 0]

## Emitery ambientu: [baza, liczba wariantów, odległość min, odległość max, głośność dB,
## waga, minimalna Uwaga, tylko gdy Stalker śpi]
const EMITTERS := [
	["amb_gust", 3, 200.0, 520.0, -4.0, 3.0, 0.0, false],
	["amb_creak", 3, 260.0, 680.0, -3.0, 2.0, 0.0, false],
	["amb_thud", 2, 650.0, 1050.0, 2.0, 1.2, 0.0, false],
	["amb_far_cry", 2, 900.0, 1400.0, 4.0, 0.9, 25.0, true],
]

var _cache: Dictionary = {}          # String -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _pos_pool: Array[AudioStreamPlayer2D] = []
var _loops: Dictionary = {}          # String -> AudioStreamPlayer
var _pos_loops: Dictionary = {}      # String -> AudioStreamPlayer2D
var _reported: Dictionary = {}       # klucze zgłoszone jako brakujące (raz)
var _voice_cache: Dictionary = {}    # klucz -> [prio, max, gap]
var _last_ms: Dictionary = {}        # rodzina -> czas ostatniego startu (ms)
var _last_variant: Dictionary = {}   # baza -> ostatnio wylosowany wariant
var _last_caption: Dictionary = {}   # tekst -> czas (ms)
var _listener: AudioListener2D
var _listener_pos := Vector2.ZERO
var _occl: Dictionary = {}           # Vector2i -> int (próg okluzji)
var _heart_key := ""
var _enabled := true
var _clock := 0.0

# --- muzyka
var _music: Array[AudioStreamPlayer] = []
var _stem_gain: Array[float] = []     # amplituda liniowa 0..1
var _stem_target: Array[float] = []
var _stem_enter_at: Array[float] = []  # od kiedy (zegar) stem może zacząć wchodzić
var _music_layer := -1
var _music_started := false
var _drop_to := -1
var _drop_at := -1.0
var _duck_db := 0.0
var _duck_hold := 0.0

# --- miks / środowisko
var _deaf := 0.0
var _deaf_hold := 0.0
var _rev_fx: AudioEffectReverb
var _lp_fx: Array[AudioEffectLowPassFilter] = []
var _rev_timer := 0.0
var _rev_wet := 0.08
var _rev_room := 0.45
var _rev_damp := 0.6
var _rev_wet_t := 0.08
var _rev_room_t := 0.45
var _rev_damp_t := 0.6
var _loop_occl_timer := 0.0
var _emit_t := 8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100

	_listener = AudioListener2D.new()
	_listener.name = "AudioListener2D"
	add_child(_listener)

	for _i in ONESHOT_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_PLAYER
		add_child(p)
		_pool.append(p)

	for _i in POSITIONAL_POOL:
		var q := AudioStreamPlayer2D.new()
		q.max_distance = MAX_DISTANCE
		q.attenuation = 1.1
		add_child(q)
		_pos_pool.append(q)

	for i in Manifest.MUSIC_STEMS.size():
		var m := AudioStreamPlayer.new()
		m.bus = BUS_MUSIC
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
		_stem_gain.append(0.0)
		_stem_target.append(0.0)
		_stem_enter_at.append(0.0)

	_bind_effects()
	_verify_manifest()


func _exit_tree() -> void:
	_shutdown()


## Publiczne wyłączenie dźwięku — np. powrót do lobby albo restart sesji.
func shutdown() -> void:
	_shutdown()


## Zamykanie audio: stop + zwolnienie referencji do strumieni, potem free()
## (nie queue_free() — kolejka nie zdąża się przetworzyć przy wyjściu).
## Zweryfikowane eksperymentem: nie eliminuje ostrzeżenia „leaked instances" w headless
## (referencje do zapętlonych AudioStreamWAV trzyma wątek audio Godota) — kosmetyka.
func _shutdown() -> void:
	for key in _loops.keys():
		var p: AudioStreamPlayer = _loops[key]
		_loops.erase(key)
		if is_instance_valid(p):
			p.stop()
			p.stream = null
			p.free()
	for key in _pos_loops.keys():
		var q = _pos_loops[key]          # bez typu: węzeł mógł zostać zwolniony razem ze źródłem
		_pos_loops.erase(key)
		if is_instance_valid(q):
			q.stop()
			q.stream = null
			q.free()
	for n in _pool:
		n.stop()
		n.stream = null
	for n in _pos_pool:
		n.stop()
		n.stream = null
	for n in _music:
		n.stop()
		n.stream = null
	_heart_key = ""
	_music_layer = -1
	_music_started = false
	_cache.clear()
	_reported.clear()
	_occl.clear()


# ---------------------------------------------------------------- strumienie

## Leniwie ładuje WAV i cache'uje. Pętle dostają tu loop_mode, bo plik .wav
## sam o sobie nie wie, że ma się zapętlić — bake zapisuje flagę do manifestu,
## a nie do pliku audio.
func stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	if not Manifest.PATHS.has(key):
		_report_missing(key, "brak wpisu w PATHS")
		return null
	var res: Resource = load(Manifest.PATHS[key])
	var s := res as AudioStream
	if s == null:
		_report_missing(key, "nie załadował się jako AudioStream")
		return null
	if Manifest.LOOPS.has(key) and s is AudioStreamWAV:
		_enable_loop(s)
	_cache[key] = s
	return s


func _enable_loop(s: AudioStreamWAV) -> void:
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	var bytes_per_frame := (2 if s.stereo else 1) * 2
	s.loop_end = s.data.size() / maxi(1, bytes_per_frame)


func _report_missing(key: String, why: String) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	push_warning("[AUDIO] brak '%s' (%s) — pomijam" % [key, why])


## Liczba istniejących wariantów rodziny „m83_shot_1..N" (0 gdy brak), do `count`.
func variant(base: String, count: int) -> int:
	var found := -1
	for i in count:
		if Manifest.PATHS.has("%s_%d" % [base, i + 1]):
			found = i
	return found


## Losuje wariant NIE powtarzając poprzedniego z rzędu (przy ciągłym ogniu ta sama
## próbka dwa razy pod rząd to słyszalny „efekt karabinu maszynowego").
func pick(base: String, count: int) -> String:
	var n := variant(base, count) + 1
	if n <= 1:
		return "%s_1" % base
	var idx := randi_range(0, n - 1)
	var last: int = _last_variant.get(base, -1)
	if idx == last:
		idx = (idx + randi_range(1, n - 1)) % n
	_last_variant[base] = idx
	return "%s_%d" % [base, idx + 1]


## Sprawdza, że każdy wpis manifestu ma plik. Wypisuje braki raz, przy starcie —
## po to, żeby brakujący asset był widoczny w logu, a nie objawiał się ciszą.
func _verify_manifest() -> void:
	var missing: Array[String] = []
	for key in Manifest.PATHS:
		if not ResourceLoader.exists(Manifest.PATHS[key]):
			missing.append(key)
	if missing.is_empty():
		print("[AUDIO] manifest OK: %d ścieżek" % Manifest.PATHS.size())
		return
	missing.sort()
	push_warning("[AUDIO] BRAK %d plików z manifestu: %s" % [
		missing.size(), ", ".join(missing.slice(0, 12))])


# ---------------------------------------------------------------- zarządzanie głosami

func _family(key: String) -> String:
	return key.rstrip("0123456789").rstrip("_")


## [priorytet, max równoczesnych, min odstęp ms] — najdłuższy pasujący prefiks, z cache'em.
func _voice(key: String) -> Array:
	if _voice_cache.has(key):
		return _voice_cache[key]
	var best := ""
	for k in VOICE:
		if key.begins_with(k) and k.length() > best.length():
			best = k
	var v: Array = VOICE[best] if best != "" else DEFAULT_VOICE
	_voice_cache[key] = v
	return v


## Zwraca gracza z puli albo null (gdy nowy dźwięk jest ważniejszy od niczego, ale
## wszystkie głosy są ważniejsze od niego — wtedy NOWY jest porzucany, nie stary).
## Najpierw rodzina: przy przekroczeniu limitu kradniemy najstarszy głos TEJ rodziny
## (podobne widmo = kradzież najmniej słyszalna).
func _acquire(pool: Array, key: String) -> Node:
	var v := _voice(key)
	var prio: int = v[0]
	var fam := _family(key)
	var now := Time.get_ticks_msec()
	var min_gap: int = v[2]
	if min_gap > 0 and prio < 90 and now - int(_last_ms.get(fam, -100000)) < min_gap:
		return null
	var max_n: int = v[1]
	var same := 0
	var oldest_same: Node = null
	var oldest_same_t := INF
	var free_one: Node = null
	var weakest: Node = null
	var weakest_score := INF
	for n in pool:
		if not n.playing:
			if free_one == null:
				free_one = n
			continue
		var t0: int = n.get_meta("t0", 0)
		if n.get_meta("fam", "") == fam:
			same += 1
			if float(t0) < oldest_same_t:
				oldest_same_t = float(t0)
				oldest_same = n
		# wynik kradzieży: niski priorytet i stary głos = pierwszy do wyrzucenia
		var score := float(n.get_meta("prio", 40)) * 100000.0 + float(t0)
		if score < weakest_score:
			weakest_score = score
			weakest = n
	var chosen: Node = null
	if same >= max_n and oldest_same != null:
		chosen = oldest_same
	elif free_one != null:
		chosen = free_one
	elif weakest != null and int(weakest.get_meta("prio", 40)) <= prio:
		chosen = weakest
	if chosen == null:
		return null
	if chosen.playing:
		chosen.stop()
	chosen.set_meta("prio", prio)
	chosen.set_meta("fam", fam)
	chosen.set_meta("t0", now)
	_last_ms[fam] = now
	return chosen


# ---------------------------------------------------------------- one-shoty

func play(key: String, bus: String = BUS_PLAYER, vol_db := 0.0, pitch := 1.0) -> void:
	if not _enabled:
		return
	var s := stream(key)
	if s == null:
		return
	var p := _acquire(_pool, key) as AudioStreamPlayer
	if p == null:
		return
	p.stream = s
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()
	_caption(key, _listener_pos)


## Wariant losowy w jednym wywołaniu: Audio.play_variant("m83_shot", 6, ...)
func play_variant(base: String, count: int, bus: String = BUS_WEAPONS,
		vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if variant(base, count) < 0:
		return
	play(pick(base, count), bus, vol_db + randf_range(-1.0, 1.0),
		pitch + randf_range(-pitch_jitter, pitch_jitter))


## Gra dźwięku w świecie: pozycyjny, z attenuation i z propagacją przez ściany.
func play_at(key: String, pos: Vector2, bus: String = BUS_WORLD,
		vol_db := 0.0, pitch := 1.0) -> void:
	if not _enabled:
		return
	# poza zasięgiem słyszalności nie zajmujemy głosu
	if pos.distance_to(_listener_pos) > MAX_DISTANCE * 0.98:
		return
	var s := stream(key)
	if s == null:
		return
	var p := _acquire(_pos_pool, key) as AudioStreamPlayer2D
	if p == null:
		return
	p.stream = s
	p.position = pos
	p.max_distance = MAX_DISTANCE
	p.attenuation = 1.1
	p.panning_strength = 0.0 if Settings.mono_audio else 1.0       # ustawienie „Mono audio": dźwięk pozycyjny bez panoramy
	p.bus = _tier_bus(bus, occlusion_tier(pos))
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()
	_caption(key, pos)
	if key.begins_with("explosion"):
		_on_explosion(pos)


func play_variant_at(base: String, count: int, pos: Vector2, bus: String = BUS_WORLD,
		vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if variant(base, count) < 0:
		return
	play_at(pick(base, count), pos, bus, vol_db + randf_range(-1.0, 1.0),
		pitch + randf_range(-pitch_jitter, pitch_jitter))


## --- powierzchnie pod stopami -------------------------------------------
## Poziom na tilemapie zna powierzchnię kafla pod stopami (level.surface_at).
## Bez poziomu (scena testowa) zostaje wyliczenie z geometrii main.tscn.
func surface_at(pos: Vector2) -> String:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		return lvl.surface_at(pos)
	if pos.y < 190.0:
		return "metal"
	if pos.x < 500.0:
		return "dirt"
	if pos.x < 1000.0:
		return "concrete"
	return "water"


## Krok na danej powierzchni (5 wariantów na powierzchnię). Przy biegu co jakiś
## czas dochodzi szelest ekwipunku — drobiazg, który odróżnia „postać" od „źródła kroków".
func play_footstep(pos: Vector2, crouching: bool, vol_db := -8.0) -> void:
	var surf := surface_at(pos)
	var prof: Dictionary = Surfaces.of(surf)
	var base: String = prof["step"]
	if variant(base, 5) < 0:
		return
	# Kucanie musi być ROZPOZNAWALNE jako cisza (GDD §8.1) — stąd cicho.
	var v := vol_db + float(prof["db"]) - (7.0 if crouching else 0.0)
	var pitch := float(prof["pitch"]) * (0.96 if crouching else 1.0)
	play_variant_at(base, 5, pos, BUS_PLAYER, v, pitch, 0.07)
	# warstwa charakterystyczna dla powierzchni (słychać, po czym idziesz)
	var layer: String = prof["layer"]
	if layer == "water":
		play_variant_at("step_water", 5, pos, BUS_PLAYER, v - 4.0, pitch * 1.5, 0.1)
	elif layer == "squelch":
		play_variant_at("impact_flesh", 3, pos, BUS_PLAYER, v - 7.0, 0.55, 0.1)
	elif layer == "ring" and not crouching:
		play_variant_at("ricochet", 2, pos, BUS_PLAYER, v - 13.0, 0.5, 0.08)
	# deszcz (RAIN / STORM) pod otwartym niebem: mokre kroki — plusk w kałużach pod stopą (powierzchnia z własnym „water" ma go już)
	if layer != "water" and Weather.active_id() in ["rain", "storm"] and lvl_sky_open(pos):
		play_variant_at("step_water", 5, pos, BUS_PLAYER, v - 7.0, pitch * 1.25, 0.1)
	if not crouching and randf() < 0.3:
		play_variant_at("foley_gear", 3, pos, BUS_PLAYER, v + 4.0, 1.0, 0.1)

func lvl_sky_open(pos: Vector2) -> bool:
	var lvl := get_tree().get_first_node_in_group("level")
	return lvl != null and lvl.sky_open_at(pos)


# ---------------------------------------------------------------- pętle

func start_loop(key: String, bus: String = BUS_PLAYER, vol_db := -6.0, pitch := 1.0) -> void:
	if _loops.has(key):
		set_loop_volume(key, vol_db)
		return
	var s := stream(key)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	p.stream = s
	p.play()
	_loops[key] = p


## Pętla POZYCYJNA przypięta do węzła (np. szept stalkera). Głośność zostaje
## sterowana skryptem źródła (spatial=false wyłącza tłumienie dystansem, żeby nie
## liczyć go dwa razy), ale dochodzą panorama stereo i okluzja przez ściany.
## `id` pozwala mieć kilka pętli z tej samej próbki naraz (np. promień LR-7 u dwóch
## graczy); stop_loop / set_loop_volume / loop_playing przyjmują wtedy to `id`.
func start_loop_at(key: String, node: Node2D, bus: String = BUS_WORLD, vol_db := -6.0,
		spatial := false, id := "") -> void:
	var reg := id if id != "" else key
	if _pos_loops.has(reg):
		set_loop_volume(reg, vol_db)
		return
	var s := stream(key)
	if s == null or node == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.panning_strength = 0.0 if Settings.mono_audio else 1.0
	p.max_distance = 4000.0 if not spatial else MAX_DISTANCE
	p.attenuation = 0.0 if not spatial else 1.1
	p.volume_db = vol_db
	p.set_meta("base_bus", bus)
	p.set_meta("tier", 0)
	p.set_meta("tier_t", 0.0)
	p.bus = bus
	node.add_child(p)
	p.stream = s
	p.play()
	_pos_loops[reg] = p


func stop_loop(key: String) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p != null:
		_loops.erase(key)
		if is_instance_valid(p):
			p.queue_free()
	var q = _pos_loops.get(key)          # bez typu: patrz _shutdown
	if q != null:
		_pos_loops.erase(key)
		if is_instance_valid(q):
			q.queue_free()


func stop_all() -> void:
	for key in _loops.keys():
		stop_loop(key)
	for key in _pos_loops.keys():
		stop_loop(key)
	for n in _pool:
		n.stop()
	for n in _pos_pool:
		n.stop()
	for i in _music.size():
		_music[i].stop()
		_stem_gain[i] = 0.0
		_stem_target[i] = 0.0
	_music_layer = -1
	_music_started = false
	_drop_to = -1
	_drop_at = -1.0
	_deaf = 0.0
	_duck_db = 0.0


func set_loop_volume(key: String, vol_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p != null:
		p.volume_db = vol_db
		return
	var q = _pos_loops.get(key)
	if q != null and is_instance_valid(q):
		q.volume_db = vol_db


func loop_playing(key: String) -> bool:
	var p: AudioStreamPlayer = _loops.get(key)
	if p != null and is_instance_valid(p):
		return p.playing
	var q = _pos_loops.get(key)
	return q != null and is_instance_valid(q) and q.playing


# ---------------------------------------------------------------- propagacja

## Próg okluzji źródła względem słuchawki: 0 czysto, 1 lekko (jeden promień zasłonięty —
## róg ściany), 2 mocno, 3 całkiem za ścianą. Cache per komórka i klatka.
func occlusion_tier(from: Vector2) -> int:
	var cell := Vector2i(round(from.x / OCCL_CELL), round(from.y / OCCL_CELL))
	if _occl.has(cell):
		return _occl[cell]
	var tier := 0
	var world := get_viewport().get_world_2d()
	if world != null:
		var to := _listener_pos
		var dir := to - from
		if dir.length() > 20.0:
			var side := Vector2(-dir.y, dir.x).normalized() * OCCL_FLANK
			var space := world.direct_space_state
			for off in [Vector2.ZERO, side, -side]:
				var q := PhysicsRayQueryParameters2D.create(from + off, to)
				q.collision_mask = OCCLUSION_MASK
				q.hit_from_inside = false
				if not space.intersect_ray(q).is_empty():
					tier += 1
	_occl[cell] = tier
	return tier


## Zgodność wsteczna: czy źródło jest w ogóle zasłonięte.
func is_occluded(from: Vector2) -> bool:
	return occlusion_tier(from) >= 2


func _tier_bus(base: String, tier: int) -> String:
	if tier <= 0:
		return base
	return OCC_BUSES[clampi(tier, 1, 3) - 1]


## Słuchawka jedzie za kamerą lokalnego CZŁOWIEKA. Przepinamy ją tylko, gdy
## zmienia się właściciel (boty też mają autorytet hosta; reparent z keep_global=false,
## inaczej słuchawka zostawałaby w (0,0) świata i promienie okluzji szłyby w złe miejsce).
func _follow_listener() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var pp := p as Node2D
		if pp == null or pp.is_bot or not pp.is_multiplayer_authority():
			continue
		var cam := pp.get_node_or_null("Camera2D") as Camera2D
		var target: Node = cam if cam != null else pp
		if _listener.get_parent() != target:
			_listener.reparent(target, false)
			_listener.position = Vector2.ZERO
			_listener.make_current()
		return
	# brak lokalnego człowieka (lobby, rozłączenie) — słuchawka wraca do nas
	if _listener.get_parent() != self:
		_listener.reparent(self, false)
		_listener.position = Vector2.ZERO


## Co 0,2 s: próg okluzji pętli pozycyjnych, z histerezą (min. 0,35 s na progu).
func _update_loop_occlusion() -> void:
	for key in _pos_loops.keys():
		var q = _pos_loops[key]
		if not is_instance_valid(q):
			_pos_loops.erase(key)
			continue
		var tier := occlusion_tier(q.global_position)
		var cur: int = q.get_meta("tier", 0)
		if tier != cur and _clock - float(q.get_meta("tier_t", 0.0)) > 0.35:
			q.set_meta("tier", tier)
			q.set_meta("tier_t", _clock)
			q.bus = _tier_bus(String(q.get_meta("base_bus", BUS_WORLD)), tier)


# ---------------------------------------------------------------- środowisko (pogłos)

func _bind_effects() -> void:
	var sfx := AudioServer.get_bus_index(BUS_SFX)
	if sfx >= 0:
		for i in AudioServer.get_bus_effect_count(sfx):
			var fx := AudioServer.get_bus_effect(sfx, i)
			if fx is AudioEffectReverb:
				_rev_fx = fx
	for b in [BUS_MUSIC, BUS_AMB, BUS_SFX]:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		for i in AudioServer.get_bus_effect_count(idx):
			var fx := AudioServer.get_bus_effect(idx, i)
			if fx is AudioEffectLowPassFilter:
				_lp_fx.append(fx)
	if _rev_fx == null or _lp_fx.size() < 3:
		push_warning("[AUDIO] bus layout bez oczekiwanych efektów (Reverb na SFX, LP na Music/Ambience/SFX)")


## Wachlarz 12 promieni wokół słuchawki → zamknięcie i średnia odległość ścian.
func _probe_environment() -> void:
	var world := get_viewport().get_world_2d()
	if world == null or _rev_fx == null:
		return
	var space := world.direct_space_state
	var reach := 520.0
	var hits := 0
	var dsum := 0.0
	var n := 12
	for i in n:
		var a := TAU * float(i) / float(n)
		var q := PhysicsRayQueryParameters2D.create(_listener_pos,
			_listener_pos + Vector2.from_angle(a) * reach)
		q.collision_mask = OCCLUSION_MASK
		var r := space.intersect_ray(q)
		if r.is_empty():
			dsum += reach
		else:
			hits += 1
			dsum += _listener_pos.distance_to(r["position"])
	var enclosure := float(hits) / float(n)
	var mean_d := dsum / float(n) / reach          # 0 ciasno .. 1 otwarcie
	_rev_wet_t = lerpf(0.04, 0.26, enclosure)
	_rev_room_t = lerpf(0.30, 0.82, clampf(enclosure * (1.15 - 0.6 * mean_d), 0.0, 1.0))
	_rev_damp_t = lerpf(0.70, 0.32, enclosure)


func _update_reverb(delta: float) -> void:
	_rev_timer -= delta
	if _rev_timer <= 0.0:
		_rev_timer = 0.25
		_probe_environment()
	if _rev_fx == null:
		return
	var k := 1.0 - exp(-delta * 1.4)                 # ~0,7 s stałej czasowej — bez skoków
	_rev_wet = lerpf(_rev_wet, _rev_wet_t, k)
	_rev_room = lerpf(_rev_room, _rev_room_t, k)
	_rev_damp = lerpf(_rev_damp, _rev_damp_t, k)
	_rev_fx.wet = _rev_wet
	_rev_fx.room_size = _rev_room
	_rev_fx.damping = _rev_damp


# ---------------------------------------------------------------- ogłuszenie / szum w uszach

## Wybuch w pobliżu słuchawki: muffling całego miksu + szum w uszach, proporcjonalnie do bliskości.
func _on_explosion(pos: Vector2) -> void:
	var d := pos.distance_to(_listener_pos)
	if d >= 420.0:
		return
	var amt := 1.0 - d / 420.0
	deafen(amt, 0.6 + amt * 1.8)
	if amt > 0.25:
		play("ear_ring", BUS_UI, lerpf(-24.0, -10.0, amt))


## Trafienie lokalnego gracza: krótkie przytłumienie; mocne (2→1 HP) dorzuca szum w uszach.
func on_player_hurt(severe := false) -> void:
	deafen(0.45 if severe else 0.22, 0.35)
	if severe:
		play("ear_ring", BUS_UI, -20.0)


## amount 0..1 (1 = głęboko przytłumiony), hold = ile sekund trzymać zanim zacznie się odbudowywać słuch.
func deafen(amount: float, hold: float) -> void:
	_deaf = maxf(_deaf, clampf(amount, 0.0, 1.0))
	_deaf_hold = maxf(_deaf_hold, hold)


func _update_deafness(delta: float) -> void:
	if _deaf_hold > 0.0:
		_deaf_hold -= delta
	elif _deaf > 0.0:
		_deaf = maxf(0.0, _deaf - delta * 0.3)         # ~3 s powrotu do pełnego słuchu
	var cutoff := 20500.0 * pow(850.0 / 20500.0, _deaf)
	for fx in _lp_fx:
		fx.cutoff_hz = cutoff


# ---------------------------------------------------------------- muzyka

## layer: 0 cisza, 1 napięcie, 2 walka, 3 pościg — STEMY NAKŁADAJĄ SIĘ (0..layer grają).
## Wejście stemu kwantyzowane do beatu; zejście w dół opóźnione (hold), żeby muzyka
## nie opadała w sekundę po ostatnim strzale.
func music_set_layer(layer: int) -> void:
	if not _enabled:
		return
	var top := Manifest.MUSIC_STEMS.size() - 1
	layer = clampi(layer, 0, top)
	if not _music_start():
		return
	if layer == _music_layer and _drop_to < 0:
		return
	if layer >= _music_layer:
		_drop_to = -1
		_drop_at = -1.0
		for i in range(layer + 1):
			if _stem_target[i] < 1.0:
				_stem_target[i] = 1.0
				_stem_enter_at[i] = _clock + _quant_delay(i)
		_music_layer = layer
	else:
		var hold: float = [0.0, 2.5, 6.0, 8.0][clampi(_music_layer, 0, 3)]
		_drop_to = layer
		_drop_at = _clock + hold


func _music_start() -> bool:
	if _music_started:
		return true
	var ok := true
	for i in Manifest.MUSIC_STEMS.size():
		if stream(Manifest.MUSIC_STEMS[i]) == null:
			ok = false
	if not ok:
		return false
	# Start wszystkich stemów w TEJ SAMEJ chwili miksu (lock = wątek audio czeka),
	# inaczej jeden z nich mógłby ruszyć bufor później → przesunięcie fazy rytmu.
	AudioServer.lock()
	for i in _music.size():
		_music[i].stream = stream(Manifest.MUSIC_STEMS[i])
		_music[i].volume_db = -80.0
		_music[i].play()
	AudioServer.unlock()
	_music_started = true
	_stem_target[0] = 1.0
	_stem_enter_at[0] = _clock
	_music_layer = 0
	return true


## Czas do następnej siatki rytmicznej danego stemu (s). 0 = natychmiast.
func _quant_delay(stem: int) -> float:
	if not _music_started or not _music[0].playing:
		return 0.0
	var beat := 60.0 / float(Manifest.MUSIC_BPM)
	var grid: float = beat * [1.0, 1.0, 0.5, 0.25][clampi(stem, 0, 3)]
	var pos := _music[0].get_playback_position() + AudioServer.get_time_since_last_mix()
	var d := grid - fmod(pos, grid)
	return 0.0 if d > grid - 0.02 else d


func _update_music(delta: float) -> void:
	if not _music_started:
		return
	if _drop_to >= 0 and _clock >= _drop_at:
		for i in range(_drop_to + 1, _stem_target.size()):
			_stem_target[i] = 0.0
		_music_layer = _drop_to
		_drop_to = -1
		_drop_at = -1.0
	if _duck_hold > 0.0:
		_duck_hold -= delta
	else:
		_duck_db = minf(0.0, _duck_db + delta * 6.0)    # ~1 s powrotu z -6 dB
	var duck := db_to_linear(_duck_db)
	for i in _music.size():
		var blend: float = Manifest.MUSIC_BLEND[i]
		if _stem_target[i] > 0.5:
			if _clock >= _stem_enter_at[i]:
				_stem_gain[i] = minf(1.0, _stem_gain[i] + delta / maxf(0.05, blend))
		else:
			_stem_gain[i] = maxf(0.0, _stem_gain[i] - delta / maxf(1.2, blend * 1.5))
		var g := _stem_gain[i] * duck
		_music[i].volume_db = -80.0 if g <= 0.0001 else linear_to_db(g)


func music_layer() -> int:
	return _music_layer


## Chwilowe przyciszenie muzyki (stingery, krzyk) — wraca po `hold` sekundach.
func duck_music(db: float, hold: float) -> void:
	_duck_db = minf(_duck_db, db)
	_duck_hold = maxf(_duck_hold, hold)


func sting(layer: int) -> void:
	# Stinger to moment, nie warstwa — gra na muzykę i znika, a muzyka na chwilę ustępuje.
	var key := "sting_%s" % ("chase" if layer >= 2 else "tension")
	if Manifest.PATHS.has(key):
		play(key, BUS_MUSIC, -2.0)
		duck_music(-6.0 if layer >= 2 else -4.0, 1.4)


# ---------------------------------------------------------------- napisy (dostępność)

func _caption(key: String, pos: Vector2) -> void:
	if caption.get_connections().is_empty():
		return
	var best := ""
	for k in Manifest.CAPTIONS:
		if key.begins_with(k) and k.length() > best.length():
			best = k
	if best == "":
		return
	var c: Array = Manifest.CAPTIONS[best]
	var text: String = c[0]
	var now := Time.get_ticks_msec()
	if now - int(_last_caption.get(text, -100000)) < 1200:
		return
	_last_caption[text] = now
	caption.emit(text, pos, int(c[1]))


# ---------------------------------------------------------------- emitery ambientu

func _update_emitters(delta: float) -> void:
	if not (_loops.has("amb_forest") or _loops.has("amb_machine")):
		return
	_emit_t -= delta
	if _emit_t > 0.0:
		return
	var lvl := NoiseMgr.level
	_emit_t = randf_range(7.0, 15.0) * lerpf(1.0, 0.55, clampf(lvl / 60.0, 0.0, 1.0))
	var total := 0.0
	var cand: Array = []
	for e in EMITTERS:
		if lvl < float(e[6]):
			continue
		if bool(e[7]) and NoiseMgr.stalker_awake:
			continue
		cand.append(e)
		total += float(e[5])
	if cand.is_empty():
		return
	var roll := randf() * total
	for e in cand:
		roll -= float(e[5])
		if roll <= 0.0:
			var pos := _listener_pos + Vector2.from_angle(randf() * TAU) * randf_range(float(e[2]), float(e[3]))
			play_variant_at(String(e[0]), int(e[1]), pos, BUS_AMB, float(e[4]), 1.0, 0.05)
			return


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_clock += delta
	_listener_pos = _listener.global_position
	_occl.clear()                      # przeszkody zmieniają się dynamicznie
	_follow_listener()
	_loop_occl_timer -= delta
	if _loop_occl_timer <= 0.0:
		_loop_occl_timer = 0.2
		_update_loop_occlusion()
	_update_reverb(delta)
	_update_deafness(delta)
	_update_music(delta)
	_update_emitters(delta)
	_update_heart(delta)


## Serce: powyżej progu bije szybciej i głośniej. Cisza = cisza (GDD §13).
func _update_heart(_delta: float) -> void:
	if not _enabled:
		return
	var lvl := NoiseMgr.level / NoiseMgr.MAX_LEVEL
	var want := HEART_FAST_KEY if lvl >= HEART_FAST_AT else HEART_SLOW_KEY
	var want_vol := -80.0
	if lvl >= 0.12:
		want_vol = lerpf(-22.0, -9.0, clampf((lvl - 0.12) / 0.6, 0.0, 1.0))
	if want != _heart_key:
		if _heart_key != "":
			stop_loop(_heart_key)
		_heart_key = want
	# Startujemy też wtedy, gdy klucz się nie zmienił, a pętla nie gra (np. wejście z lobby
	# przy Uwadze 0 ustawiło klucz bez startu).
	if want_vol > -80.0 and not loop_playing(_heart_key):
		start_loop(_heart_key, BUS_PLAYER, want_vol)
	elif loop_playing(_heart_key):
		set_loop_volume(_heart_key, want_vol)


## Wyłącza cały dźwięk (np. przy starcie lobby, żeby nie grało na pustce).
func set_enabled(on: bool) -> void:
	_enabled = on
	if on:
		return
	stop_all()
