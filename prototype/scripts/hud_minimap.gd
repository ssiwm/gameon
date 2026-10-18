extends Control
## Rzut mapy w górnym środku HUD-u (zamiast paska kierunku): okno ±38 kafli (1 kafel = 1 m) wokół gracza, 13 rzędów wysokości,
## z mgłą — widać tylko kafle, które drużyna już widziała. Teren to tekstura liczona raz z siatki poziomu (`level._map`, PX pikseli
## na kafel: wypełnienie bryły, jasna krawędź od góry, ciemniejsze boki, kładki jako linia, tło wnętrz); zawał i rozbite ściany
## przerysowują ją, gdy zmieni się siatka. Mgła to maska 1 piksel = 1 kafel, odsłaniana wokół każdego gracza. Wrogów tu nie ma
## (filarem gry jest słuch). Znaczniki (cel, wyjście, koledzy, powaleni) z dystansem w metrach; spoza okna przyklejają się do krawędzi.

const UiTheme := preload("res://scripts/ui_theme.gd")

const TILE := 16.0                ## px świata na kafel (level.TILE)
const PX := 8                     ## piksele tekstury na kafel
const HALF_COLS := 38.0           ## pół szerokości okna w kaflach
const ROWS := 13.0                ## wysokość okna w kaflach
const TILE_U := 5.0               ## jednostki HUD-u na kafel
const ABOVE := 0.6                ## część okna nad graczem (więcej widać w górę: mosty, półki, szyby)
const REVEAL := Rect2i(-14, -10, 29, 16)   ## odsłanianie mgły wokół gracza (kafle względem jego kafla; ≈ kadr kamery)
const SCAN_S := 0.5               ## co ile sekund sprawdzać zmiany siatki (zawał, rozbite ściany)

const SHADER := """
shader_type canvas_item;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform vec4 region;          // okno w UV tekstury: x, y, szerokość, wysokość
uniform float fade_x = 0.12;
uniform float fade_y = 0.1;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 q = (UV - region.xy) / region.zw;
	float e = smoothstep(0.0, fade_x, q.x) * smoothstep(0.0, fade_x, 1.0 - q.x)
			* smoothstep(0.0, fade_y, q.y) * smoothstep(0.0, fade_y, 1.0 - q.y);
	COLOR = c * COLOR;
	COLOR.a *= texture(fog, UV).r * e;
}
"""

var player_pos := Vector2.ZERO     ## pozycja gracza w świecie [px]
var markers: Array = []            ## [{pos: Vector2 świata, kind: "obj" | "exit" | "mate" | "down", label: String, col: Color}]

var _lvl = null                    ## level.gd (bez typu: pola prywatne siatki czytamy dynamicznie)
var _sig := ""                     ## identyfikator wczytanej mapy (instancja poziomu + id mapy)
var _rows_cache: Array = []
var _walls_n := -1
var _cols := 0
var _nrows := 0
var _base: Image
var _tex: ImageTexture
var _fog: Image
var _fog_tex: ImageTexture
var _fog_dirty := false
var _seen_cells := {}               ## instance_id gracza -> ostatni kafel, wokół którego odsłonięto mgłę
var _scan_t := 0.0
var _r0 := -1.0                    ## górny rząd okna (wygładzany przy skokach)
var _t := 0.0
var _map_layer: Control
var _mark_layer: Control
var _mat: ShaderMaterial

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(HALF_COLS * 2.0 * TILE_U, ROWS * TILE_U)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_map_layer = Control.new()
	_map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layer.material = _mat
	_map_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_layer.draw.connect(_draw_map)
	add_child(_map_layer)
	_mark_layer = Control.new()
	_mark_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark_layer.draw.connect(_draw_marks)
	add_child(_mark_layer)

func _process(delta: float) -> void:
	_t += delta
	if not is_visible_in_tree():
		return
	_sync_level(delta)
	if _base == null:
		return
	_reveal()
	var target := clampf(player_pos.y / TILE - ROWS * ABOVE, 0.0, maxf(0.0, float(_nrows) - ROWS))
	_r0 = target if _r0 < 0.0 else lerpf(_r0, target, minf(1.0, delta * 4.0))
	_map_layer.queue_redraw()
	_mark_layer.queue_redraw()

# ---------------------------------------------------------------- teren i mgła

