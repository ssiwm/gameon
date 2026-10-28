extends RefCounted
## Zaopatrzenie: ława (narzędzia), prasa (ST-03 — regał, etykieta partii, matryce) i stół pirotechniczny (ST-04 — skrzynia, karta w wieku, zapalnik, schemat działania).
## Wydzielone z workshop_ui.gd (STATION_CARDS_PLAN.md E1 — podział na widoki stanowisk). Stan panelu (kafle, etykiety, wybór) zostaje
## w workshop_ui.gd, tu jest budowa i wypełnianie; `ui` to panel. workshop_ui woła te funkcje przez funkcje o tych samych nazwach.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Throwables := preload("res://scripts/throwables.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const Actions := preload("res://scripts/actions.gd")
const Ammo := preload("res://scripts/ammo.gd")
const StationNoise := preload("res://scripts/station_noise.gd")
const VuMeter := preload("res://scripts/vu_meter.gd")
const SupplyArt := preload("res://scripts/station_supply_art.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, kafle, etykiety

func _init(panel: Control) -> void:
	ui = panel

## Zakładka SUPPLIES: ten sam układ co ARMS — siatka kafli po lewej (miniatura, nazwa, cena, zapas), szczegóły po prawej.
func _build_supplies() -> HBoxContainer:
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (ui.TILE_H + 6.0))            # tyle co ARMS — karta nie skacze przy przełączaniu
	var grid = GridContainer.new()
	grid.columns = ui.COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	left.add_child(grid)
	# pusty stan: na ławie zostały same narzędzia — reszta zaopatrzenia ma własne stanowiska
	ui._sup_note = UiTheme.label("", 8, UiTheme.MUTED)
	ui._sup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._sup_note.custom_minimum_size.x = ui.TILE_W * ui.COLS + 6.0
	left.add_child(ui._sup_note)
	# prasa (ST-03): regał — półka na kaliber, pudełka na deskach; pod regałem etykieta partii z ząbkiem, matryce w kolumnie po prawej
	ui._shelves = VBoxContainer.new()
	ui._shelves.add_theme_constant_override("separation", 6)
	left.add_child(ui._shelves)
	ui._notch = SupplyArt.Notch.new()
	left.add_child(ui._notch)
	# stół pirotechniczny (ST-04): skrzynia saperska z magazynu Obiektu 86, przegrody 4 × 2, karta w otwartym wieku po prawej
	ui._crate = PanelContainer.new()
	ui._crate.add_theme_stylebox_override("panel", SupplyArt.wood_box(6))
	var cv = VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	ui._crate.add_child(cv)
	var stencil = UiTheme.mono(UiTheme.label("ЯЩИК № 4  ·  ВЗРЫВЧАТЫЕ ВЕЩЕСТВА  ·  НЕ БРОСАТЬ", 8, UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	stencil.add_theme_constant_override("outline_size", 0)
	cv.add_child(stencil)                                # napis na krawędzi skrzyni (sprzęt bunkra — cyrylica, D1a)
	ui._crate_grid = GridContainer.new()
	ui._crate_grid.columns = 4
	ui._crate_grid.add_theme_constant_override("h_separation", 5)
	ui._crate_grid.add_theme_constant_override("v_separation", 5)
	cv.add_child(ui._crate_grid)
	left.add_child(ui._crate)
	var rows = {}
	var kinds = ui._supply_kinds()
	for i in kinds.size():
		var k = String(kinds[i])
		var t = _make_supply_tile(k, i)
		ui._sup_tiles.append(t)
		if _is_press_kind(k):
			var cal = String(Ammo.from_kind(k)["cal"])
			if not rows.has(cal):
				rows[cal] = _make_shelf(cal)
			(rows[cal] as Control).get_meta("boxes").add_child(t)
		elif _is_pyro_kind(k):
			ui._crate_grid.add_child(t)
		else:
			grid.add_child(t)
	ui._sup_grid = grid
	ui._sup_left = left
	ui._lid = PanelContainer.new()                          # wieko skrzyni wokół karty (pirotechnika); gdzie indziej bez ramki
	ui._lid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui._sup_paper = ui._paper(_build_supply_detail())
	ui._lid.add_child(ui._sup_paper)
	body.add_child(ui._lid)
	ui._dies = PanelContainer.new()                         # prasa: matryce (miejsca na partie) pionowo po prawej
	ui._dies.add_theme_stylebox_override("panel", UiTheme.panel_box())
	ui._dies.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui._dies_list = VBoxContainer.new()
	ui._dies_list.add_theme_constant_override("separation", 6)
	ui._dies_list.custom_minimum_size.x = 104
	ui._dies.add_child(ui._dies_list)
	body.add_child(ui._dies)
	return body

## Półka regału prasy dla kalibru `cal`: podpis kalibru nad półką, rząd pudełek, deska pod spodem.
func _make_shelf(cal: String) -> Control:
	var shelf = VBoxContainer.new()
	shelf.add_theme_constant_override("separation", 0)
	var cap = UiTheme.mono(UiTheme.label(String(Ammo.CALIBERS.get(cal, {}).get("name", cal)), 8, UiTheme.BONE_DIM))      # kaliber nad półką
	shelf.add_child(cap)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	shelf.add_child(row)
	var boxes = HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 4)
	row.add_child(boxes)
	shelf.add_child(SupplyArt.Plank.new())
	shelf.set_meta("boxes", boxes)
	ui._shelves.add_child(shelf)
	return shelf

## Układ zakładki zaopatrzenia dla stanowiska: ława — siatka kafli i karta po prawej, prasa — regał, etykieta partii pod regałem
## i matryce po prawej, pirotechnika — skrzynia i karta w wieku. Kafle stoją na stałe w swoim pojemniku (rodzaj należy do jednego stanowiska).
func _arrange_supplies() -> void:
	var press = ui._mode == "press"
	var pyro = ui._mode == "pyro"
	ui._sup_grid.visible = not (press or pyro)
	ui._shelves.visible = press
	ui._notch.visible = press
	ui._crate.visible = pyro
	ui._dies.visible = press
	ui._s_icon.visible = not (press or pyro)                # prasa i skrzynia pokazują przedmiot na regale / w przegrodzie
	ui._lid.add_theme_stylebox_override("panel", SupplyArt.wood_box(6) if pyro else StyleBoxEmpty.new())
	var body = ui._sup_left.get_parent()
	if press and ui._lid.get_parent() != ui._sup_left:
		ui._lid.reparent(ui._sup_left)
	elif not press and ui._lid.get_parent() != body:
		ui._lid.reparent(body)
		body.move_child(ui._lid, 1)
	if press:
		ui._sup_left.move_child(ui._lid, ui._notch.get_index() + 1)
	ui._s_side.visible = press
	for n in [ui._s_vu, ui._s_cmp]:
		var want: Control = ui._s_side if press else ui._s_main
		if n.get_parent() != want:
			n.reparent(want)
			if not press:
				ui._s_main.move_child(n, ui._s_stats.get_index() + (1 if n == ui._s_vu else 3))
	ui._s_text.custom_minimum_size.x = 230.0 if press else ui.DETAIL_W
	ui._s_main.custom_minimum_size.x = 230.0 if press else ui.DETAIL_W

func _make_supply_tile(kd: String, idx: int):
	if _is_press_kind(kd):
		return _make_box_tile(kd, idx)
	if _is_pyro_kind(kd):
		return _make_bay_tile(kd, idx)
	var data: Dictionary = Throwables.KINDS[kd]
	var t = ui.SupplyTile.new()
	t.kind = kd
	var ic = ItemIcon.new()
	ic.k = 1.0
	ic.set_item(kd, Color.WHITE)
	ui._dress_tile(t, ic, String(data["name"]))
	ui._add_price(t)
	var bar = ui.StockBar.new()
	bar.maxn = Throwables.units(kd, int(data["max"]))        # amunicja: w pudełkach
	ui._add_bar(t, bar)
	t.pressed.connect(ui._select_supply.bind(idx))
	return t

func _build_supply_detail() -> Control:
	var v = VBoxContainer.new()
	v.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	ui._s_icon = ItemIcon.new()
	ui._s_icon.k = 2.0
	ui._s_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(ui._s_icon)
	ui._s_title = ui._ink_heading()
	v.add_child(ui._s_title)
	ui._s_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(ui._s_tag)
	ui._s_stats = GridContainer.new()
	ui._s_stats.columns = 3
	ui._s_stats.add_theme_constant_override("h_separation", 10)
	ui._s_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(ui._s_stats)
	ui._s_vu = HBoxContainer.new()                           # VU-metr hałasu (§5a): ta sama skala co w HUD
	ui._s_vu.add_theme_constant_override("separation", 8)
	v.add_child(ui._s_vu)
	ui._s_vu_meter = VuMeter.new()
	ui._s_vu_meter.custom_minimum_size = Vector2(58, 34)
	ui._s_vu_meter.ticks = StationNoise.ticks()
	ui._s_vu.add_child(ui._s_vu_meter)
	ui._s_vu_text = UiTheme.ink("", 8)
	ui._s_vu_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui._s_vu_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui._s_vu_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._s_vu.add_child(ui._s_vu_text)
	for box in ["_s_fuse", "_s_cmp", "_s_queue"]:
		var c = VBoxContainer.new()
		c.add_theme_constant_override("separation", 3)
		v.add_child(c)
		ui.set(box, c)
	ui._s_blast = SupplyArt.BlastDiagram.new()               # pirotechnika: schemat działania w skali (za zapalnikiem)
	v.add_child(ui._s_blast)
	v.move_child(ui._s_blast, ui._s_fuse.get_index() + 1)
	v.add_child(ui._paper_rule())
	ui._s_text = UiTheme.ink("", 8)
	ui._s_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._s_text.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_child(ui._s_text)
	ui._s_action = Button.new()
	ui._s_action.focus_mode = Control.FOCUS_NONE
	ui._s_action.add_theme_font_size_override("font_size", 10)
	ui._s_action.pressed.connect(ui._buy_selected_supply)
	v.add_child(ui._s_action)
	ui._s_main = v
	var cols = HBoxContainer.new()                       # druga kolumna tylko na etykiecie partii (prasa): porównanie i hałas
	cols.add_theme_constant_override("separation", 14)
	cols.add_child(v)
	ui._s_side = VBoxContainer.new()
	ui._s_side.add_theme_constant_override("separation", 6)
	ui._s_side.custom_minimum_size.x = 196
	ui._s_side.visible = false
	cols.add_child(ui._s_side)
	return cols

## Rodzaj z prasy (amunicja specjalna bez 40 mm) / ze stołu pirotechnicznego (granaty, miny, ładunki, 40 mm) — jak `_sup_in_mode`.
func _is_press_kind(k: String) -> bool:
	return Throwables.is_ammo(k) and String(Ammo.from_kind(k).get("cal", "")) != "40mm"

func _is_pyro_kind(k: String) -> bool:
	var m = String(Throwables.KINDS[k]["mode"])
	return m == "throw" or m == "place" or (Throwables.is_ammo(k) and not _is_press_kind(k))

## Prasa (ST-03): pudełko na półce regału — nazwa na etykiecie pudełka, pasek oznaczenia czubka, okienka z pudełkami przy sobie,
## cena na krawędzi półki. Wybór = światło lampy (bez ramki).
func _make_box_tile(kd: String, idx: int):
	var data: Dictionary = Throwables.KINDS[kd]
	var t = ui.SupplyTile.new()
	t.kind = kd
	t.custom_minimum_size = Vector2(86, 74)
	var face = SupplyArt.BoxFace.new()
	face.title = String(data["name"])
	face.stock_max = Throwables.units(kd, int(data["max"]))
	face.set_item(kd, Color.WHITE)
	ui._dress_tile(t, face, String(data["name"]))
	face.position = Vector2(4, 2)
	face.size = Vector2(78, 54)
	t.name_label.visible = false                         # nazwa jest na etykiecie pudełka
	t.state_label.visible = false
	ui._add_price(t)
	t.coin.position = Vector2(8, 60)
	t.price_label.position = Vector2(20, 57)
	var bar = ui.StockBar.new()                            # zapas: okienka na pudełku (wskaźnik kafla ukryty, zostaje dla kodu odświeżania)
	bar.maxn = face.stock_max
	ui._add_bar(t, bar)
	bar.visible = false
	t.box_normal = StyleBoxEmpty.new()
	var lit = StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.8, 0.45, 0.07)
	lit.border_color = UiTheme.LAMP_LINE
	lit.border_width_bottom = 2
	t.box_lit = lit
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_normal if st != "hover" else lit)
	t.pressed.connect(ui._select_supply.bind(idx))
	return t

