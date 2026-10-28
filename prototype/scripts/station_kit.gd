extends RefCounted
## Wspólny korpus kart stanowisk Kryjówki (STATION_CARDS_PLAN.md §5, etap E1): tabliczka znamionowa, licznik złomu z bębnami, pieczątka
## skutku akcji, taśma z klawiszami i stany przycisku akcji. Tylko prezentacja — dane, ceny i wyniki operacji idą jak dotąd z Scrap / Profile.

const UiTheme := preload("res://scripts/ui_theme.gd")

## Tabliczki: [numer, druga linia] — sprzęt bunkra ma radziecki numer inwentarzowy Obiektu 86 (cyrylica tylko w IBM Plex Mono, decyzja D1a),
## szafka to rzecz oddziału: polska tabliczka w zieleni munduru (druga linia tłumaczona, reszta to napis na blasze — bez tłumaczenia).
const PLATES := {
	"bench": ["01", "ВЕРСТАК ОРУЖЕЙНЫЙ · ИНВ. № 86/0101"],
	"service": ["02", "СТОЛ ЧИСТКИ ОРУЖИЯ · ИНВ. № 86/0102"],
	"press": ["03", "ПРЕСС · ИНВ. № 86/0103"],
	"pyro": ["04", "ОПАСНО · ВВ · ИНВ. № 86/0104"],
	"lab": ["05", "ЛАБ. 3 · СЕКРЕТНО · ИНВ. № 86/0105"],
	"lathe": ["06", "ТОКАРНЫЙ СТАНОК 1К62 · ИНВ. № 86/0106"],
	"locker": ["07", ""],
}
## Napis pieczątki po udanej operacji (fioletowy tusz na karcie).
const STAMPS := {"bench": "FITTED", "service": "SERVICED", "press": "ORDERED", "pyro": "ISSUED", "lab": "RESEARCHED", "lathe": "ACCEPTED",
	"locker": "ENTERED"}
const STEEL := Color("34352f")
const STEEL_HI := Color("4a4b43")
const STEEL_LO := Color("1b1c18")
const SQUAD_GREEN := Color("323a29")
const SQUAD_HI := Color("465238")
const STAMP_INK := Color("4b2d70")          ## fiolet tylko jako tusz pieczątki (zasada §4.5)

## Tabliczka znamionowa w nagłówku karty: nitowana blacha z numerem stanowiska, nazwą (etykieta `title` — tę samą czyta reszta kodu i testy)
## i drugą linią (`sub`).
class StationPlate extends PanelContainer:
	var code: Label
	var title: Label
	var sub: Label
	var squad := false
	func _init(title_label: Label) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		code = UiTheme.heading("01", 22, UiTheme.BONE_DIM)
		code.add_theme_constant_override("outline_size", 0)
		row.add_child(code)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(col)
		title = title_label
		title.add_theme_constant_override("outline_size", 0)
		col.add_child(title)
		sub = UiTheme.mono(UiTheme.label("", 8, UiTheme.BONE_DIM))
		sub.add_theme_constant_override("outline_size", 0)
		col.add_child(sub)
		_restyle()
	## Stanowisko `mode`: numer, druga linia, kolor blachy (szafka oddziału — zieleń, reszta — stal bunkra).
	func set_station(mode: String) -> void:
		var p: Array = PLATES.get(mode, PLATES["bench"])
		code.text = String(p[0])
		squad = mode == "locker"
		sub.text = tr("SQUAD “QUIET HOUR” · PERSONAL LOCKER") if squad else String(p[1])
		_restyle()
		queue_redraw()
	func _restyle() -> void:
		var b := StyleBoxFlat.new()
		b.bg_color = SQUAD_GREEN if squad else STEEL
		b.border_color = STEEL_LO
		b.set_border_width_all(1)
		b.border_width_bottom = 2
		b.set_corner_radius_all(2)
		b.content_margin_left = 16
		b.content_margin_right = 16
		b.content_margin_top = 3
		b.content_margin_bottom = 3
		add_theme_stylebox_override("panel", b)
		title.add_theme_color_override("font_color", UiTheme.WARM if squad else UiTheme.TEXT)
	func _draw() -> void:
		var hi := SQUAD_HI if squad else STEEL_HI
		draw_rect(Rect2(2, 1, size.x - 4, 1), hi)                       # górna krawędź łapie światło lampy
		for p: Vector2 in [Vector2(6, 6), Vector2(size.x - 6, 6), Vector2(6, size.y - 7), Vector2(size.x - 6, size.y - 7)]:
			draw_circle(p + Vector2(0.5, 0.8), 2.4, Color(0, 0, 0, 0.5))      # nity
			draw_circle(p, 2.2, hi)
			draw_circle(p + Vector2(-0.6, -0.6), 0.9, Color(1, 1, 1, 0.18))

