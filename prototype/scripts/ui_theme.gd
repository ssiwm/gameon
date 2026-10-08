extends RefCounted
## Shared UI theme: readable in the dark (outlined text), consistent panels,
## buttons and inputs. Built in code so the look lives in one place.

const ACCENT := Color(1.0, 0.72, 0.28)        ## amber — objectives, highlights
const DANGER := Color(1.0, 0.28, 0.22)
const OK := Color(0.45, 1.0, 0.55)
const TEXT := Color(0.92, 0.92, 0.94)
const MUTED := Color(0.62, 0.64, 0.68)
const PANEL_BG := Color(0.07, 0.058, 0.046, 0.88)       ## ciepła, ciemna „deska” — panele należą do świata kryjówki, nie do arkusza kalkulacyjnego
const PANEL_EDGE := Color(0.46, 0.36, 0.22, 0.9)         ## mosiężna krawędź
const PANEL_EDGE_LOW := Color(0.30, 0.23, 0.13, 1.0)     ## dolna, grubsza krawędź (fałd materiału)
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

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 3)

	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "PanelContainer", panel_box())

	var normal := _box(Color(0.10, 0.11, 0.14, 0.95), Color(1, 1, 1, 0.10))
	var hover := _box(Color(0.16, 0.15, 0.13, 0.98), ACCENT.darkened(0.2))
	var pressed := _box(Color(0.22, 0.17, 0.08, 1.0), ACCENT)
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

	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 6)
	_theme = t
	return t

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

## Pikselowa czcionka nagłówków (null, gdy pliku brak — wtedy zostaje czcionka motywu).
static func heading_font() -> Font:
	if hd_on():
		if _heading_font == null:
			var fv := FontVariation.new()                     # czysty krój motywu: pogrubiony, z rozstrzeleniem liter (techniczny, wersaliki)
			fv.base_font = ThemeDB.fallback_font
			fv.variation_embolden = 0.55
			fv.spacing_glyph = 1
			_heading_font = fv
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
