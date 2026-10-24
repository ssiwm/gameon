extends Control
const Controller := preload("res://scripts/weapon_controller.gd")
## Wspólny panel siedmiu stanowisk: broń i części, konserwacja, prasa, pirotechnika, pracownia, tokarka oraz szafki.
## Lista broni odpowiada operacjom stanowiska; szczegóły porównują bieżący montaż z podglądem i pokazują pracę drużyny.
## Odblokowania i złom są wspólne, montaż prywatny; zakupy i dostawy rozstrzyga serwer (scrap.gd).
## Otwiera go workshop.gd ([E] przy ławie). Na czas panelu akcje gry są wycięte z InputMap (Settings.block_game_input), więc panel
## czyta własne akcje menu z rejestru (actions.gd: menu_left/right/up/down, menu_accept, menu_back, menu_tab, menu_slot_1/2 —
## klawiatura i D-pad / A / B / RB). Mysz: kafel wybiera, przycisk kupuje.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const PerkIcon := preload("res://scripts/perk_icon.gd")
const Perks := preload("res://scripts/perks.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Actions := preload("res://scripts/actions.gd")
const Ammo := preload("res://scripts/ammo.gd")

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
		if UiTheme.hd_on():
			draw_circle(Vector2(4, 4), 4.0, dark)
			draw_circle(Vector2(4, 4), 3.2, gold)
			draw_arc(Vector2(4, 4), 2.1, 0.0, TAU, 20, dark, 0.8, true)
			draw_arc(Vector2(4, 4), 2.9, PI * 1.1, PI * 1.6, 8, Color(1, 0.95, 0.7), 0.9, true)
			return
		draw_rect(Rect2(2, 0, 4, 8), dark)
		draw_rect(Rect2(0, 2, 8, 4), dark)
		draw_rect(Rect2(2, 1, 4, 6), gold)
		draw_rect(Rect2(1, 2, 6, 4), gold)
		draw_rect(Rect2(3, 2, 2, 4), dark)

## Trzy kwadraciki poziomu ulepszeń.
class TierBar extends Control:
	var level := 0                ## odblokowane części broni
	var total := 3                ## wszystkie części broni (parts.gd)
	var maxed := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 7)
	func _draw() -> void:
		for i in total:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < level:
				var fc := Color(0.45, 1.0, 0.55) if maxed else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(0.5, 0.66, 0.7, 0.8), false)
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
				var fc := Color(0.45, 1.0, 0.55) if have >= maxn else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(0.5, 0.66, 0.7, 0.8), false)
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
		if UiTheme.hd_on():
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9), true)
			if frac > 0.0:
				UiTheme.pill(self, Rect2(1, 1, maxf(size.y - 2.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0), true)
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(0.5, 0.66, 0.7, 0.8), false)
			return
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

## Podgląd postaci 3D na żywo (gdy gra używa modeli 3D): ten sam render co w misji, ale w pełnej jakości (MSAA, cienie, rim, `ss` do 16)
## i na stole obrotowym — widać plecak, kieszenie, szwy i twarz. Z zakładką LOOK w warsztacie i (później) z lobby.
class Look3DView extends Control:
	var code := 0
	var _c3d: Node2D
	var _holder: Node2D
	var _t := 0.0
	var _name := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		custom_minimum_size = Vector2(0, 190)

	func _ready() -> void:
		_holder = Node2D.new()
		add_child(_holder)
		resized.connect(_layout)
		_layout()

	## Postać (22 j. świata) zajmuje ~92% wysokości kontrolki; `ss` renderu dobrany do rozmiaru na ekranie (tekstura ≥ 1 px na piksel).
	func _layout() -> void:
		if _holder == null:
			return
		var k := size.y * 0.92 / 22.0
		_holder.scale = Vector2(k, k)
		_holder.position = Vector2(size.x * 0.5, size.y * 0.97)

	func _want_ss() -> int:
		var px_per_unit := get_global_transform().get_scale().x * float(get_window().size.y) / 360.0
		var k := size.y * 0.92 / 22.0
		return clampi(int(ceil(k * px_per_unit)), 6, 16)

	func set_code(c: int) -> void:
		code = c
		var nm := Char3D.char_name_for(Look.gender_id(c), Look.outfit_id(c))
		if _c3d == null:
			_c3d = Char3D.new()
			_c3d.preview = true
			_c3d.preview_ss = _want_ss()
			_holder.add_child(_c3d)
			if not _c3d.setup(nm):
				_c3d.queue_free()
				_c3d = null
				return
			_name = nm
		elif nm != _name:
			_c3d.set_look(nm)
			_name = nm
		_c3d.set_palette(Look.palette_of(c))

	func _process(delta: float) -> void:
		if _c3d == null or not is_visible_in_tree():
			return
		_t += delta
		_c3d.set_view_yaw(fmod(_t * 28.0, 360.0))
		_c3d.update(delta, "idle", 1.0, Vector2(1.0, 0.0), 0.0, true, Color.WHITE)

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
var _page := 0                        ## 0 = ARMS (bronie i ulepszenia), 1 = SUPPLIES (granaty, miny, narzędzia), 2 = PERKS, 3 = LOOK
var _mode := "bench"                  ## „bench" — ława (ARMS, SUPPLIES), „locker" — szafki osobiste (PERKS, LOOK); od 1.7.349, WORKSHOP_PLAN.md W1
## „service" — stół konserwacji (od 1.7.350, W2): zakładka ARMS bez części i zestawów, tylko czyszczenie i części eksploatacyjne broni
## „press" — prasa elaboracyjna (od 1.7.354, W4): zakładka SUPPLIES z samą amunicją specjalną, zamówienia zamiast zakupu (Scrap.request_order)
## „pyro" — stół pirotechniczny (od 1.7.355, W4b): granaty, miny, ładunki i naboje 40 mm, klawisze 1 / 2 zmieniają zapalnik (ustawienie drużyny)
## „lab" — pracownia elektroniki i próbek (od 1.7.357, W6a): zakładka ARMS z samymi częściami broni specjalnych do zbadania (Scrap.request_research)
## „lathe" — tokarka i szlifierka (od 1.7.358, W6b): części broni specjalnych ze schematów (Scrap.request_machining) i ostrzenie broni białej
const MODE_PAGES := {"bench": [0, 1], "locker": [2, 3], "service": [0], "press": [1], "pyro": [1], "lab": [0], "lathe": [0]}
const MODE_GROUP := {"bench": "workshop", "locker": "locker_station", "service": "service_bench", "press": "press_bench", "pyro": "pyro_bench", "lab": "lab_bench",
	"lathe": "lathe_bench"}      ## grupa stanowiska: panel zamyka się, gdy gracz od niego odejdzie
