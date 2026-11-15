extends RefCounted
## Muzyka adaptacyjna (MUSIC_PLAN.md E0): wynik zagrożenia T (0–100) liczony LOKALNIE dla gracza tego peera (D6, bez sieci) z tego,
## co mu naprawdę grozi (D2): wrogowie świadomi w zasięgu, obudzony boss, Stalker na łowach, świeże trafienia. Uwaga jest tylko
## składnikiem (do NOISE_MAX), więc sam hałas nie włącza muzyki — muzyka nie kłamie (P1).
## Z T wybiera warstwę stemów z histerezą; bez zagrożenia muzyka milknie (D1, warstwa -1), a co 2–4 min gra krótki „oddech”
## (warstwa 0, dron `mus_silence`). Stan każdego wroga liczy serwer i replikuje (`enemy._ai`, `boss.state`, `NoiseMgr.stalker_awake`),
## więc u klienta wynik wychodzi taki sam jak u hosta dla tej samej pozycji.

const Enemy := preload("res://scripts/enemy.gd")
const BossBase := preload("res://scripts/boss_base.gd")
const EnemyDefs := preload("res://scripts/enemy_defs.gd")

const RANGE := 480.0            ## px (30 kafli): dalej wróg nie liczy się do muzyki (słuch wrogów 150–300 px, wzrok do 280 px)
const NEAR_K := 0.45            ## waga wroga na granicy RANGE względem wroga tuż obok
const W_AWARE := 22.0           ## wróg, który goni / atakuje / zauważył
const W_AWARE_ELITE := 34.0
const W_CONTACT := 8.0          ## wróg, który sprawdza ślad albo szuka
const W_CONTACT_ELITE := 12.0
const BOSS_RANGE := 900.0
const W_BOSS := 70.0            ## obudzony boss w zasięgu: zawsze najwyższa warstwa (osobna muzyka bossa to E4)
const STALKER_RANGE := 900.0
const W_STALKER_FAR := 14.0     ## Stalker na łowach gdziekolwiek na mapie
const W_STALKER_NEAR := 40.0    ## … i tuż obok
const W_HIT := 35.0             ## świeże trafienie; gaśnie w HIT_DECAY s
const HIT_DECAY := 6.0
const NOISE_K := 0.2            ## Uwaga × NOISE_K, najwyżej NOISE_MAX — sama nie przekracza progu kontaktu
const NOISE_MAX := 12.0

const UP := [14.0, 36.0, 66.0]  ## T, od którego wchodzi warstwa 1 (kontakt / napięcie), 2 (walka), 3 (pościg)
const HYST := 8.0               ## zejście o warstwę dopiero przy T < próg − HYST (opóźnienie zejścia trzyma jeszcze AudioDirector)

const BREATH_EVERY := Vector2(120.0, 240.0)  ## s ciszy między „oddechami”
const BREATH_LEN := Vector2(8.0, 20.0)       ## s trwania oddechu
const BREATH_MAX_T := 6.0                     ## oddech tylko w prawdziwym spokoju

var threat := 0.0               ## ostatni wynik T (do dziennika i testów)
var layer := -1                 ## warstwa wybrana w tej klatce (-1 cisza … 3 pościg)
var _hit_k := 0.0
var _last_hp := -1
var _breath_in := 0.0           ## s do następnego oddechu (0 = jeszcze nie zaplanowany)
var _breath_left := 0.0
var _rng := RandomNumberGenerator.new()


