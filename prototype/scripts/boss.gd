extends "res://scripts/boss_base.gd"
## Żyła — matka gniazd. Boss misji „Gniazdo" (GDD §7.1 Żyła: splot, rodzi
## Trzoski; §16.0 pkt 1: demo = misja w całości z bossem).
##
## Gniazda są jej odnóżami: dopóki choć jedno żyje, Żyła śpi i jest
## nietykalna. Zniszczenie ostatniego budzi ją; jej śmierć otwiera ekstrakcję.
##
## Walka (1.3.9 — wcześniej ~4 s z ziemi, bez użycia filarów gry):
##   RYTM       paszcza jest zamknięta (5% obrażeń); otwiera się na MAW_WINDOW
##              po każdym ataku — unik → okno → ostrzał (otwarta ~40% czasu;
##              symulacja 1.3.9: przy 1,3 s okna i 1,1 s przerwy była otwarta
##              ~2/3 czasu i walka trwała 11 s)
##   LATARKA    snop w paszczę W TRAKCIE ZAPOWIEDZI ataku oślepia ją: atak
##              przerwany, paszcza otwarta STUN_TIME (filar 4, kooperacja: jeden
##              świeci w dobrym momencie, drugi strzela). Poza zapowiedzią nie
##              działa — inaczej stale włączona latarka ogłuszała automatycznie
##   Q          Przesterowanie w pobliżu odciąga ją na DIVERT_TIME: pluje w miejsce
##              Q zamiast w graczy, nie smaga, nie zamiata (filar 2)
##   ATAKI      macka (blisko), zamach ogonem po ziemi (przeskocz albo stań na
##              kładce), plucie zarodnikami (dalej / wyżej) — każdy z zapowiedzią
##   DYSTANS    gdy nikt nie stoi w zasięgu żadnego ataku przez IDLE_FAR, plucie
##              sięga SPIT_RANGE_FAR (1.7.551: do 1.7.550 gracze stali poza 300 px
##              przez 41% walki, Żyła milczała, paszcza się nie otwierała, a walka
##              ciągnęła się ~170 s)
##   FAZY       66%: furia (szybciej); 33%: krzyk — Uwaga 100%, światła migoczą,
##              budzi się Stalker (kulminacja grozy przed ekstrakcją)
##   GRZBIET    pocisk z góry pod stromym kątem zawsze 5% (kampienie z półek)
##
## Symulacja TYLKO na serwerze; klienci dostają stan przez _sync i _event.

const Hurtbox := preload("res://scripts/hurtbox.gd")
const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Vfx := preload("res://scripts/vfx.gd")
const SessionLog := preload("res://scripts/session_log.gd")

enum Atk { NONE, LASH, SPIT, SWEEP }
## Ruch w hali (`VEIN_PLAN.md` §7, E2): wynurzona walczy w gardzieli, potem zanurza się i przechodzi pod podłogą do innej.
##   UP      wynurzona — seria ataków (3, w fazie 2+ 4) albo do FIGHT_MAX s, potem SINK; „ból” skraca serię
##   ROAR    ryk po wynurzeniu, paszcza otwarta (pełne obrażenia) — nagroda za ustawienie się przed wynurzeniem
##   SINK    zanurzanie, paszcza zamknięta (5%)
##   TRAVEL  pod podłogą (nietrafialna, znika z celów botów), garb sunie do następnej gardzieli
##   EMERGE  zapowiedź wynurzenia w gardzieli (pęknięcia, dudnienie); na końcu cios w stojących na podłodze w EMERGE_R
## Bez danych hali (`VEIN_ARENA`) Żyła stoi w miejscu (UP bez końca), jak do 1.7.552.
enum Move { UP, ROAR, SINK, TRAVEL, EMERGE }

const BASE_HP := 750.0
const HP_PER_EXTRA_HUMAN := 250.0
const CLOSED_MULT := 0.05         ## zamknięta paszcza / pancerny grzbiet
## Opinia testera 2026-10-29 (ok. 10 prób, WRATH-4 „praktycznie nic”, SPREAD-12 „od razu”): wybuch nad Żyłą liczył się jako
## pocisk „z góry” (kierunek od środka wybuchu w dół), a granat w locie ponad 1 s zwykle trafiał w już zamkniętą paszczę — 5%.
## Wybuch nie ma kierunku: nigdy nie jest „z góry”, a w zamkniętą paszczę wchodzi BLAST_CLOSED_MULT. Śrut z kolei trafiał
## olbrzymi cel każdą śruciną (5 × 7 co 0,26 s ≈ 135 DPS w okno paszczy) — na Żyle śrucina waży PELLET_MULT.
const BLAST_CLOSED_MULT := 0.35
const PELLET_MULT := 0.6
const ARMOR_DOWN := 0.45          ## pocisk „z góry": składowa pionowa kierunku > tego
const MAW_WINDOW := 1.0           ## paszcza otwarta po ataku
const STUN_TIME := 2.0            ## oślepienie latarką
const STUN_CD := 10.0
const ATK_GAP := 2.0              ## przerwa między atakami (faza 1)
const ATK_GAP_ENRAGED := 1.5

const LASH_RANGE_X := 64.0
const LASH_RANGE_Y := 70.0
const LASH_WINDUP := 0.75
const LASH_CD := 2.6
const SPIT_RANGE := 300.0
const SPIT_RANGE_FAR := 460.0     ## zasięg plucia, gdy nikt nie stoi w zwykłym zasięgu od IDLE_FAR s
const IDLE_FAR := 3.0
const SPIT_WINDUP := 0.8
const SPIT_CD := 3.4
const SPIT_GRAVITY := 520.0
const SPIT_HIT_R := 11.0
const SWEEP_RANGE := 170.0
const SWEEP_WINDUP := 0.9
const SWEEP_CD := 6.0
const SWEEP_SPEED := 260.0
const SWEEP_HALF := 10.0          ## grubość fali
const DIVERT_TIME := 5.0
const DIVERT_RANGE := 520.0
const ENRAGED_CD := 0.75          ## mnożnik cooldownów w furii

