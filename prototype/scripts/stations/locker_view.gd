extends RefCounted
## Szafka osobista (ST-07): perki (drzwi, książeczka, naszywki, rzepy) i wygląd.
## Wydzielone z workshop_ui.gd (STATION_CARDS_PLAN.md E1 — podział na widoki stanowisk). Stan panelu (kafle, etykiety, wybór) zostaje
## w workshop_ui.gd, tu jest budowa i wypełnianie; `ui` to panel. workshop_ui woła te funkcje przez funkcje o tych samych nazwach.

const UiTheme := preload("res://scripts/ui_theme.gd")
const PerkIcon := preload("res://scripts/perk_icon.gd")
const Perks := preload("res://scripts/perks.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Char3D := preload("res://scripts/char3d.gd")
const StationNoise := preload("res://scripts/station_noise.gd")
const VuMeter := preload("res://scripts/vu_meter.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, kafle, etykiety

func _init(panel: Control) -> void:
	ui = panel

## Zakładka LOOK: siatka 2 × 3 (kolumny: mężczyzna / kobieta, wiersze: stroje) z animowanymi podglądami i szczegóły z przyciskiem Equip.
## Kod wyglądu kafla i = wiersz (strój) × 2 + kolumna (płeć). Stroje odblokowuje poziom profilu (Look.UNLOCK_LEVEL); wygląd jest tylko kosmetyką.
func _look_code(i: int) -> int:
	return Look.code(i % ui.COLS, i / ui.COLS)

func _build_look() -> HBoxContainer:
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (ui.TILE_H + 6.0))
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	var grid = GridContainer.new()
	grid.columns = ui.COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	# kolumny siatki to płeć — ta sama nazwa stroju stoi w obu, więc kolumny mają podpis
	var heads = HBoxContainer.new()
	heads.add_theme_constant_override("separation", 6)
	for g in Look.GENDERS:
		var hl = UiTheme.label(tr(String(g).capitalize()).to_upper(), 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		hl.custom_minimum_size.x = ui.TILE_W
		heads.add_child(hl)
	left.add_child(heads)
	left.move_child(heads, grid.get_index())
	for i in Look.GENDERS.size() * Look.OUTFITS.size():
		var t = ui.LookTile.new()
		t.code = _look_code(i)
		t.custom_minimum_size = Vector2(ui.TILE_W, ui.TILE_H * 1.5)
		var portrait = "res://art/portraits/look_%s_%s.png" % [Look.gender_id(t.code), Look.outfit_id(t.code)]
		t.view = ui.LookPortrait.new() if ResourceLoader.exists(portrait) else ui.LookView.new()       # render 3D jak duży podgląd; bez niego stary arkusz
		t.view.call("set_code", t.code)
		ui._dress_tile(t, t.view, Look.display_name(t.code))
		t.pressed.connect(_select_look.bind(i))
		grid.add_child(t)
		ui._look_tiles.append(t)
	var v = VBoxContainer.new()
	v.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	var lv = ui.LookView.new()                              # podgląd 2D z arkusza; model 3D na żywo dochodzi w _refresh_look (Sprites.char3d bywa ustawione później)
	lv.anim = "run"
	lv.custom_minimum_size = Vector2(0, 150)
	ui._l_view = lv
	ui._l_box = v
	v.add_child(ui._l_view)
	ui._l_title = ui._ink_heading()
	v.add_child(ui._l_title)
	ui._l_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(ui._l_tag)
	ui._pal_row = HBoxContainer.new()                       # paleta kolorów stroju: tylko dla modeli 3D
	ui._pal_row.add_theme_constant_override("separation", 5)
	ui._pal_row.add_child(UiTheme.ink(tr("COLOR"), 8, UiTheme.INK_MUTED))
	for pi in Look.PALETTES.size():
		var pb = Button.new()
		pb.focus_mode = Control.FOCUS_NONE
		pb.custom_minimum_size = Vector2(20, 14)
		pb.tooltip_text = Look.palette_name(pi)
		pb.pressed.connect(_select_palette.bind(pi))
		ui._pal_row.add_child(pb)
		ui._pal_btns.append(pb)
	ui._pal_row.visible = false
	v.add_child(ui._pal_row)
	v.add_child(ui._paper_rule())
	ui._l_text = UiTheme.ink("", 8)
	ui._l_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._l_text.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_child(ui._l_text)
	ui._l_action = Button.new()
	ui._l_action.focus_mode = Control.FOCUS_NONE
	ui._l_action.add_theme_font_size_override("font_size", 10)
	ui._l_action.pressed.connect(_act_look)
	v.add_child(ui._l_action)
	body.add_child(ui._paper(v))
	return body

func _select_palette(pi: int) -> void:
	ui._look_pal = pi
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._refresh()

func _select_look(i: int) -> void:
	ui._look_sel = i
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._refresh()

func _act_look() -> void:
	var c = Look.with_palette(_look_code(ui._look_sel), ui._look_pal)
	if Profile.look == c:
		ui._say(tr("Already wearing %s.") % Look.display_name(c), UiTheme.MUTED)
	elif Profile.set_look(c):
		ui._success_fx()
		ui._say(tr("%s (%s) equipped.") % [Look.display_name(c), tr(Look.gender_id(c).capitalize())], UiTheme.OK)
	else:
		ui._say(tr("Unlocks at level %d.") % Look.unlock_level(c), UiTheme.DANGER)

func _refresh_look() -> void:
	var lvl = Profile.level()
	var use3d = Sprites.char3d and Char3D.available()
	if use3d and ui._l_view3 == null:
		ui._l_view3 = ui.Look3DView.new()
		ui._l_box.add_child(ui._l_view3)
		ui._l_box.move_child(ui._l_view3, ui._l_view.get_index())
	ui._l_view.visible = not use3d
	if ui._l_view3 != null:
		ui._l_view3.visible = use3d
	ui._pal_row.visible = use3d
	var vw: Control = ui._l_view3 if use3d else ui._l_view
	for i in ui._look_tiles.size():
		var t = ui._look_tiles[i]
		var sel = i == ui._look_sel
		t.set_lit(sel)
		var ok = Look.is_unlocked(t.code, lvl)
		t.view.modulate = Color.WHITE if ok else Color(0.35, 0.4, 0.45)
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.TEXT)
		var worn = Look.base(Profile.look) == t.code
		t.state_label.text = (tr("EQUIPPED") if worn else tr("AVAILABLE")) if ok else tr("LV %d") % Look.unlock_level(t.code)
		t.state_label.add_theme_color_override("font_color", UiTheme.OK if worn else (UiTheme.MUTED if ok else UiTheme.DANGER))
	for pi in ui._pal_btns.size():
		var pb := ui._pal_btns[pi] as Button
		var d: Dictionary = Look.PALETTES[pi]
		var pbox = StyleBoxFlat.new()
		pbox.bg_color = (d["swatch"] as Color) if lvl >= int(d["level"]) else (d["swatch"] as Color).darkened(0.65)
		pbox.border_color = UiTheme.INK if pi == ui._look_pal else Color(UiTheme.PAPER_EDGE, 0.8)
		pbox.set_border_width_all(2 if pi == ui._look_pal else 1)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			pb.add_theme_stylebox_override(st, pbox)
		var locked = lvl < int(d["level"])
		pb.text = str(int(d["level"])) if locked else ""                  # zablokowany kolor: numer poziomu na próbce (nie tylko ciemniejszy odcień)
		pb.add_theme_font_size_override("font_size", 7)
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			pb.add_theme_color_override(fc, UiTheme.TEXT)
		pb.tooltip_text = Look.palette_name(pi) + ((" · " + tr("Locked — level %d") % int(d["level"])) if locked else "")
	var c = Look.with_palette(_look_code(ui._look_sel), ui._look_pal)
	vw.call("set_code", c)
	vw.modulate = Color.WHITE if Look.is_unlocked(c, lvl) else Color(0.35, 0.4, 0.45)
	ui._l_title.text = Look.display_name(c)
	ui._l_tag.text = tr("%s  ·  unlocks at level %d") % [tr(Look.gender_id(c).capitalize()).to_upper(), Look.unlock_level(c)]
	ui._l_text.text = tr(String(Look.OUTFIT_TEXT[Look.outfit_id(c)])) + "\n\n" + tr("Cosmetic only — other players see your look too.")
	ui._l_action.disabled = false
	ui._l_action.text = tr("Wearing") if Profile.look == c else (tr("Equip") if Look.is_unlocked(c, lvl) else tr("Locked — level %d") % Look.unlock_level(c))
	ui._act_state(ui._l_action, "ready" if Profile.look != c and Look.is_unlocked(c, lvl) else "wait", 0)      # założony albo zablokowany — ciemna dźwignia

## Zakładka PERKS: ten sam układ co ARMS i SUPPLIES — po lewej pasek poziomu, siatka kafli i dwa sloty, po prawej szczegóły wybranego perku.
func _build_perks() -> HBoxContainer:
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(0, 6.0 * (ui.TILE_H + 6.0))
	# drzwi szafki osobistej (ST-07): blacha w zieleni munduru, szczeliny, na drzwiach zdjęcie, książeczka, naszywki perków i rzepy slotów
	var door = PanelContainer.new()
	door.add_theme_stylebox_override("panel", ServiceArt.locker_door())
	door.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(door)
	var vents = ServiceArt.Vents.new()
	door.add_child(vents)
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	door.add_child(left)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	left.add_child(top)
	var photo = PanelContainer.new()                      # zdjęcie przyklejone taśmą: portret założonego wyglądu
	var pb = StyleBoxFlat.new()
	pb.bg_color = Color("1a1c17")
	pb.border_color = Color("8a8574")
	pb.set_border_width_all(2)
	pb.border_width_bottom = 6
	photo.add_theme_stylebox_override("panel", pb)
	photo.rotation_degrees = 2.5
	var lp = ui.LookPortrait.new()
	lp.custom_minimum_size = Vector2(40, 52)
	photo.add_child(lp)
	ui._book_photo = lp
	top.add_child(photo)
	var book = ServiceArt.Scrawl.new()                     # książeczka wojskowa (SCRAWL): poziom, XP, pieczątki poziomów
	book.stains = false
	book.rotation_degrees = 0.0
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(book)
	var bv = VBoxContainer.new()
	bv.add_theme_constant_override("separation", 1)
	book.add_child(bv)
	var bcap = UiTheme.ink(tr("SERVICE RECORD"), 7, UiTheme.INK_MUTED)
	bv.add_child(bcap)
	var lv = HBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	ui._lvl_label = UiTheme.heading("LV 1", 12, UiTheme.INK)
	ui._lvl_label.add_theme_constant_override("outline_size", 0)
	lv.add_child(ui._lvl_label)
	ui._lvl_bar = ui.LevelBar.new()
	ui._lvl_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(ui._lvl_bar)
	ui._xp_label = UiTheme.ink("", 9, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	lv.add_child(ui._xp_label)
	bv.add_child(lv)
	ui._book_stamps = ServiceArt.LevelStamps.new()
	bv.add_child(ui._book_stamps)
	var grid = GridContainer.new()
	grid.columns = ui.COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in Perks.ORDER.size():
		var t = _make_perk_tile(String(Perks.ORDER[i]), i)
		grid.add_child(t)
		ui._perk_tiles.append(t)
	var slots = HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	left.add_child(slots)
	for si in 2:
		slots.add_child(_make_slot_chip(si))
	ui._perk_paper = ui._paper(_build_perk_detail())             # strona książeczki: kartka odręczna (SCRAWL)
	var pp = UiTheme.paper_box()
	pp.bg_color = NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)["bg"]
	pp.border_color = NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)["edge"]
	ui._perk_paper.add_theme_stylebox_override("panel", pp)
	body.add_child(ui._perk_paper)
	return body