## Stół pirotechniczny (ST-04): przegroda skrzyni saperskiej — render przedmiotu pod lampą, licznik „przy sobie / maks.” w rogu,
## nazwa i cena na pasku jak napis na przegrodzie.
func _make_bay_tile(kd: String, idx: int):
	var data: Dictionary = Throwables.KINDS[kd]
	var t = ui.SupplyTile.new()
	t.kind = kd
	t.custom_minimum_size = Vector2(98, 96)
	var ic = ItemIcon.new()
	ic.plate = false
	ic.set_item(kd, Color.WHITE)
	ui._dress_tile(t, ic, String(data["name"]))
	ic.position = Vector2(8, 14)
	ic.size = Vector2(82, 56)
	var strip = ColorRect.new()
	strip.color = SupplyArt.LABEL_PAPER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(4, 74)
	strip.size = Vector2(90, 18)
	t.add_child(strip)
	t.move_child(strip, 0)
	t.name_label.position = Vector2(8, 75)
	t.name_label.add_theme_font_size_override("font_size", 9)
	t.state_label.position = Vector2(70, 2)              # „1/4” w rogu przegrody
	ui._add_price(t)
	t.coin.visible = false
	t.price_label.position = Vector2(66, 76)
	t.price_label.add_theme_font_size_override("font_size", 9)
	var bar = ui.StockBar.new()
	bar.maxn = Throwables.units(kd, int(data["max"]))
	ui._add_bar(t, bar)
	bar.visible = false
	t.box_normal = SupplyArt.bay_box()
	var lit = SupplyArt.bay_box()
	lit.bg_color = Color("2a2216")
	lit.border_color = UiTheme.ACCENT.darkened(0.35)
	t.box_lit = lit
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_normal if st != "hover" else lit)
	t.pressed.connect(ui._select_supply.bind(idx))
	return t

