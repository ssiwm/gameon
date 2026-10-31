extends Control
## Menu główne „FIELD TERMINAL” (MAIN_MENU_PLAN.md): key art z gry (menu_stage.gd), tytuł „DEAD AIR '87”, trzy destynacje
## (KAMPANIA z jedynym wypełnionym przyciskiem, NOCNY DYŻUR, OPERATORZY), szuflada szczegółów wskazanej destynacji pod listą,
## po prawej karta operatora i ŁĄCZNOŚĆ DRUŻYNY (towarzysz AI, dołączenie), u dołu USTAWIENIA / WYJŚCIE, wersja, ostatni komunikat
## i podpowiedzi klawiszy. KAMPANIA i NOCNY DYŻUR otwierają lobby ustawione na wpis (`entry`), DOŁĄCZ — lobby na polu IP (LAN działa
## bez Steama); USTAWIENIA otwierają menu pauzy w trybie ustawień, WYJŚCIE prosi o potwierdzenie. Pokazuje je main.gd po starcie,
## gdy gra nie hostuje / nie dołącza z linii poleceń. Trudność wybiera się w lobby — tu tylko widać ją w szufladzie kampanii.
##
## Fokus (mysz, klawiatura, pad) chodzi po siatce z MAIN_MENU_PLAN.md §5; kursor nad elementem daje mu fokus, więc szuflada
## i szczegóły karty operatora odsłaniają się tak samo pod myszą i na padzie. Szuflada ma stałe miejsce — nic się nie przesuwa.
## Współrzędne w pikselach makiety 1280×720 (korzeń skalowany jak w pause_menu.gd); najmniejszy tekst 12 px.

signal play_requested                ## otwórz lobby (patrz `entry`)
signal settings_requested
signal operators_requested           ## ekran OPERATORZY (operators_screen.gd, PROFILES_PLAN.md E3)

