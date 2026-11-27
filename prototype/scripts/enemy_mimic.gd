extends "res://scripts/enemy_behavior.gd"
## Mimik (GDD §7.1, MIMIC_PLAN.md): udaje kolegę z drużyny — stoi jak żywy, z bronią opuszczoną lufą w dół i z imieniem jak u gracza,
## ale bez serduszek. Woła o pomoc krzykiem kolegi, gdy ktoś jest w zasięgu słuchu, ale jeszcze nie przy nim — wabi do zasadzki.
## Kto podejdzie albo strzeli, ten go demaskuje (`wake`): krzyk, fala i chwila na przemianę. Snop latarki demaskuje dopiero po
## LIGHT_REVEAL_S ciągłego światła (M2); w świetle Mimik odwraca twarz, oczy łapią połysk, a klatka piersiowa zaczyna oddychać (widok 3D).
##
## Mimik-zwłoki (M5, `become_corpse`): leży w gnieździe zwłok z danych mapy (corpse.gd), w tej samej pozie i stroju co prawdziwe ciało —
## widok rysuje go jako zwłoki (corpse3d.gd), bez plamy krwi pod ciałem. Nie woła i nie ma etykiety. Demaskuje go: przeszukiwanie
## (po corpse.gd MIMIC_GRAB_S), przejście tuż nad nim (OVER_PX, także bot), trafienie, CORPSE_LIGHT_S ciągłego snopu.
## Leżąc ma niskie ciało i strefę trafień (LYING), po demaskacji wraca do stojących.
##
## Chwyt z przebrania (M6): pierwszy cios w ciągu GRAB_READY_S po demaskacji to chwyt (`strike`) — przemiana bez celu chwyta tego, kto stoi
## przy nim (przeszukujący zwłoki), zwykła zapowiedź swój cel. Chwycony jest przypięty jak u Pijawki (`player.grabbed`: może strzelać i bić),
## dostaje GRAB_DMG na początku i na końcu GRAB_S; Mimik trzyma go w miejscu (`tick_phase`, `_sp` = SP_HOLD dla widoku) i potem odskakuje.
## Wcześniej puszcza (`took_hit`): cios wręcz chwyconego, ogłuszenie (strzelba, harpun, kilof), GRAB_FREE_DMG od innych, śmierć.
## Kolejne ciosy są zwykłe, lżejszym klipem `jab`. Każdy chwyt to wpis `mimic_grab` w dzienniku sesji.
##
## Przemiana (M7): demaskacja to MORPH_S zapowiedzi bez celu (klip `morph`) — przez nią Mimik przyjmuje MORPH_DMG × obrażenia (okno kontry);
## potem zryw LOPE_S z prędkością LOPE_SPEED, dalej zwykłe 95 px/s. Leżący odwraca się przodem do stóp zwłok, bo widok wstaje klipem upadku
## od końca (corpse3d.gd `rise`). Widok dostaje czas od demaskacji (`since_reveal`) — z niego liczy wstawanie, wydłużanie rąk, materiał i chód.
##
## Echo krzyku (M8): krzyk gracza (G albo mikrofon) nie demaskuje przebranego Mimika — po ECHO_DELAY odpowiada tym samym krzykiem, odrobinę
## za nisko (ECHO_PITCH), z miejsca, w którym stoi albo leży (leżący ciszej i stłumiony, a ciało drga — corpse3d.gd `echo`). Prawdziwi
## koledzy, bot i zwłoki milczą, więc krzyk to test „kto to?”. Jedno echo na krzyk; krzyki w czasie oczekiwania łączą się w nie.
##
## Powalony kolega (M9): w co-op (≥ 2 ludzi) Mimik `Y` z szansą DOWNED_CHANCE (ziarno mapy) zamiast stać leży jak powalony gracz — model
## postaci kolegi w pozie upadku, nad nim jego kryptonim i odliczanie wykrwawiania (`down_state`), woła o pomoc. Serwer przełącza przebranie
## tylko, gdy nikt nie stoi bliżej niż DOWNED_CLEAR_PX; stan idzie do klientów w replikowanym `e._sp` (SP_DOWNED). Podnoszenie [E] (player.gd
## `_handle_revive`, grupa DOWNED_GROUP) po REVIVE_GRAB_S prosi serwer o demaskację (`revive`) — przemiana chwyta podnoszącego. Sygnały:
## prawdziwy kolega stoi w HUD drużyny (karta, strzałka przy krawędzi), odliczanie staje na 0 s, oczy w snopie, echo krzyku; leży jak zwłoki
## (niskie ciało, OVER_PX, CORPSE_LIGHT_S), wstaje „wstecz” jak Mimik-zwłoki — w modelu kolegi.
##
## Solo (uwaga z gry 2026-11-24): Mimik `Y` nie stoi jak gracz, tylko leży jako zwłoki w swoim ciele (`y_body`, level.gd `_add_y_bodies`) —
## tak samo jak Mimik-zwłoki z gniazda: przeszukiwanie, przejście tuż nad nim, snop 2,5 s, trafienie. Serwer wybiera przebranie (`want_mode`)
## i przełącza je tylko z dala od ludzi; klienci czytają je z `e._sp` (SP_CORPSE). Alarm Podsłuchacza przebranego nie budzi.

