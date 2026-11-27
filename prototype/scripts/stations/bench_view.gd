extends RefCounted
## Zakładka ARMS (WORKSHOP_IMMERSION_PLAN.md R0.3): kafle broni, karta szczegółów z porównaniem, ława rusznikarza (GunsmithPanel —
## gniazda, części, zestawy) i papierowe wiersze karty. Wspólna dla ławy, konserwacji, pracowni i tokarki (MODE_PAGES — strona 0).
## Wydzielone z workshop_ui.gd bez zmiany zachowania, jak widoki z 1.7.420: stan panelu (kafle, etykiety, wybór) zostaje
## w workshop_ui.gd, tu jest budowa i wypełnianie; `ui` to panel. Po funkcje, z których korzysta panel, inne widoki albo testy,
## panel sięga funkcjami o tych samych nazwach.

const Actions := preload("res://scripts/actions.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Codex := preload("res://scripts/codex.gd")
const Controller := preload("res://scripts/weapon_controller.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const LabArt := preload("res://scripts/station_lab_art.gd")
const Parts := preload("res://scripts/parts.gd")
const StationKit := preload("res://scripts/station_kit.gd")
const StationNoise := preload("res://scripts/station_noise.gd")
const Throwables := preload("res://scripts/throwables.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const WeaponDefinition := preload("res://scripts/weapon_def.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Widgets := preload("res://scripts/stations/station_widgets.gd")
const GunsmithPanel := preload("res://scripts/gunsmith_panel.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, kafle, etykiety

func _init(panel: Control) -> void:
	ui = panel

func _make_tile(w: int, idx: int) -> Widgets.Tile:
	var t := Widgets.Tile.new()
	t.weapon = w
	var ic := GunIcon.new()
	var d: RefCounted = Weapons.base_def(w)
	ic.plate = true
	ic.k = 0.3
	ic.set_gun(int(d.gun_row), d.tracer_color, Color.WHITE)
	_dress_tile(t, ic, String(d.name))
	_add_bar(t, Widgets.TierBar.new())
	t.pressed.connect(ui._select.bind(idx))
	return t

## Wspólna ramka kafla: style stanów, miniatura w polu po lewej, nazwa i (pusta) linia stanu. Wysoki kafel (wygląd) — obie linie wyśrodkowane.
func _dress_tile(t: Widgets.CardTile, icon: Control, title: String) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	icon.position = Vector2(4, 5)
	icon.size = Vector2(54, t.custom_minimum_size.y - 10.0)
	t.add_child(icon)
	t.icon_node = icon
	var mid = (t.custom_minimum_size.y - ui.TILE_H) * 0.5
	t.name_label = UiTheme.label(title, 10, UiTheme.TEXT)
	t.name_label.position = Vector2(64, 6.0 + mid)
	t.add_child(t.name_label)
	t.state_label = UiTheme.label("", 8, UiTheme.MUTED)
	t.state_label.position = Vector2(64, 25.0 + mid)
	t.add_child(t.state_label)

## Cena z monetą w linii stanu (zaopatrzenie).
func _add_price(t: Widgets.CardTile) -> void:
	t.coin = Widgets.Coin.new()
	t.coin.position = Vector2(64, 26)
	t.add_child(t.coin)
	t.price_label = UiTheme.label("", 10, ui.GOLD)
	t.price_label.position = Vector2(76, 23)
	t.add_child(t.price_label)

## Jedyny wskaźnik kafla: kropki przy prawej krawędzi.
func _add_bar(t: Widgets.CardTile, bar: Control) -> void:
	t.bar = bar
	t.add_child(bar)
	t.place_bar()

func _build_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	ui._arms_detail = v
	ui._cork = LabArt.CorkChain.new()                        # pracownia (ST-05): tablica korkowa z łańcuchem kroków
	ui._cork.visible = false
	v.add_child(ui._cork)
	ui._dossier_head = UiTheme.mono(UiTheme.ink("", 7, UiTheme.INK_MUTED))       # akta Obiektu 86 (sprzęt bunkra — cyrylica, D1a)
	ui._dossier_head.visible = false
	v.add_child(ui._dossier_head)
	ui._redacted = LabArt.Redacted.new()
	ui._redacted.color = UiTheme.INK
	ui._redacted.visible = false
	v.add_child(ui._redacted)
	ui._blueprint = LabArt.Blueprint.new()                   # tokarka (ST-06): rysunek części z drukarki zamiast sceny z bronią
	ui._blueprint.visible = false
	v.add_child(ui._blueprint)
	ui._d_stage = GunStage.new()
	ui._d_stage.custom_minimum_size = Vector2(0, 76)
	v.add_child(ui._d_stage)
	ui._d_title = _ink_heading()
	v.add_child(ui._d_title)
	ui._d_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(ui._d_tag)
	ui._d_panel = VBoxContainer.new()
	ui._d_panel.add_theme_constant_override("separation", 3)
	v.add_child(ui._d_panel)
	ui._d_stats = GridContainer.new()
	ui._d_stats.columns = 4                                  # parametr | teraz | → po zmianie | korzyść / koszt
	ui._d_stats.add_theme_constant_override("h_separation", 10)
	ui._d_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(ui._d_stats)
	v.add_child(_paper_rule())
	ui._d_tiers = VBoxContainer.new()
	ui._d_tiers.add_theme_constant_override("separation", 1)
	v.add_child(ui._d_tiers)
	ui._d_text = UiTheme.ink("", 8)
	ui._d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._d_text.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	v.add_child(ui._d_text)
	ui._action = Button.new()
	ui._action.focus_mode = Control.FOCUS_NONE
	ui._action.add_theme_font_size_override("font_size", 10)
	ui._action.add_theme_color_override("font_disabled_color", UiTheme.BONE_DIM)     # wyłączona akcja niesie podpowiedź („wybierz gniazdo”)
	ui._action.pressed.connect(ui._act)
	v.add_child(ui._action)
	return v

## Opcje części broni `w` w kolejności gniazd: [{slot, id}] — id "" to element fabryczny gniazda. Na końcu „SERVICE / clean”: czyszczenie
## broni przy ławie (etap 4a GUNSMITH_PLAN — stan techniczny), gdy broń jest kupiona, strzela i niezawodność nie jest wyłączona.
func _options(w: int) -> Array:
	var key := String(Weapons.def(w).key)
	var out: Array = []
	if ui._mode == "lathe":
		if Scrap.is_unlocked(w) and Weapons.def(w).is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "sharpen"})        # szlifierka: ostrze broni białej
		elif key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if ui._mode == "lab":
		if key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if ui._mode == "service":
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

## Stan wspólnej pracy, także gdy panel pokazuje inną broń.
func _queue_summary(skip_batches := false) -> String:
	var lines: Array[String] = []
	for entry in [[tr("Research"), Scrap.research], [tr("Machining"), Scrap.lathe]]:
		for id in entry[1]:
			lines.append(tr("%s: %s — after a successful mission") % [String(entry[0]), tr(String(Parts.get_part(String(id)).get("name", id)))])
	for id in Scrap.schematics:
		if not Scrap.lathe.has(id):
			lines.append(tr("Schematic: %s — take to the lathe") % tr(String(Parts.get_part(String(id)).get("name", id))))
	for kind in ([] if skip_batches else Scrap.orders):          # prasa pokazuje partie w swoich miejscach (_fill_press_queue)
		lines.append(tr("Batch: %s — after a successful mission") % tr(String(Throwables.KINDS[String(kind)]["name"])))
	for kind in Scrap.deliveries:
		var station := tr("PYROTECHNICS") if Scrap.supply_station(String(kind)) == "pyro_bench" else tr("RELOADING PRESS")
		lines.append(tr("Ready: %s · %d rounds — collect at %s") % [tr(String(Throwables.KINDS[String(kind)]["name"])), int(Scrap.deliveries[kind]), station])
	return "\n".join(lines)

func _slot_label(key: String, slot: String) -> String:
	return tr(String(ui.SLOT_LABELS.get("%s:%s" % [key, slot], Parts.SLOT_NAMES[slot])))

## Te same dane broni dla obu kolumn; porównanie nie zakłada naboju standardowego.
func _comparison_rows(d: RefCounted) -> Array:
	var rows: Array = Codex._weapon_stats(d)
	for row in rows:
		match String(row[0]):
			"Magazine":
				row[1] = "%d%s" % [d.mag, "+1" if d.chamber else ""]
			"Damage":
				if d.kind == WeaponDefinition.Kind.LAUNCHER:
					row[1] = tr("%d blast") % int(d.blast_damage)
				elif d.pellets > 1:
					row[1] = tr("%d × %d pellets") % [int(d.damage), d.pellets]
				elif d.is_continuous():
					row[1] = tr("%d / tick") % int(d.damage)
			"Fire rate":
				if d.is_continuous():
					row[1] = tr("continuous")
				elif d.kind == WeaponDefinition.Kind.RAIL:
					row[1] = tr("%.1f s charge") % d.charge_time
			"Reload":
				if d.reload_per_round:
					row[1] = tr("%.2f s / round") % d.reload_time
			"Noise":
				if d.n_max <= 0.0:
					row[1] = tr("silent")
		row[0] = tr(String(row[0]))
	if d.uses_ammo():
		rows.append([tr("Shared reserve"), "∞" if d.infinite else "%d" % Arsenal.get_reserve(d.id, d.ammo)])
	rows.append([tr("Draw"), tr("%.2f s") % d.draw_time])
	if not d.is_melee():
		rows.append([tr("Spread"), "±%.2f°" % d.jitter_deg + (" / ±%.2f°" % d.spread_deg if d.pellets > 1 else "")])
		rows.append([tr("Bloom"), "+%.2f° / %.2f°" % [d.bloom_per_shot, d.bloom_max]])
		rows.append([tr("Recoil"), "%.2f / %.2f" % [d.cam_kick, d.recoil]])
		rows.append([tr("Penetration"), _penetration_text(d)])
		rows.append([tr("Armour bypass"), "%d%%" % int(d.armor_pen * 100.0)])
		rows.append([tr("Heating"), "%.1f%% / %.1f%%" % [d.barrel_heat * 100.0, d.heat_gain * 100.0]])
	var fields := {}
	for part in Parts.of(String(d.key)):
		for modifier in part.get("mods", []):
			fields[String(modifier[0])] = true
	for field in ui.PART_METRICS:
		if not fields.has(field):
			continue
		var spec: Array = ui.PART_METRICS[field]
		var value := float(d.get(field))
		var text := (tr("Yes") if value != 0 else tr("No")) if spec[1] == "bool" else String(spec[1]) % (value * float(spec[2]))
		rows.append([tr(String(spec[0])), text])
	return rows

## Przebicie zrozumiale: energia kuli w przeszkodach (skrzynia, ciało) i dodatkowe cele promienia, szyny, bełtu (dawniej „0,00 / 1”).
func _penetration_text(d: RefCounted) -> String:
	var parts: Array = []
	if d.pen > 0.0:
		parts.append(tr("%.1f obstacles") % d.pen)
	if d.pierce > 0:
		parts.append(tr_n("+%d target", "+%d targets", d.pierce) % d.pierce)          # formy mnogie: translations/plural.csv
	return " · ".join(parts) if not parts.is_empty() else "—"

## Wiersz z paskiem na papierowej karcie: etykieta, pasek, napis wartości.
func _paper_bar(label: String, frac: float, value: String, col: Color, cap := -1.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UiTheme.ink(label, 9, UiTheme.INK_MUTED)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	var bar := Widgets.PaperBar.new()
	bar.custom_minimum_size.x = 90
	bar.frac = frac
	bar.cap = cap
	bar.col = col
	h.add_child(bar)
	var v := UiTheme.ink(UiTheme.num_text(value), 9, col, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size.x = 100
	h.add_child(v)
	ui._d_panel.add_child(h)

## Część polecana na pierwszy zakup: dopóki drużyna nie ma żadnej, ława pokazuje jedną konkretną rzecz zamiast całego katalogu (WORKSHOP_PLAN.md §6). "" = nic nie polecamy.
func _first_pick() -> String:
	return ui.FIRST_PICK if ui._mode == "bench" and Scrap.parts.is_empty() and Scrap.is_unlocked(Weapons.M83) else ""

func _first_part_opt() -> int:
	if ui._mode == "bench":
		if _first_pick() != "" and int(ui.LIST[ui._sel]) == Weapons.M83:
			var pick_ops := _options(Weapons.M83)
			for i in pick_ops.size():
				if String(pick_ops[i]["id"]) == ui.FIRST_PICK:
					return i
		return -1
	var ops := _options(int(ui.LIST[ui._sel]))
	if ui._mode == "service":                                # stół konserwacji: kursor od razu na tym, co zalecane
		var adv = ui._service_advice(int(ui.LIST[ui._sel]))
		for i in ops.size():
			if not adv.is_empty() and String(ops[i]["id"]) == String(adv["id"]):
				return i
	for i in ops.size():
		if String(ops[i]["id"]) != "":
			return i
	return 0

## Zestaw pod kursorem: zapisuje bieżący montaż broni (nadpisuje). Poza wierszem zestawu nic nie robi.
func _save_preset() -> void:
	if ui._page != 0:
		return
	var w: int = ui.LIST[ui._sel]
	var ops := _options(w)
	if ops.is_empty():
		return
	var o: Dictionary = ops[clampi(ui._opt, 0, ops.size() - 1)]
	if String(o["slot"]) != "preset":
		return
	Profile.save_preset(String(Weapons.def(w).key), int(o["id"]))
	ui._success_fx(-6.0)
	ui._say(tr("Current fit saved as set %d.") % (int(o["id"]) + 1), UiTheme.OK)
	ui._refresh()

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

func _refresh_tile(t: Widgets.Tile, selected: bool) -> void:
	var w := t.weapon
	t.set_lit(selected)
	var unlocked := Scrap.is_unlocked(w)
	var later := Scrap.is_later(w)
	(t.icon_node as GunIcon).set_gun(int(Weapons.base_def(w).gun_row), Weapons.base_def(w).tracer_color, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
	t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if selected else (UiTheme.TEXT if unlocked else UiTheme.MUTED))
	t.bar.visible = false
	if t.marks != null:
		t.marks.visible = false                       # ikonki wymian tylko na stole konserwacji (włącza je gałąź „service” niżej)
	t.state_label.add_theme_color_override("font_color", UiTheme.MUTED)
	# Kafle są tylko na stanowiskach pomocniczych (ława ma własny stojak): broń kupuje się wyłącznie przy ławie, więc bez ceny.
	# Linia stanu mówi to, co liczy się PRZY TYM stanowisku: stół konserwacji — stan, szlifierka — ostrze, reszta — odblokowane części.
	if unlocked:
		var key := String(Weapons.def(w).key)
		var melee: bool = Weapons.base_def(w).is_melee()
		var total := Parts.of(key).size()
		var owned := Scrap.parts_owned(w)
		t.tooltip_text = tr("Unlocked parts: %d / %d. Equipment is chosen separately.") % [owned, total]
		if ui._mode == "service" and not melee:
			var cond := Profile.condition(key)
			t.state_label.text = (tr("Condition %d%%") % int(cond)).to_upper()
			t.state_label.add_theme_color_override("font_color", UiTheme.DANGER if cond < 70.0 else (ui.GOLD if cond < 95.0 else UiTheme.OK))
			t.tooltip_text = tr("Below 70% a gun starts to jam.")
			# ikonki części do wymiany (lufa, sprężyny) w miejscu kropek części — na stole konserwacji kropek nie ma
			var tile := t as Widgets.Tile
			if tile != null:
				if tile.marks == null:
					tile.marks = Widgets.ServiceMarks.new()
					tile.marks.position = Vector2(ui.TILE_W - 6.0 - tile.marks.size.x, ui.TILE_H - 19.0)
					tile.add_child(tile.marks)
				for pid in Profile.WEAR_PARTS:
					var pw := Profile.part_wear(key, String(pid))
					var st := 0 if not (Weapons.def(w).can_jam() and Profile.service_due(key, String(pid))) else (2 if pw >= Profile.SERVICE_URGENT else 1)
					tile.marks.set(String(pid), st)
				tile.marks.visible = true
				tile.marks.queue_redraw()
		elif ui._mode == "lathe" and melee:
			t.state_label.text = (tr("Edge %d%%") % int(Profile.edge_of(key))).to_upper()
		else:
			t.state_label.text = tr("PARTS") if total > 0 else ""
			t.bar.visible = total > 0
			t.bar.set("level", owned)
			t.bar.set("total", total)
			t.bar.set("maxed", owned >= total)
			t.place_bar()
			t.bar.queue_redraw()
	elif later:
		t.state_label.text = tr("BOSS REWARD") if Scrap.is_gated(w) else tr("LATER ZONE")
	else:
		t.state_label.text = tr("BUY AT THE BENCH")

func _refresh_detail(w: int) -> void:
	ui._service_skin(ui._mode == "service")
	ui._action.disabled = false
	_act_state(ui._action, "", 0)
	var base: RefCounted = Weapons.base_def(w)
	var key := String(base.key)
	var unlocked := Scrap.is_unlocked(w)
	var ops := _options(w)
	ui._opt = clampi(ui._opt, -1 if ui._mode == "bench" else 0, maxi(ops.size() - 1, 0))
	var mine := Profile.fit_code(w)
	var controller = ui._local_wc()
	var ammo_type: int = controller.ammo_of(w) if controller != null else 0
	var cur: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, mine))
	# podgląd: broń z częścią spod kursora zamontowaną w jej gnieździe (reszta jak teraz)
	var preview: RefCounted = null
	var o: Dictionary = ops[ui._opt] if not ops.is_empty() and ui._opt >= 0 else {}
	if ui._mode == "bench" and not o.is_empty():
		ui._bench_slot = String(o["slot"])
	if unlocked and not o.is_empty() and String(o["id"]) != "" and not String(o["slot"]) in ["preset", "service"]:
		Profile.mark_seen("part:" + String(o["id"]))          # część pod kursorem jest obejrzana — kropka „nowe” gaśnie
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
	(ui._d_stage as GunStage).show_gun(w, Parts.decode(key, pv_code), String(o.get("id", "")) if hl_part else "", hl_slot, not unlocked)
	(ui._d_stage as GunStage).set_dirt((1.0 - Profile.condition(key) / 100.0) if unlocked and not base.is_melee() else 0.0)   # brud wg stanu broni (W2)
	(ui._d_stage as GunStage).set_strip(ui._clean_w == w)
	ui._d_title.text = String(base.name)
	var tag := tr(Codex._slot_name(base))
	if unlocked and not Parts.of(key).is_empty():
		tag += tr("  ·  UNLOCKED %d / %d") % [Scrap.parts_owned(w), Parts.of(key).size()]
		tag += tr("  ·  FITTED %d") % Parts.decode(key, mine).size()
	elif not unlocked:
		tag += tr("  ·  LOCKED")
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
	if ui._mode == "lab":
		tag += tr("  ·  SAMPLES %d") % Scrap.samples + ((tr(" (+%d this mission)") % Scrap.samples_loot) if Scrap.samples_loot > 0 else "")
	if ui._mode == "bench" and Settings.realistic_handling:
		var lp = ui._local_wc()
		if lp != null:
			var km: float = lp.kit_mass()
			tag += UiTheme.num_text(tr("  ·  KIT %.1f kg  (run noise %+d%%)") % [km, int(round((lp.mass_noise_mult() - 1.0) * 100.0))])   # masa ekwipunku (W5)
	if cur.uses_ammo() and Ammo.name_of(String(cur.caliber), ammo_type) != "":         # ogniwo LR-7 nie ma nazwy naboju
		tag += tr("  ·  AMMO %s") % Ammo.name_of(String(cur.caliber), ammo_type)
	ui._d_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._d_tag.custom_minimum_size.x = ui.DETAIL_W
	ui._d_tag.text = tag
	var jobs := _queue_summary()
	if jobs != "":
		ui._d_tag.text += "\n" + jobs
	# statystyki: broń, jaką masz teraz, i ta sama z częścią spod kursora (złote wartości — zmiany względem bieżącego montażu)
	for ch in ui._d_stats.get_children():
		ui._d_stats.remove_child(ch)
		ch.free()
	var now_rows: Array = _comparison_rows(cur)
	var next_rows: Array = _comparison_rows(preview) if preview != null else []
	if next_rows.is_empty():
		next_rows = now_rows.duplicate(true)
	if controller != null and controller.carries(w):
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
		ui._d_stats.add_child(UiTheme.ink(String(r[0]), 9, UiTheme.INK_MUTED))
		ui._d_stats.add_child(UiTheme.ink(UiTheme.num_text(String(r[1])), 9))
		# zmiana: nowa wartość i słowna ocena („korzyść” / „koszt” — od 1.7.460; kompromisem jest cała część, nie jeden parametr) — kolor tylko ją wzmacnia. Strzałka „→” nie ocenia: więcej
		# nie zawsze znaczy lepiej (masa, grzanie), więc ↑ / ↓ myliłyby kierunek liczby z oceną.
		var nv := ""
		var verdict := ""
		var kind := 0
		if i < next_rows.size() and String(next_rows[i][1]) != String(r[1]):
			kind = _change_kind(String(r[0]), cur, preview) if preview != null else 0
			nv = "→ %s" % String(next_rows[i][1])
			verdict = tr("Gain") if kind > 0 else (tr("Cost") if kind < 0 else "")
		var col := UiTheme.INK_GAIN if kind > 0 else (UiTheme.INK_COST if kind < 0 else UiTheme.INK)
		ui._d_stats.add_child(UiTheme.ink(UiTheme.num_text(nv), 9, col))
		ui._d_stats.add_child(UiTheme.ink(verdict.to_lower(), 7, col))
	ui._clear_children(ui._d_panel)
	if unlocked and (ui._mode == "service" or (ui._mode == "lathe" and base.is_melee())):          # szlifierka: pasek ostrza
		ui._clear_children(ui._d_stats)                         # przy czyszczeniu liczy się stan i zużycie, nie 22 parametry balistyczne
		ui._fill_service_panel(base, cur)
	elif (ui._mode == "lab" or ui._mode == "lathe") and not o.is_empty() and String(o["slot"]) != "service":
		ui._fill_lab_chain(key, String(o["slot"]), String(o["id"]))
	# części w gniazdach: nagłówek gniazda, element fabryczny i części (zamontowana — zielona, odblokowana — atrament, do kupienia — z ceną)
	for ch in ui._d_tiers.get_children():
		ui._d_tiers.remove_child(ch)
		ch.queue_free()                  # wiersz może właśnie obsługiwać swoje kliknięcie (_pick_opt) — natychmiastowe free() jest wtedy błędem
	var last_slot := ""
	for i in ops.size():
		var op: Dictionary = ops[i]
		var slot := String(op["slot"])
		if slot != last_slot:
			last_slot = slot
			var head_txt := tr("Service") if slot == "service" else (tr("Sets") if slot == "preset" else _slot_label(String(Weapons.def(int(ui.LIST[ui._sel])).key), slot))
			ui._d_tiers.add_child(UiTheme.ink(head_txt.to_upper(), 7, UiTheme.INK_MUTED))
		if slot == "preset":
			var pi := int(op["id"])
			var pfit := Profile.is_preset_fitted(key, pi)
			_tier_row(i, tr("Set %d  ·  %s") % [pi + 1, _preset_summary(key, pi)],
				tr("empty") if Profile.preset(key, pi).is_empty() else (tr("fitted") if pfit else tr("saved")), UiTheme.INK_GAIN if pfit else UiTheme.INK)
			continue
		if slot == "service":
			var cc := Profile.clean_time(key)
			var sid := String(op["id"])
			var pw := Profile.part_wear(key, sid) if sid != "clean" else 0.0
			var due := (cc > 0.0) if sid == "clean" else Profile.service_due(key, sid)
			var cap := Profile.clean_cap(key)
			if sid == "sharpen":
				var st := Profile.sharpen_time(key)
				_tier_row(i, tr("Sharpen  ·  edge %d%%") % int(Profile.edge_of(key)), tr("%d s") % ceili(st) if st > 0.0 else tr("sharp"), UiTheme.INK_COST if st > 0.0 else UiTheme.INK_GAIN)
			elif sid == "clean":
				var ctxt := (tr("Clean  ·  condition %d%%") % int(Profile.condition(key))) if cap >= 99.5 else (tr("Clean  ·  condition %d%% (max %d%%)") % [int(Profile.condition(key)), int(cap)])
				_tier_row(i, ctxt, tr("%d s") % ceili(cc) if cc > 0.0 else tr("clean"), UiTheme.INK_COST if due else UiTheme.INK_GAIN)
			else:
				var pname := tr("Barrel") if sid == "barrel" else tr("Springs")
				# poniżej progu bez ceny (nie da się wymienić), od progu cena, od SERVICE_URGENT cena w kolorze kosztu
				var ptail := tr("%d scrap") % int(Scrap.SERVICE_COST[sid]) if due else (tr("like new") if pw < 0.5 else tr("from %d%%") % int(Profile.SERVICE_DUE))
				var pcol := (UiTheme.INK_COST if pw >= Profile.SERVICE_URGENT else UiTheme.INK_PRICE) if due else (UiTheme.INK_GAIN if pw < 0.5 else UiTheme.INK_MUTED)
				_tier_row(i, tr("%s  ·  worn %d%%") % [pname, int(pw)], ptail, pcol)
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
				tail = (tr("%d scrap") % Scrap.machine_price(id)) if ui._mode == "lathe" else tr("schematic")
			elif Scrap.research.has(id):
				tail = tr("researching")
			elif ui._mode == "lab":
				tail = tr("%s · %d scrap") % [ui._samples_text(rc.x), rc.y]
			else:
				tail = tr("no schematic") if ui._mode == "lathe" else tr("lab")
		elif (ui._mode == "lab" or ui._mode == "lathe") and owned:
			tail = tr("known") if ui._mode == "lab" else tr("made")
		_tier_row(i, nm, tail, UiTheme.INK_GAIN if fitted else (UiTheme.INK if owned else UiTheme.INK_PRICE))
	var notes: Array = Codex.WEAPON_TEXT.get(key, ["", ""])
	var desc := Actions.fmt(tr(String(notes[0])))
	if unlocked and not o.is_empty() and String(o["slot"]) == "preset":
		desc = tr("Your saved sets of parts for this gun (only yours — the squad shares the unlocks, not the build). %s fits the set, %s saves your current fit over it.") % [
			ui._menu_key("menu_accept", Actions.pad_mode), ui._menu_key("menu_alt", Actions.pad_mode)]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "barrel":
		desc = tr("Every shot wears the bore, a hot one three times faster; a worn barrel spreads wider (up to +60%%). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["barrel"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		desc = tr("Every swing dulls the edge a little. A dull blade hurts less — down to %d%% damage when fully blunt. Sharpening costs no scrap, only time at the grinder.") % int(Profile.EDGE_MIN * 100.0)
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "springs":
		desc = tr("Springs tire with every shot; tired ones keep cleaning from restoring the gun fully (100 − half the wear). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["springs"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service":
		desc = tr("Strip and clean the gun: no scrap, only time — the dirtier, the longer. Every shot fouls it (faster hot or suppressed); below 70% it starts to jam.")
	elif unlocked and not o.is_empty() and String(o["id"]) != "":
		desc = tr(String(Parts.get_part(String(o["id"]))["desc"]))
	elif unlocked and not o.is_empty():
		desc = tr("Factory part: no gain, no cost.")
	ui._d_text.text = desc
	# przycisk akcji
	if not unlocked and Scrap.is_later(w):
		ui._action.text = "Reward for the Leech" if Scrap.is_gated(w) else "Available in a later zone"
		_act_state(ui._action, "wait", 0)
	elif not unlocked:
		ui._action.text = tr("Buy it at the workshop bench") if ui._mode in ["service", "lab", "lathe"] else tr("Buy  ·  %d scrap") % Scrap.price_of(w)
		_act_state(ui._action, "wait" if ui._mode in ["service", "lab", "lathe"] else "ready", 0 if ui._mode in ["service", "lab", "lathe"] else Scrap.price_of(w))
	elif o.is_empty():
		ui._action.text = tr("Nothing to service") if ui._mode == "service" else (tr("Nothing to research — not a special weapon") if ui._mode == "lab" else (tr("Nothing for the lathe") if ui._mode == "lathe" else "No parts for this weapon"))
		_act_state(ui._action, "wait", 0)
	elif String(o["slot"]) == "preset":
		var api := int(o["id"])
		if Profile.preset(key, api).is_empty():
			ui._action.text = tr("Save current fit as set %d") % (api + 1)
		elif Profile.is_preset_fitted(key, api):
			ui._action.text = tr("Set %d fitted  ·  %s overwrite") % [api + 1, ui._menu_key("menu_alt", Actions.pad_mode)]
		else:
			ui._action.text = tr("Fit set %d  ·  %s overwrite") % [api + 1, ui._menu_key("menu_alt", Actions.pad_mode)]
	elif String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		var stime := Profile.sharpen_time(key)
		if ui._clean_w == w:
			ui._action.text = tr("Sharpening…  %d%%  (again to stop)") % int(100.0 * ui._clean_t / maxf(0.01, ui._clean_total))
			_act_state(ui._action, "busy", 0)
		else:
			ui._action.text = tr("Sharpen  ·  %d s") % ceili(stime) if stime > 0.0 else tr("Already sharp")
			_act_state(ui._action, "wait" if stime <= 0.0 else "ready", 0)
	elif String(o["slot"]) == "service" and String(o["id"]) in Profile.WEAR_PARTS:
		# skutek wymiany w liczbach (lufa: rozrzut, sprężyny: granica czyszczenia); poniżej progu przycisk wygaszony z progiem
		var sid2 := String(o["id"])
		var pw2 := Profile.part_wear(key, sid2)
		if not Profile.service_due(key, sid2):
			ui._action.text = tr("Like new") if pw2 < 0.5 else tr("Still serviceable  ·  replace from %d%% wear") % int(Profile.SERVICE_DUE)
			_act_state(ui._action, "wait", 0)
			ui._action.disabled = true
		elif sid2 == "barrel":
			ui._action.text = tr("Replace barrel  ·  %d scrap  ·  spread +%d%% → +0%%") % [int(Scrap.SERVICE_COST[sid2]), int(round(Controller.BARREL_SPREAD * pow(pw2 / 100.0, 2.0) * 100.0))]
			_act_state(ui._action, "ready", int(Scrap.SERVICE_COST[sid2]))
		else:
			ui._action.text = tr("Replace springs  ·  %d scrap  ·  cleans to %d%% → 100%%") % [int(Scrap.SERVICE_COST[sid2]), int(Profile.clean_cap(key))]
			_act_state(ui._action, "ready", int(Scrap.SERVICE_COST[sid2]))
	elif String(o["slot"]) == "service":
		var ctime := Profile.clean_time(key)
		if ui._clean_w == w:
			ui._action.text = tr("Cleaning…  %d%%  (again to stop)") % int(100.0 * ui._clean_t / maxf(0.01, ui._clean_total))
			_act_state(ui._action, "busy", 0)
		else:
			ui._action.text = tr("Clean  ·  %d s") % ceili(ctime) if ctime > 0.0 else tr("Already clean")
			_act_state(ui._action, "wait" if ctime <= 0.0 else "ready", 0)
	else:
		var id2 := String(o["id"])
		if ui._mode == "lathe":
			if Scrap.has_part(id2):
				ui._action.text = tr("Made  ·  fit it at the bench")
				_act_state(ui._action, "wait", 0)
			elif Scrap.lathe.has(id2):
				ui._action.text = tr("On the lathe  ·  ready after the mission")
				_act_state(ui._action, "busy", 0)
			elif not Scrap.schematics.has(id2):
				ui._action.text = tr("No schematic  ·  research it at the lab")
				_act_state(ui._action, "wait", 0)
			elif Scrap.lathe.size() >= Scrap.LATHE_SLOTS:
				ui._action.text = tr_n("The lathe is busy  ·  %d job per mission", "The lathe is busy  ·  %d jobs per mission", Scrap.LATHE_SLOTS) % Scrap.LATHE_SLOTS
				_act_state(ui._action, "busy", 0)
			else:
				ui._action.text = tr("Machine  ·  %d scrap  ·  ready after the mission") % Scrap.machine_price(id2)
				_act_state(ui._action, "ready", Scrap.machine_price(id2))
		elif ui._mode == "lab":
			var rc2 := Scrap.research_cost(id2)
			if Scrap.schematics.has(id2) or Scrap.lathe.has(id2):
				ui._action.text = tr("Researched  ·  make it on the lathe")
				_act_state(ui._action, "wait", 0)
			elif Scrap.has_part(id2):
				ui._action.text = tr("Known  ·  fit it at the bench")
				_act_state(ui._action, "wait", 0)
			elif Scrap.research.has(id2):
				ui._action.text = tr("Researching  ·  ready after the mission")
				_act_state(ui._action, "busy", 0)
			elif Scrap.research.size() >= Scrap.LAB_SLOTS:
				ui._action.text = tr_n("The lab is busy  ·  %d project per mission", "The lab is busy  ·  %d projects per mission", Scrap.LAB_SLOTS) % Scrap.LAB_SLOTS
				_act_state(ui._action, "busy", 0)
			else:
				ui._action.text = tr("Research  ·  %s  ·  %d scrap") % [ui._samples_text(rc2.x), rc2.y]
				_act_state(ui._action, "ready", rc2.y)
		elif id2 != "" and not Scrap.has_part(id2) and Scrap.is_lab_part(id2) and not Scrap.found.has(id2):
			ui._action.text = tr("Research it at the lab")
			_act_state(ui._action, "wait", 0)
		elif id2 != "" and not Scrap.has_part(id2):
			ui._action.text = tr("Buy part  ·  %d scrap") % Scrap.part_cost(id2)
			_act_state(ui._action, "ready", Scrap.part_cost(id2))
		elif Profile.fitted(key, String(o["slot"])) == id2:
			ui._action.text = "Fitted"
			_act_state(ui._action, "wait", 0)
		else:
			ui._action.text = "Fit to my gun" if id2 != "" else "Fit the factory part"
	if ui._mode == "bench":
		_present_bench(w, cur, preview, now_rows, next_rows, ops, o)
	ui._dress_lab_lathe(w, o)
	ui._card.reset_size()

func _bench_slots() -> Array:
	var slots: Array = Parts.slots_of(String(Weapons.def(int(ui.LIST[ui._sel])).key)).duplicate()
	if Scrap.is_unlocked(int(ui.LIST[ui._sel])) and not slots.is_empty():
		slots.append("preset")
	return slots

func _pick_slot(slot: String) -> void:
	if not _bench_slots().has(slot):
		return
	var w := int(ui.LIST[ui._sel])
	var key := String(Weapons.def(w).key)
	var ops := _options(w)
	var fitted := Profile.fitted(key, slot)
	for i in ops.size():
		if String(ops[i]["slot"]) == slot and (slot == "preset" or String(ops[i]["id"]) == fitted):
			ui._pick_opt(i)
			return

func _move_slot(direction: int) -> void:
	var slots := _bench_slots()
	if slots.is_empty():
		return
	_pick_slot(String(slots[posmod(slots.find(ui._bench_slot) + direction, slots.size())]))

func _save_current_preset() -> void:
	if not ui._pending_part.is_empty() or ui._buying >= 0:
		return
	if ui._bench_slot != "preset":
		_pick_slot("preset")
		ui._say(tr("Choose a set, then save your current fit."), UiTheme.TEXT)
		return
	_save_preset()

func _present_committed(w: int, before: int) -> void:
	var key := String(Weapons.def(w).key)
	var after := Profile.fit_code(w)
	if ui._mode == "bench" and ui._page == 0 and int(ui.LIST[ui._sel]) == w:
		ui._opt = -1
		ui._refresh()
		if before != after:
			ui._workbench.stage.animate_mount(w, Parts.decode(key, before), Parts.decode(key, after))
	else:
		ui._refresh()

func _present_bench(w: int, cur: RefCounted, preview: RefCounted, now_rows: Array, next_rows: Array, ops: Array, selected: Dictionary) -> void:
	var key := String(cur.key)
	var unlocked := Scrap.is_unlocked(w)
	var slots: Array = []
	for slot in _bench_slots():
		var fitted := Profile.fitted(key, String(slot))
		var name := tr("Sets") if slot == "preset" else _slot_label(key, String(slot))
		var short_name: String = name if ui.SLOT_LABELS.has("%s:%s" % [key, slot]) else {"stock": tr("Grip") if cur.is_melee() else tr("Stock"), "optic": tr("Sight"), "preset": tr("Sets")}.get(slot, name)
		slots.append({"id": slot, "name": name, "short": short_name,
			"fitted": tr("Factory") if fitted == "" else tr(String(Parts.get_part(fitted)["name"]))})
	if ui._bench_slot == "" and not slots.is_empty():
		ui._bench_slot = String(slots[0]["id"])
	var records: Array = []
	for i in ops.size():
		var op: Dictionary = ops[i]
		if String(op["slot"]) != ui._bench_slot:
			continue
		var id := String(op["id"])
		var name := tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id)))
		var fitted := Profile.fitted(key, String(op["slot"])) == id
		var status := tr("fitted") if fitted else (tr("owned") if id == "" or Scrap.has_part(id) else tr("%d scrap") % Scrap.part_cost(id))
		if String(op["slot"]) == "preset":
			name = tr("Set %d") % (int(id) + 1)
			fitted = Profile.is_preset_fitted(key, int(id))
			status = tr("empty") if Profile.preset(key, int(id)).is_empty() else (tr("fitted") if fitted else tr("saved"))
		elif id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				status = tr("found — extract")
			elif Scrap.is_lab_part(id):
				status = tr("on the lathe") if Scrap.lathe.has(id) else (tr("schematic") if Scrap.schematics.has(id) else (tr("researching") if Scrap.research.has(id) else tr("lab")))
		if id != "" and id == _first_pick():
			status = tr("RECOMMENDED · %d") % Scrap.part_cost(id)           # krótko: karta części jest wąska, pełna cena stoi na przycisku
		var delta := _part_delta(w, cur, String(op["slot"]), id) if String(op["slot"]) != "preset" and not fitted else []
		records.append({"index": i, "name": name, "status": status, "fitted": fitted,
			"new": id != "" and String(op["slot"]) != "preset" and Profile.is_new("part:" + id), "delta": delta})
	var weapons: Array = []
	var wc = ui._local_wc()
	for i in ui.LIST.size():
		var wid := int(ui.LIST[i])
		var definition: RefCounted = Weapons.base_def(wid)
		var carried: bool = wc != null and wc.carries(wid)
		var status := tr("Carried") if carried else (tr("Unlocked") if Scrap.is_unlocked(wid) else (tr("Boss reward") if Scrap.is_gated(wid) else (tr("Later zone") if Scrap.is_later(wid) else tr("%d scrap") % Scrap.price_of(wid))))
		var fresh := Parts.of(String(definition.key)).any(func(pp: Dictionary) -> bool: return Profile.is_new("part:" + String(pp["id"])))
		weapons.append({"index": i, "name": String(definition.name), "row": int(definition.gun_row), "color": definition.tracer_color,
			"status": status, "carried": carried, "selected": i == ui._sel, "new": fresh})
	var rows: Array = []
	for i in now_rows.size():
		rows.append([now_rows[i][0], now_rows[i][1], next_rows[i][1] if i < next_rows.size() else now_rows[i][1],
			_change_kind(String(now_rows[i][0]), cur, preview) if preview != null else 0])
	var part_name := ""
	var id := String(selected.get("id", ""))
	if not selected.is_empty():
		part_name = tr("Set %d") % (int(id) + 1) if String(selected["slot"]) == "preset" else (tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id))))
	var pending = not ui._pending_part.is_empty() or ui._buying >= 0
	ui._action.disabled = pending or (unlocked and selected.is_empty()) or (not unlocked and (Scrap.is_later(w) or Scrap.bank < Scrap.price_of(w)))
	if pending:
		ui._action.text = tr("Waiting for confirmation…")
		_act_state(ui._action, "busy", 0)
	elif unlocked and selected.is_empty():
		ui._action.text = tr("Inspecting · choose a slot or a part")
	elif unlocked and String(selected.get("slot", "")) != "preset":
		if id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				ui._action.text = tr("Found · schematic after extraction") if Scrap.is_lab_part(id) else tr("Found · extract to unlock")
				ui._action.disabled = true
			elif Scrap.is_lab_part(id):
				ui._action.text = tr("Research and make it at the lab / lathe")
				ui._action.disabled = true
			else:
				ui._action.text = tr("Unlock & fit · %d scrap") % Scrap.part_cost(id)
				_act_state(ui._action, "ready", Scrap.part_cost(id))
				ui._action.disabled = Scrap.bank < Scrap.part_cost(id)
		else:
			ui._action.disabled = Profile.fitted(key, String(selected["slot"])) == id
	var meta := tr("Condition %d%%") % int(Profile.condition(key)) if not cur.is_melee() else tr("Edge %d%%") % int(Profile.edge_of(key))
	var kills := Profile.kills(key)
	meta += " · " + tr("Mastery %s") % ["0", "I", "II", "III", "IV", "V"][Profile.mastery_level(key)] + " · " + tr_n("%d kill", "%d kills", kills) % kills
	var ammo_name := Ammo.name_of(String(cur.caliber), wc.ammo_of(w) if wc != null else 0) if cur.uses_ammo() else ""
	if ammo_name != "":
		meta += "\n" + tr(ammo_name)
	var description = ui._d_text.text
	if id != "" and String(selected.get("slot", "")) != "preset" and not GunStage.GunModel.has_model(id):
		description += "\n" + tr("Internal modification · compare its effects on the card.")
	# metryka broni (E5, ST-01): numer, zabójstwa, wprawa i hałas magazynka od ciszy (§5a; cień = obecny montaż przy podglądzie)
	var mp := Profile.mastery_points(key)
	var ml := Profile.mastery_level(key)
	var noise_now := StationNoise.mag_level(cur) if cur.uses_ammo() else -1.0
	var noise_new := StationNoise.mag_level(preview) if preview != null and cur.uses_ammo() else -1.0
	ui._workbench.present({"name": String(cur.name), "meta": meta, "tag": ui._d_tag.text, "preview": preview != null,
		"serial": "86-%04d" % (absi(hash(key)) % 10000), "kills": kills, "mastery": ml, "mastery_points": mp,
		"mastery_next": int(Profile.MASTERY_XP[mini(ml + 1, Profile.MASTERY_XP.size() - 1)]), "ammo": ammo_name, "noise": [noise_now, noise_new],
		"pending": pending, "part_name": part_name, "option": ui._opt, "unlocked": unlocked, "slot": ui._bench_slot,
		"weapons": weapons, "slots": slots, "options": records, "rows": rows, "description": description, "melee": cur.is_melee()})