const UiTheme := preload("res://scripts/ui_theme.gd")
const W := preload("res://scripts/ui_widgets.gd")
const Scene := preload("res://scripts/menu_stage.gd")
const SessionLog := preload("res://scripts/session_log.gd")
const Level := preload("res://scripts/level.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Look := preload("res://scripts/look.gd")
const Ops := preload("res://scripts/operators_screen.gd")
const Actions := preload("res://scripts/actions.gd")
const QUIT_CONFIRM_S := 3.0
const DRAWER_DELAY := 0.12            ## s: kursor musi chwilę zostać na karcie, zanim szuflada zmieni treść (pad i klawiatura — od razu)

const MX := 61.0                     ## margines boczny
const COL_W := 480.0                 ## lista destynacji i szuflada
const SIDE_W := 253.0                ## prawa kolumna
const CARD_Y := 283.0
const CARD_H := [133.0, 64.0, 64.0]
const GAP := 5.0
const DRAWER_Y := 560.0
const DRAWER_H := 91.0
const FOOT_H := 53.0
const SQUAD_H := 131.0

## Który wpis otworzył lobby: "host", "join" albo "night" (""/inne = domyślnie host). Czyta go main.gd.
var entry := ""

var _scene: Control
var _root: Control                   ## treść w jednostkach makiety
var _title: Label
var _title_box: Control
var _cards: Array[Card] = []
var _last_card: Card
var _drawer: Drawer
var _player: PlayerCard
var _squad: Control
var _steam_dot: Label
var _ai: Row
var _join: Row
var _foot: Control
var _settings: Link
var _quit: Link
var _ticker: Ticker
var _quote: Label
var _hints: Control
var _quit_t := 0.0
var _t := 0.0
var _steam_on := false
var _pending: Card                    ## karta czekająca na DRAWER_DELAY (mysz)
var _pending_t := 0.0
var _focus_last: Control              ## ostatni element z fokusem — dźwięk ruchu raz na element
var _quiet := false                   ## fokus ustawiany z kodu (otwarcie menu) — bez dźwięku
var _hints_pad := false

## Rysowanie tekstu z zapisem: co narysowano, najmniejszy rozmiar i napisy szersze niż dostępne miejsce (`avail`, domyślnie `max_w`)
## — sprawdza je --uifittest (tools/test_ui_fit.gd), bo tekst rysowany w _draw nie ma własnego prostokąta.
class Painted extends Control:
	var drawn := PackedStringArray()
	var clipped := PackedStringArray()
	var min_px := 99
	func _begin() -> void:
		drawn.clear()
		clipped.clear()
		min_px = 99
	func _str(f: Font, pos: Vector2, s: String, al: HorizontalAlignment, max_w: float, px: int, col: Color, avail := -1.0) -> void:
		draw_string(f, pos, s, al, max_w, px, col)
		drawn.append(s)
		min_px = mini(min_px, px)
		var room := avail if avail > 0.0 else max_w
		if room > 0.0 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room + 0.5:
			clipped.append(s)

## Element z fokusem: kursor nad nim daje mu fokus, klik / [Enter] / A — `pressed`.
class Focusable extends Painted:
	signal pressed
	var via_mouse := false            ## fokus dał kursor (szuflada czeka DRAWER_DELAY), nie klawiatura / pad
	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _notification(what: int) -> void:
		if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_ENTER and is_visible_in_tree() and not has_focus():
			via_mouse = true
			grab_focus()
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			pressed.emit()
			accept_event()

## Destynacja: numer, nazwa (stencil), podpis po prawej; kampania ma też następną misję, pasek 4 misji i wypełniony przycisk.
## Fokus: czerwona szyna 2 px, trójkąt i rozjaśnione tło (bez zmiany rozmiaru).
class Card extends Focusable:
	var num := ""
	var title := ""
	var right := ""
	var mission := ""                ## kampania: następna misja
	var cleared := -1                ## kampania: ile misji ukończonych (−1 = bez paska)
	var total := 4
	var button := ""                 ## kampania: etykieta jedynego wypełnionego przycisku
	var details: Array = []          ## [[etykieta, wartość], …] do szuflady

	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		var on := has_focus()
		var big := button != ""
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.03, 0.82 if big else 0.6))
		if on:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04))
		draw_rect(Rect2(Vector2.ZERO, size), UT.LINE2 if on else UT.LINE, false, 1.0)
		var tf := UT.display_font(900 if big else 700, 1)
		var mf := UT.mono_font()
		var ts := 39 if big else 26
		var top := 14.0 if big else (size.y - tf.get_height(ts)) * 0.5
		var base := top + tf.get_ascent(ts)
		if on:
			draw_rect(Rect2(0, 0, 2, size.y), UT.DANGER)
			var cy := top + tf.get_height(ts) * 0.5
			draw_colored_polygon(PackedVector2Array([Vector2(8, cy - 5), Vector2(15, cy), Vector2(8, cy + 5)]), UT.DANGER)
		_str(mf, Vector2(22, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UT.DANGER if on else UT.MUTED)
		var tl := tr(title)
		var tw := tf.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		_str(tf, Vector2(46, base), tl, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color("f1ecdc") if on else UT.TEXT, size.x - 46.0 - 20.0)
		if right != "":
			_str(mf, Vector2(0, size.y * 0.5 + 5.0), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 20.0, 13,
				UT.TEXT if on else UT.BONE_DIM, size.x - 20.0 - 46.0 - tw - 16.0)
		if not big:
			return
		var wf := UT.whisper_font()
		_str(wf, Vector2(46, base + 10.0 + wf.get_ascent(17)), mission, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70.0, 17, UT.TEXT)
		for i in total:
			draw_rect(Rect2(46.0 + 31.0 * i, size.y - 26.0, 26, 3), UT.ACCENT if i < cleared else UT.LINE2)
		var br := Rect2(size.x - 20.0 - 150.0, size.y - 16.0 - 36.0, 150, 36)
		draw_rect(br, UT.WARM if on else UT.TEXT)
		var bf := UT.display_font(900, 2)
		var bl := tr(button)
		var bw := bf.get_string_size(bl, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_str(bf, Vector2(br.position.x + (br.size.x - bw - 18.0) * 0.5, br.position.y + (br.size.y - bf.get_height(20)) * 0.5 + bf.get_ascent(20)),
			bl, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UT.DECK_BG, br.size.x - 30.0)
		draw_string(mf, Vector2(br.end.x - 22.0, br.position.y + 23.0), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UT.DECK_BG)

## Szuflada pod listą: nagłówek wskazanej destynacji i do 4 par etykieta–wartość (2 × 2). Miejsce zarezerwowane (tło stoi),
## myszy nie łapie; nowa treść wjeżdża w FADE_S z 6 px niżej (bez animacji przy „Reduce effects”).
class Drawer extends Painted:
	const FADE_S := 0.14
	var num := ""
	var title := ""
	var pairs: Array = []
	var fade := 1.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
	func show_card(c: Card, animate := false) -> void:
		num = c.num
		title = c.title
		pairs = c.details
		fade = 0.0 if animate else 1.0
		set_process(animate)
		queue_redraw()
	func _process(delta: float) -> void:
		fade = minf(1.0, fade + delta / FADE_S)
		queue_redraw()
		if fade >= 1.0:
			set_process(false)
	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		var mf := UT.mono_font()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.03, 0.82))
		draw_rect(Rect2(0, 0, size.x, 1), UT.LINE2)
		draw_rect(Rect2(0, 0, 2, size.y), UT.DANGER)
		var a := fade
		var dy := 6.0 * (1.0 - fade)
		_str(mf, Vector2(16, 30 + dy), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UT.DANGER, a))
		_str(mf, Vector2(16, 50 + dy), tr(title), HORIZONTAL_ALIGNMENT_LEFT, 82.0, 12, Color(UT.TEXT, a))
		draw_rect(Rect2(102, 14, 1, size.y - 28.0), UT.LINE)
		var cw := (size.x - 114.0 - 10.0) * 0.5
		for i in mini(pairs.size(), 4):
			var o := Vector2(114.0 + cw * (i % 2), 13.0 + 38.0 * float(i >> 1) + dy)
			var p: Array = pairs[i]
			_str(mf, o + Vector2(0, 12), tr(String(p[0])), HORIZONTAL_ALIGNMENT_LEFT, cw - 8.0, 12, Color(UT.MUTED, a))
			_str(mf, o + Vector2(0, 31), String(p[1]), HORIZONTAL_ALIGNMENT_LEFT, cw - 6.0, 13, Color(UT.TEXT, a))