const SERVICE_IDS := ["clean", "barrel", "springs"]
var _title: Label
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
var _look_pal := 0                          ## wybrana paleta kolorów (Look.PALETTES) w zakładce LOOK
var _pal_row: HBoxContainer
var _pal_btns: Array = []
var _look_tiles: Array = []
var _l_view: Control                  ## LookView (arkusz 2D)
var _l_view3: Control                 ## Look3DView (model 3D na żywo) — tworzony przy pierwszym użyciu
var _l_box: VBoxContainer
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
var _remembered: Dictionary = {}      ## osobny wybór broni dla każdego stanowiska
var _claiming := false
var _sel := 0
var _opt := 0                         ## kursor części w szczegółach broni (indeks w `_options`): klawisze 1 / 2 albo kliknięcie wiersza
var _clean_w := -1                    ## broń czyszczona teraz przy ławie (-1 — żadna); od 1.7.347 czyszczenie kosztuje czas, nie złom
var _clean_t := 0.0                   ## s od początku czyszczenia
var _clean_total := 0.0               ## s potrzebne na całe czyszczenie (Profile.clean_time w chwili startu)
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _card: PanelContainer
var _wallet: Label
var _tiles: Array = []
var _d_stage: Control                 ## ława 3D: wybrana broń z częściami, część spod kursora świeci i wysuwa się z gniazda (gun_stage.gd)
var _d_title: Label
var _d_tag: Label
var _d_stats: GridContainer
var _d_tiers: VBoxContainer
var _d_text: Label
var _action: Button
var _msg: Label
var _hint: Label
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
	_title = UiTheme.heading("WORKSHOP", 16, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
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
	root.add_child(_scroll_body(body))
	_arms_body = body
	_sup_body = _build_supplies()
	root.add_child(_scroll_body(_sup_body))
	_sup_body.get_parent().visible = false
	_sup_body.visible = false
	_perk_body = _build_perks()
	root.add_child(_scroll_body(_perk_body))
	_perk_body.get_parent().visible = false
	_perk_body.visible = false
	_look_body = _build_look()
	root.add_child(_scroll_body(_look_body))
	_look_body.get_parent().visible = false
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
	# Główna akcja zawsze pod ręką; przewija się treść, nie przycisk zakupu/montażu/odbioru.
	_action.reparent(root)
	_s_action.reparent(root)
	_s_action.visible = false
	root.add_child(_rule())
	_msg = UiTheme.label("", 9, UiTheme.BP_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_msg)
	_hint = UiTheme.label(_controls_hint(), 8, UiTheme.BP_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_hint)
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)
	Scrap.supply_result.connect(_on_supply_result)
	Scrap.part_result.connect(_on_part_result)
	Scrap.service_result.connect(_on_service_result)
	Scrap.order_result.connect(_on_order_result)
	Scrap.research_result.connect(_on_research_result)
	Scrap.machining_result.connect(_on_machining_result)
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
	t.bar.maxn = Throwables.units(kd, int(data["max"]))        # amunicja: w pudełkach
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
	var lv := LookView.new()                              # podgląd 2D z arkusza; model 3D na żywo dochodzi w _refresh_look (Sprites.char3d bywa ustawione później)
	lv.anim = "run"
	lv.custom_minimum_size = Vector2(0, 150)
	_l_view = lv
	_l_box = v
	v.add_child(_l_view)
	_l_title = UiTheme.heading("", 16, UiTheme.ACCENT)
	v.add_child(_l_title)
	_l_tag = UiTheme.label("", 8, UiTheme.BP_MUTED)
	v.add_child(_l_tag)
	_pal_row = HBoxContainer.new()                       # paleta kolorów stroju: tylko dla modeli 3D
	_pal_row.add_theme_constant_override("separation", 5)
	_pal_row.add_child(UiTheme.label("COLOR", 8, UiTheme.BP_MUTED))
	for pi in Look.PALETTES.size():
		var pb := Button.new()
		pb.focus_mode = Control.FOCUS_NONE
		pb.custom_minimum_size = Vector2(20, 14)
		pb.tooltip_text = Look.palette_name(pi)
		pb.pressed.connect(_select_palette.bind(pi))
		_pal_row.add_child(pb)
		_pal_btns.append(pb)
	_pal_row.visible = false
	v.add_child(_pal_row)
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

func _select_palette(pi: int) -> void:
	_look_pal = pi
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select_look(i: int) -> void:
	_look_sel = i
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _act_look() -> void:
	var c := Look.with_palette(_look_code(_look_sel), _look_pal)
	if Profile.look == c:
		_say(tr("Already wearing %s.") % Look.display_name(c), UiTheme.BP_MUTED)
	elif Profile.set_look(c):
		Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		_say(tr("%s (%s) equipped.") % [Look.display_name(c), Look.gender_id(c)], UiTheme.OK)
	else:
		_say(tr("Unlocks at level %d.") % Look.unlock_level(c), UiTheme.DANGER)

func _refresh_look() -> void:
	var lvl := Profile.level()
	var use3d := Sprites.char3d and Char3D.available()
	if use3d and _l_view3 == null:
		_l_view3 = Look3DView.new()
		_l_box.add_child(_l_view3)
		_l_box.move_child(_l_view3, _l_view.get_index())
	_l_view.visible = not use3d
	if _l_view3 != null:
		_l_view3.visible = use3d
	_pal_row.visible = use3d
	var vw: Control = _l_view3 if use3d else _l_view
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
		var worn := Look.base(Profile.look) == t.code
		t.state_label.text = ("EQUIPPED" if worn else "AVAILABLE") if ok else "LV %d" % Look.unlock_level(t.code)
		t.state_label.add_theme_color_override("font_color", UiTheme.OK if worn else (UiTheme.BP_MUTED if ok else UiTheme.DANGER))
	for pi in _pal_btns.size():
		var pb := _pal_btns[pi] as Button
		var d: Dictionary = Look.PALETTES[pi]
		var pbox := StyleBoxFlat.new()
		pbox.bg_color = (d["swatch"] as Color) if lvl >= int(d["level"]) else (d["swatch"] as Color).darkened(0.65)
		pbox.border_color = UiTheme.ACCENT if pi == _look_pal else Color(1, 1, 1, 0.18)
		pbox.set_border_width_all(2 if pi == _look_pal else 1)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			pb.add_theme_stylebox_override(st, pbox)
	var c := Look.with_palette(_look_code(_look_sel), _look_pal)
	vw.call("set_code", c)
	vw.modulate = Color.WHITE if Look.is_unlocked(c, lvl) else Color(0.35, 0.4, 0.45)
	_l_title.text = Look.display_name(c)
	_l_tag.text = tr("%s  ·  unlocks at level %d") % [Look.gender_id(c).to_upper(), Look.unlock_level(c)]
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
		_say(tr("%s removed.") % Perks.display_name(id), UiTheme.BP_MUTED)
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		return
	if not Profile.is_unlocked(id):
		_say(tr("Reach level %d to unlock %s.") % [Perks.unlock_level(id), Perks.display_name(id)], UiTheme.BP_MUTED)
		return
	if _perk_slot >= Profile.slots():
		_say(tr("Slot %d unlocks at level %d.") % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])], UiTheme.BP_MUTED)
		return
	if Profile.equip(_perk_slot, id):
		_say(tr("%s equipped in slot %d.") % [Perks.display_name(id), _perk_slot + 1], UiTheme.OK)
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
			t.state_label.text = tr("EQUIPPED  ·  SLOT %d") % (at + 1)
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
	_p_tag.text = tr("Perk  ·  unlocks at level %d") % int(d["level"])
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
		_p_action.text = tr("Remove from slot %d") % (at2 + 1)
		_p_action.disabled = false
	elif not unlocked2:
		_p_action.text = tr("Locked  ·  reach level %d") % int(d["level"])
		_p_action.disabled = true
	elif _perk_slot >= Profile.slots():
		_p_action.text = tr("Slot %d unlocks at level %d") % [_perk_slot + 1, int(Profile.SLOT_LEVELS[_perk_slot])]
		_p_action.disabled = true
	else:
		_p_action.text = tr("Equip in slot %d") % (_perk_slot + 1)
		_p_action.disabled = false

func _select_supply(i: int) -> void:
	if i != _sup_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sup_sel = i
	_refresh()

func _buy_selected_supply() -> void:
	var k := String(_supply_kinds()[_sup_sel])
	if int(Scrap.deliveries.get(k, 0)) > 0:
		_claiming = true
		Scrap.request_claim(k)
	elif Throwables.is_ammo(k):
		_claiming = false
		Scrap.request_order(k)                                   # amunicja: zamówienie w prasie (gotowe po misji)
	else:
		Scrap.request_buy_supply(k)

## Indeksy kafli zaopatrzenia (w _supply_kinds) widoczne w tym trybie: ława — przedmioty, prasa — amunicja specjalna.
func _sup_list() -> Array:
	var out: Array = []
	var kinds := _supply_kinds()
	for i in kinds.size():
		if _sup_in_mode(String(kinds[i])):
			out.append(i)
	return out

## Czy rodzaj `k` należy do stanowiska: prasa — amunicja specjalna bez 40 mm, pirotechnika — granaty, miny, ładunki i 40 mm, ława — narzędzia.
func _sup_in_mode(k: String) -> bool:
	var m := String(Throwables.KINDS[k]["mode"])
	var forty := Throwables.is_ammo(k) and String(Ammo.from_kind(k).get("cal", "")) == "40mm"
	match _mode:
		"press":
			return Throwables.is_ammo(k) and not forty
		"pyro":
			return m == "throw" or m == "place" or forty
		_:
			return m == "use"

