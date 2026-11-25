extends "res://scripts/enemy_behavior.gd"
## Łupacz wychodzi z kieszeni przodem do chodnika. Ruch i kontakt rozstrzyga serwer.
## W strefie wydobycia przekopuje się do celu (gracz albo ślad hałasu): skała strefy na drodze nie zatrzymuje go, tylko spowalnia.
## Wyrwę robi pazur (dig_materials.gd Tool.CLAW, dig_zone.gd `claw_dig`), stan kopania widzą klienci jako ujemne `_sp` (−kierunek).

const ENTRY_SECONDS := 2.0
const LENGTH_PX := 20.0
const ENTRY_TRAVEL := LENGTH_PX * 1.64 / 1.90346   ## przesunięcie kości Root względem długości modelu
const CONTACT := 19.0 / 24.0
const RECOVERY := 13.0 / 24.0

var entry_time := 0.0
var entry_face := 1.0
var entry_stamp := 0
var recovery_left := 0.0
var hurt: CollisionShape2D

## Kopanie: kierunki wyrwy (−`_sp` u kopiącego). Płasko — chodnik na wysokość ciała przed nim, w górę — rampa o stopień wyżej
## (wchodzi na nią), w dół — stopień niżej, szyb — dziura pod stopami, gdy cel jest prawie pionowo pod nim, wspinaczka — strop nad głową,
## gdy cel jest prawie pionowo nad nim (albo rampa nie ma już czego wyciąć): wdrapuje się pazurami po ścianach własnego szybu.
enum Dig { NONE, FLAT, UP, DOWN, SHAFT, CLIMB }
const DIG_EVERY := 1.0 / 3.0            ## s na pociągnięcie łapą (klip `dig`: 16 klatek przy 24 kl./s = dwa pociągnięcia)
const DIG_HALF := Vector2(6.0, 7.0)     ## px: połowy boków wyrwy (z zaokrągleniem 16 × 18 px — ciało 13 × 10 i zapas na stanięcie na zadzie)
const DIG_ROUND := 2.0
const DIG_AHEAD := 11.0                 ## px: środek wyrwy przed stopami
const DIG_LIFT := {Dig.FLAT: 9.0, Dig.DOWN: 4.0}   ## px: środek wyrwy nad stopami (płasko dno równo ze stopami, w dół stopień 5 px niżej)
## Rampa w górę: stopień 6 px przed nim i strop podniesiony także nad nim (od 3 px za środkiem) — bez tego przeskok na stopień
## uderzał głową w strop komory i Łupacz spadał z powrotem (test K3c).
const UP_CENTER := Vector2(8.0, 16.0)
const UP_HALF := Vector2(9.0, 8.0)
const SHAFT_HALF := Vector2(6.0, 3.0)   ## px: szyb pod stopami (8 px w dół na pociągnięcie)
const CLIMB_LIFT := 17.0                ## px: środek wyrwy nad głową przy wspinaczce (od 10 do 24 px nad stopami)
const CLIMB_HALF := Vector2(6.0, 5.0)
const CLIMB_V := 18.0                   ## px/s: wspinaczka w szybie
const CLIMB_GRIP := 10.0                ## px od środka ciała: skała tak blisko po boku albo nad głową = ma się czego trzymać
const DIG_Y_TOL := 8.0                  ## px różnicy wysokości do celu, przy której kopie płasko
const SHAFT_X := 10.0                   ## px: cel bliżej w poziomie i niżej — kopie w dół pod sobą
const DIG_PUSH := 0.8                   ## część prędkości, z jaką napiera na czoło wyrwy
## px/s: najwyższe tempo napierania na czoło i wspinaczki — pazur wybiera skałę w stałym rytmie (DIG_EVERY), więc szybszy chód (L1: 30 px/s)
## wbijał ciało w niewybraną skałę i klinował je we własnym szybie (test K3c). W otwartym chodniku idzie pełną prędkością.
const DIG_SPEED := 16.0
const STEP_UP := 9.0                    ## px: najwyższy stopień, na który wchodzi bez skoku (rampa wyrwy w górę ma 6 px)
const STEP_FWD := 4.0                   ## px: przesunięcie na stopień
const HOP_V := -150.0                   ## przeskok na wyższy próg, do ok. 12 px (poza skałą strefy)
const STALL_HOP := 0.3                  ## s oparcia o ścianę, po których przeskakuje próg (poza skałą strefy)
const STALL_DIG := 0.5                  ## s bez postępu albo z zablokowaną trasą, po których kopie w stronę celu w pionie
const ZONE_NEAR := 24.0                 ## px od strefy: dalej nie kopie
const LEAD_Y := 10.0                    ## px: ślad hałasu osiągnięty dopiero na tej samej wysokości (rdzeń liczy 28 px — spod stropu nie słychać)
const STALL_MOVE := 2.0                 ## px od kotwicy: dalej — robi postęp
const STALL_NAV := 1.5                  ## s bez postępu i bez skały do kopania, po których oddaje ruch grafowi nawigacji…
const NAV_TIME := 2.0                   ## …na tyle s