const Lights := preload("res://scripts/lights.gd")
const Player := preload("res://scripts/player.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const LIGHT_REVEAL_S := 1.5          ## s ciągłego snopu latarki do demaskacji (M2)
const DARK_RESET_S := 0.5            ## s ciemności, po których licznik światła wraca do zera
const LIT_EVERY := 0.12              ## s między sprawdzeniami snopu w widoku (każdy peer)
const CALL_R := Vector2(70.0, 340.0) ## px: wabi, gdy najbliższy gracz jest dalej niż x i bliżej niż y
const CALL_GAP := Vector2(6.0, 10.0) ## s między wołaniami
const CALL_BLUR := 48.0              ## px: rozrzut miejsca wołania (kierunek rozmyty jak przez radio)
const LABEL_EVERY := 2.0             ## s między przeliczeniem etykiety (lista drużyny i postaci)
const CORPSE_LIGHT_S := 2.5          ## s ciągłego snopu do demaskacji leżącego (dłużej niż stojący — „wytrzymuje” światło)
const OVER_PX := 10.0                ## px: przejście tuż nad leżącym (ok. 0,6 m) go budzi
const LYING := Vector2(26.0, 5.0)    ## px: ciało ruchu i strefa trafień leżącego (zwłoki mają ok. 26 px długości)
const GRAB_READY_S := 2.5            ## s po demaskacji, w których cios jest chwytem (potem tylko zwykłe ciosy)
const GRAB_S := 1.5                  ## s trzymania chwyconego
const GRAB_DMG := 1                  ## obrażenia na początku i na końcu chwytu (× trudność)
const GRAB_FREE_DMG := 20.0          ## obrażenia od innych (kolega, bot) w trakcie chwytu, które go zrywają
const GRAB_SLACK := 12.0             ## px ponad zasięg ciosu: przemiana chwyta przeszukującego zwłoki (corpse.gd REACH_X 24 px)
const GRAB_AFTER_CD := 0.9           ## s do następnego ciosu po puszczeniu
const GRAB_RECOIL := 110.0           ## px/s odskoku Mimika po puszczeniu
const SP_HOLD := 1                   ## `e._sp` w trakcie chwytu (replikowany — widok 3D trzyma pozę chwytu, enemy3d.gd `hold_sp`)
const MORPH_S := 0.9                 ## s przemiany po demaskacji (zapowiedź bez celu; była 0,35 s)
const MORPH_DMG := 1.25              ## mnożnik przyjmowanych obrażeń w czasie przemiany
const LOPE_S := 1.5                  ## s zrywu po przemianie
const LOPE_SPEED := 110.0            ## px/s w zrywie (zwykle 95, jak gracz)
const RISE_S := 0.75                 ## s wstawania Mimika-zwłok w widoku (corpse3d.gd `rise`); potem widać model wroga
const ECHO_DELAY := 0.5              ## s od krzyku gracza do echa (M8)
const ECHO_JITTER := 0.08            ## s rozrzutu opóźnienia (echo nie brzmi jak automat)
const ECHO_PITCH := 0.9              ## wysokość echa względem krzyku gracza (player.gd `_scream_fx` 0,8 ± 0,06)
const ECHO_DB := -1.0                ## dB echa stojącego
const ECHO_DB_LYING := -7.0          ## dB echa leżącego (stłumiony głos spod ciała)
const ECHO_VIEW_S := 0.6             ## s drgnięcia ciała leżącego w widoku
const SP_CORPSE := 3                 ## `e._sp` Mimika `Y` leżącego w swoim ciele (solo; replikowany jak SP_DOWNED)
const SP_DOWNED := 2                 ## `e._sp` przebranego za powalonego kolegę (M9; replikowany w `_sync` — klienci i dołączający wiedzą bez RPC)
const DOWNED_CHANCE := 0.5           ## szansa, że Mimik `Y` w co-op leży jako powalony kolega (z ziarna mapy i nazwy — stała na całą mapę)
const DOWNED_CLEAR_PX := 300.0       ## px: przebranie zmienia się tylko, gdy żaden człowiek nie stoi bliżej (nikt nie widzi, jak się kładzie)
const MODE_EVERY := 2.0              ## s między sprawdzeniami przebrania (serwer)
const REVIVE_GRAB_S := 0.3           ## s podnoszenia do chwytu (jak przeszukiwanie Mimika-zwłok, D6)
const REVIVE_SLACK := 1.4            ## serwer: zapas zasięgu podnoszenia (pozycja klienta dochodzi z opóźnieniem)
const DOWNED_GROUP := "downed_mimics" ## Mimiki widziane jako powaleni koledzy (każdy peer) — cele podnoszenia w player.gd
const DOWNED_MODEL := "res://art/char3d/mpfb/%s.glb"   ## model postaci gracza (char3d.gd `set_look`, zestaw „mpfb”)
## Kryptonimy, gdy nie ma kogo udawać (sam, bez innych postaci i bez bota) — brzmią jak operatorzy, ale nikt ich nie nosi.
const FALLBACK_NAMES := ["Kret", "Wiór", "Sowa", "Łoś"]

var lure_t := 4.0            ## odstęp między fałszywymi wołaniami
var calls := 0               ## wołania przed demaskacją (dziennik `mimic_reveal`)
var lit_s := 0.0             ## s ciągłego światła na przebranym (serwer)
var _lit_ms := 0             ## zegar ostatniego sprawdzenia światła (serwer)
var _dark_s := 0.0           ## s ciemności od ostatniego światła (serwer)
var _lit := 0.0              ## 0..1: snop na nim w widoku (każdy peer)
var _lit_t := 0.0
var _label := ""
var _label_col := Color.WHITE
var _label_t := 0.0
var corpse: Node2D = null    ## zwłoki, które udaje (M5); null = przebranie stojące
var _nest := false           ## `corpse` to gniazdo CORPSES na stałe (M5); inaczej ciało `Y` zależne od przebrania (solo)
var y_body: Node2D = null    ## ciało Mimika `Y` (level.gd `_add_y_bodies`): leży w nim w solo
var _stand_body := Vector2.ZERO
var _stand_hurt := Vector2.ZERO
var grab_ready := 0.0        ## s okna, w którym cios jest chwytem (serwer)
var grab_victim: Node2D = null  ## chwycony gracz albo bot (serwer)
var grab_t := 0.0            ## s do końca chwytu
var grabs := 0               ## chwyty od początku misji (testy)
var _grab_team := 0.0        ## obrażenia od innych w trakcie chwytu
var _grab_dealt := 0         ## obrażenia zadane chwyconemu
var _view_grab := 0.0        ## s okna chwytu wg widoku (klient nie zna `grab_ready`: liczy od demaskacji, którą widzi)
var _seen_active := -1       ## ostatni widziany stan `active` (-1: jeszcze nie widziany — dołączający nie odgrywa cudzej demaskacji)
var morph_t := 0.0           ## s do końca przemiany (serwer)
var lope_t := 0.0            ## s zrywu (serwer)
var _morph_hit := false      ## następny cios kończy przemianę (klip `morph` zamiast chwytu)
var _view_since := -1.0      ## s od demaskacji widzianej w widoku; < 0 = udaje
var echo_t := -1.0           ## s do echa krzyku (serwer); < 0 = brak
var echoes := 0              ## echa od początku misji (testy, dziennik)
var _echo_from := Vector2.ZERO  ## skąd krzyknięto (dziennik `mimic_echo`)
var _echo_heard := 0.0       ## px drogi dźwięku krzyku
var _echo_female := false    ## krzyczała kobieta — echo jej głosem (VOICE_MOCAP_PLAN.md A2)
var _echo_view := 0.0        ## s drgnięcia w widoku (każdy peer, z `_mimic_echo`)
var last_echo := {}          ## ostatnie echo u tego peera: `pitch`, `lying` (testy)
var downed := false          ## serwer: leży jako powalony kolega (M9)
var _mode_t := 0.0           ## s do sprawdzenia przebrania (serwer)
var _down_flip := 1.0        ## kierunek twarzy przy kładzeniu się (serwer; po demaskacji wstaje w tę stronę)
var _view_downed := false    ## widok (każdy peer): leży albo wstaje jako powalony kolega
var down_timer := 0.0        ## widok: fałszywe odliczanie wykrwawiania — rusza, gdy lokalny gracz podejdzie, i staje na 0 s (prawdziwy by się odrodził)
var fake_revive := 0.0       ## widok: postęp podnoszenia lokalnego gracza (pasek nad nim)
var _label_model := ""       ## widok: model postaci udawanego kolegi
static var _forced := -2     ## --mimicdowned=0/1 (testy, zrzuty): wymusza przebranie bez co-op; -1 = co-op i losowanie

## Mimik-zwłoki (M5): leży w miejscu zwłok `cp` (level.gd przy budowie mapy, u każdego peera tak samo).
func become_corpse(cp: Node2D) -> void:
	corpse = cp
	_nest = true
	_lie(true)

func as_corpse() -> bool:
	return corpse != null

## Niskie ciało i strefa trafień leżącego (kule nad ciałem przelatują jak nad zwłokami); `false` — wymiary stojącego.
func _lie(on: bool) -> void:
	var cs := e.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		return
	var body := cs.shape as RectangleShape2D
	var hurt: RectangleShape2D = e._hit_shape
	if _stand_body == Vector2.ZERO:
		_stand_body = body.size
		_stand_hurt = hurt.size
	var bs := LYING if on else _stand_body
	var hs := LYING if on else _stand_hurt
	body.size = bs
	cs.position = Vector2(0.0, -bs.y * 0.5)
	if hurt != body:
		hurt.size = hs
		var hn = e.get_meta("hurt_shape") if e.has_meta("hurt_shape") else null
		if hn is CollisionShape2D:
			(hn as CollisionShape2D).position = Vector2(0.0, -hs.y * 0.5)

func reset() -> void:
	if grab_victim != null:
		_release("", false)
	grab_ready = 0.0
	grabs = 0
	morph_t = 0.0
	lope_t = 0.0
	_morph_hit = false
	if corpse != null:
		_lie(true)
	lure_t = 4.0
	calls = 0
	lit_s = 0.0
	_dark_s = 0.0
	_lit_ms = 0
	_label_t = 0.0
	echo_t = -1.0
	echoes = 0
	_echo_view = 0.0
	if not _nest:
		downed = false                         # `e._sp` wyzerował reset wroga — przebranie od nowa (gracze po wipe'ie stoją na starcie)
		if corpse != null:
			corpse = null
			_lie(false)
		if NoiseMgr.is_server() and e.is_inside_tree():
			_set_mode(want_mode(), false)
	_mode_t = MODE_EVERY

## Demaskacja: wpis w dzienniku (M0), krzyk, fala i chwila na zmianę postaci (zapowiedź), potem normalny pościg.
func on_wake() -> void:
	echo_t = -1.0                              # obudzony nie odpowiada już echem
	_log_reveal(String(e.wake_cause))
	if corpse != null:
		_lie(false)
		e._facing = -1.0 if bool(corpse.flip) else 1.0      # zwłoki leżą głową za plecami: wstaje przodem do stóp (corpse3d.gd `rise`)
	if e._sp == SP_CORPSE:
		e._sp = 0                              # ciało `Y` zostaje w `corpse` (wstawanie i strój w widoku), przebranie się skończyło
	elif downed:
		downed = false
		_lie(false)
		e._sp = 0
		e._facing = _down_flip                 # widok położył go z tym kierunkiem (view3d `_sync_downed`) — wstaje przodem do stóp
	NoiseMgr.add_noise(6.0, e.global_position, "enemy")
	if NoiseMgr.has_network():
		e._scream_fx.rpc()
	else:
		e._scream_fx()
	e._windup = MORPH_S
	e._windup_duration = e._windup
	e.winding = true
	grab_ready = GRAB_READY_S
	morph_t = MORPH_S
	_morph_hit = true

## `mimic_reveal` (MIMIC_PLAN.md M0): przyczyna, odległość do najbliższego człowieka, wołania przed demaskacją, rodzaj przebrania, czas światła.
func _log_reveal(cause: String) -> void:
	var best := INF
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		best = minf(best, (p as Node2D).global_position.distance_to(e.global_position))
	SessionLog.event("mimic_reveal", {"cause": cause, "dist": roundi(best) if is_finite(best) else -1, "calls": calls,
		"disguise": _disguise_id(), "lit": snappedf(lit_s, 0.1), "pos": SessionLog.xy(e.global_position)})

## Rodzaj przebrania do dziennika: corpse, downed (M9), stand.
func _disguise_id() -> String:
	return ("corpse" if _nest else "ycorpse") if corpse != null else ("downed" if downed else "stand")

## Leży (zwłoki albo powalony kolega): niskie ciało, demaskacja z bliska tylko tuż nad nim, dłuższe światło, stłumione echo.
func lying() -> bool:
	return corpse != null or downed

# ---------------------------------------------------------------- powalony kolega (M9)

## Wymuszenie z wiersza poleceń (`--mimicdowned=0/1`); -1 = bez wymuszenia.
static func forced() -> int:
	if _forced == -2:
		_forced = -1
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--mimicdowned="):
				_forced = clampi(int(a.substr("--mimicdowned=".length())), 0, 1)
	return _forced

static func set_forced(v: int) -> void:
	_forced = v

func _humans() -> int:
	var n := 0
	for p in e.get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.is_queued_for_deletion():
			n += 1
	return n

## Przebranie Mimika `Y`: „corpse” — sam człowiek (bot się nie liczy) leży w swoim ciele; w co-op „downed” (z ziarna mapy, DOWNED_CHANCE)
## albo „stand”. `--mimicdowned=1` wymusza powalonego, `0` — stojącego (testy).
func want_mode() -> String:
	if _nest or not e.is_inside_tree():
		return "nest"
	if forced() >= 0:
		return "downed" if forced() == 1 else "stand"
	if _humans() < 2:
		return "corpse" if y_body != null else "stand"
	return "downed" if want_downed() else "stand"

## Czy w co-op Mimik `Y` leży jako powalony kolega (z ziarna mapy, to samo przez całą mapę) albo z wymuszenia.
func want_downed() -> bool:
	if _nest or not e.is_inside_tree():
		return false
	if forced() >= 0:
		return forced() == 1
	if _humans() < 2:
		return false
	var lvl: Node = e.get_tree().get_first_node_in_group("level")
	var sd: int = int(lvl.get("mimic_seed")) if lvl != null and lvl.get("mimic_seed") != null else 0
	return float(hash([sd, String(e.name)]) & 0xffff) / 65536.0 < DOWNED_CHANCE

func _human_near(px: float) -> bool:
	for p in e.get_tree().get_nodes_in_group("players"):
		if not p.is_bot and (p as Node2D).global_position.distance_to(e.global_position) < px:
			return true
	return false

## Bieżące przebranie (dziennik, testy): nest, corpse, downed, stand.
func mode() -> String:
	if _nest:
		return "nest"
	if corpse != null and not e.active:
		return "corpse"
	return "downed" if downed else "stand"

## Serwer: przełącza przebranie Mimika `Y` (`want_mode`).
func _set_mode(m: String, log_it := true) -> void:
	if m == "nest" or m == mode() or e.active:
		return
	if m == "corpse":
		if downed:
			_set_downed(false, false)
		corpse = y_body
		_lie(true)
		e._sp = SP_CORPSE
		if log_it:
			SessionLog.event("mimic_disguise", {"disguise": "corpse", "humans": _humans(), "pos": SessionLog.xy(e.global_position)})
		return
	var was_corpse := corpse != null
	if was_corpse:
		corpse = null
		_lie(false)
		e._sp = 0
	_set_downed(m == "downed", log_it)
	if was_corpse and m == "stand" and log_it:
		SessionLog.event("mimic_disguise", {"disguise": "stand", "humans": _humans(), "pos": SessionLog.xy(e.global_position)})

## Serwer: kładzie się jako powalony kolega albo wstaje do przebrania stojącego.
func _set_downed(on: bool, log_it := true) -> void:
	if on == downed or e.active:
		return
	downed = on
	_lie(on)
	e._sp = SP_DOWNED if on else 0
	if on:
		_down_flip = e._facing if e._facing != 0.0 else 1.0
	if log_it:
		SessionLog.event("mimic_disguise", {"disguise": _disguise_id(), "humans": _humans(), "pos": SessionLog.xy(e.global_position)})

## Co MODE_EVERY: co-op się zaczął albo skończył — zmiana przebrania, gdy nikt nie patrzy z bliska.
func _tick_mode(delta: float) -> void:
	if _nest:
		return
	_mode_t -= delta
	if _mode_t > 0.0:
		return
	_mode_t = MODE_EVERY
	var want := want_mode()
	if want != mode() and not _human_near(DOWNED_CLEAR_PX):
		_set_mode(want)

## Serwer: gracz `peer_id` podnosi powalonego kolegę dłużej niż REVIVE_GRAB_S (player.gd → enemy.gd `mimic_revive_request`) — demaskacja.
func revive_by(peer_id: int) -> bool:
	if e.active or not downed or not e.alive:
		return false
	for p in e.get_tree().get_nodes_in_group("players"):
		if String(p.name) != str(peer_id) or p.is_bot or p.dead:
			continue
		var d: Vector2 = (p as Node2D).global_position - e.global_position
		if absf(d.x) < Player.REVIVE_RANGE * REVIVE_SLACK and absf(d.y) < 30.0:
			e.wake("revive")
			return true
	return false

## Widok (każdy peer): leży jako powalony kolega i jeszcze się nie zdemaskował.
func downed_view() -> bool:
	return _view_downed and not e.active and e.alive

## Kryptonim udawanego kolegi w podpowiedzi podnoszenia (HUD) — udając bota, tak jak przy prawdziwym botem („the bot”).
func down_name() -> String:
	_refresh_label()
	return "the bot" if _label_col == Player.BOT_COLOR else _label

## Plakietka powalonego (world_bars.gd `_draw_down`, jak player.gd `plate_state`): kryptonim, odliczanie, pasek podnoszenia; pusta = brak.
func down_state() -> Dictionary:
	if not downed_view():
		return {}
	_refresh_label()
	return {"dead": true, "name": _label, "col": _label_col, "taken": false, "timer": ceili(down_timer), "revive": fake_revive}

## Lokalny gracz podnosi go (player.gd): postęp 0..1 na pasku nad nim.
func set_revive_progress(v: float) -> void:
	fake_revive = clampf(v, 0.0, 1.0)

func scream_pitch() -> float:
	return 0.85

## Krzyk gracza w zasięgu (M8): przebrany nie budzi się i nie rusza do źródła, tylko po ECHO_DELAY odpowiada echem; obudzony słyszy jak każdy.
func hears_scream(pos: Vector2, heard: float) -> bool:
	if e.active:
		return false
	if echo_t < 0.0:
		echo_t = ECHO_DELAY + randf_range(-ECHO_JITTER, ECHO_JITTER)
		_echo_from = pos
		_echo_heard = heard
		_echo_female = Player.female_at(e.get_tree(), pos)
	return true

## Przebrany nie budzi się z watahą (krzyk czy hałas obudzi Trzoska obok, a test „kto to?” ma działać i przy innych wrogach); obudzony budzi
## sąsiadów jak każdy (rdzeń pyta obie strony — enemy.gd `wake`).
func sibling_wake_ok(_other) -> bool:
	return e.active

## Odlicza echo i je wysyła (serwer, w tiku uśpionego).
func _tick_echo(delta: float) -> void:
	if echo_t < 0.0:
		return
	echo_t -= delta
	if echo_t > 0.0:
		return
	echo_t = -1.0
	echoes += 1
	var low := lying()
	if NoiseMgr.has_network():
		e._mimic_echo.rpc(low, _echo_female)
	else:
		e._mimic_echo(low, _echo_female)
	SessionLog.event("mimic_echo", {"disguise": _disguise_id(), "dist": roundi(_echo_heard), "n": echoes,
		"from": SessionLog.xy(_echo_from), "pos": SessionLog.xy(e.global_position)})

## Echo na każdym peerze (enemy.gd `_mimic_echo`): drgnięcie leżącego w widoku.
func echo_fx(pitch: float, lying: bool) -> void:
	last_echo = {"pitch": pitch, "lying": lying}
	_echo_view = ECHO_VIEW_S

## Zamaskowany stoi jak żywy kolega, nie „śpi"; nie przygasa i ma etykietę gracza.
func anim(a: String, _moving: bool) -> String:
	return "idle" if not e.active else a

func disguised() -> bool:
	return true

## Snop latarki (M2): demaskuje dopiero po LIGHT_REVEAL_S ciągłego światła; po DARK_RESET_S ciemności licznik od zera.
## Sprawdzenia przychodzą co ok. 0,12 s (enemy.gd `_check_wake`), czas między nimi liczy zegar.
func light_wakes(lit: bool) -> bool:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _lit_ms) / 1000.0, 0.0, 0.3) if _lit_ms > 0 else 0.0
	_lit_ms = now
	if lit:
		lit_s += dt
		_dark_s = 0.0
	else:
		_dark_s += dt
		if _dark_s >= DARK_RESET_S:
			lit_s = 0.0
	return lit_s >= (CORPSE_LIGHT_S if lying() else LIGHT_REVEAL_S)

