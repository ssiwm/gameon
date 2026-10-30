extends RefCounted
## Czysta polityka wiązań: migracja, konteksty i nakładanie zdarzeń. Nie zmienia InputMap ani ustawień.
const CONTEXTS := ["mission", "range", "menu", "range_menu", "chat", "result"]
const GLOBAL := ["pause", "fullscreen", "steam_invite"]
const SHARED := ["fire", "reload", "firemode", "ammo_type", "move_left", "move_right", "crouch", "interact", "help", "chat", "journal"]

static func contexts(id: String) -> Array:
	if id in GLOBAL:
		return CONTEXTS
	if id.begins_with("menu_"):
		return ["menu", "range_menu"]
	if id.begins_with("result_"):
		return ["result"]               # raport po akcji: własny ekran, klawisze nie walczą z misją
	if id == "range_locker":
		return ["range", "range_menu"]
	if id.begins_with("range_") or id == "aim_sights":
		return ["range"]
	if id in SHARED or id.begins_with("weapon_") or id.begins_with("aim_"):
		return ["mission", "range"]
	return ["mission"]

static func simultaneous(a: String, b: String) -> bool:
	for c in contexts(a):
		if c in contexts(b):
			return true
	return false

static func normalize(raw: Dictionary) -> Dictionary:
	if not raw.get("type", "") is String:
		return {}
	for field in ["code", "location", "button", "axis"]:
		if raw.has(field) and not raw[field] is int:
			return {}
	if raw.has("value") and not (raw.value is int or raw.value is float):
		return {}
	match String(raw.get("type", "")):
		"key":
			var code := int(raw.get("code", 0))
			var loc := int(raw.get("location", KEY_LOCATION_LEFT if bool(raw.get("left", false)) else KEY_LOCATION_UNSPECIFIED))
			if code > 0 and code < KEY_UNKNOWN and loc in [KEY_LOCATION_UNSPECIFIED, KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
				return {"type": "key", "code": code, "location": loc}
		"mouse", "joy":
			var button := int(raw.get("button", -1))
			var limit := MOUSE_BUTTON_XBUTTON2 if raw.type == "mouse" else JOY_BUTTON_MAX - 1
			var minimum := MOUSE_BUTTON_LEFT if raw.type == "mouse" else 0
			if button >= minimum and button <= limit:
				return {"type": String(raw.type), "button": button}
		"axis":
			var axis := int(raw.get("axis", -1))
			var value := float(raw.get("value", 0.0))
			if axis >= 0 and axis < JOY_AXIS_MAX and absf(value) == 1.0:
				return {"type": "axis", "axis": axis, "value": value}
	return {}

static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a.type != b.type:
		return false
	match String(a.type):
		"key":
			return a.code == b.code and (a.location == b.location or a.location == KEY_LOCATION_UNSPECIFIED or b.location == KEY_LOCATION_UNSPECIFIED)
		"axis":
			return a.axis == b.axis and a.value == b.value
	return a.button == b.button

static func allowed_alias(a: String, b: String, binding: Dictionary) -> bool:
	# Esc zamyka każdą nakładkę. Szafa strzelnicy rozstrzyga D-pad → przez _locker_key.
	var pair := [a, b]
	if "pause" in pair and "menu_back" in pair:
		return binding.type == "key" and binding.code == KEY_ESCAPE
	if "range_locker" in pair and "menu_right" in pair:
		return binding.type == "joy" and binding.button == JOY_BUTTON_DPAD_RIGHT
	return false

static func conflicts(binds: Dictionary) -> Array:
	var out := []
	var ids := binds.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := String(ids[i])
			var b := String(ids[j])
			if not simultaneous(a, b):
				continue
			for x in binds[a]:
				for y in binds[b]:
					if overlaps(x, y) and not allowed_alias(a, b, x):
						out.append({"a": a, "b": b})
						break
	return out
