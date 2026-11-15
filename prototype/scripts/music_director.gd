extends RefCounted
## Muzyka adaptacyjna (MUSIC_PLAN.md E0): wynik zagrożenia T (0–100) liczony LOKALNIE dla gracza tego peera (D6, bez sieci) z tego,
## co mu naprawdę grozi (D2): wrogowie świadomi w zasięgu, obudzony boss, Stalker na łowach, świeże trafienia. Uwaga jest tylko
## składnikiem (do NOISE_MAX), więc sam hałas nie włącza muzyki — muzyka nie kłamie (P1).
## Z T wybiera warstwę stemów z histerezą; bez zagrożenia muzyka milknie (D1, warstwa -1), a co 2–4 min gra krótki „oddech”
## (warstwa 0, dron `mus_silence`). T jest wygładzany (szybciej w górę, wolno w dół), a muzyka, która weszła, gra co najmniej
## MIN_ON s: pierwszy odsłuch 1.7.578 (dziennik sesji 1.1) dał 28 wejść w 6 min, mediana 3,6 s, 30 zmian warstwy w < 1 s od
## poprzedniej — stan wrogów migocze (zauważył → zgubił), a muzyka szła za nim „jak wyłącznik”. Stan każdego wroga liczy serwer i replikuje (`enemy._ai`, `boss.state`, `NoiseMgr.stalker_awake`),
## więc u klienta wynik wychodzi taki sam jak u hosta dla tej samej pozycji.
## E1: motyw Stalkera (dalszy / bliższy wg odległości, tylko gdy poluje — D3), jednorazowe sygnały elity i hordy oraz stan
## życia lokalnego gracza (ostatnie serce, leży) — wyjście w `motif_far`, `motif_near`, `cue`, `health`, czyta je HUD.

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
const NOISE_K := 0.1            ## Uwaga × NOISE_K, najwyżej NOISE_MAX — sama nie włącza muzyki ani jej nie podtrzymuje (< DOWN[0])
const NOISE_MAX := 6.0

const UP := [14.0, 36.0, 66.0]  ## T, od którego wchodzi warstwa 1 (kontakt / napięcie), 2 (walka), 3 (pościg)
const DOWN := [9.0, 28.0, 58.0] ## T, poniżej którego warstwa 1 / 2 / 3 schodzi niżej (histereza; DOWN[0] > NOISE_MAX — sam hałas nie trzyma muzyki)
const ATTACK_TAU := 1.2         ## s: stała czasowa wzrostu wygładzonego T (mignięcie „zauważył” przez ułamek sekundy nie włącza muzyki)
const RELEASE_TAU := 5.0        ## s: stała czasowa spadku — po ostatnim zagrożeniu muzyka opada stopniowo, nie znika
const MIN_ON := 12.0            ## s: muzyka, która weszła, gra co najmniej tyle, zanim zejdzie do ciszy
const MIN_STEP := 5.0           ## s: najkrótszy pobyt w warstwie przed zejściem o warstwę (bez „pompowania” walka ↔ pościg)

const MOTIF_RANGE := 1400.0      ## px: Stalker dalej słychać tylko jako cichy motyw daleki (stała obecność, gdy poluje)
const MOTIF_NEAR := Vector2(700.0, 280.0)   ## px: od 700 motyw bliski zaczyna wchodzić, przy 280 gra w pełni
const MOTIF_FAR_MIN := 0.75     ## głośność motywu dalekiego dla Stalkera za MOTIF_RANGE (krzywa dB: ≈ −10 dB)
const MOTIF_NEAR_MIN := 0.6     ## głośność, od której wchodzi motyw bliski (≈ −16 dB)
const CUE_RANGE := 620.0        ## px: wróg dalej nie wywołuje sygnału elity ani hordy
const HORDE_N := 4              ## tylu nowych świadomych wrogów w HORDE_WINDOW s = horda
const HORDE_WINDOW := 4.0
const HORDE_COOLDOWN := 45.0
const ELITE_COOLDOWN := 20.0

const BREATH_EVERY := Vector2(120.0, 240.0)  ## s ciszy między „oddechami”
const BREATH_LEN := Vector2(8.0, 20.0)       ## s trwania oddechu
const BREATH_MAX_T := 6.0                     ## oddech tylko w prawdziwym spokoju

var threat := 0.0               ## wygładzony wynik T — on wybiera warstwę (do dziennika i testów)
var raw_threat := 0.0           ## T z tej klatki, przed wygładzeniem
var layer := -1                 ## warstwa wybrana w tej klatce (-1 cisza … 3 pościg, z oddechem)
var _base := -1                 ## warstwa z zagrożenia (bez oddechu)
var _on_t := 0.0                ## s od wejścia muzyki z ciszy
var _in_layer_t := 0.0          ## s w bieżącej warstwie _base
var _hit_k := 0.0
var _last_hp := -1
var _breath_in := 0.0           ## s do następnego oddechu (0 = jeszcze nie zaplanowany)
var _breath_left := 0.0
var _rng := RandomNumberGenerator.new()
var motif_far := 0.0            ## głośność motywu dalekiego 0..1 (dla AudioDirector.music_set_motif)
var motif_near := 0.0
var cue := ""                   ## sygnał do zagrania w tej klatce ("" = nic): cue_elite / cue_horde
var health := 0                 ## 0 zdrowy, 1 ostatnie serce, 2 leży (AudioDirector.music_set_health)
var _aware_ids := {}            ## wrogowie świadomi w CUE_RANGE w poprzedniej klatce (id → true)
var _elite_cued := {}           ## elity, które już miały sygnał w tej próbie
var _wave: Array[float] = []    ## zegary nowych „zauważył” (horda)
var _clock := 0.0
var _elite_cd := 0.0
var _horde_cd := 0.0


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
	var threats := gather(me.get_tree())
	raw_threat = score(me.global_position, threats, NoiseMgr.level, NoiseMgr.stalker_awake, _hit_k)
	step(delta, raw_threat)
	health = 2 if me.get("dead") == true else (1 if hp == 1 else 0)
	motif(me.global_position, threats, NoiseMgr.stalker_awake)
	cues(delta, me.global_position, threats)
	return layer