const BROOD_EVERY := 7.0
const BROOD_EVERY_ENRAGED := 5.0
const BROOD_MAX := 3              ## żyjącego potomstwa naraz (+1 za dodatkowego człowieka)
const N_SCREAM := 15.0            ## przebudzenie: krzyk słychać w całym tartaku
const N_STUN := 4.0
const N_SPLASH := 2.0
const N_DEATH := 20.0
const ROAR_T := 0.6
const FIGHT_MAX := 12.0           ## s wynurzenia bez względu na serię
const BURST := 3                  ## ataków na wynurzenie (faza 1)
const BURST_ENRAGED := 4
const SINK_T := 0.7
const EMERGE_T := 1.2             ## zapowiedź wynurzenia (× `boss_cd`: EASY ok. 1,5 s, HARD ok. 1,0 s)
const EMERGE_R := 40.0            ## promień ciosu wynurzenia na podłodze
const TRAVEL_SPEED := 160.0
const TRAVEL_MIN := 1.5           ## oddech drużyny między wynurzeniami (s)
const TRAVEL_MAX := 2.5
const SINK_VIS_RATE := 4.0        ## /s: wygładzanie zanurzenia w obrazie (wynurzenie ok. 0,25 s)
const SINK_DEPTH := 84.0          ## px, o ile model schodzi pod podłogę (więcej niż jego wysokość — znika cały)
const PAIN_FRAC := 0.12           ## ≥ tyle maks. HP w PAIN_WINDOW s = „ból”: zanurza się od razu
const PAIN_WINDOW := 5.0
const CAMP_R := 48.0              ## gracz, który stoi w tym promieniu ≥ CAMP_T s, „kampi” — gardziel najbliżej niego +2
const CAMP_T := 6.0
const DMG_WINDOW := 10.0          ## +1 gardzieli najbliżej tego, kto zadał najwięcej obrażeń w tylu ostatnich s
const WAIT_ROAR := 12.0           ## hala Żyły: co tyle s ryk z dna, gdy gniazda padły, a nikt nie wszedł (`VEIN_PLAN.md` §6.3)

## Sprite vein (tools/char_boss.py, klatka 128x80): wiersz 74 arkusza = y 0 w swiecie, paszcza w (64, 60).
const SPRITE_DROP := 6.0              ## o tyle w dol przesuwamy klatke (korzenie leza tuz pod y 0)
const MAW_POS := Vector2(0, -14)      ## srodek paszczy w swiecie (sprite); stary rysunek z kolek: (0, -8)
## Sprite HD (vein_hd, widok z przodu, klatka 640×400 przy 5 px na px świata): paszcza w (64, 43–46) klatki, czyli ok. 36 px nad jej dołem → −36 + SPRITE_DROP.
const MAW_POS_HD := Vector2(0, -30)
## Zyly na korpusie (jak VEINS w char_boss.py, po odjeciu (64, 74)): nakladka rysuje w nich zar.
const VEINS := [
	[Vector2(-6, -18), Vector2(-11, -24), Vector2(-17, -26), Vector2(-22, -31)],
	[Vector2(0, -20), Vector2(2, -27), Vector2(-1, -33), Vector2(2, -39)],
	[Vector2(6, -18), Vector2(12, -22), Vector2(18, -24), Vector2(23, -30)],
]

## state, hp, max_hp, phase (1 / 2 furia <66% / 3 krzyk <33%) — w boss_base.gd
var atk: int = Atk.NONE           ## trwająca zapowiedź ataku (synchronizowane)
var maw_open := false
var stunned := false
var nests_left := 3
## Hala Żyły (`VEIN_PLAN.md` §6.3, stan CZEKA): gniazda zniszczone, ale żaden człowiek nie wszedł do hali — śpi dalej (nietykalna),
## co WAIT_ROAR s ryczy. Budzi ją mission.gd `_tick_arena`.
var waiting := false
var _wait_roar := 0.0
var _hurt_on := true                  ## strefa trafień włączona (tylko przebudzona — uśpiona stoi przy gnieździe i zasłaniałaby je)
var move: int = Move.UP               ## stan ruchu (synchronizowany)
var sink := 0.0                       ## 0 = wynurzona, 1 = cała pod podłogą (serwer; klienci dostają w `_sync`)
var _sink_vis := 0.0                  ## każdy peer: wygładzone `sink` do rysowania (sprite, model 3D, paszcza)
## Gdzie się wynurzy (środek gardzieli na podłodze) od początku zapowiedzi do wynurzenia; INF = brak. Synchronizowane — widok 3D
## rysuje pęknięcia, bot schodzi z tego miejsca (`player.gd` `_spit_danger_x`).
var emerge_mark := Vector2.INF
var anchor := -1                      ## indeks bieżącej gardzieli (−1 = mapa bez hali)
var _anchors: Array[Vector2] = []     ## gardziele F1 z danych hali (stopy na podłodze)
var _home := Vector2.ZERO
var _move_t := 0.0
var _up_t := 0.0                      ## s od wynurzenia
var _burst_n := 0                     ## ataków w tym wynurzeniu
var _travel_from := Vector2.ZERO
var _travel_to := Vector2.ZERO
var _travel_dur := 1.0
var _pain: Array = []                 ## serwer: [czas ms, obrażenia] z ostatnich PAIN_WINDOW s
var _dmg_by: Array = []               ## serwer: [czas ms, id strzelca, obrażenia] z ostatnich DMG_WINDOW s
var _camp := {}                       ## serwer: nazwa gracza → [punkt zakotwiczenia, od kiedy tam stoi (ms)]
var _remote_pos := Vector2.ZERO
var _fx_t := 0.0
var _emerge_reason := "cycle"
## zgodność z wcześniejszymi testami / rysowaniem
var winding := false
var spitting := false
var enraged := false

var _atk_t := 0.0
var _atk_gap := 0.0
var _lash_cd := 0.0
var _spit_cd := 0.0
var _idle_t := 0.0                ## ile sekund nikt nie stoi w zasięgu macki, ogona ani zwykłego plucia
var _sweep_cd := 0.0
var _maw_t := 0.0
var _stun_cd := 0.0
var _light_check := 0.0
var _spit_target := Vector2.ZERO
## Gdzie spadnie plwocina (stopy celu, rzutowane na podłogę) od początku zapowiedzi do rozbryzgu; INF = brak. Synchronizowane —
## widok 3D rysuje tu znacznik (opinia testera 2026-10-29: kule trudno uniknąć, bo nie widać, gdzie spadną).
var spit_mark := Vector2.INF
var _spits: Array[Dictionary] = []    ## serwer: {pos, vel}
var _wave_r := -1.0                   ## serwer: promień fali ogona (<0 = brak)
var _wave_hit := {}
var _wave_start_ms := -1              ## każdy peer: rysowanie fali
var _brood_t := 0.0
var _brood_serial := 0
var _brood: Array[Node] = []
var _flash := 0.0
var _flinch := 0.0
var _net_t := 0.0
var _armor_snd_ms := 0
var _light: Lights.GameLight
var _overlay: Node2D
var _spr: Array = []                  ## [cialo, glow] z arkusza vein; puste = rysunek zastepczy z kolek

