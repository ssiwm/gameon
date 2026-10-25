extends Node
## Kontroler broni gracza — węzeł „Weapons” pod Player (i botem). Cała logika broni
## poza samym ruchem postaci: zestaw i zmiana, magazynek i przeładowanie, rytm ognia,
## rozgrzanie i rozrzut, ładowanie szyny, promień/płomień, cios, podnoszenie broni.
## Dane bierze z weapons.gd, obrażenia zadaje przez combat.gd, wizualia robi weapon_view.gd.
##
## SIEĆ (GDD §19): właściciel postaci jest autorytetem nad swoim magazynkiem i celowaniem
## (kooperacja — zaufanie jak przy pozycji), a SERWER nad skutkiem strzału:
##   1. strzelec natychmiast gra dźwięk, rozbłysk, odrzut i leci jego KOSMETYCZNA kula
##      (predykcja — brak opóźnienia o RTT),
##   2. wysyła do serwera {wylot, kierunek, broń, seed rozrzutu},
##   3. serwer (po prostej walidacji tempa i miejsca) spawnuje kulę AUTORYTATYWNĄ i liczy
##      trafienia, a pozostałym peerom wysyła kosmetyczne kopie (ten sam seed → ten sam rozrzut).
## Promień i płomień nie mają RPC na tyknięcie: serwer czyta zreplikowane `w_firing`,
## `aim_dir` i pozycję gracza (50 ms) i sam liczy obrażenia.

