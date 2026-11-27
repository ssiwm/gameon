extends RefCounted
## Stół konserwacji (ST-02): zalecenia, lista do zrobienia, przyrządy z manometrem, blat zamiast karty.
## Wydzielone z workshop_ui.gd (STATION_CARDS_PLAN.md E1 — podział na widoki stanowisk). Stan panelu (kafle, etykiety, wybór) zostaje
## w workshop_ui.gd, tu jest budowa i wypełnianie; `ui` to panel. workshop_ui woła te funkcje przez funkcje o tych samych nazwach.

const Controller := preload("res://scripts/weapon_controller.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")
const GunStage := preload("res://scripts/gun_stage.gd")

var ui                                   ## panel stanowisk (workshop_ui.gd): stan, kafle, etykiety

func _init(panel: Control) -> void:
	ui = panel

## Zalecenie stołu konserwacji dla broni `w`: jedna rzecz do zrobienia teraz, od najpilniejszej (od 1.7.413 — panel podawał same liczby).
## {level, id, text, short}: level 2 — pilne (broń się zacina albo czyszczenie nie wyprowadzi jej ponad próg zacięć, lufa ≥ SERVICE_URGENT),
## 1 — warto (część od progu wymiany), 0 — drobiazg (brud), -1 — nic do roboty; `id` — wiersz SERVICE, na który trafia kursor. {} — broń biała.
func _service_advice(w: int) -> Dictionary:
	var base: RefCounted = Weapons.base_def(w)
	var key = String(base.key)
	if base.is_melee():
		return {}
	var cond = Profile.condition(key)
	var cap = Profile.clean_cap(key)
	var ct = Profile.clean_time(key)
	var bw = Profile.part_wear(key, "barrel")
	var spread = int(round(Controller.BARREL_SPREAD * pow(bw / 100.0, 2.0) * 100.0))
	var jams: bool = base.can_jam()
	var springs = jams and Profile.service_due(key, "springs")
	var barrel = jams and Profile.service_due(key, "barrel")
	if springs and cap < Controller.JAM_FROM:
		return {"level": 2, "id": "springs", "short": tr("replace springs"),
			"text": tr("Replace the springs: cleaning only reaches %d%% — below %d%% the gun jams.") % [int(cap), int(Controller.JAM_FROM)]}
	if jams and cond < Controller.JAM_FROM and ct > 0.0:
		return {"level": 2, "id": "clean", "short": tr("clean (%d%%)") % int(cond),
			"text": tr("Clean it (%d s): at %d%% the gun jams.") % [ceili(ct), int(cond)]}
	if barrel and bw >= Profile.SERVICE_URGENT:
		return {"level": 2, "id": "barrel", "short": tr("replace barrel"), "text": tr("Replace the barrel: shots spread %d%% wider.") % spread}
	if springs:
		return {"level": 1, "id": "springs", "short": tr("replace springs"), "text": tr("Replace the springs: cleaning only reaches %d%%.") % int(cap)}
	if barrel:
		return {"level": 1, "id": "barrel", "short": tr("replace barrel"), "text": tr("Replace the barrel: shots spread %d%% wider.") % spread}
	if ct > 0.0:
		return {"level": 0, "id": "clean", "short": tr("clean (%d%%)") % int(cond), "text": tr("Clean it when you can (%d s) — condition %d%%.") % [ceili(ct), int(cond)]}
	return {"level": -1, "id": "clean", "short": "", "text": tr("In good order — nothing to do.")}