## Główne zmiany po zamontowaniu części `id` w gnieździe `slot` broni `w` (kafel części na ławie): do dwóch wierszy [parametr, nowa wartość,
## ocena −1 / 0 / 1] — pierwsza korzyść i pierwszy kompromis (albo zmiana bez oceny); [] — bez zmian w liczbach (część o samym opisie).
func _part_delta(w: int, cur: RefCounted, slot: String, id: String) -> Array:
	var key := String(cur.key)
	var choice := {}
	for s in Parts.slots_of(key):
		choice[s] = Profile.fitted(key, String(s))
	choice[slot] = id
	var wc = ui._local_wc()
	var ammo_type: int = wc.ammo_of(w) if wc != null else 0
	var after: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, Parts.encode(key, choice)))
	var before_rows := _comparison_rows(cur)
	var after_rows := _comparison_rows(after)
	var gain: Array = []
	var cost: Array = []
	var neutral: Array = []
	for i in mini(before_rows.size(), after_rows.size()):
		if String(before_rows[i][1]) == String(after_rows[i][1]):
			continue
		var kind := _change_kind(String(before_rows[i][0]), cur, after)
		var row := [String(before_rows[i][0]), UiTheme.num_text(String(after_rows[i][1])), kind]
		if kind > 0 and gain.is_empty():
			gain = row
		elif kind < 0 and cost.is_empty():
			cost = row
		elif kind == 0 and neutral.is_empty():
			neutral = row
	var out: Array = []
	for r in [gain, cost]:
		if not r.is_empty():
			out.append(r)
	if out.is_empty() and not neutral.is_empty():
		out.append(neutral)
	return out

