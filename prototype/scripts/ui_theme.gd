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
const PANEL_BG := Color(0.043, 0.047, 0.043, 0.9)        ## #0B0C0B „deck” — panele należą do świata, nie do arkusza kalkulacyjnego
const PANEL_EDGE := Color(0.33, 0.31, 0.25, 0.9)         ## przygaszona kość (dawniej mosiądz)
const PANEL_EDGE_LOW := Color(0.22, 0.20, 0.16, 1.0)     ## dolna, grubsza krawędź (fałd materiału)
## Materiały obiektów świata (karty zakotwiczone w kryjówce): papier z tekstem tuszem.
const PAPER := Color(0.85, 0.78, 0.59)
const PAPER_EDGE := Color(0.55, 0.44, 0.24)
const INK := Color(0.17, 0.13, 0.07)
const INK_MUTED := Color(0.42, 0.34, 0.2)
const INK_ACCENT := Color(0.58, 0.22, 0.1)
## Szkic techniczny (warsztat): ciemny błękitno-zielony arkusz z jasnymi liniami rysunku.
const BP_BG := Color(0.045, 0.085, 0.10, 0.97)
const BP_LINE := Color(0.36, 0.62, 0.68)
const BP_LINE_DIM := Color(0.2, 0.36, 0.40)
const BP_TEXT := Color(0.80, 0.92, 0.92)
const BP_MUTED := Color(0.5, 0.66, 0.70)
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
	var track := _box(Color(0.03, 0.035, 0.05, 0.95), Color(1, 1, 1, 0.14))
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(Color(ACCENT, 0.55), ACCENT.darkened(0.25))
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _grabber_icon(TEXT))
	t.set_icon("grabber_highlight", "HSlider", _grabber_icon(ACCENT))
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

static func panel_box() -> StyleBoxFlat:
	var b := _box(PANEL_BG, PANEL_EDGE)
	b.set_corner_radius_all(3 if hd_on() else 0)
	if hd_on():
		b.shadow_size = 7
		b.shadow_color = Color(0, 0, 0, 0.45)
		b.shadow_offset = Vector2(0, 2)
	b.border_width_bottom = 2                       # twarda krawędź, jak w pixel arcie świata; bez zaokrągleń i cieni
	b.border_color = PANEL_EDGE
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b

## Szkic techniczny: panel warsztatu.
static func blueprint_box() -> StyleBoxFlat:
	var b := _box(BP_BG, BP_LINE)
	b.set_corner_radius_all(3 if hd_on() else 0)
	b.border_width_bottom = 2
	b.set_content_margin_all(10)
	return b

## Kafel (pole siatki) na szkicu: stan „normal”, „hover” albo „selected”.
static func tile_box(state: String) -> StyleBoxFlat:
	var b := _box(Color(0.07, 0.12, 0.14, 0.95), BP_LINE_DIM)
	b.set_corner_radius_all(2 if hd_on() else 0)
	match state:
		"hover":
			b.border_color = BP_LINE
			b.bg_color = Color(0.09, 0.15, 0.17, 0.98)
		"selected":
			b.border_color = ACCENT
			b.bg_color = Color(0.12, 0.17, 0.15, 1.0)
			b.set_border_width_all(2)
	b.content_margin_left = 0
	b.content_margin_right = 0
	b.content_margin_top = 0
	b.content_margin_bottom = 0
	return b

## Papier (karty broni i odprawy przy obiektach): jasna kartka z ciemną dolną krawędzią.
static func paper_box() -> StyleBoxFlat:
	var b := _box(PAPER, PAPER_EDGE)
	b.set_corner_radius_all(2 if hd_on() else 0)
	b.border_width_bottom = 3
	b.content_margin_left = 9
	b.content_margin_right = 9
	b.content_margin_top = 7
	b.content_margin_bottom = 7
	return b

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