## Skorupa z urobku (1.7.681, `reports/lupacz-pancerz-2026-11-25`): trzy płyty łupka na grzbiecie — 0 kark (hełm górnika), 1 środek
## (nakładka szyny), 2 zad (lampa). Płyta wybierana z punktu trafienia wzdłuż ciała, więc ogień od przodu bije w kark, od tyłu w zad.
## Kula w całą płytę: płyta bierze SHELL_BULLET obrażeń (amunicja przeciwpancerna więcej), ciało nic, rykoszet hałasuje. Rozbita płyta
## odsłania tę tercję ciała (pełne obrażenia). Brzuch: przy zapowiedzi ciosu (staje na tylnych łapach) strefa trafień rośnie w górę
## (`_fit_hurt`), a trafienie powyżej BELLY_Y bierze ×BELLY_MULT. Kilof łupie łupek (płyta z jednego ciosu), maczeta tylko ją rysuje (jak kula).
## Wybuch zrywa wszystkie płyty, ciało bierze część. Ogień skorupa przepuszcza (podpalenie rani ciało, `enemy.gd: _tick_burn`).
const Weapons := preload("res://scripts/weapons.gd")
const LampTokens := preload("res://scripts/lamp_tokens.gd")
## vfx.gd i session_log.gd (autoloady w ciele) ładowane w chwili użycia — patrz `_autoload`.
const VFX_PATH := "res://scripts/vfx.gd"
const SESSION_LOG_PATH := "res://scripts/session_log.gd"
const PLATES := 3
const PLATE_HP := 60.0
const SHELL_BULLET := 0.3               ## część obrażeń kuli i ostrza, którą przyjmuje płyta
const SHELL_PICK := 1.5                 ## kilof w płytę (55 × 1,5 > 60 — łupek pęka od jednego ciosu)
const SHELL_BLAST_BODY := 0.5           ## wybuch ze skorupą: ciało dostaje tę część (płyty zjadają resztę i odpadają)
const BELLY_MULT := 1.5
const BELLY_Y := 12.5                   ## px nad stopami: zwykła strefa trafień ma 12 px, wyżej jest tylko brzuch podniesiony do ciosu
const PLATE_EDGE := 2.8                 ## px od środka ciała wzdłuż osi: dalej w przód — kark, w tył — zad (bok strefy trafień 17 px)
const PLATE_STAGGER := 0.4              ## s chwiania po rozbiciu płyty
const RICOCHET_NOISE := 0.4             ## Uwagi za kulę odbitą od płyty (ostrzał skorupy jest głośny)
const LAMP_PLATE := 2                   ## płyta z lampą benzynową górnika (zad): rozbita tłucze lampę…
const LAMP_FIRE := 3.0                  ## …i grzbiet płonie tyle s (8 HP/s, enemy.gd BURN_DPS — ogień rani ciało przez skorupę)
const PLATE_ORE := 0.5                  ## szansa na 1 złom (urobek z płyty łupka z pirytem) do łupu misji za rozbitą płytę
const HELMET_PLATE := 0                 ## płyta karku z hełmem górnika: rozbita zrzuca markę lampową (lamp_tokens.gd), raz na życie Łupacza
var token_dropped := false
const PLATE_LIFT := [Vector2(5.0, -10.0), Vector2(0.0, -11.0), Vector2(-5.0, -10.0)]   ## środki płyt (x wzdłuż patrzenia) — efekty
var plates := PackedFloat32Array([PLATE_HP, PLATE_HP, PLATE_HP])   ## serwer: HP płyt; klient: 0 / PLATE_HP z migawki

## Zanurzenie (1.7.683): w strefie wydobycia Łupacz wraca w skałę, gdy jest ranny (HP < SUB_HP z rozbitą płytą), gdy SUB_LOST s nie ma celu
## ani śladu albo gdy rdzeń odsyła go do snu po szukaniu (zamiast zasnąć na środku wykopu). Pod ziemią (`_sp` = SP_UNDER) jest niewidoczny i nietrafialny (enemy.gd: `is_hidden` chowa model i strefę trafień u każdego
## peera); po SUB_TIME s wybiera najbliższego gracza w strefie (do SUB_RANGE px od jej brzegu; bez nikogo czeka w skale), staje w kieszeni
## za czołem jego wykopu (`DigZone.wake_spot`, jak wyjście K3) i przez RISE_TIME s drapie (`_sp` = SP_RISE, wciąż ukryty), potem ściana
## pęka (`DigZone.open_pocket`) i wychodzi zwykłym wyjściem z kieszeni. Wraca z jedną odrośniętą płytą z tego, przez co kopał: z żyły
## pirytową (PYRITE_HP), ze skały i ziemi łupkową. Przerwa SUB_CD s między zanurzeniami.
const SP_UNDER := -20
const SP_RISE := -21
const SUB_HP := 0.4
const SUB_LOST := 4.0
const SUB_TIME := 2.5
const RISE_TIME := 1.2
const SUB_CD := 14.0
const SUB_RANGE := 48.0
const PYRITE_HP := 90.0
var sub_t := 0.0
var sub_cd := 0.0
var lost_t := 0.0
var sub_zone = null
var rise_src := Vector2.INF
var rise_side := 1.0
var submerges := 0                      ## serwer: zanurzenia od wczytania (test, dziennik)
var under_t := 0.0                      ## serwer: s pod ziemią w tym zanurzeniu (dziennik `mole_rise`)

## Dziennik spotkań (LUPACZ_PLAN.md L0): `mole_stuck`, gdy po wyjściu z kieszeni STUCK_LOG s goni cel bez postępu — raz na wyjście.
const STUCK_LOG := 3.0
var stuck_t := 0.0
var _stuck_at := Vector2.INF
var _stuck_logged := false
var _last_by := ""                      ## serwer: czym dostał ostatnio (dziennik `mole_death`)
var _was_active := false                ## serwer: był aktywny w poprzednim tiku — przejście w sen po szukaniu = zanurzenie