## VU-metr hałasu na karcie zaopatrzenia (STATION_CARDS_PLAN.md §5a): przedmiot rzucany / ładunek — poziom po jednym od ciszy i ile naraz
## do niepokoju; amunicja zmieniająca hałas — poziom po magazynku pierwszej broni tego kalibru (cień = nabój zwykły); reszta bez VU.
func _fill_noise(k: String) -> void:
	ui._s_vu.visible = false
	var uneasy = float(NoiseMgr.UNEASY_THRESHOLD)
	var item = StationNoise.item_noise(k)
	if item > 0.0:
		ui._s_vu.visible = true
		ui._s_vu_meter.visible = true
		ui._s_vu_meter.value = item / 100.0
		ui._s_vu_meter.ghost = -1.0
		ui._s_vu_meter.fill = UiTheme.ACCENT if item * 2.0 >= uneasy else UiTheme.TEXT
		var n = StationNoise.count_to(item, uneasy)
		ui._s_vu_text.text = UiTheme.num_text(tr("+%s%% noise per item") % ("%.0f" % item if item >= 1.0 else "%.1f" % item)) + "\n" + tr("%d at once = unease") % n
		return
	var ct = Ammo.from_kind(k)
	if ct.is_empty() or String(ct["cal"]) == "40mm":
		return
	var w = -1
	for id in ui.LIST:
		if String(Weapons.base_def(int(id)).caliber) == String(ct["cal"]):
			w = int(id)
			break
	if w < 0:
		return
	var wc = ui._local_wc()
	var fit: int = wc.fit_of(w) if wc != null else 0
	var plain: RefCounted = Weapons.def_build(w, Weapons.build_of(0, fit))
	var with: RefCounted = Weapons.def_build(w, Weapons.build_of(int(ct["t"]), fit))
	var a = StationNoise.mag_level(plain)
	var b = StationNoise.mag_level(with)
	if absf(a - b) < 0.5:
		ui._s_vu_text.text = tr("Shot noise unchanged.")         # VU tylko przy naboju, który zmienia hałas (§6 ST-03)
		ui._s_vu.visible = true
		ui._s_vu_meter.visible = false
		return
	ui._s_vu.visible = true
	ui._s_vu_meter.visible = true
	ui._s_vu_meter.value = b / 100.0
	ui._s_vu_meter.ghost = a / 100.0
	ui._s_vu_meter.fill = UiTheme.OK if b < a else UiTheme.DANGER
	ui._s_vu_text.text = tr("One %s magazine: %d%% → %d%% noise") % [String(plain.name), roundi(a), roundi(b)]