## Lewa kolumna stołu konserwacji: co zrobić z całym ekwipunkiem — jedna linia na broń, która czegoś potrzebuje (pilne pierwsze).
func _refresh_service_todo() -> void:
	ui._svc_todo.visible = ui._mode == "service" and ui._page == 0
	ui._svc_note.visible = ui._svc_todo.visible
	if not ui._svc_todo.visible:
		return
	var rows: Array = []
	for i in ui._arms_list():
		var w = int(ui.LIST[int(i)])
		if not Scrap.is_unlocked(w):
			continue
		var adv = _service_advice(w)
		if not adv.is_empty() and int(adv["level"]) >= 0:
			rows.append([int(adv["level"]), "%s — %s" % [String(Weapons.base_def(w).name), String(adv["short"])]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var lines: Array[String] = [tr("To do:")]
	for r in rows:
		lines.append(("! " if int(r[0]) >= 2 else "· ") + String(r[1]))
	if rows.is_empty():
		lines.append(tr("All guns in good order."))
	ui._svc_todo.text = "\n".join(lines)

## Kolor zużycia części eksploatacyjnej: zwykły poniżej progu wymiany, cena od Profile.SERVICE_DUE, koszt (pilne) od SERVICE_URGENT.
func _wear_ink(wear: float) -> Color:
	return UiTheme.INK_COST if wear >= Profile.SERVICE_URGENT else (UiTheme.INK_PRICE if wear >= Profile.SERVICE_DUE else UiTheme.INK)

## Stół konserwacji: stan broni, zużycie lufy i sprężyn ze skutkami (rozrzut, granica czyszczenia), szansa zacięcia i czas czyszczenia.
## Kreska na paskach zużycia = próg, od którego część da się wymienić.
func _fill_service_panel(base: RefCounted, cur: RefCounted) -> void:
	var key = String(base.key)
	if base.is_melee():
		var edge = Profile.edge_of(key)
		ui._paper_bar(tr("Edge"), edge / 100.0, "%d%%" % int(edge), UiTheme.INK_GAIN if edge >= 95.0 else UiTheme.INK)
		return
	var adv = _service_advice(int(ui.LIST[ui._sel]))
	if not adv.is_empty():
		var lv = int(adv["level"])
		var al = UiTheme.ink(String(adv["text"]), 10, [UiTheme.OK, UiTheme.TEXT, UiTheme.ACCENT, UiTheme.DANGER][clampi(lv + 1, 0, 3)] if ui._mode == "service" else ui._advice_ink(lv))
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size.x = ui.DETAIL_W
		ui._d_panel.add_child(al)
	var cond = Profile.condition(key)
	var cap = Profile.clean_cap(key)
	var bw = Profile.part_wear(key, "barrel")
	var spread = int(round(Controller.BARREL_SPREAD * pow(bw / 100.0, 2.0) * 100.0))
	var sw = Profile.part_wear(key, "springs")
	# trzy przyrządy z manometrem (ST-02): czyszczenie — stan, czerwona strefa zacięć poniżej JAM_FROM, kropka lampy na limicie sprężyn,
	# cień wskazówki = dokąd dojdzie czyszczenie; lufa i sprężyny — zużycie ze strefą wymiany i pilną, cień = po wymianie
	var ops = ui._options(int(ui.LIST[ui._sel]))
	var cur_id = String(ops[ui._opt]["id"]) if ui._opt >= 0 and ui._opt < ops.size() else ""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ui._d_panel.add_child(row)
	ui._gauges.clear()
	var due = Profile.SERVICE_DUE / 100.0
	var urgent = Profile.SERVICE_URGENT / 100.0
	var ctime = Profile.clean_time(key)
	var specs = [
		["clean", tr("CLEANING"), tr("%d s") % ceili(ctime) if ctime > 0.0 else "—", cond / 100.0, cap / 100.0 if cond < cap - 0.5 else -1.0, cap / 100.0 if cap < 99.5 else -1.0,
			[[0.0, Controller.JAM_FROM / 100.0, Color(UiTheme.DANGER, 0.75)]],
			(tr("condition %d%% → %d%%") % [int(cond), int(cap)] if cond < cap - 0.5 else tr("condition %d%%") % int(cond)) + (" · " + tr("jams") if cond < Controller.JAM_FROM else "")],
		["barrel", tr("BARREL"), "%d" % int(Scrap.SERVICE_COST["barrel"]), bw / 100.0, 0.0 if Profile.service_due(key, "barrel") else -1.0, -1.0,
			[[due, urgent, Color(UiTheme.ACCENT, 0.6)], [urgent, 1.0, Color(UiTheme.DANGER, 0.75)]], tr("wear %d%% · spread +%d%%") % [int(bw), spread]],
		["springs", tr("SPRINGS"), "%d" % int(Scrap.SERVICE_COST["springs"]), sw / 100.0, 0.0 if Profile.service_due(key, "springs") else -1.0, -1.0,
			[[due, urgent, Color(UiTheme.ACCENT, 0.6)], [urgent, 1.0, Color(UiTheme.DANGER, 0.75)]], tr("wear %d%% · cleans to %d%%") % [int(sw), int(cap)]],
	]
	for s in specs:
		var g = ServiceArt.Gauge.new()
		g.job = String(s[0])
		g.title.text = String(s[1])
		g.right.text = String(s[2])
		g.dial.value = float(s[3])
		g.dial.ghost = float(s[4])
		g.dial.mark = float(s[5])
		g.dial.zones = s[6]
		g.sub.text = UiTheme.num_text(String(s[7]))
		g.set_lit(cur_id == g.job)
		var oi = ops.find({"slot": "service", "id": g.job})
		g.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and oi >= 0:
				ui._pick_opt(oi))
		row.add_child(g)
		ui._gauges[g.job] = g
	var wc = ui._local_wc()
	var jam: float = wc.jam_chance(cur) if wc != null else 0.0
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 1)
	var deck = ui._mode == "service"                         # na blacie stołu konserwacji kolory blatu, nie atramentu
	grid.add_child(UiTheme.ink(tr("Jam chance"), 9, UiTheme.MUTED if deck else UiTheme.INK_MUTED))
	grid.add_child(UiTheme.ink(tr("none") if jam <= 0.0 else tr("1 in %d shots") % maxi(1, roundi(1.0 / jam)), 9,
		(UiTheme.DANGER if jam > 0.0 else UiTheme.OK) if deck else (UiTheme.INK_COST if jam > 0.0 else UiTheme.INK_GAIN)))
	ui._d_panel.add_child(grid)                              # czas czyszczenia stoi w wierszu „Czyszczenie” i na przycisku — nie trzeci raz tutaj