## Zmysł drgań (LUPACZ_PLAN.md L1, D1–D2): słuch zwykły tylko do 40 px (`hear` w enemy_defs.gd), za to drgania gruntu (`NoiseMgr.tremor`:
## bieg, kopanie, stempel, wybuch, rozbijana przegroda, drezyna, lądowanie z wysoka) czuje przez skałę, bez drogi dźwięku, do TREMOR_RANGE px
## przy sile ≥ 1 (słabsze bliżej, najmniej TREMOR_FLOOR zasięgu). Zanurzony wychodzi tylko do gracza, którego poczuł w ostatnich FELT_KEEP s.
## Wzrok bez zmian, ale gracza kucającego bez ruchu od STILL_HIDE s nie widzi dalej niż STILL_SEE px. Po wyjściu z kieszeni zryw.
const TREMOR_RANGE := 260.0
const TREMOR_FLOOR := 0.5
const FELT_KEEP := 2.5                  ## s: tak długo po drganiu zanurzony pamięta, skąd szło
const FELT_NEAR := 40.0                 ## px: gracz tak blisko miejsca drgania jest jego źródłem
const STILL_HIDE := 0.5
const STILL_SEE := 20.0
const STILL_MOVE := 1.5                 ## px od kotwicy: dalej — gracz się ruszył
const BURST_SPEED := 70.0               ## px/s przez BURST_TIME s po wyjściu z kieszeni (K3 i wynurzenie)
const BURST_TIME := 1.0
var burst_t := 0.0
var tremors := 0                        ## serwer: poczute drgania od wczytania (test)
var felt_pos := Vector2.INF             ## serwer: ostatnie poczute drganie
var felt_t := -100.0                    ## serwer: czas symulacji (`_clock`) ostatniego poczutego drgania
var _clock := 0.0
var _tremor_seen := -1
var _still := {}                        ## serwer: id gracza → [kotwica, s bez ruchu]

var dig_cd := 0.0
var digs := 0                           ## serwer: wyrw od wczytania (test, dziennik)
var stall := 0.0                        ## s bez postępu
var nav_t := 0.0
var _last_pos := Vector2.INF

func on_ready() -> void:
	hurt = e.get_meta("hurt_shape")

static func entry_travel(t: float) -> float:
	return ENTRY_TRAVEL * smoothstep(0.0, ENTRY_SECONDS, t)

func begin_entry(face: float, elapsed: float) -> void:
	entry_time = clampf(elapsed, 0.0, ENTRY_SECONDS)
	entry_face = signf(face)
	# W istniejącej migawce _sp = 0 oznacza chodnik, 1 + tik (60 Hz) oznacza wyjście.
	# Klient odzyskuje fazę z następnej migawki także po zagubieniu pakietu.
	entry_stamp = 1 + roundi(entry_time * 60.0)
	e._sp = entry_stamp
	e._facing = entry_face
	e._net_face = entry_face
	e._view_facing = entry_face

func reset() -> void:
	entry_time = 0.0
	entry_stamp = 0
	recovery_left = 0.0
	dig_cd = 0.0
	stall = 0.0
	nav_t = 0.0
	_last_pos = Vector2.INF
	_fit_hurt(0.0, 0.0)
	plates = PackedFloat32Array([PLATE_HP, PLATE_HP, PLATE_HP])          # wipe, restart: skorupa cała
	sub_t = 0.0
	sub_cd = 0.0
	lost_t = 0.0
	sub_zone = null
	rise_src = Vector2.INF
	_was_active = false
	token_dropped = false
	under_t = 0.0
	stuck_t = 0.0
	_stuck_at = Vector2.INF
	_stuck_logged = false
	_last_by = ""
	burst_t = 0.0
	felt_pos = Vector2.INF
	felt_t = -100.0
	_still.clear()

# ---------------------------------------------------------------- skorupa

## Płyta pod punktem trafienia `pos` u wroga w `feet`, zwróconego w stronę `face`: 0 kark, 1 środek, 2 zad.
static func plate_at(pos: Vector2, feet: Vector2, face: float) -> int:
	var along := (pos.x - feet.x) * (face if face != 0.0 else 1.0)
	if along > PLATE_EDGE:
		return 0
	return 2 if along < -PLATE_EDGE else 1

func intact() -> int:
	var n := 0
	for hp in plates:
		if hp > 0.0:
			n += 1
	return n

func absorb(info: Dictionary, dmg: float) -> float:
	var t := String(info.get("type", "bullet"))
	if t == "blast":
		if intact() == 0:
			return dmg
		for i in PLATES:
			if plates[i] > 0.0:
				_break(i, "blast", int(info.get("shooter", -1)))
		return dmg * SHELL_BLAST_BODY
	if t != "bullet" and t != "beam" and t != "rail" and t != "melee":
		return dmg                                           # ogień, płomień i inne: skorupa nie chroni
	var pos: Vector2 = info.get("pos", e.global_position)
	if e._windup > 0.0 and pos.y < e.global_position.y - BELLY_Y:
		info["crit"] = true                                  # brzuch podniesiony do ciosu
		return dmg * BELLY_MULT
	var i := plate_at(pos, e.global_position, e._facing)
	if plates[i] <= 0.0:
		return dmg                                           # rozbita płyta: ta tercja ciała jest odsłonięta
	info["shell"] = true
	var pick := t == "melee" and int(info.get("w", -1)) == Weapons.KILOF
	var mult := SHELL_PICK if pick else lerpf(SHELL_BULLET, 1.0, clampf(float(info.get("ap", 0.0)), 0.0, 1.0))
	plates[i] = maxf(0.0, plates[i] - dmg * mult)
	if plates[i] <= 0.0:
		_break(i, "pick" if pick else t, int(info.get("shooter", -1)))
	elif t != "melee":
		_autoload("NoiseMgr").add_noise(RICOCHET_NOISE, pos, "ricochet")
	return 0.0

## Serwer: płyta `i` odpada — chwianie, efekt u wszystkich, dziennik.
func _break(i: int, by: String, shooter: int) -> void:
	plates[i] = 0.0
	e._stagger = maxf(e._stagger, PLATE_STAGGER)
	if i == LAMP_PLATE:
		e._ignite(LAMP_FIRE)                                   # lampa pęka, benzyna zapala grzbiet
	if i == HELMET_PLATE:
		_drop_token()
	var scrap := _autoload("Scrap")
	if scrap != null and scrap.enabled() and randf() < PLATE_ORE:
		scrap.add_loot(1)                                      # urobek z płyty (Nocny Dyżur: Scrap.enabled() = false)
		e.behavior_fx("ore")
	var log_s: GDScript = load(SESSION_LOG_PATH)
	log_s.event("shell_break", {"plate": i, "by": by, "p": shooter, "left": intact(), "pos": log_s.xy(e.global_position)})
	e.behavior_fx("plate%d" % i)

