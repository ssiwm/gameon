extends RefCounted
## Rejestr akcji wejściowych — jedno źródło prawdy o tym, jakie akcje ma gra i jakimi klawiszami się je wywołuje.
##
## Z niego korzystają: `input_setup.gd` (rejestracja w InputMap), `settings.gd` (które akcje wyciąć na czas menu),
## ściąga sterowania w lobby i menu pauzy (`sheet()`), pasek sterowania w HUD (`hud_line()`) oraz teksty podpowiedzi
## (`fmt()`, `key()`), więc nazwa klawisza nie jest już wpisana ręcznie w kilkunastu miejscach.
##
## Wiązanie to słownik: {"type": "key", "code": Key, "left": bool} (left = tylko lewa strona klawiatury, np. lewy Alt)
## albo {"type": "mouse", "button": MouseButton}. Klawisze to `physical_keycode` (układ-niezależne, jak dotąd).

## id → ["keys": [Key | {"key": Key, "left": true}], "keys_macos": (zamiast keys na macOS), "mouse": [MouseButton],
##        "menu": true = akcja zostaje aktywna przy otwartym menu pauzy (reszta jest wycinana, żeby klik w menu nie strzelał)]
const DEFS := {
	"move_left": {"keys": [KEY_A, KEY_LEFT]},
	"move_right": {"keys": [KEY_D, KEY_RIGHT]},
	"move_up": {"keys": [KEY_W, KEY_UP]},
	"move_down": {"keys": [KEY_S, KEY_DOWN]},
	"jump": {"keys": [KEY_SPACE]},
	"fire": {"keys": [KEY_J], "mouse": [MOUSE_BUTTON_LEFT]},
	"crouch": {"keys": [KEY_SHIFT]},
	"overcharge": {"keys": [KEY_Q]},
	"scream": {"keys": [KEY_G]},
	"flare": {"keys": [KEY_F]},
	"interact": {"keys": [KEY_E]},
	"weapon_1": {"keys": [KEY_1]},
	"weapon_2": {"keys": [KEY_2]},
	"weapon_3": {"keys": [KEY_3]},
	"restart": {"keys": [KEY_ENTER, KEY_KP_ENTER]},
	"flashlight": {"keys": [KEY_L]},
	"reload": {"keys": [KEY_R]},
	"firemode": {"keys": [KEY_B]},
	# użycie przedmiotu: lewy Alt (na macOS lewy Cmd pierwszy, lewy Alt też działa); prawy Alt / Cmd zostaje wolny
	"throw": {"keys": [{"key": KEY_ALT, "left": true}], "keys_macos": [{"key": KEY_META, "left": true}, {"key": KEY_ALT, "left": true}]},
	"throw_next": {"keys": [KEY_X]},
	"melee": {"keys": [KEY_V], "mouse": [MOUSE_BUTTON_RIGHT]},
	"help": {"keys": [KEY_F1]},
	"pause": {"keys": [KEY_ESCAPE, KEY_P], "menu": true},
	"weapon_next": {"mouse": [MOUSE_BUTTON_WHEEL_DOWN]},
	"weapon_prev": {"mouse": [MOUSE_BUTTON_WHEEL_UP]},
	# poniżej: dawniej surowe klawisze sprawdzane w skryptach (F2 w main.gd, F11 w settings.gd, O w hud.gd)
	"steam_invite": {"keys": [KEY_F2], "menu": true},
	"fullscreen": {"keys": [KEY_F11], "menu": true},
	"open_store": {"keys": [KEY_O]},
}

