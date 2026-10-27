extends RefCounted
## Test mieszczenia się interfejsu w każdym języku: buduje menu pauzy (ustawienia, kodeks, sterowanie) po angielsku i po polsku
## i sprawdza, czy żadna widoczna kontrolka nie wystaje w poziomie poza obszar, który ją przycina (przewijana lista, strona, karta),
## a karta — poza ekran. Polskie teksty są dłuższe: segmenty („OGRANICZONE”, „ADAPTACYJNY”) i opisy wypychały prawą kolumnę
## ustawień i opisy kodeksu poza kartę.
##   godot --headless --path prototype -- --uifittest     → ostatni wiersz: PASS / FAIL (flaga w main.gd, bo menu potrzebuje autoloadów)

const PauseMenu := preload("res://scripts/pause_menu.gd")
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
	TranslationServer.set_locale(keep)
	_bestiary_checks()
	print("[UI-FIT] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return _fails


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
