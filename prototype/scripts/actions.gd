extends RefCounted
## Rejestr akcji wejściowych — jedno źródło prawdy o tym, jakie akcje ma gra i jakimi klawiszami / przyciskami się je wywołuje.
##
## Z niego korzystają: `input_setup.gd` (rejestracja w InputMap i wykrywanie urządzenia), `settings.gd` (które akcje wyciąć
## na czas menu), ściąga sterowania w lobby i menu pauzy (`sheet()`), pasek sterowania w HUD (`hud_line()`) oraz teksty
## podpowiedzi (`fmt()`, `key()`), więc nazwa klawisza nie jest wpisana ręcznie w kilkunastu miejscach. Teksty pokazują
## klawisze klawiatury albo pada — zależnie od tego, czego gracz użył ostatnio (`pad_mode`).
##
## Wiązanie to słownik: {"type": "key", "code": Key, "left": bool} (left = tylko lewa strona klawiatury, np. lewy Alt),
## {"type": "mouse", "button": MouseButton}, {"type": "joy", "button": JoyButton} albo
## {"type": "axis", "axis": JoyAxis, "value": ±1.0} (drążek lub spust). Klawisze to `physical_keycode` (układ-niezależne).
##
## Gracz może przypisać klawisz / przycisk pada do każdej akcji z `LABELS` (menu pauzy → CONTROLS): `set_binding()` podmienia
## pierwsze wiązanie danego urządzenia, a gdy ten klawisz miała inna akcja — zamienia je miejscami. Zmiany idą do
## `user://settings.cfg` (sekcja „keys”, tylko akcje różne od domyślnych), `reset_defaults()` przywraca wszystko.

## id → ["keys": [Key | {"key": Key, "left": true}], "keys_macos": (zamiast keys na macOS), "mouse": [MouseButton],
##        "pad": [JoyButton], "axis": [[JoyAxis, ±1.0]], "deadzone": float (domyślnie 0.5),
##        "menu": true = akcja zostaje aktywna przy otwartym menu pauzy (reszta jest wycinana, żeby klik w menu nie strzelał)]
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
	"flare": {"keys": [KEY_F], "pad": [JOY_BUTTON_DPAD_RIGHT]},
	"interact": {"keys": [KEY_E], "pad": [JOY_BUTTON_B]},
	"weapon_1": {"keys": [KEY_1]},
	"weapon_2": {"keys": [KEY_2]},
	"weapon_3": {"keys": [KEY_3]},
	"restart": {"keys": [KEY_ENTER, KEY_KP_ENTER], "pad": [JOY_BUTTON_BACK]},
	"flashlight": {"keys": [KEY_L], "pad": [JOY_BUTTON_DPAD_LEFT]},
	"reload": {"keys": [KEY_R], "pad": [JOY_BUTTON_RIGHT_STICK]},
	"firemode": {"keys": [KEY_B], "pad": [JOY_BUTTON_DPAD_DOWN]},
	# użycie przedmiotu: lewy Alt (na macOS lewy Cmd pierwszy, lewy Alt też działa); prawy Alt / Cmd zostaje wolny
	"throw": {"keys": [{"key": KEY_ALT, "left": true}], "keys_macos": [{"key": KEY_META, "left": true}, {"key": KEY_ALT, "left": true}], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	"throw_next": {"keys": [KEY_X], "pad": [JOY_BUTTON_DPAD_UP]},
	"melee": {"keys": [KEY_V], "mouse": [MOUSE_BUTTON_RIGHT], "pad": [JOY_BUTTON_X]},
	"help": {"keys": [KEY_F1]},
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
}

## Akcje, które gracz może przypisywać, w kolejności ekranu CONTROLS: id → etykieta. (Celowanie prawym drążkiem i akcje
## `menu_*` mają stałe wiązania.)
const LABELS := {
	"move_left": "Move left", "move_right": "Move right", "move_up": "Aim / move up", "move_down": "Aim down / drop",
	"jump": "Jump", "fire": "Fire", "reload": "Reload", "firemode": "Fire mode", "melee": "Melee",
	"weapon_1": "Weapon 1", "weapon_2": "Weapon 2", "weapon_3": "Weapon 3", "weapon_next": "Next weapon", "weapon_prev": "Previous weapon",
	"crouch": "Sneak", "overcharge": "Overcharge (lure)", "scream": "Scream", "flare": "Flare", "flashlight": "Flashlight",
	"interact": "Interact / revive", "throw": "Use item", "throw_next": "Switch item", "restart": "Confirm / ready up",
	"help": "Controls overlay", "pause": "Pause menu", "steam_invite": "Steam invite", "fullscreen": "Fullscreen",
}

