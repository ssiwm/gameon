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
##      Źródło mocno zasłonięte może zagrać „dookoła": drogą po wolnych kaflach mapy
##      (level.sound_grid), z kierunku przejścia i z odległości równej długości drogi —
##      jeśli tak wychodzi głośniej niż przez ścianę (_placement).
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
## Początek wyjścia z gry (przycisk Quit, zamknięcie okna, koniec testu) — main.gd domyka wtedy dziennik misji w toku.
signal quitting

const Surfaces := preload("res://scripts/surfaces.gd")
const Weather := preload("res://scripts/weather.gd")
const Manifest := preload("res://scripts/audio_manifest.gd")
const Sight := preload("res://scripts/sight.gd")

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
## Pogoda (WEATHER_PLAN.md W2–W4, weather_sound.gd): własna szyna z suwakiem (D4), wpięta w „Ambience” (ogłuszenie, pogłos tła
## i ściszanie pod strzałami działają na nią same). Na szynie: „Duck_weather” (ściszanie pod sygnałami, zasada 5) i filtr
## podziemi; grzmot ma podszynę „Thunder” z filtrem odległości.
const BUS_WEATHER := "Weather"
const BUS_THUNDER := "Thunder"
## Sygnały przed pogodą (zasada 5 planu): dźwięk o priorytecie głosu co najmniej tym (strzały, wrogowie, krzyki, Stalker, radio,
## podpowiedzi) ścisza pogodę o WEATHER_DUCK_DB na czas WEATHER_DUCK_HOLD — ulewa nie zagłusza tego, co trzeba usłyszeć.
const WEATHER_DUCK_PRIO := 42
const WEATHER_DUCK_DB := -5.0
const WEATHER_DUCK_HOLD := 0.7
const WEATHER_UNDER_HZ := 400.0       ## pod ziemią pogoda słychać jak przez warstwę ziemi (filtr zamiast samego ściszenia)
## Zgodność wsteczna: dawny pojedynczy bus okluzji.
const BUS_OCCLUDED := BUS_OCC_HEAVY
const OCC_BUSES := [BUS_OCC_LIGHT, BUS_OCC_HEAVY, BUS_OCC_BLOCKED]

## Warstwa kolizji ścian (World w main.tscn ustawia collision_layer = 1) i cała szyba okna (window_glass.gd SOUND_LAYER = 256).
const OCCLUSION_MASK := 1 | 256
## Siatka kwantowania pozycji w cache'u przeszkód (jeden raz na klatkę na komórkę).
const OCCL_CELL := 24.0
## Rozstaw bocznych promieni okluzji (px) — „szerokość" ściany, którą dźwięk omija.
const OCCL_FLANK := 18.0

## Assety z nagrań (poza repo) i syntetyczne (w repo) — patrz _path().
const PUBLIC_ROOT := "res://audio/"
const LICENSED_ROOT := "res://audio_licensed/"

## Droga dźwięku po mapie (AUDIO_PLAN.md F6, level.sound_grid). Źródło zasłonięte (próg okluzji ≥ 2) może zagrać
## „dookoła": z kierunku ostatniego rogu drogi, z odległości równej jej długości, przez najlżejszy filtr.
## Wybieramy głośniejszą z dwóch dróg — dookoła albo przez ścianę (wprost, z ciężkim filtrem).
const ROUTE_TIER := 1                 ## próg okluzji (szyna) dla dźwięku, który obszedł przeszkodę
const ROUTE_LOSS_DB := -2.0           ## strata na ugięciu wokół rogu
const WALL_LOSS_DB := [0.0, 0.0, -9.0, -16.0]   ## szacowana strata „przez ścianę” dla progów okluzji 0–3 (filtry OccHeavy / OccBlocked)
const ROUTE_SMOOTH := 8.0             ## 1/s: jak szybko pętla pozycyjna przesuwa się do nowego pozornego położenia

const ONESHOT_POOL := 32
const POSITIONAL_POOL := 28
const SHUTDOWN_DRAIN_USEC := 100000
const MAX_DISTANCE := 1600.0
## Bliska i daleka wersja tej samej rodziny (`<broń>_shot` → `<broń>_far`, `explosion` → `explosion_far`) przenikają się
## wg odległości od słuchacza: do FAR_START gra sama bliska, od FAR_FULL sama daleka (stała moc pomiędzy).
const FAR_START := 300.0
const FAR_FULL := 900.0

## Rodzina dźwięku -> [priorytet 0-100, max równoczesnych, min odstęp ms]. Dopasowanie
## po NAJDŁUŻSZYM prefiksie; wszystko inne dostaje DEFAULT_VOICE.
const VOICE := {
	"stalker_shriek": [100, 2, 0], "player_down": [95, 1, 0], "explosion": [92, 3, 0],
	"sting": [90, 2, 0], "stalker_growl": [85, 2, 700], "revive": [80, 1, 0],
	"player_hurt": [80, 2, 120], "stalker_step": [70, 3, 140], "spread12_shot": [75, 4, 0],
	"p64_shot": [65, 5, 0], "m83_shot": [60, 8, 0], "ui_": [55, 3, 0], "warn_pulse": [55, 1, 300],
	"oc_load": [55, 1, 0], "radio_beep": [50, 2, 0], "impact_flesh": [45, 5, 30],
	"land_hard": [40, 2, 100], "dry_fire": [40, 1, 90],
	"impact_hard": [35, 6, 25], "step_": [30, 6, 0], "ricochet": [30, 3, 60],
	"whizz": [25, 3, 70], "amb_": [20, 3, 0], "foley_gear": [10, 2, 120], "shell_": [8, 4, 60],
	# głosy gatunków: krzyk alarmu i bossowie jak Stalker; zwykli wrogowie niżej, z odstępem — wataha nie robi ściany dźwięku
	"podsluchacz_scream": [88, 2, 0], "kaplan_scream": [88, 2, 0], "zerca_grab": [88, 2, 0], "rzeznik_roar": [70, 2, 0], "zerca_warn": [44, 1, 2500], "zyla_": [86, 2, 0], "leech_": [86, 2, 0],
	"wolek_": [50, 2, 100], "slepiec_": [46, 2, 100], "trzosek_death": [44, 3, 60], "trzosek_attack": [42, 3, 80],
}
const DEFAULT_VOICE := [40, 6, 0]

## Emitery ambientu: [baza, liczba wariantów, odległość min, odległość max, głośność dB,
## waga, minimalna Uwaga, tylko gdy Stalker śpi]. Podmuch i skrzypienie (WIND_EMITTERS) ważone siłą wiatru z zegara pogody
## (`weather_wind`, W3): w ciszy prawie znikają, w burzy przeważają; podmuch nadchodzi od strony wiatru.
const EMITTERS := [
	["amb_gust", 3, 200.0, 520.0, -4.0, 3.0, 0.0, false],
	["amb_creak", 3, 260.0, 680.0, -3.0, 2.0, 0.0, false],
	["amb_thud", 2, 650.0, 1050.0, 2.0, 1.2, 0.0, false],
	["amb_far_cry", 2, 900.0, 1400.0, 4.0, 0.9, 25.0, true],
]
const WIND_EMITTERS := ["amb_gust", "amb_creak"]
const WIND_REF := 0.85                 ## siła wiatru (skala `WeatherClock.WIND_BASE`), przy której podmuch i skrzypienie mają wagę z EMITTERS

