extends RefCounted
## Pracownia i tokarka (ST-05, ST-06): korek z łańcuchem, słoje, akta, wydruk; rysunek, zlecenie, rulony, szlifierka.
## Wydzielone z workshop_ui.gd (STATION_CARDS_PLAN.md E1 — podział na widoki stanowisk). Stan panelu (kafle, etykiety, wybór) zostaje
## w workshop_ui.gd, tu jest budowa i wypełnianie; `ui` to panel. workshop_ui woła te funkcje przez funkcje o tych samych nazwach.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Parts := preload("res://scripts/parts.gd")
const StationKit := preload("res://scripts/station_kit.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")
const LabArt := preload("res://scripts/station_lab_art.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, kafle, etykiety

func _init(panel: Control) -> void:
	ui = panel

## Pracownia i tokarka (ST-05, ST-06): prawa kolumna (słoje z próbkami i odczyt części / zlecenie na szpikulcu) i szlifierka pod kaflami.
func _build_lab_lathe(left: VBoxContainer, body: HBoxContainer) -> void:
	ui._arms_side = VBoxContainer.new()
	ui._arms_side.add_theme_constant_override("separation", 10)
	ui._arms_side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui._arms_side.visible = false
	body.add_child(ui._arms_side)
	var jp = PanelContainer.new()
	jp.add_theme_stylebox_override("panel", UiTheme.panel_box())
	var jv = VBoxContainer.new()
	jv.add_theme_constant_override("separation", 4)
	jp.add_child(jv)
	ui._jars_cap = UiTheme.mono(UiTheme.label("", 8, UiTheme.MUTED))
	jv.add_child(ui._jars_cap)
	ui._jars = LabArt.Jars.new()
	jv.add_child(ui._jars)
	ui._arms_side.add_child(jp)
	jp.set_meta("lab", true)
	ui._printout = PanelContainer.new()                      # odczyt części: wydruk z perforacją
	ui._printout.add_theme_stylebox_override("panel", LabArt.printout_box())
	ui._printout.add_child(LabArt.Perforation.new())
	var pv = VBoxContainer.new()
	pv.add_theme_constant_override("separation", 3)
	ui._printout.add_child(pv)
	ui._printout_head = UiTheme.label("", 10, LabArt.printout()["ink"])
	ui._printout_head.add_theme_font_override("font", UiTheme.note_font(NotePaletteRef.Note.PRINTOUT))
	ui._printout_head.add_theme_constant_override("outline_size", 0)
	pv.add_child(ui._printout_head)
	ui._printout.set_meta("body", pv)
	ui._printout.set_meta("lab", true)
	ui._arms_side.add_child(ui._printout)
	ui._order = ServiceArt.Scrawl.new()                      # zlecenie odręczne nabite na szpikulec
	(ui._order as ServiceArt.Scrawl).stains = false
	ui._order.rotation_degrees = 1.5
	ui._order.custom_minimum_size.x = 150
	ui._order_box = VBoxContainer.new()
	ui._order_box.add_theme_constant_override("separation", 1)
	ui._order.add_child(ui._order_box)
	ui._order_stamp = StationKit.Stamp.new()
	ui._order.add_child(ui._order_stamp)
	var spike = LabArt.Spike.new()
	ui._arms_side.add_child(spike)
	spike.set_meta("lathe", true)
	ui._arms_side.add_child(ui._order)
	ui._order.set_meta("lathe", true)
	ui._grinder = PanelContainer.new()                       # szlifierka: ostrze broni białej, iskry tylko w trakcie
	ui._grinder.add_theme_stylebox_override("panel", UiTheme.panel_box())
	var gv = VBoxContainer.new()
	gv.add_theme_constant_override("separation", 3)
	ui._grinder.add_child(gv)
	gv.add_child(UiTheme.mono(UiTheme.label(tr("GRINDER"), 8, UiTheme.MUTED)))
	ui._grinder_text = UiTheme.label("", 9, UiTheme.TEXT)
	gv.add_child(ui._grinder_text)
	var track = ColorRect.new()
	track.color = Color("23221d")
	track.custom_minimum_size = Vector2(ui.COLS * ui.TILE_W - 30.0, 5)
	gv.add_child(track)
	ui._grinder_bar = ColorRect.new()
	ui._grinder_bar.color = UiTheme.BONE_DIM
	ui._grinder_bar.size = Vector2(0, 5)
	track.add_child(ui._grinder_bar)
	ui._sparks = LabArt.Sparks.new()
	gv.add_child(ui._sparks)
	ui._grinder.visible = false
	left.add_child(ui._grinder)

## Pracownia i tokarka: akta z zaczernieniami i korek (pracownia), rysunek, zlecenie, rulony schematów i szlifierka (tokarka), wydruk
## odczytu w prawej kolumnie. Wołane z `_refresh_detail` po wypełnieniu karty.
func _dress_lab_lathe(w: int, o: Dictionary) -> void:
	var lab = ui._mode == "lab"
	var lathe = ui._mode == "lathe"
	var base: RefCounted = Weapons.base_def(w)
	var key = String(base.key)
	var part = not o.is_empty() and String(o.get("slot", "")) != "service" and String(o.get("id", "")) != ""
	ui._arms_side.visible = lab or lathe
	for c in ui._arms_side.get_children():
		c.visible = (lab and c.has_meta("lab")) or (lathe and c.has_meta("lathe") and part)
	ui._cork.visible = lab and part
	ui._dossier_head.visible = lab
	ui._redacted.visible = lab
	ui._legacy_stage.visible = not ((lab and part) or (lathe and part))
	ui._blueprint.visible = lathe and part
	ui._grinder.visible = lathe and base.is_melee()
	# rulony schematów (tokarka): lista części przy kaflach zamiast na rysunku
	var want: Control = ui._arms_left if lathe else ui._arms_detail
	if ui._d_tiers.get_parent() != want:
		ui._d_tiers.reparent(want)
		if not lathe:
			ui._arms_detail.move_child(ui._d_tiers, ui._d_text.get_index())
	if lathe:                                              # nagłówki gniazd przy rulonach w kolorach blatu
		for c in ui._d_tiers.get_children():
			if c is Label:
				(c as Label).add_theme_color_override("font_color", UiTheme.MUTED)
	if not (lab or lathe):
		if ui._d_stats.get_parent() != ui._arms_detail:
			ui._d_stats.reparent(ui._arms_detail)
			ui._arms_detail.move_child(ui._d_stats, ui._d_panel.get_index() + 1)
		return
	if lab:
		ui._dossier_head.text = "ОБЪЕКТ 86  ·  ОТДЕЛ 3  ·  " + tr("FILE %s") % String(base.name)
		(ui._redacted as LabArt.Redacted).text = tr("Recovered from █ — do not point at █.")
		ui._redacted.queue_redraw()
		ui._jars_cap.text = tr("SAMPLES  ·  %d") % Scrap.samples
		(ui._jars as LabArt.Jars).count = mini(Scrap.samples, 6)
		# odczyt części na wydruku: porównanie przenosi się z karty na wydruk (kolory wydruku)
		var body: VBoxContainer = ui._printout.get_meta("body")
		if ui._d_stats.get_parent() != body:
			ui._d_stats.reparent(body)
		ui._printout_head.text = "== " + tr("READOUT") + " · " + (tr(String(Parts.get_part(String(o["id"])).get("name", ""))).to_upper() if part else String(base.name)) + " =="
		ui._printout.visible = part and ui._d_stats.get_child_count() > 0
		_recolor_printout(ui._printout)
	if lathe:
		_dress_lathe(w, o, key, part)

## Tokarka: rysunek części (szablon wg gniazda), zlecenie odręczne z pieczątką PRZYJĘTO, gdy część jest na tokarce, szlifierka.
func _dress_lathe(w: int, o: Dictionary, key: String, part: bool) -> void:
	var base: RefCounted = Weapons.base_def(w)
	if base.is_melee():
		var edge = Profile.edge_of(key)
		ui._grinder_text.text = UiTheme.num_text("%s · %s %d%%" % [String(base.name), tr("edge"), int(edge)])
		ui._grinder_bar.size.x = (ui._grinder_bar.get_parent() as Control).custom_minimum_size.x * edge / 100.0
		(ui._sparks as LabArt.Sparks).active = ui._clean_w == w
	if not part:
		return
	var id = String(o["id"])
	var pd = Parts.get_part(id)
	var bp := ui._blueprint as LabArt.Blueprint
	bp.slot = String(o["slot"])
	bp.title = tr(String(pd.get("name", id))).to_upper()
	bp.line2 = "%s · %s · %s" % [String(base.name), ui._slot_label(key, String(o["slot"])).to_upper(), tr("1 PC.")]
	var hsh = absi(hash(id))
	bp.dims = Vector2(30 + hsh % 30, 12 + (hsh / 31) % 20)
	bp.has_schematic = Scrap.schematics.has(id) or Scrap.lathe.has(id) or Scrap.has_part(id)
	bp.queue_redraw()
	ui._clear_children(ui._order_box)
	var pal = NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)
	var hand = UiTheme.note_font(NotePaletteRef.Note.SCRAWL)
	ui._order_box.add_child(UiTheme.mono(UiTheme.ink(tr("WORK ORDER No. %04d") % (417 + hsh % 400), 7, pal["dim"])))
	var nm = UiTheme.ink(tr(String(pd.get("name", id))), 12, pal["ink"])
	nm.add_theme_font_override("font", hand)
	ui._order_box.add_child(nm)
	for r in [[tr("For"), String(base.name)], [tr("Cost"), "%d" % Scrap.machine_price(id)], [tr("Lathe"), "%d / %d" % [Scrap.lathe.size(), Scrap.LATHE_SLOTS]]]:
		var h = HBoxContainer.new()
		var a = UiTheme.ink(String(r[0]), 8, pal["dim"])
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UiTheme.ink(String(r[1]), 8, pal["ink"]))
		ui._order_box.add_child(h)
	ui._order_box.add_child(UiTheme.ink(tr("Collect after a successful mission"), 7, pal["dim"]))
	var st := ui._order_stamp as StationKit.Stamp
	if Scrap.lathe.has(id):
		st.hold(tr("ACCEPTED"))
	else:
		st.hold("")

