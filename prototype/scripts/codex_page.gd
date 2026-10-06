extends HBoxContainer
## Strona kodeksu w menu pauzy: lista pozycji po lewej, szczegóły po prawej (portret, statystyki, opis, wskazówka).
## Dane dostarcza codex.gd; ten sam widok służy bestiariuszowi i broniom.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Sprites := preload("res://scripts/sprites.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")

const LIST_W := 104.0
const DETAIL_W := 300.0
const PORTRAIT_H := 76.0

## Portret: animowana klatka z arkusza, miniatura broni albo (boss) sylwetka rysowana w kodzie.
class Portrait extends Control:
	var spec := {}
	var _t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func show_spec(s: Dictionary) -> void:
		spec = s
		_t = 0.0
		queue_redraw()
	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if spec.get("type", "") == "sprite" or spec.get("type", "") == "vein":
			_t += delta
			queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.85))
		draw_rect(Rect2(0, size.y - 1, size.x, 1), Color(1, 1, 1, 0.08))
		match spec.get("type", ""):
			"sprite":
				_draw_sprite()
			"gun":
				_draw_gun()
			"vein":
				_draw_vein()
	func _draw_sprite() -> void:
		var sheet: String = spec["sheet"]
		if not Sprites.has(sheet):
			return
		var man: Dictionary = Sprites.manifest()["sheets"][sheet]
		var fr: Array = man["frame"]
		var an: Dictionary = man["anims"].get(spec["anim"], {"row": 0, "frames": 1, "fps": 1})
		var frame := int(_t * float(an["fps"])) % maxi(1, int(an["frames"]))
		var fw := float(fr[0])
		var fh := float(fr[1])
		var k := maxf(1.0, floorf(minf((size.x - 8.0) / fw, (size.y - 8.0) / fh)))
		var dst := Rect2(((size - Vector2(fw, fh) * k) * 0.5).round(), Vector2(fw, fh) * k)
		var src := Rect2(frame * fw, int(an["row"]) * fh, fw, fh)
		draw_texture_rect_region(Sprites.texture(Sprites.DIR + sheet + ".png"), dst, src)
		if bool(man.get("glow", false)):
			var g := Sprites.texture(Sprites.DIR + sheet + "_glow.png")
			if g != null:
				draw_texture_rect_region(g, dst, src)
	func _draw_gun() -> void:
		var tex := Sprites.texture(GunIcon.GUN_SHEET)
		if tex == null:
			return
		var k := maxf(1.0, floorf(minf((size.x - 16.0) / GunIcon.FW, (size.y - 8.0) / GunIcon.FH)))
		var gs := Vector2(GunIcon.FW, GunIcon.FH) * k
		var dst := Rect2(((size - gs) * 0.5).round(), gs)
		var src := Rect2(0, int(spec["row"]) * GunIcon.FH, GunIcon.FW, GunIcon.FH)
		var acc: Color = spec.get("color", Color.WHITE)
		draw_rect(Rect2(0, size.y - 2, size.x, 2), Color(acc.r, acc.g, acc.b, 0.8))
		for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_texture_rect_region(tex, Rect2(dst.position + o * k * 0.5, dst.size), src, Color(0, 0, 0, 0.85))
		draw_texture_rect_region(tex, dst, src)
		var g := Sprites.texture(GunIcon.GUN_GLOW)
		if g != null:
			draw_texture_rect_region(g, dst, src)
	## Żyła: masa cielsk i otwierająca się paszcza — uproszczona wersja tego, co rysuje boss.gd.
	func _draw_vein() -> void:
		var c := size * 0.5 + Vector2(0, 8)
		var breathe := 1.0 + 0.04 * sin(_t * 2.0)
		var base := Color(0.42, 0.18, 0.22)
		draw_circle(c + Vector2(0, -6), 24.0 * breathe, base)
		draw_circle(c + Vector2(-26, 0), 14.0 * breathe, base.darkened(0.15))
		draw_circle(c + Vector2(26, 0), 14.0 * breathe, base.darkened(0.1))
		draw_circle(c + Vector2(-12, -24), 11.0, base.lightened(0.05))
		draw_circle(c + Vector2(13, -22), 10.0, base.lightened(0.03))
		var maw := 3.0 + 3.0 * (0.5 + 0.5 * sin(_t * 1.3))
		draw_circle(c + Vector2(0, -4), maw + 4.0, Color(0.06, 0.02, 0.03))
		draw_circle(c + Vector2(0, -4), maw, Color(0.75, 0.25, 0.2, 0.75))
		draw_circle(c + Vector2(-9, -12), 2.0, Color(1.0, 0.7, 0.3))
		draw_circle(c + Vector2(9, -12), 2.0, Color(1.0, 0.7, 0.3))

var _entries: Array = []
var _buttons: Array[Button] = []
var _portrait: Portrait
var _title: Label
var _tag: Label
var _stats: GridContainer
var _text: Label
var _tip: Label
var _sel := -1

func setup(entries: Array) -> void:
	_entries = entries
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(LIST_W + DETAIL_W + 8.0, 0)
	# lista
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in entries.size():
		var b := Button.new()
		b.text = entries[i]["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 8)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBox = get_theme_stylebox(state, "Button").duplicate()
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			sb.content_margin_left = 6
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(select.bind(i))
		list.add_child(b)
		_buttons.append(b)
	# szczegóły
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_theme_constant_override("separation", 3)
	add_child(detail)
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(0, PORTRAIT_H)
	detail.add_child(_portrait)
	_title = UiTheme.label("", 14, UiTheme.ACCENT)
	detail.add_child(_title)
	_tag = UiTheme.label("", 8, UiTheme.MUTED)
	detail.add_child(_tag)
	_stats = GridContainer.new()
	_stats.columns = 4
	_stats.add_theme_constant_override("h_separation", 8)
	_stats.add_theme_constant_override("v_separation", 1)
	detail.add_child(_stats)
	_text = UiTheme.label("", 8, UiTheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_child(_text)
	_tip = UiTheme.label("", 8, UiTheme.ACCENT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.add_child(_tip)
	select(0)

func select(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	_sel = i
	for j in _buttons.size():
		_buttons[j].set_pressed_no_signal(j == i)
	var e: Dictionary = _entries[i]
	_portrait.show_spec(e["portrait"])
	_title.text = e["title"]
	_tag.text = e["tag"]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	for st in e["stats"]:
		_stats.add_child(UiTheme.label(st[0], 8, UiTheme.MUTED))
		_stats.add_child(UiTheme.label(st[1], 8, UiTheme.TEXT))
	_text.text = e["text"]
	_tip.text = "TIP  " + e["tip"]