const Weapons := preload("res://scripts/weapons.gd")
const WeaponDef := preload("res://scripts/weapon_def.gd")
const Combat := preload("res://scripts/combat.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Lights := preload("res://scripts/lights.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Motion := preload("res://scripts/weapon_motion.gd")

enum State { READY, DRAW, RELOAD, CHARGE, MELEE }

const BUFFER := 0.12              ## s — klik tuż przed końcem cooldownu nie przepada
const MELEE_HIT_AT := 0.45        ## ułamek czasu ciosu, w którym liczymy trafienie
const GRANT_TIMEOUT := 1.5        ## s oczekiwania na naboje z serwera, potem przerwanie
const MUZZLE_TOLERANCE := 40.0    ## px — dalszy wylot niż to serwer koryguje do pozycji gracza
const RATE_CAP := 2.5             ## „zapas” strzałów po lagu sieci (token bucket)
const FX_REPORT_EVERY := 0.2      ## efekt trafienia promieniem/płomieniem nie częściej niż co tyle
const NOISE_RELOAD := 0.25
const NOISE_DRY := 0.12
const FIRE_DROP_MAX := 40.0       ## px w dół od końca płomienia, w których szukamy podłogi
## Obsługa broni (GUNSMITH_PLAN.md etap 3a, od 1.7.324; ustawienie „Weapon handling”, Settings.realistic_handling).
## Podrzut: przy celowaniu myszą każdy strzał unosi lufę (a z nią celownik) zamiast losowo poszerzać stożek — gracz może ją ściągać w dół.
## Wielkość z danych rozrzutu broni (części, które zmniejszają rozrzut serii, zmniejszają też podrzut). Klawiatura, pad i boty zostają przy rozrzucie.
const CLIMB_K := 2.2              ## podrzut na strzał = bloom_per_shot × K (°)
const CLIMB_MAX_K := 2.0          ## górna granica podrzutu = bloom_max × K
const CLIMB_RECOVER_K := 0.6      ## powrót lufy = bloom_decay × K (°/s)
const CLIMB_JITTER := 0.25        ## ± tyle (ułamek) zmienia się podrzut kolejnych strzałów — przewidywalny, ale nie mechaniczny
const CLIMB_CROUCH := 0.6         ## kucanie: mniejszy podrzut
## Oparcie (§5.2): broń leży na krawędzi skrzyni, murku, kładki tuż przed dłonią — mniejszy podrzut (i narastanie rozrzutu) oraz rozrzut.
const BRACE_CLIMB := 0.4
const BRACE_SPREAD := 0.6
const BRACE_PROBE := [0.45, 0.75, 1.0, 1.4]   ## gdzie wzdłuż broni szukamy krawędzi podparcia (0 = chwyt, 1 = wylot; łoże, wylot i tuż za nim)
const BRACE_DEPTH := [1.5, 3.0, 4.5, 6.0]   ## px pod linią lufy, w których krawędź jeszcze podpiera broń
const BRACE_MASK := 1 | 16 | 32             ## bryły, kładki, skrzynie i beczki (prop.gd)
## Gorąca lufa (§5.5, etap 3b, od 1.7.325; też tylko w obsłudze realistycznej): temperatura z WeaponDef.barrel_heat, stygnie z pełnej w 45 s.
const BARREL_COOL := 1.0 / 45.0
const HOT_SPREAD := 0.4           ## rozrzut (bazowy + dodatkowy) × (1 + 0,4·t²) — czuć dopiero przy długim ogniu
const HOT_CAN := 0.5              ## tłumik: hałas × (1 + 0,5·t) — rozgrzana puszka głośnieje
const HOT_SMOKE := 0.5            ## od tej temperatury z lufy idzie dym (view3d.gd), od HOT_HAZE — falowanie powietrza
const HOT_HAZE := 0.6
## Dwa przeładowania (§5.3, etap 3c, od 1.7.326; obsługa realistyczna, broń z WeaponDef.mag_drop): [R] krótko — szybkie: magazynek leci na ziemię
## z resztkami (wracają do zapasu dopiero po podniesieniu — kucnij nad nim); [R] przytrzymane — taktyczne: +0,4 s, resztki zostają w zapasie.
const MAG_OUT_AT := 0.25          ## s od początku przeładowania: magazynek wychodzi z gniazda — wtedy rozstrzyga się, czy [R] jest wciąż wciśnięte
const TAC_EXTRA := 0.4
const MAG_DROP_NOISE := 0.15      ## magazynek uderza o ziemię
const MAG_MAX := 16               ## tyle magazynków najwyżej leży na mapie (serwer usuwa najstarsze)
## Stan techniczny i zacięcia (§6, etap 4a, od 1.7.328; ustawienie „Weapon reliability”, Settings.reliability_mult): broń gracza zużywa się
## z każdym strzałem (Profile.cond), a poniżej JAM_FROM % zaczyna się zacinać. Zacięcie to chwila napięcia, nie kara: zawsze usuwa je [R].
const WEAR_SHOT := 0.06           ## % stanu na strzał (× WeaponDef.wear × ustawienie); od 1.7.347 ×3 — M-83 traci ok. 15 % na misję, zaniedbany zaczyna się zacinać
const WEAR_HOT := 3.0             ## lufa gorętsza niż HOT_WEAR_AT — zużycie ×3
const HOT_WEAR_AT := 0.8
const WEAR_CAN := 1.5             ## tłumik: gazy cofają się do mechanizmu
## Części eksploatacyjne (WORKSHOP_PLAN.md W2, od 1.7.350): % zużycia na strzał × WeaponDef.wear × ustawienie; lufę gorąca lufa zużywa ×WEAR_HOT.
## M-83: lufa ok. 5 % na misję (~20 misji, szybciej przy długim ogniu), sprężyny ok. 6 % (po ~10 misjach czyszczenie nie dobija do 70 %).
const WEAR_BARREL := 0.02
const WEAR_SPRINGS := 0.025
## Masa ekwipunku (WORKSHOP_PLAN.md W5, od 1.7.356; tylko obsługa realistyczna): suma mas noszonej broni z częściami gracza (dwie główne,
## pistolet, broń biała) względem fabrycznego zestawu startowego (mass_ref, ok. 10 kg — z nim nic się nie zmienia). Każdy kilogram ponad to:
## bieg +5 % hałasu i −1,2 % tempa; lżej — odwrotnie.
const MASS_NOISE := 0.05
const MASS_SPEED := 0.012
const MASS_NOISE_RANGE := Vector2(0.8, 1.5)
const MASS_SPEED_RANGE := Vector2(0.9, 1.05)
const BARREL_SPREAD := 0.6        ## zużyta lufa: rozrzut (bazowy + dodatkowy) × (1 + 0,6·z²), z = zużycie 0..1 — przy 50 % ×1,15, przy 100 % ×1,6
const JAM_FROM := 70.0            ## % stanu, poniżej którego broń zaczyna się zacinać…
const JAM_SPAN := 40.0            ## …a przy JAM_FROM − JAM_SPAN (30 %) zacina się raz na JAM_ODDS strzałów
const JAM_ODDS := 150.0
const JAM_SAFE_SHOTS := 3         ## nigdy w pierwszych strzałach magazynka
const JAM_GAP_MS := 10000         ## nigdy dwa razy w 10 s
const CLEAR_TIME := 0.6           ## s — przeładowanie rączką (niewypał, zacięcie łuski)
const DOUBLE_FEED_EXTRA := 1.0    ## s — podwójne podanie: magazynek wyjąć, przeładować rączką, włożyć
const NOISE_CLEAR := 0.18
const DIRTY_AT := 40.0            ## % — HUD ostrzega, że broń jest brudna
## Etap 4b (od 1.7.329): zużycie od otoczenia i upadku, awarie broni eksperymentalnej.
const WEAR_WATER := 5.0           ## % — wejście w wodę (brodzenie) moczy całą noszoną broń…
const WEAR_MUD := 10.0            ## …a błoto ją zapycha
const WEAR_DOWN := 3.0            ## % — upadek (gracz leży) z bronią w rękach
const WADE_GAP := 20.0            ## s — ta sama powierzchnia zużywa broń najwyżej raz na tyle (brnięcie tam i z powrotem to jedno zamoczenie)
const FAULT_TICK := 0.1           ## LR-7: szansa przegrzania ogniwa na tik wiązki = szansa zacięcia × to (10 tików na sekundę)
const ARC_MULT := 5.0             ## SPECTER-1: szansa przebicia kondensatora na strzał = szansa zacięcia × to (strzałów jest mało)
const OVERHEAT_PAUSE := 1.0       ## s — przegrzane ogniwo LR-7 stygnie
const ARC_SHOW := 1.5             ## s — komunikat o przebiciu kondensatora
## Wprawa (GUNSMITH_PLAN §7.3, etap 5a, od 1.7.330): trafienia i zabójstwa z danej broni dają punkty (Profile.mastery, osobno dla gracza
## i broni), 5 stopni. Każdy stopień: −2 % czasu przeładowania, dobycia i podrzutu (narastania rozrzutu), −4 % usuwania zacięcia —
## na piątym −10 % / −20 %. Wyszkolenie, nie supermoc; działa tylko u człowieka (boty bez wprawy).
const MASTERY_PTS := {0: 1, 1: 2, 2: 5, 3: 1}     ## Arsenal.Confirm → punkty: HIT 1, CRIT 2, KILL 5, ARMOR 1
const MASTERY_STEP := 0.02
const MASTERY_CLEAR_STEP := 0.04
const ROMAN := ["0", "I", "II", "III", "IV", "V"]

signal shot(w: int)
signal jam_started(w: int, kind: String)        ## „misfire” | „stovepipe” | „double”
signal reload_started(w: int)
signal dry_fired(w: int)
signal weapon_changed(w: int)
signal fire_mode_changed(w: int, burst: bool)
signal melee_swung(w: int)
signal ammo_changed(w: int, t: int)        ## gracz wybrał typ naboju na następny magazynek (klawisz Z)

var player: CharacterBody2D

# --- zestaw (właściciel; `kit` w graczu replikuje go reszcie)
var loadout: Array[int] = [Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_SIDEARM]
var melee_id := Weapons.START_MELEE
var slot := 0
var inspect_item: Node2D               ## lokalnie: broń w oględzinach ([H]; widok z oczu gracza i panel HUD)
var inspect_slot := 0                  ## docelowy slot broni głównej w oględzinach
var _inspect_hp := 0.0                 ## zdrowie w chwili otwarcia oględzin (spadek je zamyka)
var mags: Dictionary = {}
var burst_on: Dictionary = {}     ## id broni → true: wybrany tryb serii (klawisz B; lokalnie, serwer go nie potrzebuje)
var loaded: Dictionary = {}       ## id broni → typ naboju w magazynku (ammo.gd; brak wpisu = zwykły) — właściciel magazynka, jak `mags`
var want_ammo: Dictionary = {}    ## id broni → typ wybrany na NASTĘPNY magazynek (klawisz Z); wymiana zachodzi przy przeładowaniu

# --- stan
var state: int = State.READY
var state_t := 0.0
var charge := 0.0                 ## 0..1 (szyna)
var firing := false               ## promień/płomień w toku
var bloom := 0.0                  ## ° dodatkowego rozrzutu od serii
var climb := 0.0                  ## ° uniesienia lufy od odrzutu (podrzut; tylko celowanie myszą i obsługa realistyczna)
var braced := false               ## broń oparta o krawędź przeszkody (lokalnie, co klatkę — check_brace)
var reload_held := false          ## [R] wciśnięte (lokalnie, co klatkę; testy ustawiają sim_reload_hold)
var sim_reload_hold := false
var tactical := false             ## bieżące przeładowanie jest taktyczne (resztki zostają)
var dropped_mags := 0             ## ile magazynków z resztkami gracz upuścił (podpowiedź o podnoszeniu)
var _rl_out := -1.0               ## s do wyjęcia magazynka (< 0 — rozstrzygnięte albo nie dotyczy)
var jams: Dictionary = {}         ## id broni → zacięcie czekające na usunięcie: "misfire" | "stovepipe" | "double"
var sim_jam := ""                 ## testy: następna próba strzału kończy się tym zacięciem
var jam_count := 0                ## ile zacięć miał gracz (podpowiedź)
var clearing := false             ## trwa usuwanie zacięcia (stan RELOAD)
var _shots_mag: Dictionary = {}   ## id broni → strzały od ostatniego przeładowania
var _last_jam_ms := -100000
var fault_count := 0              ## awarie broni eksperymentalnej (testy)
var sim_fault := ""               ## testy: następny tik / strzał broni eksperymentalnej kończy się tą awarią
var _fault_t := 0.0               ## s do końca przerwy po awarii (wpis „overheat” / „arc” w `jams` znika razem z nią)
var _fault_w := -1
var _wade_t: Dictionary = {}      ## powierzchnia → s do ponownego zużycia od niej
var recoil := 0.0                 ## 0..1 — wizualne cofnięcie broni (widok)
var cd := 0.0
var melee_total := 0.35
var ammo_enabled := true          ## boty mają nieskończoną amunicję
## Strzelnica FPP (RANGE_FPS_PLAN.md, scripts/range3d/fp_mode.gd): obiekt z `range_shot(d, seed, extra)` i `braced()` — przejmuje strzał
## (zamiast pocisku 2D promień w tunelu 3D) i oparcie. Cała reszta (magazynek, przeładowania, zacięcia, lufa, podrzut) liczy się jak na misji.
var range_sink: Object = null
var practice := false             ## amunicja ćwiczebna (strzelnica): przeładowanie nie bierze naboi z zapasu, strzał nie zużywa broni
var _mass_sig := ""               ## podpis ekwipunku, dla którego policzono `_mass` (kit_mass)
var _mass := 0.0
var range_fit := {}               ## strzelnica: próbny montaż części (id broni → kod fit), także części jeszcze nieodblokowanych; tylko lokalnie
                                  ## (strzał idzie do range_sink, nie do serwera) i znika przy wyjściu (range_restore)

## Hooki testów headless (--weapontest): symulowany spust. W grze zawsze false.
var sim_fire := false
var sim_press := false
## Licznik strzałów przyjętych przez serwer (test limitu tempa).
var srv_shots := 0
var srv_last_build := -1          ## kod `build` ostatniego strzału przyjętego przez serwer od tego gracza (po sanityzacji części) — test sieci

var _heat: Dictionary = {}
var _barrel: Dictionary = {}      ## id broni → temperatura lufy 0..1 (każda broń swoja; schowana stygnie tak samo)
var _buf_t := 0.0
var _dry_latch := false
var _rl_total := 0.0
var _rl_left := 0.0
var _rl_req := false
var _rl_pending := 0
var _rl_cap := 0                  ## ile naboi zmieści broń po tym przeładowaniu (WeaponDef.capacity: z nabojem w komorze o jeden więcej)
var _rl_wait := 0.0
var _melee_pending := false
var _cycle_t := -1.0              ## s do dźwięku/łuski po strzale (pompka)
var _cycle_w := 0
var _cycle_muzzle := Vector2.ZERO
var _cycle_dir := Vector2.RIGHT
var _burst_left := 0              ## ile strzałów trwającej serii jeszcze zostało (seria dobiega bez trzymania spustu)
var _srv_tokens := 1.5
var _srv_last_ms := 0
var _srv_tick := 0.0
var _srv_fx_t := 0.0
var _srv_patch_t := 0.0              ## HKM-9: ile płomienia upłynęło od ostatniego ognia na podłodze
var _prev_w := -1
var _action_seq := 0
var _action := Vector4i.ZERO
var _action_duration := 0.0
var _action_elapsed := 0.0
var _action_progress := 0.0

## Zegar wizualny nie zadaje obrażeń; właściciel publikuje go razem ze stanem, serwer nadal liczy trafienie.
func _begin_motion(kind: int, w: int, duration: float, variant := 0) -> void:
	_action_seq += 1
	_action = Vector4i(_action_seq, kind, w, variant)
	_action_duration = maxf(duration, 0.05)
	_action_elapsed = 0.0
	_action_progress = 0.0
	_sync_player()

func _sync_motion() -> void:
	if state == State.MELEE:
		_action_duration = melee_total
		_action_elapsed = clampf(melee_total - state_t, 0.0, melee_total)
	elif state == State.RELOAD:
		# Przeładowanie taktyczne może wydłużyć akcję: faza nie wraca do poprzedniej pozy.
		_action_progress = maxf(_action_progress, reload_progress())
		_action_duration = maxf(_rl_total, 0.05)
		_action_elapsed = _action_progress * _action_duration
	else:
		_action.y = Motion.NONE
	player.w_action = _action
	player.w_action_clock = Vector2(_action_duration, _action_elapsed)

func _ready() -> void:
	player = get_parent() as CharacterBody2D
	Arsenal.rounds_granted.connect(_on_rounds_granted)
	Arsenal.weapon_hit.connect(_on_weapon_hit)
	reset()

## Stopień wprawy gracza z bronią `w` (0..5; bot — 0).
func mastery_of(w: int) -> int:
	if player == null or player.is_bot or not Weapons.is_valid(w):
		return 0
	return Profile.mastery_level(String(Weapons.def(w).key))

## Mnożnik czasów (przeładowanie, dobycie) i podrzutu z wprawy: 1 − 0,02 × stopień.
func mastery_mult(w: int) -> float:
	return 1.0 - MASTERY_STEP * float(mastery_of(w))

## Nacięcia broni `w` do pokazania na modelu: n + 16 × głębokie (bossowie). Swój gracz — z profilu, cudzy — z replikowanego `player.notches`
## (tylko trzymana broń).
func notches_of(w: int) -> int:
	if player == null or player.is_bot or not Weapons.is_valid(w):
		return 0
	if is_owner():
		var key := String(Weapons.def(w).key)
		return Profile.notches(key) + 16 * Profile.boss_notches(key)
	return int(player.get("notches")) if int(player.weapon) == w else 0

## Trafienie lokalnego strzelca (Arsenal.weapon_hit): punkty wprawy dla broni, z której padł strzał; awans — komunikat. Zabójstwo — do historii
## broni (§7.4); elita albo boss — nacięcie na kolbie.
func _on_weapon_hit(kind: int, w: int, rank := 0) -> void:
	if player == null or player.is_bot or not is_owner() or not Weapons.is_valid(w):
		return
	var key := String(Weapons.def(w).key)
	if kind == Arsenal.Confirm.KILL and Profile.add_kill(key, rank):
		Msg.post("notch.%s" % key, Msg.Ch.TOAST, tr("A notch on the %s") % String(Weapons.def(w).name),
			{"sub": tr("%d on the stock") % Profile.notches(key), "style": Msg.Style.SUCCESS, "ttl": 4.0, "prio": 70})
	var lvl := Profile.add_mastery(key, int(MASTERY_PTS.get(kind, 1)))
	if lvl > 0:
		Msg.post("mastery.%s" % key, Msg.Ch.TOAST, tr("%s  ·  MASTERY %s") % [String(Weapons.def(w).name), ROMAN[lvl]],
			{"sub": tr("Reload, draw and recoil −%d%%") % int(round(MASTERY_STEP * 100.0 * float(lvl))), "style": Msg.Style.SUCCESS, "ttl": 5.0, "prio": 75})

# ---------------------------------------------------------------- dostęp

## Trzymana broń: zamontowane części gracza i typ naboju w magazynku (Weapons.def_build).
func cur() -> WeaponDef:
	return def_of(loadout[slot])

## Serwer: broń `w` tego gracza do ognia ciągłego i ciosów — części gracza (player.fits), ale tylko te, które drużyna odblokowała (Scrap.parts).
## Do 1.7.350 ogień ciągły brał tu fabryczną broń, więc części LR-7 i HKM-9 nie zmieniały obrażeń ani zasięgu; kule niosą kod części w strzale.
func server_def(w: int) -> WeaponDef:
	return Weapons.def_build(w, Weapons.build_of(0, Parts.sanitize(String(Weapons.def(w).key), fit_of(w), Scrap.parts)))

## Broń `w` tego gracza (części + nabój w magazynku).
func def_of(w: int) -> WeaponDef:
	return Weapons.def_build(w, Weapons.build_of(ammo_of(w), fit_of(w)))

## Kod części broni `w` tego gracza (player.fits — replikowane od właściciela; boty i brak wpisu = fabryczna).
func fit_of(w: int) -> int:
	if range_sink != null and range_fit.has(w):
		return int(range_fit[w])                                # strzelnica: próba części z szafy (fp_mode.gd)
	if player == null or player.is_bot or w < 0 or w >= player.fits.size():
		return 0
	return int(player.fits[w])

## Typ naboju w magazynku broni `w` (0 = zwykły).
func ammo_of(w: int) -> int:
	return int(loaded.get(w, 0))

## Typ wybrany na następny magazynek broni `w`.
func next_ammo_of(w: int) -> int:
	return int(want_ammo.get(w, ammo_of(w)))

## Klawisz Z: następny typ naboju kalibru trzymanej broni, który drużyna ma w zapasie (zwykły jest zawsze). Typ wchodzi z nowym
## magazynkiem — gotowa broń od razu się przeładowuje (stary magazynek wraca do zapasu swojego typu, także nabój z komory).
func cycle_ammo() -> void:
	var d := cur()
	var n := Ammo.count(String(d.caliber))
	if n <= 1 or not d.uses_ammo() or d.infinite:
		return
	var from := next_ammo_of(d.id)
	var pick := from
	for i in range(1, n + 1):
		var t := (from + i) % n
		if t == 0 or practice or Arsenal.get_reserve(d.id, t) > 0:
			pick = t
			break
	if pick == from:
		return
	want_ammo[d.id] = pick
	if not player.is_bot:
		Audio.play("ui_click", Audio.BUS_UI, -10.0, 1.1)
	ammo_changed.emit(d.id, pick)
	if pick != ammo_of(d.id) and state == State.READY:
		try_reload()

## Czy `d` strzela teraz serią (broń ma tryb serii i gracz go wybrał).
func is_burst(d: WeaponDef) -> bool:
	return d.burst_size > 0 and bool(burst_on.get(d.id, false))

## Klawisz B: przełącza ogień ciągły ↔ seria dla trzymanej broni (jeśli ma oba tryby).
func toggle_fire_mode() -> void:
	var d := cur()
	if d.burst_size <= 0 or state == State.RELOAD:
		return
	burst_on[d.id] = not bool(burst_on.get(d.id, false))
	_burst_left = 0
	if not player.is_bot:
		Audio.play("ui_click", Audio.BUS_UI, -10.0, 0.8 if burst_on[d.id] else 1.3)
	fire_mode_changed.emit(d.id, bool(burst_on[d.id]))

func def_of_slot(i: int) -> WeaponDef:
	return def_of(loadout[i])

func mag_of(w: int) -> int:
	return int(mags.get(w, 0))

func heat_of(w: int) -> float:
	return float(_heat.get(w, 0.0))

## Temperatura lufy broni `w` (0..1).
func barrel_of(w: int) -> float:
	return float(_barrel.get(w, 0.0))

## Stan techniczny broni `w` tego gracza (0..100 %).
func condition_of(w: int) -> float:
	return Profile.condition(String(Weapons.def(w).key))

## Zacięcie broni `w` czekające na usunięcie ("" — brak).
func jammed(w: int) -> String:
	return String(jams.get(w, ""))

## Szansa awarii broni eksperymentalnej (WeaponDef.fault) — ta sama krzywa co zacięcie broni palnej.
func fault_chance(d: WeaponDef) -> float:
	var m := Settings.reliability_mult()
	if m <= 0.0 or String(d.fault) == "":
		return 0.0
	return clampf((JAM_FROM - condition_of(d.id)) / JAM_SPAN, 0.0, 1.75) / JAM_ODDS * m

func _take_sim_fault(kind: String) -> bool:
	if sim_fault != kind:
		return false
	sim_fault = ""
	return true

func _start_fault(d: WeaponDef, kind: String, t: float) -> void:
	jams[d.id] = kind
	_fault_t = t
	_fault_w = d.id
	fault_count += 1
	firing = false
	jam_started.emit(d.id, kind)
	Audio.play_variant("reload_cell" if kind == "overheat" else "reload_rail", 2 if kind == "overheat" else 1, Audio.BUS_WEAPONS, -8.0, 0.7)

## Zużycie noszonej broni (otoczenie, upadek): cały zestaw albo tylko broń w rękach. Tylko człowiek, właściciel.
func wear_carried(amount: float, held_only := false) -> void:
	if player == null or player.is_bot or not is_owner():
		return
	var m := Settings.reliability_mult()
	if m <= 0.0:
		return
	var ws: Array = [cur().id] if held_only else loadout
	for w in ws:
		var wd := Weapons.def(int(w))
		if not wd.is_melee():
			Profile.wear(String(wd.key), amount * m)

## Wejście na powierzchnię (player.gd, co klatkę): woda i błoto zużywają broń, najwyżej raz na WADE_GAP s na rodzaj.
func wade(surface: String) -> void:
	var amt := WEAR_WATER if surface == "water" else (WEAR_MUD if surface == "mud" else 0.0)
	if amt <= 0.0 or float(_wade_t.get(surface, 0.0)) > 0.0:
		return
	_wade_t[surface] = WADE_GAP
	wear_carried(amt)

## Serwer potwierdził zużycie zestawu do czyszczenia (arsenal.gd): broń w rękach +40 %, zacięcie usunięte.
@rpc("any_peer", "call_remote", "reliable")
func cleankit_done() -> void:
	if NoiseMgr.has_network() and multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if player == null or player.is_bot:
		return
	var d := cur()
	if d.is_melee():
		return
	Profile.restore(String(d.key), float(Throwables.KINDS["cleankit"]["restore"]))
	if jammed(d.id) in ["misfire", "stovepipe", "double"]:
		jams.erase(d.id)
	Audio.play_variant("reload_bolt", 1, Audio.BUS_WEAPONS, -10.0, 0.9)

## Szansa zacięcia na strzał: 0 powyżej JAM_FROM % stanu, potem rośnie (1/150 przy 30 %, ok. 1/86 przy 0 %); ustawienie ją mnoży.
func jam_chance(d: WeaponDef) -> float:
	var m := Settings.reliability_mult()
	if m <= 0.0 or not d.can_jam():
		return 0.0
	return clampf((JAM_FROM - condition_of(d.id)) / JAM_SPAN, 0.0, 1.75) / JAM_ODDS * m

## Zużycie broni strzałem (tylko człowiek, właściciel — stan siedzi w jego profilu).
func _wear_shot(d: WeaponDef) -> void:
	if player == null or player.is_bot or not is_owner():
		return
	var a := WEAR_SHOT * d.wear * Settings.reliability_mult()
	if barrel_of(d.id) >= HOT_WEAR_AT:
		a *= WEAR_HOT
	if d.suppressor > 0.0:
		a *= WEAR_CAN
	Profile.wear(String(d.key), a)
	if d.can_jam():                                        # broń na naboje: lufa i sprężyny (stół konserwacji)
		var m := d.wear * Settings.reliability_mult()
		Profile.wear_part(String(d.key), "barrel", WEAR_BARREL * m * (WEAR_HOT if barrel_of(d.id) >= HOT_WEAR_AT else 1.0))
		Profile.wear_part(String(d.key), "springs", WEAR_SPRINGS * m)

## Losuje zacięcie przy próbie strzału: niewypał (połowa), zacięcie łuski, rzadko podwójne podanie. Nigdy w pierwszych strzałach
## magazynka i nigdy dwa razy w JAM_GAP_MS.
func _roll_jam(d: WeaponDef) -> String:
	if sim_jam != "":
		var j := sim_jam
		sim_jam = ""
		return j
	if player.is_bot or int(_shots_mag.get(d.id, 0)) < JAM_SAFE_SHOTS or Time.get_ticks_msec() - _last_jam_ms < JAM_GAP_MS:
		return ""
	if randf() >= jam_chance(d):
		return ""
	var r := randf()
	return "misfire" if r < 0.5 else ("stovepipe" if r < 0.9 else "double")

func _start_jam(d: WeaponDef, kind: String) -> void:
	jams[d.id] = kind
	_last_jam_ms = Time.get_ticks_msec()
	jam_count += 1
	_burst_left = 0
	jam_started.emit(d.id, kind)

## Spust przy zaciętej broni: klik (jak na pustym), bez automatycznego przeładowania.
func _jam_click(d: WeaponDef) -> void:
	_buf_t = 0.0
	if _dry_latch:
		return
	_dry_latch = true
	Audio.play("dry_fire", Audio.BUS_WEAPONS, -8.0, 0.9)
	NoiseMgr.add_noise(NOISE_DRY, player.global_position, "dry")
	dry_fired.emit(d.id)

## [R] przy zaciętej broni: przeładowanie rączką (0,6 s, mały hałas); podwójne podanie — z wyjęciem magazynka (+1 s).
func _start_clear(d: WeaponDef) -> void:
	firing = false
	_burst_left = 0
	state = State.RELOAD
	clearing = true
	tactical = false
	_rl_out = -1.0
	_rl_req = false
	_rl_pending = 0
	_rl_total = (CLEAR_TIME + (DOUBLE_FEED_EXTRA if jammed(d.id) == "double" else 0.0)) * (1.0 - MASTERY_CLEAR_STEP * float(mastery_of(d.id)))
	_rl_left = _rl_total
	_begin_motion(Motion.RELOAD, d.id, _rl_total, Motion.CLEAR)
	NoiseMgr.add_noise(NOISE_CLEAR, player.global_position, "reload")
	if is_owner():
		Audio.play_variant("reload_bolt", 1, Audio.BUS_WEAPONS, -8.0, 1.05)

## Rozgrzewa lufę jednym strzałem.
func _heat_barrel(d: WeaponDef) -> void:
	if d.barrel_heat > 0.0:
		_barrel[d.id] = minf(1.0, barrel_of(d.id) + d.barrel_heat)

func carries(w: int) -> bool:
	return loadout.has(w) or w == melee_id

func primaries() -> Array:
	return [loadout[0], loadout[1]]

func is_owner() -> bool:
	if player == null:
		return false
	if player.is_bot:
		return NoiseMgr.is_server()
	return player.is_multiplayer_authority()

func is_reloading() -> bool:
	return state == State.RELOAD

## Postęp przeładowania 0..1 (HUD, widok).
func reload_progress() -> float:
	if state != State.RELOAD or _rl_total <= 0.0:
		return 0.0
	return clampf(1.0 - _rl_left / _rl_total, 0.0, 1.0)

func kit() -> Vector3i:
	return Vector3i(loadout[0], loadout[1], melee_id)

## Rozrzut dokładany do bazowego: seria (bloom), bieg, strzał w locie, kucanie, oparcie.
func spread_extra(d: WeaponDef) -> float:
	var e := bloom
	if not player.is_on_floor():
		e += d.air_spread                  # skok, spadanie: bez oparcia nóg strzał nie jest celny jak z ziemi (od 1.7.316)
	elif absf(player.velocity.x) > 60.0:
		e += 0.8
	if player.crouching:
		e *= float(d.crouch_accuracy)
	if braced:
		e *= BRACE_SPREAD
	if Settings.realistic_handling:
		var t := barrel_of(d.id)
		e += (d.jitter_deg + e) * HOT_SPREAD * t * t        # gorąca lufa rozrzuca: rośnie cały stożek, także bazowy
	var z := barrel_wear_of(d)
	if z > 0.0:
		e += (d.jitter_deg + e) * BARREL_SPREAD * z * z     # wyrobiona lufa (W2): stożek rośnie, póki gracz jej nie wymieni
	return e

## Masa noszonego ekwipunku w kg (części gracza wliczone). Liczona od nowa tylko po zmianie broni albo montażu.
func kit_mass() -> float:
	var sig := "%s|%d|%s" % [str(loadout), melee_id, str(player.fits) if player != null else ""]
	if sig != _mass_sig:
		_mass_sig = sig
		_mass = 0.0
		for w in loadout:
			if Weapons.is_valid(int(w)):
				_mass += def_of(int(w)).mass
		if Weapons.is_valid(melee_id):
			_mass += def_of(melee_id).mass
	return _mass

## Mnożnik hałasu biegu od masy ekwipunku (1 w obsłudze klasycznej, dla botów i poza strzelnicą — jak niżej).
func mass_noise_mult() -> float:
	if not _mass_applies():
		return 1.0
	return clampf(1.0 + MASS_NOISE * (kit_mass() - mass_ref()), MASS_NOISE_RANGE.x, MASS_NOISE_RANGE.y)

## Mnożnik tempa biegu od masy ekwipunku.
func mass_speed_mult() -> float:
	if not _mass_applies():
		return 1.0
	return clampf(1.0 - MASS_SPEED * (kit_mass() - mass_ref()), MASS_SPEED_RANGE.x, MASS_SPEED_RANGE.y)

## Masa fabrycznego zestawu startowego (bez części) — punkt odniesienia masy ekwipunku.
static func mass_ref() -> float:
	return Weapons.def(Weapons.START_PRIMARY_A).mass + Weapons.def(Weapons.START_PRIMARY_B).mass + Weapons.def(Weapons.START_SIDEARM).mass + Weapons.def(Weapons.START_MELEE).mass

func _mass_applies() -> bool:
	return Settings.realistic_handling and player != null and not player.is_bot

## Zużycie lufy broni `d` tego gracza 0..1 (profil właściciela; boty, inni gracze i broń bez naboi — 0; niezawodność OFF — 0).
func barrel_wear_of(d: WeaponDef) -> float:
	if player == null or player.is_bot or not is_owner() or not d.can_jam() or Settings.reliability_mult() <= 0.0:
		return 0.0
	return Profile.part_wear(String(d.key), "barrel") / 100.0

## Mnożnik hałasu od temperatury lufy: rozgrzany tłumik głośnieje.
func hot_can_mult(d: WeaponDef) -> float:
	if not Settings.realistic_handling or d.suppressor <= 0.0:
		return 1.0
	return 1.0 + HOT_CAN * barrel_of(d.id)

## Podrzut zamiast narastania rozrzutu: obsługa realistyczna i celowanie myszą (tylko mysz pozwala ściągać lufę w dół).
func climb_mode() -> bool:
	return Settings.realistic_handling and player != null and bool(player.get("aim_by_mouse"))

## Kierunek celowania uniesiony o podrzut (w górę ekranu niezależnie od strony, w którą patrzy postać).
func apply_climb(dir: Vector2) -> Vector2:
	if climb <= 0.0:
		return dir
	return dir.rotated(deg_to_rad(climb) * (-1.0 if dir.x >= 0.0 else 1.0))

## Oparcie (GUNSMITH_PLAN.md §5.2): pod łożem albo wylotem broni jest górna krawędź skrzyni, murku, progu albo kładki, a sama broń
## nad nią jest wolna — broń leży na krawędzi. Lufa stojącej postaci jest na 17–18 px, skrzynia ma 14 px, stopień z jednego kafla 16 px:
## na stojąco opierasz się o skrzynię i murek, kucając chowasz się za nimi. Na ziemi, bez biegu, lufa najwyżej lekko w dół; krawędź musi
## być wyżej niż stopy (podłoga, na której stoisz, nie podpiera broni).
func check_brace(d: WeaponDef) -> bool:
	if not Settings.realistic_handling or player == null or not player.is_inside_tree() or d.is_melee() or d.is_continuous():
		return false
	if not player.is_on_floor() or absf(player.velocity.x) > 40.0:
		return false
	var dir: Vector2 = player.aim_dir
	if absf(dir.x) < 0.5 or dir.y > 0.25:
		return false
	var ht := _hand_tip(dir, d)
	var hand: Vector2 = ht[0]
	var tip: Vector2 = ht[1]
	var space := player.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = BRACE_MASK
	q.exclude = [player.get_rid()]
	var feet: float = player.global_position.y - 3.0
	for t in BRACE_PROBE:
		var p := hand.lerp(tip, float(t))
		q.position = p + Vector2(0.0, -1.5)
		if not space.intersect_point(q, 1).is_empty():
			return false                                   # linia lufy zasłonięta — to ściana, nie krawędź
		for dy in BRACE_DEPTH:
			q.position = p + Vector2(0.0, float(dy))
			if q.position.y < feet and not space.intersect_point(q, 1).is_empty():
				return true
	return false

## Wylot lufy w świecie: dłoń (jak w widoku broni) + długość lufy wzdłuż celowania (postać 3D: wylot z modelu broni).
## Lufa nie wychodzi za ścianę: gdy między dłonią a wylotem jest przeszkoda, wylot stoi tuż przed nią
## (długa broń nie strzela przez cienką ścianę, gdy stoisz przy niej).
func muzzle_pos(dir: Vector2, d: WeaponDef) -> Vector2:
	var ht := _hand_tip(dir, d)
	var hand: Vector2 = ht[0]
	var tip: Vector2 = ht[1]
	if not player.is_inside_tree():
		return tip
	var q := PhysicsRayQueryParameters2D.create(hand, tip, Combat.LAYER_WORLD)
	var hit := player.get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"] - dir * 1.0
	return tip

## Chwyt (dłoń / nadgarstek) i wylot lufy w świecie, bez sprawdzania ścian.
func _hand_tip(dir: Vector2, d: WeaponDef) -> Array:
	var side := signf(dir.x) if absf(dir.x) > 0.1 else 1.0
	var hand := player.global_position + Vector2(side, -8.0 if player.crouching else -12.0)
	var tip := hand + dir * d.gun_len
	var c3d: Node2D = player.get("c3d")
	if c3d != null and c3d.ready_ok and not bool(player.get("dead")):
		# postać 3D: chwyt i wylot z pozy nominalnej (Char3D.aim_points) — pocisk wychodzi z lufy, a klatka animacji (bieg, odrzut, obrót modelu,
		# przeładowanie) nie przesuwa jego toru; ten sam stan gracza daje ten sam punkt u każdego peera
		var ap: Array = c3d.aim_points(dir, side, bool(player.get("crouching")), String(d.key), d.fit)
		hand = player.global_position + (ap[0] as Vector2)
		tip = player.global_position + (ap[1] as Vector2)
	return [hand, tip]

## Okno wyrzutowe łusek: punkt na osi broni między chwytem a wylotem (`WeaponDef.eject_frac`). Wcześniej łuska wylatywała zawsze 6 px
## (ok. 0,5 m) za wylotem — przy pistolecie długości 0,18 m to okolice barku.
func eject_pos(dir: Vector2, d: WeaponDef) -> Vector2:
	var ht := _hand_tip(dir, d)
	return (ht[0] as Vector2).lerp(ht[1], d.eject_frac)

# ---------------------------------------------------------------- reset / zestaw

## Pełny reset (spawn, restart misji): zestaw startowy, pełne magazynki, zimne lufy.
func reset() -> void:
	loadout = [Weapons.START_PRIMARY_A, Weapons.START_PRIMARY_B, Weapons.START_SIDEARM]
	if player != null and player.is_bot:
		loadout = [Weapons.M83, Weapons.M83, Weapons.P64]
		ammo_enabled = false
	melee_id = Weapons.START_MELEE
	slot = 0
	inspect_item = null
	inspect_slot = 0
	mags.clear()
	loaded.clear()
	want_ammo.clear()
	for w in loadout:
		mags[w] = def_of(w).mag
	_heat.clear()
	_barrel.clear()
	jams.clear()
	_shots_mag.clear()
	clearing = false
	bloom = 0.0
	climb = 0.0
	recoil = 0.0
	cd = 0.0
	charge = 0.0
	firing = false
	state = State.READY
	state_t = 0.0
	_rl_req = false
	_rl_pending = 0
	_melee_pending = false
	_buf_t = 0.0
	_sync_player()

## Gracz padł (down): przerwij wszystko — w tym ciągły ogień, żeby nie palił po śmierci.
func on_down() -> void:
	_cancel_actions()
	firing = false
	wear_carried(WEAR_DOWN, true)                         # broń upada razem z graczem
	_sync_player()

## Zimne lufy i zerowy rozrzut (po wykrwawieniu, bez utraty zestawu).
func cool() -> void:
	_heat.clear()
	_barrel.clear()
	bloom = 0.0
	climb = 0.0
	cd = 0.0

func _sync_player() -> void:
	if player == null:
		return
	player.weapon = loadout[slot]
	player.w_state = state
	_sync_motion()
	player.w_charge = charge
	player.w_firing = firing
	player.w_hot = barrel_of(player.weapon)
	if is_owner() and not player.is_bot:
		player.notches = notches_of(player.weapon)          # nacięcia trzymanej broni widzą wszyscy
	player.kit = kit()
	if _prev_w != player.weapon:
		_prev_w = player.weapon
		weapon_changed.emit(player.weapon)

# ---------------------------------------------------------------- tyknięcie właściciela

## Wołane z player.gd co klatkę fizyki (człowiek, żywy). `reviving` blokuje strzał.
func tick_local(delta: float, reviving: bool) -> void:
	_tick_common(delta)
	braced = bool(range_sink.braced()) if range_sink != null else check_brace(cur())
	reload_held = Input.is_action_pressed("reload") or sim_reload_hold
	if reviving:
		_cancel_actions()
		_sync_player()
		inspect_item = null
		return
	_tick_inspect()
	if inspect_item != null:                              # oględziny: ręce zajęte — bez strzału, przeładowania i zmiany broni
		_cancel_actions()
		_sync_player()
		return
	_handle_switch_input()
	if Input.is_action_just_pressed("firemode"):
		toggle_fire_mode()
	if Input.is_action_just_pressed("melee") and range_sink == null:      # strzelnica: PPM celuje przez przyrządy (fp_mode.gd)
		try_melee()
	if Input.is_action_just_pressed("reload"):
		try_reload()
	if Input.is_action_just_pressed("ammo_type"):
		cycle_ammo()
	var held := Input.is_action_pressed("fire") or sim_fire
	var pressed := Input.is_action_just_pressed("fire") or sim_press
	sim_press = false
	_handle_fire(held, pressed, delta)
	_sync_player()

## Bot: tylko liczniki; strzela przez bot_fire().
func tick_bot(delta: float) -> void:
	_tick_common(delta)
	_sync_player()

func _tick_common(delta: float) -> void:
	for w in _heat.keys():
		_heat[w] = maxf(0.0, float(_heat[w]) - Weapons.def(w).heat_decay * delta)
	for w in _barrel.keys():
		_barrel[w] = maxf(0.0, float(_barrel[w]) - BARREL_COOL * delta)
	for sfc in _wade_t.keys():
		_wade_t[sfc] = maxf(0.0, float(_wade_t[sfc]) - delta)
	if _fault_t > 0.0:
		_fault_t -= delta
		if _fault_t <= 0.0:
			if jammed(_fault_w) in ["overheat", "arc"]:
				jams.erase(_fault_w)
			_fault_w = -1
	bloom = maxf(0.0, bloom - cur().bloom_decay * delta)
	climb = maxf(0.0, climb - cur().bloom_decay * CLIMB_RECOVER_K * delta)
	recoil = maxf(0.0, recoil - delta * 9.0)
	cd = maxf(cd - delta, -delta)
	_buf_t = maxf(0.0, _buf_t - delta)
	if _cycle_t >= 0.0:
		_cycle_t -= delta
		if _cycle_t < 0.0:
			_cycle_t = -1.0
			_cycle_fx()
	match state:
		State.DRAW:
			state_t -= delta
			if state_t <= 0.0:
				state = State.READY
				_auto_reload_if_empty()
		State.MELEE:
			state_t -= delta
			if _melee_pending and state_t <= melee_total * (1.0 - MELEE_HIT_AT):
				_melee_pending = false
				_melee_resolve()
			if state_t <= 0.0:
				state = State.READY
		State.RELOAD:
			_tick_reload(delta)

func _cancel_actions() -> void:
	_burst_left = 0
	if state == State.RELOAD:
		_cancel_reload()
	if state == State.CHARGE:
		_cancel_charge()
	if state == State.MELEE:
		state = State.READY
		_melee_pending = false
	firing = false
	_sync_player()

# ---------------------------------------------------------------- zmiana broni

func _handle_switch_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		select_slot(0)
	elif Input.is_action_just_pressed("weapon_2"):
		select_slot(1)
	elif Input.is_action_just_pressed("weapon_3"):
		select_slot(2)
	elif Input.is_action_just_pressed("weapon_next"):
		select_slot((slot + 1) % 3)
	elif Input.is_action_just_pressed("weapon_prev"):
		select_slot((slot + 2) % 3)

func select_slot(i: int) -> void:
	if i == slot or i < 0 or i > 2:
		return
	_cancel_actions()
	slot = i
	var d := cur()
	state = State.DRAW
	state_t = d.draw_time * mastery_mult(d.id)
	cd = maxf(cd, 0.0)
	_dry_latch = false
	Audio.play_variant("foley_gear", 3, Audio.BUS_PLAYER, -14.0, 1.0 + 0.1 * float(i))
	if not player.is_bot:
		Audio.play("ui_click", Audio.BUS_UI, -14.0, 1.2)
	_sync_player()

## Pusty magazynek po zmianie broni → od razu przeładowanie (nikt nie chce celować kliknięciem).
func _auto_reload_if_empty() -> void:
	var d := cur()
	if ammo_enabled and d.uses_ammo() and mag_of(d.id) <= 0:
		try_reload(true)

# ---------------------------------------------------------------- ogień

func _handle_fire(held: bool, pressed: bool, delta: float) -> void:
	var d := cur()
	if pressed:
		_buf_t = BUFFER
	if not held:
		_dry_latch = false
	match d.kind:
		WeaponDef.Kind.BEAM, WeaponDef.Kind.FLAME:
			_handle_continuous(d, held)
		WeaponDef.Kind.RAIL:
			_handle_rail(d, held, delta)
		_:
			_handle_shot(d, held)

func _has_ammo(d: WeaponDef) -> bool:
	return not ammo_enabled or not d.uses_ammo() or mag_of(d.id) >= d.ammo_per_shot

func _handle_shot(d: WeaponDef, held: bool) -> void:
	var bursting := is_burst(d)
	var want := held if (d.auto and not bursting) else _buf_t > 0.0
	if bursting and (held or _burst_left > 0):
		want = true                                      # przytrzymany spust powtarza serie, a rozpoczęta seria dobiega sama po puszczeniu
	if not want:
		return
	# strzelbę/granatnik ładowane po jednym naboju można przerwać strzałem
	if state == State.RELOAD and d.reload_per_round and mag_of(d.id) > 0:
		_cancel_reload()
	if state != State.READY or cd > 0.0:
		return
	var jam := jammed(d.id)
	if jam != "":
		if jam == "misfire" and d.key == "p64" and _buf_t > 0.0 and not _dry_latch:
			jams.erase(d.id)                               # P-83 (podwójne działanie): drugie pociągnięcie spustu uderza kurkiem jeszcze raz
		else:
			_jam_click(d)
			return
	if not _has_ammo(d):
		_burst_left = 0
		_dry_fire(d)
		return
	if jam == "":
		var j := _roll_jam(d)
		if j != "":
			_start_jam(d, j)
			if j == "misfire":
				_jam_click(d)                              # niewypał: kurek uderzył, strzału nie ma
				return
			# zacięcie łuski / podwójne podanie: ten strzał wychodzi, następny już nie
	_buf_t = 0.0
	_fire_shot(d)

func _dry_fire(d: WeaponDef) -> void:
	if _dry_latch:
		return
	_dry_latch = true
	Audio.play("dry_fire", Audio.BUS_WEAPONS, -8.0, 1.0)
	NoiseMgr.add_noise(NOISE_DRY, player.global_position, "dry")
	dry_fired.emit(d.id)
	_buf_t = 0.0
	try_reload(true)

func _handle_continuous(d: WeaponDef, held: bool) -> void:
	if not held or state != State.READY or jammed(d.id) == "overheat":
		firing = false
		return
	if not _has_ammo(d):
		firing = false
		_dry_fire(d)
		return
	if not firing:
		firing = true
		Audio.play_variant(d.sfx, d.sfx_count, Audio.BUS_WEAPONS, d.sfx_vol, d.sfx_pitch)
		cd = minf(cd, 0.0)
	if cd <= 0.0:
		cd += d.cooldown
		if ammo_enabled:
			mags[d.id] = mag_of(d.id) - d.ammo_per_shot
		var heat := heat_of(d.id)
		NoiseMgr.add_noise(d.noise(heat), player.global_position, "shot:" + d.key)       # wiązka się grzeje: hałas rośnie z czasem ciągłego ognia (LR-7)
		_heat[d.id] = minf(1.0, heat + d.heat_gain)
		_wear_shot(d)
		if String(d.fault) == "overheat" and (_take_sim_fault("overheat") or randf() < fault_chance(d) * FAULT_TICK):
			_start_fault(d, "overheat", OVERHEAT_PAUSE)       # zużyte ogniwo przegrzewa się: wiązka gaśnie na chwilę
		recoil = maxf(recoil, 0.25)
		Feel.shake(d.shake)
		if range_sink != null:                                   # strzelnica: krok promienia / płomienia w tunelu 3D (range_sim.gd)
			range_sink.range_shot(d, randi(), 0.0)
		shot.emit(d.id)

func _handle_rail(d: WeaponDef, held: bool, delta: float) -> void:
	if state == State.READY and held and cd <= 0.0:
		if not _has_ammo(d):
			_dry_fire(d)
			return
		state = State.CHARGE
		charge = 0.0
		Audio.stop_loop(d.sfx_loop)
		Audio.start_loop(d.sfx_loop, Audio.BUS_WEAPONS, d.sfx_vol - 6.0, 1.0)
	if state != State.CHARGE:
		return
	if held:
		charge = minf(1.0, charge + delta / d.charge_time)
		Feel.shake(0.15 + 0.5 * charge * charge)
	elif charge >= 1.0:
		if String(d.fault) == "arc" and (_take_sim_fault("arc") or randf() < fault_chance(d) * ARC_MULT):
			_cancel_charge()                                  # zużyty kondensator przebija: ładunek uchodzi iskrą, ładowanie od nowa
			_start_fault(d, "arc", ARC_SHOW)
			return
		_fire_shot(d)
	else:
		_cancel_charge()

func _cancel_charge() -> void:
	var d := cur()
	if d.sfx_loop != "":
		Audio.stop_loop(d.sfx_loop)
	charge = 0.0
	if state == State.CHARGE:
		state = State.READY

## Jeden strzał pociskiem / granatem / szyną: koszt, rozgrzanie, hałas, efekty własne, wysyłka.
func _fire_shot(d: WeaponDef) -> void:
	var dir: Vector2 = player.aim_dir
	var muzzle := muzzle_pos(dir, d)
	var extra := spread_extra(d)
	var seed := randi()
	if ammo_enabled and d.uses_ammo():
		mags[d.id] = mag_of(d.id) - d.ammo_per_shot
	_shots_mag[d.id] = int(_shots_mag.get(d.id, 0)) + 1
	if not practice:
		_wear_shot(d)
	var heat := heat_of(d.id)
	var bursting := is_burst(d)
	NoiseMgr.add_noise(d.noise(heat) * (d.burst_quiet if bursting else 1.0) * hot_can_mult(d), player.global_position, "shot:" + d.key)
	_heat[d.id] = minf(1.0, heat + d.heat_gain * (d.burst_heat if bursting else 1.0))
	_heat_barrel(d)
	var kick := (d.burst_bloom if bursting else 1.0) * (BRACE_CLIMB if braced else 1.0) * mastery_mult(d.id)
	if climb_mode():
		# podrzut: lufa idzie w górę o przewidywalną wartość, rozrzut serii nie rośnie (mysz kompensuje)
		var g := d.bloom_per_shot * CLIMB_K * kick * (CLIMB_CROUCH if player.crouching else 1.0) * (1.0 + randf_range(-CLIMB_JITTER, CLIMB_JITTER))
		climb = minf(climb + g, d.bloom_max * CLIMB_MAX_K)
	else:
		bloom = minf(bloom + d.bloom_per_shot * kick, d.bloom_max)
	if bursting:
		# pierwszy strzał otwiera serię (zostaje burst_size − 1), kolejne ją dokańczają; po ostatnim — dłuższa przerwa
		if _burst_left > 0:
			_burst_left -= 1
		else:
			_burst_left = d.burst_size - 1
		cd += d.burst_gap if _burst_left > 0 else d.burst_rest
	else:
		cd += d.cooldown
	if d.kind == WeaponDef.Kind.RAIL:
		Audio.stop_loop(d.sfx_loop)
		charge = 0.0
		state = State.READY
	if range_sink != null:
		# strzelnica: dźwięk i odrzut modelu jak zwykle, kula leci w tunelu 3D (bez pocisku 2D, efektów w kryjówce i pchnięcia postaci)
		recoil = 1.0
		Audio.play_variant(d.sfx, d.sfx_count, Audio.BUS_WEAPONS, d.sfx_vol, d.sfx_pitch)
		range_sink.range_shot(d, seed, extra)
		shot.emit(d.id)
		if d.sfx_cycle != "":
			_schedule_cycle(d, muzzle, dir)
		return
	_own_shot_fx(d, muzzle, dir)
	if NoiseMgr.is_server():
		_server_fire(muzzle, dir, d.id, seed, extra, player.player_id, true, 0.0, d.build)
	else:
		_predict(d, muzzle, dir, seed, extra)
		_fire_request.rpc_id(1, muzzle, dir, d.id, seed, extra, d.build)
	shot.emit(d.id)
	if d.sfx_cycle != "":
		_schedule_cycle(d, muzzle, dir)

## Strzał bota: M-83 bez kosztu amunicji, tempo ×1,8 (dyscyplina ognia w player.gd).
func bot_fire(dir: Vector2) -> bool:
	var d := Weapons.def(Weapons.M83)
	if cd > 0.0 or state != State.READY:
		return false
	var muzzle := muzzle_pos(dir, d)
	var seed := randi()
	var heat := heat_of(d.id)
	NoiseMgr.add_noise(d.noise(heat), player.global_position, "shot:" + d.key)
	_heat[d.id] = minf(1.0, heat + d.heat_gain)
	_heat_barrel(d)
	cd += d.cooldown * 1.8
	recoil = maxf(recoil, 0.6)
	player.weapon = d.id
	_server_fire(muzzle, dir, d.id, seed, 0.0, player.player_id, false)
	shot.emit(d.id)
	return true

# ---------------------------------------------------------------- strzał: efekty

## Efekty strzelca (jego własny peer): dźwięk niepozycyjny, rozbłysk, kamera, odrzut, łuska.
func _own_shot_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	recoil = 1.0
	Audio.play_variant(d.sfx, d.sfx_count, Audio.BUS_WEAPONS, d.sfx_vol, d.sfx_pitch)
	Feel.shake(d.shake)
	if d.cam_kick > 0.0:
		Feel.kick(-dir * d.cam_kick)
	if d.kick > 0.0:
		player.apply_recoil_kick(-dir.x * d.kick)
	_cosmetic_fx(d, muzzle, dir, d.sfx_cycle == "")

## Efekty cudzego strzału (inny człowiek, bot): pozycyjny dźwięk + rozbłysk + łuska.
func _remote_shot_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	Audio.play_variant_at(d.sfx, d.sfx_count, muzzle, Audio.BUS_WEAPONS, d.sfx_vol - 3.0, d.sfx_pitch)
	recoil = 1.0
	_cosmetic_fx(d, muzzle, dir, d.sfx_cycle == "")
	shot.emit(d.id)
	if d.sfx_cycle != "":
		_schedule_cycle(d, muzzle, dir)

func _cosmetic_fx(d: WeaponDef, muzzle: Vector2, dir: Vector2, eject_now: bool) -> void:
	var parent: Node = player._fx_root()
	if eject_now and d.casing > 0:
		Vfx.casing(parent, eject_pos(dir, d), dir, d.casing >= 2)
	Vfx.smoke(parent, muzzle, dir)

func _schedule_cycle(d: WeaponDef, muzzle: Vector2, dir: Vector2) -> void:
	_cycle_t = 0.38
	_cycle_w = d.id
	_cycle_muzzle = muzzle
	_cycle_dir = dir

## Pompka / zamek po strzale: dźwięk i wyrzut łuski (strzelba wyrzuca ją dopiero tu).
func _cycle_fx() -> void:
	var d := Weapons.def(_cycle_w)
	if d.sfx_cycle != "":
		if is_owner():
			Audio.play_variant(d.sfx_cycle, d.sfx_cycle_count, Audio.BUS_WEAPONS, d.sfx_vol - 5.0, 1.0)
		else:
			Audio.play_variant_at(d.sfx_cycle, d.sfx_cycle_count, _cycle_muzzle, Audio.BUS_WEAPONS, d.sfx_vol - 8.0, 1.0)
	if d.casing > 0:
		Vfx.casing(player._fx_root(), eject_pos(_cycle_dir, d), _cycle_dir, d.casing >= 2)          # pompka: okno wyrzutowe w chwili przeładowania

# ---------------------------------------------------------------- strzał: serwer i sieć

## Strzelec-klient: kosmetyczne kopie pocisków od razu (predykcja).
func _predict(d: WeaponDef, muzzle: Vector2, dir: Vector2, seed: int, extra: float) -> void:
	match d.kind:
		WeaponDef.Kind.RAIL:
			var tr := Combat.trace(player.get_world_2d().direct_space_state, muzzle, dir, d.range_px, int(d.pierce), d.wall_pierce, [player.get_rid()])
			_rail_visual(d, muzzle, tr["end"], tr)
		_:
			_spawn_projectiles(d, muzzle, dir, seed, extra, player.player_id, false)

func _spawn_projectiles(d: WeaponDef, muzzle: Vector2, dir: Vector2, seed: int, extra: float, shooter: int, auth: bool, lag := 0.0) -> void:
	var scene := get_tree().current_scene
	for dd in Weapons.pellet_dirs(d, dir, seed, extra):
		var p := Projectile.new()
		p.launch(d.id, muzzle, dd, shooter, auth, lag, d.build)
		scene.add_child(p)

## Serwer: waliduje (tempo, wylot) i wykonuje strzał; resztę peerów informuje o kosmetyce.
@rpc("any_peer", "call_remote", "reliable")
func _fire_request(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float, build: int) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if multiplayer.get_remote_sender_id() != player.player_id or not Weapons.is_valid(w):
		return
	# części tylko odblokowane przez drużynę (reszta = fabryczne), nieznany typ naboju = zwykły (Weapons.def_build)
	var fit := Parts.sanitize(String(Weapons.def(w).key), Weapons.fit_of_build(build), Scrap.parts)
	var d := Weapons.def_build(w, Weapons.build_of(Weapons.ammo_of_build(build), fit))
	srv_last_build = d.build
	if d.is_melee() or d.is_continuous():
		return
	# tempo: token bucket — lag może skumulować kilka strzałów, ale nie więcej niż RATE_CAP
	var now := Time.get_ticks_msec()
	_srv_tokens = minf(RATE_CAP, _srv_tokens + float(now - _srv_last_ms) / (maxf(d.cooldown, 0.05) * 1000.0))
	_srv_last_ms = now
	if _srv_tokens < 1.0:
		return
	_srv_tokens -= 1.0
	var expect := muzzle_pos(dir.normalized(), d)
	if muzzle.distance_to(expect) > MUZZLE_TOLERANCE:
		muzzle = expect
	# kompensacja opóźnienia: serwer sam mierzy RTT strzelca (lag_comp.gd), klient niczego nie deklaruje
	var lag := LagComp.rewind_for(player.player_id)
	_server_fire(muzzle, dir.normalized(), w, seed, clampf(extra, 0.0, 12.0), player.player_id, false, lag, d.build)

## Autorytatywny strzał (serwer). `own_fx_done` = strzelec (host) już zagrał swoje efekty. `build` = części i typ naboju (Weapons.build_of).
func _server_fire(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float, shooter: int, own_fx_done: bool, lag := 0.0, build := 0) -> void:
	var d := Weapons.def_build(w, build)
	srv_shots += 1
	Lights.add_flash(muzzle, d.flash_light, player)
	match d.kind:
		WeaponDef.Kind.RAIL:
			_server_rail(d, muzzle, dir, shooter, lag)
		_:
			_spawn_projectiles(d, muzzle, dir, seed, extra, shooter, true, lag)
	if not own_fx_done:
		_remote_shot_fx(d, muzzle, dir)
	if NoiseMgr.has_network():
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_fire_remote.rpc_id(peer, muzzle, dir, w, seed, extra, shooter, d.build)

## Kosmetyka cudzego strzału u klientów (serwer wywołuje na węźle należącym do KLIENTA).
@rpc("any_peer", "call_remote", "unreliable")
func _fire_remote(muzzle: Vector2, dir: Vector2, w: int, seed: int, extra: float, shooter: int, build: int) -> void:
	if NoiseMgr.is_server() or multiplayer.get_remote_sender_id() != 1 or not Weapons.is_valid(w):
		return
	var d := Weapons.def_build(w, build)
	if d.kind != WeaponDef.Kind.RAIL:
		_spawn_projectiles(d, muzzle, dir, seed, extra, shooter, false)
	_remote_shot_fx(d, muzzle, dir)

## Szyna: trafienie natychmiastowe, przebija wszystkich (i opcjonalnie cienką ścianę).
## Serwer rysuje tor u siebie; strzelec-klient narysował go sam w predykcji, reszta dostaje RPC.
func _server_rail(d: WeaponDef, muzzle: Vector2, dir: Vector2, shooter: int, lag := 0.0) -> void:
	var space := player.get_world_2d().direct_space_state
	# lag > 0: trafiamy wrogów w pozycjach sprzed `lag` s (szyna jest natychmiastowa — jeden test w przeszłość)
	var tr := Combat.trace(space, muzzle, dir, d.range_px, int(d.pierce), d.wall_pierce, [player.get_rid()], LagComp.now() - lag if lag > 0.0 else -1.0)
	for h in tr["hits"]:
		var info := Combat.make_info(d.id, d.damage, h["pos"], dir, shooter, "rail", d.build)
		info["heavy"] = true
		Combat.apply_and_report(h["collider"], info)
	_rail_visual(d, muzzle, tr["end"], tr)
	if NoiseMgr.has_network():
		for peer in multiplayer.get_peers():
			if peer != shooter:
				_tracer_remote.rpc_id(peer, muzzle, tr["end"], d.id, tr["wall"], tr["wall_normal"])

@rpc("any_peer", "call_remote", "unreliable")
func _tracer_remote(from: Vector2, to: Vector2, w: int, wall: bool, normal: Vector2) -> void:
	if NoiseMgr.is_server() or multiplayer.get_remote_sender_id() != 1 or not Weapons.is_valid(w):
		return
	_rail_visual(Weapons.def(w), from, to, {"wall": wall, "wall_normal": normal})

func _rail_visual(d: WeaponDef, from: Vector2, to: Vector2, tr: Dictionary) -> void:
	var parent: Node = player._fx_root()
	Vfx.streak(parent, from, to, d.tracer_color, 2.0, 0.22)
	if bool(tr.get("wall", false)):
		var lvl := get_tree().get_first_node_in_group("level")
		var surface := "metal"
		if lvl != null:
			surface = lvl.surface_at_hit(to, tr["wall_normal"])
		Vfx.impact(parent, to, tr["wall_normal"], surface, true)

# ---------------------------------------------------------------- ciągły ogień (serwer)

func _physics_process(delta: float) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if not player.w_firing:
		_srv_tick = 0.0
		_srv_patch_t = 0.0
		return
	var d := server_def(player.weapon)
	if not d.is_continuous() or bool(player.get("in_range")):
		return                                                   # na strzelnicy promień i płomień są w tunelu, nie w kryjówce (bez ognia przy drzwiach)
	_srv_tick -= delta
	_srv_fx_t -= delta
	if _srv_tick > 0.0:
		return
	_srv_tick += d.cooldown
	if _srv_tick < 0.0:
		_srv_tick = 0.0
	var dir: Vector2 = player.aim_dir
	var origin := muzzle_pos(dir, d)                     # ten sam wylot co kule (poza nominalna, lufa nie wychodzi za ścianę)
	var space := player.get_world_2d().direct_space_state
	var report := _srv_fx_t <= 0.0
	if report:
		_srv_fx_t = FX_REPORT_EVERY
	if d.kind == WeaponDef.Kind.BEAM:
		var tr := beam_trace(d, dir)
		for h in tr["hits"]:
			_continuous_hit(d, h["collider"], h["pos"], dir, "beam", report, d.damage * d.falloff(float(h["dist"])))   # wiązka słabnie z dystansem
	else:
		for t in Combat.in_cone(get_tree(), space, origin, dir, d.range_px, d.arc_deg):
			var c := Combat.center_of(t)
			var dist := c.distance_to(origin)
			var info_amount := d.damage * d.falloff(dist)
			_continuous_hit(d, t, c, dir, "fire", report, info_amount)
		_srv_patch_t += d.cooldown
		if _srv_patch_t >= d.patch_every:
			_srv_patch_t = 0.0
			_drop_fire_patch(d, space, origin, dir)

## Ślad wiązki (LR-7) od wylotu lufy — jeden dla obrażeń (serwer) i obrazu (weapon_view.gd), więc promień kończy się tam,
## gdzie naprawdę rani. Wcześniej serwer liczył go od środka tułowia, a obraz od animowanej lufy modelu.
func beam_trace(d: WeaponDef, dir: Vector2) -> Dictionary:
	return Combat.trace(player.get_world_2d().direct_space_state, muzzle_pos(dir, d), dir, d.range_px, int(d.pierce), 0.0, [player.get_rid()])

## Koniec płomienia (albo mur, w który uderza) rzutowany w dół na podłogę — tam zostaje ogień.
func _drop_fire_patch(d: WeaponDef, space: PhysicsDirectSpaceState2D, origin: Vector2, dir: Vector2) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.has_method("spawn_fire_patch"):
		return
	var tip := origin + dir * d.range_px * 0.9
	var wall := space.intersect_ray(PhysicsRayQueryParameters2D.create(origin, tip, 1))
	if not wall.is_empty():
		tip = (wall["position"] as Vector2) - dir * 4.0
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters2D.create(tip, tip + Vector2(0.0, FIRE_DROP_MAX), 1 | 16))
	if floor_hit.is_empty():
		return
	lvl.spawn_fire_patch((floor_hit["position"] as Vector2) + Vector2(0.0, -1.0), d.id, player.player_id, d.patch_life)