## Stół pirotechniczny: krótszy (−1) albo dłuższy (+1) zapalnik zaznaczonego przedmiotu — dla całej drużyny (serwer).
func _step_fuse(d: int) -> void:
	var k := String(_supply_kinds()[_sup_sel])
	var opts: Array = Throwables.FUSES.get(k, []) as Array
	if opts.is_empty():
		return
	var ni := clampi(Scrap.fuse_index(k) + d, 0, opts.size() - 1)
	if ni == Scrap.fuse_index(k):
		return
	Scrap.request_fuse(k, ni)
	Audio.play("ui_click", Audio.BUS_UI, -10.0, 1.2)
	_say(tr("%s fuse: %.1f s — for the whole squad.") % [String(Throwables.KINDS[k]["name"]), float(opts[ni])], UiTheme.OK)
	_refresh()

## Cena kafla: przedmiot — sklep ławy, amunicja — partia w prasie.
func _sup_price(k: String) -> int:
	return Scrap.press_price(k) if Throwables.is_ammo(k) else Throwables.price_of(k)

func _on_order_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s collected. Remaining delivery: %d rounds.") % [nm, int(Scrap.deliveries.get(kind, 0))] if _claiming else tr("%s ordered — ready after the next mission (%d / %d batches in the press).") % [nm, Scrap.orders.size(), Scrap.PRESS_SLOTS], UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % Scrap.press_price(kind), UiTheme.DANGER)
		"busy":
			_say(tr("The press is full — %d batches per mission.") % Scrap.PRESS_SLOTS, UiTheme.BP_MUTED)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.BP_MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Rodzaje do kupienia (z ceną) w kolejności karuzeli: przedmioty, potem amunicja specjalna.
func _supply_kinds() -> Array:
	var out: Array = []
	for k in Throwables.SHOP_ORDER:
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