## Stół konserwacji (ST-02): karta znika — rozłożona broń na płótnie i przyrządy stoją na ciemnym blacie, napisy w kolorach blatu,
## lista części zastąpiona wyborem przyrządu (strzałki w lewo / w prawo albo klik). Pozostałe stanowiska: karta na papierze.
func _service_skin(on: bool) -> void:
	if ui._arms_paper.get_meta("service", false) == on:
		return
	ui._arms_paper.set_meta("service", on)
	var deck = StyleBoxFlat.new()
	deck.bg_color = Color(0, 0, 0, 0)
	deck.set_content_margin_all(2)
	ui._arms_paper.add_theme_stylebox_override("panel", deck if on else UiTheme.paper_box())
	ui._d_title.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.INK)
	ui._d_tag.add_theme_color_override("font_color", UiTheme.MUTED if on else UiTheme.INK_MUTED)
	ui._d_text.add_theme_color_override("font_color", UiTheme.MUTED if on else UiTheme.INK)
	ui._d_tiers.visible = not on
	ui._legacy_stage.modulate = Color(0.78, 0.76, 0.72) if on else Color.WHITE  # płótno z rozłożoną bronią przyciemnione — światło na przyrządach

## Czyszczenie przy ławie (stan siedzi w profilu gracza, więc serwer nie bierze udziału): trwa Profile.clean_time, panel musi zostać
## otwarty, a gracz przy ławie — odejście, zmiana broni albo ponowne [E] przerywa i trzeba zacząć od nowa.
func _start_clean(w: int) -> void:
	ui._clean_w = w
	ui._clean_t = 0.0
	var melee := Weapons.def(w).is_melee()
	ui._clean_total = Profile.sharpen_time(String(Weapons.def(w).key)) if melee else Profile.clean_time(String(Weapons.def(w).key))
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -8.0, 0.85)
	ui._say((tr("Sharpening the %s…") if melee else tr("Stripping the %s…")) % String(Weapons.def(w).name), UiTheme.TEXT)
	ui._refresh()