## Kolor jest pomocniczy: korzyści i kompromisy mają również podpis. Mieszane zmiany pozostają neutralne.
func _change_kind(metric: String, before: RefCounted, after: RefCounted) -> int:
	for field in ui.PART_METRICS:
		if metric == tr(String(ui.PART_METRICS[field][0])):
			if field == "auto":
				return 0 # tryb ognia jest wyborem sposobu użycia
			var direction := -1.0 if Parts.LOWER_IS_BETTER.has(field) or field == "ammo_per_shot" else 1.0
			return int(signf((float(after.get(field)) - float(before.get(field))) * direction))
	if metric == tr("Damage"):
		var old_damage: float = before.blast_damage if before.kind == WeaponDefinition.Kind.LAUNCHER else before.damage * before.pellets
		var new_damage: float = after.blast_damage if after.kind == WeaponDefinition.Kind.LAUNCHER else after.damage * after.pellets
		return int(signf(new_damage - old_damage))
	var fields := {tr("Damage"): ["damage", 1], tr("Magazine"): ["mag", 1], tr("Noise"): ["n_max", -1],
		tr("Mass"): ["mass", -1], tr("Kit mass"): ["mass", -1], tr("Run speed / noise"): ["mass", -1],
		tr("Draw"): ["draw_time", -1], tr("Armour bypass"): ["armor_pen", 1]}
	if fields.has(metric):
		var spec: Array = fields[metric]
		return int(signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[1])))
	if metric == tr("Range") or metric == tr("Reach"):
		return int(signf(after.range_m() - before.range_m()))
	if metric == tr("Fire rate") or metric == tr("Swing rate"):
		return int(signf(after.rpm() - before.rpm()))
	if metric == tr("Reload"):
		return int(signf(before.full_reload_time() - after.full_reload_time()))
	if metric == tr("DPS"):
		return int(signf(after.dps() - before.dps()))
	var pairs := {tr("Spread"): ["jitter_deg", "spread_deg", -1], tr("Bloom"): ["bloom_per_shot", "bloom_max", -1],
		tr("Recoil"): ["cam_kick", "recoil", -1], tr("Penetration"): ["pen", "pierce", 1], tr("Heating"): ["barrel_heat", "heat_gain", -1]}
	if pairs.has(metric):
		var spec: Array = pairs[metric]
		var a := signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[2]))
		var b := signf((float(after.get(spec[1])) - float(before.get(spec[1]))) * float(spec[2]))
		return int(signf(a + b)) if a * b >= 0 else 0
	return 0