func _sync_level(delta: float) -> void:
	var lvl = get_tree().get_first_node_in_group("level")
	if lvl == null or lvl.get("_map") == null or (lvl._map as Array).is_empty():
		_lvl = null
		_base = null
		return
	var sig := "%d:%s" % [lvl.get_instance_id(), String(lvl.map_id)]
	if lvl != _lvl or sig != _sig or (lvl._map as Array).size() != _nrows:
		_lvl = lvl
		_sig = sig
		_build(true)
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_S
	var walls: int = (lvl._wall_cells as Dictionary).size()
	if walls != _walls_n or not _same_rows(lvl._map):
		_build(false)

func _same_rows(rows: Array) -> bool:
	if rows.size() != _rows_cache.size():
		return false
	for i in rows.size():
		if rows[i] != _rows_cache[i]:
			return false
	return true

## Tekstura terenu z siatki poziomu; `reset_fog` przy nowej mapie (zawał i ściany zostawiają odkryte kafle).
func _build(reset_fog: bool) -> void:
	var rows: Array = _lvl._map
	_rows_cache = rows.duplicate()
	_walls_n = (_lvl._wall_cells as Dictionary).size()
	var cols: int = (rows[0] as String).length()
	var nrows := rows.size()
	var resized := cols != _cols or nrows != _nrows
	_cols = cols
	_nrows = nrows
	var bone := UiTheme.TEXT
	var c_fill := Color(bone, 0.12)
	var c_top := Color(bone, 0.78)
	var c_side := Color(bone, 0.32)
	var c_plat := Color(bone, 0.5)
	var c_back := Color(bone, 0.05)
	var c_water := Color(0.43, 0.63, 0.75, 0.45)
	var c_mud := Color(0.51, 0.39, 0.24, 0.45)
	var img := Image.create_empty(cols * PX, nrows * PX, false, Image.FORMAT_RGBA8)
	for r in nrows:
		for c in cols:
			var x := c * PX
			var y := r * PX
			if _lvl._is_solid(c, r):
				var ch: String = _lvl._ch(c, r)
				img.fill_rect(Rect2i(x, y, PX, PX), c_water if ch == "~" else (c_mud if ch == "m" else c_fill))
				if not _lvl._is_solid(c - 1, r):
					img.fill_rect(Rect2i(x, y, 1, PX), c_side)
				if not _lvl._is_solid(c + 1, r):
					img.fill_rect(Rect2i(x + PX - 1, y, 1, PX), c_side)
				if not _lvl._is_solid(c, r + 1):
					img.fill_rect(Rect2i(x, y + PX - 1, PX, 1), c_side)
				if not _lvl._is_solid(c, r - 1):
					img.fill_rect(Rect2i(x, y, PX, 2), c_top)
			elif _lvl._is_platform_cell(c, r):
				img.fill_rect(Rect2i(x, y, PX, 1), c_plat)
			else:
				var k: Array = _lvl.KINDS.get(_lvl._ch(c, r), [])
				if k.size() == 3 and int(k[2]) == 2:
					img.fill_rect(Rect2i(x, y, PX, PX), c_back)
	_base = img
	if _tex == null or resized:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	if reset_fog or resized or _fog == null:
		_fog = Image.create_empty(cols, nrows, false, Image.FORMAT_L8)
		_fog_tex = ImageTexture.create_from_image(_fog)
		_mat.set_shader_parameter("fog", _fog_tex)
		_seen_cells.clear()
		_r0 = -1.0