# ---------------------------------------------------------------- zanurzenie

func is_hidden() -> bool:
	return e._sp <= SP_UNDER

func threat_ok() -> bool:
	return not is_hidden()

func may_attack() -> bool:
	return not is_hidden()

## W skale (zanurzony i drapiący) nic go nie rani. Playtest 1.7.685: granat 40 mm w otwarty dołek nad nim (i pył ćm) zabijał rannego
## Łupacza pod ziemią — niewidocznie, więc wyglądało, jakby nie wrócił (LUPACZ_PLAN.md L0).
func immune(_info: Dictionary) -> bool:
	return is_hidden()

## Serwer: strefa, w której Łupacz ma się zanurzyć teraz, albo null. Tylko na podłożu, poza ciosem, w samej strefie.
func _wants_under(went_idle := false):
	if sub_cd > 0.0 or (not e.active and not went_idle) or e._windup > 0.0 or recovery_left > 0.0 or not e.is_on_floor():
		return null
	var hurt: bool = e.hp < e._max_hp * SUB_HP and intact() < PLATES
	if not hurt and lost_t < SUB_LOST and not went_idle:
		return null
	var zone = _zone_near()
	if zone == null or not (zone.rect_px() as Rect2).has_point(e.global_position + Vector2(0.0, -4.0)):
		return null
	return zone

func _go_under(zone) -> void:
	sub_zone = zone
	sub_t = 0.0
	under_t = 0.0
	sub_cd = SUB_CD
	submerges += 1
	var why := "hurt" if e.hp < e._max_hp * SUB_HP and intact() < PLATES else "lost"
	e.active = true                                            # w skale czuwa: wyjdzie do gracza, który wejdzie do strefy
	_was_active = true
	e._sp = SP_UNDER
	e.velocity = Vector2.ZERO
	e._windup = 0.0
	e._burn = 0.0                                              # skała dusi ogień (lampa z płyty zadu, plama) — inaczej dopalał się pod ziemią
	zone.claw_dig(e.global_position + Vector2(0.0, 2.0), Vector2(7.0, 5.0), DIG_ROUND, Vector2.UP)      # dołek po zanurzeniu
	var log_s: GDScript = load(SESSION_LOG_PATH)
	log_s.event("mole_under", {"why": why, "hp": roundi(e.hp), "plates": intact(), "pos": log_s.xy(e.global_position)})
	e.behavior_fx("under")

func _tick_under(delta: float) -> void:
	sub_t += delta
	under_t += delta
	e.velocity = Vector2.ZERO
	if sub_zone == null or not is_instance_valid(sub_zone):
		e._sp = 0                                              # strefa zniknęła (zmiana mapy) — wraca tam, gdzie był
		return
	if e._sp == SP_UNDER:
		var who: Node2D = _rise_target() if sub_t >= SUB_TIME else null
		if who != null:
			var dir := Vector2(signf(who.global_position.x - e.global_position.x), 0.0)
			var spot: Array = sub_zone.wake_spot(who.global_position, dir)
			rise_src = spot[0]
			rise_side = float(spot[2])
			e.global_position = Vector2(rise_src.x + rise_side * 4.0, rise_src.y + float(sub_zone.WAKE_POCKET.y) - 1.0)
			e._sp = SP_RISE
			var log_r: GDScript = load(SESSION_LOG_PATH)
			log_r.event("mole_rise", {"to": _who(who), "spot": log_r.xy(rise_src), "behind": bool(spot[1]), "under": snappedf(under_t, 0.1)})
			log_r.note_mole("rises")
			sub_t = 0.0
			e.behavior_fx("rise:%d:%d" % [roundi(rise_src.x), roundi(rise_src.y)])
	elif sub_t >= RISE_TIME:
		sub_zone.open_pocket(rise_src)
		var mat := String(sub_zone.material_at_px(rise_src))
		var grown := _regrow(mat)
		var log_e: GDScript = load(SESSION_LOG_PATH)
		log_e.event("mole_emerge", {"pos": log_e.xy(e.global_position), "mat": mat, "grow": grown, "plates": intact(), "under": snappedf(under_t, 0.1)})
		log_e.note_mole("emerges")
		_stuck_logged = false
		stuck_t = 0.0
		_stuck_at = Vector2.INF
		lost_t = 0.0
		e._sp = 0
		begin_entry(-rise_side, 0.0)                           # wyjście z kieszeni przodem do chodnika (jak K3)
		e.behavior_fx("emerge")
	e._send_state(delta)

## Gracz w strefie zanurzenia (do SUB_RANGE px od jej brzegu), którego Łupacz poczuł w ostatnich FELT_KEEP s — najbliższy miejscu drgania
## (do FELT_NEAR px od niego) — albo null. Kto stoi albo kuca cicho, tego nie znajdzie (L1: „przestań kopać i kucnij”).
func _rise_target() -> Node2D:
	if felt_pos == Vector2.INF or _clock - felt_t > FELT_KEEP:
		return null
	var area: Rect2 = (sub_zone.rect_px() as Rect2).grow(SUB_RANGE)
	var best: Node2D = null
	for p in e.get_tree().get_nodes_in_group("players"):
		var pn := p as Node2D
		if pn == null or bool(pn.get("dead")) or not area.has_point(pn.global_position) or pn.global_position.distance_to(felt_pos) > FELT_NEAR:
			continue
		if best == null or pn.global_position.distance_to(felt_pos) < best.global_position.distance_to(felt_pos):
			best = pn
	return best

## Zasięg odczuwania drgania o sile `strength` (px, przed mnożnikiem słuchu z trudności).
static func tremor_reach(strength: float) -> float:
	return TREMOR_RANGE * clampf(strength, TREMOR_FLOOR, 1.0)