## Kolumna szczegółów na papierze (jak karta ławy): marginesy karty, napisy atramentem (UiTheme.ink).
## Stan dźwigni akcji (StationKit.action_boxes): `st` "ready" / "wait" / "busy" / "collect" ("" — z `disabled`), `price` > złomu = brak złomu.
func _act_state(b: Button, st: String, price: int) -> void:
	b.set_meta("st", st)
	b.set_meta("price", price)

func _dress_action(b: Button) -> void:
	var st := String(b.get_meta("st", ""))
	if st == "":
		st = "wait" if b.disabled else "ready"
	if st == "busy":
		st = "wait"
	if st == "ready" and (b.disabled or (int(b.get_meta("price", 0)) > Scrap.bank and Scrap.enabled())):
		st = "broke" if int(b.get_meta("price", 0)) > Scrap.bank else "wait"
	if String(b.get_meta("dressed", "")) == st:
		return
	b.set_meta("dressed", st)
	var boxes := StationKit.action_boxes(st)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, boxes[k])
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, boxes["fg"])
	b.add_theme_constant_override("outline_size", 0)

func _paper(inner: Control) -> PanelContainer:
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UiTheme.paper_box())
	paper.add_child(inner)
	var stamp := StationKit.Stamp.new()                  # pieczątka skutku akcji (nakładka, nie zmienia układu)
	paper.add_child(stamp)
	paper.set_meta("stamp", stamp)
	ui._papers.append(paper)
	return paper