## Karta operatora: portret, kryptonim, poziom i pasek XP; z fokusem dopisuje XP i złom (rośnie w dół, pod nią jest pusto).
class PlayerCard extends Focusable:
	const H := 84.0
	const H_OPEN := 104.0
	var callsign := ""
	var lv := 1
	var xp := 0
	var xp_need := 1
	var scrap := 0
	var portrait: Control
	func _init() -> void:
		super()
		portrait = Ops.Portrait.new()
		portrait.position = Vector2(12, 10)
		portrait.size = Vector2(45, 63)
		add_child(portrait)
	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		var on := has_focus()
		var r := Rect2(0, 0, size.x, H_OPEN if on else H)
		draw_rect(r, Color(0.03, 0.035, 0.03, 0.82))
		if on:
			draw_rect(r, Color(1, 1, 1, 0.04))
			draw_rect(Rect2(0, 0, 2, r.size.y), UT.DANGER)
		draw_rect(r, UT.LINE2 if on else UT.LINE, false, 1.0)
		var tf := UT.display_font(900, 1)
		var mf := UT.mono_font()
		var px := 24                  # długi kryptonim: mniejszy stencil, a najszerszy (16 × „W”) — węższy krój mono
		var cf: Font = tf
		while px > 16 and tf.get_string_size(callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x - 84.0:
			px -= 2
		if tf.get_string_size(callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > size.x - 84.0:
			cf = mf
			px = 14
		_str(cf, Vector2(70, 12 + tf.get_ascent(24)), callsign, HORIZONTAL_ALIGNMENT_LEFT, size.x - 84.0, px,
			Color("f1ecdc") if on else UT.TEXT)
		_str(mf, Vector2(70, 56), "LV %d" % lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UT.BONE_DIM)
		var bw := size.x - 90.0
		draw_rect(Rect2(70, 66, bw, 3), UT.LINE2)
		draw_rect(Rect2(70, 66, bw * clampf(float(xp) / float(maxi(1, xp_need)), 0.0, 1.0), 3), UT.TEXT)
		if on:
			_str(mf, Vector2(16, 96), "XP %d / %d  ·  %s %d" % [xp, xp_need, tr("SCRAP"), scrap], HORIZONTAL_ALIGNMENT_LEFT,
				size.x - 30.0, 12, UT.TEXT)

## Wiersz panelu drużyny: przełącznik (towarzysz AI) albo przycisk w ramce z podpisem i strzałką (dołączenie).
class Row extends Focusable:
	var label := ""
	var sub := ""
	var toggle := -1                 ## −1 bez przełącznika; 0 / 1 — stan
	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		var on := has_focus()
		var mf := UT.mono_font()
		if on:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04))
			draw_rect(Rect2(0, 0, 2, size.y), UT.DANGER)
		if toggle < 0:
			draw_rect(Rect2(Vector2.ZERO, size), UT.TEXT if on else UT.LINE2, false, 1.0)
			var tf := UT.display_font(700, 1)
			var sub_w := mf.get_string_size(tr(sub), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			_str(tf, Vector2(14, (size.y - tf.get_height(20)) * 0.5 + tf.get_ascent(20)), tr(label), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 20, Color("f1ecdc") if on else UT.TEXT, size.x - 34.0 - sub_w - 28.0)
			_str(mf, Vector2(0, size.y * 0.5 + 4.5), tr(sub), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 34.0, 12, UT.MUTED)
			_str(mf, Vector2(size.x - 24.0, size.y * 0.5 + 5.0), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UT.DANGER)
			return
		var sw := Rect2(size.x - 12.0 - 38.0, size.y * 0.5 - 10.0, 38, 20)
		var word := tr("ON" if toggle == 1 else "OFF")
		var ww := mf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0 if on else 0.0
		_str(mf, Vector2(12, size.y * 0.5 + 4.5), tr(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UT.TEXT if on else UT.BONE_DIM,
			sw.position.x - 12.0 - ww - 8.0)
		draw_rect(sw, Color("1c1c18") if toggle == 1 else Color("0d0e0c"))
		draw_rect(sw, UT.TEXT if toggle == 1 else UT.LINE2, false, 1.0)
		draw_rect(Rect2(sw.position + Vector2(sw.size.x - 17.0 if toggle == 1 else 3.0, 3.0), Vector2(14, 14)),
			UT.TEXT if toggle == 1 else Color("7d7a6d"))
		if on:
			_str(mf, Vector2(0, size.y * 0.5 + 4.5), word, HORIZONTAL_ALIGNMENT_RIGHT, sw.position.x - 10.0, 12, UT.TEXT)

## Odnośnik w pasku dolnym (USTAWIENIA, WYJŚCIE): mono 13, z fokusem jaśnieje i dostaje czerwone podkreślenie.
class Link extends Focusable:
	var label := "":
		set(v):
			label = v
			var f := preload("res://scripts/ui_theme.gd").mono_font()
			custom_minimum_size = Vector2(f.get_string_size(tr(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 4.0, 24)
			queue_redraw()
	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		var on := has_focus()
		_str(UT.mono_font(), Vector2(2, 16), tr(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UT.TEXT if on else UT.BONE_DIM)
		if on:
			draw_rect(Rect2(2, 21, size.x - 4.0, 1), UT.DANGER)

## OSTATNI KOMUNIKAT: dioda, etykieta i wykres fali; cytat audycji pokazuje się obok po najechaniu (main_menu._show_quote).
class Ticker extends Painted:
	func _init() -> void:
		custom_minimum_size = Vector2(180, 24)
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		_begin()
		var UT := preload("res://scripts/ui_theme.gd")
		draw_circle(Vector2(4, 12), 3.0, UT.DANGER)
		_str(UT.mono_font(), Vector2(14, 16), tr("LAST BROADCAST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UT.BONE_DIM)
		var x := UT.mono_font().get_string_size(tr("LAST BROADCAST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
		for i in 6:
			var h: float = [4.0, 9.0, 6.0, 11.0, 5.0, 8.0][i]
			draw_rect(Rect2(x + 4.0 * i, 12.0 + 5.0 - h, 2, h), UT.MUTED)
		custom_minimum_size.x = x + 26.0

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scene = Scene.new()
	add_child(_scene)
	_root = Control.new()
	add_child(_root)
	_build_title()
	_build_cards()
	_build_side()
	_build_footer()
	_wire_focus()
	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_fit)
	Settings.changed.connect(_refresh)
	Difficulty.changed.connect(func(_l: int) -> void: _refresh())
	Characters.changed.connect(_refresh)
	Profile.changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree():
			_refresh()
			_focus_quiet(_cards[0]))
	for n in focusables():
		n.focus_entered.connect(_on_focus.bind(n))
	_fit()
	_refresh()
	_focus_quiet.call_deferred(_cards[0])

func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(vp.x / 1280.0, vp.y / 720.0)       # układ ma sztywną siatkę 1280×720 — rozmiar HUD-u go nie powiększa (lista wychodziła poza ekran)
	_root.scale = Vector2(k, k)
	_root.size = vp / k
	size = vp
	_scene.fit(vp)
	_layout()

func _layout() -> void:
	var w := _root.size.x
	var h := _root.size.y
	var side_x := w - MX - SIDE_W
	_title_box.position = Vector2(MX, 23.0)
	_player.position = Vector2(side_x, 43.0)
	_squad.position = Vector2(side_x, CARD_Y + CARD_H[0] + CARD_H[1] + CARD_H[2] + GAP * 2.0 - SQUAD_H)
	_foot.position = Vector2(0, h - FOOT_H)
	_foot.size = Vector2(w, FOOT_H)
	_hints.reset_size()
	_hints.position = Vector2(w - MX - _hints.size.x, 15)
	var x := MX
	for ch in _quote.get_parent().get_children():
		if ch == _quote:
			break
		x += (ch as Control).get_combined_minimum_size().x + 18.0
	_quote.custom_minimum_size.x = maxf(0.0, _hints.position.x - x - 24.0)

func _build_title() -> void:
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 2)
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_box)
	_title_box.add_child(W.mono("DON'T MAKE A SOUND", 13, UiTheme.MUTED, 0.34))
	_title = W.stencil("DEAD AIR", 132, Color("d9d4c3"), 0.01, HORIZONTAL_ALIGNMENT_LEFT, 900)
	_title.custom_minimum_size = Vector2(520, 96)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var yr := W.stencil("'87", 64, UiTheme.DANGER, 0.0, HORIZONTAL_ALIGNMENT_LEFT, 900)
	yr.add_theme_color_override("font_outline_color", Color(UiTheme.DANGER, 0.35))
	yr.add_theme_constant_override("outline_size", 6)
	row.add_child(yr)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(200, 1)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.draw.connect(func() -> void:
		rule.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(200, 0), Vector2(200, 1), Vector2(0, 1)]),
			PackedColorArray([UiTheme.DANGER, Color(UiTheme.DANGER, 0.0), Color(UiTheme.DANGER, 0.0), UiTheme.DANGER])))
	row.add_child(rule)
	var ns := W.mono("NO SIGNAL", 12, UiTheme.MUTED, 0.2)
	ns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ns)
	_title_box.add_child(row)

## Trzy destynacje jedna pod drugą i szuflada pod nimi.
func _build_cards() -> void:
	var y := CARD_Y
	var defs := [["01", "CAMPAIGN", func() -> void: _play("host")], ["02", "NIGHT SHIFT", func() -> void: _play("night")],
		["03", "OPERATORS", func() -> void: operators_requested.emit()]]
	for i in defs.size():
		var c := Card.new()
		c.num = defs[i][0]
		c.title = defs[i][1]
		c.position = Vector2(MX, y)
		c.size = Vector2(COL_W, CARD_H[i])
		var action: Callable = defs[i][2]
		var snd := "ui_click" if i == 2 else "ui_confirm"
		c.pressed.connect(func() -> void:
			Audio.play(snd, Audio.BUS_UI, -8.0)
			action.call())
		c.focus_entered.connect(_on_card_focus.bind(c))
		_root.add_child(c)
		_cards.append(c)
		y += CARD_H[i] + GAP
	_cards[0].button = "OPEN LOBBY"
	_cards[1].right = tr("ENDLESS")
	_last_card = _cards[0]
	_drawer = Drawer.new()
	_drawer.position = Vector2(MX, DRAWER_Y)
	_drawer.size = Vector2(COL_W, DRAWER_H)
	_root.add_child(_drawer)

## Prawa kolumna: karta operatora u góry, ŁĄCZNOŚĆ DRUŻYNY na wysokości dołu listy.
func _build_side() -> void:
	_player = PlayerCard.new()
	_player.size = Vector2(SIDE_W, PlayerCard.H)
	_player.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		operators_requested.emit())
	_root.add_child(_player)
	_squad = Control.new()
	_squad.size = Vector2(SIDE_W, SQUAD_H)
	_squad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad.draw.connect(func() -> void:
		_squad.draw_rect(Rect2(Vector2.ZERO, _squad.size), Color(0.03, 0.035, 0.03, 0.82))
		_squad.draw_rect(Rect2(Vector2.ZERO, _squad.size), UiTheme.LINE, false, 1.0)
		_squad.draw_rect(Rect2(12, 36, SIDE_W - 24.0, 1), UiTheme.LINE))
	_root.add_child(_squad)
	var hl := W.mono("SQUAD LINK", 12, UiTheme.MUTED, 0.22)
	hl.position = Vector2(12, 10)
	_squad.add_child(hl)
	_steam_dot = W.mono("○ STEAM", 12, UiTheme.MUTED, 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_steam_dot.position = Vector2(12, 10)
	_steam_dot.size = Vector2(SIDE_W - 24.0, 16)
	_squad.add_child(_steam_dot)
	_ai = Row.new()
	_ai.label = "AI COMPANION"
	_ai.position = Vector2(0, 41)
	_ai.size = Vector2(SIDE_W, 37)
	_ai.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		Settings.set_ai_companion(not Settings.ai_companion)
		_refresh())
	_squad.add_child(_ai)
	_join = Row.new()
	_join.label = "JOIN SESSION"
	_join.position = Vector2(12, 41 + 37 + 6)
	_join.size = Vector2(SIDE_W - 24.0, 37)
	_join.pressed.connect(func() -> void:
		Audio.play("ui_confirm", Audio.BUS_UI, -8.0)
		_play("join"))
	_squad.add_child(_join)