## Leżący budzi się dopiero, gdy ktoś przejdzie tuż nad nim (OVER_PX); stojący — przy zwykłym `wake_near`.
func near_mult() -> float:
	return OVER_PX / maxf(float(e._def["wake_near"]), 1.0) if lying() else 1.0

## Alarm Podsłuchacza budzi go dopiero po demaskacji — przebrany czeka na gracza (w grze alarm budził Mimika-zwłoki, zanim gracz podszedł).
func alarm_wakes() -> bool:
	return e.active

## Okno kontry: w czasie przemiany obrażenia × MORPH_DMG.
func damage_mult() -> float:
	return MORPH_DMG if morph_t > 0.0 else 1.0

## Zryw po przemianie.
func speed_mult() -> float:
	return LOPE_SPEED / maxf(float(e._def["speed"]), 1.0) if lope_t > 0.0 else 1.0

## Zabity Mimik-zwłoki zostawia łup ciała, które udawał.
func on_death() -> void:
	if grab_victim != null:
		_release("death")
	if corpse != null and is_instance_valid(corpse) and corpse.has_method("drop_mimic_loot"):
		corpse.drop_mimic_loot()

## Widok (każdy peer): czy jeszcze udaje, i snop na nim — odwraca twarz, połysk oczu, oddech.
func present(delta: float) -> void:
	var act := 1 if e.active else 0
	if act == 1 and _seen_active == 0:
		_view_grab = GRAB_READY_S
		_view_since = 0.0
	elif act == 1 and _seen_active == -1:
		_view_since = 99.0                     # dołączający widzi Mimika już po przemianie
	elif act == 0:
		_view_since = -1.0
	elif _view_since >= 0.0:
		_view_since += delta
	_seen_active = act
	if act == 0 and not _nest and not NoiseMgr.is_server():
		var want_c: Node2D = y_body if e._sp == SP_CORPSE else null      # klient: ciało `Y` z replikowanego `_sp` (solo)
		if want_c != corpse:
			corpse = want_c
			_lie(want_c != null)
	var dn: bool = act == 0 and e.alive and e._sp == SP_DOWNED
	if dn and not _view_downed:
		down_timer = Player.BLEED_TIME * Difficulty.m("bleed")       # jak prawdziwy powalony: odliczanie od pełnego wykrwawiania
	if act == 0:
		_view_downed = dn                      # po demaskacji zostaje do wstania (`rise`), restart liczy od nowa
	if not e.alive:
		_view_downed = false
	if dn:
		if e._local_player_pos().distance_to(e.global_position) > DOWNED_CLEAR_PX:
			down_timer = Player.BLEED_TIME * Difficulty.m("bleed")   # nikt nie patrzy: przy podejściu odliczanie rusza od pełnego (jak świeżo powalony)
		else:
			down_timer = maxf(0.0, down_timer - delta)       # staje na 0 s — prawdziwy kolega by się wtedy odrodził (sygnał)
		if not e.is_in_group(DOWNED_GROUP):
			e.add_to_group(DOWNED_GROUP)
	elif e.is_in_group(DOWNED_GROUP):
		e.remove_from_group(DOWNED_GROUP)
		fake_revive = 0.0
	_view_grab = maxf(0.0, _view_grab - delta)
	_echo_view = maxf(0.0, _echo_view - delta)
	_lit_t -= delta
	if _lit_t > 0.0:
		return
	_lit_t = LIT_EVERY
	var on: bool = not e.active and e.alive and e.is_inside_tree() \
			and Lights.flashlight_on(e.global_position + Vector2(0, -6), e.get_tree(), e.get_world_2d().direct_space_state) != null
	_lit = 1.0 if on else 0.0