## Napisy pod wydrukiem / rysunkiem: kolory atramentu na papierze zamienione na kolory wydruku (zielony na ciemnym).
func _recolor_printout(root: Node) -> void:
	var p = LabArt.printout()
	var map = {UiTheme.INK: p["ink"], UiTheme.INK_MUTED: p["dim"], UiTheme.INK_GAIN: p["ink"], UiTheme.INK_COST: Color("e3b46e"), UiTheme.INK_PRICE: p["dim"]}
	for n in root.find_children("*", "Control", true, false):
		if n is Label or n is Button:
			var c := n as Control
			if c.has_theme_color_override("font_color"):
				var col = c.get_theme_color("font_color")
				if map.has(col):
					c.add_theme_color_override("font_color", map[col])

## Pracownia / tokarka: droga części broni specjalnej PRÓBKI › BADANIE › SCHEMAT › TOKARKA › ŁAWA — zrobione kroki zielone, bieżący z paskiem,
## pod spodem jedno zdanie, co dalej (dawniej trzeba było to wyczytać z nawiasów przy częściach).
func _fill_lab_chain(key: String, slot: String, id: String) -> void:
	if id == "" or not Scrap.is_lab_part(id):
		return
	var rc = Scrap.research_cost(id)
	var step = 0
	var busy = false
	var note = ""
	if Scrap.has_part(id):
		step = 5 if Profile.fitted(key, slot) == id else 4
		note = tr("Fitted to your gun.") if step == 5 else tr("Part made — fit it at the workshop bench.")
	elif Scrap.lathe.has(id):
		step = 3
		busy = true
		note = tr("On the lathe — ready after a successful mission.")
	elif Scrap.schematics.has(id):
		step = 3
		note = tr("Schematic ready — make the part on the lathe.")
	elif Scrap.research.has(id):
		step = 1
		busy = true
		note = tr("Being researched — ready after a successful mission.")
	elif Scrap.samples >= rc.x:
		step = 1
		note = tr("You have %s — enough to research it at the lab.") % ui._samples_text(Scrap.samples)
	else:
		note = tr("Research needs %s, you have %d. Elites, bosses and side goals drop samples.") % [ui._samples_text(rc.x), Scrap.samples]
	if ui._mode == "lab":                                     # tablica korkowa (ST-05): kartki kroków na pinezkach, czerwona nić
		var subs = [tr("%d in jars") % Scrap.samples, tr("here"), tr("printout"), "ST-06", tr("fitting")]
		var steps: Array = []
		for i in ui.LAB_STEPS.size():
			steps.append([tr(ui.LAB_STEPS[i]), subs[i]])
		var ck := ui._cork as LabArt.CorkChain
		ck.steps = steps
		ck.step = step
		ck.busy = busy
		ck.queue_redraw()
		var nl = UiTheme.ink(note, 8)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = ui.DETAIL_W
		ui._d_panel.add_child(nl)
		return
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for i in ui.LAB_STEPS.size():
		if i > 0:
			row.add_child(UiTheme.ink("›", 8, UiTheme.INK_MUTED))
		var done = i < step
		var cell = PanelContainer.new()
		var box = StyleBoxFlat.new()
		box.bg_color = UiTheme.PAPER_SEL if i == step else Color(0, 0, 0, 0)
		box.set_content_margin_all(1)
		box.content_margin_left = 3
		box.content_margin_right = 3
		cell.add_theme_stylebox_override("panel", box)
		cell.add_child(UiTheme.ink(tr(ui.LAB_STEPS[i]) + ("…" if busy and i == step else ""), 8, UiTheme.INK_GAIN if done else (UiTheme.INK if i == step else UiTheme.INK_MUTED)))
		row.add_child(cell)
	ui._d_panel.add_child(row)
	var l = UiTheme.ink(note, 8)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = ui.DETAIL_W
	ui._d_panel.add_child(l)
