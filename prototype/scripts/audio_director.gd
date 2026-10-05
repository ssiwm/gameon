extends Node
## AudioDirector — autoload `Audio`. Jedyne miejsce w projekcie, które wie
## o plikach WAV; reszta kodu woła tylko Audio.play(...) / Audio.play_at(...).
##
## Trzy rzeczy, które dzieją się tu i są kluczowe dla GDD §13 („Audio (filar!)"):
##
##   1. PROPAGACJA PRZEZ ŚCIANY. Raycast ze źródła do słuchawki; jeśli
##      przeszkoda na linii, głos leci na bus „Occluded" (lowpass 620 Hz).
##      To jest cały efekt „słyszysz, ale nie widzisz" — bez niego stalker
##      za ścianą brzmi jakby stał obok.
##
##   2. MUZYKA ADAPTACYJNA. Warstwy z manifestu przełączane crossfadem.
##      UWAGA na rozjazd z komentarzem w manifeście: manifest mówi „kumulatywne",
##      ale bake renderuje każdą warstwę jako PEŁNY, samodzielny utwór
##      (d.buf_norm na całości, osobny zapis). Nakładanie ich = podwójny bas
##      i podwójna perkusja, więc tu jest crossfade, a nie stack.
##
##   3. SERCE. Poziom Uwagi (NoiseMgr) steruje tempem i głośnością — najtańszy
##      sposób na zrobienie z HUD-u strachu.

const Manifest := preload("res://scripts/audio_manifest.gd")

const BUS_MUSIC := "Music"
const BUS_AMB := "Ambience"
const BUS_PLAYER := "Player"
const BUS_WEAPONS := "Weapons"
const BUS_WORLD := "World"
const BUS_STALKER := "Stalker"
const BUS_UI := "UI"
const BUS_OCCLUDED := "Occluded"

## Warstwa kolizji ścian (World w main.tscn ustawia collision_layer = 1).
const OCCLUSION_MASK := 1
## Siatka kwantowania pozycji w cache'u przeszkód — 24 px wystarcza, żeby
## krok po kaflu nie odpytywał świata co klatkę z osobna dla każdego piksela.
const OCCL_CELL := 24.0

const ONESHOT_POOL := 24
const POSITIONAL_POOL := 16

# Serce: próg, od którego bije szybciej (GDD: Uwaga napędza strach).
const HEART_FAST_AT := 0.45
const HEART_SLOW_KEY := "heart_slow_loop"
const HEART_FAST_KEY := "heart_fast_loop"

var _cache: Dictionary = {}          # String -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _pos_pool: Array[AudioStreamPlayer2D] = []
var _loops: Dictionary = {}          # String -> AudioStreamPlayer
var _reported: Dictionary = {}       # klucze zgłoszone jako brakujące (raz)
var _music: Array[AudioStreamPlayer] = []
var _music_layer := -1
var _music_tween: Tween
var _listener: AudioListener2D
var _listener_pos := Vector2.ZERO
var _occl: Dictionary = {}            # Vector2i -> bool
var _heart_key := ""
var _heart_vol := -80.0
var _enabled := true


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
		q.max_distance = 1600.0
		q.attenuation = 1.1
		add_child(q)
		_pos_pool.append(q)

	for _i in Manifest.MUSIC_STEMS.size():
		var m := AudioStreamPlayer.new()
		m.bus = BUS_MUSIC
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)

	_verify_manifest()


func _exit_tree() -> void:
	_shutdown()


## Publiczne wyłączenie dźwięku — np. powrót do lobby albo restart sesji.
func shutdown() -> void:
	_shutdown()


## Zamykanie audio: stop + zwolnienie referencji do strumieni, potem free()
## (nie queue_free() — kolejka nie zdąża się przetworzyć przy wyjściu).
##
## UWAGA, zweryfikowane eksperymentem: to NIE eliminuje ostrzeżenia
## „leaked instances" w headless. Wywołanie shutdown() przed get_tree().quit()
## daje identyczny wynik, a referencje do zapętlonych AudioStreamWAV trzyma
## wątek audio Godota 4.7. Wyciek jest więc wyłącznie kosmetyczny i dotyczy
## momentu zamykania procesu, nie działania gry.
func _shutdown() -> void:
	for key in _loops.keys():
		var p: AudioStreamPlayer = _loops[key]
		_loops.erase(key)
		p.stop()
		p.stream = null      # samo stop() zostawia referencję do AudioStreamWAV
		p.free()
	for n in _pool:
		(n as AudioStreamPlayer).stop()
		(n as AudioStreamPlayer).stream = null
	for n in _pos_pool:
		(n as AudioStreamPlayer2D).stop()
		(n as AudioStreamPlayer2D).stream = null
	for n in _music:
		(n as AudioStreamPlayer).stop()
		(n as AudioStreamPlayer).stream = null
	_heart_key = ""
	_music_layer = -1
	# Cache trzyma AudioStreamWAV w referencjach — bez tego wyciekają w
	# raporcie ObjectDB mimo stopnięcia wszystkich odtwarzaczy.
	_cache.clear()
	_reported.clear()
	_occl.clear()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()


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


