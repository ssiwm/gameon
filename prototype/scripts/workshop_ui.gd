extends Control
## Panel warsztatu (złom, fazy B i C; wygląd — UI faza 3): szkic techniczny z siatką broni po lewej (miniatura, nazwa, poziom
## ulepszeń albo cena) i szczegółami po prawej: duża miniatura, statystyki „teraz → po zakupie”, lista trzech poziomów
## i przycisk akcji (kup / ulepsz). Wspólny złom drużyny; zakup rozstrzyga serwer (scrap.gd).
## Otwiera go workshop.gd ([E] przy ławie). Na czas panelu akcje gry są wycięte z InputMap (Settings.block_game_input), więc klawisze
## czytamy surowo: strzałki / WASD wybór, Enter lub Spacja akcja, Esc / E / Backspace zamyka. Mysz: kafel wybiera, przycisk kupuje.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")

const GOLD := Color(0.95, 0.8, 0.4)
const COLS := 2
const TILE_W := 150.0
const TILE_H := 46.0
const DETAIL_W := 270.0
## Kolejność siatki: bronie od początku, potem do kupienia za złom, na końcu zablokowane do późniejszych stref.
const LIST := [Weapons.M83, Weapons.SPREAD12, Weapons.P64, Weapons.LR7, Weapons.HKM9, Weapons.SRUT8, Weapons.SOKOL6, Weapons.CIEGNO6]

## Moneta złomu (8×8).
class Coin extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8, 8)
	func _draw() -> void:
		var gold := Color(0.95, 0.78, 0.32)
		var dark := Color(0.5, 0.36, 0.1)
		draw_rect(Rect2(2, 0, 4, 8), dark)
		draw_rect(Rect2(0, 2, 8, 4), dark)
		draw_rect(Rect2(2, 1, 4, 6), gold)
		draw_rect(Rect2(1, 2, 6, 4), gold)
		draw_rect(Rect2(3, 2, 2, 4), dark)

## Trzy kwadraciki poziomu ulepszeń.
class TierBar extends Control:
	var level := 0
	var maxed := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 7)
	func _draw() -> void:
		for i in 3:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < level:
				draw_rect(r, Color(0.45, 1.0, 0.55) if maxed else Color(1.0, 0.72, 0.28))
			else:
				draw_rect(r, Color(0.5, 0.66, 0.7, 0.8), false, 1.0)

## Kafel broni w siatce: miniatura + nazwa + stan (poziom / cena / „późniejsza strefa”).
class Tile extends Button:
	var weapon := 0
	var icon_node: Control
	var name_label: Label
	var bar: TierBar
	var price_label: Label
	var coin: Coin
	var state_label: Label
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = false
		custom_minimum_size = Vector2(150.0, 46.0)

var _open := false
var _sel := 0
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _card: PanelContainer
var _wallet: Label
var _tiles: Array = []
var _d_icon: Control
var _d_title: Label
var _d_tag: Label
var _d_stats: GridContainer
var _d_tiers: VBoxContainer
var _d_text: Label
var _action: Button
var _msg: Label
var _msg_t := 0.0

