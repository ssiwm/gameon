extends RefCounted
## Shared UI theme: readable in the dark (outlined text), consistent panels,
## buttons and inputs. Built in code so the look lives in one place.

## Paleta (UI_PLAN.md §3): prawie wszystko to kość słoniowa na niemal czarnym tle. Krew (DANGER) jest racjonowana —
## niebezpieczeństwo, aktywny punkt, tytuł; przygasająca lampa (ACCENT) to jedyne ciepłe światło: bezpieczne miejsca i nagrody.
const ACCENT := Color(0.851, 0.573, 0.18)      ## #D9922E lampa — cel, wyróżnienia
const DANGER := Color(0.898, 0.282, 0.227)     ## #E5483A krew
const OK := Color(0.541, 0.659, 0.475)         ## #8AA879 mech
const CALM := Color(0.435, 0.639, 0.608)       ## #6FA39B mgła (spokój)
const TEXT := Color(0.851, 0.831, 0.765)       ## #D9D4C3 kość
const MUTED := Color(0.553, 0.541, 0.486)      ## #8D8A7C przygaszony
## Deck (System.dc.html): tło sceny, panel, linie, kość przygaszona, ciepła biel tytułów, ramki krwi i lampy.
const GROUND := Color("050605")
const DECK_BG := Color("0b0c0b")
const HAIR := Color("23221d")
const LINE := Color("2b2a25")
const LINE2 := Color("3d3a30")
const BONE_DIM := Color("9c9988")
const WARM := Color("e8e2c4")
const BLOOD_LINE := Color("6e1410")
const LAMP_LINE := Color("4a3414")
const PANEL_BG := Color(0.043, 0.047, 0.043, 0.9)        ## #0B0C0B „deck” — panele należą do świata, nie do arkusza kalkulacyjnego
const PANEL_EDGE := Color(0.33, 0.31, 0.25, 0.9)         ## przygaszona kość (dawniej mosiądz)
const PANEL_EDGE_LOW := Color(0.22, 0.20, 0.16, 1.0)     ## dolna, grubsza krawędź (fałd materiału)
## Notatki przy obiektach (MESSAGES_PLAN.md §4): trzy materiały zależne od źródła informacji i ciemna paleta po zmroku (gra toczy się w nocy,
## jasny papier świeciłby jak ekran). Luminancja tła notatki <= 0,3, tekst >= 4,5:1, duże pismo >= 3:1 — pilnuje tego tools/test_note_contrast.gd.
const NotePalette := preload("res://scripts/note_palette.gd")
const Note := NotePalette.Note
static func note_palette(mat: int) -> Dictionary:
	return NotePalette.palette(mat)

const FONT_NOTE_PRINT := "res://art/fonts/VT323-Regular.ttf"
const FONT_NOTE_HAND := "res://art/fonts/Caveat-VF.ttf"
static var _note_fonts := {}

## Krój notatki wg materiału: akta — Special Elite (maszynopis), wydruk — VT323 (matrycowy), kartka — Caveat 700 (odręczne, polskie znaki w komplecie).
static func note_font(mat: int) -> Font:
	if _note_fonts.has(mat):
		return _note_fonts[mat]
	var f: Font = null
	match mat:
		Note.PRINTOUT:
			f = _file_font(FONT_NOTE_PRINT)
		Note.SCRAWL:
			var vf := _file_font(FONT_NOTE_HAND)
			if vf != null:
				var fv := FontVariation.new()
				fv.base_font = vf
				fv.variation_opentype = {"wght": 700}
				f = fv
	if f == null:
		f = whisper_font()
	_note_fonts[mat] = f
	return f

## Rozmiar tekstu notatki wg materiału (VT323 i Caveat są drobniejsze od maszynopisu).
static func note_size(mat: int, base: int) -> int:
	match mat:
		Note.PRINTOUT:
			return int(round(float(base) * 1.45))
		Note.SCRAWL:
			return int(round(float(base) * 1.3))
	return base

