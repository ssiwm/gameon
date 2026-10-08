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
const Throwables := preload("res://scripts/throwables.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const PerkIcon := preload("res://scripts/perk_icon.gd")
const Perks := preload("res://scripts/perks.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")

const GOLD := Color(0.95, 0.8, 0.4)
const COLS := 2
const TILE_W := 150.0
const TILE_H := 46.0
const DETAIL_W := 270.0
## Kolejność siatki: bronie od początku, potem do kupienia za złom, na końcu zablokowane do późniejszych stref.
const LIST := [Weapons.M83, Weapons.SPREAD12, Weapons.P64, Weapons.LR7, Weapons.HKM9, Weapons.SRUT8, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6, Weapons.MACZETA, Weapons.KILOF]

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

## Kropki zapasu drużyny: `have` wypełnionych z `maxn` (jak kwadraciki poziomu ulepszeń broni).
class StockBar extends Control:
	var have := 0
	var maxn := 3
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(36, 7)
	func _draw() -> void:
		for i in maxn:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < have:
				draw_rect(r, Color(0.45, 1.0, 0.55) if have >= maxn else Color(1.0, 0.72, 0.28))
			else:
				draw_rect(r, Color(0.5, 0.66, 0.7, 0.8), false, 1.0)

## Pasek poziomu profilu: wypełnienie = postęp XP w bieżącym poziomie.
class LevelBar extends Control:
	var frac := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 7)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.66, 0.7, 0.8), false, 1.0)
		draw_rect(Rect2(1, 1, maxf(0.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0))

## Kafel perku w siatce: miniatura + nazwa + stan (poziom odblokowania / założony / dostępny).
## Podgląd postaci z arkusza HD (256×384 na klatkę): animowany (bieg/idle) w kafelku i w szczegółach zakładki LOOK. Arkusz ładowany leniwie (z mipmapami).
class LookView extends Control:
	var code := 0
	var anim := "idle"
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func set_code(c: int) -> void:
		if c != code:
			code = c
			queue_redraw()

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var sheet := Look.sheet(code)
		if not Sprites.has(sheet):
			return
		var man: Dictionary = Sprites.manifest()["sheets"][sheet]
		var an: Dictionary = man["anims"].get(anim, man["anims"]["idle"])
		var fr: Array = man["frame"]
		var frame := int(_t * float(an["fps"])) % maxi(1, int(an["frames"]))
		var tex := Sprites.mip_texture(Sprites.DIR + sheet + ".png")
		if tex == null:
			return
		var s := minf(size.x / float(fr[0]), size.y / float(fr[1]))
		var w := Vector2(float(fr[0]), float(fr[1])) * s
		draw_texture_rect_region(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), Rect2(frame * fr[0], int(an["row"]) * fr[1], fr[0], fr[1]))

class LookTile extends Button:
	var code := 0
	var view: LookView
	var name_label: Label
	var state_label: Label

class PerkTile extends Button:
	var perk := ""
	var icon_node: Control
	var name_label: Label
	var state_label: Label
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = false
		custom_minimum_size = Vector2(150.0, 46.0)

## Kafel zaopatrzenia w siatce: miniatura przedmiotu + nazwa + cena (moneta) + zapas drużyny.
class SupplyTile extends Button:
	var kind := ""
	var icon_node: Control
	var name_label: Label
	var coin: Coin
	var price_label: Label
	var bar: StockBar
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = false
		custom_minimum_size = Vector2(150.0, 46.0)