func _ready() -> void:
	add_to_group("workshop_ui")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.blueprint_box())
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_card.add_child(root)
	# nagłówek: tytuł, portfel
	var head := HBoxContainer.new()
	var title := UiTheme.heading("WORKSHOP", 16, UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var coin := Coin.new()
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(coin)
	_wallet = UiTheme.label("", 11, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)       # liczby zwykłą czcionką: pikselowa 8 myli cyfry (8/3)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_wallet)
	root.add_child(head)
	root.add_child(_rule())
	# korpus: siatka broni | szczegóły
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for i in LIST.size():
		var t := _make_tile(int(LIST[i]), i)
		grid.add_child(t)
		_tiles.append(t)
	body.add_child(_build_detail())
	root.add_child(_rule())
	_msg = UiTheme.label("", 9, UiTheme.BP_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_msg)
	var hint := UiTheme.label("ARROWS select   ·   ENTER buy / upgrade   ·   ESC close   ·   or click", 8, UiTheme.BP_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(hint)
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)

func _make_tile(w: int, idx: int) -> Tile:
	var t := Tile.new()
	t.weapon = w
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	var ic := GunIcon.new()
	var d: RefCounted = Weapons.base_def(w)
	ic.plate = true
	ic.k = 0.3
	ic.position = Vector2(4, 5)
	ic.size = Vector2(54, 36)
	ic.set_gun(int(d.gun_row), d.tracer_color, Color.WHITE)
	t.add_child(ic)
	t.icon_node = ic
	t.name_label = UiTheme.label(String(d.name), 10, UiTheme.BP_TEXT)
	t.name_label.position = Vector2(64, 6)
	t.add_child(t.name_label)
	t.bar = TierBar.new()
	t.bar.position = Vector2(64, 27)
	t.add_child(t.bar)
	t.coin = Coin.new()
	t.coin.position = Vector2(64, 25)
	t.add_child(t.coin)
	t.price_label = UiTheme.label("", 10, GOLD)
	t.price_label.position = Vector2(76, 22)
	t.add_child(t.price_label)
	t.state_label = UiTheme.label("", 8, UiTheme.BP_MUTED)
	t.state_label.position = Vector2(64, 25)
	t.add_child(t.state_label)
	t.pressed.connect(_select.bind(idx))
	return t

func _build_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_d_icon = GunIcon.new()
	(_d_icon as GunIcon).plate = true
	(_d_icon as GunIcon).k = 0.62
	_d_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(_d_icon)
	_d_title = UiTheme.heading("", 16, UiTheme.ACCENT)
	v.add_child(_d_title)
	_d_tag = UiTheme.label("", 8, UiTheme.BP_MUTED)
	v.add_child(_d_tag)
	_d_stats = GridContainer.new()
	_d_stats.columns = 3
	_d_stats.add_theme_constant_override("h_separation", 10)
	_d_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_d_stats)
	v.add_child(_rule())
	_d_tiers = VBoxContainer.new()
	_d_tiers.add_theme_constant_override("separation", 1)
	v.add_child(_d_tiers)
	_d_text = UiTheme.label("", 8, UiTheme.BP_TEXT)
	_d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_d_text)
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", 10)
	_action.pressed.connect(_act)
	v.add_child(_action)
	return v

# ---------------------------------------------------------------- otwieranie

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_msg.text = ""
	_sel = 0
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE            # w grze celownik zastępuje kursor; panel potrzebuje myszy
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(delta: float) -> void:
	if not _open:
		return
	_msg_t = maxf(0.0, _msg_t - delta)
	if _msg_t <= 0.0:
		_msg.text = ""
	# panel zamyka się, gdy gracz odejdzie od ławy / zginie / misja się zmieni
	var wk := get_tree().get_first_node_in_group("workshop")
	if wk == null or not wk.local_in_range or not NoiseMgr.safe_zone:
		close()
		return
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	_card.position = ((size - _card.size) * 0.5).round()

func _exit_tree() -> void:
	if _open:
		Settings.block_game_input(false)
		Input.mouse_mode = _prev_mouse

# ---------------------------------------------------------------- sterowanie

func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_LEFT or k == KEY_A:
		_move(-1)
	elif k == KEY_RIGHT or k == KEY_D:
		_move(1)
	elif k == KEY_UP or k == KEY_W:
		_move(-COLS)
	elif k == KEY_DOWN or k == KEY_S:
		_move(COLS)
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		_act()
	elif k == KEY_ESCAPE or k == KEY_E or k == KEY_BACKSPACE:
		close()
	get_viewport().set_input_as_handled()

func _move(d: int) -> void:
	var n := _sel + d
	if n < 0 or n >= LIST.size():
		return
	_sel = n
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select(i: int) -> void:
	if i != _sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sel = i
	_refresh()

## Akcja na wybranej broni: kup (zablokowana) albo kolejny poziom (odblokowana).
func _act() -> void:
	var w: int = LIST[_sel]
	if Scrap.is_unlocked(w):
		Scrap.request_upgrade(w)
	else:
		Scrap.request_buy(w)