## Pieczątka na widocznej karcie po udanej operacji stanowiska (ZAMÓWIONO, WYDANO, ZBADANO…).
func _stamp() -> void:
	for p in ui._papers:
		var pc := p as PanelContainer
		if pc.is_visible_in_tree():
			(pc.get_meta("stamp") as StationKit.Stamp).play(tr(String(StationKit.STAMPS.get(ui._mode, "DONE"))))
			return

func _paper_rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.PAPER_EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Tytuł karty na papierze: krój nagłówków, atrament, bez obrysu.
func _ink_heading() -> Label:
	var l := UiTheme.heading("", 16, UiTheme.INK)
	l.add_theme_constant_override("outline_size", 0)
	return l

## Wiersz listy części / czynności na papierze. Zaznaczony ma ciemniejszy pasek i znacznik „»” (nie tylko inny kolor), stan w nawiasie.
func _tier_row(i: int, text: String, tail: String, col: Color) -> void:
	var sel = i == ui._opt
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_constant_override("outline_size", 0)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, col)
	b.text = ("%s %s   [%s]" % ["»" if sel else " ", text, tail]) if tail != "" else ("%s %s" % ["»" if sel else " ", text])
	b.custom_minimum_size = Vector2(ui.DETAIL_W, 0)
	if ui._mode == "lathe":                                  # tokarka (ST-06): schematy jako rulony przy kaflach — kolory blatu
		b.flat = false
		var light := {UiTheme.INK: UiTheme.TEXT, UiTheme.INK_MUTED: UiTheme.MUTED, UiTheme.INK_GAIN: UiTheme.OK, UiTheme.INK_COST: UiTheme.DANGER, UiTheme.INK_PRICE: UiTheme.ACCENT}
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, light.get(col, UiTheme.TEXT))
		b.custom_minimum_size = Vector2(ui.COLS * ui.TILE_W, 22)
		for st in ["normal", "hover", "pressed", "focus"]:
			var roll := StyleBoxFlat.new()
			roll.bg_color = Color("2a2216") if sel else (Color("1b1c18") if st != "hover" else Color("23241f"))
			roll.border_color = UiTheme.LAMP_LINE if sel else UiTheme.LINE
			roll.set_border_width_all(1)
			roll.set_corner_radius_all(9)
			roll.content_margin_left = 12.0
			roll.content_margin_top = 2.0
			roll.content_margin_bottom = 2.0
			b.add_theme_stylebox_override(st, roll)
		b.pressed.connect(ui._pick_opt.bind(i))
		ui._d_tiers.add_child(b)
		return
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBox = StyleBoxEmpty.new()
		if sel or st == "hover":
			var band := StyleBoxFlat.new()
			band.bg_color = UiTheme.PAPER_SEL if sel else Color(UiTheme.PAPER_SEL, 0.55)
			sb = band
		sb.content_margin_top = 1.0                         # wiersz bez marginesów przycisku — lista części mieści się w karcie
		sb.content_margin_bottom = 1.0
		sb.content_margin_left = 2.0
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(ui._pick_opt.bind(i))
	ui._d_tiers.add_child(b)

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _move_opt(d: int) -> void:
	if ui._mode == "bench":
		var ops = ui._options(int(ui.LIST[ui._sel]))
		var indices: Array = []
		for i in ops.size():
			if String(ops[i]["slot"]) == ui._bench_slot:
				indices.append(i)
		if not indices.is_empty():
			_pick_opt(int(indices[posmod(indices.find(ui._opt) + d, indices.size())]))
		return
	var n = ui._options(int(ui.LIST[ui._sel])).size()
	if n == 0:
		return
	ui._opt = posmod(ui._opt + d, n)
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._refresh()
	_reveal_option()

