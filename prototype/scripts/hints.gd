extends RefCounted
## Podpowiedzi dla nowego gracza — krótkie, pokazywane jednorazowo w chwili, gdy mechanika się przydaje
## (a nie ścianą tekstu na starcie). Raz pokazana podpowiedź jest zapamiętana w Settings.seen_tips,
## więc weteran ich nie widzi; wyłącznik w menu pauzy.
##
## `update()` jest wołane co klatkę przez hud.gd i zwraca bieżący tekst ("" = brak) — hud tylko go rysuje.

const Weapons := preload("res://scripts/weapons.gd")
const Actions := preload("res://scripts/actions.gd")
const SessionLog := preload("res://scripts/session_log.gd")

const SHOW_S := 7.0                  ## ile sekund wisi podpowiedź
const GAP_S := 2.5                   ## przerwa między podpowiedziami
const FADE_S := 0.5
const DIG_TIP_PX := 96.0             ## porada o kopaniu i skanerze (1.1): tak blisko strefy wydobycia

## [id, tekst]; kolejność = priorytet, gdy kilka warunków spełnia się naraz
const TIPS := [
	["move", "{move} to move  ·  {jump} to jump  ·  hold {crouch} to sneak — sneaking is silent"],
	["hub", "Safe room — nothing hunts you here. Read the board, spend scrap at the workshop bench ({interact}), then press {restart} to ready up"],
	["noise", "Every shot makes NOISE. Watch the meter in the top-left corner"],
	["ford", "Water slows you and splashes — running through it is loud. Mud muffles your steps but drags you down. Something big sleeps on the bank: hold {crouch} under it. Crouched in the reeds, eyes slide past you"],
	["camp", "A pack sleeps under the broken bridge and the gap is too wide to jump. Go up into the branches — or hold {crouch} on the bridge and they stay asleep"],
	["culvert", "A pack sleeps across the yard. The hatch at your feet drops into an old culvert that runs under them to the station well — {crouch} all the way through: they hear you through the ground"],
	["sneak", "Something is asleep close by — hold {crouch} and walk: a crouching step is silent and wakes it from half the distance"],
	["quiet", "Attention is up. Stop shooting — in silence the meter drains fast. Sneaking ({crouch}) is silent too"],
	["broadcast", "The transmitter is live and HE heard it. Press {overcharge} to throw a lure and pull him away — then run for the exit"],
	["handcar", "Stand on the handcar and HOLD {interact} to pump — more hands, more speed. You cannot shoot while pumping"],
	["generator", "Hold {interact} at a generator to start it. The work is loud, and a running generator keeps humming"],
	["uneasy", "Something is listening. Stop shooting, sneak ({crouch}) — or press {overcharge} to lure it away"],
	["revive", "A friend is down — stand next to them and HOLD {interact} to revive"],
	["downed", "You are down. Stay still — a teammate can revive you before you bleed out"],
	["downed_solo", "You are down and no one can revive you. Bleed out and you wake up further back (the start, the last generator, the handcar) — fall again and the attempt is lost"],
	["light", "{flashlight} toggles the flashlight. Light is noise too — turn it off to hide"],
	["battery_low", "The flashlight battery is running low. Flat 4.5 V batteries lie around the map, drop from enemies and from smashed moth nests — and the light slowly recharges while switched off"],
	["moths", "Moths nest under the watchtower roof and swarm any light they can see — your flashlight, even muzzle flashes. Bullets and fire do not touch them: throw a flare ({flare}) away from you to draw the swarm off, or cut them down with your blade ({melee})"],
	["adit", "An old drainage adit runs west under the camp and comes up through a hatch in its hollow. Board this opening up behind you (hold {interact}) — whatever hunts you will have to smash through"],
	["moths_on", "Moths are smothering your flashlight: the beam dims, the battery drains and their fluttering is loud. Swing your blade ({melee}) through them or switch the light off ({flashlight}) to shake them — killed at your face, they raise dust that makes you cough"],
	["flare", "{flare} throws a flare: bait that draws enemies with light instead of noise"],
	["scream", "{scream} screams: a burst of NOISE that pulls every enemy nearby — and HIM. Turn on the microphone in the lobby and the game hears your real scream"],
	["scream_mic", "The microphone is on: scream for real (or press {scream}) and everything nearby comes running. Whispering is safe"],
	["grenade", "{throw} uses the selected item (grenades, mine, charge, medkit, defibrillator, scanner), {throw_next} switches. A frag or a charge hurts the squad too"],
	["pickaxe", "Melee ({melee}) at a wall, grate or rubble swings the pickaxe — everyone carries one ({tool} any time). It is loud"],
	["dig_scanner", "This rock face can be dug: melee ({melee}) swings the pickaxe. Metal buried in it shows on the OWL scanner (workshop) — pick it with {throw_next}, use it with {throw}"],
	["firemode", "{firemode} switches the M-83 between full auto and a quiet 3-round burst"],
	["jam", "Jammed! Tap {reload} to clear it. A dirty gun jams more often — clean it at the maintenance table in the safe room"],
	["samples", "SAMPLES (from elites, bosses and side goals) go to the LAB bench here in the safe room ({interact}): they research parts for special weapons"],
	["service_open", "Weapon wear is on: the MAINTENANCE table ({interact}) cleans your guns and swaps worn barrels and springs. Dirty guns jam"],
	["lathe_open", "The LATHE downstairs is running ({interact}): it machines parts from schematics and sharpens blades"],
	["magdrop", "A quick tap of {reload} drops the magazine with the rounds still in it — crouch ({crouch}) over it to get them back. Hold {reload} for a slower reload that keeps them"],
]

