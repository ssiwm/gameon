extends RefCounted
## Test mieszczenia się interfejsu w każdym języku: buduje menu pauzy (ustawienia, kodeks, sterowanie) po angielsku i po polsku
## i sprawdza, czy żadna widoczna kontrolka nie wystaje w poziomie poza obszar, który ją przycina (przewijana lista, strona, karta),
## a karta — poza ekran. Polskie teksty są dłuższe: segmenty („OGRANICZONE”, „ADAPTACYJNY”) i opisy wypychały prawą kolumnę
## ustawień i opisy kodeksu poza kartę.
##   godot --headless --path prototype -- --uifittest     → ostatni wiersz: PASS / FAIL (flaga w main.gd, bo menu potrzebuje autoloadów)

const PauseMenu := preload("res://scripts/pause_menu.gd")
const OperatorsScreen := preload("res://scripts/operators_screen.gd")
const Codex := preload("res://scripts/codex.gd")
const MainMenu := preload("res://scripts/main_menu.gd")
const Actions := preload("res://scripts/actions.gd")
const MENU_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 800)]
const MENU_WORDS := 70                 ## MAIN_MENU_PLAN.md §7: tekst w spoczynku
const MENU_MIN_PX := 12

const LOCALES := ["en", "pl"]
const TAB_NAMES := ["SETTINGS", "BESTIARY", "WEAPONS", "GEAR", "PERKS", "CONTROLS"]
const SLACK := 0.5                     ## tolerancja zaokrągleń [px]

var _fails := 0
var _seen := {}                        ## zgłoszone już (język, karta, kontrolka) — wpisy kodeksu powtarzają te same błędy