## Klawisze w tekście `[E]` -> klawisz z ramką (BBCode dla RichTextLabel): ciemne pole, jasna litera, jak na klawiaturze.
static func keycaps(text: String, fg := "f0e8d4", bg := "2a211a") -> String:
	var re := RegEx.new()
	re.compile("\\[([A-Za-z0-9↑↓←→ +/\\-]{1,9})\\]")
	return re.sub(text, "[bgcolor=#" + bg + "][color=#" + fg + "] $1 [/color][/bgcolor]", true)
## Stanowiska kryjówki (warsztat i sześć pozostałych): ten sam język co ława — ciemny blat „deck”, oliwkowe kafle z mosiężną ramką
## i karta szczegółów na papierze, pisana atramentem. Papier to akta w palecie nocnej (note_palette.gd, od 1.7.415: luminancja 0,25 zamiast 0,47), atrament >= 4,5:1.
const TILE_BG := Color("22281f")
const TILE_BG_HOVER := Color("2b2f24")
const TILE_BG_SEL := Color("3b3827")
const TILE_EDGE := Color("4a4836")
const TILE_EDGE_HOVER := Color("68664b")
const PAPER := NotePalette.STATION_PAPER
const PAPER_EDGE := NotePalette.STATION_PAPER_EDGE
const PAPER_SEL := NotePalette.STATION_PAPER_SEL   ## wiersz zaznaczony na papierze: plama lampy (pasek, nie sam kolor)
const INK := NotePalette.STATION_INK
const INK_MUTED := NotePalette.STATION_INK_MUTED
const INK_GAIN := NotePalette.STATION_INK_GAIN
const INK_COST := NotePalette.STATION_INK_COST
const INK_PRICE := NotePalette.STATION_INK_PRICE
## Skala typograficzna komunikatów (MESSAGES_PLAN.md §3): cztery rozmiary w jednostkach logicznych HUD zamiast 7, 8, 9, 10, 14, 16, 21, 24 i 56.
const T_DISPLAY := 24                          ## duży alert, cyfra odliczania (cyfra: ×2)
const T_TITLE := 16                            ## tytuł notatki, tytuł karty tytułowej
const T_BODY := 10                             ## treść komunikatów
const T_CAPTION := 8                           ## podpisy, stopki, znaczniki

## Kolor semantyczny stylu komunikatu (Messages.Style): informacja, akcja, sukces, ostrzeżenie, groźba, lore.
static func msg_color(style: int) -> Color:
	match style:
		1: return ACCENT
		2: return OK
		3: return WARM
		4: return DANGER
		5: return Color("c8664f")
	return TEXT

const HEADING_FONT := "res://art/fonts/Silkscreen-Regular.ttf"   ## pikselowa czcionka nagłówków (SIL OFL, art/fonts/OFL.txt)

static var _theme: Theme
static var _hd := -1

## Dev (--newui): UI w stylu HD — gładkie wektory zamiast pikseli, czysty krój nagłówków, miękkie rogi i cień paneli. Czytane z argumentów przy
## pierwszym użyciu (HUD i menu budują się w `_ready` dzieci, zanim zadziała `Main._ready`, więc zwykła zmienna ustawiana w main.gd byłaby za późno).
static func hd_on() -> bool:
	if _hd < 0:
		var args := OS.get_cmdline_user_args()
		_hd = 1 if ("--newui" in args or Settings.hd_active()) else 0
	return _hd == 1