## Serwer: nowe drganie gruntu (`NoiseMgr.tremor`) w zasięgu — zapamiętuje miejsce (wynurzenie), śpiącego budzi i prowadzi do źródła
## (z błędem jak słuch), obudzonego bez celu w oku prowadzi. Przez skałę: odległość w linii prostej.
func _feel() -> void:
	var nm := _autoload("NoiseMgr")
	if nm == null or int(nm.tremor_serial) == _tremor_seen:
		return
	_tremor_seen = int(nm.tremor_serial)
	var pos: Vector2 = nm.last_tremor_pos
	var strength := float(nm.last_tremor_strength)
	var diff := _autoload("Difficulty")
	var reach := tremor_reach(strength) * (float(diff.m("enemy_hear")) if diff != null else 1.0)
	var d: float = e.global_position.distance_to(pos)
	if d >= reach:
		return
	tremors += 1
	felt_pos = pos
	felt_t = _clock
	if is_hidden():
		return
	var lead: Vector2 = e._heard_pos(pos, d, reach, strength)
	if not e.active:
		e._lead_at(lead)
		e.wake("tremor")
	elif e._target == null:
		e._lead_at(lead)

## Serwer: ile s każdy gracz kuca bez ruchu (`sees`).
func _track_still(delta: float) -> void:
	for p in e.get_tree().get_nodes_in_group("players"):
		var pn := p as Node2D
		if pn == null:
			continue
		var id := pn.get_instance_id()
		var s: Array = _still.get(id, [pn.global_position, 0.0])
		if not bool(pn.get("crouching")) or (s[0] as Vector2).distance_to(pn.global_position) > STILL_MOVE:
			s = [pn.global_position, 0.0]
		else:
			s[1] = float(s[1]) + delta
		_still[id] = s

## Czy gracz `pp` kuca bez ruchu od STILL_HIDE s.
func still_hidden(pp: Node2D) -> bool:
	var s: Array = _still.get(pp.get_instance_id(), [])
	return not s.is_empty() and bool(pp.get("crouching")) and float(s[1]) >= STILL_HIDE

func sees(pp: Node2D, d: float) -> bool:
	return d <= STILL_SEE or not still_hidden(pp)

func speed_mult() -> float:
	return BURST_SPEED / maxf(1.0, float(e._def["speed"])) if burst_t > 0.0 else 1.0

## Zanurzony nie śpi płytko — nie zwalnia tików (drgania nie zmieniają `noise_serial`, więc LOD rdzenia by ich nie zauważył).
func asleep_lod() -> bool:
	return false

## Odrasta pierwsza rozbita płyta (od karku): z żyły pirytowa, inaczej łupkowa. Zwraca numer płyty albo −1.
func _regrow(material: String) -> int:
	for i in PLATES:
		if plates[i] <= 0.0:
			plates[i] = PYRITE_HP if material == "vein" else PLATE_HP
			e.behavior_fx("grow%d" % i)
			return i
	return -1

## Gracz w dzienniku: P<n> (bot jak człowiek — pole `bot` mówi resztę).
static func _who(p: Node) -> String:
	return "P%d" % int(p.get("display_id")) if p != null and p.get("display_id") != null else String(p.name) if p != null else ""

## Serwer, cios w zasięgu (te same warunki co `enemy.gd: _resolve_attack`): wpis `mole_hit` — komu, ile, czym. Cios zadaje rdzeń.
func strike(pp: Node2D) -> bool:
	if pp != null and is_instance_valid(pp) and not bool(pp.get("dead")) and e._in_reach(pp, 6.0) and not e._wall_between(pp):
		var dmg: int = e._scaled_damage(int(e._def["damage"]))
		var log_s: GDScript = load(SESSION_LOG_PATH)
		log_s.event("mole_hit", {"to": _who(pp), "bot": bool(pp.get("is_bot")), "dmg": dmg, "by": "swipe", "hp": int(pp.get("hp")), "pos": log_s.xy(e.global_position)})
		log_s.note_mole("hits")
		log_s.note_mole("dmg", float(dmg))
	return false

func took_hit(info: Dictionary, _dmg: float) -> void:
	_last_by = String(info.get("type", ""))
	if int(info.get("w", -1)) == Weapons.KILOF and _last_by == "melee":
		_last_by = "pick"

func on_death() -> void:
	var log_s: GDScript = load(SESSION_LOG_PATH)
	log_s.event("mole_death", {"by": _last_by, "plates": intact(), "submerges": submerges, "pos": log_s.xy(e.global_position)})
	log_s.note_mole("deaths")

## Serwer, po wyjściu z kieszeni: STUCK_LOG s pościgu bez postępu (ruch < STALL_MOVE px) — wpis `mole_stuck` raz na wyjście.
func _watch_stuck(delta: float) -> void:
	if _stuck_logged or not e.active or (e._target == null and not e._has_lead) or e._windup > 0.0 or recovery_left > 0.0 			or (e._target != null and e._in_reach(e._target, 0.0)):
		stuck_t = 0.0
		_stuck_at = e.global_position
		return
	if _stuck_at.distance_to(e.global_position) > STALL_MOVE:
		_stuck_at = e.global_position
		stuck_t = 0.0
		return
	stuck_t += delta
	if stuck_t >= STUCK_LOG:
		_stuck_logged = true
		var goal: Vector2 = e._target.global_position if e._target != null else e._last_known
		var log_s: GDScript = load(SESSION_LOG_PATH)
		log_s.event("mole_stuck", {"pos": log_s.xy(e.global_position), "goal": log_s.xy(goal), "target": _who(e._target) if e._target != null else "", "ai": e.ai_name()})
		log_s.note_mole("stuck")