func _continuous_hit(d: WeaponDef, target: Node, pos: Vector2, dir: Vector2, type: String, report: bool, amount := -1.0) -> void:
	var info := Combat.make_info(d.id, d.damage if amount < 0.0 else amount, pos, dir, player.player_id, type, d.build)
	info["heavy"] = false
	var res := Combat.apply(target, info)
	if report:
		Combat.report(info, res)

# ---------------------------------------------------------------- przeładowanie

func try_reload(auto := false) -> bool:
	var d := cur()
	if not d.uses_ammo() or state != State.READY:
		return false
	if jammed(d.id) in ["overheat", "arc"]:
		return false                                       # awaria broni eksperymentalnej mija sama
	if jammed(d.id) != "":
		if not auto:
			_start_clear(d)                                # [R] przy zacięciu: najpierw usunąć zacięcie
		return not auto
	_shots_mag[d.id] = 0
	var t := next_ammo_of(d.id)
	var swap := t != ammo_of(d.id)                     # inny typ naboju: cały magazynek (z komorą) wraca do zapasu, ładujemy nowy
	var cap := d.capacity(mag_of(d.id) > 0)           # nabój w komorze: z pełnym magazynkiem można jeszcze dołożyć jeden (30+1)
	if mag_of(d.id) >= cap and not swap:
		return false
	if not _free_ammo(d) and Arsenal.get_reserve(d.id, t) <= 0 and ammo_enabled:
		if swap:
			want_ammo[d.id] = ammo_of(d.id)                # wybranego typu już nie ma — zostaje to, co jest w magazynku
			ammo_changed.emit(d.id, ammo_of(d.id))
		if not auto:
			Audio.play("dry_fire", Audio.BUS_WEAPONS, -10.0, 0.8)
		return false
	if swap:
		if mag_of(d.id) > 0 and ammo_enabled:
			Arsenal.deposit(d.id, mag_of(d.id), ammo_of(d.id))
		mags[d.id] = 0
		loaded[d.id] = t
		d = cur()
		cap = d.capacity(false)
	firing = false
	_burst_left = 0
	state = State.RELOAD
	_rl_req = false
	_rl_pending = 0
	_rl_wait = 0.0
	_rl_cap = cap
	tactical = false
	_rl_out = MAG_OUT_AT if (d.mag_drop and Settings.realistic_handling and not swap) else -1.0
	if d.reload_per_round:
		_begin_round(d)
	else:
		_rl_total = (d.reload_time + (d.reload_empty_extra if mag_of(d.id) <= 0 else 0.0)) * mastery_mult(d.id)
		_rl_left = _rl_total
		_reload_sfx(d)
		_begin_motion(Motion.RELOAD, d.id, _rl_total, Motion.EMPTY if mag_of(d.id) <= 0 else Motion.TACTICAL)
	NoiseMgr.add_noise(NOISE_RELOAD, player.global_position, "reload")
	reload_started.emit(d.id)
	return true