var _open := false
var _page := 0                        ## 0 = ARMS (bronie i ulepszenia), 1 = SUPPLIES (granaty, miny, narzędzia)
var _sup_sel := 0
var _arms_body: HBoxContainer
var _sup_body: HBoxContainer
var _sup_tiles: Array = []            ## kafle zaopatrzenia (SupplyTile) — kolejność = _supply_kinds()
var _s_icon: ItemIcon
var _s_title: Label
var _s_tag: Label
var _s_stats: GridContainer
var _s_text: Label
var _s_action: Button
var _page_btns: Array[Button] = []
var _look_body: HBoxContainer
var _look_sel := 0
var _look_tiles: Array = []
var _l_view: LookView
var _l_title: Label
var _l_tag: Label
var _l_text: Label
var _l_action: Button
var _perk_body: HBoxContainer
var _perk_sel := 0
var _perk_slot := 0
var _perk_tiles: Array = []
var _slot_chips: Array = []           ## [{root, icon, name, sub}] dla dwóch slotów
var _lvl_label: Label
var _lvl_bar: LevelBar
var _xp_label: Label
var _p_icon: PerkIcon
var _p_title: Label
var _p_tag: Label
var _p_stats: GridContainer
var _p_text: Label
var _p_action: Button
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
	for pi in 4:
		var pb := Button.new()                                 # zakładki ARMS / SUPPLIES / PERKS / LOOK (Tab przełącza)
		pb.text = ["ARMS", "SUPPLIES", "PERKS", "LOOK"][pi]
		pb.toggle_mode = true
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_font_size_override("font_size", 9)
		pb.pressed.connect(_set_page.bind(pi))
		head.add_child(pb)
		_page_btns.append(pb)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	head.add_child(gap)
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
	_arms_body = body
	_sup_body = _build_supplies()
	root.add_child(_sup_body)
	_sup_body.visible = false
	_perk_body = _build_perks()
	root.add_child(_perk_body)
	_perk_body.visible = false
	_look_body = _build_look()
	root.add_child(_look_body)
	_look_body.visible = false
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
	var hint := UiTheme.label("ARROWS select   ·   ENTER buy / upgrade / equip   ·   TAB arms / supplies / perks / look   ·   ESC close   ·   or click", 8, UiTheme.BP_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(hint)
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)
	Scrap.supply_result.connect(_on_supply_result)
	Profile.changed.connect(_refresh)
	Arsenal.stock_changed.connect(_refresh)

## Zakładka SUPPLIES: ten sam układ co ARMS — siatka kafli po lewej (miniatura, nazwa, cena, zapas), szczegóły po prawej.
func _build_supplies() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))            # tyle co ARMS — karta nie skacze przy przełączaniu
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(grid)
	var kinds := _supply_kinds()
	for i in kinds.size():
		var t := _make_supply_tile(String(kinds[i]), i)
		grid.add_child(t)
		_sup_tiles.append(t)
	body.add_child(_build_supply_detail())
	return body

func _make_supply_tile(kd: String, idx: int) -> SupplyTile:
	var data: Dictionary = Throwables.KINDS[kd]
	var t := SupplyTile.new()
	t.kind = kd
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	var ic := ItemIcon.new()
	ic.k = 1.0
	ic.position = Vector2(4, 5)
	ic.size = Vector2(54, 36)
	ic.set_item(kd, Color.WHITE)
	t.add_child(ic)
	t.icon_node = ic
	t.name_label = UiTheme.label(String(data["name"]), 10, UiTheme.BP_TEXT)
	t.name_label.position = Vector2(64, 6)
	t.add_child(t.name_label)
	t.coin = Coin.new()
	t.coin.position = Vector2(64, 26)
	t.add_child(t.coin)
	t.price_label = UiTheme.label("%d" % Throwables.price_of(kd), 10, GOLD)
	t.price_label.position = Vector2(76, 23)
	t.add_child(t.price_label)
	t.bar = StockBar.new()
	t.bar.maxn = int(data["max"])
	t.bar.position = Vector2(150.0 - 6.0 - float(t.bar.maxn) * 9.0 + 2.0, 27)
	t.add_child(t.bar)
	t.pressed.connect(_select_supply.bind(idx))
	return t

func _build_supply_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_s_icon = ItemIcon.new()
	_s_icon.k = 2.0
	_s_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(_s_icon)
	_s_title = UiTheme.heading("", 16, UiTheme.ACCENT)
	v.add_child(_s_title)
	_s_tag = UiTheme.label("", 8, UiTheme.BP_MUTED)
	v.add_child(_s_tag)
	_s_stats = GridContainer.new()
	_s_stats.columns = 3
	_s_stats.add_theme_constant_override("h_separation", 10)
	_s_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_s_stats)
	v.add_child(_rule())
	_s_text = UiTheme.label("", 8, UiTheme.BP_TEXT)
	_s_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_s_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_s_text)
	_s_action = Button.new()
	_s_action.focus_mode = Control.FOCUS_NONE
	_s_action.add_theme_font_size_override("font_size", 10)
	_s_action.pressed.connect(_buy_selected_supply)
	v.add_child(_s_action)
	return v