func view_extra(d: Dictionary) -> void:
	var morphing: bool = _morph_hit if NoiseMgr.is_server() else (_view_since >= 0.0 and _view_since < MORPH_S + 0.2)
	if e.winding and morphing:
		d["motion_action"] = "morph"                # przemiana (M7)
	elif (grab_ready if NoiseMgr.is_server() else _view_grab) > 0.0 and e.winding:
		d["motion_action"] = "grab_hold"            # zapowiedź chwytu; klient liczy okno od demaskacji, którą widzi (`present`)
	d["since_reveal"] = _view_since if e.alive else -1.0
	var low := corpse != null or _view_downed
	d["rise"] = _view_since / RISE_S if low and e.alive and _view_since >= 0.0 and _view_since < RISE_S else -1.0
	d["from_corpse"] = low
	if _view_downed and _label_model == "":
		_refresh_label()
	d["outfit_model"] = String(corpse.outfit) if corpse != null else (_label_model if _view_downed else "")
	d["as_downed"] = downed_view()            # widok rysuje go jako powalonego kolegę (view3d `_sync_downed`), nie jako wroga (M9)
	d["disguised"] = not e.active
	d["lit"] = _lit
	d["echo"] = _echo_view / ECHO_VIEW_S if not e.active else 0.0      # 1 → 0: drgnięcie leżącego przy echu (M8)
	d["as_corpse"] = corpse != null and not e.active and e.alive          # widok rysuje go jako zwłoki (view3d `_sync_corpses`), nie jako wroga