## Losuje wariant z rodziny „m83_shot_1..4". Zwraca -1 gdy żadnego nie ma.
func variant(base: String, count: int) -> int:
	var found := -1
	for i in count:
		if Manifest.PATHS.has("%s_%d" % [base, i + 1]):
			found = i
	return found


func pick(base: String, count: int) -> String:
	var idx := randi_range(0, maxi(0, variant(base, count)))
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


# ---------------------------------------------------------------- one-shoty

func play(key: String, bus: String = BUS_PLAYER, vol_db := 0.0, pitch := 1.0) -> void:
	if not _enabled:
		return
	var s := stream(key)
	if s == null:
		return
	var p := _free_pool(_pool)
	p.stream = s
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## Wariant losowy w jednym wywołaniu: Audio.play_variant("m83_shot", 4, ...)
func play_variant(base: String, count: int, bus: String = BUS_WEAPONS,
		vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if variant(base, count) < 0:
		return
	play(pick(base, count), bus, vol_db, pitch + randf_range(-pitch_jitter, pitch_jitter))


## Gra dźwięku w świecie: pozycyjny, z attenuation i z propagacją przez ściany.
func play_at(key: String, pos: Vector2, bus: String = BUS_WORLD,
		vol_db := 0.0, pitch := 1.0) -> void:
	if not _enabled:
		return
	var s := stream(key)
	if s == null:
		return
	var p := _free_pool(_pos_pool)
	p.stream = s
	p.position = pos
	p.bus = BUS_OCCLUDED if is_occluded(pos) else bus
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func play_variant_at(base: String, count: int, pos: Vector2, bus: String = BUS_WORLD,
		vol_db := 0.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if variant(base, count) < 0:
		return
	play_at(pick(base, count), pos, bus, vol_db,
		pitch + randf_range(-pitch_jitter, pitch_jitter))


## Zwraca wolnego gracza z puli; jak wszystkie grają, przekreca najdłużej
## grającego. Celowo bez `as AudioStreamPlayer` — AudioStreamPlayer2D NIE
## dziedziczy z AudioStreamPlayer, więc taki cast zamieniał całą pulę
## pozycyjną w null i każde play_at() wywracało się.
func _free_pool(pool: Array) -> Node:
	var oldest: Node = null
	var oldest_pos := -1.0
	for n in pool:
		if not n.playing:
			return n
		var pp: float = n.get_playback_position()
		if oldest == null or pp > oldest_pos:
			oldest = n
			oldest_pos = pp
	if oldest == null:
		return null
	oldest.stop()
	return oldest


## --- powierzchnie pod stopami -------------------------------------------
## W prototypie poziom nie ma tilemapy, więc powierzchnia wyliczana jest
## z geometrii (main.tscn): platformy P1..P6 to blacha, ziemia dzieli się
## pasami. To PLACEHOLDER — przy własnych tilemapach wystarczy podmienić
## ciało tej funkcji na odczyt z tilemapy, interfejs zostaje ten sam.
func surface_at(pos: Vector2) -> String:
	# poziom na tilemapie zna powierzchnię kafla pod stopami
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl != null:
		return lvl.surface_at(pos)
	if pos.y < 190.0:
		return "metal"                      # stoisz na platformie
	if pos.x < 500.0:
		return "dirt"
	if pos.x < 1000.0:
		return "concrete"
	return "water"


## Losuje krok na danej powierzchni (3 warianty na powierzchnię).
func play_footstep(pos: Vector2, crouching: bool, vol_db := -14.0) -> void:
	var surf := surface_at(pos)
	if variant("step_" + surf, 3) < 0:
		return
	# Kucanie musi być ROZPOZNAWALNE jako cisza (GDD §8.1) — stąd cicho.
	var v := vol_db - 6.0 if crouching else vol_db
	play_variant_at("step_" + surf, 3, pos, BUS_PLAYER, v, 1.0, 0.09)


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


func stop_loop(key: String) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null:
		return
	_loops.erase(key)
	p.queue_free()


func stop_all() -> void:
	for key in _loops.keys():
		stop_loop(key)
	for n in _pool:
		(n as AudioStreamPlayer).stop()
	for n in _pos_pool:
		(n as AudioStreamPlayer2D).stop()
	for n in _music:
		(n as AudioStreamPlayer).stop()
	_music_layer = -1
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()


func set_loop_volume(key: String, vol_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p != null:
		p.volume_db = vol_db


func loop_playing(key: String) -> bool:
	var p: AudioStreamPlayer = _loops.get(key)
	return p != null and p.playing


# ---------------------------------------------------------------- propagacja

## Czy słyszalność źródła do słuchawki blokuje przeszkoda (ściana).
func is_occluded(from: Vector2) -> bool:
	var cell := Vector2i(round(from.x / OCCL_CELL), round(from.y / OCCL_CELL))
	if _occl.has(cell):
		return _occl[cell]
	var world := get_viewport().get_world_2d()
	var blocked := false
	if world != null:
		var q := PhysicsRayQueryParameters2D.create(from, _listener_pos)
		q.collision_mask = OCCLUSION_MASK
		q.hit_from_inside = false
		blocked = not world.direct_space_state.intersect_ray(q).is_empty()
	_occl[cell] = blocked
	return blocked


## Słuchawka jedzie za kamerą lokalnego CZŁOWIEKA. Przepinamy ją tylko, gdy
## zmienia się właściciel. Dwa błędy z wcześniejszej wersji:
##   - boty też mają autorytet hosta, a pętla przerywała się dopiero PO
##     przepięciu, więc na hoście słuchawka skakała co klatkę gracz↔bot;
##   - reparent() domyślnie zachowuje pozycję GLOBALNĄ, więc słuchawka
##     zostawała w (0,0) świata zamiast w środku kamery i promienie okluzji
##     szły do złego punktu.
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


# ---------------------------------------------------------------- muzyka

## layer: 0 cisza, 1 napięcie, 2 walka, 3 pościg.
func music_set_layer(layer: int) -> void:
	if not _enabled:
		return
	var top := Manifest.MUSIC_STEMS.size() - 1
	layer = clampi(layer, 0, top)
	if layer == _music_layer:
		return
	var s := stream(Manifest.MUSIC_STEMS[layer])
	if s == null:
		return
	var incoming := _music[layer]
	# Warstwy mają tę samą długość (16 taktów), więc nowa wchodzi w tym samym
	# miejscu taktu co grająca — przejście nie gubi rytmu. Jeśli ta warstwa
	# wciąż wybrzmiewa (szybki powrót), gra dalej od miejsca, w którym jest.
	if not incoming.playing:
		incoming.stream = s
		incoming.volume_db = -80.0
		var pos := _music_position()
		incoming.play(fmod(pos, s.get_length()) if pos >= 0.0 else 0.0)
	_music_layer = layer
	# Czas wjścia na warstwę jest asymetryczny (MUSIC_BLEND): wchodzenie
	# w spokój trwa, w akcję jest natychmiastowe.
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	var blend := float(Manifest.MUSIC_BLEND[layer])
	_music_tween.tween_property(incoming, "volume_db", 0.0, blend)
	# Wygaszamy WSZYSTKIE pozostałe warstwy, nie tylko poprzednią — przy
	# szybkiej zmianie 0→1→2 przerwany tween zostawiał warstwę 0 na
	# połowie głośności na zawsze. Wygaszone zatrzymujemy.
	for i in _music.size():
		var m := _music[i]
		if i == layer or not m.playing:
			continue
		_music_tween.tween_property(m, "volume_db", -80.0, blend)
	_music_tween.chain().tween_callback(_stop_silent_stems)


## Pozycja odtwarzania grającej warstwy (do synchronizacji wejścia nowej).
func _music_position() -> float:
	for m in _music:
		if m.playing and m.volume_db > -79.0:
			return m.get_playback_position()
	return -1.0


func _stop_silent_stems() -> void:
	for i in _music.size():
		if i != _music_layer and _music[i].volume_db <= -79.0:
			_music[i].stop()


func music_layer() -> int:
	return _music_layer


func sting(layer: int) -> void:
	# Stinger to moment, nie warstwa — gra na muzykę i znika.
	var key := "sting_%s" % ("chase" if layer >= 2 else "tension")
	if Manifest.PATHS.has(key):
		play(key, BUS_MUSIC, -2.0)


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_listener_pos = _listener.global_position
	_occl.clear()                      # przeszkody zmieniają się dynamicznie
	_follow_listener()
	_update_heart(delta)


## Serce: powyżej progu bije szybciej i głośniej. Cisza = cisza (GDD §13).
func _update_heart(delta: float) -> void:
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
	# Startujemy też wtedy, gdy klucz się nie zmienił, a pętla nie gra —
	# wcześniej start był tylko przy ZMIANIE klucza, więc gdy w lobby
	# (Uwaga 0) klucz ustawił się na wolne serce bez startu, serce milczało
	# aż do pierwszego przejścia w szybkie.
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