## Nazwy klawiszy tam, gdzie `OS.get_keycode_string` daje inną niż ta, którą widzi gracz.
const KEY_NAMES := {KEY_ESCAPE: "Esc", KEY_KP_ENTER: "Enter", KEY_META: "Cmd"}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel", MOUSE_BUTTON_WHEEL_DOWN: "Wheel",
}
const JOY_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
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
## Ostatnio użyte urządzenie wejścia (ustawia `input_setup.gd`): teksty podpowiedzi pokazują wtedy przyciski pada.
static var pad_mode := false

## Rejestruje wszystkie akcje w InputMap (woła `input_setup.gd`). Powtórne wywołanie niczego nie dubluje.
static func register() -> void:
	_binds.clear()
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
	return list

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
			j.button_index = int(b["button"])
			return j
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(b["axis"])
			m.axis_value = float(b["value"])
			return m
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(b["button"])
			return mb
	var ev := InputEventKey.new()
	ev.physical_keycode = int(b["code"])
	if bool(b.get("left", false)):
		ev.location = KEY_LOCATION_LEFT
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
			return String(JOY_NAMES.get(int(b["button"]), "Pad %d" % int(b["button"])))
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
					return "LT"
				JOY_AXIS_TRIGGER_RIGHT:
					return "RT"
			return "Axis %d" % int(b["axis"])
		"mouse":
			return String(MOUSE_NAMES.get(int(b["button"]), "Mouse %d" % int(b["button"])))
	var code := int(b["code"])
	var n: String = String(KEY_NAMES.get(code, OS.get_keycode_string(code)))
	return ("L-" + n) if bool(b.get("left", false)) else n

## Wiązania akcji z klawiatury i myszy (domyślnie) albo tylko z pada (`pad_only`).
static func _list(id: String, pad_only := false) -> Array:
	var out: Array = []
	for b in _binds.get(id, []):
		if _is_pad(b) == pad_only:
			out.append(b)
	return out

## Urządzenie do wyświetlenia dla grupy akcji: pad, gdy ostatnio używany i choć jedna akcja ma przycisk pada.
static func _device_for(action_ids: Array, device: int) -> int:
	if device != DEV_AUTO:
		return device
	if pad_mode:
		for id in action_ids:
			if not _list(id, true).is_empty():
				return DEV_PAD
	return DEV_KEY

## Nazwa(y) klawiszy akcji: "J / LMB". `first_only` — tylko pierwsze wiązanie (do podpowiedzi w nawiasach);
## `device` — DEV_KEY / DEV_PAD albo DEV_AUTO (wg ostatnio użytego urządzenia; akcja bez przycisku pada pokazuje klawisz).
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
		[text("reload"), "Reload"],
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
		[text("steam_invite"), "Steam invite (host)"],
	]

## Jednowierszowy pasek sterowania w dole HUD (F1 przełącza).
static func hud_line() -> String:
	var items := [
		"%s move" % cluster(MOVE_IDS, "", true).to_upper(),
		"%s jump" % key("jump"),
		"%s+%s drop" % [key("move_down"), key("jump")],
		"%s sneak" % key("crouch"),
		"%s fire" % text("fire").replace(" / ", "/").to_upper(),
		"%s reload" % key("reload"),
		"%s fire mode" % key("firemode"),
		"%s item (%s switch)" % [key("throw"), key("throw_next")],
		"%s melee" % text("melee").replace(" / ", "/").to_upper(),
		"%s gun" % (key("weapon_next") if _device_for(WEAPON_IDS + ["weapon_next"], DEV_AUTO) == DEV_PAD else "%s-%s" % [key("weapon_1"), key("weapon_3")]),
		"%s take/revive" % key("interact"),
		"%s lure" % key("overcharge"),
		"%s flare" % key("flare"),
		"%s scream" % key("scream"),
		"%s light" % key("flashlight"),
	]
	return " · ".join(items)

# ---------------------------------------------------------------- przypisywanie klawiszy

## Akcje do przypisania w kolejności ekranu CONTROLS.
static func rebindable() -> Array:
	return LABELS.keys()

static func label_of(id: String) -> String:
	return String(LABELS.get(id, id))

## Czy akcja ma przycisk pada, który da się zmienić (drążki ruchu i celowania mają stałe osie).
static func pad_rebindable(id: String) -> bool:
	for b in _list(id, true):
		if String(b["type"]) == "joy" or _is_trigger(b):
			return true
	return false