func disguise_label() -> String:
	if e.active or corpse != null or _view_downed:
		return ""                              # powalony: kryptonim rysuje plakietka powalonego (`down_state`)
	_refresh_label()
	return _label

func disguise_color() -> Color:
	return _label_col

## Imię jak u gracza, ale bez plakietki życia (zdradza go). W co-opie kryptonim innego człowieka z drużyny (PROFILES_PLAN.md D2) —
## każdy widzi imię kolegi, nie swoje; sam — inna postać z ekranu OPERATORZY, a bez niej bot albo kryptonim spoza drużyny.
## Kolor jak imię udawanego gracza (MIMIC_PLAN.md M1).
func _refresh_label() -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if _label != "" and now < _label_t:
		return
	_label_t = now + LABEL_EVERY
	var pick := int(e.get_instance_id() & 0x7fffffff)
	var mates: Array = []
	var bot: Node = null
	for p in e.get_tree().get_nodes_in_group("players"):
		if p.is_queued_for_deletion():
			continue
		if p.is_bot:
			bot = p
		elif not p.is_multiplayer_authority():
			mates.append(p)
	if not mates.is_empty():
		mates.sort_custom(func(a: Node, b: Node) -> bool: return int(a.display_id) < int(b.display_id))
		var m: Node = mates[pick % mates.size()]
		_label = String(m.label())
		_label_col = m._body_color()
		_label_model = _model_of(m)
		return
	var others: Array = []
	if Characters.persist:
		for c in Characters.list():
			var n := Characters.display_clean(String((c as Dictionary).get("name", "")))
			if String(c["id"]) != Characters.active_id and n != "":
				others.append(n)
	var col: Color = Player.BODY_COLORS[1 + pick % (Player.BODY_COLORS.size() - 1)]
	_label_model = DOWNED_MODEL % "male_scav"
	if not others.is_empty():
		_label = String(others[pick % others.size()])
		_label_col = col
	elif bot != null:
		_label = String(bot.label())
		_label_col = Player.BOT_COLOR
		_label_model = _model_of(bot)
		return
	else:
		_label = String(FALLBACK_NAMES[pick % FALLBACK_NAMES.size()])
		_label_col = col

