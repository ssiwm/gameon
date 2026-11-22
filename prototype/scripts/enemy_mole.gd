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

func tick_special(delta: float) -> bool:
	if e._sp <= 0:
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

func server_facing() -> bool:
	return true

func attack_action() -> String:
	return "swipe"

func after_attack() -> void:
	recovery_left = RECOVERY

func tick_prelude(delta: float) -> void:
	recovery_left = maxf(0.0, recovery_left - delta)
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
	if target != null and e._in_reach(target, 0.0) and not e._wall_between(target):
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
		_climb(zone, d, face, speed, delta)
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
		e.velocity.x = 0.0 if dir == Dig.SHAFT else face * speed * DIG_PUSH
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