func _init() -> void:
	hp = BASE_HP
	max_hp = BASE_HP

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	Hurtbox.add(self, 70.0, 66.0)                             # strefa trafień na wysokość modelu (enemy3d.gd SPEC „fit")
	nests_left = _nest_count()
	_light = Lights.make_light(Lights.radial(), 3.5, Color(1.0, 0.35, 0.25), 0.5, false)
	_light.position = Vector2(0, -20)
	add_child(_light)
	_overlay = Lights.add_overlay(self)
	_set_hurt(false)
	_home = position
	_remote_pos = position
	var lvl := get_parent()
	if lvl != null and lvl.get("vein_arena") is Dictionary and not (lvl.vein_arena as Dictionary).is_empty():
		for c in lvl.vein_arena.get("anchors", []):
			_anchors.append(Vector2(float(c) * 16.0 + 8.0, position.y))
		anchor = _nearest_anchor(position)
	if Sprites.has(Sprites.enemy_sheet("vein")):
		_spr = Sprites.attach(self, Sprites.enemy_sheet("vein"))
		for l in _spr:
			if l != null:
				l.position = Vector2(0, SPRITE_DROP)

## Czy rysuje arkusz HD (widok z przodu, szczęki: zamknięte w uśpieniu / bezczynności / zapowiedzi, otwarte w oknie podatności i przy pluciu).
func _is_hd() -> bool:
	return not _spr.is_empty() and Sprites.enemy_sheet("vein").ends_with("_hd")

## Punkt, w który celuje latarka / który podświetla nakładka: paszcza sprite'a (HD wyżej niż w klasycznym arkuszu).
func _maw_point() -> Vector2:
	var down := Vector2(0.0, _sink_vis * SINK_DEPTH)          # zanurzona: paszcza schodzi razem z modelem
	if _spr.is_empty():
		return Vector2(0, -8) + down
	return (MAW_POS_HD if _is_hd() else MAW_POS) + down

## Czy da się ją trafić: wynurzona, w ryku albo w trakcie zanurzania (pod podłogą i w zapowiedzi wynurzenia — nie).
func _hittable() -> bool:
	return state == State.AWAKE and (move == Move.UP or move == Move.ROAR or move == Move.SINK)

## Zagrożenie dla botów i Dyrektora tylko nad podłogą — pod nią boty nie marnują amunicji.
func is_threat() -> bool:
	return state == State.AWAKE and move != Move.TRAVEL and move != Move.EMERGE

## Kontrakt widoku (view3d.gd) — patrz enemy.gd: view_info. `winding` to zapowiedź macki (inne ataki mają własne pozy z animacji).
func view_info() -> Dictionary:
	return {"kind": "vein", "alive": state != State.DEAD, "winding": winding, "sp": 0, "flash": _flash > 0.0}

# ---------------------------------------------------------------- misja (serwer)

## Liczba gniazd na mapie (tyle żył świeci, dopóki Żyła śpi).
func _nest_count() -> int:
	return maxi(1, get_tree().get_nodes_in_group("nests").size())

func on_nest_lost(left: int) -> void:
	nests_left = left
	_flinch = 0.6
	Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.9)
	_send_state(true)

## Serwer: gniazda zniszczone, ale walka w hali rusza dopiero z wejściem człowieka (mission.gd `_tick_arena`).
func begin_wait() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	waiting = true
	nests_left = 0
	_wait_roar = 1.5
	_send_state(true)

func _tick_wait(delta: float) -> void:
	_wait_roar -= delta
	if _wait_roar <= 0.0:
		_wait_roar = WAIT_ROAR
		_event.rpc("wait_roar")

## Strefa trafień i ciało: włączone tylko u przebudzonej (każdy peer, przy zmianie stanu).
func _set_hurt(on: bool) -> void:
	if on == _hurt_on:
		return
	_hurt_on = on
	Hurtbox.set_enabled(self, on)

func awaken() -> void:
	if not NoiseMgr.is_server() or state != State.DORMANT:
		return
	waiting = false
	max_hp = scaled_hp(BASE_HP, HP_PER_EXTRA_HUMAN, _humans())
	hp = max_hp
	state = State.AWAKE
	_pain.clear()
	_dmg_by.clear()
	_camp.clear()
	if not _anchors.is_empty():
		_emerge_reason = "wake"
		_set_move(Move.ROAR, ROAR_T)                # pierwszy ryk z gardzieli, nad którą spała — otwarta paszcza od razu
		_open_maw(ROAR_T, false)
		_log_emerge()
	_set_hurt(_hittable())
	phase = 1
	_atk_gap = 1.5
	_lash_cd = 0.0
	_spit_cd = 1.0
	_sweep_cd = 3.0
	_idle_t = 0.0
	_brood_t = 2.0
	_stun_cd = 0.0                    # po wipe poprzednia próba nie może zostawić cooldownu oślepienia
	_light_check = 0.0
	NoiseMgr.add_noise(N_SCREAM, global_position, "boss")
	print("[BOSS] Żyła budzi się, HP=%.0f" % max_hp)
	_event.rpc("awaken")
	_send_state(true)

func reset_enemy() -> void:
	state = State.DORMANT
	hp = BASE_HP
	max_hp = BASE_HP
	phase = 1
	nests_left = _nest_count()
	_set_atk(Atk.NONE)
	_maw_t = 0.0
	maw_open = false
	stunned = false
	enraged = false
	_idle_t = 0.0
	_spits.clear()
	spit_mark = Vector2.INF
	_wave_r = -1.0
	_wave_start_ms = -1
	visible = true
	waiting = false
	position = _home
	_remote_pos = _home
	move = Move.UP
	sink = 0.0
	_sink_vis = 0.0
	emerge_mark = Vector2.INF
	anchor = _nearest_anchor(_home)
	_pain.clear()
	_dmg_by.clear()
	_camp.clear()
	_hurt_on = true
	_set_hurt(false)                  # po śmierci ciało było wyłączone bez `_set_hurt` — wymuszamy stan
	if NoiseMgr.is_server():
		_clear_brood.rpc()
		_send_state(true)

# ---------------------------------------------------------------- symulacja