## Naboje bez zapasu: broń o nieskończonej amunicji albo strzelnica (amunicja ćwiczebna).
func _free_ammo(d: WeaponDef) -> bool:
	return d.infinite or practice

func _reload_sfx(d: WeaponDef) -> void:
	if d.reload_sfx == "":
		return
	if range_sink != null and bool(range_sink.call("clip_sounds", d)):
		return                                             # strzelnica FPP: dźwięki mechaniki grają w klatkach klipu
	if is_owner():
		Audio.play_variant(d.reload_sfx, d.reload_sfx_count, Audio.BUS_WEAPONS, -8.0, 1.0)

func _begin_round(d: WeaponDef) -> void:
	_rl_total = d.reload_time * mastery_mult(d.id)
	_rl_left = _rl_total
	_rl_wait = 0.0
	_begin_motion(Motion.RELOAD, d.id, _rl_total, Motion.ROUND)
	_rl_req = true
	if _free_ammo(d):
		_rl_req = false
		_rl_pending += 1
	else:
		Arsenal.request_rounds(d.id, 1, ammo_of(d.id))
	_reload_sfx(d)

func _tick_reload(delta: float) -> void:
	var d := cur()
	if clearing:
		_rl_left -= delta
		if _rl_left <= 0.0:
			if jammed(d.id) in ["misfire", "double"]:
				mags[d.id] = maxi(0, mag_of(d.id) - 1)          # nabój z komory wylatuje na ziemię
			jams.erase(d.id)
			_finish_reload()
		return
	if _rl_out >= 0.0:
		_rl_out -= delta
		if _rl_out < 0.0:
			_mag_out(d)
	if _rl_req and _rl_left <= 0.0:
		_rl_wait += delta
		if _rl_wait > GRANT_TIMEOUT:
			_cancel_reload()
		return
	_rl_left -= delta
	if _rl_left > 0.0:
		return
	if d.reload_per_round:
		if _rl_pending > 0:
			_rl_pending -= 1
			mags[d.id] = mini(_rl_cap, mag_of(d.id) + 1)
		if mag_of(d.id) < _rl_cap and (_rl_req or _rl_pending > 0 or _free_ammo(d) or Arsenal.get_reserve(d.id, ammo_of(d.id)) > 0):
			_begin_round(d)
		elif not _rl_req:
			_finish_reload()
		return
	if not _rl_req:
		_rl_req = true
		_rl_wait = 0.0
		var want := _rl_cap - mag_of(d.id)
		if _free_ammo(d) or not ammo_enabled:
			_on_rounds_granted(d.id, want)
		else:
			Arsenal.request_rounds(d.id, want, ammo_of(d.id))