## Wiatr z zegara pogody (weather_fx.gd → weather_sound.gd, W3) dla emiterów: siła (WIND_REF bez deszczu, burzy i mgły — waga z EMITTERS bez zmian) i kierunek (+1 z prawej).
var weather_wind := WIND_REF
var weather_wdir := 1.0
var _wduck_db := 0.0
var _wduck_hold := 0.0
var _wduck_fx: AudioEffectAmplify
var _wunder_fx: AudioEffectLowPassFilter
var _wunder := 0.0                    ## 0..1: jak głęboko pod ziemią (filtr pogody), ustawia weather_sound.gd
var _thunder_fx: AudioEffectLowPassFilter
var _thunder_hz := 20500.0

var _cache: Dictionary = {}          # String -> AudioStream
var _warm: Dictionary = {}           # String -> ścieżka: klucz wczytywany w tle (_warm_all), jeszcze nie w _cache
var _warm_paths: Dictionary = {}     # ścieżka -> true: zlecenie ResourceLoader.load_threaded_request czeka na odbiór
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
var _enabled := true
var _quitting := false
var _use_licensed := not ("--synthaudio" in OS.get_cmdline_user_args())
var _use_routes := not ("--nosoundpath" in OS.get_cmdline_user_args())   ## dev: bez drogi po mapie (porównanie w grze)
var _use_far := not ("--nofar" in OS.get_cmdline_user_args())             ## dev: bez dalekich wersji strzałów (porównanie w grze)
var _far_cache: Dictionary = {}   # rodzina bliska -> [baza dalekiej, liczba wariantów] albo []
var _routes: Dictionary = {}         # Vector2i (komórka źródła) -> [pozorne położenie: Vector2, długość drogi: float] albo []
var _routes_ear := Vector2i(-9999, -9999)    # komórka słuchacza, dla której policzono _routes
var _routes_ver := -1                # wersja siatki poziomu, dla której policzono _routes
var _clock := 0.0

# --- muzyka
var _music: Array[AudioStreamPlayer] = []
var _stem_gain: Array[float] = []     # postęp przejścia 0..1 (głośność z krzywej `_fade_gain`, nie liniowo)
var _stem_target: Array[float] = []
var _stem_enter_at: Array[float] = []  # od kiedy (zegar) stem może zacząć wchodzić
var _music_layer := -1
var _music_started := false
const MUSIC_FADE_OUT := [10.0, 8.0, 6.0, 5.0]   ## s wyciszania stemu (cisza … pościg); od 1.7.578 dłużej i krzywą w dB (`_fade_gain`)
const MUSIC_FADE_FLOOR_DB := -40.0               ## początek / koniec krzywej przejścia (poniżej tego stem jest niesłyszalny)
const MUSIC_DROP_HOLD := [0.0, 2.0, 3.0, 4.0]    ## s czekania przed zejściem z warstwy (resztę trzyma MusicDirector: MIN_ON, MIN_STEP)
## Motyw Stalkera (MUSIC_PLAN.md E1): dwie pętle na siatce stemów, startują razem z nimi; głośność z `music_set_motif`.
const MOTIF_KEYS := ["mus_stalker_far", "mus_stalker_near"]
const MOTIF_FADE_IN := 3.0
const MOTIF_FADE_OUT := 6.0
## Stan życia lokalnego gracza (E1): 0 zdrowy, 1 ostatnie serce, 2 leży. Muzyka ciszej i „przez ścianę”, a pod nią serce.
const HEALTH_DB := [0.0, -7.0, -12.0]
const HEALTH_LP_HZ := [20500.0, 1500.0, 650.0]
const HEALTH_HEART_DB := [-80.0, -17.0, -12.0]
const STALKER_DUCK_DB := -5.0                     ## muzyka ustępuje głosowi Stalkera (jednorazowe dźwięki na szynie Stalker, nie pętle)
const NO_DROP := -2                    # _drop_to: brak zaplanowanego zejścia (-1 to zejście do ciszy)
var _drop_to := NO_DROP
var _drop_at := -1.0
var _motif: Array[AudioStreamPlayer] = []
var _motif_x: Array[float] = [0.0, 0.0]          # postęp przejścia 0..1 (krzywa `_fade_gain`)
var _motif_target: Array[float] = [0.0, 0.0]     # docelowy postęp = głośność z odległości
var _health := 0
var _health_db := 0.0                             # wygładzone
var _music_lp_hz := 20500.0                       # wygładzone; łączy się z głuchotą (min)
var _music_lp: AudioEffectLowPassFilter
## Segmenty (MUSIC_PLAN.md E2): wszystkie warianty warstwy grają razem na wspólnej siatce, słychać jeden. Cała muzyka
## zmienia sekcję (wariant każdej warstwy) NARAZ i tylko na początku pętli; przenikanie kończy się dokładnie na granicy.
## Po odsłuchu 1.7.580: warstwy zmieniane osobno co 1–3 frazy brzmiały chaotycznie, jak zmiany tempa.
const SEG_XF := 0.6                               ## s przenikania sekcji tuż przed początkiem pętli (ok. jeden beat)
const SEG_RUN := Vector2i(2, 4)                   ## ile pętli (po 20 s) gra sekcja, zanim przyjdzie następna
const CADENCE_CUT := 0.7                          ## s wyciszenia warstwy pod uderzeniem kadencji (zamiast 5–6 s)
const CADENCE_MIN_GAIN := 0.6                     ## kadencja tylko, gdy kończąca się warstwa była naprawdę słychać
const CADENCE_SKIP_BARS := [3, 7]                 ## takty na A-dur (dominanta): tonika D tam nie siada, kadencja czeka takt dłużej
const PALETTE_CHECK := 1.0                        ## s między sprawdzeniami mapy (paleta zmienia się dopiero w ciszy)
var _seg: Array = []                              # per stem: Array[AudioStreamPlayer], [0] = _music[i]
var _seg_n: Array[int] = []                       # per stem: ile wariantów ma paleta
var _seg_cur: Array[int] = []                     # per stem: słyszany wariant
var _seg_prev: Array[int] = []                    # per stem: wariant, z którego trwa przenikanie (-1 brak)
var _sec := 0                                     # grająca sekcja (wariant warstwy = _sec % liczba wariantów)
var _sec_left := 2                                # pętli do zmiany sekcji
var _seg_xf_end := -1.0                           # zegar: koniec przenikania (= granica frazy)
var _seg_next_ok := 0.0                           # zegar: od kiedy wolno zaplanować kolejną granicę
var _seg_rng := RandomNumberGenerator.new()
var _palette := "default"
var _palette_want := "default"
var _palette_t := 0.0
var _cad: AudioStreamPlayer
var _cad_key := ""                                # kadencja w drodze ("" brak)
var _cad_land := -1.0                             # zegar: początek taktu, w który trafia uderzenie
var _cad_started := false
var _stem_fast: Array[bool] = []                  # per stem: wycinany pod kadencją (CADENCE_CUT)
var _duck_db := 0.0
var _duck_hold := 0.0