## Jeden bęben licznika: cyfra `digit` (z częścią ułamkową w trakcie obrotu) przewija się w pionie, okienko przycina sąsiednie cyfry.
class DrumCell extends Control:
	var digit := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		custom_minimum_size = Vector2(13, 19)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0d0e0c"))
		var font := UiTheme.mono_font()
		var fs := 13
		var d := fmod(digit, 10.0)
		var base := floorf(d)
		var frac := d - base
		for i in 2:
			var n := int(base + i) % 10
			var y := size.y * 0.5 + (float(i) - frac) * size.y + fs * 0.36
			draw_string(font, Vector2(0, y), str(n), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, UiTheme.TEXT)
		draw_rect(Rect2(0, 0, size.x, 3), Color(0, 0, 0, 0.45))           # cień obudowy nad i pod bębnem
		draw_rect(Rect2(0, size.y - 3, size.x, 3), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE2, false, 1.0)

## Licznik złomu jak mechaniczny licznik bębnowy (`shown` — wartość z częścią ułamkową, cyfry obracają się jak w liczydle).
## Wydatek obraca bębny (odliczanie w `_tick_wallet`), brak złomu — czerwony błysk i drgnięcie (`broke`).
class DrumCounter extends HBoxContainer:
	var shown := 0.0:
		set(v):
			shown = maxf(0.0, v)
			_layout_cells()
	var _cells: Array = []
	var _tw: Tween
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 1)
		var cap := UiTheme.mono(UiTheme.label(tr("SCRAP"), 8, UiTheme.MUTED))
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(cap)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(5, 0)
		add_child(gap)
		_layout_cells()
	func _layout_cells() -> void:
		var n := maxi(3, str(int(floorf(shown))).length())
		while _cells.size() < n:
			var c := DrumCell.new()
			add_child(c)
			_cells.append(c)
		for i in _cells.size():
			var c := _cells[i] as DrumCell
			c.visible = i < n
			if not c.visible:
				continue
			var place := n - 1 - i                                      # 0 = jedności (bęben po prawej)
			var p := pow(10.0, place)
			var v := shown / p
			# odometr: wyższe bębny obracają się dopiero, gdy niższe przechodzą z 9 na 0
			var whole := floorf(v)
			var frac := 0.0 if place == 0 else clampf((fmod(shown, p) - (p - 1.0)), 0.0, 1.0)
			c.digit = (v if place == 0 else whole + frac)
			c.queue_redraw()
	## Brak złomu: bębny na chwilę czerwienieją i drgają (bez drgania przy „Reduce effects”).
	func broke() -> void:
		if _tw != null and _tw.is_running():
			_tw.kill()
		modulate = Color(1.6, 0.55, 0.5)
		_tw = create_tween()
		_tw.tween_property(self, "modulate", Color.WHITE, 0.5)
		if Settings.fx_mult() > 0.0:
			var x := position.x
			var sh := create_tween()
			for dx in [3.0, -3.0, 2.0, -1.0, 0.0]:
				sh.tween_property(self, "position:x", x + dx, 0.04)

