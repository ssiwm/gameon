extends RefCounted
## Test mieszczenia się interfejsu w każdym języku: buduje menu pauzy (ustawienia, kodeks, sterowanie) po angielsku i po polsku
## i sprawdza, czy żadna widoczna kontrolka nie wystaje w poziomie poza obszar, który ją przycina (przewijana lista, strona, karta),
## a karta — poza ekran. Polskie teksty są dłuższe: segmenty („OGRANICZONE”, „ADAPTACYJNY”) i opisy wypychały prawą kolumnę
## ustawień i opisy kodeksu poza kartę.
##   godot --headless --path prototype -- --uifittest     → ostatni wiersz: PASS / FAIL (flaga w main.gd, bo menu potrzebuje autoloadów)

const PauseMenu := preload("res://scripts/pause_menu.gd")

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
	print("[UI-FIT] %s (%d błędów)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return _fails


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