## Nazwy klawiszy tam, gdzie `OS.get_keycode_string` daje inną niż ta, którą widzi gracz.
const KEY_NAMES := {KEY_ESCAPE: "Esc", KEY_KP_ENTER: "Enter", KEY_META: "Cmd"}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel", MOUSE_BUTTON_WHEEL_DOWN: "Wheel",
}
const ARROWS := [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

## id → Array[Dictionary]: aktualne wiązania (po `register()` domyślne).
static var _binds := {}

## Rejestruje wszystkie akcje w InputMap (woła `input_setup.gd`). Powtórne wywołanie niczego nie dubluje.
static func register() -> void:
	_binds.clear()
	var mac := OS.get_name() == "macOS"
	for id in DEFS:
		var d: Dictionary = DEFS[id]
		var list: Array = []
		var keys: Array = d["keys_macos"] if (mac and d.has("keys_macos")) else d.get("keys", [])
		for k in keys:
			if k is Dictionary:
				list.append({"type": "key", "code": int(k["key"]), "left": bool(k.get("left", false))})
			else:
				list.append({"type": "key", "code": int(k), "left": false})
		for b in d.get("mouse", []):
			list.append({"type": "mouse", "button": int(b)})
		_binds[id] = list
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		InputMap.action_erase_events(id)
		for b in list:
			InputMap.action_add_event(id, _event_of(b))

static func _event_of(b: Dictionary) -> InputEvent:
	if String(b["type"]) == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(b["button"])
		return m
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

static func _name_of(b: Dictionary) -> String:
	if String(b["type"]) == "mouse":
		return String(MOUSE_NAMES.get(int(b["button"]), "Mouse %d" % int(b["button"])))
	var code := int(b["code"])
	var n: String = String(KEY_NAMES.get(code, OS.get_keycode_string(code)))
	return ("L-" + n) if bool(b.get("left", false)) else n

## Nazwa(y) klawiszy akcji: "J / LMB". `first_only` — tylko pierwsze wiązanie (do podpowiedzi w nawiasach).
static func text(id: String, first_only := false) -> String:
	var names: Array = []
	for b in _binds.get(id, []):
		var n := _name_of(b)
		if not names.has(n):
			names.append(n)
		if first_only:
			break
	return " / ".join(names) if not names.is_empty() else "—"

## Krótka nazwa pierwszego klawisza wersalikami do nawiasów w podpowiedziach: `[E]`, `[ENTER]`, `[L-ALT]`.
static func key(id: String) -> String:
	return text(id, true).to_upper()

## Grupa akcji jako jedna nazwa: ruch → "WASD / Arrows". Każde wiązanie (slot) to osobna część, połączone `sep`;
## same strzałki skracają się do „Arrows”. `first_slot_only` — tylko pierwszy slot („WASD”).
static func cluster(action_ids: Array, sep := "", first_slot_only := false) -> String:
	var slots := 0
	for id in action_ids:
		slots = maxi(slots, (_binds.get(id, []) as Array).size())
	if first_slot_only:
		slots = mini(slots, 1)
	var parts: Array = []
	for s in slots:
		var names: Array = []
		var all_arrows := true
		for id in action_ids:
			var arr: Array = _binds.get(id, [])
			if s >= arr.size():
				continue
			var b: Dictionary = arr[s]
			names.append(_name_of(b))
			all_arrows = all_arrows and String(b["type"]) == "key" and ARROWS.has(int(b["code"]))
		if names.is_empty():
			continue
		parts.append("Arrows" if all_arrows else sep.join(names))
	return " / ".join(parts)

const MOVE_IDS := ["move_up", "move_left", "move_down", "move_right"]
const WEAPON_IDS := ["weapon_1", "weapon_2", "weapon_3"]

## Podstawia `{id}` nazwą klawisza akcji (wersaliki, pierwsze wiązanie): "Press {overcharge}" → "Press Q".
## Dodatkowy znacznik `{move}` = ruch („WASD”).
static func fmt(template: String) -> String:
	var out := template.replace("{move}", cluster(MOVE_IDS, "", true))
	for id in DEFS:
		var token := "{%s}" % id
		if out.contains(token):
			out = out.replace(token, key(id))
	return out

# ---------------------------------------------------------------- ściągi

## Wiersze ściągi sterowania [klawisze, opis] (lobby, menu pauzy) — klawisze z aktualnych wiązań.
static func sheet() -> Array:
	return [
		[cluster(MOVE_IDS), "Move & aim"],
		[text("jump"), "Jump (hold = higher)"],
		["%s + %s" % [text("move_down", true), text("jump", true)], "Drop through a catwalk"],
		[text("crouch"), "Sneak — silent"],
		[text("fire"), "Fire — makes NOISE"],
		[text("reload"), "Reload"],
		[text("firemode"), "Fire mode (auto / burst)"],
		[text("melee"), "Melee"],
		["%s / %s" % [cluster(WEAPON_IDS, " "), text("weapon_next")], "Switch weapon"],
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
		"%s move" % cluster(MOVE_IDS, "", true),
		"%s jump" % key("jump"),
		"%s+%s drop" % [key("move_down"), key("jump")],
		"%s sneak" % key("crouch"),
		"%s fire" % text("fire").replace(" / ", "/").to_upper(),
		"%s reload" % key("reload"),
		"%s fire mode" % key("firemode"),
		"%s item (%s switch)" % [key("throw"), key("throw_next")],
		"%s melee" % text("melee").replace(" / ", "/").to_upper(),
		"%s-%s gun" % [key("weapon_1"), key("weapon_3")],
		"%s take/revive" % key("interact"),
		"%s lure" % key("overcharge"),
		"%s flare" % key("flare"),
		"%s scream" % key("scream"),
		"%s light" % key("flashlight"),
	]
	return " · ".join(items)