var current := ""                    ## tekst w tej chwili
var alpha := 0.0
var _id := ""
var _t := 0.0                        ## ile już wisi bieżąca podpowiedź
var _gap := 1.5                      ## odliczanie do następnej
var _session := 0.0
var _noise_seen := 0.0
var _queued := {}                    ## id → true (warunek spełniony, czeka na swoją kolej)

func reset() -> void:
	current = ""
	alpha = 0.0
	_id = ""
	_t = 0.0
	_gap = 1.5
	_session = 0.0
	_queued.clear()

## `p` = lokalny gracz (może być null).
func update(delta: float, p: Node) -> String:
	if not Settings.hints_on or p == null:
		alpha = maxf(0.0, alpha - delta / FADE_S)
		if alpha <= 0.0:
			current = ""
		return current
	_session += delta
	_collect(p)
	if _id != "":
		_t += delta
		alpha = clampf(minf(_t / FADE_S, (SHOW_S - _t) / FADE_S), 0.0, 1.0)
		if _t >= SHOW_S:
			Settings.mark_tip(_id)
			_id = ""
			current = ""
			_gap = GAP_S
	else:
		_gap -= delta
		if _gap <= 0.0:
			_start_next()
	return current

func _start_next() -> void:
	for tip in TIPS:
		var id: String = tip[0]
		if _queued.has(id) and not Settings.tip_seen(id):
			_id = id
			SessionLog.event("hint", {"id": id})          # playtest: czy gracz użył mechaniki przed podpowiedzią, czy dopiero po niej
			current = Actions.fmt(tr(tip[1]))
			_t = 0.0
			alpha = 0.0
			_queued.erase(id)
			return