## Głos wołania (każdy peer): płeć kolegi, którego Mimik udaje u tego peera (`_label_model`; VOICE_MOCAP_PLAN.md A2).
func call_voice() -> String:
	_refresh_label()
	return Player.voice_key_gender(_label_model.get_file().begins_with("female_"), "player_hurt")

## Głos echa krzyku (M8): płeć tego, kto krzyknął (serwer ustala ją w `hears_scream`, peery dostają w RPC).
func echo_voice(female: bool) -> String:
	return Player.voice_key_gender(female, "player_hurt")

## Plik modelu postaci gracza (jak player.gd `_char3d_name` → char3d.gd `set_look`); brak pliku — mundur patrolu.
static func _model_of(p: Node) -> String:
	var path := DOWNED_MODEL % String(p._char3d_name())
	return path if ResourceLoader.exists(path) else DOWNED_MODEL % "male_scav"

## Zamaskowany Mimik woła o pomoc krzykiem kolegi (ten sam dźwięk co krzyk gracza [G]) z rozmytym kierunkiem i trzaskiem radia,
## gdy ktoś jest w zasięgu słuchu, ale jeszcze nie przy nim — wabi do zasadzki.
func asleep_lod() -> bool:
	return false

func tick_asleep(delta: float) -> void:
	_tick_echo(delta)
	_tick_mode(delta)
	if corpse != null:
		return                                  # zwłoki nie wołają
	lure_t -= delta
	if lure_t > 0.0:
		return
	var p = e._nearest_player()
	var d: float = p.global_position.distance_to(e.global_position) if p != null else INF
	if d < CALL_R.y and d > CALL_R.x:
		lure_t = randf_range(CALL_GAP.x, CALL_GAP.y)
		calls += 1
		var at: Vector2 = e.global_position + Vector2(randf_range(-CALL_BLUR, CALL_BLUR), 0.0)
		if NoiseMgr.has_network():
			e._mimic_call.rpc(at)
		else:
			e._mimic_call(at)
	else:
		lure_t = 1.0