func _physics_process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_flinch = maxf(0.0, _flinch - delta)
	if not NoiseMgr.is_server():
		position = position.lerp(_remote_pos, 0.25)
		_sink_vis = move_toward(_sink_vis, sink, delta * SINK_VIS_RATE)
		return
	if state == State.AWAKE:
		_tick_maw(delta)
		if move == Move.UP or move == Move.ROAR:
			_tick_flashlight(delta)
		if move == Move.UP:
			_tick_attacks(delta)
			_tick_brood(delta)
		if not _anchors.is_empty():
			_tick_move(delta)
			_track_camp()
	elif state == State.DORMANT and waiting:
		_tick_wait(delta)
	_sink_vis = move_toward(_sink_vis, sink, delta * SINK_VIS_RATE)
	_tick_spits(delta)
	if spit_mark != Vector2.INF and atk != Atk.SPIT and _spits.is_empty():
		spit_mark = Vector2.INF                      # rozbryzg albo przerwana zapowiedź (oślepienie)
		_send_state(true)
	_tick_wave(delta)
	_net_t -= delta
	if _net_t <= 0.0:
		_send_state(false)

# ---------------------------------------------------------------- ruch w hali (VEIN_PLAN.md §7, E2)

func _set_move(m: int, t: float) -> void:
	move = m
	_move_t = t
	_set_hurt(_hittable())
	_send_state(true)

func _nearest_anchor(p: Vector2) -> int:
	var best := -1
	for i in _anchors.size():
		if best < 0 or absf(_anchors[i].x - p.x) < absf(_anchors[best].x - p.x):
			best = i
	return best

## Serwer: maszyna stanów ruchu. Wynurzona schodzi po serii, po FIGHT_MAX s albo po „bólu”, ale nie w trakcie zapowiedzi ataku
## (ból ją przerywa), oślepienia ani biegnącej fali (fala liczy się od pozycji Żyły).
func _tick_move(delta: float) -> void:
	_move_t -= delta
	match move:
		Move.ROAR:
			if _move_t <= 0.0:
				_up_t = 0.0
				_burst_n = 0
				_set_move(Move.UP, 0.0)
		Move.UP:
			_up_t += delta
			var limit := BURST_ENRAGED if phase >= 2 else BURST
			var why := ""
			if _pain_taken() >= max_hp * PAIN_FRAC:
				why = "pain"
			elif _burst_n >= limit and _maw_t <= 0.0:
				why = "burst"
			elif _up_t >= FIGHT_MAX:
				why = "time"
			if why == "" or stunned or _wave_r >= 0.0 or (atk != Atk.NONE and why != "pain"):
				return
			_begin_sink(why)
		Move.SINK:
			sink = clampf(1.0 - _move_t / SINK_T, 0.0, 1.0)
			if _move_t <= 0.0:
				sink = 1.0
				_begin_travel()
		Move.TRAVEL:
			var k := clampf(1.0 - _move_t / _travel_dur, 0.0, 1.0)
			position = _travel_from.lerp(_travel_to, smoothstep(0.0, 1.0, k))
			if _move_t <= 0.0:
				position = _travel_to
				emerge_mark = _travel_to
				_set_move(Move.EMERGE, EMERGE_T * Difficulty.m("boss_cd"))
				_event.rpc("emerge_warn")
		Move.EMERGE:
			sink = clampf(_move_t / (EMERGE_T * Difficulty.m("boss_cd")), 0.0, 1.0) * 0.35 + 0.65   # tuż pod podłogą, wypycha ją
			if _move_t <= 0.0:
				_emerge_hit()
				emerge_mark = Vector2.INF
				sink = 0.0
				_set_move(Move.ROAR, ROAR_T)
				_open_maw(ROAR_T, false)
				_event.rpc("emerge")
				_log_emerge()

func _begin_sink(why: String) -> void:
	_set_atk(Atk.NONE)
	_maw_t = 0.0
	maw_open = false
	stunned = false
	_pain.clear()
	_emerge_reason = "pain" if why == "pain" else "cycle"
	SessionLog.event("vein", {"what": "sink", "why": why, "up_s": snappedf(_up_t, 0.1), "attacks": _burst_n, "anchor": anchor,
		"hp": roundi(hp), "phase": phase})
	_set_move(Move.SINK, SINK_T)
	_event.rpc("sink")

func _begin_travel() -> void:
	var nxt := _pick_anchor()
	_travel_from = position
	_travel_to = _anchors[nxt]
	anchor = nxt
	_travel_dur = clampf(_travel_from.distance_to(_travel_to) / TRAVEL_SPEED, TRAVEL_MIN, TRAVEL_MAX)
	_set_move(Move.TRAVEL, _travel_dur)
	_event.rpc("travel")

## Wybór gardzieli (§7): nigdy ta sama dwa razy z rzędu; +2 najbliższa graczowi, który najdłużej stoi w jednym miejscu (≥ CAMP_T s
## w CAMP_R px — przeciw kampieniu), +1 najbliższa temu, kto zadał najwięcej obrażeń w DMG_WINDOW s; przy wyniku różnym o mniej niż 1
## losowanie między dwiema najlepszymi.
func _pick_anchor() -> int:
	var score := {}
	for i in _anchors.size():
		if i != anchor:
			score[i] = 0.0
	var camper := _camper()
	if camper != null:
		_score_add(score, _nearest_anchor(camper.global_position), 2.0)
	var dealer := _top_dealer()
	if dealer != null:
		_score_add(score, _nearest_anchor(dealer.global_position), 1.0)
	var keys: Array = score.keys()
	keys.shuffle()                                       # remis rozstrzyga los
	keys.sort_custom(func(a, b) -> bool: return float(score[a]) > float(score[b]))
	if keys.size() >= 2 and float(score[keys[0]]) - float(score[keys[1]]) < 1.0:
		return int(keys[randi() % 2])
	return int(keys[0])

static func _score_add(score: Dictionary, i: int, v: float) -> void:
	if score.has(i):
		score[i] = float(score[i]) + v

## Serwer: kto stoi w miejscu (żywi gracze w hali; punkt zakotwiczenia przesuwa się, gdy gracz odejdzie dalej niż CAMP_R).
func _track_camp() -> void:
	var now := Time.get_ticks_msec()
	var lvl := get_parent()
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or not lvl.in_vein_arena(p.global_position):
			_camp.erase(p.name)
			continue
		var c: Array = _camp.get(p.name, [])
		if c.is_empty() or (c[0] as Vector2).distance_to(p.global_position) > CAMP_R:
			_camp[p.name] = [p.global_position, now]

## Gracz, który najdłużej stoi w jednym miejscu (≥ CAMP_T s), albo null.
func _camper() -> Node2D:
	var now := Time.get_ticks_msec()
	var best: Node2D = null
	var best_t := CAMP_T * 1000.0
	for p in get_tree().get_nodes_in_group("players"):
		if not _camp.has(p.name):
			continue
		var t := float(now - int(_camp[p.name][1]))
		if t >= best_t:
			best_t = t
			best = p
	return best