func _collect(p: Node) -> void:
	# trwałe: warunek raz spełniony, podpowiedź czeka na swoją kolej
	_queue("move", _session > 2.0, true)
	var mn = p.get_tree().current_scene.get("mission") if p.get_tree().current_scene != null else null
	_queue("hub", mn != null and mn.kind == "hub" and _session > 4.0, true)
	# próbki (opinia testera 2026-10-29: „nie wiem, do czego służą próbki”): pierwsza wizyta w kryjówce z próbkami w banku
	_queue("samples", mn != null and mn.kind == "hub" and _session > 12.0 and Scrap.samples > 0, true)
	# stanowiska uśpione do pierwszego otwarcia (HUB_LAYOUT_PLAN.md E4): raz, przy pierwszym pobycie, w którym działają; pracownię zapowiada „samples”
	_queue("service_open", mn != null and mn.kind == "hub" and _session > 16.0 and Settings.reliability_mult() > 0.0, true)
	_queue("lathe_open", mn != null and mn.kind == "hub" and _session > 20.0 and Scrap.lathe_open(), true)
	_queue("noise", NoiseMgr.level >= 8.0, true)
	var lvl_n = p.get_tree().get_first_node_in_group("level")
	var below: bool = lvl_n != null and p.global_position.y > float(lvl_n.underground_y) and float(lvl_n.underground_y) > 0.0
	_queue("light", _session > 45.0 or (below and not p.flashlight == true), true)
	_queue("battery_low", p.get("bat_pct") != null and int(p.bat_pct) < 20, true)       # słaba bateria (BATTERY_PLAN.md B2): skąd wziąć nową
	_queue("flare", _session > 150.0, true)
	# krzyk (GDD §8.2): hak gry, którego dotąd nic nie uczyło — mikrofon jest opt-in w lobby, więc podpowiedź mówi, gdzie go włączyć
	_queue("scream", _session > 210.0 and not Voice.enabled, true)
	_queue("scream_mic", _session > 210.0 and Voice.enabled, true)
	var wall_near := false
	for bw in p.get_tree().get_nodes_in_group("breakables"):
		if p.global_position.distance_to(bw.global_position) < 70.0:
			wall_near = true
	_queue("grenade", _session > 120.0, true)
	_queue("pickaxe", wall_near, false)                     # kilof ma każdy (B1) — podpowiedź dla każdego przy pierwszej przegrodzie
	# strefa wydobycia (D5) tylko na 1.1 (prośba z 2026-11-06): przy ścianie strefy — że da się kopać i że skaner „Sowa” widzi metal w skale
	var dig_near := false
	if lvl_n != null and String(lvl_n.get("map_id")) == "z1_m1":
		for z in p.get_tree().get_nodes_in_group("dig_zones"):
			if (z.rect_px() as Rect2).grow(DIG_TIP_PX).has_point(p.global_position):
				dig_near = true
				break
	_queue("dig_scanner", dig_near, false)
	_queue("firemode", _session > 90.0 and p.weapons != null and p.weapons.cur().burst_size > 0, true)
	_queue("jam", p.weapons != null and int(p.weapons.jam_count) > 0, true)                  # pierwsze zacięcie (etap 4a)
	_queue("magdrop", p.weapons != null and int(p.weapons.dropped_mags) > 0, true)          # szybkie przeładowanie upuściło magazynek z nabojami (etap 3c)
	# chwilowe: gdy sytuacja minie, zanim przyjdzie kolej, podpowiedź przepada
	_queue("uneasy", NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD or NoiseMgr.stalker_awake, false)
	var alone := p.get_tree().get_nodes_in_group("players").filter(func(q: Node) -> bool: return not q.is_queued_for_deletion()).size() == 1
	_queue("downed", bool(p.dead) and not alone, false)
	_queue("downed_solo", bool(p.dead) and alone, false)             # sam bez bota (NOBOT_PLAN.md D1a): nikt nie podniesie
	# cisza (misja 1.1): śpiący wróg tuż obok, a gracz idzie wyprostowany; po strzelaninie — nic nie goni, a Uwaga wciąż wysoka
	var sleeper_near := false
	var threat_near := false
	for e in p.get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not e.has_method("is_threat") or e.get("alive") != true:
			continue
		var dd: float = (e as Node2D).global_position.distance_to(p.global_position)
		if e.get("active") == true:
			if dd < 420.0:
				threat_near = true
		elif dd < 130.0:
			sleeper_near = true
	_queue("sneak", sleeper_near and not p.crouching == true, false)
	# bród (misja 1.1, HINT_ZONES „ford”): przy wodzie — lekcja powierzchni (woda, błoto) i kucania pod śpiącym na skarpie
	var ford_zone = lvl_n.get("hint_zones").get("ford") if lvl_n != null and lvl_n.get("hint_zones") != null else null
	_queue("ford", ford_zone is Rect2 and (ford_zone as Rect2).has_point(p.global_position), true)      # trwała: tuż po starcie wisi jeszcze „move”
	# obóz (misja 1.1, HINT_ZONES): na podejściu, póki wataha śpi — wskazuje cichą drogę konarami (MAPS_PLAN.md, playtest 2026-10-18)
	var camp_zone = lvl_n.get("hint_zones").get("camp") if lvl_n != null and lvl_n.get("hint_zones") != null else null
	var camp_asleep := false
	if camp_zone is Rect2 and (camp_zone as Rect2).has_point(p.global_position):
		for e in p.get_tree().get_nodes_in_group("enemies"):
			var near_x: bool = e is Node2D and absf((e as Node2D).global_position.x - p.global_position.x) < 500.0
			if near_x and e.get("alive") == true and e.get("active") == false and e.get("kind") == "trzosek":
				camp_asleep = true
				break
	_queue("camp", camp_asleep, false)
	# przepust (misja 1.2, HINT_ZONES „culvert”, MAPS_PLAN.md §4): przed watahą na dziedzińcu, póki śpi — cicha droga pod nią, tylko na kucaka
	var culvert_zone = lvl_n.get("hint_zones").get("culvert") if lvl_n != null and lvl_n.get("hint_zones") != null else null
	var yard_asleep := false
	if culvert_zone is Rect2 and (culvert_zone as Rect2).has_point(p.global_position):
		for e in p.get_tree().get_nodes_in_group("enemies"):
			var near_y: bool = e is Node2D and absf((e as Node2D).global_position.x - p.global_position.x) < 400.0 and absf((e as Node2D).global_position.y - p.global_position.y) < 80.0
			if near_y and e.get("alive") == true and e.get("active") == false and e.get("kind") == "trzosek":
				yard_asleep = true
				break
	_queue("culvert", yard_asleep, false)
	# strażnica (misja 1.1, HINT_ZONES „moths”): pod wieżą, póki ćmy wiszą pod dachem — lekcja flary
	var moth_zone = lvl_n.get("hint_zones").get("moths") if lvl_n != null and lvl_n.get("hint_zones") != null else null
	var moths_hang := false
	if moth_zone is Rect2 and (moth_zone as Rect2).has_point(p.global_position):
		for e in p.get_tree().get_nodes_in_group("enemies"):
			var near_m: bool = e is Node2D and absf((e as Node2D).global_position.x - p.global_position.x) < 500.0
			if near_m and e.get("alive") == true and e.get("active") == false and e.get("kind") == "cma":
				moths_hang = true
				break
	_queue("moths", moths_hang, false)
	# sztolnia (misja 1.1, HINT_ZONES „adit”, MAPS_PLAN.md §1.6 L2): przy pustym otworze, póki nie jest zabity deskami — po co go zabijać
	var adit_zone = lvl_n.get("hint_zones").get("adit") if lvl_n != null and lvl_n.get("hint_zones") != null else null
	var adit_open := false
	if adit_zone is Rect2 and (adit_zone as Rect2).has_point(p.global_position) and lvl_n.has_method("boards_of"):
		for sp in p.get_tree().get_nodes_in_group("barricade_spots"):
			if (adit_zone as Rect2).grow(16.0).has_point((sp as Node2D).global_position) and int(lvl_n.boards_of(String(sp.get("wall_name")))) < int(lvl_n.BOARDS):
				adit_open = true
				break
	_queue("adit", adit_open, false)
	_queue("moths_on", int(p.get("moth_cover")) > 0, false)        # rój na latarce: jak go strząsnąć
	_queue("quiet", NoiseMgr.level >= 22.0 and NoiseMgr.level < NoiseMgr.AWAKE_THRESHOLD and not threat_near, false)
	var friend_down := false
	for o in p.get_tree().get_nodes_in_group("players"):
		if o != p and bool(o.dead) and not o.is_queued_for_deletion() \
				and absf(o.global_position.x - p.global_position.x) < 160.0:
			friend_down = true
			break
	_queue("revive", friend_down, false)
	# misja 1.2: generator pod ręką; po ostatnim — lekcja Q na Stalkerze
	var near_gen := false
	for g in p.get_tree().get_nodes_in_group("generators"):
		if not g.running and absf(g.global_position.x - p.global_position.x) < 110.0 and absf(g.global_position.y - p.global_position.y) < 60.0:
			near_gen = true
			break
	_queue("generator", near_gen, false)
	var m = p.get_tree().current_scene.get("mission") if p.get_tree().current_scene else null
	var car = p.get_tree().get_first_node_in_group("handcar")
	_queue("handcar", car != null and car.enabled and not car.arrived and car.local_state != "", false)
	_queue("broadcast", m != null and m.kind == "generators" and m.phase == m.Phase.EXTRACT and NoiseMgr.stalker_awake, false)

func _queue(id: String, cond: bool, sticky: bool) -> void:
	if cond:
		if id != _id and not Settings.tip_seen(id):
			_queued[id] = true
	elif not sticky:
		_queued.erase(id)