## Zakładka LOOK: siatka 2 × 3 (kolumny: mężczyzna / kobieta, wiersze: stroje) z animowanymi podglądami i szczegóły z przyciskiem Equip.
## Kod wyglądu kafla i = wiersz (strój) × 2 + kolumna (płeć). Stroje odblokowuje poziom profilu (Look.UNLOCK_LEVEL); wygląd jest tylko kosmetyką.
func _look_code(i: int) -> int:
	return Look.code(i % COLS, i / COLS)

func _build_look() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in Look.GENDERS.size() * Look.OUTFITS.size():
		var t := LookTile.new()
		t.code = _look_code(i)
		t.custom_minimum_size = Vector2(TILE_W, TILE_H * 1.5)
		t.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
		t.view = LookView.new()
		t.view.position = Vector2(4, 3)
		t.view.size = Vector2(46, TILE_H * 1.5 - 6.0)
		t.view.set_code(t.code)
		t.add_child(t.view)
		t.name_label = UiTheme.label(Look.display_name(t.code), 9, UiTheme.BP_TEXT)
		t.name_label.position = Vector2(56, 14)
		t.add_child(t.name_label)
		t.state_label = UiTheme.label("", 8, UiTheme.BP_MUTED)
		t.state_label.position = Vector2(56, 34)
		t.add_child(t.state_label)
		t.pressed.connect(_select_look.bind(i))
		grid.add_child(t)
		_look_tiles.append(t)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_l_view = LookView.new()
	_l_view.anim = "run"
	_l_view.custom_minimum_size = Vector2(0, 150)
	v.add_child(_l_view)
	_l_title = UiTheme.heading("", 16, UiTheme.ACCENT)
	v.add_child(_l_title)
	_l_tag = UiTheme.label("", 8, UiTheme.BP_MUTED)
	v.add_child(_l_tag)
	v.add_child(_rule())
	_l_text = UiTheme.label("", 8, UiTheme.BP_TEXT)
	_l_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_l_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_l_text)
	_l_action = Button.new()
	_l_action.focus_mode = Control.FOCUS_NONE
	_l_action.add_theme_font_size_override("font_size", 10)
	_l_action.pressed.connect(_act_look)
	v.add_child(_l_action)
	body.add_child(v)
	return body

func _select_look(i: int) -> void:
	_look_sel = i
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _act_look() -> void:
	var c := _look_code(_look_sel)
	if Profile.look == c:
		_say("Already wearing %s." % Look.display_name(c), UiTheme.BP_MUTED)
	elif Profile.set_look(c):
		Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		_say("%s (%s) equipped." % [Look.display_name(c), Look.gender_id(c)], UiTheme.OK)
	else:
		_say("Unlocks at level %d." % Look.unlock_level(c), UiTheme.DANGER)

func _refresh_look() -> void:
	var lvl := Profile.level()
	for i in _look_tiles.size():
		var t := _look_tiles[i] as LookTile
		var sel := i == _look_sel
		var sbox := UiTheme.tile_box("selected") if sel else UiTheme.tile_box("normal")
		t.add_theme_stylebox_override("normal", sbox)
		t.add_theme_stylebox_override("pressed", sbox)
		t.add_theme_stylebox_override("focus", sbox)
		var ok := Look.is_unlocked(t.code, lvl)
		t.view.modulate = Color.WHITE if ok else Color(0.35, 0.4, 0.45)
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.BP_TEXT)
		t.state_label.text = ("EQUIPPED" if Profile.look == t.code else "AVAILABLE") if ok else "LV %d" % Look.unlock_level(t.code)
		t.state_label.add_theme_color_override("font_color", UiTheme.OK if Profile.look == t.code else (UiTheme.BP_MUTED if ok else UiTheme.DANGER))
	var c := _look_code(_look_sel)
	_l_view.set_code(c)
	_l_view.modulate = Color.WHITE if Look.is_unlocked(c, lvl) else Color(0.35, 0.4, 0.45)
	_l_title.text = Look.display_name(c)
	_l_tag.text = "%s  ·  unlocks at level %d" % [Look.gender_id(c).to_upper(), Look.unlock_level(c)]
	_l_text.text = String(Look.OUTFIT_TEXT[Look.outfit_id(c)]) + "\n\nCosmetic only — other players see your look too."
	_l_action.disabled = false
	_l_action.text = "Wearing" if Profile.look == c else ("Equip" if Look.is_unlocked(c, lvl) else "Locked — level %d" % Look.unlock_level(c))