func _top_dealer() -> Node2D:
	var now := Time.get_ticks_msec()
	_dmg_by = _dmg_by.filter(func(e: Array) -> bool: return now - int(e[0]) <= int(DMG_WINDOW * 1000.0))
	var sum := {}
	for e in _dmg_by:
		sum[int(e[1])] = float(sum.get(int(e[1]), 0.0)) + float(e[2])
	var best_id := -1
	for id in sum:
		if best_id < 0 or float(sum[id]) > float(sum[best_id]):
			best_id = id
	if best_id < 0:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.player_id) == best_id and not p.dead:
			return p
	return null

func _pain_taken() -> float:
	var now := Time.get_ticks_msec()
	_pain = _pain.filter(func(e: Array) -> bool: return now - int(e[0]) <= int(PAIN_WINDOW * 1000.0))
	var s := 0.0
	for e in _pain:
		s += float(e[1])
	return s

## Koniec zapowiedzi: kto stoi na podłodze w EMERGE_R od gardzieli, dostaje 1 HP (z odrzutem od niej).
func _emerge_hit() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - position
		if absf(d.x) <= EMERGE_R and absf(d.y) < 4.0:
			p.deliver_hit(1, position, "vein")
			SessionLog.event("vein", {"what": "emerge_hit", "who": String(p.name), "bot": bool(p.is_bot)})

func _log_emerge() -> void:
	SessionLog.event("vein", {"what": "emerge", "anchor": anchor, "reason": _emerge_reason, "pos": SessionLog.xy(position), "phase": phase})
	_emerge_reason = "cycle"

func _cd(base: float) -> float:
	return base * (ENRAGED_CD if phase >= 2 else 1.0) * Difficulty.m("boss_cd")

func _set_atk(a: int) -> void:
	atk = a
	winding = a == Atk.LASH
	spitting = a == Atk.SPIT

func _open_maw(t: float, is_stun: bool) -> void:
	_maw_t = maxf(_maw_t, t)
	maw_open = true
	stunned = is_stun
	_send_state(true)

func _tick_maw(delta: float) -> void:
	if _maw_t <= 0.0:
		return
	_maw_t -= delta
	if _maw_t <= 0.0:
		maw_open = false
		stunned = false
		_send_state(true)

## Snop latarki w paszczę w trakcie zapowiedzi ataku: oślepienie — atak
## przerwany, paszcza otwarta.
func _tick_flashlight(delta: float) -> void:
	_stun_cd = maxf(0.0, _stun_cd - delta)
	_light_check -= delta
	if _light_check > 0.0 or _stun_cd > 0.0 or stunned or atk == Atk.NONE:
		return
	_light_check = 0.1
	var lighter := Lights.flashlight_on(global_position + (MAW_POS_HD if _is_hd() else Vector2(0, -8)), get_tree(), get_world_2d().direct_space_state)
	if lighter == null:
		return
	_stun_cd = STUN_CD
	_set_atk(Atk.NONE)
	_open_maw(STUN_TIME, true)
	NoiseMgr.add_noise(N_STUN, global_position, "boss")
	print("[BOSS] oślepiona latarką (P%d)" % lighter.display_id)
	_event.rpc("blinded")

## Q w pobliżu: przez DIVERT_TIME atakuje miejsce Przesterowania, nie graczy.
func _diverted() -> bool:
	return NoiseMgr.seconds_since_overcharge() < DIVERT_TIME \
		and NoiseMgr.last_overcharge_pos.distance_to(global_position) < DIVERT_RANGE

func _tick_attacks(delta: float) -> void:
	_lash_cd -= delta
	_spit_cd -= delta
	_sweep_cd -= delta
	if not _players_in_reach(0.0).is_empty() or _ground_players_near() or _spit_candidate(SPIT_RANGE) != null:
		_idle_t = 0.0
	else:
		_idle_t += delta
	if atk != Atk.NONE:
		_atk_t -= delta
		if _atk_t <= 0.0:
			_resolve_attack()
		return
	if stunned:
		return
	_atk_gap -= delta
	if _atk_gap > 0.0:
		return
	if _diverted():
		if _spit_cd <= 0.0:
			_begin(Atk.SPIT, SPIT_WINDUP, NoiseMgr.last_overcharge_pos)
		return
	if _lash_cd <= 0.0 and not _players_in_reach(0.0).is_empty():
		_begin(Atk.LASH, LASH_WINDUP, Vector2.ZERO)
	elif _sweep_cd <= 0.0 and _ground_players_near():
		_begin(Atk.SWEEP, SWEEP_WINDUP, Vector2.ZERO)
	elif _spit_cd <= 0.0:
		var p := _spit_candidate(SPIT_RANGE_FAR if _idle_t >= IDLE_FAR else SPIT_RANGE)
		if p != null:
			# cel ustalony NA POCZĄTKU zapowiedzi — kto się ruszy, ten unika
			_begin(Atk.SPIT, SPIT_WINDUP, p.global_position + Vector2(0, -8))

func _begin(a: int, windup: float, target: Vector2) -> void:
	_set_atk(a)
	_atk_t = windup * Difficulty.m("boss_cd")
	_spit_target = target
	if a == Atk.SPIT:
		spit_mark = _floor_below(target + Vector2(0, 8))
	_event.rpc(["", "lash_windup", "spit_windup", "sweep_windup"][a])
	_send_state(true)

func _resolve_attack() -> void:
	var a := atk
	_set_atk(Atk.NONE)
	match a:
		Atk.LASH:
			for p in _players_in_reach(6.0):
				p.deliver_hit(1, global_position, "vein")
			Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD, -4.0, 0.5)
			_lash_cd = _cd(LASH_CD)
		Atk.SPIT:
			_launch_spit(_spit_target)
			_spit_cd = _cd(SPIT_CD)
		Atk.SWEEP:
			_wave_r = 24.0
			_wave_hit.clear()
			_event.rpc("sweep_go")
			_sweep_cd = _cd(SWEEP_CD)
	# po każdym ataku paszcza się otwiera — okno na ostrzał
	_burst_n += 1
	_open_maw(MAW_WINDOW, false)
	_atk_gap = (ATK_GAP_ENRAGED if phase >= 2 else ATK_GAP) * Difficulty.m("boss_cd")

## Pierwsza pełna komórka pod punktem (najwyżej 12 kafli) — znacznik plucia leży na podłodze, także gdy cel był w skoku.
func _floor_below(p: Vector2) -> Vector2:
	var lvl := get_parent()
	var cx := int(floor(p.x / 16.0))
	var cy := int(floor((p.y - 1.0) / 16.0))
	for i in 12:
		if lvl._is_solid(cx, cy + i):
			return Vector2(p.x, float(cy + i) * 16.0)
	return p