## Długie porównania i kolejki pozostają dostępne także w bazowej rozdzielczości 640×360.
func _scroll_body(body: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(TILE_W * COLS + DETAIL_W + 36.0, 250.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return scroll

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
	_d_stage = GunStage.new()
	_d_stage.custom_minimum_size = Vector2(0, 76)
	v.add_child(_d_stage)
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

## `mode`: „bench" — ława warsztatu (bronie, części, zaopatrzenie), „locker" — szafki osobiste (perki, wygląd). Zakładki spoza trybu są ukryte.
func open(mode := "bench") -> void:
	if _open:
		return
	_open = true
	visible = true
	_mode = mode if MODE_PAGES.has(mode) else "bench"
	_title.text = {"locker": tr("LOCKER"), "service": tr("MAINTENANCE"), "press": tr("RELOADING PRESS"), "pyro": tr("PYROTECHNICS"), "lab": tr("LAB"), "lathe": tr("LATHE")}.get(_mode, tr("WORKSHOP"))
	for pi in _page_btns.size():
		(_page_btns[pi] as Button).visible = (MODE_PAGES[_mode] as Array).has(pi) and (MODE_PAGES[_mode] as Array).size() > 1
	_msg.text = ""
	_hint.text = _controls_hint()
	_sel = _initial_selection()
	_opt = _first_part_opt()
	_page = int((MODE_PAGES[_mode] as Array)[0])
	var allowed := _sup_list()
	if not allowed.has(_sup_sel) and not allowed.is_empty():
		_sup_sel = int(allowed[0])
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE            # w grze celownik zastępuje kursor; panel potrzebuje myszy
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()

func close() -> void:
	if not _open:
		return
	_remembered[_mode] = _sel
	_stop_clean()
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
	# panel zamyka się, gdy gracz odejdzie od ławy / zginie / misja się zmieni (przerwane czyszczenie trzeba zacząć od nowa)
	var wk := get_tree().get_first_node_in_group(String(MODE_GROUP[_mode]))
	if wk == null or not wk.local_in_range or not NoiseMgr.safe_zone:
		close()
		return
	tick_clean(delta)
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		(body.get_parent() as ScrollContainer).custom_minimum_size.y = clampf(size.y - 132.0, 150.0, 520.0)
	_card.position = ((size - _card.size) * 0.5).round()

func _exit_tree() -> void:
	if _open:
		Settings.block_game_input(false)
		Input.mouse_mode = _prev_mouse

# ---------------------------------------------------------------- sterowanie

## Linia sterowania pod panelem: klawisze z rejestru akcji, a gdy jest pad — jego przyciski.
func _controls_hint() -> String:
	var pad := Actions.pad_mode
	var nav := "D-PAD" if pad else Actions.cluster(["menu_up", "menu_left", "menu_down", "menu_right"]).to_upper()
	if _mode == "lathe":
		return tr("%s select   ·   %s / %s job   ·   %s machine / sharpen   ·   %s close   ·   or click") % [
			nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_back", pad)]
	if _mode == "lab":
		return tr("%s select   ·   %s / %s part   ·   %s research   ·   %s close   ·   or click") % [
			nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_back", pad)]
	if _mode == "press":
		return tr("%s select   ·   %s order a batch   ·   %s close   ·   or click") % [nav, _menu_key("menu_accept", pad), _menu_key("menu_back", pad)]
	if _mode == "pyro":
		return tr("%s select   ·   %s / %s fuse   ·   %s buy / order   ·   %s close   ·   or click") % [
			nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_back", pad)]
	if _mode == "service":
		return tr("%s select   ·   %s / %s job   ·   %s clean / replace   ·   %s close   ·   or click") % [
			nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_back", pad)]
	if _mode == "locker":
		return tr("%s select   ·   %s / %s perk slot   ·   %s equip   ·   %s perks / look   ·   %s close   ·   or click") % [
			nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_tab", pad), _menu_key("menu_back", pad)]
	return tr("%s select   ·   %s / %s part   ·   %s buy / fit   ·   %s save set   ·   %s arms / supplies   ·   %s close   ·   or click") % [
		nav, _menu_key("menu_slot_1", pad), _menu_key("menu_slot_2", pad), _menu_key("menu_accept", pad), _menu_key("menu_alt", pad), _menu_key("menu_tab", pad), _menu_key("menu_back", pad)]

func _menu_key(id: String, pad: bool) -> String:
	return Actions.text(id, true, Actions.DEV_PAD if pad else Actions.DEV_KEY).to_upper()

## Krok zaznaczenia z akcji menu (strzałki / WASD / D-pad): ±1 w poziomie, ±COLS w pionie, 0 = to nie nawigacja.
func _nav_step(event: InputEvent) -> int:
	if event.is_action_pressed("menu_left"):
		return -1
	if event.is_action_pressed("menu_right"):
		return 1
	if event.is_action_pressed("menu_up"):
		return -COLS
	if event.is_action_pressed("menu_down"):
		return COLS
	return 0

func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("menu_tab"):
		var pages: Array = MODE_PAGES[_mode]
		_set_page(int(pages[(pages.find(_page) + 1) % pages.size()]))
		get_viewport().set_input_as_handled()
		return
	var step := _nav_step(event)
	var accept := event.is_action_pressed("menu_accept")
	var back := event.is_action_pressed("menu_back")
	if _page == 3:
		if step != 0 and _look_sel + step >= 0 and _look_sel + step < Look.GENDERS.size() * Look.OUTFITS.size():
			_look_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_look()
		elif back:
			close()
	elif _page == 2:
		if step != 0 and _perk_sel + step >= 0 and _perk_sel + step < Perks.ORDER.size():
			_perk_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
			_perk_slot = 0 if event.is_action_pressed("menu_slot_1") else 1
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_perk()
		elif back:
			close()
	elif _page == 1:
		var vis := _sup_list()
		var np := vis.find(_sup_sel) + step
		if step != 0 and np >= 0 and np < vis.size():
			_sup_sel = int(vis[np])
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif _mode == "pyro" and (event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2")):
			_step_fuse(-1 if event.is_action_pressed("menu_slot_1") else 1)
		elif accept:
			_buy_selected_supply()
		elif back:
			close()
	elif step != 0:
		_move(step)
	elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
		_move_opt(-1 if event.is_action_pressed("menu_slot_1") else 1)
	elif event.is_action_pressed("menu_alt"):
		_save_preset()
	elif accept:
		_act()
	elif back:
		close()
	get_viewport().set_input_as_handled()

## Opcje części broni `w` w kolejności gniazd: [{slot, id}] — id "" to element fabryczny gniazda. Na końcu „SERVICE / clean”: czyszczenie
## broni przy ławie (etap 4a GUNSMITH_PLAN — stan techniczny), gdy broń jest kupiona, strzela i niezawodność nie jest wyłączona.
func _options(w: int) -> Array:
	var key := String(Weapons.def(w).key)
	var out: Array = []
	if _mode == "lathe":
		if Scrap.is_unlocked(w) and Weapons.def(w).is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "sharpen"})        # szlifierka: ostrze broni białej
		elif key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "lab":
		if key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "service":
		var d := Weapons.def(w)
		if Scrap.is_unlocked(w) and not d.is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "clean"})
			if d.can_jam():                                      # broń na naboje: lufa i sprężyny (energetyczna ma swoje usterki — WeaponDef.fault)
				out.append({"slot": "service", "id": "barrel"})
				out.append({"slot": "service", "id": "springs"})
		return out
	for s in Parts.slots_of(key):
		out.append({"slot": s, "id": ""})
		for p in Parts.in_slot(key, String(s)):
			out.append({"slot": s, "id": String(p["id"])})
	if Scrap.is_unlocked(w) and not Parts.slots_of(key).is_empty():
		for i in Profile.PRESETS:
			out.append({"slot": "preset", "id": str(i)})       # zestawy części gracza (WORKSHOP_PLAN.md U6)
	return out

func _move_opt(d: int) -> void:
	var n := _options(int(LIST[_sel])).size()
	if n == 0:
		return
	_opt = posmod(_opt + d, n)
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()
	_reveal_option()

func _pick_opt(i: int) -> void:
	if i != _opt:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_opt = i
	_refresh()
	_reveal_option()

## Nawigacja klawiszami/padem nie zostawia wybranej operacji poza przewijanym kadrem.
func _reveal_option() -> void:
	var buttons := _d_tiers.get_children().filter(func(c: Node) -> bool: return c is Button)
	if _opt >= 0 and _opt < buttons.size():
		_ensure_arm_option_visible.call_deferred(buttons[_opt])

## Przebudowa części może odłączyć przycisk przed odroczonym przewinięciem fokusu.
func _ensure_arm_option_visible(button: Control) -> void:
	if not is_instance_valid(button) or not is_instance_valid(_arms_body):
		return
	var scroll := _arms_body.get_parent() as ScrollContainer
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)

func _move(d: int) -> void:
	var choices := _arms_list()
	var pos := choices.find(_sel)
	var next := pos + d
	if next < 0 or next >= choices.size():
		return
	var n := int(choices[next])
	if n < 0 or n >= LIST.size():
		return
	_stop_clean()
	_sel = n
	(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
	_opt = _first_part_opt()
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select(i: int) -> void:
	if not _arms_list().has(i):
		return
	if i != _sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
		_stop_clean()
		_sel = i
		(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
		_opt = _first_part_opt()
	_refresh()

## Kursor na pierwszej części (nie na elemencie fabrycznym) — po wyborze broni widać od razu, co można kupić.
## Siatka i nawigacja korzystają z tej samej listy rzeczywistych opcji stanowiska.
func _arms_list() -> Array:
	var out: Array = []
	for i in LIST.size():
		var w := int(LIST[i])
		if _mode == "bench" or _mode == "locker" or not _options(w).is_empty():
			out.append(i)
	return out

func _initial_selection() -> int:
	var choices := _arms_list()
	if choices.is_empty():
		return 0
	var jobs: Array = Scrap.lathe if _mode == "lathe" else (Scrap.research if _mode == "lab" else [])
	if _mode == "lathe" and jobs.is_empty():
		jobs = Scrap.schematics.keys()
	for id in jobs:
		var w := Weapons.index_of(String(Parts.get_part(String(id)).get("weapon", "")))
		var i := LIST.find(w)
		if choices.has(i):
			return i
	var remembered := int(_remembered.get(_mode, -1))
	if choices.has(remembered):
		return remembered
	var controller := _local_wc()
	if controller != null:
		var i := LIST.find(controller.cur().id)
		if choices.has(i):
			return i
	for i in choices:
		if Scrap.is_unlocked(int(LIST[int(i)])):
			return int(i)
	return int(choices[0])

## Stan wspólnej pracy, także gdy panel pokazuje inną broń.
func _queue_summary() -> String:
	var lines: Array[String] = []
	for entry in [[tr("Research"), Scrap.research], [tr("Machining"), Scrap.lathe]]:
		for id in entry[1]:
			lines.append(tr("%s: %s — after a successful mission") % [String(entry[0]), tr(String(Parts.get_part(String(id)).get("name", id)))])
	for id in Scrap.schematics:
		if not Scrap.lathe.has(id):
			lines.append(tr("Schematic: %s — take to the lathe") % tr(String(Parts.get_part(String(id)).get("name", id))))
	for kind in Scrap.orders:
		lines.append(tr("Batch: %s — after a successful mission") % tr(String(Throwables.KINDS[String(kind)]["name"])))
	for kind in Scrap.deliveries:
		var station := tr("PYROTECHNICS") if Scrap.supply_station(String(kind)) == "pyro_bench" else tr("RELOADING PRESS")
		lines.append(tr("Ready: %s · %d rounds — collect at %s") % [tr(String(Throwables.KINDS[String(kind)]["name"])), int(Scrap.deliveries[kind]), station])
	return "\n".join(lines)

## Te same dane broni dla obu kolumn; porównanie nie zakłada naboju standardowego.
func _comparison_rows(d: RefCounted) -> Array:
	var rows: Array = Codex._weapon_stats(d)
	for row in rows:
		if String(row[0]) == "Magazine":
			row[1] = "%d%s" % [d.mag, "+1" if d.chamber else ""]
	if d.uses_ammo():
		rows.append([tr("Shared reserve"), "∞" if d.infinite else "%d" % Arsenal.get_reserve(d.id, d.ammo)])
	rows.append([tr("Draw"), tr("%.2f s") % d.draw_time])
	if not d.is_melee():
		rows.append([tr("Spread"), "±%.2f°" % d.jitter_deg + (" / ±%.2f°" % d.spread_deg if d.pellets > 1 else "")])
		rows.append([tr("Bloom"), "+%.2f° / %.2f°" % [d.bloom_per_shot, d.bloom_max]])
		rows.append([tr("Recoil"), "%.2f / %.2f" % [d.cam_kick, d.recoil]])
		rows.append([tr("Penetration"), "%.2f / %d" % [d.pen, d.pierce]])
		rows.append([tr("Armour bypass"), "%d%%" % int(d.armor_pen * 100.0)])
		rows.append([tr("Heating"), "%.1f%% / %.1f%%" % [d.barrel_heat * 100.0, d.heat_gain * 100.0]])
	return rows

func _first_part_opt() -> int:
	var ops := _options(int(LIST[_sel]))
	for i in ops.size():
		if String(ops[i]["id"]) != "":
			return i
	return 0

## Akcja na wybranej broni: kup broń (zablokowana), a odblokowanej — kup część pod kursorem, zamontuj ją albo wróć do fabrycznej.
func _act() -> void:
	var w: int = LIST[_sel]
	if not Scrap.is_unlocked(w):
		if _mode in ["service", "lab", "lathe"]:
			_say(tr("Buy it at the workshop bench first."), UiTheme.BP_MUTED)
		else:
			Scrap.request_buy(w)
		return
	var ops := _options(w)
	if ops.is_empty():
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	var key := String(Weapons.def(w).key)
	var id := String(o["id"])
	if String(o["slot"]) == "preset":
		var pi := int(o["id"])
		if Profile.preset(key, pi).is_empty():
			_save_preset()
		elif Profile.is_preset_fitted(key, pi):
			_say(tr("Set %d is already fitted.") % (pi + 1), UiTheme.BP_MUTED)
		else:
			var skipped := Profile.load_preset(key, pi)
			Audio.play("ui_confirm", Audio.BUS_UI, -6.0)
			_say((tr("Fitted set %d.") % (pi + 1)) if skipped == 0 else (tr("Fitted set %d — %d parts the squad no longer has stay as they were.") % [pi + 1, skipped]),
				UiTheme.OK if skipped == 0 else UiTheme.BP_MUTED)
			_refresh()
		return
	if String(o["slot"]) == "service" and id in Profile.WEAR_PARTS:
		if Profile.part_wear(key, id) < 0.5:
			_say(tr("Still like new — nothing to replace."), UiTheme.BP_MUTED)
		else:
			Scrap.request_service(w, id)
		return
	if String(o["slot"]) == "service":
		if _clean_w == w:
			_stop_clean()
			_say(tr("Cleaning stopped."), UiTheme.BP_MUTED)
			_refresh()
		elif id == "sharpen" and Profile.sharpen_time(key) <= 0.0:
			_say(tr("Already sharp."), UiTheme.BP_MUTED)
		elif id != "sharpen" and Profile.clean_time(key) <= 0.0:
			_say(tr("Already clean."), UiTheme.BP_MUTED)
		else:
			_start_clean(w)
		return
	if _mode == "lathe" and String(o["slot"]) != "service":
		if Scrap.has_part(id):
			_say(tr("Already made — fit it at the workshop bench."), UiTheme.BP_MUTED)
		elif Scrap.lathe.has(id):
			_say(tr("On the lathe — ready after the next mission."), UiTheme.BP_MUTED)
		elif Scrap.schematics.has(id):
			Scrap.request_machining(id)
		else:
			_say(tr("No schematic — research it at the lab first."), UiTheme.BP_MUTED)
		return
	if _mode == "lab":
		if Scrap.schematics.has(id) or Scrap.lathe.has(id):
			_say(tr("Already researched — make it on the lathe downstairs."), UiTheme.BP_MUTED)
			return
		if Scrap.has_part(id):
			_say(tr("Already known — fit it at the workshop bench."), UiTheme.BP_MUTED)
		elif Scrap.research.has(id):
			_say(tr("Being researched — ready after the next mission."), UiTheme.BP_MUTED)
		else:
			Scrap.request_research(id)
		return
	if id != "" and not Scrap.has_part(id):
		if Scrap.is_lab_part(id) and not Scrap.found.has(id):
			_say(tr("Special-weapon parts are researched at the lab upstairs."), UiTheme.BP_MUTED)
		else:
			Scrap.request_part(id)
	elif Profile.fitted(key, String(o["slot"])) != id:
		Profile.set_fit(key, String(o["slot"]), id)
		Audio.play("ui_confirm", Audio.BUS_UI, -6.0)
		_say(tr("Fitted: %s.") % (tr(Parts.get_part(id)["name"]) if id != "" else tr("factory part")), UiTheme.OK)
		_refresh()

func _on_result(w: int, ok: bool, reason: String) -> void:
	if not _open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s unlocked — take it from the rack.") % name, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			_say(tr("%s is already unlocked.") % name, UiTheme.BP_MUTED)
		"later":
			_say("Not available yet — a later zone.", UiTheme.BP_MUTED)
		"reward":
			_say("Defeat the Leech to unlock it.", UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Zestaw pod kursorem: zapisuje bieżący montaż broni (nadpisuje). Poza wierszem zestawu nic nie robi.
func _save_preset() -> void:
	if _page != 0:
		return
	var w: int = LIST[_sel]
	var ops := _options(w)
	if ops.is_empty():
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	if String(o["slot"]) != "preset":
		return
	Profile.save_preset(String(Weapons.def(w).key), int(o["id"]))
	Audio.play("ui_confirm", Audio.BUS_UI, -6.0)
	_say(tr("Current fit saved as set %d.") % (int(o["id"]) + 1), UiTheme.OK)
	_refresh()

## „1 próbka” / „3 próbki” (badania kosztują 1–3 próbki).
func _samples_text(n: int) -> String:
	return tr("1 sample") if n == 1 else tr("%d samples") % n

## Kontroler broni lokalnego gracza (masa ekwipunku w nagłówku ławy) albo null.
func _local_wc() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p.weapons
	return null

## Krótki opis zestawu: nazwy części (bez fabrycznych), „factory", gdy same fabryczne, „—" dla pustego.
func _preset_summary(key: String, i: int) -> String:
	var p := Profile.preset(key, i)
	if p.is_empty():
		return "—"
	var names: Array = []
	for s in Parts.slots_of(key):
		var id := String(p.get(s, ""))
		if id != "":
			names.append(tr(String(Parts.get_part(id)["name"])))
	var txt := ", ".join(names) if not names.is_empty() else tr("factory")
	return txt if txt.length() <= 30 else txt.substr(0, 29) + "…"

## Czyszczenie przy ławie (stan siedzi w profilu gracza, więc serwer nie bierze udziału): trwa Profile.clean_time, panel musi zostać
## otwarty, a gracz przy ławie — odejście, zmiana broni albo ponowne [E] przerywa i trzeba zacząć od nowa.
func _start_clean(w: int) -> void:
	_clean_w = w
	_clean_t = 0.0
	var melee := Weapons.def(w).is_melee()
	_clean_total = Profile.sharpen_time(String(Weapons.def(w).key)) if melee else Profile.clean_time(String(Weapons.def(w).key))
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -8.0, 0.85)
	_say((tr("Sharpening the %s…") if melee else tr("Stripping the %s…")) % String(Weapons.def(w).name), UiTheme.BP_TEXT)
	_refresh()

func _stop_clean() -> void:
	_clean_w = -1
	_clean_t = 0.0

## Klatka czyszczenia (z `_process`; testy wołają ją ręcznie).
func tick_clean(delta: float) -> void:
	if _clean_w < 0:
		return
	_clean_t += delta
	var ck := String(Weapons.def(_clean_w).key)
	var melee := Weapons.def(_clean_w).is_melee()
	if _clean_t < _clean_total:
		_action.text = (tr("Sharpening…  %d%%  (again to stop)") if melee else tr("Cleaning…  %d%%  (again to stop)")) % int(100.0 * _clean_t / _clean_total)
		if not melee:
			var c0 := Profile.condition(ck)                 # brud schodzi z broni w trakcie (ława 3D)
			(_d_stage as GunStage).set_dirt(1.0 - lerpf(c0, Profile.clean_cap(ck), _clean_t / _clean_total) / 100.0)
		return
	var w := _clean_w
	_stop_clean()
	if melee:
		Profile.sharpen(ck)                                 # szlifierka (W6b)
		_say(tr("%s sharpened — edge 100%%.") % String(Weapons.def(w).name), UiTheme.OK)
		Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.3)
		_refresh()
		return
	Profile.clean(ck)
	_say(tr("%s stripped and cleaned — condition %d%%.") % [String(Weapons.def(w).name), int(Profile.condition(ck))], UiTheme.OK)
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.0)
	_refresh()

func _on_machining_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s on the lathe — ready after the next mission.") % nm, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % Scrap.machine_price(id), UiTheme.DANGER)
		"busy":
			_say(tr("The lathe is busy — %d job per mission.") % Scrap.LATHE_SLOTS, UiTheme.BP_MUTED)
		"noschem":
			_say(tr("No schematic — research it at the lab first."), UiTheme.BP_MUTED)
		"owned":
			_say(tr("Already made."), UiTheme.BP_MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_service_result(w: int, part: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say((tr("New barrel in the %s.") if part == "barrel" else tr("New springs in the %s.")) % String(Weapons.def(w).name), UiTheme.OK)
			Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.1)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % int(Scrap.SERVICE_COST.get(part, 0)), UiTheme.DANGER)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_research_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	var cost := Scrap.research_cost(id)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s: research started — ready after the next mission.") % nm, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"samples":
			_say(tr("Not enough samples (%d needed) — elites and bosses drop them.") % cost.x, UiTheme.DANGER)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % cost.y, UiTheme.DANGER)
		"busy":
			_say(tr("The lab is busy — %d project per mission.") % Scrap.LAB_SLOTS, UiTheme.BP_MUTED)
		"locked":
			_say(tr("Buy the gun at the workshop bench first."), UiTheme.BP_MUTED)
		"owned":
			_say(tr("Already known."), UiTheme.BP_MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.BP_MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_part_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s unlocked for the squad and fitted to your gun.") % nm, UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % Scrap.part_cost(id), UiTheme.DANGER)
		"owned":
			_say(tr("The squad already has %s.") % nm, UiTheme.BP_MUTED)
		"locked":
			_say("Unlock the weapon first.", UiTheme.BP_MUTED)
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
	_action.visible = _page == 0
	_s_action.visible = _page == 1
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		body.get_parent().visible = body.visible
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
	var arms := _arms_list()
	if not arms.is_empty() and not arms.has(_sel):
		_sel = _initial_selection()
	for i in _tiles.size():
		(_tiles[i] as Tile).visible = arms.has(i)
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
		t.visible = _sup_in_mode(k)
		var have := Arsenal.get_throwable(k)
		var price := _sup_price(k)
		t.price_label.text = ("%d" % price) + (("  +%d" % Scrap.ordered(k)) if Scrap.ordered(k) > 0 else "")
		(t.icon_node as ItemIcon).set_item(k, Color.WHITE if have > 0 or Scrap.bank >= price else Color(0.6, 0.64, 0.68))
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.BP_TEXT)
		t.price_label.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)
		t.bar.have = Throwables.units(k, have)
		t.bar.queue_redraw()
	var k2 := String(kinds[_sup_sel])
	var d: Dictionary = Throwables.KINDS[k2]
	var have2 := Arsenal.get_throwable(k2)
	var maxn := int(d["max"])
	_s_icon.set_item(k2, Color.WHITE)
	_s_title.text = String(d["name"])
	var mode: String = {"throw": "Throwable", "place": "Placed", "use": "Tool", "ammo": "Ammunition"}[String(d["mode"])]
	_s_tag.text = "%s  ·  %s" % [String(d["full"]), mode]
	for ch in _s_stats.get_children():
		_s_stats.remove_child(ch)
		ch.free()
	var rows: Array = [["Carried", "%d / %d" % [have2, maxn]], ["Issued free", "%d per mission" % int(d["issue"]) if int(d["issue"]) > 0 else "—"]]
	if Throwables.is_ammo(k2):
		var ct := Ammo.from_kind(k2)
		var users: Array = []
		for wd in Weapons.defs():
			if String(wd.caliber) == String(ct.get("cal", "")):
				users.append(String(wd.name))
		rows = [["Carried", tr("%d / %d rounds") % [have2, maxn]], ["Box", tr("%d rounds") % Throwables.box_of(k2)], ["Fits", ", ".join(users)],
			["In the press", tr("%d of %d batches") % [Scrap.orders.size(), Scrap.PRESS_SLOTS]]]
	elif d.has("noise"):
		rows.append(["Noise", "%.0f" % float(d["noise"])])
	elif k2 in ["frag", "charge"]:
		rows.append(["Noise", "explosion"])
	if Throwables.FUSES.has(k2):
		var fo: Array = Throwables.FUSES[k2]
		var fi := Scrap.fuse_index(k2)
		rows.append(["Fuse", tr("%.1f s  (%d of %d)") % [float(fo[fi]), fi + 1, fo.size()] + ((tr("  ·  %s / %s change") % [_menu_key("menu_slot_1", Actions.pad_mode), _menu_key("menu_slot_2", Actions.pad_mode)]) if _mode == "pyro" else "")])
	for r in rows:
		_s_stats.add_child(UiTheme.label(String(r[0]), 9, UiTheme.BP_MUTED))
		_s_stats.add_child(UiTheme.label(String(r[1]), 9, UiTheme.BP_TEXT))
		_s_stats.add_child(Control.new())
	_s_text.text = tr(String(d["note"]))
	var summary := _queue_summary()
	if summary != "":
		_s_text.text += "\n\n" + summary
	if Throwables.is_ammo(k2):
		_s_text.text += "\n" + tr("[%s] in the field picks the ammo type for the next magazine.") % Actions.key("ammo_type")
	var price2 := _sup_price(k2)
	var queued := Scrap.ordered(k2) * Throwables.box_of(k2) + int(Scrap.deliveries.get(k2, 0))
	_s_action.disabled = have2 + queued >= maxn or not Scrap.enabled()
	if not Scrap.enabled():
		_s_action.text = "No scrap in this mode"
	elif int(Scrap.deliveries.get(k2, 0)) > 0:
		_s_action.disabled = have2 >= maxn
		_s_action.text = tr("Collect ready delivery · %d rounds") % int(Scrap.deliveries[k2])
	elif have2 + queued >= maxn:
		_s_action.text = "The squad is carrying the maximum"
	elif Throwables.is_ammo(k2) and Scrap.orders.size() >= Scrap.PRESS_SLOTS:
		_s_action.text = tr("The press is full — %d batches per mission") % Scrap.PRESS_SLOTS
	elif Throwables.is_ammo(k2):
		_s_action.text = tr("Order a batch  ·  %d scrap  ·  ready after the mission") % price2
	else:
		_s_action.text = (tr("Buy a box  ·  %d scrap") % price2) if Throwables.is_ammo(k2) else (tr("Buy +1  ·  %d scrap") % price2)

func _on_supply_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.BP_MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.BP_MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.BP_MUTED)
		"ok":
			_say(tr("%s bought — the squad now carries %d.") % [nm, Arsenal.get_throwable(kind)], UiTheme.OK)
			Audio.play("ui_confirm", Audio.BUS_UI, -4.0)
		"poor":
			_say(tr("Not enough scrap (%d needed).") % Throwables.price_of(kind), UiTheme.DANGER)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.BP_MUTED)
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
		var total := Parts.of(String(Weapons.def(w).key)).size()
		var owned := Scrap.parts_owned(w)
		t.bar.level = owned
		t.bar.total = total
		t.bar.custom_minimum_size.x = maxf(26.0, total * 9.0 - 2.0)
		t.tooltip_text = tr("Unlocked parts: %d / %d. Equipment is chosen separately.") % [owned, total]
		t.bar.maxed = owned >= total
		t.bar.queue_redraw()
	elif later:
		t.state_label.text = "BOSS REWARD" if Scrap.is_gated(w) else "LATER ZONE"
	else:
		var price := Scrap.price_of(w)
		t.price_label.text = "%d" % price
		t.price_label.add_theme_color_override("font_color", GOLD if Scrap.bank >= price else UiTheme.DANGER)