## Zakładka PERKS: ten sam układ co ARMS i SUPPLIES — po lewej pasek poziomu, siatka kafli i dwa sloty, po prawej szczegóły wybranego perku.
func _build_perks() -> HBoxContainer:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (TILE_H + 6.0))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	_lvl_label = UiTheme.heading("LV 1", 12, UiTheme.ACCENT)
	lv.add_child(_lvl_label)
	_lvl_bar = LevelBar.new()
	_lvl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(_lvl_bar)
	_xp_label = UiTheme.label("", 9, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	lv.add_child(_xp_label)
	left.add_child(lv)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in Perks.ORDER.size():
		var t := _make_perk_tile(String(Perks.ORDER[i]), i)
		grid.add_child(t)
		_perk_tiles.append(t)
	left.add_child(_rule())
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	left.add_child(slots)
	for si in 2:
		slots.add_child(_make_slot_chip(si))
	body.add_child(_build_perk_detail())
	return body

func _make_perk_tile(id: String, idx: int) -> PerkTile:
	var t := PerkTile.new()
	t.perk = id
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	var ic := PerkIcon.new()
	ic.k = 1.0
	ic.position = Vector2(4, 5)
	ic.size = Vector2(54, 36)
	ic.set_perk(id, Color.WHITE)
	t.add_child(ic)
	t.icon_node = ic
	t.name_label = UiTheme.label(Perks.display_name(id), 10, UiTheme.BP_TEXT)
	t.name_label.position = Vector2(64, 6)
	t.add_child(t.name_label)
	t.state_label = UiTheme.label("", 8, UiTheme.BP_MUTED)
	t.state_label.position = Vector2(64, 25)
	t.add_child(t.state_label)
	t.pressed.connect(_select_perk.bind(idx))
	return t

## Slot perka (0–1) pod siatką: miniatura założonego perka, nazwa albo „empty” / poziom odblokowania. Klik albo klawisz 1 / 2 wybiera slot docelowy.
func _make_slot_chip(si: int) -> Control:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(150, 40)
	root.add_theme_stylebox_override("panel", UiTheme.tile_box("normal"))
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	root.add_child(h)
	var ic := PerkIcon.new()
	ic.k = 1.0
	ic.custom_minimum_size = Vector2(40, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	var cap := UiTheme.label("SLOT %d  [%d]" % [si + 1, si + 1], 8, UiTheme.BP_MUTED)
	col.add_child(cap)
	var nm := UiTheme.label("", 9, UiTheme.BP_TEXT)
	col.add_child(nm)
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_perk_slot = si
			_refresh())
	_slot_chips.append({"root": root, "icon": ic, "name": nm})
	return root

func _build_perk_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_p_icon = PerkIcon.new()
	_p_icon.k = 2.0
	_p_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(_p_icon)
	_p_title = UiTheme.heading("", 16, UiTheme.ACCENT)
	v.add_child(_p_title)
	_p_tag = UiTheme.label("", 8, UiTheme.BP_MUTED)
	v.add_child(_p_tag)
	_p_stats = GridContainer.new()
	_p_stats.columns = 3
	_p_stats.add_theme_constant_override("h_separation", 10)
	_p_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_p_stats)
	v.add_child(_rule())
	_p_text = UiTheme.label("", 8, UiTheme.BP_TEXT)
	_p_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_p_text)
	_p_action = Button.new()
	_p_action.focus_mode = Control.FOCUS_NONE
	_p_action.add_theme_font_size_override("font_size", 10)
	_p_action.pressed.connect(_act_perk)
	v.add_child(_p_action)
	return v

func _select_perk(i: int) -> void:
	if i != _perk_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_perk_sel = i
	_refresh()

## Które sloty zajmuje perk: indeks slotu albo -1.
func _perk_slot_of(id: String) -> int:
	return Profile.equipped.find(id)

## Akcja na wybranym perku: zdejmij (jeśli założony) albo załóż w wybranym slocie.
func _act_perk() -> void:
	var id := String(Perks.ORDER[_perk_sel])
	var have := _perk_slot_of(id)
	if have >= 0:
		Profile.unequip(have)
		_say("%s removed." % Perks.display_name(id), UiTheme.BP_MUTED)
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		return
	if not Profile.is_unlocked(id):
		_say("Reach level %d to unlock %s." % [Perks.unlock_level(id), Perks.display_name(id)], UiTheme.BP_MUTED)
		return
	if _perk_slot >= Profile.slots():
		_say("Slot %d unlocks at level %d." % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])], UiTheme.BP_MUTED)
		return
	if Profile.equip(_perk_slot, id):
		_say("%s equipped in slot %d." % [Perks.display_name(id), _perk_slot + 1], UiTheme.OK)
		Audio.play("ui_confirm", Audio.BUS_UI, -4.0)