## Serwer: hełm z płyty karku spada — w nim marka lampowa górnika z tej mapy, której gospodarz jeszcze nie ma (lamp_tokens.gd `for_map`).
func _drop_token() -> void:
	if token_dropped:
		return
	var lvl: Node = e.get_tree().get_first_node_in_group("level")
	var prof: Node = _autoload("Profile")
	if lvl == null or prof == null or not lvl.has_method("spawn_item"):
		return
	var id := LampTokens.for_map(String(lvl.get("map_id")), prof.lamp_tokens)
	if id == "":
		return
	token_dropped = true
	var off: Vector2 = PLATE_LIFT[HELMET_PLATE]
	lvl.spawn_item("lamptoken", LampTokens.index_of(id), e.global_position + Vector2(off.x * e._facing, off.y))

## Autoload z drzewa w chwili użycia: `enemy_defs.gd` wczytuje ten plik (`Mole`) także w skryptach `-s` bez autoloadów
## (test_enemy_surface.gd), więc odwołanie wprost do `NoiseMgr` / `Audio` (i preload skryptów, które ich używają) nie skompilowałoby się tam.
func _autoload(n: String) -> Node:
	return e.get_node_or_null("/root/" + n)

## Każdy peer: dźwięk i odłamki zanurzenia — wejście w skałę, drapanie w miejscu wyjścia (zapowiedź), pęknięcie ściany, odrośnięta płyta.
func _burrow_fx(event: String) -> void:
	if event.begins_with("grow"):
		plates[clampi(int(event.substr(4)), 0, PLATES - 1)] = PLATE_HP
	var au := _autoload("Audio")
	if au == null:
		return
	var vfx: GDScript = load(VFX_PATH)
	var at: Vector2 = e.global_position
	if event == "under":
		vfx.chips(e.get_parent(), at, Vector2.UP, Color(0.36, 0.32, 0.27), 12, "chip", 90.0, Vector2(0.8, 1.8))
		au.play_variant_at("dig_gravel", 3, at, au.BUS_WORLD, -3.0, 0.62)
		au.play_variant_at("claw_scrape", 3, at, au.BUS_WORLD, -8.0, 0.9)
	elif event.begins_with("rise:"):
		var xy := event.split(":")
		var spot := Vector2(float(xy[1]), float(xy[2]))
		au.play_variant_at("claw_scrape", 3, spot, au.BUS_WORLD, -4.0, randf_range(0.95, 1.05))      # sygnatura: trzy pociągnięcia pazurów
	elif event == "emerge":
		au.play_at("collapse", at, au.BUS_WORLD, -5.0, 1.35)
		au.play_variant_at("lupacz_squeal", 2, at, au.BUS_WORLD, -3.0, randf_range(0.9, 1.0))
		vfx.chips(e.get_parent(), at + Vector2(0.0, -8.0), Vector2.UP, Color(0.36, 0.32, 0.27), 12, "chip", 120.0, Vector2(1.0, 2.2))
	else:
		au.play_variant_at("dig_gravel", 3, at, au.BUS_WORLD, -6.0, 0.5)

## Tłumaczenie tekstu UI (zachowanie to RefCounted bez `tr`).
func tr_ui(text: String) -> String:
	return e.tr(text)

func net_bits() -> int:
	var m := 0
	for i in PLATES:
		if plates[i] > 0.0:
			m |= 1 << i
	return m

func apply_net_bits(bits: int) -> void:
	for i in PLATES:
		plates[i] = PLATE_HP if bits & (1 << i) else 0.0

## Każdy peer: płyta odpada — odłamki łupka z jej miejsca, trzask kamienia i pisk.
func fx(event: String) -> void:
	if event == "under" or event == "emerge" or event.begins_with("rise:") or event.begins_with("grow"):
		_burrow_fx(event)
		return
	if event == "ore":
		var msg := _autoload("Msg")
		if msg != null:
			msg.post("mole.ore", msg.Ch.TOAST, tr_ui("Shale plate: +1 scrap"), {"sub": tr_ui("Ore from the shell goes to the mission loot"), "style": msg.Style.SUCCESS, "ttl": 2.0, "prio": 25})
		return
	if not event.begins_with("plate"):
		return
	var i := clampi(int(event.substr(5)), 0, PLATES - 1)
	plates[i] = 0.0
	var off: Vector2 = PLATE_LIFT[i]
	var at: Vector2 = e.global_position + Vector2(off.x * e._facing, off.y)
	(load(VFX_PATH) as GDScript).chips(e.get_parent(), at, Vector2(-e._facing * 0.4, -1.0).normalized(), Color(0.27, 0.29, 0.31), 14, "chip", 140.0, Vector2(1.0, 2.4))
	var au := _autoload("Audio")
	if au == null:
		return
	au.play_variant_at("shell_crack", 2, at, au.BUS_WORLD, -2.0, randf_range(0.94, 1.06))      # łupek pęka wzdłuż warstw (bake_sfx.py `_build_shell`)
	au.play_variant_at("lupacz_squeal", 2, at, au.BUS_WORLD, -4.0, randf_range(0.95, 1.08))

func tick_special(delta: float) -> bool:
	_clock += delta
	_track_still(delta)
	_feel()
	if e._sp <= SP_UNDER:
		_tick_under(delta)
		return true
	if e._sp <= 0:
		sub_cd = maxf(0.0, sub_cd - delta)
		lost_t = 0.0 if (e._target != null or e._has_lead or not e.active) else lost_t + delta
		var went_idle: bool = _was_active and not e.active
		_was_active = e.active
		_watch_stuck(delta)
		var zone = _wants_under(went_idle)
		if zone != null:
			_go_under(zone)
			return true
		return false
	var before := entry_travel(entry_time)
	entry_time = minf(ENTRY_SECONDS, entry_time + delta)
	e._sp = 1 + roundi(entry_time * 60.0)
	e.velocity.x = entry_face * (entry_travel(entry_time) - before) / delta
	e._apply_gravity(delta)
	e._slide()
	if entry_time >= ENTRY_SECONDS:
		e._sp = 0
		e.velocity.x = 0.0
		burst_t = BURST_TIME                                   # zryw spod ściany — wyjście nie jest darmowym oknem na ostrzał
	e._send_state(delta)
	return true

