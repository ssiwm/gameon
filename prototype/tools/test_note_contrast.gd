extends SceneTree
## Test kontrastu notatek (UiTheme.note_palette, MESSAGES_PLAN.md §4): gra toczy się w nocy, więc papier nie może jaśnieć (luminancja tła <= 0,3),
## a tekst ma zostać czytelny (WCAG: tekst >= 4,5:1, duże pismo i tytuły >= 3:1). Pilnuje, żeby przyszłe poprawki palety nie rozjaśniły notatek
## ani nie pogorszyły czytelności.
##   godot --headless --path prototype -s tools/test_note_contrast.gd     → ostatni wiersz: PASS / FAIL

const NotePalette := preload("res://scripts/note_palette.gd")

const MAX_BG_LUMINANCE := 0.30
const MIN_TEXT := 4.5
const MIN_LARGE := 3.0

var _fails := 0


func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _ratio(a: Color, b: Color) -> float:
	var x := _lum(a)
	var y := _lum(b)
	return (maxf(x, y) + 0.05) / (minf(x, y) + 0.05)


func _check(name: String, ok: bool) -> void:
	print("[NOTE-CONTRAST] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _init() -> void:
	var names := ["akta sztabu", "wydruk z radia", "kartka odręczna"]
	for m in NotePalette.PALETTES.size():
		var pal: Dictionary = NotePalette.palette(m)
		# tło notatki bierzemy z obu końców gradientu (górny i dolny kolor papieru)
		for key in ["bg", "bg2"]:
			var bg: Color = pal[key]
			_check("%s: luminancja tła %s = %.2f <= %.2f" % [names[m], key, _lum(bg), MAX_BG_LUMINANCE], _lum(bg) <= MAX_BG_LUMINANCE)
			_check("%s: tekst (ink) na %s %.1f:1 >= %.1f" % [names[m], key, _ratio(pal["ink"], bg), MIN_TEXT], _ratio(pal["ink"], bg) >= MIN_TEXT)
			_check("%s: tekst przygaszony (dim) na %s %.1f:1 >= %.1f" % [names[m], key, _ratio(pal["dim"], bg), MIN_TEXT], _ratio(pal["dim"], bg) >= MIN_TEXT)
			_check("%s: tytuł (accent) na %s %.1f:1 >= %.1f" % [names[m], key, _ratio(pal["accent"], bg), MIN_LARGE], _ratio(pal["accent"], bg) >= MIN_LARGE)
	# papier kart stanowisk (STATION_CARDS_PLAN.md E1): tło i plama lampy <= 0,3, atrament, przygaszony, zysk, koszt i cena >= 4,5:1 na obu
	var inks := {"STATION_INK": NotePalette.STATION_INK, "STATION_INK_MUTED": NotePalette.STATION_INK_MUTED, "STATION_INK_GAIN": NotePalette.STATION_INK_GAIN,
		"STATION_INK_COST": NotePalette.STATION_INK_COST, "STATION_INK_PRICE": NotePalette.STATION_INK_PRICE}
	var papers := {"STATION_PAPER": NotePalette.STATION_PAPER, "STATION_PAPER_SEL": NotePalette.STATION_PAPER_SEL}
	for bg_name in papers:
		var bg: Color = papers[bg_name]
		_check("karta stanowiska: luminancja %s = %.2f <= %.2f" % [bg_name, _lum(bg), MAX_BG_LUMINANCE], _lum(bg) <= MAX_BG_LUMINANCE)
		for ink_name in inks:
			var ink: Color = inks[ink_name]
			_check("karta stanowiska: %s na %s %.1f:1 >= %.1f" % [ink_name, bg_name, _ratio(ink, bg), MIN_TEXT], _ratio(ink, bg) >= MIN_TEXT)
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