func _players_in_reach(slack: float) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.x) <= LASH_RANGE_X + slack and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			out.append(p)
	return out

## Ktoś stoi na podłodze w zasięgu ogona.
func _ground_players_near() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.y) < 4.0 and absf(d.x) <= SWEEP_RANGE:
			return true
	return false

## Cel plucia: najwyżej stojący żywy gracz poza zasięgiem macki, nie dalej niż range (SPIT_RANGE albo SPIT_RANGE_FAR).
func _spit_candidate(range_px: float) -> Node2D:
	var best: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: Vector2 = p.global_position - global_position
		if d.length() > range_px:
			continue
		if absf(d.x) <= LASH_RANGE_X and d.y <= 8.0 and d.y >= -LASH_RANGE_Y:
			continue
		if best == null or p.global_position.y < best.global_position.y:
			best = p
	return best

# ---------------------------------------------------------------- fala ogona

## Fala biegnie od Żyły po podłodze w obie strony. Trafia tylko tych, którzy
## STOJĄ na podłodze, gdy przechodzi — skok albo kładka = unik.
func _tick_wave(delta: float) -> void:
	if _wave_r < 0.0:
		return
	_wave_r += SWEEP_SPEED * delta
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or _wave_hit.has(p.name):
			continue
		var d: Vector2 = p.global_position - global_position
		if absf(d.y) < 3.0 and absf(absf(d.x) - _wave_r) <= SWEEP_HALF:
			_wave_hit[p.name] = true
			p.deliver_hit(1, global_position, "vein")
	if _wave_r > SWEEP_RANGE:
		_wave_r = -1.0

# ---------------------------------------------------------------- plucie

func _launch_spit(target: Vector2) -> void:
	var start := global_position + Vector2(0, -34)
	var dist := start.distance_to(target)
	var t := clampf(dist / 240.0, 0.75, 1.3)
	var vel := (target - start - Vector2(0, 0.5 * SPIT_GRAVITY * t * t)) / t
	_spits.append({"pos": start, "vel": vel})
	_spit_fx.rpc(start, vel)

func _tick_spits(delta: float) -> void:
	if _spits.is_empty():
		return
	var lvl := get_parent()
	var keep: Array[Dictionary] = []
	for sp in _spits:
		sp.vel.y += SPIT_GRAVITY * delta
		sp.pos += sp.vel * delta
		var hit := false
		for p in get_tree().get_nodes_in_group("players"):
			if not p.dead and p.hurt_point(sp.pos).distance_to(sp.pos) <= SPIT_HIT_R:
				p.deliver_hit(1, sp.pos, "vein")
				hit = true
				break
		var cell := Vector2i(int(floor(sp.pos.x / 16.0)), int(floor(sp.pos.y / 16.0)))
		if hit or lvl._is_solid(cell.x, cell.y) or sp.pos.y > lvl.bounds.end.y:
			NoiseMgr.add_noise(N_SPLASH, sp.pos, "boss")
			_splash_fx.rpc(sp.pos)
			continue
		keep.append(sp)
	_spits = keep

@rpc("authority", "call_local", "reliable")
func _spit_fx(start: Vector2, vel: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, start, Audio.BUS_WORLD, -4.0, 1.4)
	var glob := SpitGlob.new()
	glob.vel = vel
	glob.gravity = SPIT_GRAVITY
	glob.level = get_parent()
	glob.position = start
	glob.material = Lights.unshaded()
	glob.add_child(Lights.make_light(Lights.radial(), 1.5, Color(0.7, 1.0, 0.3), 0.8, false))
	get_parent().add_child(glob)

@rpc("authority", "call_local", "unreliable")
func _splash_fx(pos: Vector2) -> void:
	Audio.play_variant_at("impact_flesh", 3, pos, Audio.BUS_WORLD, -8.0, 1.2)
	_burst(pos, Color(0.6, 0.95, 0.3), 14)

class SpitGlob extends Node2D:
	var vel := Vector2.ZERO
	var gravity := 520.0
	var level: Node
	var life := 2.5
	func _ready() -> void:
		add_to_group("spit_globs")                        # widok 3D: kula plwociny (view3d.gd: _sync_globs)
	func _physics_process(delta: float) -> void:
		vel.y += gravity * delta
		position += vel * delta
		life -= delta
		var c := Vector2i(int(floor(position.x / 16.0)), int(floor(position.y / 16.0)))
		if life <= 0.0 or level._is_solid(c.x, c.y):
			queue_free()
		queue_redraw()
# ---------------------------------------------------------------- potomstwo

func _tick_brood(delta: float) -> void:
	for i in range(_brood.size() - 1, -1, -1):          # pętla zamiast filter(): zwolniony węzeł w tablicy typowanej psuł przypisanie
		if not is_instance_valid(_brood[i]) or not _brood[i].alive:
			_brood.remove_at(i)
	_brood_t -= delta
	if _brood_t > 0.0:
		return
	_brood_t = BROOD_EVERY_ENRAGED if phase >= 2 else BROOD_EVERY
	if _brood.size() >= BROOD_MAX + maxi(0, _humans() - 1):
		return
	_spawn_one()

func _spawn_one() -> void:
	_brood_serial += 1
	var side := -1.0 if _brood_serial % 2 == 0 else 1.0
	_spawn_brood.rpc("Brood%d" % _brood_serial, global_position + Vector2(side * 34.0, 0))

@rpc("authority", "call_local", "reliable")
func _spawn_brood(n: String, pos: Vector2) -> void:
	var e := _summon(n, pos, 0.55)
	if e != null and NoiseMgr.is_server():
		_brood.append(e)                  # listę czyści tylko serwer (_tick_brood) — u klientów rosłaby bez końca

## Serwer: dołączający w trakcie walki dostaje żywe potomstwo (bez tego RPC-e Trzosków `BroodN` trafiały u niego w próżnię).
func send_brood_to(peer_id: int) -> void:
	for b in _brood:
		if is_instance_valid(b) and b.alive:
			_spawn_brood.rpc_id(peer_id, String(b.name), b.global_position)

@rpc("authority", "call_local", "reliable")
func _clear_brood() -> void:
	_clear_summoned("Brood")
	_brood.clear()

# ---------------------------------------------------------------- obrażenia

## Trafienie z kierunkiem (projectile.gd). Pełne obrażenia tylko w OTWARTĄ paszczę
## i nie z góry; reszta (zamknięta paszcza, pancerny grzbiet) — 5% + iskra.
func take_bullet_dir(from_pos: Vector2, dmg: float, dir: Vector2) -> void:
	if not NoiseMgr.is_server():
		return
	var from_above := dir.y > ARMOR_DOWN and from_pos.y < global_position.y - 26.0
	_hit(from_pos, dmg, from_above)