func _make_perk_tile(id: String, idx: int):
	var t = ui.PerkTile.new()
	t.perk = id
	var ic = PerkIcon.new()
	ic.k = 1.0
	ic.set_perk(id, Color.WHITE)
	ui._dress_tile(t, ic, Perks.display_name(id))
	var col: Color = Perks.PERKS[id]["color"]              # naszywka: tkanina w kolorze perka z obszyciem
	t.box_normal = ServiceArt.patch_box(col, false)
	t.box_lit = ServiceArt.patch_box(col, true)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, t.box_lit if st == "hover" else t.box_normal)
	var stitch = ServiceArt.Stitch.new()
	stitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stitch.color = Color(col, 0.45)
	t.add_child(stitch)
	t.set_meta("stitch", stitch)
	t.pressed.connect(_select_perk.bind(idx))
	return t

## Slot perka (0–1) pod siatką: miniatura założonego perka, nazwa albo „empty” / poziom odblokowania. Klik albo klawisz 1 / 2 wybiera slot docelowy.
func _make_slot_chip(si: int) -> Control:
	var root = PanelContainer.new()
	root.custom_minimum_size = Vector2(150, 40)
	root.add_theme_stylebox_override("panel", UiTheme.tile_box("normal"))
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(ServiceArt.Velcro.new())               # slot = pasek rzepu na drzwiach (naszywka perka przypina się do niego)
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	root.add_child(h)
	var ic = PerkIcon.new()
	ic.k = 1.0
	ic.custom_minimum_size = Vector2(40, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	var cap = UiTheme.label("SLOT %d  [%d]" % [si + 1, si + 1], 8, UiTheme.MUTED)
	col.add_child(cap)
	var nm = UiTheme.label("", 9, UiTheme.TEXT)
	col.add_child(nm)
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			ui._perk_slot = si
			ui._refresh())
	ui._slot_chips.append({"root": root, "icon": ic, "name": nm})
	return root

