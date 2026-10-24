extends RefCounted
## Rejestr akcji wejściowych — jedno źródło prawdy o tym, jakie akcje ma gra i jakimi klawiszami / przyciskami się je wywołuje.
##
## Z niego korzystają: `input_setup.gd` (rejestracja w InputMap i wykrywanie urządzenia), `settings.gd` (które akcje wyciąć
## na czas menu), ściąga sterowania w lobby i menu pauzy (`sheet()`), pasek sterowania w HUD (`hud_line()`) oraz teksty
## podpowiedzi (`fmt()`, `key()`), więc nazwa klawisza nie jest wpisana ręcznie w kilkunastu miejscach. Teksty pokazują
## klawisze klawiatury albo pada — zależnie od tego, czego gracz użył ostatnio (`pad_mode`).
##
## Wiązanie to słownik: {"type": "key", "code": Key, "location": KeyLocation} (ANY/LEFT/RIGHT),
## {"type": "mouse", "button": MouseButton}, {"type": "joy", "button": JoyButton} albo
## {"type": "axis", "axis": JoyAxis, "value": ±1.0} (drążek lub spust). Klawisze to `physical_keycode` (układ-niezależne).
##
## Gracz może przypisać klawisz / przycisk pada do każdej akcji z `LABELS` (menu pauzy → CONTROLS): `set_binding()` podmienia
## wybrane wiązanie po walidacji całej zmiany w kontekstach. UI zatwierdza plan zamiany; zmiany idą do
## `user://settings.cfg` (sekcja „keys”, tylko akcje różne od domyślnych), `reset_defaults()` przywraca wszystko.

## id → ["keys": [Key | {"key": Key, "left": true}], "keys_macos": (zamiast keys na macOS), "mouse": [MouseButton],
##        "pad": [JoyButton], "axis": [[JoyAxis, ±1.0]], "deadzone": float (domyślnie 0.5),
##        "menu": true = akcja zostaje aktywna przy otwartym menu pauzy (reszta jest wycinana, żeby klik w menu nie strzelał)]
const Policy := preload("res://scripts/bindings_policy.gd")