func take_bullet(from_pos: Vector2, dmg: float = 8.0) -> void:
	if not NoiseMgr.is_server():
		return
	_hit(from_pos, dmg, false)

## Obrażenia z broni (combat.gd). Otwarta paszcza i trafienie z poziomu ziemi = pełne
## obrażenia; zamknięta paszcza albo pancerny grzbiet (z góry) = 5% + iskry (efekt
## „twardego” celu rysuje generyczny efekt trafienia, więc _hit nie dubluje go).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	var dir: Vector2 = info["dir"]
	var pos: Vector2 = info["pos"]
	var blast := String(info.get("type", "")) == "blast"
	var from_above := not blast and dir.y > ARMOR_DOWN and pos.y < global_position.y - 26.0
	var armored := state != State.AWAKE or from_above or not maw_open
	var amount := float(info["amount"])
	if int(info.get("pellets", 1)) > 1:
		amount *= PELLET_MULT
	var before := hp
	_hit(pos, amount, from_above, false, BLAST_CLOSED_MULT if blast else CLOSED_MULT)
	if before > hp:
		_dmg_by.append([Time.get_ticks_msec(), int(info.get("shooter", -1)), before - hp])
	return {"hit": true, "dealt": before - hp, "killed": state == State.DEAD,
		"mat": Arsenal.Mat.ARMOR if armored else Arsenal.Mat.FLESH}

func _hit(from_pos: Vector2, dmg: float, from_above: bool, fx := true, closed_mult := CLOSED_MULT) -> void:
	if state != State.AWAKE:
		if state == State.DORMANT and fx:
			Audio.play_variant_at("ricochet", 2, global_position, Audio.BUS_WORLD, -16.0)
		return
	if not _hittable():
		return                                    # pod podłogą (przejście, zapowiedź wynurzenia) — nic jej nie sięga
	if from_above or not maw_open:
		dmg *= closed_mult
		if fx:
			_armor_fx.rpc(from_pos)
	else:
		_flash = 0.08
	hp -= dmg
	_pain.append([Time.get_ticks_msec(), dmg])
	if phase == 1 and hp <= max_hp * 0.66:
		phase = 2
		enraged = true
		NoiseMgr.add_noise(N_SCREAM * 0.5, global_position, "boss")
		_event.rpc("enrage")
	if phase == 2 and hp <= max_hp * 0.33:
		_phase3()
	if hp <= 0.0:
		_die()
	else:
		_send_state(false)

## Faza 3: krzyk przyzywa Stalkera — Uwaga 100%, światła graczy migoczą.
func _phase3() -> void:
	phase = 3
	NoiseMgr.add_noise(NoiseMgr.MAX_LEVEL, global_position, "boss")
	_spawn_one()
	print("[BOSS] faza 3 — krzyk, Uwaga %.0f" % NoiseMgr.level)
	_event.rpc("phase3")
	var mis := get_tree().get_first_node_in_group("mission")
	if mis != null and mis.has_method("on_vein_release"):
		mis.on_vein_release("phase3")              # hala Żyły: brama się otwiera, Stalker rusza (VEIN_PLAN.md §12)

@rpc("authority", "call_local", "unreliable")
func _armor_fx(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - _armor_snd_ms > 120:
		_armor_snd_ms = now
		Audio.play_variant_at("ricochet", 2, pos, Audio.BUS_WORLD, -12.0, 1.2)
	_burst(pos, Color(1.0, 0.85, 0.4), 6)

func _burst(pos: Vector2, col: Color, n: int) -> void:
	Vfx.burst_fx(pos, {"color": col, "amount": n, "life": 0.35, "explosiveness": 1.0, "dir": Vector2.RIGHT, "spread": 180.0,
		"vmin": 30.0, "vmax": 90.0, "gravity": Vector2(0, 300)})

func _die() -> void:
	state = State.DEAD
	_set_atk(Atk.NONE)
	hp = 0.0
	maw_open = false
	_wave_r = -1.0
	NoiseMgr.add_noise(N_DEATH, global_position, "boss")
	_kill_summoned(_brood)
	_brood.clear()
	print("[BOSS] Żyła nie żyje")
	_drop_boss_loot()                 # dwie apteczki na drogę do ekstrakcji przez obudzony teren i złom
	_event.rpc("death")
	_send_state(true)
	died.emit()

# ---------------------------------------------------------------- sieć

func _send_state(now: bool) -> void:
	if not NoiseMgr.has_network() or not NoiseMgr.is_server():
		return
	if not now and _net_t > 0.0:
		return
	_net_t = 0.1
	_sync.rpc(state, hp, max_hp, atk, maw_open, stunned, phase, nests_left, spit_mark, position, move, sink, emerge_mark)

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync(s: int, h: float, mh: float, a: int, mo: bool, st: bool, ph: int, nl: int, sm := Vector2.INF, pos := Vector2.INF,
		mv := 0, sk := 0.0, em := Vector2.INF) -> void:
	if pos.is_finite():
		if _remote_pos.distance_to(pos) > 200.0:
			position = pos                       # dołączający / restart: bez przeciągania przez halę
		_remote_pos = pos
	move = mv
	sink = sk
	emerge_mark = em
	if h < hp - 0.01 and mo:
		_flash = 0.08
	state = s
	hp = h
	max_hp = mh
	_set_atk(a)
	maw_open = mo
	stunned = st
	phase = ph
	enraged = ph >= 2
	if nl < nests_left:
		_flinch = 0.6
	nests_left = nl
	spit_mark = sm
	if s != State.DEAD and not visible:
		visible = true
	if s != State.DEAD:
		_set_hurt(_hittable())

@rpc("authority", "call_local", "reliable")
func _event(kind: String) -> void:
	match kind:
		"awaken":
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, 0.0, 0.9)
			Audio.sting(2)
			_shake_near(5.0)
		"lash_windup":
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -2.0, 1.0)
		"spit_windup":
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -4.0, 1.25)
		"sweep_windup":
			# dudnienie pod wodą — „zaraz pójdzie fala, skacz"
			Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_STALKER, 5.0, 0.6)
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.8)
		"sweep_go":
			_wave_start_ms = Time.get_ticks_msec()
			Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, 2.0, 0.6)
			_shake_near(2.0)
		"wait_roar":
			# czeka w hali: ryk z dna, korzenie drgają — „wejdź”
			_flinch = 0.8
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -3.0, 0.8)
			Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_STALKER, 0.0, 0.5)
		"sink":
			# zanurzanie: mlaśnięcie i rozbryzg
			Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, 0.0, 0.5)
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -8.0, 0.7)
			Vfx.splash(get_parent(), global_position + Vector2(0, -2), 1.4)
		"travel":
			Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_STALKER, -4.0, 0.7)
		"emerge_warn":
			# „zaraz tu wyjdzie”: dudnienie narastające do wynurzenia
			Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_STALKER, 4.0, 0.55)
			Audio.play_variant_at("zyla_growl", 2, global_position, Audio.BUS_STALKER, -6.0, 0.75)
			_shake_near(1.5)
		"emerge":
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, -2.0, 1.0)
			Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, 4.0, 0.6)
			_burst(global_position + Vector2(0, -4), Color(0.7, 0.85, 0.95), 28)
			_shake_near(3.0)
		"blinded":
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, -6.0, 1.2)
		"enrage":
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, -2.0, 1.0)
			_shake_near(3.0)
		"phase3":
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, 2.0, 0.8)
			Audio.sting(2)
			Lights.flicker_until_ms = Time.get_ticks_msec() + 3500
			_shake_near(6.0)
		"death":
			Audio.play_variant_at("explosion", 2, global_position, Audio.BUS_WORLD, 0.0, 0.6)
			Audio.play_variant_at("zyla_roar", 2, global_position, Audio.BUS_STALKER, -2.0, 0.7)
			_shake_near(7.0)
			Feel.hitstop(0.12)
			_death_fx()
			Vfx.gibs(get_parent(), global_position + Vector2(0, -24), Color(0.4, 0.1, 0.14), 26)
			visible = false
			_hurt_on = false
			Hurtbox.set_enabled(self, false)