func _refresh_perks() -> void:
	var lp := Profile.level_progress()
	_lvl_label.text = "LV %d" % Profile.level()
	_lvl_bar.frac = clampf(float(lp[0]) / maxf(1.0, float(lp[1])), 0.0, 1.0)
	_lvl_bar.queue_redraw()
	_xp_label.text = "%d / %d XP" % [int(lp[0]), int(lp[1])]
	if _perk_slot >= maxi(1, Profile.slots()):
		_perk_slot = 0
	for i in _perk_tiles.size():
		var t := _perk_tiles[i] as PerkTile
		var id := t.perk
		var sel := i == _perk_sel
		var sbox := UiTheme.tile_box("selected") if sel else UiTheme.tile_box("normal")
		t.add_theme_stylebox_override("normal", sbox)
		t.add_theme_stylebox_override("pressed", sbox)
		t.add_theme_stylebox_override("focus", sbox)
		var unlocked := Profile.is_unlocked(id)
		var at := _perk_slot_of(id)
		(t.icon_node as PerkIcon).set_perk(id, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else (UiTheme.BP_TEXT if unlocked else UiTheme.BP_MUTED))
		if at >= 0:
			t.state_label.text = "EQUIPPED  ·  SLOT %d" % (at + 1)
			t.state_label.add_theme_color_override("font_color", UiTheme.OK)
		elif unlocked:
			t.state_label.text = "AVAILABLE"
			t.state_label.add_theme_color_override("font_color", UiTheme.BP_MUTED)
		else:
			t.state_label.text = "LV %d" % Perks.unlock_level(id)
			t.state_label.add_theme_color_override("font_color", GOLD if Profile.level() + 1 >= Perks.unlock_level(id) else UiTheme.DANGER)
	for si in _slot_chips.size():
		var c: Dictionary = _slot_chips[si]
		var open := si < Profile.slots()
		var eq := String(Profile.equipped[si])
		var chosen := si == _perk_slot
		(c["root"] as PanelContainer).add_theme_stylebox_override("panel", UiTheme.tile_box("selected") if chosen else UiTheme.tile_box("normal"))
		if not open:
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "LV %d" % int(Profile.SLOT_LEVELS[si])
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.DANGER)
		elif eq == "":
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "empty"
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.BP_MUTED)
		else:
			(c["icon"] as PerkIcon).set_perk(eq, Color.WHITE)
			(c["name"] as Label).text = Perks.display_name(eq)
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.BP_TEXT)
	var id2 := String(Perks.ORDER[_perk_sel])
	var d: Dictionary = Perks.PERKS[id2]
	var unlocked2 := Profile.is_unlocked(id2)
	var at2 := _perk_slot_of(id2)
	_p_icon.set_perk(id2, Color.WHITE if unlocked2 else Color(0.55, 0.6, 0.65))
	_p_title.text = String(d["name"]).to_upper()
	_p_tag.text = "Perk  ·  unlocks at level %d" % int(d["level"])
	for ch in _p_stats.get_children():
		_p_stats.remove_child(ch)
		ch.free()
	var status := "Equipped — slot %d" % (at2 + 1) if at2 >= 0 else ("Available" if unlocked2 else "Locked — reach level %d" % int(d["level"]))
	for r in [["Status", status], ["Slots", "%d of 2 open" % Profile.slots()]]:
		_p_stats.add_child(UiTheme.label(String(r[0]), 9, UiTheme.BP_MUTED))
		_p_stats.add_child(UiTheme.label(String(r[1]), 9, UiTheme.OK if at2 >= 0 and String(r[0]) == "Status" else UiTheme.BP_TEXT))
		_p_stats.add_child(Control.new())
	_p_text.text = String(d["desc"])
	if at2 >= 0:
		_p_action.text = "Remove from slot %d" % (at2 + 1)
		_p_action.disabled = false
	elif not unlocked2:
		_p_action.text = "Locked  ·  reach level %d" % int(d["level"])
		_p_action.disabled = true
	elif _perk_slot >= Profile.slots():
		_p_action.text = "Slot %d unlocks at level %d" % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])]
		_p_action.disabled = true
	else:
		_p_action.text = "Equip in slot %d" % (_perk_slot + 1)
		_p_action.disabled = false