const DEFS := {
	"move_left": {"keys": [KEY_A, KEY_LEFT], "axis": [[JOY_AXIS_LEFT_X, -1.0]], "deadzone": 0.3},
	"move_right": {"keys": [KEY_D, KEY_RIGHT], "axis": [[JOY_AXIS_LEFT_X, 1.0]], "deadzone": 0.3},
	"move_up": {"keys": [KEY_W, KEY_UP], "axis": [[JOY_AXIS_LEFT_Y, -1.0]], "deadzone": 0.3},
	"move_down": {"keys": [KEY_S, KEY_DOWN], "axis": [[JOY_AXIS_LEFT_Y, 1.0]], "deadzone": 0.3},
	# celowanie drugą gałką (swobodne, 360°); klawiatura i mysz celują jak dotąd (ruch / kursor)
	"aim_left": {"axis": [[JOY_AXIS_RIGHT_X, -1.0]], "deadzone": 0.3},
	"aim_right": {"axis": [[JOY_AXIS_RIGHT_X, 1.0]], "deadzone": 0.3},
	"aim_up": {"axis": [[JOY_AXIS_RIGHT_Y, -1.0]], "deadzone": 0.3},
	"aim_down": {"axis": [[JOY_AXIS_RIGHT_Y, 1.0]], "deadzone": 0.3},
	"jump": {"keys": [KEY_SPACE], "pad": [JOY_BUTTON_A]},
	"fire": {"keys": [KEY_J], "mouse": [MOUSE_BUTTON_LEFT], "axis": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
	"crouch": {"keys": [KEY_SHIFT], "pad": [JOY_BUTTON_LEFT_STICK]},
	"overcharge": {"keys": [KEY_Q], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
	"scream": {"keys": [KEY_G], "axis": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	"inspect_weapon": {"keys": [KEY_H]},
	"flare": {"keys": [KEY_F], "pad": [JOY_BUTTON_DPAD_RIGHT]},
	"interact": {"keys": [KEY_E], "pad": [JOY_BUTTON_B]},
	"weapon_1": {"keys": [KEY_1]},
	"weapon_2": {"keys": [KEY_2]},
	"weapon_3": {"keys": [KEY_3]},
	"restart": {"keys": [KEY_ENTER, KEY_KP_ENTER], "pad": [JOY_BUTTON_BACK]},
	"flashlight": {"keys": [KEY_L], "pad": [JOY_BUTTON_DPAD_LEFT]},
	"reload": {"keys": [KEY_R], "pad": [JOY_BUTTON_RIGHT_STICK]},
	"firemode": {"keys": [KEY_B], "pad": [JOY_BUTTON_DPAD_DOWN]},
	"ammo_type": {"keys": [KEY_Z]},                    # typ naboju na następny magazynek (ammo.gd); pad: bez domyślnego przycisku, można przypisać
	# użycie przedmiotu: lewy Alt (na macOS lewy Cmd pierwszy, lewy Alt też działa); prawy Alt / Cmd zostaje wolny
	"throw": {"keys": [{"key": KEY_ALT, "left": true}], "keys_macos": [{"key": KEY_META, "left": true}, {"key": KEY_ALT, "left": true}], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	"throw_next": {"keys": [KEY_X], "pad": [JOY_BUTTON_DPAD_UP]},
	"melee": {"keys": [KEY_V], "mouse": [MOUSE_BUTTON_RIGHT], "pad": [JOY_BUTTON_X]},
	# strzelnica FPP (scripts/range3d/fp_mode.gd): celowanie przez przyrządy — ten sam PPM co cios i ten sam lewy spust co krzyk, bo na
	# strzelnicy cios i krzyk są wyłączone, a poza nią przyrządów nie ma (kontekst „range”: RANGE_SHEET)
	"aim_sights": {"mouse": [MOUSE_BUTTON_RIGHT], "axis": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	# strzelnica: zmiana ćwiczenia (5 blach / przeładowanie) — ten sam klawisz co wybór rzucanego (throw_next), który na strzelnicy nic nie robi
	"range_exercise": {"keys": [KEY_X], "pad": [JOY_BUTTON_DPAD_UP]},
	# strzelnica: szafa z bronią — ten sam klawisz co flara, która na strzelnicy nic nie robi
	"range_locker": {"keys": [KEY_F], "pad": [JOY_BUTTON_DPAD_RIGHT]},
	"help": {"keys": [KEY_F1]},
	"chat": {"keys": [KEY_T]},
	"journal": {"keys": [KEY_N]},                       # dziennik komunikatów i porad (MESSAGES_PLAN.md); pad: bez domyślnego przycisku, można przypisać
	"pause": {"keys": [KEY_ESCAPE, KEY_P], "pad": [JOY_BUTTON_START], "menu": true},
	"weapon_next": {"mouse": [MOUSE_BUTTON_WHEEL_DOWN], "pad": [JOY_BUTTON_Y]},
	"weapon_prev": {"mouse": [MOUSE_BUTTON_WHEEL_UP]},
	# poniżej: dawniej surowe klawisze sprawdzane w skryptach (F2 w main.gd, F11 w settings.gd, O w hud.gd)
	"steam_invite": {"keys": [KEY_F2], "menu": true},
	"fullscreen": {"keys": [KEY_F11], "menu": true},
	"open_store": {"keys": [KEY_O]},
	# nawigacja po panelach z własnym zaznaczeniem (warsztat): strzałki / WASD / D-pad, zatwierdź, wróć, następna zakładka, sloty.
	# Osobne od wbudowanych ui_* Godota: te sterują fokusem kontrolek, a tu panel sam trzyma zaznaczenie.
	"menu_left": {"keys": [KEY_A, KEY_LEFT], "pad": [JOY_BUTTON_DPAD_LEFT], "menu": true},
	"menu_right": {"keys": [KEY_D, KEY_RIGHT], "pad": [JOY_BUTTON_DPAD_RIGHT], "menu": true},
	"menu_up": {"keys": [KEY_W, KEY_UP], "pad": [JOY_BUTTON_DPAD_UP], "menu": true},
	"menu_down": {"keys": [KEY_S, KEY_DOWN], "pad": [JOY_BUTTON_DPAD_DOWN], "menu": true},
	"menu_accept": {"keys": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], "pad": [JOY_BUTTON_A], "menu": true},
	"menu_back": {"keys": [KEY_ESCAPE, KEY_E, KEY_BACKSPACE], "pad": [JOY_BUTTON_B], "menu": true},
	"menu_tab": {"keys": [KEY_TAB], "pad": [JOY_BUTTON_RIGHT_SHOULDER], "menu": true},
	"menu_tab_prev": {"pad": [JOY_BUTTON_LEFT_SHOULDER], "menu": true},
	"menu_slot_1": {"keys": [KEY_1], "pad": [JOY_BUTTON_X], "menu": true},
	"menu_slot_2": {"keys": [KEY_2], "pad": [JOY_BUTTON_Y], "menu": true},
	"menu_alt": {"keys": [KEY_R], "pad": [JOY_BUTTON_LEFT_STICK], "menu": true},          # warsztat: zapisz bieżący montaż do zestawu (nadpisz)
}

## Akcje, które gracz może przypisywać, w kolejności ekranu CONTROLS: id → etykieta. (Celowanie prawym drążkiem i akcje
## `menu_*` mają stałe wiązania.)
const LABELS := {
	"move_left": "Move left", "move_right": "Move right", "move_up": "Aim / move up", "move_down": "Aim down / drop",
	"jump": "Jump", "fire": "Fire", "reload": "Reload", "firemode": "Fire mode", "ammo_type": "Ammo type", "melee": "Melee",
	"weapon_1": "Weapon 1", "weapon_2": "Weapon 2", "weapon_3": "Weapon 3", "weapon_next": "Next weapon", "weapon_prev": "Previous weapon",
	"crouch": "Sneak", "overcharge": "Overcharge (lure)", "scream": "Scream", "flare": "Flare", "flashlight": "Flashlight", "inspect_weapon": "Inspect weapon",
	"aim_sights": "Aim down sights (range)", "range_exercise": "Change exercise (range)", "range_locker": "Weapon locker (range)",
	"interact": "Interact / revive", "throw": "Use item", "throw_next": "Switch item", "restart": "Confirm / ready up",
	"help": "Controls overlay", "chat": "Team chat", "journal": "Journal", "pause": "Pause menu", "steam_invite": "Steam invite", "fullscreen": "Fullscreen",
}

## Nazwy klawiszy tam, gdzie `OS.get_keycode_string` daje inną niż ta, którą widzi gracz.
const KEY_NAMES := {KEY_ESCAPE: "Esc", KEY_KP_ENTER: "Enter", KEY_META: "Cmd"}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel ↑", MOUSE_BUTTON_WHEEL_DOWN: "Wheel ↓",
	MOUSE_BUTTON_XBUTTON1: "M4", MOUSE_BUTTON_XBUTTON2: "M5",
}
const JOY_NAMES := {
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "D-Pad ↑", JOY_BUTTON_DPAD_DOWN: "D-Pad ↓", JOY_BUTTON_DPAD_LEFT: "D-Pad ←", JOY_BUTTON_DPAD_RIGHT: "D-Pad →",
}
const ARROWS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

const DEV_AUTO := -1                 ## urządzenie wg ostatniego użycia (`pad_mode`)
const DEV_KEY := 0                   ## klawiatura i mysz
const DEV_PAD := 1                   ## pad

const MOVE_IDS := ["move_up", "move_left", "move_down", "move_right"]
const AIM_IDS := ["aim_up", "aim_left", "aim_down", "aim_right"]
const WEAPON_IDS := ["weapon_1", "weapon_2", "weapon_3"]

## id → Array[Dictionary]: aktualne wiązania (po `register()` domyślne).
static var _binds := {}
static var _revision := 0
static var load_repairs: Array = []
static var pad_device := -1
static var pad_family := "xbox"
## Ostatnio użyte urządzenie wejścia (ustawia `input_setup.gd`): teksty podpowiedzi pokazują wtedy przyciski pada.
static var pad_mode := false

## Rejestruje wszystkie akcje w InputMap (woła `input_setup.gd`). Powtórne wywołanie niczego nie dubluje.
static func register() -> void:
	_binds.clear()
	_revision += 1
	for id in DEFS:
		_binds[id] = _default_list(id)
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		_write_input_map(id)
		InputMap.action_set_deadzone(id, float(DEFS[id].get("deadzone", 0.5)))

## Autoload Settings (null, zanim powstanie: `register()` woła InputSetup przed nim).
static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Settings") if tree != null else null

static func _save_settings() -> void:
	var st := _settings()
	if st != null:
		st.save_bindings()

## Domyślne wiązania akcji z `DEFS` (na macOS `keys_macos` zamiast `keys`).
static func _default_list(id: String) -> Array:
	var d: Dictionary = DEFS[id]
	var list: Array = []
	var mac := OS.get_name() == "macOS"
	var keys: Array = d["keys_macos"] if (mac and d.has("keys_macos")) else d.get("keys", [])
	for k in keys:
		if k is Dictionary:
			list.append({"type": "key", "code": int(k["key"]), "left": bool(k.get("left", false))})
		else:
			list.append({"type": "key", "code": int(k), "left": false})
	for b in d.get("mouse", []):
		list.append({"type": "mouse", "button": int(b)})
	for b in d.get("pad", []):
		list.append({"type": "joy", "button": int(b)})
	for a in d.get("axis", []):
		list.append({"type": "axis", "axis": int(a[0]), "value": float(a[1])})
	return list.map(func(b: Dictionary) -> Dictionary: return Policy.normalize(b))

## Wpisuje wiązania akcji do InputMap. Gdy menu pauzy trzyma zdarzenia akcji gry w schowku (Settings.block_game_input),
## zmiana trafia do schowka — wróci do InputMap razem z resztą po zamknięciu menu.
static func _write_input_map(id: String) -> void:
	var evs: Array = []
	for b in _binds.get(id, []):
		evs.append(_event_of(b))
	var st := _settings()
	if st != null and st.blocked and blockable().has(id):
		st._stash[id] = evs
		return
	InputMap.action_erase_events(id)
	for e in evs:
		InputMap.action_add_event(id, e)

static func _event_of(b: Dictionary) -> InputEvent:
	match String(b["type"]):
		"joy":
			var j := InputEventJoypadButton.new()
			j.device = -1
			j.button_index = int(b["button"])
			return j
		"axis":
			var m := InputEventJoypadMotion.new()
			m.device = -1
			m.axis = int(b["axis"])
			m.axis_value = float(b["value"])
			return m
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(b["button"])
			return mb
	var ev := InputEventKey.new()
	ev.physical_keycode = int(b["code"])
	ev.location = int(b.get("location", KEY_LOCATION_UNSPECIFIED))
	return ev

# ---------------------------------------------------------------- zapytania

## Wszystkie zarejestrowane id akcji.
static func ids() -> Array:
	return DEFS.keys()

## Akcje wycinane z InputMap na czas menu pauzy (wszystkie poza oznaczonymi `menu`).
static func blockable() -> Array:
	var out: Array = []
	for id in DEFS:
		if not bool(DEFS[id].get("menu", false)):
			out.append(id)
	return out

## Aktualne wiązania akcji (kopia).
static func bindings(id: String) -> Array:
	return (_binds.get(id, []) as Array).duplicate(true)

static func _is_pad(b: Dictionary) -> bool:
	var t := String(b["type"])
	return t == "joy" or t == "axis"

static func _name_of(b: Dictionary) -> String:
	match String(b["type"]):
		"joy":
			return _joy_name(int(b["button"]))
		"axis":
			var v := float(b["value"])
			match int(b["axis"]):
				JOY_AXIS_LEFT_X:
					return "L-Stick " + ("→" if v > 0.0 else "←")
				JOY_AXIS_LEFT_Y:
					return "L-Stick " + ("↓" if v > 0.0 else "↑")
				JOY_AXIS_RIGHT_X:
					return "R-Stick " + ("→" if v > 0.0 else "←")
				JOY_AXIS_RIGHT_Y:
					return "R-Stick " + ("↓" if v > 0.0 else "↑")
				JOY_AXIS_TRIGGER_LEFT:
					return "L2" if pad_family == "playstation" else ("ZL" if pad_family == "nintendo" else "LT")
				JOY_AXIS_TRIGGER_RIGHT:
					return "R2" if pad_family == "playstation" else ("ZR" if pad_family == "nintendo" else "RT")
			return "Axis %d" % int(b["axis"])
		"mouse":
			return String(MOUSE_NAMES.get(int(b["button"]), "Mouse %d" % int(b["button"])))
	var code := int(b["code"])
	var n: String = String(KEY_NAMES.get(code, OS.get_keycode_string(code)))
	return ("L-" + n) if int(b.get("location", 0)) == KEY_LOCATION_LEFT else (("R-" + n) if int(b.get("location", 0)) == KEY_LOCATION_RIGHT else n)

## Rodzina oznaczeń z nazwy zgłaszanej przez sterownik; Steam Input może zgłaszać wirtualny Xbox.
static func family_of(name: String) -> String:
	var n := name.to_lower()
	if n.contains("playstation") or n.contains("dualshock") or n.contains("dualsense") or n.contains("ps4") or n.contains("ps5"):
		return "playstation"
	if n.contains("nintendo") or n.contains("switch") or n.contains("joy-con"):
		return "nintendo"
	return "xbox"

static func _joy_name(button: int) -> String:
	var names := {}
	if pad_family == "playstation":
		names = {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_BACK: "Share", JOY_BUTTON_MISC1: "Create", JOY_BUTTON_START: "Options"}
	elif pad_family == "nintendo":
		names = {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X", JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_BACK: "−", JOY_BUTTON_START: "+", JOY_BUTTON_MISC1: "Capture"}
	return String(names.get(button, JOY_NAMES.get(button, "Pad %d" % button)))

## Wiązania akcji z klawiatury i myszy (domyślnie) albo tylko z pada (`pad_only`).
static func _list(id: String, pad_only := false) -> Array:
	var out: Array = []
	for b in _binds.get(id, []):
		if _is_pad(b) == pad_only:
			out.append(b)
	return out

## Urządzenie ostatnio używane; brak przypisania na padzie jest jawnie oznaczony przez —.
static func _device_for(_action_ids: Array, device: int) -> int:
	if device != DEV_AUTO:
		return device
	if pad_mode:
		return DEV_PAD
	return DEV_KEY

## Nazwa(y) klawiszy akcji: "J / LMB". `first_only` — tylko pierwsze wiązanie (do podpowiedzi w nawiasach);
## `device` — DEV_KEY / DEV_PAD albo DEV_AUTO (wg ostatnio użytego urządzenia; akcja bez przycisku pada pokazuje —).
static func text(id: String, first_only := false, device := DEV_AUTO) -> String:
	var names: Array = []
	for b in _list(id, _device_for([id], device) == DEV_PAD):
		var n := _name_of(b)
		if not names.has(n):
			names.append(n)
		if first_only:
			break
	return " / ".join(names) if not names.is_empty() else "—"

## Krótka nazwa pierwszego klawisza wersalikami do nawiasów w podpowiedziach: `[E]`, `[ENTER]`, `[L-ALT]`, `[RT]`.
static func key(id: String) -> String:
	return text(id, true).to_upper()

## Grupa akcji jako jedna nazwa: ruch → "WASD / Arrows" (pad: "L-Stick"). Każde wiązanie (slot) to osobna część, połączone
## `sep`; same strzałki skracają się do „Arrows”, osie jednego drążka do jego nazwy. `first_slot_only` — tylko pierwszy slot.
static func cluster(action_ids: Array, sep := "", first_slot_only := false, device := DEV_AUTO) -> String:
	var pad := _device_for(action_ids, device) == DEV_PAD
	var slots := 0
	for id in action_ids:
		slots = maxi(slots, _list(id, pad).size())
	if first_slot_only:
		slots = mini(slots, 1)
	var parts: Array = []
	for s in slots:
		var names: Array = []
		var all_arrows := true
		var sticks := {}
		for id in action_ids:
			var arr: Array = _list(id, pad)
			if s >= arr.size():
				continue
			var b: Dictionary = arr[s]
			names.append(_name_of(b))
			all_arrows = all_arrows and String(b["type"]) == "key" and ARROWS.has(int(b["code"]))
			if String(b["type"]) == "axis":
				sticks[String(_name_of(b)).split(" ")[0]] = true
			else:
				sticks[""] = true
		if names.is_empty():
			continue
		if sticks.size() == 1 and not sticks.has(""):
			parts.append(String(sticks.keys()[0]))
		else:
			parts.append("Arrows" if all_arrows else sep.join(names))
	return " / ".join(parts)

static func _join(parts: Array, sep := " / ") -> String:
	var out: Array = []
	for p in parts:
		if String(p) != "" and String(p) != "—":
			out.append(String(p))
	return sep.join(out)

## Podstawia `{id}` nazwą klawisza akcji (wersaliki, pierwsze wiązanie): "Press {overcharge}" → "Press Q".
## Dodatkowy znacznik `{move}` = ruch („WASD”, pad: „L-STICK”).
static func fmt(template: String) -> String:
	var out := template.replace("{move}", cluster(MOVE_IDS, "", true).to_upper())
	for id in DEFS:
		var token := "{%s}" % id
		if out.contains(token):
			out = out.replace(token, key(id))
	return out

## Czy podłączony jest pad.
static func pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()

# ---------------------------------------------------------------- ściągi

## Wiersze ściągi sterowania [klawisze, opis] (lobby, menu pauzy) — z aktualnych wiązań i urządzenia (`pad_mode`).
static func sheet() -> Array:
	var pad := _device_for(MOVE_IDS, DEV_AUTO) == DEV_PAD
	var aim := cluster(AIM_IDS, "", true) if pad else ""
	return [
		[_join([cluster(MOVE_IDS), aim]), "Move & aim"],
		[text("jump"), "Jump (hold = higher)"],
		["%s + %s" % [text("move_down", true), text("jump", true)], "Drop through a catwalk"],
		[text("crouch"), "Sneak — silent"],
		[text("fire"), "Fire — makes NOISE"],
		[text("reload"), "Reload (hold: tactical)"],
		[text("ammo_type"), "Ammo type"],
		[text("inspect_weapon"), "Inspect weapon"],
		[text("firemode"), "Fire mode (auto / burst)"],
		[text("melee"), "Melee"],
		[text("weapon_next") if _device_for(["weapon_next"], DEV_AUTO) == DEV_PAD else _join([cluster(WEAPON_IDS, " "), text("weapon_next")]), "Switch weapon"],
		[text("overcharge"), "Overcharge — lure HIM away"],
		[text("scream"), "Scream — lures enemies"],
		[text("flare"), "Flare — light bait, no noise"],
		["%s / %s" % [text("throw", true), text("throw_next", true)], "Use item / switch item"],
		[text("flashlight"), "Flashlight — light is noise"],
		["Hold %s" % text("interact"), "Take weapon / revive"],
		[text("help"), "Controls on / off"],
		[text("chat"), "Team chat"],
		[text("journal"), "Journal (messages and tips)"],
		[text("steam_invite"), "Steam invite (host)"],
	]

## Kontekst „range” (strzelnica FPP, scripts/range3d/fp_mode.gd): te same akcje co w grze, inne znaczenie — A/D stanowisko, skradanie
## to przyklęk z oparciem na ławie, PPM przyrządy (zamiast ciosu), interakcja wychodzi. Ruch, skok, krzyk, przynęta, raca, latarka
## i przedmioty na strzelnicy nic nie robią (player._range_brain ich nie czyta). [akcje, opis] w kolejności ściągi.
const RANGE_SHEET := [
	[["move_left", "move_right"], "Change station"],
	[["crouch"], "Hold: brace on the bench"],
	[["aim_sights"], "Aim down sights"],
	[["fire"], "Fire"],
	[["reload"], "Reload (hold: tactical)"],
	[["firemode"], "Fire mode"],
	[["ammo_type"], "Ammo type (free here)"],
	[["weapon_1", "weapon_2", "weapon_3"], "Switch weapon"],
	[["range_exercise"], "Change exercise"],
	[["range_locker"], "Weapon locker"],
	[["interact"], "Leave the range"],
]

## Ściąga strzelnicy [klawisze, opis] — wiersze jak `sheet()`.
static func range_sheet() -> Array:
	var out: Array = []
	for r in RANGE_SHEET:
		var ids: Array = r[0]
		var keys := text("weapon_next", true) if ids == WEAPON_IDS and pad_mode else (cluster(ids, "/", true) if ids.size() > 1 else text(String(ids[0]), true))
		var desc := "Toggle: brace on the bench" if ids == ["crouch"] and _settings() != null and _settings().fp_brace_toggle else String(r[1])
		out.append([keys, desc])
	return out

## Pasek sterowania w dole HUD na strzelnicy (F1 przełącza; zamiast `hud_line()`).
static func range_hud_line() -> String:
	var items: Array = []
	for r in range_sheet():
		items.append("%s %s" % [String(r[0]).to_upper(), TranslationServer.translate(String(r[1])).to_lower()])
	return " · ".join(items)

## Jednowierszowa podpowiedź u góry obrazu strzelnicy (range_view.gd) — tylko to, czego nie ma w zwykłej grze.
static func range_line() -> String:
	var line := "RANGE  ·  %s/%s station  ·  toggle %s brace on the bench  ·  %s sights  ·  %s exercise  ·  %s locker  ·  %s leave" if _settings() != null and _settings().fp_brace_toggle else "RANGE  ·  %s/%s station  ·  hold %s brace on the bench  ·  %s sights  ·  %s exercise  ·  %s locker  ·  %s leave"
	return TranslationServer.translate(line) % [
		key("move_left"), key("move_right"), key("crouch"), key("aim_sights"), key("range_exercise"), key("range_locker"), key("interact")]

## Jednowierszowy pasek sterowania w dole HUD (F1 przełącza).
static func hud_line() -> String:
	var items := [
		TranslationServer.translate("%s move") % cluster(MOVE_IDS, "", true).to_upper(),
		TranslationServer.translate("%s jump") % key("jump"),
		TranslationServer.translate("%s+%s drop") % [key("move_down"), key("jump")],
		TranslationServer.translate("%s sneak") % key("crouch"),
		TranslationServer.translate("%s fire") % text("fire").replace(" / ", "/").to_upper(),
		TranslationServer.translate("%s reload") % key("reload"),
		TranslationServer.translate("%s ammo") % key("ammo_type"),
		TranslationServer.translate("%s inspect") % key("inspect_weapon"),
		TranslationServer.translate("%s fire mode") % key("firemode"),
		TranslationServer.translate("%s item (%s switch)") % [key("throw"), key("throw_next")],
		TranslationServer.translate("%s melee") % text("melee").replace(" / ", "/").to_upper(),
		TranslationServer.translate("%s gun") % (key("weapon_next") if _device_for(WEAPON_IDS + ["weapon_next"], DEV_AUTO) == DEV_PAD else cluster(WEAPON_IDS, "/", true).to_upper()),
		TranslationServer.translate("%s take/revive") % key("interact"),
		TranslationServer.translate("%s lure") % key("overcharge"),
		TranslationServer.translate("%s flare") % key("flare"),
		TranslationServer.translate("%s scream") % key("scream"),
		TranslationServer.translate("%s light") % key("flashlight"),
		TranslationServer.translate("%s chat") % key("chat"),
		TranslationServer.translate("%s journal") % key("journal"),
	]
	return " · ".join(items)

# ---------------------------------------------------------------- przypisywanie klawiszy

static func rebindable() -> Array:
	return LABELS.keys()

static func label_of(id: String) -> String:
	return String(LABELS.get(id, id.replace("_", " ").capitalize()))

static func _is_trigger(b: Dictionary) -> bool:
	return b.type == "axis" and int(b.axis) in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

static func _fixed(id: String, b: Dictionary) -> bool:
	return (id == "pause" and b.type == "key" and b.code == KEY_ESCAPE) or (b.type == "axis" and not _is_trigger(b))

## Brak przycisku jest edytowalny; tylko drążki ruchu/celowania mają stałe osie.
static func pad_rebindable(id: String) -> bool:
	return LABELS.has(id) and not id in MOVE_IDS

static func editable_slots(id: String, device: int) -> Array:
	var out := []
	var list: Array = _binds.get(id, [])
	for i in list.size():
		if _is_pad(list[i]) == (device == DEV_PAD) and not _fixed(id, list[i]):
			out.append(i)
	return out

static func binding_name(id: String, slot: int) -> String:
	return _name_of(_binds[id][slot])

static func binding_from_event(event: InputEvent, device: int) -> Dictionary:
	if device == DEV_KEY and event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
		var loc := int(k.location) if code in [KEY_ALT, KEY_META, KEY_SHIFT, KEY_CTRL] else KEY_LOCATION_UNSPECIFIED
		return Policy.normalize({"type": "key", "code": code, "location": loc})
	if device == DEV_KEY and event is InputEventMouseButton:
		return Policy.normalize({"type": "mouse", "button": event.button_index})
	if device == DEV_PAD and event is InputEventJoypadButton:
		return Policy.normalize({"type": "joy", "button": event.button_index})
	if device == DEV_PAD and event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and event.axis_value >= 0.7:
			return Policy.normalize({"type": "axis", "axis": event.axis, "value": 1.0})
	return {}

static func _same(a: Dictionary, b: Dictionary) -> bool:
	var x := Policy.normalize(a)
	var y := Policy.normalize(b)
	return not x.is_empty() and not y.is_empty() and Policy.overlaps(x, y)

static func _unique(list: Array) -> Array:
	var out := []
	for binding in list:
		if not binding in out:
			out.append(binding)
	return out

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "swapped": "", "changed": []}

static func _plan(candidate: Dictionary) -> Dictionary:
	var issues := Policy.conflicts(candidate)
	if not issues.is_empty():
		return _failure(TranslationServer.translate("Conflicting controls: %s / %s") % [TranslationServer.translate(label_of(issues[0].a)), TranslationServer.translate(label_of(issues[0].b))])
	var changed := []
	for id in candidate:
		if candidate[id] != _binds[id]:
			changed.append(id)
	return {"ok": true, "reason": "", "changed": changed, "bindings": candidate, "revision": _revision, "swapped": ""}

## Plan bez skutków ubocznych. slot=-2: pierwsze edytowalne, -1: dodaj; pozostałe: indeks wiązania.
static func plan_binding(id: String, device: int, event: InputEvent, slot := -2) -> Dictionary:
	if slot < -2 or not device in [DEV_KEY, DEV_PAD] or not LABELS.has(id) or (device == DEV_PAD and not pad_rebindable(id)):
		return _failure(TranslationServer.translate("Fixed axes"))
	var nb := binding_from_event(event, device)
	if nb.is_empty():
		return _failure(TranslationServer.translate("That key cannot be used here."))
	if nb.type == "key" and nb.code == KEY_ESCAPE:
		return _failure(TranslationServer.translate("Esc is reserved for cancel and pause."))
	var candidate: Dictionary = _binds.duplicate(true)
	var list: Array = candidate[id]
	var slots := editable_slots(id, device)
	var idx: int = int(slots[0]) if slot == -2 and not slots.is_empty() else (-1 if slot == -2 else slot)
	if idx >= 0 and not idx in slots:
		return _failure(TranslationServer.translate("That key cannot be used here."))
	var old: Dictionary = list[idx] if idx >= 0 else {}
	for other in DEFS:
		if other == id or not Policy.simultaneous(id, other):
			continue
		var ol: Array = candidate[other]
		for i in ol.size():
			if not Policy.overlaps(ol[i], nb) or Policy.allowed_alias(id, other, nb):
				continue
			if not LABELS.has(other) or _fixed(other, ol[i]) or old.is_empty():
				return _failure(TranslationServer.translate("Already used by %s. Choose another binding.") % TranslationServer.translate(label_of(other)))
			ol[i] = old
		candidate[other] = _unique(ol)
	if idx >= 0:
		list[idx] = nb
	else:
		list.append(nb)
	candidate[id] = _unique(list)
	var plan := _plan(candidate)
	if plan.ok:
		for changed_id in plan.changed:
			if changed_id != id:
				plan.swapped = changed_id
				break
	return plan

static func plan_remove(id: String, slot: int) -> Dictionary:
	if not LABELS.has(id) or slot < 0 or slot >= _binds[id].size() or _fixed(id, _binds[id][slot]):
		return _failure(TranslationServer.translate("That key cannot be used here."))
	var candidate: Dictionary = _binds.duplicate(true)
	candidate[id].remove_at(slot)
	return _plan(candidate)

## Atomowe zastosowanie zatwierdzonego planu; odrzuca plan sprzed innej zmiany.
static func apply_plan(plan: Dictionary, persist := true) -> Dictionary:
	if not plan.get("ok", false):
		return plan
	if int(plan.get("revision", -1)) != _revision:
		return _failure(TranslationServer.translate("Controls changed. Please try again."))
	var checked := _plan(plan.bindings)
	if not checked.ok:
		return checked
	_binds = plan.bindings.duplicate(true)
	_revision += 1
	for id in checked.changed:
		Input.action_release(id)
		_write_input_map(id)
	_notify(persist)
	return plan

static func _notify(persist: bool) -> void:
	var st := _settings()
	if st != null:
		if persist:
			st.save_bindings()
		else:
			st.bindings_changed.emit()

static func set_binding(id: String, device: int, event: InputEvent, persist := true, slot := -2) -> Dictionary:
	return apply_plan(plan_binding(id, device, event, slot), persist)

static func _preset(name: String) -> Dictionary:
	var out := {}
	for id in DEFS:
		out[id] = _default_list(id)
	if name == "modern":
		out.flashlight.insert(0, Policy.normalize({"type": "key", "code": KEY_C}))
		out.throw.push_front(Policy.normalize({"type": "mouse", "button": MOUSE_BUTTON_XBUTTON1}))
		out.inspect_weapon.append(Policy.normalize({"type": "mouse", "button": MOUSE_BUTTON_XBUTTON2}))
		out.inspect_weapon.append(Policy.normalize({"type": "joy", "button": JOY_BUTTON_MISC1}))
		for id in ["reload", "melee"]:
			for b in out[id]:
				if b.type == "joy":
					b.button = JOY_BUTTON_X if id == "reload" else JOY_BUTTON_RIGHT_STICK
	return out

static func plan_preset(name: String) -> Dictionary:
	if not name in ["classic", "modern"]:
		return _failure(TranslationServer.translate("That key cannot be used here."))
	return _plan(_preset(name))

static func preset_name() -> String:
	for name in ["classic", "modern"]:
		if _binds == _preset(name):
			return name.capitalize()
	return "Custom"

static func reset_defaults(persist := true) -> void:
	apply_plan(plan_preset("classic"), persist)

static func is_default(id: String) -> bool:
	return _binds.get(id, []) == _default_list(id)

static func save_to(cf: ConfigFile) -> void:
	if cf.has_section("keys"):
		cf.erase_section("keys")
	for id in LABELS:
		if not is_default(id):
			cf.set_value("keys", id, _binds[id])

## Migracja boola left, walidacja danych i przywrócenie tylko niebezpiecznych nadpisań.
static func load_from(cf: ConfigFile) -> void:
	load_repairs.clear()
	if not cf.has_section("keys"):
		return
	var candidate: Dictionary = _binds.duplicate(true)
	var custom := []
	for id in cf.get_section_keys("keys"):
		if not LABELS.has(id):
			continue
		var arr: Variant = cf.get_value("keys", id)
		if not arr is Array:
			load_repairs.append(id)
			continue
		var clean := []
		for b in arr:
			if b is Dictionary:
				var normalized := Policy.normalize(b)
				if normalized.is_empty() or (normalized.type == "key" and normalized.code == KEY_ESCAPE and id != "pause"):
					continue
				if _fixed(id, normalized) and not normalized in _default_list(id):
					continue
				clean.append(normalized)
		if not arr.is_empty() and clean.is_empty():
			load_repairs.append(id)
			continue
		for factory in _default_list(id):
			if _fixed(id, factory) and not factory in clean:
				clean.append(factory)
		if id == "pause" and not Policy.normalize({"type": "key", "code": KEY_ESCAPE}) in clean:
			clean.push_front(Policy.normalize({"type": "key", "code": KEY_ESCAPE}))
		candidate[id] = _unique(clean)
		custom.append(id)
	# Nowe H nie może odebrać wcześniejszego, poprawnego przypisania gracza.
	# Brak sekcji tej nowej akcji oznacza starszy zapis: kolidujące domyślne H pozostaje nieprzypisane.
	if not cf.has_section_key("keys", "inspect_weapon"):
		var inspect: Array = candidate.inspect_weapon.duplicate(true)
		for id in custom:
			if not Policy.simultaneous("inspect_weapon", id):
				continue
			for existing in candidate[id]:
				for binding in inspect:
					if Policy.overlaps(binding, existing) and binding in candidate.inspect_weapon:
						candidate.inspect_weapon.erase(binding)
		if candidate.inspect_weapon != inspect:
			load_repairs.append("inspect_weapon")
	for attempt in LABELS.size():
		var conflicts := Policy.conflicts(candidate)
		if conflicts.is_empty():
			break
		var restored := false
		for issue in conflicts:
			for id in [issue.a, issue.b]:
				if id in custom:
					candidate[id] = _default_list(id)
					custom.erase(id)
					load_repairs.append(id)
					restored = true
		if not restored:
			break
	_binds = candidate
	_revision += 1
	for id in _binds:
		_write_input_map(id)