func _build_perk_detail() -> Control:
	var v = VBoxContainer.new()
	v.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	ui._p_icon = PerkIcon.new()
	ui._p_icon.k = 2.0
	ui._p_icon.custom_minimum_size = Vector2(0, 58)
	v.add_child(ui._p_icon)
	ui._p_title = ui._ink_heading()
	v.add_child(ui._p_title)
	ui._p_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(ui._p_tag)
	ui._p_stats = GridContainer.new()
	ui._p_stats.columns = 3
	ui._p_stats.add_theme_constant_override("h_separation", 10)
	ui._p_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(ui._p_stats)
	ui._p_vu = HBoxContainer.new()
	ui._p_vu.add_theme_constant_override("separation", 8)
	v.add_child(ui._p_vu)
	ui._p_vu_meter = VuMeter.new()
	ui._p_vu_meter.custom_minimum_size = Vector2(58, 34)
	ui._p_vu_meter.ticks = StationNoise.ticks()
	ui._p_vu.add_child(ui._p_vu_meter)
	ui._p_vu_text = UiTheme.ink("", 8)
	ui._p_vu_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ui._p_vu.add_child(ui._p_vu_text)
	v.add_child(ui._paper_rule())
	ui._p_text = UiTheme.ink("", 8)
	ui._p_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._p_text.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_child(ui._p_text)
	ui._p_action = Button.new()
	ui._p_action.focus_mode = Control.FOCUS_NONE
	ui._p_action.add_theme_font_size_override("font_size", 10)
	ui._p_action.pressed.connect(_act_perk)
	v.add_child(ui._p_action)
	return v

