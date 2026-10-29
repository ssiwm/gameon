extends RefCounted
## Test mieszczenia się interfejsu w każdym języku: buduje menu pauzy (ustawienia, kodeks, sterowanie) po angielsku i po polsku
## i sprawdza, czy żadna widoczna kontrolka nie wystaje w poziomie poza obszar, który ją przycina (przewijana lista, strona, karta),
## a karta — poza ekran. Polskie teksty są dłuższe: segmenty („OGRANICZONE”, „ADAPTACYJNY”) i opisy wypychały prawą kolumnę
## ustawień i opisy kodeksu poza kartę.
##   godot --headless --path prototype -- --uifittest     → ostatni wiersz: PASS / FAIL (flaga w main.gd, bo menu potrzebuje autoloadów)

const PauseMenu := preload("res://scripts/pause_menu.gd")
const OperatorsScreen := preload("res://scripts/operators_screen.gd")
const Codex := preload("res://scripts/codex.gd")

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
		host.add_child(ops)
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
		for b in [ops._new_btn, ops._rename_btn, ops._back_btn]:
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
		ops.queue_free()
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