func present(delta: float) -> void:
	if not e.is_multiplayer_authority():
		if e._sp > 0:
			var stamp: int = e._sp
			var seconds := (stamp - 1) / 60.0
			entry_time = seconds if stamp != entry_stamp else minf(entry_time + delta, minf(seconds + 0.05, ENTRY_SECONDS))
			entry_stamp = stamp
		recovery_left = maxf(0.0, recovery_left - delta)
		_fit_hurt(e._view_windup_remaining, e._view_windup_duration)

func view_extra(d: Dictionary) -> void:
	if e._sp > 0:
		d["burrow_time"] = entry_time
	if recovery_left > 0.0:
		d["swipe_recovery"] = recovery_left
	d["shell"] = net_bits()                                  # maska całych płyt — dla modelu ze skorupą

func server_facing() -> bool:
	return true

func attack_action() -> String:
	return "swipe"

func after_attack() -> void:
	recovery_left = RECOVERY

func tick_prelude(delta: float) -> void:
	recovery_left = maxf(0.0, recovery_left - delta)
	burst_t = maxf(0.0, burst_t - delta)
	dig_cd = maxf(0.0, dig_cd - delta)
	if e._sp < 0 and (not e.active or e._windup > 0.0):
		e._sp = 0
	_fit_hurt(e._windup, e._windup_duration)

## Serwer, łańcuch decyzji przed pościgiem: w strefie wydobycia (i tuż przy niej) Łupacz sam prowadzi się do celu — gracza albo śladu
## hałasu — prosto, bez grafu nawigacji (graf nie zna wykopów: kafel z resztką skały jest dla niego bryłą, więc kazał stać pod celem).
## Skała strefy na drodze: kopie (płasko, rampą w górę, stopniem w dół, szybem pod sobą). Niski stopień: wchodzi na niego (`step_up`).
## Oddaje ruch rdzeniowi przy celu w zasięgu ciosu, na samym śladzie (rozgląda się) i na NAV_TIME s, gdy STALL_NAV s stoi bez
## postępu i nie ma czego kopać (ściana mapy poza strefą — wtedy obchodzi ją grafem).
func drive(delta: float, target: Node2D, speed: float) -> bool:
	nav_t = maxf(0.0, nav_t - delta)
	var goal: Vector2 = target.global_position if target != null else (e._last_known if e._has_lead else Vector2.INF)
	var zone = _zone_near() if goal != Vector2.INF and nav_t <= 0.0 else null
	var pos: Vector2 = e.global_position
	if zone == null:
		_stop_dig()
		stall = 0.0
		return false
	# cios oddaje rdzeniowi dopiero na podłożu: w szybie, wisząc na pazurach 18 px pod celem, przerywał wspinaczkę dla ciosu, spadał i chybiał (K3c)
	if target != null and e._in_reach(target, 0.0) and not e._wall_between(target) and (e.is_on_floor() or e._sp != -Dig.CLIMB):
		_stop_dig()
		return false
	var d: Vector2 = goal - pos
	if target == null and absf(d.x) < 10.0 and absf(d.y) < LEAD_Y:
		_stop_dig()
		return false                                         # na śladzie — rozgląda się rdzeń (`_investigate`)
	if target == null:
		e._search_t = 0.0                                    # rdzeń uznaje ślad za osiągnięty już 28 px niżej — Łupacz kopie dalej, nie szuka pod nim
	var face: float = signf(d.x) if absf(d.x) > 1.0 else e._facing
	var walled: bool = e.is_on_floor() and e.is_on_wall()
	# na nierównym konturze wykopu ciało potrafi zawisnąć na rogu (bez podłogi albo bez „ściany”) — próg sprawdza też po chwili bez postępu
	if (walled or stall >= STALL_HOP) and (e.is_on_floor() or e.is_on_wall()) and absf(d.x) > 3.0 and step_up(face):
		walled = false
	# postęp względem kotwicy: drgania ciała klinowanego w rogu konturu (ułamki px na klatkę) nie liczą się jako ruch
	if _last_pos.distance_to(e.global_position) > STALL_MOVE:
		_last_pos = e.global_position
		stall = 0.0
	else:
		stall += delta
	var dir := dig_dir(d, zone.claw_rock(cut_center(Dig.FLAT, face), DIG_HALF, DIG_ROUND), stall >= STALL_DIG)
	if dir == Dig.UP and stall >= STALL_DIG and not _cut_has_rock(zone, dir, face):
		dir = Dig.CLIMB                                      # komora pod celem bez stopnia — rampa nie ma czego wyciąć
	if dir == Dig.CLIMB and _grip(zone):
		_climb(zone, d, face, minf(speed, DIG_SPEED), delta)
		return true
	if dir != Dig.NONE and dir != Dig.CLIMB and _cut_has_rock(zone, dir, face):
		e._sp = -dir
		e._facing = face
		e._blocked = false
		e._blocked_t = 0.0
		if dig_cd <= 0.0:
			dig_cd = DIG_EVERY
			zone.claw_dig(cut_center(dir, face), cut_half(dir), DIG_ROUND, Vector2.UP if dir == Dig.SHAFT else Vector2(-face, -0.5).normalized())
			digs += 1
		e.velocity.x = 0.0 if dir == Dig.SHAFT else face * minf(speed, DIG_SPEED) * DIG_PUSH
		return true
	_stop_dig()
	if stall >= STALL_NAV:
		nav_t = NAV_TIME
		stall = 0.0
		return false
	if walled and stall >= STALL_HOP:
		e.velocity.y = HOP_V
	e.velocity.x = face * speed if absf(d.x) > 3.0 else 0.0
	return true