## Magazynek wychodzi z gniazda: [R] wciąż wciśnięte i są w nim naboje — przeładowanie taktyczne (dłuższe, resztki zostają);
## inaczej magazynek leci na ziemię z resztkami (w broni zostaje tylko nabój w komorze).
func _mag_out(d: WeaponDef) -> void:
	var keep := 1 if (d.chamber and mag_of(d.id) > 0) else 0
	var left := mag_of(d.id) - keep
	if left > 0 and reload_held:
		tactical = true
		_rl_left += TAC_EXTRA * mastery_mult(d.id)
		_rl_total += TAC_EXTRA * mastery_mult(d.id)
		return
	mags[d.id] = keep
	if practice:
		return                                             # strzelnica: magazynek z resztkami nie ląduje na podłodze kryjówki
	var n := left if (ammo_enabled and not d.infinite) else 0
	if n > 0:
		dropped_mags += 1
	if NoiseMgr.is_server():
		_spawn_mag(d.id, n, ammo_of(d.id))
	else:
		_drop_mag_rpc.rpc_id(1, d.id, n, ammo_of(d.id))

## Klient: upuściłem magazynek (`n` naboi typu `t`). Serwer sprawdza nadawcę, broń i liczbę (najwyżej pełny magazynek) — jak przy zwrocie naboi.
@rpc("any_peer", "call_remote", "reliable")
func _drop_mag_rpc(w: int, n: int, t: int) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead or multiplayer.get_remote_sender_id() != player.player_id:
		return
	if not Weapons.is_valid(w) or not Weapons.def(w).mag_drop or not Ammo.valid(String(Weapons.def(w).caliber), t):
		return
	_spawn_mag(w, clampi(n, 0, Parts.max_capacity(Weapons.def(w))), t)