func _init(seed_value := -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Klatka: zwraca warstwę muzyki dla gracza `me` (-1 = cisza). Poza misją (menu) i w kryjówce zawsze -1 i stan od nowa
## (muzyka kryjówki to radio z E5, MUSIC_PLAN.md §4.1).
func update(delta: float, me: Node2D, in_session: bool) -> int:
	if not in_session or NoiseMgr.safe_zone or not is_instance_valid(me):
		reset()
		return layer
	var hp: int = int(me.get("hp")) if me.get("hp") != null else 0
	if _last_hp >= 0 and hp < _last_hp:
		_hit_k = 1.0
	_last_hp = hp
	_hit_k = maxf(0.0, _hit_k - delta / HIT_DECAY)
	threat = score(me.global_position, gather(me.get_tree()), NoiseMgr.level, NoiseMgr.stalker_awake, _hit_k)
	layer = pick_layer(threat, layer if _breath_left <= 0.0 else -1)
	_drive_breath(delta)
	return layer


func reset() -> void:
	threat = 0.0
	layer = -1
	_hit_k = 0.0
	_last_hp = -1
	_breath_in = 0.0
	_breath_left = 0.0


## Oddech: w długiej ciszy na chwilę wchodzi sam dron (warstwa 0); każde zagrożenie go przerywa i liczy ciszę od nowa.
func _drive_breath(delta: float) -> void:
	if layer > -1 or threat >= BREATH_MAX_T:
		_breath_left = 0.0
		_breath_in = _rng.randf_range(BREATH_EVERY.x, BREATH_EVERY.y)
		return
	if _breath_left > 0.0:
		_breath_left -= delta
		if _breath_left > 0.0:
			layer = 0
		else:
			_breath_in = _rng.randf_range(BREATH_EVERY.x, BREATH_EVERY.y)
		return
	if _breath_in <= 0.0:
		_breath_in = _rng.randf_range(BREATH_EVERY.x, BREATH_EVERY.y)
	_breath_in -= delta
	if _breath_in <= 0.0:
		_breath_left = _rng.randf_range(BREATH_LEN.x, BREATH_LEN.y)
		layer = 0


## Warstwa z T z histerezą względem poprzedniej (`prev` -1 … 3). Bez oddechu: poniżej progu kontaktu cisza (-1).
static func pick_layer(t: float, prev: int) -> int:
	var up := -1
	for i in UP.size():
		if t >= float(UP[i]):
			up = i + 1
	if up >= prev:
		return up
	var keep := prev
	while keep > up and t < float(UP[keep - 1]) - HYST:
		keep -= 1
	return keep


## Zagrożenia sceny jako wpisy {pos, what: "enemy" | "boss" | "stalker", aware: 0 nic / 1 kontakt / 2 świadomy, elite}.
static func gather(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for e in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.has_method("is_stalker") and e.is_stalker():
			out.append({"pos": e.global_position, "what": "stalker", "aware": 0, "elite": false})
		elif e is BossBase:
			if e.state == BossBase.State.AWAKE:
				out.append({"pos": e.global_position, "what": "boss", "aware": 2, "elite": true})
		elif e is Enemy:
			if not e.alive or e._was_hidden:          # zamaskowany (Żerca przed porwaniem) to zasadzka — muzyka jej nie zdradza
				continue
			var a := awareness(e._ai)
			if a > 0:
				out.append({"pos": e.global_position, "what": "enemy", "aware": a, "elite": EnemyDefs.is_elite(e.kind)})
	return out


## 2 = wie o graczu (goni, zamach, rzut, krzyk, zauważył), 1 = kontakt (sprawdza ślad, szuka), 0 = śpi / wisi / słucha / wraca.
static func awareness(ai: int) -> int:
	match ai:
		Enemy.Ai.CHASE, Enemy.Ai.WINDUP, Enemy.Ai.LUNGE, Enemy.Ai.ALERT, Enemy.Ai.SCREAM, Enemy.Ai.SPECIAL:
			return 2
		Enemy.Ai.INVESTIGATE, Enemy.Ai.SEARCH:
			return 1
	return 0


## Wynik zagrożenia T (0–100) dla pozycji gracza.
static func score(me: Vector2, threats: Array, noise: float, stalker_awake: bool, hit_k: float) -> float:
	var t := minf(noise * NOISE_K, NOISE_MAX) + W_HIT * clampf(hit_k, 0.0, 1.0)
	for th in threats:
		var d: float = me.distance_to(th["pos"])
		match String(th["what"]):
			"boss":
				if d <= BOSS_RANGE:
					t += W_BOSS
			"stalker":
				if stalker_awake:
					t += lerpf(W_STALKER_NEAR, W_STALKER_FAR, clampf(d / STALKER_RANGE, 0.0, 1.0))
			_:
				if d > RANGE:
					continue
				var near := lerpf(1.0, NEAR_K, d / RANGE)
				var elite: bool = th["elite"]
				var w: float = 0.0
				if int(th["aware"]) >= 2:
					w = W_AWARE_ELITE if elite else W_AWARE
				elif int(th["aware"]) == 1:
					w = W_CONTACT_ELITE if elite else W_CONTACT
				t += w * near
	return clampf(t, 0.0, 100.0)