func _refresh_detail(w: int) -> void:
	var base: RefCounted = Weapons.base_def(w)
	var key := String(base.key)
	var unlocked := Scrap.is_unlocked(w)
	var ops := _options(w)
	_opt = clampi(_opt, 0, maxi(ops.size() - 1, 0))
	var mine := Profile.fit_code(w)
	var controller := _local_wc()
	var ammo_type: int = controller.ammo_of(w) if controller != null else 0
	var cur: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, mine))
	# podgląd: broń z częścią spod kursora zamontowaną w jej gnieździe (reszta jak teraz)
	var preview: RefCounted = null
	var o: Dictionary = ops[_opt] if not ops.is_empty() else {}
	var pv_code := mine
	if unlocked and not o.is_empty():
		var choice := {}
		for s in Parts.slots_of(key):
			choice[s] = Profile.fitted(key, String(s))
		if String(o["slot"]) == "preset":                      # zestaw: cała broń z tym zestawem (części, których drużyna nie ma, zostają jak są)
			var pset := Profile.preset(key, int(o["id"]))
			for s in pset:
				if String(pset[s]) == "" or Scrap.has_part(String(pset[s])):
					choice[s] = String(pset[s])
		else:
			choice[String(o["slot"])] = String(o["id"])
		pv_code = Parts.encode(key, choice)
		if pv_code != mine:
			preview = Weapons.def_build(w, Weapons.build_of(ammo_type, pv_code))
	# na ławie broń już z częścią spod kursora; ona (albo fabryczny element gniazda) świeci i jest wysunięta
	var hl_part := unlocked and not o.is_empty() and String(o["slot"]) != "preset" and String(o["slot"]) != "service"
	var hl_slot := String(o.get("slot", "")) if hl_part else ("barrel" if unlocked and not o.is_empty() and String(o["id"]) == "barrel" else "")
	(_d_stage as GunStage).show_gun(w, Parts.decode(key, pv_code), String(o.get("id", "")) if hl_part else "", hl_slot, not unlocked)
	(_d_stage as GunStage).set_dirt((1.0 - Profile.condition(key) / 100.0) if unlocked and not base.is_melee() else 0.0)   # brud wg stanu broni (W2)
	(_d_stage as GunStage).set_strip(_clean_w == w)
	_d_title.text = String(base.name)
	var tag := Codex._slot_name(base)
	if unlocked and not Parts.of(key).is_empty():
		tag += tr("  ·  UNLOCKED %d / %d") % [Scrap.parts_owned(w), Parts.of(key).size()]
		tag += tr("  ·  FITTED %d") % Parts.decode(key, mine).size()
	elif not unlocked:
		tag += "  ·  LOCKED"
	if unlocked and Profile.kills(key) > 0:
		tag += tr("  ·  KILLS %d") % Profile.kills(key)                    # historia broni (etap 5b)
	if unlocked:
		# wprawa (etap 5a): stopień i punkty do następnego
		var ml := Profile.mastery_level(key)
		var mp := Profile.mastery_points(key)
		if ml < Profile.MASTERY_XP.size() - 1:
			tag += tr("  ·  MASTERY %s  (%d / %d)") % [["0", "I", "II", "III", "IV", "V"][ml], mp, int(Profile.MASTERY_XP[ml + 1])]
		else:
			tag += tr("  ·  MASTERY %s") % ["0", "I", "II", "III", "IV", "V"][ml]
	if _mode == "lab":
		tag += tr("  ·  SAMPLES %d") % Scrap.samples + ((tr(" (+%d this mission)") % Scrap.samples_loot) if Scrap.samples_loot > 0 else "")
	if _mode == "bench" and Settings.realistic_handling:
		var lp := _local_wc()
		if lp != null:
			var km: float = lp.kit_mass()
			tag += tr("  ·  KIT %.1f kg  (run noise %+d%%)") % [km, int(round((lp.mass_noise_mult() - 1.0) * 100.0))]   # masa ekwipunku (W5)
	if cur.uses_ammo():
		tag += tr("  ·  AMMO %s") % Ammo.name_of(String(cur.caliber), ammo_type)
	_d_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_tag.custom_minimum_size.x = DETAIL_W
	_d_tag.text = tag
	var jobs := _queue_summary()
	if jobs != "":
		_d_tag.text += "\n" + jobs
	# statystyki: broń, jaką masz teraz, i ta sama z częścią spod kursora (złote wartości — zmiany względem bieżącego montażu)
	for ch in _d_stats.get_children():
		_d_stats.remove_child(ch)
		ch.free()
	var now_rows: Array = _comparison_rows(cur)
	var next_rows: Array = _comparison_rows(preview) if preview != null else []
	if next_rows.is_empty():
		next_rows = now_rows.duplicate(true)
	if controller != null and (controller.loadout.has(w) or controller.melee_id == w):
		var km: float = controller.kit_mass()
		var next_mass: float = km + (preview.mass - cur.mass if preview != null else 0.0)
		now_rows.append([tr("Kit mass"), tr("%.2f kg") % km])
		next_rows.append([tr("Kit mass"), tr("%.2f kg") % next_mass])
		var speed: float = clampf(1.0 - Controller.MASS_SPEED * (next_mass - Controller.mass_ref()), Controller.MASS_SPEED_RANGE.x, Controller.MASS_SPEED_RANGE.y) if Settings.realistic_handling else 1.0
		var noise: float = clampf(1.0 + Controller.MASS_NOISE * (next_mass - Controller.mass_ref()), Controller.MASS_NOISE_RANGE.x, Controller.MASS_NOISE_RANGE.y) if Settings.realistic_handling else 1.0
		now_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(controller.mass_speed_mult() - 1.0) * 100.0, (controller.mass_noise_mult() - 1.0) * 100.0]])
		next_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(speed - 1.0) * 100.0, (noise - 1.0) * 100.0]])
	for i in now_rows.size():
		var r: Array = now_rows[i]
		# Podgląd części/zestawu zaczyna od rzeczywistych zmian. Pełna karta jest widoczna bez zmiany montażu.
		if preview != null and i < next_rows.size() and String(next_rows[i][1]) == String(r[1]):
			continue
		_d_stats.add_child(UiTheme.label(String(r[0]), 9, UiTheme.BP_MUTED))
		_d_stats.add_child(UiTheme.label(String(r[1]), 9, UiTheme.BP_TEXT))
		var nv := ""
		if i < next_rows.size() and String(next_rows[i][1]) != String(r[1]):
			nv = "» %s" % String(next_rows[i][1])
		_d_stats.add_child(UiTheme.label(nv, 9, GOLD))
	# części w gniazdach: nagłówek gniazda, element fabryczny i części (zamontowana — zielona, odblokowana — jasna, do kupienia — z ceną)
	for ch in _d_tiers.get_children():
		_d_tiers.remove_child(ch)
		ch.queue_free()                  # wiersz może właśnie obsługiwać swoje kliknięcie (_pick_opt) — natychmiastowe free() jest wtedy błędem
	var last_slot := ""
	for i in ops.size():
		var op: Dictionary = ops[i]
		var slot := String(op["slot"])
		if slot != last_slot:
			last_slot = slot
			var head_txt := tr("Service") if slot == "service" else (tr("Sets") if slot == "preset" else tr(Parts.SLOT_NAMES[slot]))
			_d_tiers.add_child(UiTheme.label(head_txt.to_upper(), 7, UiTheme.BP_MUTED))
		if slot == "preset":
			var pi := int(op["id"])
			var pb := Button.new()
			pb.flat = true
			pb.focus_mode = Control.FOCUS_NONE
			pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			pb.add_theme_font_size_override("font_size", 8)
			var pfit := Profile.is_preset_fitted(key, pi)
			pb.add_theme_color_override("font_color", UiTheme.ACCENT if i == _opt else (UiTheme.OK if pfit else UiTheme.BP_TEXT))
			pb.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
			pb.text = "%s %s   [%s]" % ["»" if i == _opt else " ", tr("Set %d  ·  %s") % [pi + 1, _preset_summary(key, pi)],
				tr("empty") if Profile.preset(key, pi).is_empty() else (tr("fitted") if pfit else tr("saved"))]
			pb.custom_minimum_size = Vector2(DETAIL_W, 0)
			for st in ["normal", "hover", "pressed", "focus"]:
				var psb := StyleBoxEmpty.new()
				psb.content_margin_top = 1.0
				psb.content_margin_bottom = 1.0
				pb.add_theme_stylebox_override(st, psb)
			pb.pressed.connect(_pick_opt.bind(i))
			_d_tiers.add_child(pb)
			continue
		if slot == "service":
			var cc := Profile.clean_time(key)
			var sid := String(op["id"])
			var pw := Profile.part_wear(key, sid) if sid != "clean" else 0.0
			var cb := Button.new()
			cb.flat = true
			cb.focus_mode = Control.FOCUS_NONE
			cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cb.add_theme_font_size_override("font_size", 8)
			var due := (cc > 0.0) if sid == "clean" else (pw >= 0.5)
			cb.add_theme_color_override("font_color", UiTheme.ACCENT if i == _opt else (GOLD if due else UiTheme.OK))
			cb.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
			var cap := Profile.clean_cap(key)
			if sid == "sharpen":
				var st := Profile.sharpen_time(key)
				cb.add_theme_color_override("font_color", UiTheme.ACCENT if i == _opt else (GOLD if st > 0.0 else UiTheme.OK))
				cb.text = "%s %s   [%s]" % ["»" if i == _opt else " ", tr("Sharpen  ·  edge %d%%") % int(Profile.edge_of(key)), tr("%d s") % ceili(st) if st > 0.0 else tr("sharp")]
			elif sid == "clean":
				var ctxt := (tr("Clean  ·  condition %d%%") % int(Profile.condition(key))) if cap >= 99.5 else (tr("Clean  ·  condition %d%% (max %d%%)") % [int(Profile.condition(key)), int(cap)])
				cb.text = "%s %s   [%s]" % ["»" if i == _opt else " ", ctxt, tr("%d s") % ceili(cc) if cc > 0.0 else tr("clean")]
			else:
				var pname := tr("Barrel") if sid == "barrel" else tr("Springs")
				cb.text = "%s %s   [%s]" % ["»" if i == _opt else " ", tr("%s  ·  worn %d%%") % [pname, int(pw)], tr("%d scrap") % int(Scrap.SERVICE_COST[sid]) if due else tr("like new")]
			cb.custom_minimum_size = Vector2(DETAIL_W, 0)
			for st in ["normal", "hover", "pressed", "focus"]:
				var csb := StyleBoxEmpty.new()
				csb.content_margin_top = 1.0
				csb.content_margin_bottom = 1.0
				cb.add_theme_stylebox_override(st, csb)
			cb.pressed.connect(_pick_opt.bind(i))
			_d_tiers.add_child(cb)
			continue
		var id := String(op["id"])
		var fitted := Profile.fitted(key, slot) == id
		var owned := id == "" or Scrap.has_part(id)
		var nm := tr("Factory") if id == "" else tr(String(Parts.get_part(id)["name"]))
		var tail := tr("fitted") if fitted else ("" if id == "" else (tr("owned") if owned else (tr("found — extract") if Scrap.found.has(id) else tr("%d scrap") % Scrap.part_cost(id))))
		if id != "" and not owned and not Scrap.found.has(id) and Scrap.is_lab_part(id):
			var rc := Scrap.research_cost(id)
			if Scrap.lathe.has(id):
				tail = tr("on the lathe")
			elif Scrap.schematics.has(id):
				tail = (tr("%d scrap") % Scrap.machine_price(id)) if _mode == "lathe" else tr("schematic")
			elif Scrap.research.has(id):
				tail = tr("researching")
			elif _mode == "lab":
				tail = tr("%s · %d scrap") % [_samples_text(rc.x), rc.y]
			else:
				tail = tr("no schematic") if _mode == "lathe" else tr("lab")
		elif (_mode == "lab" or _mode == "lathe") and owned:
			tail = tr("known") if _mode == "lab" else tr("made")
		var col: Color = UiTheme.OK if fitted else (UiTheme.BP_TEXT if owned else GOLD)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_color_override("font_color", UiTheme.ACCENT if i == _opt else col)
		b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
		b.text = ("%s %s   [%s]" % ["»" if i == _opt else " ", nm, tail]) if tail != "" else ("%s %s" % ["»" if i == _opt else " ", nm])
		b.custom_minimum_size = Vector2(DETAIL_W, 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxEmpty.new()                  # wiersz bez marginesów przycisku — lista części mieści się w karcie
			sb.content_margin_top = 1.0
			sb.content_margin_bottom = 1.0
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(_pick_opt.bind(i))
		_d_tiers.add_child(b)
	var notes: Array = Codex.WEAPON_TEXT.get(key, ["", ""])
	var desc := String(notes[0])
	if unlocked and not o.is_empty() and String(o["slot"]) == "preset":
		desc = tr("Your saved sets of parts for this gun (only yours — the squad shares the unlocks, not the build). %s fits the set, %s saves your current fit over it.") % [
			_menu_key("menu_accept", Actions.pad_mode), _menu_key("menu_alt", Actions.pad_mode)]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "barrel":
		desc = tr("Every shot wears the bore, a hot barrel three times faster. A worn barrel throws the shots wider (at 100%% wear the cone is 60%% wider). A new one costs %d scrap from the squad.") % int(Scrap.SERVICE_COST["barrel"])
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		desc = tr("Every swing dulls the edge a little. A dull blade hurts less — down to %d%% damage when fully blunt. Sharpening costs no scrap, only time at the grinder.") % int(Profile.EDGE_MIN * 100.0)
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "springs":
		desc = tr("Recoil and firing-pin springs tire with every shot. Tired springs feed badly: cleaning can no longer bring the gun back to 100%%, only to 100 − half the spring wear. New springs cost %d scrap.") % int(Scrap.SERVICE_COST["springs"])
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service":
		desc = tr("Strip and clean the gun on the table: condition back to 100% (less with tired springs). It costs no scrap, only time — the dirtier the gun, the longer. Below 70% a gun starts to jam, and every shot wears it — faster with a hot barrel or a suppressor.")
	elif unlocked and not o.is_empty() and String(o["id"]) != "":
		desc = tr(String(Parts.get_part(String(o["id"]))["desc"]))
	elif unlocked and not o.is_empty():
		desc = tr("Factory part: no gain, no cost.")
	_d_text.text = desc
	# przycisk akcji
	if not unlocked and Scrap.is_later(w):
		_action.text = "Reward for the Leech" if Scrap.is_gated(w) else "Available in a later zone"
	elif not unlocked:
		_action.text = tr("Buy it at the workshop bench") if _mode in ["service", "lab", "lathe"] else tr("Buy  ·  %d scrap") % Scrap.price_of(w)
	elif o.is_empty():
		_action.text = tr("Nothing to service") if _mode == "service" else (tr("Nothing to research — not a special weapon") if _mode == "lab" else (tr("Nothing for the lathe") if _mode == "lathe" else "No parts for this weapon"))
	elif String(o["slot"]) == "preset":
		var api := int(o["id"])
		if Profile.preset(key, api).is_empty():
			_action.text = tr("Save current fit as set %d") % (api + 1)
		elif Profile.is_preset_fitted(key, api):
			_action.text = tr("Set %d fitted  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
		else:
			_action.text = tr("Fit set %d  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
	elif String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		var stime := Profile.sharpen_time(key)
		if _clean_w == w:
			_action.text = tr("Sharpening…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
		else:
			_action.text = tr("Sharpen  ·  %d s") % ceili(stime) if stime > 0.0 else tr("Already sharp")
	elif String(o["slot"]) == "service" and String(o["id"]) in Profile.WEAR_PARTS:
		var sid2 := String(o["id"])
		_action.text = (tr("Replace  ·  %d scrap") % int(Scrap.SERVICE_COST[sid2])) if Profile.part_wear(key, sid2) >= 0.5 else tr("Like new")
	elif String(o["slot"]) == "service":
		var ctime := Profile.clean_time(key)
		if _clean_w == w:
			_action.text = tr("Cleaning…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
		else:
			_action.text = tr("Clean  ·  %d s") % ceili(ctime) if ctime > 0.0 else tr("Already clean")
	else:
		var id2 := String(o["id"])
		if _mode == "lathe":
			if Scrap.has_part(id2):
				_action.text = tr("Made  ·  fit it at the bench")
			elif Scrap.lathe.has(id2):
				_action.text = tr("On the lathe  ·  ready after the mission")
			elif not Scrap.schematics.has(id2):
				_action.text = tr("No schematic  ·  research it at the lab")
			elif Scrap.lathe.size() >= Scrap.LATHE_SLOTS:
				_action.text = tr("The lathe is busy  ·  1 job per mission")
			else:
				_action.text = tr("Machine  ·  %d scrap  ·  ready after the mission") % Scrap.machine_price(id2)
		elif _mode == "lab":
			var rc2 := Scrap.research_cost(id2)
			if Scrap.schematics.has(id2) or Scrap.lathe.has(id2):
				_action.text = tr("Researched  ·  make it on the lathe")
			elif Scrap.has_part(id2):
				_action.text = tr("Known  ·  fit it at the bench")
			elif Scrap.research.has(id2):
				_action.text = tr("Researching  ·  ready after the mission")
			elif Scrap.research.size() >= Scrap.LAB_SLOTS:
				_action.text = tr("The lab is busy  ·  1 project per mission")
			else:
				_action.text = tr("Research  ·  %s  ·  %d scrap") % [_samples_text(rc2.x), rc2.y]
		elif id2 != "" and not Scrap.has_part(id2) and Scrap.is_lab_part(id2) and not Scrap.found.has(id2):
			_action.text = tr("Research it at the lab")
		elif id2 != "" and not Scrap.has_part(id2):
			_action.text = tr("Buy part  ·  %d scrap") % Scrap.part_cost(id2)
		elif Profile.fitted(key, String(o["slot"])) == id2:
			_action.text = "Fitted"
		else:
			_action.text = "Fit to my gun" if id2 != "" else "Fit the factory part"
	_card.reset_size()

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.BP_LINE, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