func _death_fx() -> void:
	Vfx.burst_fx(global_position + Vector2(0, -20), {"color": Color(0.55, 0.12, 0.16), "amount": 90, "life": 1.4, "dir": Vector2(0, -1), "spread": 80.0,
		"vmin": 60.0, "vmax": 220.0, "gravity": Vector2(0, 380), "smin": 1.5, "smax": 3.5})

# ---------------------------------------------------------------- rysowanie

func _process(delta: float) -> void:
	if not visible:
		return
	_tick_wave_spray(delta)
	_tick_move_fx(delta)
	var t := Time.get_ticks_msec() / 1000.0
	var awake := state == State.AWAKE
	_light.energy = (0.9 if awake else 0.35) + 0.25 * sin(t * (5.0 if enraged else 2.0))
	if maw_open:
		_light.energy += 0.4
	_animate_sprite(t, awake)
	queue_redraw()
	_overlay.queue_redraw()

var _spray_t := 0.0

## Kosmetyka ruchu (każdy peer): garb pod podłogą rozpycha wodę w przejściu, w zapowiedzi wynurzenia z gardzieli pryska woda i pył.
func _tick_move_fx(delta: float) -> void:
	if state != State.AWAKE or (move != Move.TRAVEL and move != Move.EMERGE):
		_fx_t = 0.0
		return
	_fx_t -= delta
	if _fx_t > 0.0:
		return
	if move == Move.TRAVEL:
		_fx_t = 0.09
		Vfx.burst(get_parent(), global_position + Vector2(0.0, -3.0), Color(0.72, 0.9, 1.0, 0.8), 4, 25.0, 80.0, Vector2.UP, 50.0, 320.0,
			0.45, Vector2(0.8, 1.6), true)
	else:
		_fx_t = 0.12
		var m := emerge_mark if emerge_mark.is_finite() else global_position
		Vfx.burst(get_parent(), m + Vector2(randf_range(-EMERGE_R, EMERGE_R) * 0.8, -2.0), Color(0.55, 0.45, 0.4, 0.9), 3, 30.0, 90.0,
			Vector2.UP, 35.0, 300.0, 0.5, Vector2(0.8, 1.4), true)

## Bryzg z grzbietów fali (lokalna kosmetyka): kilka miękkich kropel co ułamek sekundy z czoła fali po obu stronach.
func _tick_wave_spray(delta: float) -> void:
	if _wave_start_ms < 0 or Settings.quality_idx < 1:
		_spray_t = 0.0
		return
	_spray_t -= delta
	if _spray_t > 0.0:
		return
	_spray_t = 0.06
	var wr := 24.0 + (Time.get_ticks_msec() - _wave_start_ms) / 1000.0 * SWEEP_SPEED
	if wr > SWEEP_RANGE:
		return
	for sd in [-1.0, 1.0]:
		Vfx.burst(get_parent(), global_position + Vector2(sd * wr, -3.0), Color(0.75, 0.93, 1.0, 0.8), 3, 20.0, 70.0,
			Vector2(sd * 0.35, -1.0).normalized(), 40.0, 320.0, 0.4, Vector2(0.8, 1.5), true)

## Animacja z arkusza: uspiona / bezczynna (paszcza zamknieta) / otwarta / zapowiedz macek / plucie.
func _animate_sprite(t: float, awake: bool) -> void:
	if _spr.is_empty():
		return
	var anim := "dormant"
	if awake:
		if spitting:
			anim = "spit"
		elif atk != Atk.NONE:
			anim = "windup"
		elif maw_open or stunned:
			anim = "open"
		else:
			anim = "idle"
	Sprites.play(_spr, anim, false)
	var body: AnimatedSprite2D = _spr[0]
	body.speed_scale = 1.45 if enraged else 1.0
	# drzenie po trafieniu gniazda / ogluszeniu i bialy blysk po obrazeniach w paszcze
	var shake := sin(t * 40.0) * (1.6 if _flinch > 0.0 or stunned else 0.0)
	var flash := Color(2.4, 2.2, 2.2) if _flash > 0.0 else Color.WHITE
	for l in _spr:
		if l != null:
			l.position = Vector2(shake, SPRITE_DROP + _sink_vis * SINK_DEPTH)   # zanurzona: obraz (i model 3D za nim) schodzi pod podłogę
	body.modulate = flash
	# furia / krzyk: oczy i zar mocniej swieca
	var glow: AnimatedSprite2D = _spr[1]
	if glow != null:
		glow.modulate = Color(1.0, 0.8, 0.7).lerp(Color(1.4, 0.7, 0.6), 0.5 * (phase - 1)) if awake else Color(0.7, 0.7, 0.7)

## Żar paszczy, łuk zasięgu macki, zapowiedź zamachu i falę rysuje widok 3D (view3d.gd: _sync_boss_fx); tu tylko koniec biegu fali.
func _draw_overlay(_ov: Node2D) -> void:
	if _wave_start_ms >= 0 and 24.0 + (Time.get_ticks_msec() - _wave_start_ms) / 1000.0 * SWEEP_SPEED > SWEEP_RANGE:
		_wave_start_ms = -1