## Serwer: magazynek na ziemi pod ręką gracza (znajdźka „mag”: arg = broń | typ naboju << 8, rounds = naboje), stuk o ziemię (hałas);
## na mapie leży najwyżej MAG_MAX magazynków — najstarsze znikają.
func _spawn_mag(w: int, n: int, t: int) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null:
		return
	var side := signf(player.aim_dir.x) if absf(player.aim_dir.x) > 0.1 else 1.0
	var pos := player.global_position + Vector2(side * 3.0, -10.0)
	lvl.spawn_item("mag", w | (t << 8), pos, n)
	NoiseMgr.add_noise(MAG_DROP_NOISE, pos, "mag_drop")
	var mags_on_map: Array = get_tree().get_nodes_in_group("pickups").filter(func(it: Node) -> bool: return it.get("kind") == "mag" and not it.is_queued_for_deletion())
	if mags_on_map.size() > MAG_MAX:
		mags_on_map.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		for i in mags_on_map.size() - MAG_MAX:
			lvl.take_item(mags_on_map[i].name, true)

func _finish_reload() -> void:
	state = State.READY
	_rl_req = false
	_rl_pending = 0
	_rl_left = 0.0
	_rl_out = -1.0
	clearing = false
	_sync_player()

func _cancel_reload() -> void:
	var d := cur()
	# naboje już przyznane, a jeszcze niewsunięte (strzelba), lądują w magazynku
	if _rl_pending > 0:
		var put := mini(_rl_pending, maxi(0, maxi(_rl_cap, d.mag) - mag_of(d.id)))
		mags[d.id] = mag_of(d.id) + put
		if _rl_pending > put and range_sink == null:
			Arsenal.deposit(d.id, _rl_pending - put, ammo_of(d.id))
	_finish_reload()