## Stół pirotechniczny: schemat działania przedmiotu w skali z sylwetką kolegi (granat i ładunek ranią drużynę, mina nie) — z danych przedmiotu.
func _fill_blast(k: String) -> void:
	var d: Dictionary = Throwables.KINDS[k]
	var b := ui._s_blast as SupplyArt.BlastDiagram
	b.visible = ui._mode == "pyro" and k in ["frag", "charge", "mine", "phos", "smoke"]
	if not b.visible:
		return
	b.kind = k
	match k:
		"frag", "charge":
			b.lines = [UiTheme.num_text(tr("%s m · %d damage") % ["%.0f" % (float(d["radius"]) / SupplyArt.PX_PER_M), int(d["damage"])]),
				tr("squad mate: hurt"), tr("safe")]
		"mine":
			b.lines = [UiTheme.num_text(tr("%s m · %d damage · %d° cone") % ["%.0f" % (float(d["range"]) / SupplyArt.PX_PER_M), int(d["damage"]), roundi(2.0 * float(d["half_deg"]))]),
				tr("squad mate: spared"), tr("safe")]
		"phos":
			b.lines = [tr("fire field · %d s") % int(d["field_life"])]
		"smoke":
			b.lines = [tr("cloud · %d s · blocks sight, not sound") % int(d["cloud_life"])]
	b.queue_redraw()