# --- miks / środowisko
var _deaf := 0.0
var _deaf_hold := 0.0
var _rev_fx: AudioEffectReverb
## Pogłos w wykopie pod skałą (`_dig_acoustics`): [ziemia, skała] wg dig_materials.gd `echo`
const DIG_WET := Vector2(0.10, 0.30)
const DIG_DAMP := Vector2(0.88, 0.30)
const DIG_ROOM_SOFT := 0.30               ## ziemia: mały pokój — ogon zaraz ginie
const DIG_ROOM_HARD := 0.62               ## skała: dłuższe echo chodnika
const DIG_ROOM_TIGHT := 0.22              ## ciasny tunel: ogon jeszcze krótszy (gęste, bliskie odbicia)
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
		_stem_fast.append(false)
		_seg.append([m])
		_seg_n.append(1)
		_seg_cur.append(0)
		_seg_prev.append(-1)
	_cad = AudioStreamPlayer.new()
	_cad.bus = BUS_MUSIC
	add_child(_cad)
	_seg_rng.randomize()
	for _k in MOTIF_KEYS:
		var mm := AudioStreamPlayer.new()
		mm.bus = BUS_MUSIC
		mm.volume_db = -80.0
		add_child(mm)
		_motif.append(mm)

	_bind_effects()
	_verify_manifest()
	# Alt+F4 / zamknięcie okna musi przejść przez ten sam cykl co przycisk Quit.
	get_tree().set_auto_accept_quit(false)
	get_tree().root.close_requested.connect(quit_game)
	if DisplayServer.get_name() != "headless":
		_warm_all()


func _exit_tree() -> void:
	_shutdown()


## Publiczne wyłączenie dźwięku — np. powrót do lobby albo restart sesji.
func shutdown() -> void:
	_shutdown()