func _stop_clean() -> void:
	ui._clean_w = -1
	ui._clean_t = 0.0

## Klatka czyszczenia (z `_process`; testy wołają ją ręcznie).
func tick_clean(delta: float) -> void:
	if ui._clean_w < 0:
		return
	ui._clean_t += delta
	var ck := String(Weapons.def(ui._clean_w).key)
	var melee := Weapons.def(ui._clean_w).is_melee()
	if ui._clean_t < ui._clean_total:
		ui._action.text = (tr("Sharpening…  %d%%  (again to stop)") if melee else tr("Cleaning…  %d%%  (again to stop)")) % int(100.0 * ui._clean_t / ui._clean_total)
		if String(ui._action.get_meta("st", "")) != "busy":
			ui._act_state(ui._action, "busy", 0)
			ui._dress_action(ui._action)
		if not melee:
			var c0 := Profile.condition(ck)                 # brud schodzi z broni w trakcie (ława 3D)
			(ui._d_stage as GunStage).set_dirt(1.0 - lerpf(c0, Profile.clean_cap(ck), ui._clean_t / ui._clean_total) / 100.0)
			if ui._gauges.has("clean") and is_instance_valid(ui._gauges["clean"]):            # przyrząd czyszczenia: wskazówka idzie do limitu
				(ui._gauges["clean"] as ServiceArt.Gauge).dial.value = lerpf(c0, Profile.clean_cap(ck), ui._clean_t / ui._clean_total) / 100.0
		return
	var w = ui._clean_w
	_stop_clean()
	if melee:
		Profile.sharpen(ck)                                 # szlifierka (W6b)
		ui._stamp()
		ui._say(tr("%s sharpened — edge 100%%.") % String(Weapons.def(w).name), UiTheme.OK)
		Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.3)
		ui._refresh()
		return
	Profile.clean(ck)
	ui._stamp()
	ui._say(tr("%s stripped and cleaned — condition %d%%.") % [String(Weapons.def(w).name), int(Profile.condition(ck))], UiTheme.OK)
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.0)
	ui._refresh()

func _on_service_result(w: int, part: String, ok: bool, reason: String) -> void:
	if not ui._open:
		return
	match reason:
		"station":
			ui._say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			ui._say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			ui._say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"early":
			ui._say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		"ok":
			ui._say((tr("New barrel in the %s.") if part == "barrel" else tr("New springs in the %s.")) % String(Weapons.def(w).name), UiTheme.OK)
			Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.1)
		"poor":
			ui._drum.broke()
			ui._say(tr("Not enough scrap (%d needed).") % int(Scrap.SERVICE_COST.get(part, 0)), UiTheme.DANGER)
		_:
			ui._say("Cannot do that.", UiTheme.DANGER)
	ui._refresh()

## Taśma sterowania stołu konserwacji (workshop_ui.gd `_controls_hint` wybiera widok stanowiska).
func hint(pad: bool) -> String:
	return tr("%s gun   ·   %s instrument   ·   %s hold: clean / replace   ·   %s close   ·   or click") % [
		ui._cap("menu_up", pad) + " " + ui._cap("menu_down", pad), ui._cap("menu_left", pad) + " " + ui._cap("menu_right", pad), ui._cap("menu_accept", pad), ui._cap("menu_back", pad)]