static func _is_trigger(b: Dictionary) -> bool:
	return String(b["type"]) == "axis" and (int(b["axis"]) == JOY_AXIS_TRIGGER_LEFT or int(b["axis"]) == JOY_AXIS_TRIGGER_RIGHT)

## Wiązanie z jednego zdarzenia ({} gdy zdarzenie nie nadaje się dla urządzenia).
static func binding_from_event(event: InputEvent, device: int) -> Dictionary:
	if device == DEV_KEY and event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		if code == 0 or code == KEY_UNKNOWN:
			return {}
		var left := false
		if code == KEY_ALT or code == KEY_META or code == KEY_SHIFT or code == KEY_CTRL:
			left = k.location == KEY_LOCATION_LEFT
		return {"type": "key", "code": code, "left": left}
	if device == DEV_PAD and event is InputEventJoypadButton:
		return {"type": "joy", "button": int((event as InputEventJoypadButton).button_index)}
	if device == DEV_PAD and event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		if (m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT) and m.axis_value >= 0.7:
			return {"type": "axis", "axis": int(m.axis), "value": 1.0}
	return {}

static func _same(a: Dictionary, b: Dictionary) -> bool:
	if String(a["type"]) != String(b["type"]):
		return false
	match String(a["type"]):
		"key":
			return int(a["code"]) == int(b["code"]) and bool(a.get("left", false)) == bool(b.get("left", false))
		"axis":
			return int(a["axis"]) == int(b["axis"]) and float(a["value"]) == float(b["value"])
	return int(a["button"]) == int(b["button"])

## Przypisuje zdarzenie do akcji: podmienia pierwsze wiązanie tego urządzenia. Jeśli inna przypisywalna akcja miała to
## samo wiązanie, dostaje w zamian poprzednie wiązanie tej (zamiana miejscami). Zwraca {"ok": bool, "swapped": id | ""}.
static func set_binding(id: String, device: int, event: InputEvent, persist := true) -> Dictionary:
	var nb := binding_from_event(event, device)
	if nb.is_empty() or not LABELS.has(id):
		return {"ok": false, "swapped": ""}
	var list: Array = _binds[id]
	var idx := -1
	for i in list.size():
		var b: Dictionary = list[i]
		if device == DEV_KEY and String(b["type"]) == "key":
			idx = i
			break
		if device == DEV_PAD and (String(b["type"]) == "joy" or _is_trigger(b)):
			idx = i
			break
	var old: Dictionary = list[idx] if idx >= 0 else {}
	var swapped := ""
	for other in LABELS:
		if other == id:
			continue
		var ol: Array = _binds[other]
		for i in ol.size():
			if _same(ol[i], nb):
				swapped = String(other)
				if old.is_empty():
					ol.remove_at(i)
				else:
					ol[i] = old
				_write_input_map(String(other))
				break
	if idx >= 0:
		list[idx] = nb
	else:
		list.append(nb)
	_write_input_map(id)
	if persist:
		_save_settings()
	return {"ok": true, "swapped": swapped}

## Przywraca domyślne wiązania wszystkich akcji.
static func reset_defaults(persist := true) -> void:
	for id in DEFS:
		_binds[id] = _default_list(id)
		_write_input_map(id)
	if persist:
		_save_settings()

static func is_default(id: String) -> bool:
	return _binds.get(id, []) == _default_list(id)

## Zapis do pliku ustawień: tylko akcje różne od domyślnych (sekcja „keys”).
static func save_to(cf: ConfigFile) -> void:
	if cf.has_section("keys"):
		cf.erase_section("keys")
	for id in LABELS:
		if not is_default(id):
			cf.set_value("keys", id, _binds[id])

## Wczytanie z pliku ustawień; wpisy niepoprawne lub dla nieznanych akcji są pomijane.
static func load_from(cf: ConfigFile) -> void:
	if not cf.has_section("keys"):
		return
	for id in cf.get_section_keys("keys"):
		if not LABELS.has(id):
			continue
		var arr: Variant = cf.get_value("keys", id)
		if not (arr is Array) or (arr as Array).is_empty():
			continue
		var clean: Array = []
		for b in arr:
			if b is Dictionary and b.has("type"):
				match String(b["type"]):
					"key":
						if b.has("code"):
							clean.append({"type": "key", "code": int(b["code"]), "left": bool(b.get("left", false))})
					"mouse", "joy":
						if b.has("button"):
							clean.append({"type": String(b["type"]), "button": int(b["button"])})
					"axis":
						if b.has("axis") and b.has("value"):
							clean.append({"type": "axis", "axis": int(b["axis"]), "value": float(b["value"])})
		if not clean.is_empty():
			_binds[id] = clean
			_write_input_map(id)