## Odsłania kafle wokół każdego gracza (wspólna wiedza drużyny; licz lokalnie, bez sieci).
func _reveal() -> void:
	for n in get_tree().get_nodes_in_group("players"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var lp: Vector2 = _lvl.to_local((n as Node2D).global_position)
		var cell := Vector2i(lp / TILE)
		if _seen_cells.get(n.get_instance_id(), Vector2i(-9999, -9999)) == cell:
			continue
		_seen_cells[n.get_instance_id()] = cell
		var rc := Rect2i(cell + REVEAL.position, REVEAL.size).intersection(Rect2i(0, 0, _cols, _nrows))
		for r in range(rc.position.y, rc.end.y):
			for c in range(rc.position.x, rc.end.x):
				if _fog.get_pixel(c, r).r < 0.5:
					_fog.set_pixel(c, r, Color.WHITE)
					_fog_dirty = true
	if _fog_dirty:
		_fog_dirty = false
		_fog_tex.update(_fog)

# ---------------------------------------------------------------- rysowanie

func _window() -> Rect2:
	var p: Vector2 = _lvl.to_local(player_pos) / TILE
	return Rect2(p.x - HALF_COLS, _r0, HALF_COLS * 2.0, ROWS)

func _draw_map() -> void:
	if _base == null or _tex == null:
		return
	var win := _window()
	var full := Vector2(_cols, _nrows)
	_mat.set_shader_parameter("region", Vector4(win.position.x / full.x, win.position.y / full.y, win.size.x / full.x, win.size.y / full.y))
	var src := win.intersection(Rect2(Vector2.ZERO, full))
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	var k := size.x / win.size.x
	var dst := Rect2((src.position - win.position) * k, src.size * k)
	_map_layer.draw_texture_rect_region(_tex, dst, Rect2(src.position * PX, src.size * PX))

func _to_screen(world: Vector2, win: Rect2) -> Vector2:
	var l: Vector2 = _lvl.to_local(world)
	return (l / TILE - win.position) * (size.x / win.size.x)

func _draw_marks() -> void:
	if _base == null:
		return
	var win := _window()
	var f := UiTheme.mono_font()
	var me := _to_screen(player_pos, win)
	var taken: Array = []
	var order := markers.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).distance_squared_to(player_pos) < (b["pos"] as Vector2).distance_squared_to(player_pos))
	var inner := Rect2(Vector2(6, 5), size - Vector2(12, 10))
	for m in order:
		var wp: Vector2 = m["pos"]
		var s := _to_screen(wp, win)
		var edge := not inner.has_point(s)
		s = s.clamp(inner.position, inner.end)
		var kind := String(m["kind"])
		var col: Color = m["col"]
		if kind == "down" and Settings.fx_mult() > 0.0:
			col.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 6.0))
		if edge:
			col.a *= 0.6
		var r := 4.5 if kind == "obj" else 3.5
		var dia := PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)])
		if kind == "exit":
			_mark_layer.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), col, 1.2, true)
		else:
			_mark_layer.draw_colored_polygon(dia, col)
		var d := wp - player_pos
		var arrow := ""
		if absf(d.y) >= 3.0 * TILE:
			arrow = " ↑" if d.y < 0.0 else " ↓"
		var txt := "%s · %d m%s" % [String(m["label"]), int(d.length() / TILE), arrow]
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		var x0 := clampf(s.x - tw * 0.5, 0.0, size.x - tw)
		var ty := s.y + r + 7.0 if s.y < size.y - 12.0 else s.y - r - 3.0
		var clash := false
		for t in taken:
			if x0 < float(t[1]) + 4.0 and x0 + tw > float(t[0]) - 4.0 and absf(ty - float(t[2])) < 8.0:
				clash = true
		if not clash:
			taken.append([x0, x0 + tw, ty])
			_mark_layer.draw_string(f, Vector2(x0, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(UiTheme.TEXT if kind == "obj" else UiTheme.MUTED, col.a))
	# gracz: romb z ciemną obwódką (czytelny na jasnej krawędzi terenu)
	var pr := 4.0
	_mark_layer.draw_colored_polygon(PackedVector2Array([me + Vector2(0, -pr - 1), me + Vector2(pr + 1, 0), me + Vector2(0, pr + 1), me + Vector2(-pr - 1, 0)]), Color(0, 0, 0, 0.7))
	_mark_layer.draw_colored_polygon(PackedVector2Array([me + Vector2(0, -pr), me + Vector2(pr, 0), me + Vector2(0, pr), me + Vector2(-pr, 0)]), UiTheme.TEXT)
	# skala 10 m w prawym górnym rogu okna (dół zajmują podpisy znaczników przyklejonych do krawędzi)
	var k := size.x / win.size.x
	var sx := size.x - 10.0 * k - 8.0
	var sy := 9.0
	var sc := Color(UiTheme.TEXT, 0.45)
	_mark_layer.draw_line(Vector2(sx, sy), Vector2(sx + 10.0 * k, sy), sc, 1.0)
	_mark_layer.draw_line(Vector2(sx, sy - 2.5), Vector2(sx, sy), sc, 1.0)
	_mark_layer.draw_line(Vector2(sx + 10.0 * k, sy - 2.5), Vector2(sx + 10.0 * k, sy), sc, 1.0)
	var lt := "10 m"
	var lw := f.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 5).x
	_mark_layer.draw_string(f, Vector2(sx + 5.0 * k - lw * 0.5, sy + 7.0), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(UiTheme.MUTED, 0.8))