# ---------------------------------------------------------------- chwyt z przebrania (M6)

func tick_prelude(delta: float) -> void:
	grab_ready = maxf(0.0, grab_ready - delta)
	if morph_t > 0.0:
		morph_t -= delta
		if morph_t <= 0.0:
			lope_t = LOPE_S
	else:
		lope_t = maxf(0.0, lope_t - delta)
		if not e.winding:
			_morph_hit = false                 # cios przemiany rozstrzygnięty bez `strike` (np. Mimik zginął w przemianie)

## Klip kontaktu: koniec przemiany, chwyt w oknie po demaskacji, potem zwykły lżejszy cios (`EnemyMotion.KIND`).
func attack_action() -> String:
	if _morph_hit:
		return "morph"
	return "grab_hold" if grab_ready > 0.0 else ""

func strike(pp: Node2D) -> bool:
	_morph_hit = false
	if grab_ready <= 0.0:
		return false
	grab_ready = 0.0
	var v: Node2D = pp if _grabbable(pp, 6.0) else null
	if v == null and pp == null:
		v = _victim_near()                     # przemiana bez celu: chwyta tego, kto stoi przy nim
	if v == null:
		return false
	_begin_grab(v)
	return true

func _grabbable(p: Node2D, slack: float) -> bool:
	return p != null and is_instance_valid(p) and not p.is_queued_for_deletion() and not p.dead and not p.grabbed and not p.taken 			and e._in_reach(p, slack) and not e._wall_between(p)