## AudioServer musi otrzymać stop przed końcem ostatniej klatki, a nie dopiero
## podczas niszczenia SceneTree. Pierwsze żądanie zachowuje swój kod wyjścia.
func quit_game(exit_code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	quitting.emit()
	var trace := "--shutdowntrace" in OS.get_cmdline_user_args()
	var started := Time.get_ticks_usec()
	if trace:
		print("[AUDIO-SHUTDOWN] start loops=", _loops.size(), " positional=", _pos_loops.size(), " music=", _music_started, " driver=", AudioServer.get_driver_name())
	_shutdown()
	get_tree().paused = true # wyjście jest ostateczne; symulacja nie biegnie podczas opróżniania miksu
	# Wątek miksu zwalnia playback asynchronicznie. Same referencje stream=null
	# nie wystarczają przy wyjściu w tej samej klatce (także driver Dummy).
	# SceneTreeTimer korzysta z kroku silnika; szybki headless może odmierzyć
	# 100 ms symulacji w kilka ms. Mikser potrzebuje czasu zegara monotonicznego.
	Engine.max_fps = 60
	var release_at := Time.get_ticks_usec() + SHUTDOWN_DRAIN_USEC
	while Time.get_ticks_usec() < release_at:
		await get_tree().process_frame
	if trace:
		print("[AUDIO-SHUTDOWN] finish elapsed_ms=", (Time.get_ticks_usec() - started) / 1000.0, " since_mix=", AudioServer.get_time_since_last_mix(), " cache=", _cache.size())
	get_tree().quit.call_deferred(exit_code)


## Zamykanie audio: stop + zwolnienie referencji do strumieni, potem free()
## pętli. _exit_tree jest zabezpieczeniem, zwykłe wyjście korzysta z quit_game.
func _shutdown() -> void:
	_enabled = false
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
	for players in _seg:
		for n in players:
			n.stop()
			n.stream = null
	for n in _motif:
		n.stop()
		n.stream = null
	if _cad != null:
		_cad.stop()
		_cad.stream = null
	_reset_segments()
	for i in _stem_target.size():               # po ponownym włączeniu stemy nie wracają do warstw sprzed wyłączenia
		_stem_target[i] = 0.0
		_stem_gain[i] = 0.0
	_motif_x = [0.0, 0.0]
	_motif_target = [0.0, 0.0]
	_health = 0
	_health_db = 0.0
	_music_lp_hz = 20500.0
	_music_layer = -1
	_music_started = false
	_drop_to = NO_DROP
	for wp in _warm_paths:                 # wczytywanie w tle (`_warm_all`) odbieramy przed wyjściem — wątek nie trzyma zasobu przy zamykaniu
		ResourceLoader.load_threaded_get(wp)
	_warm.clear()
	_warm_paths.clear()
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
	var res: Resource = null
	if _warm.has(key):
		var wp: String = _warm[key]
		_warm.erase(key)
		if _warm_paths.has(wp):
			_warm_paths.erase(wp)
			res = ResourceLoader.load_threaded_get(wp)       # czeka na wątek, jeśli jeszcze wczytuje (zwykle już gotowe)
	if res == null:
		res = load(_path(key))
	var s := res as AudioStream
	if s == null:
		_report_missing(key, "nie załadował się jako AudioStream")
		return null
	if Manifest.LOOPS.has(key):
		if s is AudioStreamWAV:
			_enable_loop(s)
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true      # muzyka i ambient: Ogg Vorbis, pętla na całej długości co do próbki
	_cache[key] = s
	return s


## Cały manifest wczytywany w tle zaraz po starcie (efekty WAV to ok. 30 MB): pierwsze zagranie dźwięku czytało plik w wątku głównym
## i zacinało klatkę o 46–54 ms (pomiar --perf 2026-10-23: amb_thud, tape_stop, revive, foley_gear w środku misji). Gotowe pliki odbiera
## `_poll_warm` w `_process`, a `stream()` klucza jeszcze w drodze czeka na jego wątek. W trybie headless (testy) bez tego.
func _warm_all() -> void:
	for key in Manifest.PATHS:
		var k := String(key)
		if _cache.has(k):
			continue
		var p := _path(k)
		if not _warm_paths.has(p):
			if not ResourceLoader.exists(p) or ResourceLoader.load_threaded_request(p) != OK:
				continue
			_warm_paths[p] = true
		_warm[k] = p

## Odbiera do 8 gotowych dźwięków z wczytywania w tle na klatkę.
func _poll_warm() -> void:
	var n := 0
	for k in _warm.keys():
		var p: String = _warm[k]
		if not _warm_paths.has(p):
			stream(String(k))                                # ta sama ścieżka odebrana pod innym kluczem: już w cache'u zasobów
			continue
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			stream(String(k))
			n += 1
			if n >= 8:
				return
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_warm.erase(k)
			_warm_paths.erase(p)

## Wczytuje z góry warianty rodziny (`base_1` … `base_N`) do cache'u — żeby pierwsze zagranie w środku walki nie zacinało klatki ładowaniem pliku
## (zacięcie w złym momencie potrafi przepuścić pocisk przez cel; wróg warmuje swoje głosy w `_ready`).
func warm_family(base: String, count: int) -> void:
	for i in count:
		var key := "%s_%d" % [base, i + 1]
		if Manifest.PATHS.has(key):
			stream(key)


## Plik, który faktycznie gra pod kluczem. Wersje z nagrań z bibliotek nie mogą leżeć w publicznym repo (licencja,
## AUDIO_PLAN.md §6), więc lokalny bake zapisuje je do res://audio_licensed/ pod tą samą ścieżką względną: jeśli plik
## tam jest, wygrywa z syntetycznym z res://audio/. Dev: `--synthaudio` wymusza samą syntezę (porównanie w grze).
## Który zestaw dźwięku gra na tej maszynie: "recordings" (jest choć jeden plik z nagrań) albo "synth". Dla dziennika sesji —
## build bez `audio_licensed/` brzmi inaczej i wyników playtestu nie wolno wtedy porównywać.
func source_set() -> String:
	if _use_licensed:
		for key in Manifest.PATHS:
			if _path(String(key)).begins_with(LICENSED_ROOT):
				return "recordings"
	return "synth"

func _path(key: String) -> String:
	var p: String = Manifest.PATHS[key]
	if _use_licensed:
		var alt := LICENSED_ROOT + p.trim_prefix(PUBLIC_ROOT)
		if ResourceLoader.exists(alt):
			return alt
	return p


func _enable_loop(s: AudioStreamWAV) -> void:
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	# Długość ze strumienia, nie z rozmiaru danych: po imporcie z kompresją (QOA) bajty nie są klatkami
	# i pętla urywała się po ok. 1/5 długości (tools/test_audio_loops.gd).
	s.loop_end = int(round(s.get_length() * s.mix_rate))


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
	var licensed := 0
	for key in Manifest.PATHS:
		if not ResourceLoader.exists(Manifest.PATHS[key]):
			missing.append(key)
		elif _path(key) != Manifest.PATHS[key]:
			licensed += 1
	if missing.is_empty():
		print("[AUDIO] manifest OK: %d ścieżek%s" % [Manifest.PATHS.size(), (", z nagrań: %d" % licensed) if licensed > 0 else ""])
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
	_weather_signal(key)
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
	var place := _placement(pos)
	var far := _far(key)
	if not far.is_empty():
		var t := clampf(((place[0] as Vector2).distance_to(_listener_pos) - FAR_START) / (FAR_FULL - FAR_START), 0.0, 1.0)
		if t > 0.0:
			_emit_at(pick(far[0], far[1]), place, bus, vol_db + linear_to_db(sin(t * PI * 0.5)), pitch)
			if t > 0.98:
				_caption(key, pos)
				return
			vol_db += linear_to_db(cos(t * PI * 0.5))
	_emit_at(key, place, bus, vol_db, pitch)
	_caption(key, pos)
	if key.begins_with("explosion"):
		_on_explosion(pos)


## Daleka rodzina dla klucza bliskiego: [baza, liczba wariantów] albo [] — z manifestu, bez osobnej tabeli.
func _far(key: String) -> Array:
	if not _use_far:
		return []
	var fam := _family(key)
	if _far_cache.has(fam):
		return _far_cache[fam]
	var base := ""
	if fam == "explosion":
		base = "explosion_far"
	elif fam.ends_with("_shot"):
		base = fam.trim_suffix("_shot") + "_far"
	var n := 0
	while base != "" and Manifest.PATHS.has("%s_%d" % [base, n + 1]):
		n += 1
	var out: Array = [base, n] if n > 0 else []
	_far_cache[fam] = out
	return out


## Jeden głos pozycyjny w miejscu wyznaczonym przez _placement(): [pozycja, stopień zasłonięcia].
func _emit_at(key: String, place: Array, bus: String, vol_db: float, pitch: float) -> void:
	var s := stream(key)
	if s == null:
		return
	var p := _acquire(_pos_pool, key) as AudioStreamPlayer2D
	if p == null:
		return
	p.stream = s
	p.position = place[0]
	p.max_distance = MAX_DISTANCE
	p.attenuation = 1.1
	p.panning_strength = 0.0 if Settings.mono_audio else 1.0       # ustawienie „Mono audio": dźwięk pozycyjny bez panoramy
	p.bus = _tier_bus(bus, int(place[1]))
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()
	_weather_signal(key)


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
	if not _enabled:
		return
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
	if not _enabled:
		return
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
		for n in _seg[i]:
			n.stop()
		_stem_gain[i] = 0.0
		_stem_target[i] = 0.0
	_cad.stop()
	_reset_segments()
	for i in _motif.size():
		_motif[i].stop()
		_motif_x[i] = 0.0
		_motif_target[i] = 0.0
	_health = 0
	_health_db = 0.0
	_music_lp_hz = 20500.0
	_music_layer = -1
	_music_started = false
	_drop_to = NO_DROP
	_drop_at = -1.0
	_deaf = 0.0
	_duck_db = 0.0
	_wduck_db = 0.0
	_wduck_hold = 0.0


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
				if not Sight.first_hit(space, q).is_empty():             # przez dziurę w deskach słychać jak przez stłuczone okno
					tier += 1
	_occl[cell] = tier
	return tier


## Zgodność wsteczna: czy źródło jest w ogóle zasłonięte.
func is_occluded(from: Vector2) -> bool:
	return occlusion_tier(from) >= 2


## Gdzie i przez jaki filtr zagrać źródło z `pos`: [położenie odtwarzacza: Vector2, próg okluzji: int].
## Źródło widoczne albo lekko zasłonięte gra ze swojego miejsca. Zasłonięte (próg ≥ 2) dostaje drogę po mapie:
## jeśli „dookoła” wychodzi głośniej niż „przez ścianę”, gra z pozornego położenia przy ostatnim rogu drogi.
## Napisy dźwięków i ogłuszenie liczą się zawsze z prawdziwego `pos`.
func _placement(pos: Vector2) -> Array:
	var tier := occlusion_tier(pos)
	if tier < 2 or not _use_routes:
		return [pos, tier]
	var r := _route(pos)
	if r.is_empty():
		return [pos, tier]
	var around_db := _distance_db(float(r[1])) + ROUTE_LOSS_DB
	var through_db := _distance_db(pos.distance_to(_listener_pos)) + float(WALL_LOSS_DB[clampi(tier, 0, 3)])
	if around_db < through_db:
		return [pos, tier]
	return [r[0], ROUTE_TIER]


## Tłumienie odległościowe odtwarzacza pozycyjnego w dB (ten sam wzór co AudioStreamPlayer2D: (1 − d/max)^attenuation).
func _distance_db(dist: float) -> float:
	return linear_to_db(pow(maxf(1.0 - dist / MAX_DISTANCE, 0.0001), 1.1))


## Droga dźwięku z `pos` do słuchacza: [pozorne położenie, długość drogi px] albo [] (brak poziomu, brak drogi,
## droga dłuższa niż zasięg słyszalności). Pamięć podręczna per komórka źródła; czyszczona, gdy słuchacz zmieni kafel
## albo zmieni się mapa (zawał, rozbita ściana).
func _route(pos: Vector2) -> Array:
	var lvl := get_tree().get_first_node_in_group("level") as Node2D
	if lvl == null or lvl.get("sound_grid") == null:
		return []
	var grid: RefCounted = lvl.sound_grid
	var ear_local := lvl.to_local(_listener_pos)
	var ear: Vector2i = grid.cell(ear_local)
	if ear != _routes_ear or int(grid.version) != _routes_ver:
		_routes.clear()
		_routes_ear = ear
		_routes_ver = int(grid.version)
	var src_local := lvl.to_local(pos)
	var key: Vector2i = grid.cell(src_local)
	if _routes.has(key):
		return _routes[key]
	var out: Array = []
	var r: Array = grid.route(src_local, ear_local)
	if not r.is_empty() and float(r[0]) < MAX_DISTANCE * 0.98:
		var dir := lvl.to_global(r[1]) - _listener_pos
		if dir.length() > 1.0:
			out = [_listener_pos + dir.normalized() * float(r[0]), float(r[0])]
	_routes[key] = out
	return out


## Co klatkę: pętle pozycyjne dojeżdżają płynnie do pozornego położenia (bez skoku panoramy, gdy droga się zmienia).
func _update_loop_routes(delta: float) -> void:
	var k := 1.0 - exp(-delta * ROUTE_SMOOTH)
	for key in _pos_loops:
		var q = _pos_loops[key]
		if not is_instance_valid(q):
			continue
		var host := q.get_parent() as Node2D
		if host == null:
			continue
		var want: Vector2 = q.get_meta("route_off", Vector2.ZERO)
		var off: Vector2 = (q.get_meta("route_cur", Vector2.ZERO) as Vector2).lerp(want, k)
		if off.length_squared() < 0.25 and want == Vector2.ZERO:
			off = Vector2.ZERO
		q.set_meta("route_cur", off)
		q.global_position = host.global_position + off


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
		var host := q.get_parent() as Node2D
		if host == null:
			continue
		var place := _placement(host.global_position)
		q.set_meta("route_off", (place[0] as Vector2) - host.global_position)    # dokąd ma dojechać odtwarzacz (0 = na źródle)
		var tier := int(place[1])
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
				if b == BUS_MUSIC:
					_music_lp = fx
	if _rev_fx == null or _lp_fx.size() < 3:
		push_warning("[AUDIO] bus layout bez oczekiwanych efektów (Reverb na SFX, LP na Music/Ambience/SFX)")
	var wb := AudioServer.get_bus_index(BUS_WEATHER)
	if wb >= 0:
		for i in AudioServer.get_bus_effect_count(wb):
			var fx := AudioServer.get_bus_effect(wb, i)
			if fx is AudioEffectAmplify:
				_wduck_fx = fx
			elif fx is AudioEffectLowPassFilter:
				_wunder_fx = fx
	var tb := AudioServer.get_bus_index(BUS_THUNDER)
	if tb >= 0 and AudioServer.get_bus_effect_count(tb) > 0:
		_thunder_fx = AudioServer.get_bus_effect(tb, 0) as AudioEffectLowPassFilter
	if _wduck_fx == null or _wunder_fx == null or _thunder_fx == null:
		push_warning("[AUDIO] bus layout bez szyn pogody (Weather: Amplify + LP, Thunder: LP)")


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
	var dig_hits := 0
	var echo := 0.0
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
			var z = (r["collider"] as Node).get_parent() if r["collider"] is Node else null
			if z != null and z.is_in_group("dig_zones"):
				dig_hits += 1
				echo += z.echo_at(r["position"], Vector2.from_angle(a))
	var enclosure := float(hits) / float(n)
	var mean_d := dsum / float(n) / reach          # 0 ciasno .. 1 otwarcie
	_rev_wet_t = lerpf(0.04, 0.26, enclosure)
	_rev_room_t = lerpf(0.30, 0.82, clampf(enclosure * (1.15 - 0.6 * mean_d), 0.0, 1.0))
	_rev_damp_t = lerpf(0.70, 0.32, enclosure)
	_dig_acoustics(dig_hits, echo, mean_d)


## Kopanie P2c: słuchawka w wykopie strefy wydobycia pod skałą (level.gd `dig_cover_at`). Ciasny tunel to nie hala: krótszy ogon
## (pokój tym mniejszy, im bliżej ścian), a materiał ścian (dig_materials.gd `echo`) decyduje o barwie — ziemia pochłania (głucho,
## prawie bez pogłosu), skała odbija (jaśniej i więcej echa). Ściany strefy z wachlarza promieni ważą resztę ścian mapy po równo.
func _dig_acoustics(dig_hits: int, echo: float, mean_d: float) -> void:
	if dig_hits == 0:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.has_method("dig_cover_at") or lvl.dig_cover_at(_listener_pos) == null:
		return
	var e := echo / float(dig_hits)
	var tight := clampf(1.0 - mean_d * 2.5, 0.0, 1.0)            # 1 — ściany tuż przy słuchawce (tunel na wzrost postaci)
	_rev_wet_t = lerpf(DIG_WET.x, DIG_WET.y, e)
	_rev_room_t = lerpf(lerpf(DIG_ROOM_SOFT, DIG_ROOM_HARD, e), DIG_ROOM_TIGHT, tight * (1.0 - 0.5 * e))
	_rev_damp_t = lerpf(DIG_DAMP.x, DIG_DAMP.y, e)


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


## Ucieczka o włos przed Stalkerem (FUN_PLAN.md P0.1): świat i muzyka na chwilę cichną, zostaje puls ostrzegawczy — „czas zwalnia”.
func on_close_call() -> void:
	deafen(0.4, 0.5)
	duck_music(-9.0, 1.2)
	play("warn_pulse", BUS_UI, -7.0, 0.8)


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
	var k := 1.0 - exp(-delta / 0.8)                   # stan życia przechodzi w ~1 s
	_health_db += (float(HEALTH_DB[_health]) - _health_db) * k
	_music_lp_hz = exp(lerpf(log(_music_lp_hz), log(float(HEALTH_LP_HZ[_health])), k))
	for fx in _lp_fx:
		fx.cutoff_hz = minf(cutoff, _music_lp_hz) if fx == _music_lp else cutoff


# ---------------------------------------------------------------- muzyka

## layer: -1 cisza (żaden stem), 0 dron (oddech), 1 napięcie, 2 walka, 3 pościg — STEMY NAKŁADAJĄ SIĘ (0..layer grają).
## Warstwę wybiera `MusicDirector` (MUSIC_PLAN.md E0); stemy ruszają dopiero przy pierwszej warstwie ≥ 0, potem grają
## dalej po cichu (-80 dB), żeby wejście kolejnej warstwy trzymało rytm.
## Wejście stemu kwantyzowane do beatu; zejście w dół opóźnione (hold), żeby muzyka
## nie opadała w sekundę po ostatnim strzale.
func music_set_layer(layer: int) -> void:
	if not _enabled:
		return
	var top := Manifest.MUSIC_STEMS.size() - 1
	layer = clampi(layer, -1, top)
	if layer < 0 and not _music_started:
		return                                # cisza przed pierwszym zagrożeniem: stemy nawet nie ruszają (menu, początek misji)
	if not _music_start():
		return
	if layer == _music_layer and _drop_to == NO_DROP:
		return
	if layer >= _music_layer:
		_drop_to = NO_DROP
		_drop_at = -1.0
		_cad_key = ""                                        # walka wróciła: zejście odwołane (zagrana kadencja wybrzmiewa sama)
		_cad_land = -1.0
		_cad_started = false
		for i in range(layer + 1):
			if _stem_target[i] < 1.0:
				_stem_target[i] = 1.0
				_stem_enter_at[i] = _clock + _quant_delay(i)
		_music_layer = layer
	else:
		var hold: float = MUSIC_DROP_HOLD[clampi(_music_layer, 0, MUSIC_DROP_HOLD.size() - 1)]
		_drop_to = layer
		_drop_at = _clock + hold


func _music_start() -> bool:
	if _music_started:
		return true
	var keys := _palette_keys(_palette_want)
	if keys.is_empty():
		return false
	_palette = _palette_want
	_start_players(keys)
	_music_started = true
	_music_layer = -1                                    # warstwy ustawia music_set_layer (start mógł przyjść od motywu)
	return true


## Warianty warstw z palety (E2) — tylko te, które mają plik; warstwa bez żadnego wariantu wraca do stemu bazowego.
## Pusta tablica = muzyki nie da się uruchomić.
func _palette_keys(pal: String) -> Array:
	var segs: Dictionary = Manifest.MUSIC_SEGMENTS
	var layers: Array = segs.get(pal, segs.get("default", []))
	var out: Array = []
	for i in Manifest.MUSIC_STEMS.size():
		var ok: Array = []
		for k in (layers[i] if i < layers.size() else []):
			if Manifest.PATHS.has(k) and stream(k) != null:
				ok.append(k)
		if ok.is_empty() and stream(Manifest.MUSIC_STEMS[i]) != null:
			ok.append(Manifest.MUSIC_STEMS[i])
		if ok.is_empty():
			return []
		out.append(ok)
	return out


## Paleta dla mapy: najpierw cała nazwa („z1_b1”), potem strefa („z1”), na końcu „default”.
static func palette_for(map_id: String) -> String:
	var segs: Dictionary = Manifest.MUSIC_SEGMENTS
	if segs.has(map_id):
		return map_id
	var zone := map_id.get_slice("_", 0)
	return zone if segs.has(zone) else "default"


## Start wszystkich wariantów wszystkich warstw i motywu w TEJ SAMEJ chwili miksu (lock = wątek audio czeka),
## inaczej któryś mógłby ruszyć bufor później → przesunięcie fazy rytmu.
func _start_players(keys: Array) -> void:
	for i in _seg.size():
		while _seg[i].size() < keys[i].size():
			var p := AudioStreamPlayer.new()
			p.bus = BUS_MUSIC
			p.volume_db = -80.0
			add_child(p)
			_seg[i].append(p)
	_reset_segments()
	AudioServer.lock()
	for i in _seg.size():
		_seg_n[i] = keys[i].size()
		for v in _seg[i].size():
			var p: AudioStreamPlayer = _seg[i][v]
			p.stop()
			p.volume_db = -80.0
			p.stream = stream(keys[i][v]) if v < keys[i].size() else null
			if p.stream != null:
				p.play()
	for i in _motif.size():                              # motyw na tej samej siatce: start w tej samej chwili miksu
		_motif[i].stream = stream(MOTIF_KEYS[i]) if Manifest.PATHS.has(MOTIF_KEYS[i]) else null
		_motif[i].volume_db = -80.0
		if _motif[i].stream != null:
			_motif[i].play()
	AudioServer.unlock()


func _reset_segments() -> void:
	for i in _seg_cur.size():
		_seg_cur[i] = 0
		_seg_prev[i] = -1
		_stem_fast[i] = false
	_sec = 0
	_sec_left = _seg_rng.randi_range(SEG_RUN.x, SEG_RUN.y)
	_seg_xf_end = -1.0
	_seg_next_ok = 0.0
	_cad_key = ""
	_cad_land = -1.0
	_cad_started = false


## Pozycja w pętli (s) wg pierwszego stemu — wszystkie warianty i motyw grają na tej samej siatce.
func _music_pos() -> float:
	if not _music_started or not _music[0].playing:
		return 0.0
	return _music[0].get_playback_position() + AudioServer.get_time_since_last_mix()


func _bar_len() -> float:
	return 4.0 * 60.0 / float(Manifest.MUSIC_BPM)


## Czas do następnej siatki rytmicznej danego stemu (s). 0 = natychmiast.
func _quant_delay(stem: int) -> float:
	if not _music_started or not _music[0].playing:
		return 0.0
	var beat := 60.0 / float(Manifest.MUSIC_BPM)
	var grid: float = beat * [1.0, 1.0, 0.5, 0.25][clampi(stem, 0, 3)]
	var d := grid - fmod(_music_pos(), grid)
	return 0.0 if d > grid - 0.02 else d


## Ile sekund do taktu, w który trafi kadencja: następny początek taktu, ale nie na dominantę (CADENCE_SKIP_BARS)
## i nie bliżej niż przedbieg pliku (inaczej uderzenie spóźniłoby się o ułamek).
func _cadence_wait(pos: float) -> float:
	var bar := _bar_len()
	var bars := int(Manifest.MUSIC_BEATS / 4)
	var cur := int(floor(pos / bar)) % bars
	var wait := bar - fmod(pos, bar)
	var nxt := (cur + 1) % bars
	if wait < float(Manifest.MUSIC_CADENCE_PRE) + 0.03:
		wait += bar
		nxt = (nxt + 1) % bars
	while nxt in CADENCE_SKIP_BARS:
		wait += bar
		nxt = (nxt + 1) % bars
	return wait


## Kadencja przy zejściu z `from` do `to`: najwyższa gasnąca warstwa, która ma kadencję i była słychać.
func _cadence_key(from: int, to: int) -> String:
	var cads: Array = Manifest.MUSIC_CADENCES
	for i in range(mini(from, _stem_gain.size() - 1), to, -1):
		if i < cads.size() and String(cads[i]) != "" and _stem_gain[i] >= CADENCE_MIN_GAIN and Manifest.PATHS.has(cads[i]):
			return cads[i]
	return ""


## Sekcje (E2): tuż przed początkiem pętli, gdy skończył się przydział pętli, cała muzyka przechodzi na następną sekcję —
## każda warstwa na swój wariant tej sekcji. Przenikanie SEG_XF kończy się na samej granicy pętli.
func _update_segments(pos: float) -> void:
	if _seg_xf_end >= 0.0 and _clock >= _seg_xf_end:
		for i in _seg_prev.size():
			_seg_prev[i] = -1
		_seg_xf_end = -1.0
	var loop := float(Manifest.MUSIC_LOOP_SEC)
	var to_b := loop - fmod(pos, loop)
	if to_b > SEG_XF or _clock < _seg_next_ok:
		return
	_seg_next_ok = _clock + to_b + 1.0                   # jedna decyzja na granicę
	_sec_left -= 1
	if _sec_left > 0:
		return
	_sec_left = _seg_rng.randi_range(SEG_RUN.x, SEG_RUN.y)
	var n_max := 1
	for n in _seg_n:
		n_max = maxi(n_max, n)
	if n_max < 2:
		return
	var nxt := _seg_rng.randi_range(0, n_max - 2)
	if nxt >= _sec:
		nxt += 1                                         # zawsze inna niż grająca
	_sec = nxt
	_seg_xf_end = _clock + to_b
	for i in _seg_cur.size():
		var v := _sec % _seg_n[i]
		if v != _seg_cur[i]:
			_seg_prev[i] = _seg_cur[i]
			_seg_cur[i] = v


## Udział wariantu v warstwy i w jej głośności (0..1) — liniowe przenikanie, warianty mają tę samą głośność, harmonię i rytm.
func _seg_weight(i: int, v: int) -> float:
	var k := 1.0
	if _seg_prev[i] >= 0 and _seg_xf_end >= 0.0:
		k = clampf(1.0 - (_seg_xf_end - _clock) / SEG_XF, 0.0, 1.0)
	if v == _seg_cur[i]:
		return k
	if v == _seg_prev[i]:
		return 1.0 - k
	return 0.0


## Kadencja w drodze: uruchomiona z przedbiegiem pliku (play od MUSIC_CADENCE_PRE − czas do taktu), żeby uderzenie
## trafiło w początek taktu co do bufora miksu, a nie co do klatki.
func _update_cadence(pos: float) -> void:
	if _cad_key == "" or _cad_started:
		return
	var pre := float(Manifest.MUSIC_CADENCE_PRE)
	var est := _cad_land - _clock
	if est > pre:
		return
	var bar := _bar_len()
	var to_bar := bar - fmod(pos, bar)
	var lead := to_bar if absf(to_bar - est) < 0.2 else maxf(est, 0.0)   # pozycja audio dokładniejsza niż zegar klatek
	_cad.stream = stream(_cad_key)
	_cad.volume_db = _health_db
	if _cad.stream != null:
		_cad.play(clampf(pre - lead, 0.0, pre))
	_cad_started = true


## Paleta zmienia się z mapą (E2), ale stemy grają przez całą sesję — podmiana dopiero, gdy wszystko ucichło.
func _update_palette(delta: float) -> void:
	_palette_t -= delta
	if _palette_t > 0.0:
		return
	_palette_t = PALETTE_CHECK
	var lvl := get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	if lvl == null or lvl.get("map_id") == null:
		return
	_palette_want = palette_for(String(lvl.get("map_id")))
	if not _music_started or _palette_want == _palette:
		return
	if _stem_gain.any(func(g: float) -> bool: return g > 0.0) or _motif_x.any(func(x: float) -> bool: return x > 0.0):
		return
	var keys := _palette_keys(_palette_want)
	if keys.is_empty():
		return
	_palette = _palette_want
	_start_players(keys)


func _update_music(delta: float) -> void:
	_update_palette(delta)
	if not _music_started:
		return
	var pos := _music_pos()
	if _drop_to != NO_DROP and _clock >= _drop_at:
		if _cad_key == "":
			_cad_key = _cadence_key(_music_layer, _drop_to)
			if _cad_key != "":
				_cad_land = _clock + _cadence_wait(pos)
				_cad_started = false
		if _cad_key == "" or _clock >= _cad_land:
			var cads: Array = Manifest.MUSIC_CADENCES
			for i in range(_drop_to + 1, _stem_target.size()):
				_stem_target[i] = 0.0
				_stem_fast[i] = _cad_key != "" and i < cads.size() and String(cads[i]) != ""
			_music_layer = _drop_to
			_drop_to = NO_DROP
			_drop_at = -1.0
			_cad_key = ""
			_cad_land = -1.0
	_update_cadence(pos)
	_update_segments(pos)
	if _duck_hold > 0.0:
		_duck_hold -= delta
	else:
		_duck_db = minf(0.0, _duck_db + delta * 6.0)    # ~1 s powrotu z -6 dB
	var duck := db_to_linear(_duck_db)
	var life := db_to_linear(_health_db)
	for i in _music.size():
		var blend: float = Manifest.MUSIC_BLEND[i]
		if _stem_target[i] > 0.5:
			_stem_fast[i] = false
			if _clock >= _stem_enter_at[i]:
				_stem_gain[i] = minf(1.0, _stem_gain[i] + delta / maxf(0.05, blend))
		else:
			var out_s: float = CADENCE_CUT if _stem_fast[i] else float(MUSIC_FADE_OUT[mini(i, MUSIC_FADE_OUT.size() - 1)])
			_stem_gain[i] = maxf(0.0, _stem_gain[i] - delta / out_s)
		var g := _fade_gain(_stem_gain[i]) * duck * life
		for v in _seg_n[i]:
			var gv := g * _seg_weight(i, v)
			_seg[i][v].volume_db = -80.0 if gv <= 0.0001 else linear_to_db(gv)
	for i in _motif.size():
		var tgt: float = _motif_target[i]
		if _motif_x[i] < tgt:
			_motif_x[i] = minf(tgt, _motif_x[i] + delta / MOTIF_FADE_IN)
		else:
			_motif_x[i] = maxf(tgt, _motif_x[i] - delta / MOTIF_FADE_OUT)
		var mg := _fade_gain(_motif_x[i]) * duck * life
		_motif[i].volume_db = -80.0 if mg <= 0.0001 else linear_to_db(mg)


## Motyw Stalkera (E1): docelowa głośność pętli dalekiej i bliskiej, 0..1 na krzywej `_fade_gain` (0,75 ≈ −10 dB).
## Stemy i motyw startują razem (wspólna siatka); sam motyw nie włącza warstw.
func music_set_motif(far: float, near: float) -> void:
	if not _enabled or _motif.is_empty():
		return
	if far <= 0.0 and near <= 0.0 and not _music_started:
		return
	if not _music_start():
		return
	_motif_target[0] = clampf(far, 0.0, 1.0)
	_motif_target[1] = clampf(near, 0.0, 1.0)


## Stan życia lokalnego gracza (E1): 0 zdrowy, 1 ostatnie serce, 2 leży — muzyka ciszej, za filtrem, a pod nią serce.
func music_set_health(state: int) -> void:
	state = clampi(state, 0, HEALTH_DB.size() - 1)
	if state == _health:
		return
	_health = state
	if not _enabled:
		return
	if state == 0:
		stop_loop("heart_slow_loop")
	else:
		stop_loop("heart_slow_loop")
		start_loop("heart_slow_loop", BUS_PLAYER, float(HEALTH_HEART_DB[state]))


## Jednorazowy sygnał zagrożenia (E1: `cue_elite`, `cue_horde`) — gra na muzyce, a ona na chwilę ustępuje.
func music_cue(key: String) -> void:
	if not _enabled or not Manifest.PATHS.has(key):
		return
	play(key, BUS_MUSIC, -2.0)
	duck_music(-6.0, 2.5)


## Muzyka ustępuje głosowi Stalkera: wołany co klatkę, patrzy tylko na jednorazowe głosy (pule), nie na pętle (szept).
func _duck_under_stalker() -> void:
	for q in _pos_pool:
		if q.playing and q.bus == BUS_STALKER:
			duck_music(STALKER_DUCK_DB, 0.4)
			return
	for q in _pool:
		if q.playing and q.bus == BUS_STALKER:
			duck_music(STALKER_DUCK_DB, 0.4)
			return


## Postęp przejścia 0..1 → amplituda: równo w decybelach od MUSIC_FADE_FLOOR_DB do 0 dB. Liniowa amplituda (do 1.7.577)
## wskakiwała w słyszalne poziomy w pierwszych procentach wejścia i urywała się na końcu wyciszenia.
static func _fade_gain(x: float) -> float:
	if x <= 0.0:
		return 0.0
	return db_to_linear(MUSIC_FADE_FLOOR_DB * (1.0 - minf(x, 1.0)))


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
	if not _loops.has("amb_forest"):
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
		total += _emitter_weight(e)
	if cand.is_empty():
		return
	var roll := randf() * total
	for e in cand:
		roll -= _emitter_weight(e)
		if roll <= 0.0:
			var pos := _listener_pos + Vector2.from_angle(randf() * TAU) * randf_range(float(e[2]), float(e[3]))
			if String(e[0]) == "amb_gust":
				pos.x = _listener_pos.x + absf(pos.x - _listener_pos.x) * weather_wdir     # podmuch od strony wiatru
			play_variant_at(String(e[0]), int(e[1]), pos, BUS_AMB, float(e[4]), 1.0, 0.05)
			return


## Waga emitera ambientu: podmuch i skrzypienie × (siła wiatru / WIND_REF)² (0,1–3) — ok. ×0,12 w pogodną noc, ×3 w burzy.
func _emitter_weight(e: Array) -> float:
	var w := float(e[5])
	if String(e[0]) in WIND_EMITTERS:
		w *= clampf(pow(weather_wind / WIND_REF, 2.0), 0.1, 3.0)
	return w


# ---------------------------------------------------------------- miks pogody (WEATHER_PLAN.md W2–W4)

## Ważny dźwięk (priorytet głosu ≥ WEATHER_DUCK_PRIO) ścisza pogodę (zasada 5: sygnały przed pogodą).
func _weather_signal(key: String) -> void:
	if int(_voice(key)[0]) >= WEATHER_DUCK_PRIO:
		duck_weather(WEATHER_DUCK_DB, WEATHER_DUCK_HOLD)


## Ściszenie szyny pogody o `db` na `hold` s (potem ok. 0,8 s powrotu). Także z zewnątrz (podpowiedzi, radio).
func duck_weather(db: float, hold: float) -> void:
	_wduck_db = minf(_wduck_db, db)
	_wduck_hold = maxf(_wduck_hold, hold)


## Położenie słuchawki w świecie (dźwięk pogody stawia emitery względem niej).
func listener_pos() -> Vector2:
	return _listener_pos


## Bieżące ściszenie pogody [dB] (testy, dziennik).
func weather_duck_db() -> float:
	return _wduck_fx.volume_db if _wduck_fx != null else 0.0


## Pogoda pod ziemią: 0 — na powierzchni (bez filtra), 1 — głęboko (dolnoprzepustowy WEATHER_UNDER_HZ).
func set_weather_underground(amount: float) -> void:
	_wunder = clampf(amount, 0.0, 1.0)


## Filtr odległości grzmotu (szyna „Thunder”): odcięcie dla najświeższego grzmotu, dojeżdża płynnie.
func set_thunder_cutoff(hz: float) -> void:
	_thunder_hz = clampf(hz, 200.0, 20500.0)


func _update_weather_mix(delta: float) -> void:
	if _wduck_hold > 0.0:
		_wduck_hold -= delta
	else:
		_wduck_db = minf(0.0, _wduck_db + delta * 6.0)          # ok. 0,8 s powrotu z −5 dB
	if _wduck_fx != null:
		var cur := _wduck_fx.volume_db
		var k := 1.0 - exp(-delta * (40.0 if _wduck_db < cur else 8.0))   # szybkie wejście, łagodne wyjście
		_wduck_fx.volume_db = lerpf(cur, _wduck_db, k)
	if _wunder_fx != null:
		_wunder_fx.cutoff_hz = 20500.0 * pow(WEATHER_UNDER_HZ / 20500.0, _wunder)
	if _thunder_fx != null:
		var tk := 1.0 - exp(-delta * 4.0)
		_thunder_fx.cutoff_hz = exp(lerpf(log(_thunder_fx.cutoff_hz), log(_thunder_hz), tk))


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_clock += delta
	if not _warm.is_empty():
		_poll_warm()
	_listener_pos = _listener.global_position
	_occl.clear()                      # przeszkody zmieniają się dynamicznie
	_follow_listener()
	_loop_occl_timer -= delta
	if _loop_occl_timer <= 0.0:
		_loop_occl_timer = 0.2
		_update_loop_occlusion()
	_update_loop_routes(delta)
	_update_reverb(delta)
	_update_deafness(delta)
	_duck_under_stalker()
	_update_music(delta)
	_update_emitters(delta)
	_update_weather_mix(delta)


## Wyłącza cały dźwięk (np. przy starcie lobby, żeby nie grało na pustce).
func set_enabled(on: bool) -> void:
	_enabled = on and not _quitting
	if _enabled:
		return
	stop_all()