func _pick_opt(i: int) -> void:
	var ops = ui._options(int(ui.LIST[ui._sel]))
	if i < 0 or i >= ops.size():
		return
	if i != ui._opt:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._opt = i
	ui._selection_revision += 1
	if ui._mode == "bench":
		ui._bench_slot = String(ops[i]["slot"])
		ui._workbench.stage.cancel_mount()
	ui._refresh()
	_reveal_option()

## Nawigacja klawiszami/padem nie zostawia wybranej operacji poza przewijanym kadrem.
func _reveal_option() -> void:
	call_deferred("_reveal_current_option")

func _reveal_current_option() -> void:
	if not ui._open or ui._page != 0 or ui._mode == "bench":
		return
	var buttons = ui._d_tiers.get_children().filter(func(c: Node) -> bool: return c is Button)
	if ui._opt >= 0 and ui._opt < buttons.size():
		_ensure_arm_option_visible.call_deferred(buttons[ui._opt])

## Przebudowa części może odłączyć przycisk przed odroczonym przewinięciem fokusu.
func _ensure_arm_option_visible(button: Control) -> void:
	if not is_instance_valid(button) or not is_instance_valid(ui._arms_body):
		return
	var scroll := ui._arms_body.get_parent() as ScrollContainer
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)

func _move(d: int) -> void:
	var choices := _arms_list()
	var pos := choices.find(ui._sel)
	var next := pos + d
	if next < 0 or next >= choices.size():
		return
	var n := int(choices[next])
	if n < 0 or n >= ui.LIST.size():
		return
	ui._stop_clean()
	ui._sel = n
	ui._selection_revision += 1
	ui._bench_slot = ""
	(ui._arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
	ui._opt = ui._first_part_opt()
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	ui._refresh()

func _select(i: int) -> void:
	if not _arms_list().has(i):
		return
	if i != ui._sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
		ui._stop_clean()
		ui._sel = i
		ui._selection_revision += 1
		ui._bench_slot = ""
		(ui._arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
		ui._opt = ui._first_part_opt()
	ui._refresh()

## Kursor na pierwszej części (nie na elemencie fabrycznym) — po wyborze broni widać od razu, co można kupić.
## Siatka i nawigacja korzystają z tej samej listy rzeczywistych opcji stanowiska.
func _arms_list() -> Array:
	var out: Array = []
	for i in ui.LIST.size():
		var w := int(ui.LIST[i])
		if ui._mode == "bench" or ui._mode == "locker" or not ui._options(w).is_empty():
			out.append(i)
	return out

func _initial_selection() -> int:
	var choices := _arms_list()
	if choices.is_empty():
		return 0
	if ui._first_pick() != "" and choices.has(ui.LIST.find(Weapons.M83)):
		return ui.LIST.find(Weapons.M83)
	var jobs: Array = Scrap.lathe if ui._mode == "lathe" else (Scrap.research if ui._mode == "lab" else [])
	if ui._mode == "lathe" and jobs.is_empty():
		jobs = Scrap.schematics.keys()
	for id in jobs:
		var w := Weapons.index_of(String(Parts.get_part(String(id)).get("weapon", "")))
		var i = ui.LIST.find(w)
		if choices.has(i):
			return i
	var remembered := int(ui._remembered.get(ui._mode, -1))
	if choices.has(remembered):
		return remembered
	var controller = ui._local_wc()
	if controller != null:
		var i = ui.LIST.find(controller.cur().id)
		if choices.has(i):
			return i
	for i in choices:
		if Scrap.is_unlocked(int(ui.LIST[int(i)])):
			return int(i)
	return int(choices[0])

func _act() -> void:
	ui._note_act()
	if not ui._pending_part.is_empty() or ui._buying >= 0:
		return
	var w: int = ui.LIST[ui._sel]
	if not Scrap.is_unlocked(w):
		if ui._mode in ["service", "lab", "lathe"]:
			ui._say(tr("Buy it at the workshop bench first."), UiTheme.MUTED)
		else:
			ui._buying = w
			Scrap.request_buy(w)
		return
	var ops = ui._options(w)
	if ops.is_empty():
		return
	if ui._mode == "bench" and ui._opt < 0:
		return
	var o: Dictionary = ops[clampi(ui._opt, 0, ops.size() - 1)]
	var key := String(Weapons.def(w).key)
	var id := String(o["id"])
	if String(o["slot"]) == "preset":
		var pi := int(o["id"])
		if Profile.preset(key, pi).is_empty():
			ui._save_preset()
		elif Profile.is_preset_fitted(key, pi):
			ui._say(tr("Set %d is already fitted.") % (pi + 1), UiTheme.MUTED)
		else:
			var before := Profile.fit_code(w)
			var skipped := Profile.load_preset(key, pi)
			ui._success_fx(-6.0)
			ui._say((tr("Fitted set %d.") % (pi + 1)) if skipped == 0 else (tr("Fitted set %d — %d parts the squad no longer has stay as they were.") % [pi + 1, skipped]),
				UiTheme.OK if skipped == 0 else UiTheme.MUTED)
			ui._present_committed(w, before)
		return
	if String(o["slot"]) == "service" and id in Profile.WEAR_PARTS:
		if not Profile.service_due(key, id):
			ui._say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		else:
			Scrap.request_service(w, id)
		return
	if String(o["slot"]) == "service":
		if ui._clean_w == w:
			ui._stop_clean()
			ui._say(tr("Cleaning stopped."), UiTheme.MUTED)
			ui._refresh()
		elif id == "sharpen" and Profile.sharpen_time(key) <= 0.0:
			ui._say(tr("Already sharp."), UiTheme.MUTED)
		elif id != "sharpen" and Profile.clean_time(key) <= 0.0:
			ui._say(tr("Already clean."), UiTheme.MUTED)
		else:
			ui._start_clean(w)
		return
	if ui._mode == "lathe" and String(o["slot"]) != "service":
		if Scrap.has_part(id):
			ui._say(tr("Already made — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.lathe.has(id):
			ui._say(tr("On the lathe — ready after the next mission."), UiTheme.MUTED)
		elif Scrap.schematics.has(id):
			Scrap.request_machining(id)
		else:
			ui._say(tr("No schematic — research it at the lab first."), UiTheme.MUTED)
		return
	if ui._mode == "lab":
		if Scrap.schematics.has(id) or Scrap.lathe.has(id):
			ui._say(tr("Already researched — make it on the lathe downstairs."), UiTheme.MUTED)
			return
		if Scrap.has_part(id):
			ui._say(tr("Already known — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.research.has(id):
			ui._say(tr("Being researched — ready after the next mission."), UiTheme.MUTED)
		else:
			Scrap.request_research(id)
		return
	if id != "" and not Scrap.has_part(id):
		if Scrap.is_lab_part(id) and not Scrap.found.has(id):
			ui._say(tr("Special-weapon parts are researched at the lab upstairs."), UiTheme.MUTED)
		else:
			ui._pending_part = {"id": id, "w": w, "fit": Profile.fit_code(w), "session": ui._session, "revision": ui._selection_revision}
			ui._refresh()
			Scrap.request_part(id)
	elif Profile.fitted(key, String(o["slot"])) != id:
		var before := Profile.fit_code(w)
		Profile.set_fit(key, String(o["slot"]), id)
		ui._success_fx(-6.0)
		ui._say(tr("Fitted: %s.") % (tr(Parts.get_part(id)["name"]) if id != "" else tr("factory part")), UiTheme.OK)
		ui._present_committed(w, before)

func _on_result(w: int, ok: bool, reason: String) -> void:
	if ui._buying == w:
		ui._buying = -1
	if not ui._open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"station":
			ui._say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			ui._say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			ui._say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			ui._say(tr("%s unlocked — take it from the rack.") % name, UiTheme.OK)
			ui._success_fx()
		"poor":
			ui._drum.broke()
			ui._say(tr("Not enough scrap (%d needed).") % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			ui._say(tr("%s is already unlocked.") % name, UiTheme.MUTED)
		"later":
			ui._say("Not available yet — a later zone.", UiTheme.MUTED)
		"reward":
			ui._say("Defeat the Leech to unlock it.", UiTheme.MUTED)
		_:
			ui._say("Cannot do that.", UiTheme.DANGER)
	ui._refresh()

func _on_part_result(id: String, ok: bool, reason: String) -> void:
	var context: Dictionary = ui._pending_part.duplicate() if String(ui._pending_part.get("id", "")) == id else {}
	if not context.is_empty():
		ui._pending_part.clear()
	if not ui._open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			ui._say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			ui._say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			ui._say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			ui._say(tr("%s unlocked for the squad and fitted to your gun.") % nm, UiTheme.OK)
			ui._success_fx()
		"poor":
			ui._drum.broke()
			ui._say(tr("Not enough scrap (%d needed).") % Scrap.part_cost(id), UiTheme.DANGER)
		"owned":
			ui._say(tr("The squad already has %s.") % nm, UiTheme.MUTED)
		"locked":
			ui._say("Unlock the weapon first.", UiTheme.MUTED)
		_:
			ui._say("Cannot do that.", UiTheme.DANGER)
	if ok and not context.is_empty() and int(context["session"]) == ui._session and int(context["revision"]) == ui._selection_revision and int(ui.LIST[ui._sel]) == int(context["w"]):
		ui._present_committed(int(context["w"]), int(context["fit"]))
	else:
		ui._refresh()

## Taśma sterowania ławy ARMS (workshop_ui.gd `_controls_hint` wybiera widok stanowiska).
func hint(pad: bool) -> String:
	return tr("%s weapon · %s slot · %s / %s part · %s fit · %s inspect · %s tabs · %s close") % [
		ui._cap("menu_up", pad) + "/" + ui._cap("menu_down", pad), ui._cap("menu_left", pad) + "/" + ui._cap("menu_right", pad),
		ui._cap("menu_slot_1", pad), ui._cap("menu_slot_2", pad), ui._cap("menu_accept", pad), ui._cap("menu_inspect", pad),
		ui._cap("menu_tab", pad), ui._cap("menu_back", pad)]

## Zakładka ARMS: siatka broni, kartka „do zrobienia” stołu konserwacji, karta szczegółów, pracownia / tokarka i ława rusznikarza.
func _build_arms(root: VBoxContainer, body: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	ui._arms_left = left
	var grid := GridContainer.new()
	grid.columns = ui.COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in ui.LIST.size():
		var t = ui._make_tile(int(ui.LIST[i]), i)
		grid.add_child(t)
		ui._tiles.append(t)
	ui._svc_todo = UiTheme.label("", 9, UiTheme.MUTED)                   # stół konserwacji: lista „do zrobienia” pod kaflami (puste miejsce przy kilku broniach)
	ui._svc_todo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._svc_todo.custom_minimum_size.x = ui.COLS * ui.TILE_W - 24.0
	ui._svc_todo.visible = false
	var scrawl := NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)
	ui._svc_todo.add_theme_font_override("font", UiTheme.note_font(NotePaletteRef.Note.SCRAWL))   # kartka odręczna (ST-02): Caveat, atrament kartki
	ui._svc_todo.add_theme_font_size_override("font_size", UiTheme.note_size(NotePaletteRef.Note.SCRAWL, 10))
	ui._svc_todo.add_theme_color_override("font_color", scrawl["ink"])
	ui._svc_todo.add_theme_constant_override("outline_size", 0)
	ui._svc_note = ServiceArt.Scrawl.new()
	ui._svc_note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ui._svc_note.visible = false
	ui._svc_note.add_child(ui._svc_todo)
	left.add_child(ui._svc_note)
	ui._arms_paper = ui._paper(ui._build_detail())
	body.add_child(ui._arms_paper)
	ui._build_lab_lathe(left, body)
	ui._legacy_stage = ui._d_stage as GunStage
	ui._workbench = GunsmithPanel.new()
	ui._workbench.custom_minimum_size = Vector2(606, 240)
	root.add_child(ui._workbench)
	ui._workbench.visible = false
	ui._workbench.weapon_selected.connect(ui._select)
	ui._workbench.slot_selected.connect(ui._pick_slot)
	ui._workbench.option_selected.connect(ui._pick_opt)
	ui._workbench.inspect_requested.connect(ui._inspect)
	ui._workbench.save_requested.connect(ui._save_current_preset)