static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 10
	if hd_on():
		var body := _file_font(FONT_BODY)                        # opisy i ustawienia: wąski, czytelny krój (polskie znaki w komplecie)
		if body != null:
			t.default_font = body

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 3)

	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())

	var normal := _box(Color(0.082, 0.085, 0.078, 0.96), Color(1, 1, 1, 0.10))
	var hover := _box(Color(0.13, 0.125, 0.105, 0.98), ACCENT.darkened(0.2))
	var pressed := _box(Color(0.19, 0.14, 0.07, 1.0), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT, 1)
	# wyłączony przycisk (np. Steam bez wtyczki): wyraźnie przygaszony, bez reakcji na hover
	var disabled := _box(Color(0.07, 0.075, 0.09, 0.8), Color(1, 1, 1, 0.05))
	for s in [normal, hover, pressed, disabled]:
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 5
		s.content_margin_bottom = 5
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.45))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_font_size("font_size", "Button", 11)

	var edit := _box(Color(0.02, 0.025, 0.035, 0.95), Color(1, 1, 1, 0.14))
	edit.content_margin_left = 8
	edit.content_margin_right = 8
	edit.content_margin_top = 4
	edit.content_margin_bottom = 4
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), ACCENT, 1))
	var ro := _box(Color(0.03, 0.035, 0.045, 0.7), Color(1, 1, 1, 0.05))
	ro.content_margin_left = 8
	ro.content_margin_right = 8
	ro.content_margin_top = 4
	ro.content_margin_bottom = 4
	t.set_stylebox("read_only", "LineEdit", ro)
	t.set_color("font_uneditable_color", "LineEdit", MUTED.darkened(0.4))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.3))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 11)

	# suwak (głośność): ciemny tor, bursztynowe wypełnienie i prostokątny uchwyt
	var track := _box(Color("1f1e19"), Color("1f1e19"))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(TEXT, TEXT)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _grabber_icon(TEXT))
	t.set_icon("grabber_highlight", "HSlider", _grabber_icon(Color("f1ecdc")))
	t.set_icon("grabber_disabled", "HSlider", _grabber_icon(MUTED.darkened(0.4)))

	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	_theme = t
	return t

## Panel pojawia się w 160 ms (przy „Reduce effects" od razu). Tylko alfa — kontenery i tak nadpisują pozycję.
static func fade_in(c: CanvasItem) -> void:
	if Settings.fx_mult() <= 0.0 or not c.is_inside_tree():
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.16)

## Uchwyt suwaka: prostokąt 6×12 z ciemnym obrysem (generowany, bez pliku).
static func _grabber_icon(col: Color) -> ImageTexture:
	var img := Image.create(6, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.02, 0.03, 1.0))
	img.fill_rect(Rect2i(1, 1, 4, 10), col)
	return ImageTexture.create_from_image(img)

## Panel „deck": niemal czarny, 1 px linia #2B2A25, kwadratowe rogi, bez cienia i bez grubszej krawędzi (makieta HUD).
static func panel_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(6.0 / 255.0, 7.0 / 255.0, 6.0 / 255.0, 0.78)
	b.border_color = LINE
	b.set_border_width_all(1)
	b.set_corner_radius_all(0)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b

## Panel stanowiska: blat „deck” jak na ławie, ale nieprzezroczysty (okno stoi nad sceną, nie nad przyciemnieniem całego ekranu).
static func station_box() -> StyleBoxFlat:
	var b := _box(Color(DECK_BG, 0.97), PANEL_EDGE)
	b.border_width_bottom = 2
	b.border_color = PANEL_EDGE
	b.set_content_margin_all(10)
	return b

## Kafel (pole siatki) stanowiska: stan „normal”, „hover” albo „selected” — kolory przycisków stojaka na ławie.
static func tile_box(state: String) -> StyleBoxFlat:
	var b := _box(TILE_BG, TILE_EDGE)
	match state:
		"hover":
			b.border_color = TILE_EDGE_HOVER
			b.bg_color = TILE_BG_HOVER
		"selected":
			# światło jako kursor (STATION_CARDS_PLAN.md §5): kafel w snopie lampy — cieplejsze tło i ciepła krawędź zamiast pomarańczowej ramki
			b.border_color = LAMP_LINE
			b.bg_color = TILE_BG_SEL
			b.border_width_bottom = 2
	b.content_margin_left = 0
	b.content_margin_right = 0
	b.content_margin_top = 0
	b.content_margin_bottom = 0
	return b