func _victim_near() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in e.get_tree().get_nodes_in_group("players"):
		var p := n as Node2D
		if not _grabbable(p, GRAB_SLACK):
			continue
		var d := absf(p.global_position.x - e.global_position.x)
		if d < best_d:
			best_d = d
			best = p
	return best

func _begin_grab(v: Node2D) -> void:
	grab_victim = v
	grab_t = GRAB_S
	_grab_team = 0.0
	_grab_dealt = 0
	grabs += 1
	e._sp = SP_HOLD
	var dx: float = v.global_position.x - e.global_position.x
	if absf(dx) > 0.1:
		e._facing = signf(dx)
	e.velocity.x = 0.0
	v.deliver_grab(true, v.global_position)
	_grab_hit(v)

func _grab_hit(v: Node2D) -> void:
	if not is_instance_valid(v) or v.dead:
		return
	var n: int = e._scaled_damage(GRAB_DMG)
	v.deliver_hit(n, e.global_position, e.kind, true)
	_grab_dealt += n

## Trzyma chwyconego w miejscu; po GRAB_S drugi cios i puszczenie. Leżący (pierwszy cios go powalił) wypada z chwytu.
func tick_phase(delta: float, _target: Node2D) -> bool:
	if grab_victim == null:
		return false
	var v := grab_victim
	if not is_instance_valid(v) or v.is_queued_for_deletion() or v.dead:
		_release("down")
		return false
	e.velocity.x = 0.0
	grab_t -= delta
	if grab_t <= 0.0:
		_grab_hit(v)
		_release("time")
	return true

## Uwolnienie: cios wręcz chwyconego, ogłuszenie, obrażenia od innych (MIMIC_PLAN.md M6).
func took_hit(info: Dictionary, dmg: float) -> void:
	if grab_victim == null or e.hp <= 0.0 or not is_instance_valid(grab_victim):
		return
	var by := int(info.get("shooter", -1))
	var mine := by == int(grab_victim.player_id)
	if mine and String(info.get("type", "")) == "melee":
		_release("melee")
	elif float(info.get("stun", 0.0)) >= e.WINDUP_INTERRUPT_STUN:
		_release("stun")
	elif not mine:
		_grab_team += dmg
		if _grab_team >= GRAB_FREE_DMG:
			_release("team")

## Puszcza chwyconego; `how`: time (trzymał do końca), melee / stun / team (uwolniony), down, death. Pusty `how` (reset) bez wpisu w dzienniku.
func _release(how: String, recoil := true) -> void:
	var v := grab_victim
	grab_victim = null
	e._sp = 0
	if v != null and is_instance_valid(v):
		v.deliver_grab(false, Vector2.ZERO)
	if how == "":
		return
	e._cd = maxf(e._cd, GRAB_AFTER_CD)
	if recoil and how != "death":
		e.velocity.x = -e._facing * GRAB_RECOIL
	var ok := v != null and is_instance_valid(v)
	SessionLog.event("mimic_grab", {"who": "P%d" % int(v.display_id) if ok else "", "bot": bool(v.is_bot) if ok else false,
		"freed": how in ["melee", "stun", "team"], "how": how, "dmg": _grab_dealt, "team": roundi(_grab_team),
		"held": snappedf(GRAB_S - maxf(grab_t, 0.0), 0.1), "pos": SessionLog.xy(e.global_position)})