func _select_supply(i: int) -> void:
	if i != _sup_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sup_sel = i
	_refresh()

func _buy_selected_supply() -> void:
	Scrap.request_buy_supply(String(_supply_kinds()[_sup_sel]))

## Rodzaje do kupienia (z ceną) w kolejności karuzeli.
func _supply_kinds() -> Array:
	var out: Array = []
	for k in Throwables.ORDER:
		if Throwables.price_of(String(k)) > 0:
			out.append(k)
	return out

func _set_page(p: int) -> void:
	if p == _page:
		_page_btns[p].set_pressed_no_signal(true)
		return
	_page = p
	Audio.play("ui_click", Audio.BUS_UI, -12.0, 1.1)
	_refresh()

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
	_page = 0
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
	if k == KEY_TAB:
		_set_page((_page + 1) % 4)
		get_viewport().set_input_as_handled()
		return
	if _page == 3:
		var lstep := 0
		if k == KEY_LEFT or k == KEY_A:
			lstep = -1
		elif k == KEY_RIGHT or k == KEY_D:
			lstep = 1
		elif k == KEY_UP or k == KEY_W:
			lstep = -COLS
		elif k == KEY_DOWN or k == KEY_S:
			lstep = COLS
		if lstep != 0 and _look_sel + lstep >= 0 and _look_sel + lstep < Look.GENDERS.size() * Look.OUTFITS.size():
			_look_sel += lstep
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			_act_look()
		elif k == KEY_ESCAPE or k == KEY_E or k == KEY_BACKSPACE:
			close()
		get_viewport().set_input_as_handled()
		return
	if _page == 2:
		var pn := Perks.ORDER.size()
		var pstep := 0
		if k == KEY_LEFT or k == KEY_A:
			pstep = -1
		elif k == KEY_RIGHT or k == KEY_D:
			pstep = 1
		elif k == KEY_UP or k == KEY_W:
			pstep = -COLS
		elif k == KEY_DOWN or k == KEY_S:
			pstep = COLS
		if pstep != 0 and _perk_sel + pstep >= 0 and _perk_sel + pstep < pn:
			_perk_sel += pstep
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif k == KEY_1 or k == KEY_2:
			_perk_slot = 0 if k == KEY_1 else 1
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			_act_perk()
		elif k == KEY_ESCAPE or k == KEY_E or k == KEY_BACKSPACE:
			close()
		get_viewport().set_input_as_handled()
		return
	if _page == 1:
		var n := _supply_kinds().size()
		var step := 0
		if k == KEY_LEFT or k == KEY_A:
			step = -1
		elif k == KEY_RIGHT or k == KEY_D:
			step = 1
		elif k == KEY_UP or k == KEY_W:
			step = -COLS
		elif k == KEY_DOWN or k == KEY_S:
			step = COLS
		if step != 0 and _sup_sel + step >= 0 and _sup_sel + step < n:
			_sup_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			_buy_selected_supply()
		elif k == KEY_ESCAPE or k == KEY_E or k == KEY_BACKSPACE:
			close()
		get_viewport().set_input_as_handled()
		return
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
		"reward":
			_say("Defeat the Leech to unlock it.", UiTheme.BP_MUTED)
		"up_ok":
			_say("%s upgraded to tier %d." % [name, Scrap.level_of(w)], UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"up_poor":
			_say("Not enough scrap (%d needed)." % Scrap.tier_cost(String(Weapons.base_def(w).key), Scrap.level_of(w) + 1), UiTheme.DANGER)
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
	for pi in _page_btns.size():
		_page_btns[pi].set_pressed_no_signal(pi == _page)
	_arms_body.visible = _page == 0
	_sup_body.visible = _page == 1
	_perk_body.visible = _page == 2
	_look_body.visible = _page == 3
	if _page == 3:
		_refresh_look()
		_card.reset_size()
		return
	if _page == 2:
		_refresh_perks()
		_card.reset_size()
		return
	if _page == 1:
		_refresh_supplies()
		_card.reset_size()
		return
	for i in _tiles.size():
		_refresh_tile(_tiles[i] as Tile, i == _sel)
	_refresh_detail(int(LIST[_sel]))

func _refresh_supplies() -> void:
	var kinds := _supply_kinds()
	for i in _sup_tiles.size():
		var t := _sup_tiles[i] as SupplyTile
		var sel := i == _sup_sel
		var sbox := UiTheme.tile_box("selected") if sel else UiTheme.tile_box("normal")
		t.add_theme_stylebox_override("normal", sbox)
		t.add_theme_stylebox_override("pressed", sbox)
		t.add_theme_stylebox_override("focus", sbox)
		var k := String(kinds[i])
		var have := Arsenal.get_throwable(k)
		var price := Throwables.price_of(k)
		(t.icon_node as ItemIcon).set_item(k, Color.WHITE if have > 0 or Scrap.bank >= price else Color(0.6, 0.64, 0.68))
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.BP_TEXT)
		t.price_label.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)
		t.bar.have = have
		t.bar.queue_redraw()
	var k2 := String(kinds[_sup_sel])
	var d: Dictionary = Throwables.KINDS[k2]
	var have2 := Arsenal.get_throwable(k2)
	var maxn := int(d["max"])
	_s_icon.set_item(k2, Color.WHITE)
	_s_title.text = String(d["name"])
	var mode: String = {"throw": "Throwable", "place": "Placed", "use": "Tool"}[String(d["mode"])]
	_s_tag.text = "%s  ·  %s" % [String(d["full"]), mode]
	for ch in _s_stats.get_children():
		_s_stats.remove_child(ch)
		ch.free()
	var rows: Array = [["Carried", "%d / %d" % [have2, maxn]], ["Issued free", "%d per mission" % int(d["issue"]) if int(d["issue"]) > 0 else "—"]]
	if d.has("noise"):
		rows.append(["Noise", "%.0f" % float(d["noise"])])
	elif k2 in ["frag", "charge"]:
		rows.append(["Noise", "explosion"])
	for r in rows:
		_s_stats.add_child(UiTheme.label(String(r[0]), 9, UiTheme.BP_MUTED))
		_s_stats.add_child(UiTheme.label(String(r[1]), 9, UiTheme.BP_TEXT))
		_s_stats.add_child(Control.new())
	_s_text.text = String(d["note"])
	var price2 := Throwables.price_of(k2)
	_s_action.disabled = have2 >= maxn or not Scrap.enabled()
	if not Scrap.enabled():
		_s_action.text = "No scrap in this mode"
	elif have2 >= maxn:
		_s_action.text = "The squad is carrying the maximum"
	else:
		_s_action.text = "Buy +1  ·  %d scrap" % price2