func _build_footer() -> void:
	_foot = Control.new()
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot.draw.connect(func() -> void: _foot.draw_rect(Rect2(0, 0, _foot.size.x, 1), UiTheme.HAIR))
	_root.add_child(_foot)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left.position = Vector2(MX, 14)
	_foot.add_child(left)
	_settings = Link.new()
	_settings.label = "SETTINGS"
	_settings.pressed.connect(func() -> void:
		Audio.play("ui_click", Audio.BUS_UI, -10.0)
		settings_requested.emit())
	left.add_child(_settings)
	_quit = Link.new()
	_quit.label = "QUIT"
	_quit.pressed.connect(_on_quit)
	left.add_child(_quit)
	left.add_child(W.vline(UiTheme.LINE))
	var ver := W.mono("v" + SessionLog.build(), 12, Color("7d7a6d"), 0.06)
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(ver)
	_ticker = Ticker.new()
	_ticker.mouse_entered.connect(_show_quote.bind(true))
	_ticker.mouse_exited.connect(_show_quote.bind(false))
	left.add_child(_ticker)
	_quote = W.whisper("", 13, Color("bdb8a6"))
	_quote.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quote.modulate.a = 0.0
	_quote.clip_text = true
	_quote.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(_quote)
	for l in [_settings, _quit]:
		l.focus_entered.connect(_show_quote.bind(true))
		l.focus_exited.connect(_show_quote.bind(false))
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 18)
	_foot.add_child(hints)
	_hints = hints
	_build_hints()