func _select_perk(i: int) -> void:
	if i != ui._perk_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._perk_sel = i
	ui._refresh()

## Które sloty zajmuje perk: indeks slotu albo -1.
func _perk_slot_of(id: String) -> int:
	return Profile.equipped.find(id)

## Akcja na wybranym perku: zdejmij (jeśli założony) albo załóż w wybranym slocie.
func _act_perk() -> void:
	var id = String(Perks.ORDER[ui._perk_sel])
	var have = _perk_slot_of(id)
	if have >= 0:
		Profile.unequip(have)
		ui._say(tr("%s removed.") % Perks.display_name(id), UiTheme.MUTED)
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		return
	if not Profile.is_unlocked(id):
		ui._say(tr("Reach level %d to unlock %s.") % [Perks.unlock_level(id), Perks.display_name(id)], UiTheme.MUTED)
		return
	if ui._perk_slot >= Profile.slots():
		ui._say(tr("Slot %d unlocks at level %d.") % [ui._perk_slot + 1, int(Profile.SLOT_LEVELS[ui._perk_slot])], UiTheme.MUTED)
		return
	if Profile.equip(ui._perk_slot, id):
		ui._say(tr("%s equipped in slot %d.") % [Perks.display_name(id), ui._perk_slot + 1], UiTheme.OK)
		ui._success_fx()