## Stół pirotechniczny: krótszy (−1) albo dłuższy (+1) zapalnik zaznaczonego przedmiotu — dla całej drużyny (serwer).
func _step_fuse(d: int) -> void:
	var k = String(ui._supply_kinds()[ui._sup_sel])
	var opts: Array = Throwables.FUSES.get(k, []) as Array
	if opts.is_empty():
		return
	_set_fuse(k, clampi(Scrap.fuse_index(k) + d, 0, opts.size() - 1))

## Zapalnik `k` na pozycję `ni` (przełącznik na karcie albo klawisze 1 / 2) — ustawienie drużyny rozstrzyga serwer.
func _set_fuse(k: String, ni: int) -> void:
	var opts: Array = Throwables.FUSES.get(k, []) as Array
	if ni < 0 or ni >= opts.size() or ni == Scrap.fuse_index(k):
		return
	Scrap.request_fuse(k, ni)
	Audio.play("ui_click", Audio.BUS_UI, -10.0, 1.2)
	ui._say(tr("%s fuse: %.1f s — for the whole squad.") % [tr(String(Throwables.KINDS[k]["name"])), float(opts[ni])], UiTheme.OK)
	ui._refresh()

## Stół pirotechniczny: trzy pozycje zapalnika jako przełącznik (zamiast „1,8 s (2 z 3) · 1 / 2 zmień”), z dopiskiem, że to ustawienie drużyny.
func _fill_fuse(k: String) -> void:
	ui._clear_children(ui._s_fuse)
	ui._s_fuse.visible = ui._mode == "pyro" and Throwables.FUSES.has(k)
	if not ui._s_fuse.visible:
		return
	ui._s_fuse.add_child(UiTheme.ink(tr("FUSE  ·  %s / %s") % [ui._menu_key("menu_slot_1", Actions.pad_mode), ui._menu_key("menu_slot_2", Actions.pad_mode)], 7, UiTheme.INK_MUTED))
	# pokrętło zapalnika (ST-04): tarcza z pozycjami, obok lista pozycji z czasem; klawisze pozycji obracają pokrętło
	var dial_row = HBoxContainer.new()
	dial_row.add_theme_constant_override("separation", 10)
	ui._s_fuse.add_child(dial_row)
	var opts: Array = Throwables.FUSES[k]
	var dial = SupplyArt.FuseDial.new()
	dial.count = opts.size()
	dial.index = Scrap.fuse_index(k)
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dial_row.add_child(dial)
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dial_row.add_child(row)
	for i in opts.size():
		var b = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s" % [tr(ui.FUSE_NAMES[mini(i, ui.FUSE_NAMES.size() - 1)]), UiTheme.num_text("%.1f s" % float(opts[i]))]
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_constant_override("outline_size", 0)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, UiTheme.INK if i == Scrap.fuse_index(k) else UiTheme.INK_MUTED)
		for st in ["normal", "hover", "pressed", "focus"]:
			var box = StyleBoxFlat.new()
			var sel = i == Scrap.fuse_index(k)
			box.bg_color = UiTheme.PAPER_SEL if sel else (Color(UiTheme.PAPER_SEL, 0.5) if st == "hover" else Color(0, 0, 0, 0))
			box.border_color = UiTheme.INK if sel else UiTheme.PAPER_EDGE
			box.set_border_width_all(2 if sel else 1)
			box.set_content_margin_all(3)
			b.add_theme_stylebox_override(st, box)
		b.pressed.connect(_set_fuse.bind(k, i))
		row.add_child(b)
	var cord = SupplyArt.FuseCord.new()                 # lont: długość = czas zapalnika (pełna szerokość = najdłuższa pozycja)
	cord.seconds = float(opts[Scrap.fuse_index(k)])
	cord.max_s = float(opts.back())
	ui._s_fuse.add_child(cord)
	var note = UiTheme.ink(tr("Squad setting: everyone's %s uses this fuse.") % tr(String(Throwables.KINDS[k]["name"])), 7, UiTheme.INK_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = ui.DETAIL_W
	ui._s_fuse.add_child(note)

## Prasa: co nabój zmienia względem zwykłego tego kalibru (modyfikatory ammo.gd) — wartość i ocena słowem, kolor tylko ją wzmacnia.
func _fill_ammo_cmp(k: String) -> void:
	ui._clear_children(ui._s_cmp)
	var rows = _ammo_rows(k)
	ui._s_cmp.visible = not rows.is_empty()
	if rows.is_empty():
		return
	ui._s_cmp.add_child(UiTheme.ink(tr("VS. STANDARD ROUND"), 7, UiTheme.INK_MUTED))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	ui._s_cmp.add_child(grid)
	for r in rows:
		var kind = int(r[2])
		var col = UiTheme.INK_GAIN if kind > 0 else (UiTheme.INK_COST if kind < 0 else UiTheme.INK)
		grid.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		if ui._mode == "press":
			# etykieta partii (ST-03): pasek od zera — zysk w prawo, koszt w lewo — i wartość ze znakiem ▲▼ (kolor tylko wzmacnia)
			var bar = SupplyArt.CmpBar.new()
			bar.value = float(kind) * (float(r[3]) if r.size() > 3 else 0.3)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(bar)
			grid.add_child(UiTheme.ink(("▲ " if kind > 0 else ("▼ " if kind < 0 else "")) + UiTheme.num_text(String(r[1])), 9, col))
			continue
		grid.add_child(UiTheme.ink(UiTheme.num_text(String(r[1])), 9, col))
		grid.add_child(UiTheme.ink((tr("Gain") if kind > 0 else (tr("Trade-off") if kind < 0 else "")).to_lower(), 7, col))

## Wiersze porównania naboju `k` z nabojem zwykłym: [etykieta, zmiana, ocena −1 / 0 / 1]. Granaty 40 mm to inny ładunek, nie wariant — bez porównania.
func _ammo_rows(k: String) -> Array:
	var ct = Ammo.from_kind(k)
	if ct.is_empty() or String(ct["cal"]) == "40mm":
		return []
	var t = Ammo.type_of(String(ct["cal"]), int(ct["t"]))
	var out: Array = []
	if bool(t.get("slug", false)):
		out.append(["Pellets", tr("one heavy slug"), 0])
	if bool(t.get("subsonic", false)):
		out.append(["Bullet crack", tr("none — quieter"), 1])
	for m in t.get("mods", []):
		var f = String(m[0])
		if not ui.AMMO_FIELDS.has(f):
			continue
		var spec: Array = ui.AMMO_FIELDS[f]
		var v = float(m[2])
		var text = ""
		var sgn = 0.0
		match String(m[1]):
			"mul":
				text = "%+d%%" % roundi((v - 1.0) * 100.0)
				sgn = v - 1.0
			"add":
				match String(spec[2]):
					"pct":
						text = "+%d%%" % roundi(v * 100.0)
					"s":
						text = tr("+%.1f s") % v
					"m":
						text = "+%.1f m" % (v / 16.0)
					_:
						text = "%+.1f" % v
				sgn = v
			"set":
				text = tr("none") if f == "crit_mult" and v <= 1.0 else "%.1f" % v
				sgn = -1.0 if f == "crit_mult" else 1.0
		out.append([String(spec[0]), text, int(signf(sgn) * float(spec[1])), clampf(absf(sgn) if String(m[1]) != "set" else 0.5, 0.1, 1.0)])
	return out

## Prasa: miejsca na partie — zajęte z nazwą naboju, wolne puste (dawniej wiersz „1 z 3 partii”).
func _fill_press_queue() -> void:
	ui._clear_children(ui._s_queue)
	ui._s_queue.visible = false                             # od E2 partie stoją na matrycach w kolumnie po prawej (_fill_dies)
	_fill_dies()

## Prasa (ST-03): matryce pionowo po prawej — zajęta pokazuje nabój i „po udanej misji”, wolna jest pusta.
func _fill_dies() -> void:
	ui._clear_children(ui._dies_list)
	if ui._mode != "press":
		return
	ui._dies_list.add_child(UiTheme.mono(UiTheme.label(tr("DIES"), 8, UiTheme.MUTED)))
	for i in Scrap.PRESS_SLOTS:
		var filled = i < Scrap.orders.size()
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var die = SupplyArt.FuseDial.new()                  # matryca: okrągłe gniazdo, zajęte ze wskazówką w kolorze lampy
		die.count = 1
		die.index = 0
		die.custom_minimum_size = Vector2(26, 26)
		die.modulate = Color.WHITE if filled else Color(0.5, 0.5, 0.5)
		die.set_meta("filled", filled)
		row.add_child(die)
		var col = VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.add_child(UiTheme.label(String(Throwables.KINDS[String(Scrap.orders[i])]["name"]) if filled else tr("free"), 9, UiTheme.TEXT if filled else UiTheme.MUTED))
		col.add_child(UiTheme.label(tr("after a successful mission") if filled else "—", 7, UiTheme.MUTED))
		row.add_child(col)
		ui._dies_list.add_child(row)

func _refresh_supplies() -> void:
	var kinds = ui._supply_kinds()
	for i in ui._sup_tiles.size():
		var t = ui._sup_tiles[i]
		var sel = i == ui._sup_sel
		t.set_lit(sel)
		var k = String(kinds[i])
		t.visible = ui._sup_in_mode(k)
		var have = Arsenal.get_throwable(k)
		var price = ui._sup_price(k)
		t.price_label.text = ("%d" % price) + (("  +%d" % Scrap.ordered(k)) if Scrap.ordered(k) > 0 else "")
		(t.icon_node as ItemIcon).set_item(k, Color.WHITE if have > 0 or Scrap.bank >= price else Color(0.6, 0.64, 0.68))
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.TEXT)
		t.price_label.add_theme_color_override("font_color", ui.GOLD if Scrap.bank >= price else UiTheme.DANGER)
		t.bar.have = Throwables.units(k, have)
		t.bar.queue_redraw()
		if t.icon_node is SupplyArt.BoxFace:                 # pudełko na półce: okienka = pudełka przy sobie, cena na desce
			(t.icon_node as SupplyArt.BoxFace).stock = t.bar.have
			t.icon_node.queue_redraw()
		elif _is_pyro_kind(k):                               # przegroda skrzyni: napis atramentem na pasku, licznik w rogu
			t.name_label.add_theme_color_override("font_color", UiTheme.INK)
			t.name_label.add_theme_constant_override("outline_size", 0)
			t.price_label.add_theme_color_override("font_color", UiTheme.INK_PRICE if Scrap.bank >= price else UiTheme.INK_COST)
			t.price_label.add_theme_constant_override("outline_size", 0)
			t.state_label.text = "%d/%d" % [Throwables.units(k, have), t.bar.maxn]
			t.state_label.add_theme_color_override("font_color", UiTheme.TEXT if have > 0 else UiTheme.MUTED)
		t.tooltip_text = tr("The squad carries %d of %d.") % [have, int(Throwables.KINDS[k]["max"])]
	ui._sup_note.text = tr("Grenades, mines and 40 mm rounds are at the pyrotechnics table, special ammo at the reloading press.") if ui._mode == "bench" else ""
	ui._sup_note.visible = ui._sup_note.text != ""
	var k2 = String(kinds[ui._sup_sel])
	var d: Dictionary = Throwables.KINDS[k2]
	var have2 = Arsenal.get_throwable(k2)
	var maxn = int(d["max"])
	ui._s_icon.set_item(k2, Color.WHITE)
	ui._s_title.text = String(d["name"])
	var mode: String = {"throw": "Throwable", "place": "Placed", "use": "Tool", "ammo": "Ammunition"}[String(d["mode"])]
	ui._s_tag.text = "%s  ·  %s" % [tr(String(d["full"])), tr(mode)]
	if Throwables.is_ammo(k2):
		ui._s_title.text = tr(String(d["full"]))               # pełna nazwa naboju zamiast skrótu z kafla („7.62 HOT” → „7.62×39 ładunek wzmocniony”)
		ui._s_tag.text = "%s  ·  %s" % [String(d["name"]), tr(mode)]
	for ch in ui._s_stats.get_children():
		ui._s_stats.remove_child(ch)
		ch.free()
	var rows: Array = [["Carried", "%d / %d" % [have2, maxn]], ["Issued free", tr("%d per mission") % int(d["issue"]) if int(d["issue"]) > 0 else "—"]]
	if Throwables.is_ammo(k2):
		var ct = Ammo.from_kind(k2)
		var users: Array = []
		for wd in Weapons.defs():
			if String(wd.caliber) == String(ct.get("cal", "")):
				users.append(String(wd.name))
		rows = [["Carried", tr("%d / %d rounds") % [have2, maxn]], ["Box", tr("%d rounds") % Throwables.box_of(k2)], ["Fits", ", ".join(users)]]
	elif (d.has("noise") or k2 in ["frag", "charge"]) and ui._mode != "pyro":
		rows.append(["Noise", Codex.noise_text(k2)])                       # przy stole pirotechnicznym hałas pokazuje VU-metr
	if Throwables.FUSES.has(k2) and ui._mode != "pyro":
		rows.append(["Fuse", "%.1f s" % Scrap.fuse_of(k2)])              # przy stole pirotechnicznym zapalnik ma własny przełącznik
	for r in rows:
		ui._s_stats.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		ui._s_stats.add_child(UiTheme.ink(UiTheme.num_text(tr(String(r[1]))), 9))
		ui._s_stats.add_child(Control.new())
	_fill_noise(k2)
	_fill_fuse(k2)
	_fill_blast(k2)
	_fill_ammo_cmp(k2)
	ui._notch.target = ui._sup_tiles[ui._sup_sel]
	_fill_press_queue()
	ui._s_text.text = tr(String(d["note"]))
	var summary = ui._queue_summary(ui._mode == "press")
	if summary != "":
		ui._s_text.text += "\n\n" + summary
	if Throwables.is_ammo(k2):
		ui._s_text.text += "\n" + tr("[%s] in the field picks the ammo type for the next magazine.") % Actions.key("ammo_type")
	var price2 = ui._sup_price(k2)
	var queued = Scrap.ordered(k2) * Throwables.box_of(k2) + int(Scrap.deliveries.get(k2, 0))
	ui._act_state(ui._s_action, "", 0)
	ui._s_action.disabled = have2 + queued >= maxn or not Scrap.enabled()
	if not Scrap.enabled():
		ui._s_action.text = "No scrap in this mode"
	elif int(Scrap.deliveries.get(k2, 0)) > 0:
		ui._s_action.disabled = have2 >= maxn
		ui._s_action.text = tr("Collect ready delivery · %d rounds") % int(Scrap.deliveries[k2])
		ui._act_state(ui._s_action, "collect", 0)
	elif have2 + queued >= maxn:
		ui._s_action.text = "The squad is carrying the maximum"
	elif Throwables.is_ammo(k2) and Scrap.orders.size() >= Scrap.PRESS_SLOTS:
		ui._s_action.text = tr("The press is full — %d batches per mission") % Scrap.PRESS_SLOTS
	elif Throwables.is_ammo(k2):
		ui._s_action.text = tr("Order a batch  ·  %d scrap  ·  ready after the mission") % price2
		ui._act_state(ui._s_action, "ready", price2)
	else:
		ui._s_action.text = (tr("Buy a box  ·  %d scrap") % price2) if Throwables.is_ammo(k2) else (tr("Buy +1  ·  %d scrap") % price2)
		ui._act_state(ui._s_action, "ready", price2)