static var _lamp_pool: GradientTexture2D

## Snop lampy nad wybranym kafelkiem stanowiska: miękka, ciepła plama (radialny gradient), rysowana pod miniaturą i napisami.
static func lamp_pool() -> GradientTexture2D:
	if _lamp_pool == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.8, 0.48, 0.30))
		g.set_color(1, Color(1.0, 0.7, 0.35, 0.0))
		g.add_point(0.45, Color(1.0, 0.76, 0.42, 0.12))
		_lamp_pool = GradientTexture2D.new()
		_lamp_pool.gradient = g
		_lamp_pool.fill = GradientTexture2D.FILL_RADIAL
		_lamp_pool.fill_from = Vector2(0.5, 0.5)
		_lamp_pool.fill_to = Vector2(1.0, 0.5)
		_lamp_pool.width = 128
		_lamp_pool.height = 128
	return _lamp_pool

static func _box(bg: Color, edge: Color, width: int = 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(width)
	b.set_corner_radius_all(2 if hd_on() else 0)
	return b

## Label helper with size/colour in one call.
static func label(text: String, size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Karta szczegółów na papierze (ława i stanowiska).
static func paper_box() -> StyleBoxFlat:
	var b := _box(PAPER, PAPER_EDGE)
	b.set_content_margin_all(7)
	return b

## Napis atramentem na papierze: bez obrysu (obrys czytelności z motywu brudzi jasne tło).
static func ink(text: String, size: int, color: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	l.add_theme_constant_override("outline_size", 0)
	return l

static var _decimal_re: RegEx

## Wartość liczbowa w zapisie języka gry: po polsku przecinek dziesiętny („3,0 s”, „0,6 → 1,5”), jak w opisach części.
## Tylko dla pól z wartościami (statystyki), nie dla nazw — „7.62 HOT” czy „M-83” zostają bez zmian.
static func num_text(text: String) -> String:
	if not TranslationServer.get_locale().begins_with("pl"):
		return text
	if _decimal_re == null:
		_decimal_re = RegEx.create_from_string("(?<=\\d)\\.(?=\\d)")
	return _decimal_re.sub(text, ",", true)

static var _heading_font: Font
static var _mono_font: Font
static var _whisper_font: Font

## Role czcionek (UI_PLAN.md): nagłówki — Big Shoulders Stencil Display (OFL), opisy i ustawienia — IBM Plex Sans Condensed (OFL),
## liczby i etykiety przyrządów — IBM Plex Mono (OFL), „szept” (ostrzeżenia, podpowiedzi, notatki) — Special Elite (Apache-2.0).
## Pliki w art/fonts/ (licencje w art/fonts/licenses/). Gdy pliku brak, zostaje SystemFont z listą zastępczą (potem domyślna).
const FONT_HEADING := "res://art/fonts/BigShouldersStencilDisplay-VF.ttf"
const FONT_BODY := "res://art/fonts/IBMPlexSansCondensed-Regular.ttf"
const FONT_BODY_BOLD := "res://art/fonts/IBMPlexSansCondensed-SemiBold.ttf"
const FONT_MONO := "res://art/fonts/IBMPlexMono-Medium.ttf"
const FONT_WHISPER := "res://art/fonts/SpecialElite-Regular.ttf"

static func _file_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var ff := load(path) as FontFile
	if ff != null:
		ff.hinting = TextServer.HINTING_NONE                         # obraz jest skalowany (canvas_items) — hinting psuł odstępy liter
		ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF
		ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return ff

static func _system(names: Array, weight := 400, spacing := 0) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(names)
	sf.font_weight = weight
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_NONE                            # obraz jest skalowany (canvas_items) — hinting psuł odstępy liter
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_HALF
	if spacing == 0:
		return sf
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = spacing
	return fv

static func mono_font() -> Font:
	if _mono_font == null:
		_mono_font = _file_font(FONT_MONO)
	if _mono_font == null:
		_mono_font = _system(["IBM Plex Mono", "Consolas", "Cascadia Mono", "Menlo", "DejaVu Sans Mono", "Courier New"], 500)
	return _mono_font

static func whisper_font() -> Font:
	if _whisper_font == null:
		_whisper_font = _file_font(FONT_WHISPER)
	if _whisper_font == null:
		_whisper_font = _system(["Special Elite", "American Typewriter", "Courier New", "Courier Prime", "DejaVu Sans Mono"], 400)
	return _whisper_font

## Etykieta liczbowa / przyrządowa (HD: monospace; klasyczna grafika zostaje przy czcionce motywu).
static func mono(l: Label) -> Label:
	if hd_on():
		l.add_theme_font_override("font", mono_font())
	return l

## Etykieta „szeptu” — maszynowa (HD).
static func whisper(l: Label) -> Label:
	if hd_on():
		l.add_theme_font_override("font", whisper_font())
	return l

static var _display_cache := {}

## Stencil (Big Shoulders Stencil Display) o podanej wadze 700..900 — tytuły, pozycje menu, przyciski. Bez pliku: SystemFont.
static func display_font(weight := 700, spacing := 0) -> Font:
	var key := weight * 100 + spacing
	if _display_cache.has(key):
		return _display_cache[key]
	var f: Font = null
	var vf := _file_font(FONT_HEADING)
	if vf != null:
		var fv := FontVariation.new()
		fv.base_font = vf
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		fv.spacing_glyph = spacing            # rozstrzelenie w tym samym FontVariation — zagnieżdżone gubi oś wagi
		f = fv
	else:
		f = _system(["Big Shoulders Stencil Display", "Bahnschrift SemiBold Condensed", "Bahnschrift Condensed", "Impact", "Arial Narrow"], weight, spacing)
	_display_cache[key] = f
	return f

## Czcionka nagłówków: HD — wąski techniczny krój (Big Shoulders / Bahnschrift Condensed / Impact…), klasyczna grafika —
## pikselowa Silkscreen (null, gdy pliku brak — wtedy zostaje czcionka motywu).
static func heading_font() -> Font:
	if hd_on():
		if _heading_font == null:
			var vf := _file_font(FONT_HEADING)               # zmienna czcionka: oś wagi ustawiona na 700
			if vf != null:
				var fv := FontVariation.new()
				fv.base_font = vf
				fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 700}
				fv.spacing_glyph = 1
				_heading_font = fv
		if _heading_font == null:
			_heading_font = _system(["Big Shoulders Stencil Display", "Big Shoulders Display", "Bahnschrift SemiBold Condensed", "Bahnschrift Condensed", "Impact", "Arial Narrow"], 700, 1)
		return _heading_font
	if _heading_font == null and ResourceLoader.exists(HEADING_FONT):
		_heading_font = load(HEADING_FONT) as Font
	return _heading_font

## Nagłówek: ta sama sygnatura co label(), ale pikselowa czcionka. Rozmiary dobieraj wielokrotnościami 8 (siatka czcionki).
static func heading(text: String, size: int, color: Color = TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, align)
	var f := heading_font()
	if f != null:
		l.add_theme_font_override("font", f)
		l.add_theme_constant_override("outline_size", 2)
	return l

## Zaokrąglony segment (HD): wypełniony kolorem albo sam obrys — zamiast kwadratów w pikselowym UI.
static func pill(ci: CanvasItem, r: Rect2, col: Color, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(r.size.y * 0.5) + 1)
	sb.anti_aliasing = true
	if filled:
		sb.bg_color = col
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = col
		sb.set_border_width_all(1)
	ci.draw_style_box(sb, r)