## Wynik: liczba błędów (0 = PASS). `host` — węzeł w drzewie (main.gd), pod nim powstaje próbne menu.
func run(host: Node) -> int:
	var tree := host.get_tree()
	# pierwszy start bez zapisu ustawień: język z systemu (Settings.system_locale_idx)
	for case in [["pl", 1], ["PL", 1], ["en", 0], ["de", 0], ["", 0]]:
		var got: int = Settings.system_locale_idx(String(case[0]))
		if got != int(case[1]):
			_fail("język systemu „%s” → %s, oczekiwano %s" % [case[0], Settings.LOCALES[got], Settings.LOCALES[int(case[1])]])
	print("[UI-FIT] PASS  język systemu przy pierwszym starcie: pl → POLSKI, inne → ENGLISH" if _fails == 0 else "[UI-FIT] FAIL  język systemu")
	# pierwszy start: zintegrowana karta → MEDIUM i 75%, osobna i inne → HIGH 100% (Settings.first_run_graphics)
	var igpu: Array = Settings.first_run_graphics(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU)
	var dgpu: Array = Settings.first_run_graphics(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU)
	if Settings.QUALITY_NAMES[int(igpu[0])] != "MEDIUM" or not is_equal_approx(float(Settings.RENDER_SCALE_LIST[int(igpu[1])]), 0.75) 			or Settings.QUALITY_NAMES[int(dgpu[0])] != "HIGH" or int(dgpu[1]) != 0:
		_fail("grafika pierwszego startu: zintegrowana %s, osobna %s" % [igpu, dgpu])
	else:
		print("[UI-FIT] PASS  grafika pierwszego startu: zintegrowana karta MEDIUM 75%, osobna HIGH 100%")
	# nowy gracz: obsługa CLASSIC i bez zacięć (GDD §16.0a)
	if Settings.REALISTIC_DEFAULT or Settings.RELIABILITY_NAMES[Settings.RELIABILITY_DEFAULT] != "OFF":
		_fail("domyślna obsługa broni nowego gracza nie jest CLASSIC + OFF")
	# nowy gracz: EASY, dopóki sam nie wybierze poziomu; zapamiętany wybór (także NORMAL) zostaje
	var picked := ConfigFile.new()
	picked.set_value("game", "difficulty", Difficulty.Level.NORMAL)
	var other := ConfigFile.new()
	other.set_value("game", "lang", 1)
	if Difficulty.saved_level(null) != Difficulty.Level.EASY or Difficulty.saved_level(other) != Difficulty.Level.EASY \
			or Difficulty.saved_level(picked) != Difficulty.Level.NORMAL:
		_fail("poziom trudności pierwszego startu: brak pliku %d, plik bez wyboru %d, wybrany NORMAL %d" % [
			Difficulty.saved_level(null), Difficulty.saved_level(other), Difficulty.saved_level(picked)])
	else:
		print("[UI-FIT] PASS  pierwszy start na EASY, zapamiętany wybór zostaje")
	var keep := TranslationServer.get_locale()
	# układ kodeksu sprawdzamy na pełnych wpisach (najdłuższe teksty) — bestiariusz odsłonięty w całości
	for id in Profile.bestiary_ids():
		Profile.bestiary[String(id)] = 0
	for loc in LOCALES:
		TranslationServer.set_locale(loc)
		var pm: Control = PauseMenu.new()
		host.add_child(pm)
		pm.visible = true
		for t in TAB_NAMES.size():
			pm._show_tab(t)
			for _f in 4:
				await tree.process_frame
			_check_tab(pm, loc, t)
			if t == 1 or t == 2:
				# każdy wpis kodeksu: opisy i statystyki zmieniają szerokość
				var page: Node = pm.page_of(t)
				for i in page._entries.size():
					page.select(i)
					for _f in 2:
						await tree.process_frame
					_check_tab(pm, loc, t, " wpis %d" % i)
		if loc == "en":
			# zmiana języka przy otwartym menu (ustawienia → Język): karta przebudowuje się w nowym języku
			TranslationServer.set_locale("pl")
			pm._refresh()
			for _f in 3:
				await tree.process_frame
			var nav0: String = pm._nav[0].label
			if nav0 != TranslationServer.translate("SETTINGS") or nav0 == "SETTINGS":
				_fail("zmiana języka en → pl: nawigacja nadal „%s”" % nav0)
			else:
				print("[UI-FIT] PASS  zmiana języka en → pl przebudowuje menu („%s”)" % nav0)
		pm.queue_free()
		await tree.process_frame
	await _operators_checks(host)
	await _main_menu_checks(host)
	TranslationServer.set_locale(keep)
	_bestiary_checks()
	_new_marks_checks()
	print("[UI-FIT] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return _fails


## Ekran OPERATORZY (PROFILES_PLAN.md E3) po angielsku i po polsku: sześć kart z najszerszymi kryptonimami mieści się w karcie i na ekranie,
## okno zmiany nazwy też; zły kryptonim pokazuje błąd i niczego nie zapisuje, dobry zmienia nazwę. Magazyn postaci w osobnym katalogu.
func _operators_checks(host: Node) -> void:
	var tree := host.get_tree()
	const ROOT := "user://uifit_chars/"
	Characters.use_root(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	var ids: Array = []
	for i in Characters.MAX:
		ids.append(Characters.create("WWWWWWWWWWWWWW%02d" % i))
	Characters.select(String(ids[0]))
	for loc in LOCALES:
		TranslationServer.set_locale(loc)
		var ops: Control = OperatorsScreen.new()
		var layer := CanvasLayer.new()             # nad lobby (pełny ekran na warstwie UI łapałby kliknięcia myszą)
		layer.layer = 120
		host.add_child(layer)
		layer.add_child(ops)
		ops.open()
		for _f in 4:
			await tree.process_frame
		var vp := Rect2(Vector2.ZERO, ops.get_viewport_rect().size)
		var bad := 0
		for card in ops._cards:
			var cr: Rect2 = (card as Control).get_global_rect()
			if not vp.encloses(cr.grow(-SLACK)):
				bad += 1
				_fail("%s OPERATORZY: karta %s poza ekranem %s" % [loc, cr, vp])
			for n in (card as Control).find_children("*", "Control", true, false):
				var c := n as Control
				if c.is_visible_in_tree() and c.size.x > 0.0 and c.get_global_rect().end.x > cr.end.x + SLACK:
					bad += 1
					_fail("%s OPERATORZY: %s %s wystaje poza kartę" % [loc, c.get_class(), _desc(c)])
		ops._undo_btn.visible = true                # COFNIJ widać po operacji — stopka musi się zmieścić razem z nim
		for _f in 2:
			await tree.process_frame
		for b in [ops._new_btn, ops._rename_btn, ops._reset_btn, ops._delete_btn, ops._undo_btn, ops._back_btn]:
			if not vp.encloses((b as Control).get_global_rect().grow(-SLACK)):
				bad += 1
				_fail("%s OPERATORZY: przycisk %s poza ekranem" % [loc, _desc(b)])
		ops._open_dialog("rename", String(ids[1]))
		for _f in 3:
			await tree.process_frame
		var dr: Rect2 = ops._dlg.get_global_rect()
		if not vp.encloses(dr.grow(-SLACK)):
			bad += 1
			_fail("%s OPERATORZY: okno kryptonimu %s poza ekranem" % [loc, dr])
		for n in ops._dlg.find_children("*", "Control", true, false):
			var c := n as Control
			if c.is_visible_in_tree() and c.size.x > 0.0 and c.get_global_rect().end.x > dr.end.x + SLACK:
				bad += 1
				_fail("%s OPERATORZY: %s %s wystaje poza okno" % [loc, c.get_class(), _desc(c)])
		if bad == 0:
			print("[UI-FIT] PASS  %s OPERATORZY: %d kart, przyciski i okno kryptonimu mieszczą się" % [loc, ops._cards.size()])
		if loc == "en":
			ops._dlg_edit.text = "S"
			ops._confirm()
			var short_err: String = ops._dlg_err.text
			ops._dlg_edit.text = "Sowa"
			ops._confirm()
			if short_err == "" or String(Characters.meta(String(ids[1]))["name"]) != "Sowa" or ops._dlg.visible:
				_fail("OPERATORZY: zmiana nazwy — błąd za krótkiej „%s”, nazwa po zatwierdzeniu „%s”" % [short_err, Characters.meta(String(ids[1]))["name"]])
			else:
				print("[UI-FIT] PASS  OPERATORZY: za krótki kryptonim pokazuje błąd („%s”), poprawny zmienia nazwę" % short_err)
		# okna resetu i usuwania (E4): mieszczą się w obu językach
		var abad := 0
		for kind in ["campaign", "character", "delete"]:
			ops._open_action(kind, String(ids[3]))
			for _f in 3:
				await tree.process_frame
			var ar: Rect2 = ops._act.get_global_rect()
			if not vp.encloses(ar.grow(-SLACK)):
				abad += 1
				_fail("%s OPERATORZY: okno „%s” %s poza ekranem" % [loc, kind, ar])
			for n in ops._act.find_children("*", "Control", true, false):
				var c := n as Control
				if c.is_visible_in_tree() and c.size.x > 0.0 and c.get_global_rect().end.x > ar.end.x + SLACK:
					abad += 1
					_fail("%s OPERATORZY: okno „%s”: %s %s wystaje" % [loc, kind, c.get_class(), _desc(c)])
		if abad == 0:
			print("[UI-FIT] PASS  %s OPERATORZY: okna nowej kampanii, resetu operatora i usunięcia mieszczą się" % loc)
		if loc == "en":
			# usunięcie z ekranu (bez przytrzymania — sygnał `confirmed` jak po 3 s) i COFNIJ
			ops._open_action("delete", String(ids[4]))
			ops._act_hold.confirmed.emit()
			var gone: bool = not Characters.has(String(ids[4])) and ops._undo_btn.visible and ops._note.text != ""
			ops._undo()
			if not gone or not Characters.has(String(ids[4])) or ops._undo_btn.visible:
				_fail("OPERATORZY: usunięcie z ekranu i COFNIJ (usunięta=%s, wróciła=%s)" % [str(gone), str(Characters.has(String(ids[4])))])
			else:
				print("[UI-FIT] PASS  OPERATORZY: usunięcie po przytrzymaniu, komunikat i COFNIJ przywraca postać („%s”)" % ops._note.text)
			# prawdziwe przytrzymanie: mysz krótko (0,6 s) — nic; mysz pełne 2 s — nowa kampania; [Enter] trzymany — tak samo
			var target := String(ids[5])
			var hold := func(seconds: float, use_key: bool) -> void:
				var at: Vector2 = ops._act_hold.get_global_rect().get_center()
				var ev: InputEvent
				if use_key:
					ops._act_hold.grab_focus()
					ev = InputEventAction.new()
					(ev as InputEventAction).action = "ui_accept"
				else:
					ev = InputEventMouseButton.new()
					(ev as InputEventMouseButton).button_index = MOUSE_BUTTON_LEFT
					(ev as InputEventMouseButton).position = at
					(ev as InputEventMouseButton).global_position = at
				ev.pressed = true
				# mysz prosto do viewportu (headless nie przekazuje kliknięć z Input do GUI); akcja przez Input jak z klawiatury / pada
				var send := func(e: InputEvent) -> void:
					if use_key:
						Input.parse_input_event(e)
					else:
						ops.get_viewport().push_input(e, true)          # współrzędne płótna
				send.call(ev)
				await tree.create_timer(seconds).timeout
				var up: InputEvent = ev.duplicate()
				up.pressed = false
				send.call(up)
				for _f in 3:
					await tree.process_frame
			ops._open_action("campaign", target)
			for _f in 3:
				await tree.process_frame
			await hold.call(0.6, false)
			var short_ok: bool = ops._act.visible and not Characters.can_undo()
			await hold.call(ops.HOLD_RESET + 0.4, false)
			var mouse_ok: bool = not ops._act.visible and String(Characters.undo_info().get("op", "")) == "campaign"
			Characters.undo()
			ops._open_action("delete", target)
			for _f in 3:
				await tree.process_frame
			await hold.call(ops.HOLD_DELETE + 0.4, true)
			var key_ok: bool = not Characters.has(target)
			Characters.undo()
			ops._rebuild()
			if short_ok and mouse_ok and key_ok and Characters.has(target):
				print("[UI-FIT] PASS  OPERATORZY: krótkie przytrzymanie nic nie robi, pełne myszą (2 s) resetuje, [Enter] trzymany 3 s usuwa")
			else:
				_fail("OPERATORZY: przytrzymanie — krótkie bez skutku=%s, mysz=%s, klawisz=%s" % [str(short_ok), str(mouse_ok), str(key_ok)])
		layer.queue_free()
		await tree.process_frame
	# przełączenie postaci (Characters.activate): profil i kryptonim wybranej, nie poprzedniej
	var pf := ConfigFile.new()
	pf.set_value("profile", "xp", 760)
	pf.save(Characters.dir_of(String(ids[2])) + "profile.cfg")
	Profile.persist = true                       # odczyt z katalogu testu (Characters.persist zostaje false — bez zapisu poprzedniej)
	var ok: bool = Characters.activate(String(ids[2]))
	var got_xp: int = Profile.xp
	var got_name := Characters.callsign()
	Profile.persist = false
	Profile.reset_for_test()
	if not ok or got_xp != 760 or got_name != String(Characters.meta(String(ids[2]))["name"]):
		_fail("OPERATORZY: przełączenie postaci — XP %d (oczekiwano 760), kryptonim „%s”" % [got_xp, got_name])
	else:
		print("[UI-FIT] PASS  OPERATORZY: przełączenie postaci wczytuje jej profil (XP %d) i kryptonim „%s”" % [got_xp, got_name])
	_rm_tree(ROOT)
	Characters.use_root(Characters.ROOT)

## Menu główne (MAIN_MENU_PLAN.md §7) po angielsku i po polsku w 1280×720, 1920×1080, 2560×1440 i 1280×800 (SubViewport w tym
## rozmiarze): tekst rysowany w kartach mieści się (Painted.clipped) przy fokusie na każdym elemencie, nic nie wychodzi poza ekran,
## strefy na siebie nie wchodzą, tekst ≥ 12 px, w spoczynku ≤ 70 słów. Raz: siatka fokusu dochodzi do 8 elementów, akcje wysyłają
## swoje sygnały (bez drugiego kliknięcia WYJŚCIA i bez przełącznika AI — ten zapisuje ustawienia), DOŁĄCZ bez Steama, szuflada
## (od razu z klawiatury, po opóźnieniu pod kursorem, „Reduce effects”), podpowiedzi pada. Najdłuższy kryptonim (16 × „W”).
func _main_menu_checks(host: Node) -> void:
	var tree := host.get_tree()
	var keep_name: String = Characters._override_name
	Characters._override_name = "WWWWWWWWWWWWWWWW"
	var before := _fails
	for loc in LOCALES:
		TranslationServer.set_locale(loc)
		for sz in MENU_SIZES:
			var svp := SubViewport.new()
			svp.size = sz
			host.add_child(svp)
			var m: Control = MainMenu.new()
			svp.add_child(m)
			for _f in 3:
				await tree.process_frame
			var tag := "%s %dx%d" % [loc, sz.x, sz.y]
			for n in m.focusables():
				(n as Control).grab_focus()
				await tree.process_frame
				_menu_clipped(m, "%s, fokus %s" % [tag, _menu_name(n)])
			_menu_bounds(m, tag, Rect2(Vector2.ZERO, Vector2(sz)))
			if sz == MENU_SIZES[0]:
				m.focus_first()
				await tree.process_frame
				await tree.process_frame
				var words := _menu_words(m)
				if words > MENU_WORDS:
					_fail("%s menu główne: w spoczynku %d słów (limit %d)" % [tag, words, MENU_WORDS])
				else:
					print("[UI-FIT] PASS  %s menu główne: w spoczynku %d słów (≤ %d)" % [tag, words, MENU_WORDS])
				if loc == "en":
					await _menu_behaviour(m, tree)
			svp.queue_free()
			await tree.process_frame
	Characters._override_name = keep_name
	if _fails == before:
		print("[UI-FIT] PASS  menu główne: EN/PL × 1280×720, 1920×1080, 2560×1440, 1280×800 — tekst w kartach, ekran, strefy, ≥ %d px" % MENU_MIN_PX)


func _menu_name(n: Control) -> String:
	for p in ["title", "label"]:
		var v: Variant = n.get(p)
		if v != null and String(v) != "":
			return String(v)
	return n.get_class()


## Napisy rysowane w _draw, które nie mieszczą się w swoim miejscu, i rozmiar poniżej MENU_MIN_PX (także w etykietach).
func _menu_clipped(m: Control, tag: String) -> void:
	for n in m.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		if c.get("clipped") != null:
			for t in (c.get("clipped") as PackedStringArray):
				var key := "menu|%s|%s" % [tag.get_slice(",", 0), t]
				if not _seen.has(key):
					_seen[key] = true
					_fail("%s: „%s” nie mieści się" % [tag, t])
			if (c.get("drawn") as PackedStringArray).size() > 0 and int(c.get("min_px")) < MENU_MIN_PX:
				_fail("%s: tekst %d px w %s" % [tag, int(c.get("min_px")), c.get_class()])
		elif c is Label and c.get_theme_font_size("font_size") < MENU_MIN_PX:
			var key := "menu|px|%s" % (c as Label).text
			if not _seen.has(key):
				_seen[key] = true
				_fail("%s: etykieta %s ma %d px" % [tag, _desc(c), c.get_theme_font_size("font_size")])


## Strefy na ekranie i bez nakładania: tytuł nad listą, lista z lewej od prawej kolumny, cytat przed podpowiedziami.
func _menu_bounds(m: Control, tag: String, vp: Rect2) -> void:
	var k: float = (m._root as Control).scale.x
	var player: Control = m._player
	var pr := Rect2(player.get_global_rect().position, Vector2(player.size.x, player.H_OPEN) * k)
	var zones := {"tytuł": (m._title_box as Control).get_global_rect(), "karta operatora": pr,
		"łączność drużyny": (m._squad as Control).get_global_rect(), "szuflada": (m._drawer as Control).get_global_rect(),
		"podpowiedzi": (m._hints as Control).get_global_rect()}
	for c in m._cards:
		zones["karta " + String(c.title)] = (c as Control).get_global_rect()
	for z in zones:
		if not vp.encloses((zones[z] as Rect2).grow(-SLACK)):
			_fail("%s menu główne: %s %s poza ekranem %s" % [tag, z, zones[z], vp])
	var first: Rect2 = (m._cards[0] as Control).get_global_rect()
	if zones["tytuł"].end.y > first.position.y + SLACK:
		_fail("%s menu główne: tytuł (do y %.0f) wchodzi na kartę kampanii (y %.0f)" % [tag, zones["tytuł"].end.y, first.position.y])
	var left_end: float = (m._drawer as Control).get_global_rect().end.x
	for z in ["karta operatora", "łączność drużyny"]:
		if zones[z].position.x < left_end + 8.0 * k:
			_fail("%s menu główne: %s (x %.0f) za blisko listy (do x %.0f)" % [tag, z, zones[z].position.x, left_end])
	var q: Rect2 = (m._quote as Control).get_global_rect()
	if q.end.x > zones["podpowiedzi"].position.x + SLACK:
		_fail("%s menu główne: cytat (do x %.0f) wchodzi na podpowiedzi (x %.0f)" % [tag, q.end.x, zones["podpowiedzi"].position.x])


## Słowa widoczne w spoczynku: napisy rysowane i etykiety (bez ukrytego cytatu), liczone jako ciągi z literą albo cyfrą.
func _menu_words(m: Control) -> int:
	var words := 0
	var re := RegEx.create_from_string("[\\p{L}\\p{N}]")
	for n in m.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.modulate.a < 0.01:
			continue
		var texts: Array = []
		if c.get("drawn") != null:
			texts = Array(c.get("drawn") as PackedStringArray)
		elif c is Label:
			texts = [(c as Label).text]
		for t in texts:
			for w in String(t).split(" ", false):
				if re.search(w) != null:
					words += 1
	return words


## Siatka fokusu, akcje, DOŁĄCZ bez Steama, szuflada (klawiatura / mysz / „Reduce effects”), podpowiedzi pada.
func _menu_behaviour(m: Control, tree: SceneTree) -> void:
	var nodes: Array = m.focusables()
	var seen := {nodes[0]: true}
	var queue: Array = [nodes[0]]
	while not queue.is_empty():
		var n: Control = queue.pop_front()
		for p in [n.focus_neighbor_top, n.focus_neighbor_bottom, n.focus_neighbor_left, n.focus_neighbor_right]:
			var t := n.get_node_or_null(p)
			if t != null and not seen.has(t):
				seen[t] = true
				queue.append(t)
	var c: Array = m._cards
	var expect := [[c[0], "focus_neighbor_bottom", c[1]], [c[0], "focus_neighbor_right", m._player],
		[c[1], "focus_neighbor_right", m._ai], [c[2], "focus_neighbor_right", m._join], [c[2], "focus_neighbor_bottom", m._settings],
		[m._join, "focus_neighbor_bottom", m._quit], [m._settings, "focus_neighbor_right", m._quit], [m._quit, "focus_neighbor_top", m._join]]
	var grid_ok := seen.size() == nodes.size()
	if not grid_ok:
		_fail("menu główne: siatka fokusu dochodzi do %d z %d elementów" % [seen.size(), nodes.size()])
	for e in expect:
		if (e[0] as Control).get_node_or_null((e[0] as Control).get(e[1])) != e[2]:
			grid_ok = false
			_fail("menu główne: %s.%s nie prowadzi do oczekiwanego elementu" % [_menu_name(e[0]), e[1]])
	c[1].grab_focus()
	await tree.process_frame
	var back: bool = (m._ai as Control).get_node_or_null(m._ai.focus_neighbor_left) == c[1]
	if grid_ok and back:
		print("[UI-FIT] PASS  menu główne: siatka fokusu dochodzi do %d elementów, „w lewo” wraca do ostatniej karty" % nodes.size())
	elif not back:
		_fail("menu główne: „w lewo” z prawej kolumny nie wraca do ostatniej karty")
	# akcje
	var got := []
	m.play_requested.connect(func() -> void: got.append("play:" + String(m.entry)))
	m.operators_requested.connect(func() -> void: got.append("operators"))
	m.settings_requested.connect(func() -> void: got.append("settings"))
	for n in [c[0], c[1], m._join, c[2], m._player, m._settings, m._quit]:
		(n as Control).emit_signal("pressed")
	var want := ["play:host", "play:night", "play:join", "operators", "operators", "settings"]
	if got != want or m._quit.label != "CLICK AGAIN TO QUIT":
		_fail("menu główne: akcje %s (oczekiwano %s), WYJŚCIE „%s”" % [got, want, m._quit.label])
	else:
		print("[UI-FIT] PASS  menu główne: kampania, Nocny Dyżur, dołączanie, operatorzy (karta i portret), ustawienia, potwierdzenie wyjścia")
	if m._ai.toggle != (1 if Settings.ai_companion else 0):
		_fail("menu główne: przełącznik AI nie pokazuje Settings.ai_companion")
	m.set_steam_available(false)
	var lan_ok: bool = m._join.sub == "LAN / IP" and (m._join as Control).focus_mode == Control.FOCUS_ALL
	m.set_steam_available(true)
	lan_ok = lan_ok and m._join.sub == "LAN / STEAM"
	m.set_steam_available(false)
	if lan_ok:
		print("[UI-FIT] PASS  menu główne: DOŁĄCZ aktywne bez Steama (LAN / IP), ze Steamem LAN / STEAM")
	else:
		_fail("menu główne: DOŁĄCZ bez Steama — podpis „%s”, fokus %d" % [m._join.sub, (m._join as Control).focus_mode])
	# szuflada: klawiatura od razu, mysz po opóźnieniu, „Reduce effects” — od razu i bez animacji
	c[1].grab_focus()
	await tree.process_frame
	var key_ok: bool = m._drawer.title == "NIGHT SHIFT" and m._drawer.pairs.size() == 4
	c[2].via_mouse = true
	c[2].grab_focus()
	var early: bool = m._drawer.title == "NIGHT SHIFT"
	await tree.create_timer(m.DRAWER_DELAY + 0.1).timeout
	var mouse_ok: bool = early and m._drawer.title == "OPERATORS"
	Settings.reduce_fx = true
	c[0].via_mouse = true
	c[0].grab_focus()
	var still_ok: bool = m._drawer.title == "CAMPAIGN" and is_equal_approx(float(m._drawer.fade), 1.0)
	var stage: Control = m._scene
	stage._process(5.0)
	still_ok = still_ok and is_equal_approx(float(stage._pan.scale.x), float(stage._cover))
	Settings.reduce_fx = false
	if key_ok and mouse_ok and still_ok:
		print("[UI-FIT] PASS  menu główne: szuflada od razu z klawiatury, pod kursorem po %.2f s, „Reduce effects” bez opóźnienia, animacji i najazdu" % m.DRAWER_DELAY)
	else:
		_fail("menu główne: szuflada — klawiatura %s, mysz %s, Reduce effects %s" % [str(key_ok), str(mouse_ok), str(still_ok)])
	# podpowiedzi pada
	var keep_pad := Actions.pad_mode
	Actions.pad_mode = true
	await tree.process_frame
	await tree.process_frame
	var caps := []
	for h in (m._hints as Control).get_children():
		if not h.is_queued_for_deletion():
			caps.append(((h.get_child(0) as Control).get_child(0) as Label).text)
	Actions.pad_mode = keep_pad
	if caps.size() == 3 and String(caps[1]) == Actions.text("menu_accept", true, Actions.DEV_PAD).to_upper() \
			and String(caps[2]) == Actions.text("pause", true, Actions.DEV_PAD).to_upper():
		print("[UI-FIT] PASS  menu główne: podpowiedzi pada %s" % [caps])
	else:
		_fail("menu główne: podpowiedzi pada %s" % [caps])


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

## Bestiariusz z odkrywaniem (1.7.407): nieznany wpis zakryty, spotkanie odsłania, zabójstwo liczy, profil sprzed 1.7.407 z postępem zna wszystko.
func _bestiary_checks() -> void:
	Profile.bestiary = {}
	var beasts: Array = Codex.bestiary()
	var cutpurse: Dictionary = beasts[0]
	var hidden := Codex.beast_view(cutpurse)
	var stalker: Dictionary = beasts.filter(func(e: Dictionary) -> bool: return e.get("beast", "") == "stalker")[0]
	var ok: bool = hidden["title"] == "???" and (hidden["stats"] as Array).is_empty() and String(hidden["tip"]) == "" 		and bool((hidden["portrait"] as Dictionary).get("unknown", false)) and Codex.beast_view(stalker)["title"] == "STALKER"
	Profile.discover("trzosek")
	var shown := Codex.beast_view(cutpurse)
	ok = ok and shown["title"] == cutpurse["title"] and (shown["stats"] as Array).any(func(r: Array) -> bool: return r[0] == "Your kills" and r[1] == "0")
	Profile.note_beast_kill("trzosek")
	Profile.note_beast_kill("trzosek")
	Profile.note_beast_kill("wolek")
	ok = ok and Profile.beast_kills("trzosek") == 2 and Profile.knows("wolek") and not Profile.knows("vein")
	var path := "user://uifit_bestiary.cfg"
	var cases := [[{"xp": 500}, "vein", true], [{"xp": 0}, "trzosek", false], [{"xp": 500, "bestiary": {"skoczek": 3}}, "trzosek", false]]
	for c in cases:
		var cfg := ConfigFile.new()
		for k in c[0]:
			cfg.set_value("profile", String(k), c[0][k])
		cfg.save(path)
		Profile.load_from(path)
		ok = ok and Profile.knows(String(c[1])) == bool(c[2])
	ok = ok and Profile.beast_kills("skoczek") == 3
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.reset_for_test()
	if ok:
		print("[UI-FIT] PASS  bestiariusz: nieznany wpis zakryty, spotkanie odsłania, zabójstwa liczone, stary profil z postępem zna wszystko")
	else:
		_fail("bestiariusz z odkrywaniem: zakrycie / odsłonięcie / licznik / migracja")

## Znaczniki „nowe” (1.7.409): odblokowany perk i spotkany wróg mają kropkę do obejrzenia, Stalker nie; profil bez listy obejrzanych nie dostaje kropek.
func _new_marks_checks() -> void:
	Profile.reset_for_test()
	var ok: bool = not Profile.is_new("perk:quiet_steps")
	Profile.add_xp(300, "test")                                     # poziom 2: pierwsze perki
	ok = ok and Profile.is_unlocked("quiet_steps") and Profile.is_new("perk:quiet_steps")
	Profile.mark_seen("perk:quiet_steps")
	ok = ok and not Profile.is_new("perk:quiet_steps") and Profile.is_new("perk:smith")
	Profile.discover("trzosek")
	ok = ok and Profile.is_new("beast:trzosek") and not Profile.is_new("beast:stalker")
	var path := "user://uifit_seen.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "xp", 800)
	cfg.set_value("profile", "bestiary", {"wolek": 1})
	cfg.save(path)
	Profile.load_from(path)
	ok = ok and not Profile.is_new("perk:smith") and not Profile.is_new("beast:wolek")
	Profile.discover("skoczek")
	ok = ok and Profile.is_new("beast:skoczek")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.reset_for_test()
	if ok:
		print("[UI-FIT] PASS  znaczniki „nowe”: nowy perk i wróg z kropką do obejrzenia, stary profil bez kropek")
	else:
		_fail("znaczniki „nowe”: nowy / obejrzany / migracja")

func _check_tab(pm: Control, loc: String, t: int, what := "") -> void:
	var card: Control = pm._card
	var vp := Rect2(Vector2.ZERO, pm.get_viewport_rect().size)
	var cr := card.get_global_rect()
	if cr.position.x < vp.position.x - SLACK or cr.end.x > vp.end.x + SLACK:
		_fail("%s %s: karta %s wychodzi poza ekran %s" % [loc, TAB_NAMES[t], cr, vp])
	var bad := 0
	for n in card.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x <= 0.0 or c is ScrollBar:
			continue
		var clip := _clip_rect(c, card)
		var r := c.get_global_rect()
		if r.end.x > clip.end.x + SLACK or r.position.x < clip.position.x - SLACK:
			var key := "%s|%d|%s" % [loc, t, _desc(c) if (c is Label or c is Button) else c.get_class()]
			if _seen.has(key):
				continue
			_seen[key] = true
			bad += 1
			if bad <= 4:
				_fail("%s %s%s: %s %s wystaje poza %s (o %.0f px)" % [loc, TAB_NAMES[t], what, c.get_class(), _desc(c), clip,
					maxf(r.end.x - clip.end.x, clip.position.x - r.position.x)])
	if bad > 4:
		_fail("%s %s%s: … i jeszcze %d kontrolek" % [loc, TAB_NAMES[t], what, bad - 4])


## Prostokąt najbliższego przodka, który przycina zawartość (clip_contents, przewijana lista), albo karty.
func _clip_rect(c: Control, card: Control) -> Rect2:
	var p := c.get_parent()
	while p != null and p != card:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			return (p as Control).get_global_rect()
		p = p.get_parent()
	return card.get_global_rect()


func _desc(c: Control) -> String:
	if c is Label:
		return "„%s”" % (c as Label).text.left(40)
	if c is Button:
		return "„%s”" % (c as Button).text.left(40)
	return String(c.name)


func _fail(msg: String) -> void:
	_fails += 1
	print("[UI-FIT] FAIL  " + msg)