## Pieczątka skutku akcji na karcie (ZAMÓWIONO, WYDANO, ZBADANO…): fioletowy tusz, przechylona, uderza i blednie.
## Nakładka na papier karty — nie przyjmuje myszy, nie zmienia układu. „Reduce effects” — bez uderzenia, samo pojawienie się.
class Stamp extends Control:
	var text := ""
	var _a := 0.0
	var _k := 1.0
	var _tw: Tween
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func play(t: String) -> void:
		text = t
		if _tw != null and _tw.is_running():
			_tw.kill()
		_tw = create_tween()
		if Settings.fx_mult() > 0.0:
			_k = 1.45
			_a = 0.0
			_tw.tween_method(func(v: float) -> void:
				_k = lerpf(1.45, 1.0, v)
				_a = v
				queue_redraw(), 0.0, 1.0, 0.14).set_ease(Tween.EASE_IN)
		else:
			_k = 1.0
			_a = 1.0
			queue_redraw()
		_tw.tween_interval(1.5)
		_tw.tween_method(func(v: float) -> void:
			_a = v
			queue_redraw(), 1.0, 0.0, 0.6)
	func _draw() -> void:
		if _a <= 0.0 or text == "":
			return
		var font := UiTheme.heading_font()
		var fs := 15
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
		var h := fs + 8.0
		var centre := Vector2(size.x - w * 0.5 - 10.0, 26.0)
		draw_set_transform(centre, deg_to_rad(-9.0), Vector2.ONE * _k)
		var ink := Color(STAMP_INK, 0.88 * _a)
		var r := Rect2(-w * 0.5, -h * 0.5, w, h)
		draw_rect(r, ink, false, 2.0)
		draw_rect(r.grow(-3.0), Color(ink, ink.a * 0.6), false, 1.0)
		draw_string(font, Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Taśma maskująca z klawiszami pod kartą: tekst sterowania, w którym nazwy klawiszy są oznaczone `KEY_OPEN` / `KEY_CLOSE`
## (`WorkshopUi._cap`), zamienia na klawisze w ramce. Nazwy idą z rejestru akcji (`Actions`), nie literałem.
const KEY_OPEN := "\u0001"
const KEY_CLOSE := "\u0002"
static func tape_text(hint: String) -> String:
	var out := hint.replace("[", "[lb]")
	out = out.replace(KEY_OPEN, "[bgcolor=#15130e][color=#e8e2c4] ").replace(KEY_CLOSE, " [/color][/bgcolor]")
	return "[center]" + out + "[/center]"

static func tape_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color("3a362b")
	b.border_color = Color("2a271f")
	b.border_width_bottom = 1
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 3
	b.content_margin_bottom = 3
	return b

## Stany dźwigni akcji (§5): „ready” — lampa (jedyny element w kolorze lampy), „broke” — brak złomu (szary, napis krwią),
## „wait” — w toku albo nic do zrobienia (ciemny), „collect” — do odbioru (mech).
static func action_boxes(state: String) -> Dictionary:
	var bg: Color
	var fg: Color
	var edge: Color
	match state:
		"ready":
			bg = UiTheme.ACCENT
			fg = Color("1a1209")
			edge = Color("8a5a12")
		"broke":
			bg = Color("26251f")
			fg = UiTheme.DANGER.lightened(0.15)
			edge = UiTheme.BLOOD_LINE
		"collect":
			bg = UiTheme.OK
			fg = Color("0e140b")
			edge = Color("4d6141")
		_:
			bg = Color("15160f")
			fg = UiTheme.MUTED
			edge = UiTheme.LINE
	var out := {"fg": fg}
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = bg.lightened(0.08) if st == "hover" else (bg.darkened(0.12) if st == "pressed" else bg)
		b.border_color = edge
		b.set_border_width_all(1)
		b.border_width_bottom = 3 if st != "pressed" else 1
		b.set_corner_radius_all(2)
		b.content_margin_top = 5
		b.content_margin_bottom = 5
		b.content_margin_left = 10
		b.content_margin_right = 10
		out[st] = b
	return out