## Motyw Stalkera: tylko gdy poluje (D3 — uczciwie). Daleko cichy motyw daleki, bliżej przenika w bliski.
func motif(me: Vector2, threats: Array, stalker_awake: bool) -> void:
	motif_far = 0.0
	motif_near = 0.0
	if not stalker_awake:
		return
	var dist := INF
	for th in threats:
		if String(th["what"]) == "stalker":
			dist = minf(dist, me.distance_to(th["pos"]))
	if dist == INF:
		return
	var near := smoothstep(0.0, 1.0, clampf((MOTIF_NEAR.x - dist) / (MOTIF_NEAR.x - MOTIF_NEAR.y), 0.0, 1.0))
	var close := clampf(1.0 - dist / MOTIF_RANGE, 0.0, 1.0)
	motif_far = lerpf(MOTIF_FAR_MIN, 1.0, clampf(close / 0.5, 0.0, 1.0)) * (1.0 - 0.85 * near)
	motif_near = lerpf(MOTIF_NEAR_MIN, 1.0, near) if near > 0.0 else 0.0


## Sygnały: elita, która pierwszy raz w tej próbie cię zauważyła; horda = krzyk alarmu albo HORDE_N nowych świadomych w HORDE_WINDOW s.
func cues(delta: float, me: Vector2, threats: Array) -> void:
	cue = ""
	_clock += delta
	_elite_cd = maxf(0.0, _elite_cd - delta)
	_horde_cd = maxf(0.0, _horde_cd - delta)
	var now := {}
	var new_elite := false
	var scream := false
	for th in threats:
		if String(th["what"]) != "enemy" or int(th["aware"]) < 2 or me.distance_to(th["pos"]) > CUE_RANGE:
			continue
		var id: int = int(th.get("id", 0))
		now[id] = true
		scream = scream or bool(th.get("scream", false))
		if _aware_ids.has(id):
			continue
		_wave.append(_clock)
		if bool(th["elite"]) and not _elite_cued.has(id):
			_elite_cued[id] = true
			new_elite = true
	_aware_ids = now
	while not _wave.is_empty() and _clock - _wave[0] > HORDE_WINDOW:
		_wave.pop_front()
	if _horde_cd <= 0.0 and (scream or _wave.size() >= HORDE_N):
		cue = "cue_horde"
		_horde_cd = HORDE_COOLDOWN
		_elite_cd = maxf(_elite_cd, 6.0)              # elita w samej hordzie nie dokłada drugiego sygnału
		_wave.clear()
	elif new_elite and _elite_cd <= 0.0:
		cue = "cue_elite"
		_elite_cd = ELITE_COOLDOWN


## Wygładzenie T, warstwa z histerezą i minimalnymi czasami, potem oddech. Osobno od `update`, żeby test mógł podać T wprost.
func step(delta: float, raw: float) -> void:
	raw_threat = raw
	threat += (raw - threat) * (1.0 - exp(-delta / (ATTACK_TAU if raw > threat else RELEASE_TAU)))
	var want := pick_layer(threat, _base)
	if want < _base and (_in_layer_t < MIN_STEP or (want < 0 and _on_t < MIN_ON)):
		want = _base
	_in_layer_t = _in_layer_t + delta if want == _base else 0.0
	_on_t = _on_t + delta if want >= 0 else 0.0
	_base = want
	layer = _base
	_drive_breath(delta)


func reset() -> void:
	threat = 0.0
	raw_threat = 0.0
	layer = -1
	_base = -1
	_on_t = 0.0
	_in_layer_t = 0.0
	_hit_k = 0.0
	_last_hp = -1
	motif_far = 0.0
	motif_near = 0.0
	cue = ""
	health = 0
	_aware_ids.clear()
	_elite_cued.clear()
	_wave.clear()
	_elite_cd = 0.0
	_horde_cd = 0.0
	_breath_in = 0.0
	_breath_left = 0.0


## Oddech: w długiej ciszy na chwilę wchodzi sam dron (warstwa 0); każde zagrożenie go przerywa i liczy ciszę od nowa.
func _drive_breath(delta: float) -> void:
	if _base > -1 or threat >= BREATH_MAX_T:
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
	while keep > up and t < float(DOWN[keep - 1]):
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
				out.append({"pos": e.global_position, "what": "enemy", "aware": a, "elite": EnemyDefs.is_elite(e.kind),
					"id": e.get_instance_id(), "scream": e._ai == Enemy.Ai.SCREAM})
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