## Podpowiedzi klawiszy z rejestru akcji (Actions.key): klawiatura ENTER / ESC, pad A / START — przełączane z Actions.pad_mode.
func _build_hints() -> void:
	_hints_pad = Actions.pad_mode
	for ch in _hints.get_children():
		_hints.remove_child(ch)
		ch.queue_free()
	for pair in [["↑↓←→", "SELECT"], [Actions.key("menu_accept"), "CONFIRM"], [Actions.key("pause"), "SETTINGS"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(W.keycap(pair[0], 12))
		h.add_child(W.mono(pair[1], 12, UiTheme.MUTED))
		_hints.add_child(h)

## Siatka fokusu z MAIN_MENU_PLAN.md §5. „W lewo” z prawej kolumny wraca do ostatniej wskazanej destynacji (_on_card_focus).
func _wire_focus() -> void:
	var c0 := _cards[0]
	var c1 := _cards[1]
	var c2 := _cards[2]
	_nb(c0, c0, c1, c0, _player)
	_nb(c1, c0, c2, c1, _ai)
	_nb(c2, c1, _settings, c2, _join)
	_nb(_player, _player, _ai, c0, _player)
	_nb(_ai, _player, _join, c0, _ai)
	_nb(_join, _ai, _quit, c0, _join)
	_nb(_settings, c2, _settings, _settings, _quit)
	_nb(_quit, _join, _quit, _settings, _quit)

func _nb(n: Control, up: Control, down: Control, left: Control, right: Control) -> void:
	n.focus_neighbor_top = n.get_path_to(up)
	n.focus_neighbor_bottom = n.get_path_to(down)
	n.focus_neighbor_left = n.get_path_to(left)
	n.focus_neighbor_right = n.get_path_to(right)
	n.focus_next = n.get_path_to(down)
	n.focus_previous = n.get_path_to(up)

## Wskazana destynacja: szuflada pokazuje jej szczegóły — od razu z klawiatury i pada, po DRAWER_DELAY pod kursorem
## (przejazd myszą przez listę nie miga treścią); „Reduce effects” — bez opóźnienia i bez animacji.
func _on_card_focus(c: Card) -> void:
	_last_card = c
	for n in [_player, _ai, _join]:
		n.focus_neighbor_left = n.get_path_to(c)
	var fx := Settings.fx_mult() > 0.0
	if c.via_mouse and fx:
		_pending = c
		_pending_t = DRAWER_DELAY
	else:
		_pending = null
		_drawer.show_card(c, fx and not _quiet)

## Wszystkie elementy z fokusem (siatka z MAIN_MENU_PLAN.md §5) — także dla testu i zrzutów.
func focusables() -> Array:
	return [_cards[0], _cards[1], _cards[2], _player, _ai, _join, _settings, _quit]

## Fokus ustawiony z kodu (otwarcie menu): bez dźwięku ruchu.
func _focus_quiet(n: Control) -> void:
	_quiet = true
	n.grab_focus()
	_focus_last = n
	_quiet = false

## Dźwięk ruchu raz na element (powrót na ten sam element i fokus z kodu — cicho).
func _on_focus(n: Control) -> void:
	(n as Focusable).via_mouse = false
	if _quiet or n == _focus_last:
		return
	_focus_last = n
	Audio.play("ui_tick", Audio.BUS_UI, -16.0)

func _show_quote(on: bool) -> void:
	_quote.modulate.a = 1.0 if on or _settings.has_focus() or _quit.has_focus() else 0.0

func _play(which: String) -> void:
	entry = which
	play_requested.emit()

func _on_quit() -> void:
	if _quit_t > 0.0:
		Audio.quit_game()
		return
	Audio.play("ui_deny", Audio.BUS_UI, -10.0)
	_quit_t = QUIT_CONFIRM_S
	_quit.label = "CLICK AGAIN TO QUIT"
	_layout()

func set_steam_available(on: bool) -> void:
	_steam_on = on
	_refresh()

func _refresh() -> void:
	if _drawer == null:
		return
	_steam_dot.text = "● STEAM" if _steam_on else "○ STEAM"           # pełna kropka = połączony (kształt, nie tylko kolor)
	_steam_dot.add_theme_color_override("font_color", UiTheme.OK if _steam_on else UiTheme.MUTED)
	_join.sub = "LAN / STEAM" if _steam_on else "LAN / IP"
	_ai.toggle = 1 if Settings.ai_companion else 0
	var cs := Characters.callsign()
	var name := cs if cs != "" else tr("UNNAMED")
	# kampania drużyny (Scrap.cleared, jak main.campaign_start_map): następna po najdalszej ukończonej, po bossie znowu 1.1
	var far := -1
	var done := 0
	for i in Level.CAMPAIGN.size():
		if Scrap.cleared.has(String(Level.CAMPAIGN[i])):
			far = i
			done += 1
	var nxt := far + 1 if far + 1 < Level.CAMPAIGN.size() else 0
	var next_title := _map_title(String(Level.CAMPAIGN[nxt]))
	var c0 := _cards[0]
	c0.mission = "%s · %s" % [tr("START CAMPAIGN") if far < 0 else tr("NEXT UP"), next_title]     # nowy gracz / reset: od 1.1
	c0.cleared = done
	c0.total = Level.CAMPAIGN.size()
	c0.details = [["NEXT MISSION", next_title], ["PROGRESS", "%d / %d" % [done, Level.CAMPAIGN.size()]],
		["DIFFICULTY", tr(Difficulty.level_name())], ["SQUAD", tr("1–4 + AI") if Settings.ai_companion else tr("1–4, NO AI")]]
	var best := "—"
	if Settings.shift_best_cleared > 0:
		best = "%d / %d" % [Settings.shift_best_cleared, NightShift.MISSIONS]
		if Settings.shift_best_time > 0.0:
			best += "  ·  %d:%02d" % [floori(Settings.shift_best_time / 60.0), int(Settings.shift_best_time) % 60]
	_cards[1].details = [["MISSIONS", "%d · %s" % [NightShift.MISSIONS, tr("RANDOM MAPS")]],
		["MODIFIERS", tr("UP TO %d PER MISSION") % NightShift.MODS_PER_MISSION.max()], ["BEST RUN", best], ["REWARD", tr("HALF XP")]]
	var last := String(Profile.last_record.get("map", ""))
	_cards[2].right = "%d / %d" % [Characters.count(), Characters.MAX]
	_cards[2].details = [["ACTIVE", name], ["OUTFIT", tr(Look.display_name(Profile.look))],
		["ROSTER", "%d / %d" % [Characters.count(), Characters.MAX]], ["LAST MISSION", _map_title(last) if last != "" else "—"]]
	for c in _cards:
		c.queue_redraw()
	if _pending == null:
		_drawer.show_card(_last_card)
	var prog: Array = Profile.level_progress()
	_player.callsign = name
	_player.lv = Profile.level()
	_player.xp = int(prog[0])
	_player.xp_need = int(prog[1])
	_player.scrap = Scrap.bank
	_player.portrait.set_code(Profile.look)
	_player.queue_redraw()
	_ai.queue_redraw()
	_join.queue_redraw()
	if _quote.text == "":
		_quote.text = tr(_NOTES[int(Time.get_ticks_msec() / 1000) % _NOTES.size()])

## Tytuł mapy do UI: przetłumaczony TITLE ze skryptu mapy, z pojedynczą spacją po numerze („1.3 GNIAZDO”).
func _map_title(id: String) -> String:
	var s: GDScript = Level.MAPS.get(id)
	if s == null:
		return id
	return tr(String(s.get_script_constant_map().get("TITLE", id))).replace("  ", " ")

const _NOTES := [
	"Extraction complete. Nobody went down. It heard us anyway.",
	"Patrol Seven, do you read? ...we went into the trees.",
	"Don't shoot unless you must. Noise carries.",
	"Crouch and the dark can't hear you.",
	"If you hear it breathing, it has already found you.",
]

func focus_first() -> void:
	_focus_quiet(_cards[0])

func _process(delta: float) -> void:
	if visible and NoiseMgr.has_network():
		visible = false                  # sesja ruszyła inną drogą niż PLAY (zaproszenie Steam, dołączenie) — menu nie może zostać na wierzchu
	if not visible:
		return
	if _pending != null:
		_pending_t -= delta
		if _pending_t <= 0.0:
			if _pending.has_focus():
				_drawer.show_card(_pending, Settings.fx_mult() > 0.0)
			_pending = null
	if Actions.pad_mode != _hints_pad:
		_build_hints()
		_layout()
	if _quit_t > 0.0:
		_quit_t -= delta
		if _quit_t <= 0.0:
			_quit.label = "QUIT"
			_layout()
	# tytuł lekko „migocze" — rzadkie, krótkie zaniki; „Reduce effects" wyłącza to razem z resztą
	_t += delta
	var dip := 0.6 if (Settings.fx_mult() > 0.0 and (fmod(_t, 7.3) < 0.09 or (fmod(_t, 11.9) > 11.7 and fmod(_t, 0.07) < 0.035))) else 1.0
	_title.modulate.a = dip