## Zmiana części lub zestawu: zachowuje rodzaj nabojów i komorę, oddaje nadmiar; większy magazynek nie daje nabojów.
func configuration_changed() -> void:
	_mass_sig = ""
	if player == null or not is_owner() or player.is_bot or range_sink != null:
		return
	for w in mags.keys():
		var n := mag_of(int(w))
		var cap: int = def_of(int(w)).capacity(n > 0)
		if n > cap:
			mags[w] = cap
			Arsenal.deposit(int(w), n - cap, ammo_of(int(w)))
	_sync_player()

func _on_rounds_granted(w: int, n: int) -> void:
	if player == null or not is_owner() or player.is_bot:
		return
	var d := def_of(w)
	var reloading := state == State.RELOAD and cur().id == w
	if reloading and not d.reload_per_round:
		var put := mini(n, maxi(0, _rl_cap - mag_of(w)))
		mags[w] = mag_of(w) + put
		if n > put and range_sink == null:
			Arsenal.deposit(w, n - put, ammo_of(w))
		_finish_reload()
		return
	if reloading and d.reload_per_round:
		_rl_req = false
		_rl_pending += n
		return
	# przeładowanie przerwane, zanim przyszła odpowiedź — wsuń do magazynka, nadmiar oddaj
	if n > 0 and loadout.has(w):
		var room := maxi(0, d.capacity(mag_of(w) > 0) - mag_of(w))
		var put := mini(room, n)
		mags[w] = mag_of(w) + put
		if n > put:
			Arsenal.deposit(w, n - put, ammo_of(w))
	elif n > 0:
		Arsenal.deposit(w, n, ammo_of(w))

# ---------------------------------------------------------------- broń biała

func try_melee() -> void:
	if player.dead or state == State.MELEE:
		return
	var md := def_of(melee_id)
	_cancel_actions()
	state = State.MELEE
	melee_total = md.cooldown
	state_t = md.cooldown
	_melee_pending = true
	cd = maxf(cd, 0.2)
	NoiseMgr.add_noise(md.noise(0.0), player.global_position, "shot:" + md.key)
	Audio.play_variant(md.sfx, md.sfx_count, Audio.BUS_WEAPONS, md.sfx_vol, 1.0)
	Feel.shake(md.shake * 0.5)
	_begin_motion(Motion.MELEE, melee_id, melee_total)
	melee_swung.emit(melee_id)

func _melee_resolve() -> void:
	var origin := player.global_position + Vector2(0, -9)
	var dir: Vector2 = player.aim_dir
	var key := String(Weapons.def(melee_id).key)
	var e := 100.0 if player.is_bot else Profile.edge_of(key)              # ostrze siedzi w profilu gracza — idzie z ciosem (serwer przycina)
	if not player.is_bot and Settings.reliability_mult() > 0.0:
		Profile.wear_edge(key, Profile.EDGE_WEAR * Settings.reliability_mult())
	if NoiseMgr.is_server():
		_server_melee(origin, dir, melee_id, player.player_id, e)
	else:
		_melee_request.rpc_id(1, origin, dir, melee_id, e)

@rpc("any_peer", "call_remote", "reliable")
func _melee_request(origin: Vector2, dir: Vector2, w: int, e: float = 100.0) -> void:
	if not NoiseMgr.is_server() or player == null or player.dead:
		return
	if multiplayer.get_remote_sender_id() != player.player_id or not Weapons.is_valid(w) or not Weapons.def(w).is_melee():
		return
	var expect := player.global_position + Vector2(0, -9)
	if origin.distance_to(expect) > MUZZLE_TOLERANCE:
		origin = expect
	_server_melee(origin, dir.normalized(), w, player.player_id, clampf(e, 0.0, 100.0))