func _refresh_perks() -> void:
	var lp = Profile.level_progress()
	ui._lvl_label.text = "LV %d" % Profile.level()
	ui._lvl_bar.frac = clampf(float(lp[0]) / maxf(1.0, float(lp[1])), 0.0, 1.0)
	ui._lvl_bar.queue_redraw()
	ui._xp_label.text = "%d / %d XP" % [int(lp[0]), int(lp[1])]
	(ui._book_stamps as ServiceArt.LevelStamps).level = Profile.level()
	ui._book_stamps.queue_redraw()
	(ui._book_photo).set_code(Look.base(Profile.look))
	if ui._perk_slot >= maxi(1, Profile.slots()):
		ui._perk_slot = 0
	Profile.mark_seen("perk:" + String(Perks.ORDER[ui._perk_sel]))       # perk pod kursorem jest obejrzany — kropka „nowe” gaśnie
	for i in ui._perk_tiles.size():
		var t = ui._perk_tiles[i]
		var id = t.perk
		var sel = i == ui._perk_sel
		t.set_lit(sel)
		var unlocked = Profile.is_unlocked(id)
		var at = _perk_slot_of(id)
		t.set_new(Profile.is_new("perk:" + id))
		(t.icon_node as PerkIcon).set_perk(id, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
		var sti := t.get_meta("stitch") as ServiceArt.Stitch
		sti.foil = not unlocked                              # zablokowany perk w folii
		sti.queue_redraw()
		t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if sel else (UiTheme.TEXT if unlocked else UiTheme.MUTED))
		if at >= 0:
			t.state_label.text = tr("EQUIPPED  ·  SLOT %d") % (at + 1)
			t.state_label.add_theme_color_override("font_color", UiTheme.OK)
		elif unlocked:
			t.state_label.text = "AVAILABLE"
			t.state_label.add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			t.state_label.text = "LV %d" % Perks.unlock_level(id)
			t.state_label.add_theme_color_override("font_color", ui.GOLD if Profile.level() + 1 >= Perks.unlock_level(id) else UiTheme.DANGER)
	for si in ui._slot_chips.size():
		var c: Dictionary = ui._slot_chips[si]
		var open = si < Profile.slots()
		var eq = String(Profile.equipped[si])
		var chosen = si == ui._perk_slot
		var vb = StyleBoxFlat.new()                             # rzep: wybrany slot w świetle lampy
		vb.bg_color = Color(0, 0, 0, 0)
		vb.border_color = UiTheme.LAMP_LINE if chosen else Color("15170f")
		vb.set_border_width_all(2 if chosen else 1)
		vb.set_content_margin_all(4)
		(c["root"] as PanelContainer).add_theme_stylebox_override("panel", vb)
		if not open:
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "LV %d" % int(Profile.SLOT_LEVELS[si])
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.DANGER)
		elif eq == "":
			(c["icon"] as PerkIcon).set_perk(String(Perks.ORDER[0]), Color(0.25, 0.28, 0.32, 0.6))
			(c["name"] as Label).text = "empty"
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.MUTED)
		else:
			(c["icon"] as PerkIcon).set_perk(eq, Color.WHITE)
			(c["name"] as Label).text = Perks.display_name(eq)
			(c["name"] as Label).add_theme_color_override("font_color", UiTheme.TEXT)
	var id2 = String(Perks.ORDER[ui._perk_sel])
	var d: Dictionary = Perks.PERKS[id2]
	var unlocked2 = Profile.is_unlocked(id2)
	var at2 = _perk_slot_of(id2)
	ui._p_icon.set_perk(id2, Color.WHITE if unlocked2 else Color(0.55, 0.6, 0.65))
	ui._p_title.text = tr(String(d["name"])).to_upper()
	ui._p_tag.text = tr("Perk  ·  unlocks at level %d") % int(d["level"])
	for ch in ui._p_stats.get_children():
		ui._p_stats.remove_child(ch)
		ch.free()
	var status = tr("Equipped — slot %d") % (at2 + 1) if at2 >= 0 else (tr("Available") if unlocked2 else tr("Locked — reach level %d") % int(d["level"]))
	var prows: Array = [["Status", status], ["Slots", tr("%d of 2 open") % Profile.slots()]]
	var pp: Dictionary = d.get("params", {})
	if pp.has("run_noise_mult"):                           # bieg nie przebija wygaszania Uwagi (§5a) — mnożnik w wierszu, bez VU
		prows.append(["Running", UiTheme.num_text("▼ ×%.1f  (%.2f / s)" % [float(pp["run_noise_mult"]), NoiseMgr.N_RUN_PER_SEC * float(pp["run_noise_mult"])])])
	ui._p_vu.visible = pp.has("scream_cap")
	if ui._p_vu.visible:                                      # krzyk to jedno zdarzenie: poziom po krzyku od ciszy, cień = bez perka
		ui._p_vu_meter.value = float(pp["scream_cap"]) / 100.0
		ui._p_vu_meter.ghost = NoiseMgr.N_SCREAM / 100.0
		ui._p_vu_meter.fill = UiTheme.OK
		ui._p_vu_text.text = tr("Scream: %d%% → %d%% noise") % [int(NoiseMgr.N_SCREAM), int(pp["scream_cap"])]
	for r in prows:
		ui._p_stats.add_child(UiTheme.ink(tr(String(r[0])), 9, UiTheme.INK_MUTED))
		ui._p_stats.add_child(UiTheme.ink(String(r[1]), 9, UiTheme.INK_GAIN if at2 >= 0 and String(r[0]) == "Status" else UiTheme.INK))
		ui._p_stats.add_child(Control.new())
	ui._p_text.text = String(d["desc"])
	if at2 >= 0:
		ui._p_action.text = tr("Remove from slot %d") % (at2 + 1)
		ui._p_action.disabled = false
	elif not unlocked2:
		ui._p_action.text = tr("Locked  ·  reach level %d") % int(d["level"])
		ui._p_action.disabled = true
	elif ui._perk_slot >= Profile.slots():
		ui._p_action.text = tr("Slot %d unlocks at level %d") % [ui._perk_slot + 1, int(Profile.SLOT_LEVELS[ui._perk_slot])]
		ui._p_action.disabled = true
	else:
		ui._p_action.text = tr("Equip in slot %d") % (ui._perk_slot + 1)
		ui._p_action.disabled = false