func _on_supply_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"ok":
			_say("%s bought — the squad now carries %d." % [nm, Arsenal.get_throwable(kind)], UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say("Not enough scrap (%d needed)." % Throwables.price_of(kind), UiTheme.DANGER)
		"full":
			_say("The squad cannot carry more %s." % nm, UiTheme.BP_MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _refresh_tile(t: Tile, selected: bool) -> void:
	var w := t.weapon
	var sbox := UiTheme.tile_box("selected") if selected else UiTheme.tile_box("normal")
	t.add_theme_stylebox_override("normal", sbox)
	t.add_theme_stylebox_override("pressed", sbox)
	t.add_theme_stylebox_override("focus", sbox)
	var unlocked := Scrap.is_unlocked(w)
	var later := Scrap.is_later(w)
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
		t.state_label.text = "BOSS REWARD" if Scrap.is_gated(w) else "LATER ZONE"
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
			var tail := "installed" if state == 0 else "%d" % Scrap.tier_cost(String(base.key), i)
			var l := UiTheme.label("T%d  %s — %s  [%s]" % [i, t["name"], t["desc"], tail], 8, col)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(DETAIL_W, 0)
			_d_tiers.add_child(l)
	var notes: Array = Codex.WEAPON_TEXT.get(String(base.key), ["", ""])
	_d_text.text = String(notes[0])
	# przycisk akcji
	if not unlocked and Scrap.is_later(w):
		_action.text = "Reward for the Leech" if Scrap.is_gated(w) else "Available in a later zone"
	elif not unlocked:
		_action.text = "Buy  ·  %d scrap" % Scrap.price_of(w)
	elif can_next:
		_action.text = "Upgrade to tier %d  ·  %d scrap" % [next_lv, Scrap.tier_cost(String(base.key), next_lv)]
	else:
		_action.text = "Fully upgraded"
	_card.reset_size()

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.BP_LINE, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