func _server_melee(origin: Vector2, dir: Vector2, w: int, shooter: int, e: float = 100.0) -> void:
	var d := server_def(w)                                      # części gracza, ale tylko odblokowane przez drużynę
	d.damage *= Profile.edge_mult(e) if Settings.reliability_mult() > 0.0 else 1.0     # tępe ostrze rani słabiej (W6b; niezawodność OFF — bez)
	var space := player.get_world_2d().direct_space_state
	var hit_any := false
	for t in Combat.in_cone(get_tree(), space, origin, dir, d.reach, d.arc_deg):
		var c := Combat.center_of(t)
		var info := Combat.make_info(w, d.damage, c, dir, shooter, "melee", d.build)
		info["backstab"] = d.key == "maczeta"
		info["heavy"] = d.damage >= 50.0
		var res := Combat.apply(t, info)
		Combat.report(info, res)
		hit_any = hit_any or bool(res["hit"])
	if not hit_any:
		var q := PhysicsRayQueryParameters2D.create(origin, origin + dir * d.reach, Combat.LAYER_WORLD)
		var wall := space.intersect_ray(q)
		if not wall.is_empty():
			Arsenal.broadcast_hit(wall["position"], -dir, Arsenal.Mat.METAL, false, d.damage >= 50.0)

# ---------------------------------------------------------------- podnoszenie i zamiana broni

func nearby_weapon_item() -> Node2D:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or player == null:
		return null
	return lvl.weapon_item_near(player.global_position + Vector2(0, -8))

## Przy broni (stojak albo łup na ziemi): [H] otwiera / zamyka oględziny (widok z oczu gracza, broń unosi się przed nim, statystyki obok —
## weapon_inspect.gd i view3d.gd, lokalnie), [E] bierze broń (zamianę rozstrzyga serwer). Oględziny mają osobną akcję inspect_weapon,
## więc [F] nadal rzuca flarę obok broni (player.gd). Odejście od broni albo utrata zdrowia zamyka oględziny.
## Gablota (cabinet.gd): oględziny obejmują całą gablotę — ↑ / ↓ wybiera broń rząd wyżej / niżej, [E] bierze wybraną; zamyka je dopiero odejście
## od gabloty (najbliższa broń jest wtedy z innej gabloty albo żadna).
func _tick_inspect() -> void:
	var it := nearby_weapon_item()
	var hp_v = player.get("hp")
	var hp_now := float(hp_v) if hp_v != null else 0.0
	if inspect_item != null and (not is_instance_valid(inspect_item) or inspect_item.is_queued_for_deletion() or hp_now < _inspect_hp
			or (it != inspect_item and not _same_cabinet(it, inspect_item)) or not inspect_item.in_reach(player)):
		inspect_item = null
	if it == null:
		return
	if inspect_item != null and inspect_item.has_meta("cabinet"):
		if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("menu_up"):
			_cycle_cabinet(-1)
		elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("menu_down"):
			_cycle_cabinet(1)
	if inspect_item != null:
		if Input.is_action_just_pressed("menu_slot_1"):
			inspect_slot = 0
		elif Input.is_action_just_pressed("menu_slot_2"):
			inspect_slot = 1
	if Input.is_action_just_pressed("inspect_weapon"):
		inspect_item = null if (inspect_item == it or _same_cabinet(inspect_item, it)) else it
		inspect_slot = slot if slot < 2 else 0
		_inspect_hp = hp_now
		Audio.play("ui_click", Audio.BUS_UI, -16.0)
	elif Input.is_action_just_pressed("interact"):
		_try_pickup(inspect_item)

## Czy dwa przedmioty broni wiszą w tej samej gablocie (meta „cabinet" z level.gd).
static func _same_cabinet(a: Node, b: Node) -> bool:
	return a != null and b != null and is_instance_valid(a) and is_instance_valid(b) and a.has_meta("cabinet") and b.has_meta("cabinet") \
			and int(a.get_meta("cabinet")) == int(b.get_meta("cabinet"))

## Oględziny gabloty: wybór broni rząd wyżej (step −1) albo niżej (+1); puste haki (broń wzięta) są pomijane, na krańcach wybór stoi.
func _cycle_cabinet(step: int) -> void:
	if inspect_item == null or not is_instance_valid(inspect_item):
		return
	var cab := int(inspect_item.get_meta("cabinet"))
	var items: Array = get_tree().get_nodes_in_group("pickups").filter(func(n: Node) -> bool:
		return n.has_meta("cabinet") and int(n.get_meta("cabinet")) == cab and not n.is_queued_for_deletion())
	items.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get_meta("slot")) < int(b.get_meta("slot")))
	var i := items.find(inspect_item)
	var j := clampi(i + step, 0, items.size() - 1)
	if i < 0 or j == i:
		return
	inspect_item = items[j]
	Audio.play("ui_click", Audio.BUS_UI, -18.0)

func select_cabinet_slot(row: int) -> void:
	if inspect_item == null or not is_instance_valid(inspect_item) or not inspect_item.has_meta("cabinet"):
		return
	var level := get_tree().get_first_node_in_group("level")
	if level == null or row < 0 or row >= int(level._cab_slots):
		return
	var name := "MapGun%d" % (int(inspect_item.get_meta("cabinet")) * int(level._cab_slots) + row)
	var item := level.get_node_or_null(name) as Node2D
	if item != null and not item.is_queued_for_deletion() and item.in_reach(player):
		inspect_item = item

## [E]: bierze `target` (broń wybraną w oględzinach), a bez niej — najbliższą. Zamianę rozstrzyga serwer (odległość, blokada).
func _try_pickup(target: Node2D = null) -> void:
	var it := target if target != null and is_instance_valid(target) and not target.is_queued_for_deletion() else nearby_weapon_item()
	if it == null:
		return
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl.is_locked_item(it):
		Audio.play("ui_deny", Audio.BUS_UI, -14.0)
		Msg.post("armory.locked", Msg.Ch.TOAST, tr("LOCKED  ·  %s") % Scrap.lock_text(int(it.arg)), {"ttl": 3.0, "style": Msg.Style.WARN})
		return
	lvl.request_weapon_pickup(it.name, inspect_slot if inspect_item != null else (slot if slot < 2 else 0))

## Strzelnica FPP (fp_mode.gd): zestaw w chwili wejścia — bronie, magazynki, typy naboi, zacięcia, temperatury. Przy wyjściu `range_restore`
## przywraca go w całości: broń z szafy strzelnicy i strzały ćwiczebne nie zmieniają sprzętu, z którym gracz wraca do kryjówki.
func range_snapshot() -> Dictionary:
	return {"loadout": loadout.duplicate(), "slot": slot, "mags": mags.duplicate(), "loaded": loaded.duplicate(), "want_ammo": want_ammo.duplicate(),
		"jams": jams.duplicate(), "burst_on": burst_on.duplicate(), "heat": _heat.duplicate(), "barrel": _barrel.duplicate(),
		"shots_mag": _shots_mag.duplicate()}

func range_restore(s: Dictionary) -> void:
	range_fit.clear()                                           # próbne części zostają w szafie strzelnicy
	if s.is_empty():
		return
	_cancel_actions()
	loadout.assign(s["loadout"])
	slot = int(s["slot"])
	mags = (s["mags"] as Dictionary).duplicate()
	loaded = (s["loaded"] as Dictionary).duplicate()
	want_ammo = (s["want_ammo"] as Dictionary).duplicate()
	jams = (s["jams"] as Dictionary).duplicate()
	burst_on = (s["burst_on"] as Dictionary).duplicate()
	_heat = (s["heat"] as Dictionary).duplicate()
	_barrel = (s["barrel"] as Dictionary).duplicate()
	_shots_mag = (s["shots_mag"] as Dictionary).duplicate()
	state = State.READY
	state_t = 0.0
	clearing = false
	climb = 0.0
	bloom = 0.0
	cd = 0.0
	_sync_player()

## Szafa strzelnicy (fp_mode.gd): broń `w` do ręki na czas strzelnicy — z pełnym magazynkiem, bez zapasu, bez porzucania własnej (zestaw z wejścia
## wraca przez `range_restore`). Broń, którą gracz już niesie, tylko się dobywa; długa zastępuje trzymaną długą (albo pierwszą, gdy w ręku pistolet).
func range_take(w: int) -> void:
	if not Weapons.is_valid(w):
		return
	var d := Weapons.def(w)
	if d.slot == Weapons.Slot.MELEE:
		return
	var have := loadout.find(w)
	if have >= 0:
		select_slot(have)
		return
	var target := 2 if d.slot == Weapons.Slot.SIDEARM else (slot if slot < 2 else 0)
	_cancel_actions()
	loadout[target] = w
	mags[w] = d.mag
	jams.erase(w)
	loaded.erase(w)
	want_ammo.erase(w)
	if target == slot:
		state = State.DRAW
		state_t = d.draw_time * mastery_mult(d.id)
		Audio.play_variant("foley_gear", 3, Audio.BUS_PLAYER, -14.0, 1.0)
		_sync_player()
	else:
		select_slot(target)

## Szafa strzelnicy, próba części (WORKSHOP_PLAN.md U5): broń `w` z kodem części `code` do ręki — z pełnym magazynkiem, bo część może go zmienić.
## Działa tylko na strzelnicy; zestaw z wejścia wraca przez `range_restore`.
func range_try(w: int, code: int) -> void:
	if range_sink == null or not Weapons.is_valid(w):
		return
	range_fit[w] = code
	if carries(w):
		_cancel_actions()
		mags[w] = def_of(w).mag
		jams.erase(w)
		if loadout[slot] == w:
			state = State.READY
			_sync_player()
			return
	range_take(w)
	mags[w] = def_of(w).mag

## Czy broń `w` ma na strzelnicy próbną część, której drużyna jeszcze nie ma.
func range_trial(w: int) -> bool:
	if not range_fit.has(w):
		return false
	for id in Parts.decode(String(Weapons.def(w).key), int(range_fit[w])):
		if not Scrap.has_part(String(id)):
			return true
	return false

## Serwer przyznał broń (po sprawdzeniu odległości). Zastępuje bieżącą główną, jeśli nie masz
## już tej samej; porzucona broń leży pod stopami, jej magazynek wraca do wspólnego zapasu.
@rpc("any_peer", "call_remote", "reliable")
func grant_weapon(w: int, target_slot := -1) -> void:
	var sender := multiplayer.get_remote_sender_id() if NoiseMgr.has_network() else 0
	if sender != 0 and sender != 1:
		return
	if not Weapons.is_valid(w):
		return
	var d := Weapons.def(w)
	if carries(w):
		return          # znana broń: naboje już poszły do zapasu (level.gd)
	if d.slot == Weapons.Slot.MELEE:
		melee_id = w
		_sync_player()
		return
	if d.slot != Weapons.Slot.PRIMARY:
		return
	var target := target_slot if target_slot >= 0 and target_slot < 2 else (slot if slot < 2 else 0)
	var old := loadout[target]
	_cancel_actions()
	if mag_of(old) > 0:
		Arsenal.deposit(old, mag_of(old), ammo_of(old))
	mags.erase(old)
	loaded.erase(old)
	want_ammo.erase(old)
	loadout[target] = w
	mags[w] = 0
	if target == slot:
		state = State.DRAW
		state_t = d.draw_time * mastery_mult(d.id)
	Audio.play("weapon_pickup", Audio.BUS_UI, -8.0)
	_sync_player()          # pusty magazynek nowej broni ładuje się sam po dobyciu