func _on_result(w: int, ok: bool, reason: String) -> void:
	if not _open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"ok":
			_say("%s unlocked — take it from the rack." % name, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say("Not enough scrap (%d needed)." % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			_say("%s is already unlocked." % name, UiTheme.BP_MUTED)
		"later":
			_say("Not available yet — a later zone.", UiTheme.BP_MUTED)
		"up_ok":
			_say("%s upgraded to tier %d." % [name, Scrap.level_of(w)], UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"up_poor":
			_say("Not enough scrap (%d needed)." % Upgrades.COSTS[clampi(Scrap.level_of(w), 0, Upgrades.MAX_LEVEL - 1)], UiTheme.DANGER)
		"up_max":
			_say("%s is fully upgraded." % name, UiTheme.BP_MUTED)
		"up_locked":
			_say("Unlock %s first." % name, UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _say(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg_t = 3.0

# ---------------------------------------------------------------- odświeżanie

func _refresh() -> void:
	if not _open:
		return
	_wallet.text = "%d" % Scrap.bank
	for i in _tiles.size():
		_refresh_tile(_tiles[i] as Tile, i == _sel)
	_refresh_detail(int(LIST[_sel]))

func _refresh_tile(t: Tile, selected: bool) -> void:
	var w := t.weapon
	var sbox := UiTheme.tile_box("selected") if selected else UiTheme.tile_box("normal")
	t.add_theme_stylebox_override("normal", sbox)
	t.add_theme_stylebox_override("pressed", sbox)
	t.add_theme_stylebox_override("focus", sbox)
	var unlocked := Scrap.is_unlocked(w)
	var later := Scrap.LATER.has(w)
	(t.icon_node as GunIcon).set_gun(int(Weapons.base_def(w).gun_row), Weapons.base_def(w).tracer_color, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
	t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if selected else (UiTheme.BP_TEXT if unlocked else UiTheme.BP_MUTED))
	t.bar.visible = unlocked
	t.coin.visible = not unlocked and not later
	t.price_label.visible = not unlocked and not later
	t.state_label.visible = later
	if unlocked:
		var lv := Scrap.level_of(w)
		t.bar.level = lv
		t.bar.maxed = lv >= Upgrades.MAX_LEVEL
		t.bar.queue_redraw()
	elif later:
		t.state_label.text = "LATER ZONE"
	else:
		var price := Scrap.price_of(w)
		t.price_label.text = "%d" % price
		t.price_label.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)

func _refresh_detail(w: int) -> void:
	var base: RefCounted = Weapons.base_def(w)
	var lv := Scrap.level_of(w)
	var unlocked := Scrap.is_unlocked(w)
	var cur: RefCounted = Weapons.def_at(w, lv)
	var has_tiers := Upgrades.has_tiers(String(base.key))
	var next_lv := lv + 1
	var can_next := unlocked and has_tiers and lv < Upgrades.MAX_LEVEL
	(_d_icon as GunIcon).set_gun(int(base.gun_row), base.tracer_color, Color.WHITE if unlocked else Color(0.5, 0.55, 0.6))
	_d_title.text = String(base.name)
	var tag := Codex._slot_name(base)
	if has_tiers and unlocked:
		tag += "  ·  TIER %d / %d" % [lv, Upgrades.MAX_LEVEL]
	elif not unlocked:
		tag += "  ·  LOCKED"
	_d_tag.text = tag
	# statystyki: teraz, a jeśli jest następny poziom — także wartość po zakupie (zielona, gdy się zmienia)
	for ch in _d_stats.get_children():
		_d_stats.remove_child(ch)
		ch.free()
	var now_rows: Array = Codex._weapon_stats(cur)
	var next_rows: Array = Codex._weapon_stats(Weapons.def_at(w, next_lv)) if can_next else []
	for i in now_rows.size():
		var r: Array = now_rows[i]
		_d_stats.add_child(UiTheme.label(String(r[0]), 9, UiTheme.BP_MUTED))
		_d_stats.add_child(UiTheme.label(String(r[1]), 9, UiTheme.BP_TEXT))
		var nv := ""
		var changed := false
		if i < next_rows.size() and String(next_rows[i][1]) != String(r[1]):
			nv = "» %s" % String(next_rows[i][1])
			changed = true
		_d_stats.add_child(UiTheme.label(nv, 9, UiTheme.OK if changed else UiTheme.BP_MUTED))
	# poziomy ulepszeń
	for ch in _d_tiers.get_children():
		_d_tiers.remove_child(ch)
		ch.free()
	if has_tiers:
		for i in range(1, Upgrades.MAX_LEVEL + 1):
			var t := Upgrades.tier(String(base.key), i)
			var state := 0 if (unlocked and i <= lv) else (1 if (unlocked and i == lv + 1) else 2)
			var col: Color = UiTheme.OK if state == 0 else (GOLD if state == 1 else UiTheme.BP_MUTED)
			var tail := "installed" if state == 0 else "%d" % Upgrades.COSTS[i - 1]
			var l := UiTheme.label("T%d  %s — %s  [%s]" % [i, t["name"], t["desc"], tail], 8, col)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(DETAIL_W, 0)
			_d_tiers.add_child(l)
	var notes: Array = Codex.WEAPON_TEXT.get(String(base.key), ["", ""])
	_d_text.text = String(notes[0])
	# przycisk akcji
	if not unlocked and Scrap.LATER.has(w):
		_action.text = "Available in a later zone"
	elif not unlocked:
		_action.text = "Buy  ·  %d scrap" % Scrap.price_of(w)
	elif can_next:
		_action.text = "Upgrade to tier %d  ·  %d scrap" % [next_lv, Upgrades.COSTS[lv]]
	else:
		_action.text = "Fully upgraded"
	_card.reset_size()

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.BP_LINE, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