## Wspinaczka w szybie (Dig.CLIMB): strop nad głową w skale — kopie go i trzyma się ścian (bez opadania), wolno — wdrapuje się w górę,
## przesuwając się w stronę celu, żeby wyjść na krawędź, gdy stopy miną wylot. Grawitację rdzeń dodaje po `drive` — tu ją znosimy.
func _climb(zone, d: Vector2, face: float, speed: float, delta: float) -> void:
	e._sp = -Dig.CLIMB
	e._facing = face
	e._blocked = false
	e._blocked_t = 0.0
	stall = 0.0
	var hold: float = 0.0 if e.is_on_floor() else -e.GRAVITY * delta
	var c: Vector2 = cut_center(Dig.CLIMB, face)
	if zone.claw_rock(c, CLIMB_HALF, DIG_ROUND):
		if dig_cd <= 0.0:
			dig_cd = DIG_EVERY
			zone.claw_dig(c, CLIMB_HALF, DIG_ROUND, Vector2.DOWN)
			digs += 1
		e.velocity = Vector2(0.0, hold)
		return
	e.velocity = Vector2(face * speed * 0.6 if absf(d.x) > 3.0 else 0.0, hold - CLIMB_V)

## Czy ma się czego trzymać przy wspinaczce: skała strefy tuż obok boku ciała albo nad głową. W otwartej komorze ani nad wylotem
## szybu nie wspina się — spada i idzie zwykłym ruchem.
func _grip(zone) -> bool:
	var p: Vector2 = e.global_position
	for y in [-1.0, -5.0, -9.0]:
		for x in [-CLIMB_GRIP, CLIMB_GRIP]:
			if zone.solid_at_px(p + Vector2(x, y)):
				return true
	return zone.solid_at_px(p + Vector2(0.0, -12.0))

## Wejście na stopień do STEP_UP px przed sobą (w stronę `face`): ciało podnosi się o najmniejszą wysokość, na której ma przed sobą
## STEP_FWD px wolnego miejsca, i przesuwa się na stopień — przód ciała staje na nim, grawitacja dociska. Ciało 2D samo nie wchodzi
## na próg, przeskok zahaczał rogiem o krawędź, a przesunięcie o 1 px zostawiało ciało bez oparcia (zsuwało się, test K3c). True — wszedł.
func step_up(face: float) -> bool:
	var xf: Transform2D = e.global_transform
	var h := 1.0
	# sprawdza samą podniesioną pozycję i drogę w przód, nie drogę w górę: róg ciała wbity w krawędź konturu (ułamek px) zgłasza
	# kolizję przy każdym ruchu z miejsca. Podniesione ciało, które zachodzi na strop, też ją zgłasza — przez strop nie przejdzie.
	while h <= STEP_UP:
		if not e.test_move(xf.translated(Vector2(0.0, -h)), Vector2(face * STEP_FWD, 0.0)):
			e.global_position += Vector2(face * STEP_FWD, -h)
			return true
		h += 1.0
	return false

## Kierunek kopania do celu `d` (cel − stopy): płasko, gdy przed nim w chodniku leży skała (`flat_rock`); w pionie także bez niej, gdy
## od STALL_DIG s nie robi postępu (`stuck`) albo cel jest prawie pionowo pod nim. Dig.NONE — idzie zwykłym pościgiem.
static func dig_dir(d: Vector2, flat_rock: bool, stuck: bool) -> int:
	if d.y > DIG_Y_TOL and absf(d.x) < SHAFT_X:
		return Dig.SHAFT
	if d.y < -DIG_Y_TOL and absf(d.x) < SHAFT_X:
		return Dig.CLIMB
	if not flat_rock and not stuck:
		return Dig.NONE
	if d.y < -DIG_Y_TOL:
		return Dig.UP
	if d.y > DIG_Y_TOL:
		return Dig.DOWN
	return Dig.FLAT if flat_rock else Dig.NONE

## Środek wyrwy w kierunku `dir` przed wrogiem zwróconym w stronę `face`.
func cut_center(dir: int, face: float) -> Vector2:
	if dir == Dig.CLIMB:
		return e.global_position + Vector2(0.0, -CLIMB_LIFT)
	if dir == Dig.SHAFT:
		return e.global_position + Vector2(0.0, SHAFT_HALF.y - 1.0)
	if dir == Dig.UP:
		return e.global_position + Vector2(face * UP_CENTER.x, -UP_CENTER.y)
	return e.global_position + Vector2(face * DIG_AHEAD, -float(DIG_LIFT.get(dir, DIG_LIFT[Dig.FLAT])))

## Połowy boków wyrwy w kierunku `dir`.
static func cut_half(dir: int) -> Vector2:
	return SHAFT_HALF if dir == Dig.SHAFT else UP_HALF if dir == Dig.UP else CLIMB_HALF if dir == Dig.CLIMB else DIG_HALF

func _cut_has_rock(zone, dir: int, face: float) -> bool:
	return zone.claw_rock(cut_center(dir, face), cut_half(dir), DIG_ROUND)

func _stop_dig() -> void:
	if e._sp < 0:
		e._sp = 0

## Strefa wydobycia, przy której stoi (najdalej ZONE_NEAR px od jej brzegu), albo null.
func _zone_near():
	var lvl = e.get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.has_method("dig_zones"):
		return null
	for z in lvl.dig_zones():
		if (z.rect_px() as Rect2).grow(ZONE_NEAR).has_point(e.global_position):
			return z
	return null

## Podniesiony bark i głowa wystają nad korytarz. Zmienia się strefa pocisków,
## a niskie ciało poruszające się po wykopie zachowuje swoje wymiary.
func _fit_hurt(remaining: float, duration: float) -> void:
	var frame := 19.0 * (1.0 - remaining / duration) if remaining > 0.0 and duration > 0.0 else 0.0
	var rear := smoothstep(4.0, 12.0, frame) * (1.0 - smoothstep(14.0, 18.0, frame))
	var shape := hurt.shape as RectangleShape2D
	var height := 12.0 + roundf(7.0 * rear)
	if shape.size.y != height:
		shape.size.y = height
		hurt.position.y = -0.5 * height

func holds_still() -> bool:
	return recovery_left > 0.0
