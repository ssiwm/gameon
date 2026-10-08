extends StaticBody2D
## Tarcza strzelnicy w kryjówce (znacznik „t"): nieśmiertelny manekin. Przyjmuje trafienia jak wróg (grupa „enemies",
## Combat.apply → take_hit), ale nie ginie i nie hałasuje (kryjówka to NoiseMgr.safe_zone). Liczy serię: obrażenia,
## trafienia, DPS od pierwszego do ostatniego trafienia; seria się zeruje po SERIES_GAP s bez strzału. Dodatkowo
## pokazuje odległość od linii strzału („r", range_line.gd) i unoszące się liczby obrażeń (czerwone: głowa).
## Pociski i promienie lecą przez tarczę dalej (res.pass), więc strzał z linii trafia wszystkie w rzędzie, a każda pokazuje
## własne obrażenia — widać spadek obrażeń z dystansu. Granaty/wybuchowe pociski detonują na pierwszej.
## Autorytet: serwer liczy, wszyscy rysują (RPC _show).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Vfx := preload("res://scripts/vfx.gd")

const SERIES_GAP := 3.0
const H := 34.0                     ## wysokość sylwetki
const HEAD_FRAC := 0.28             ## górna część sylwetki liczona jako głowa (crit)

var distance_m := -1.0              ## odległość od najbliższego znacznika strzelnicy w metrach (-1: brak) — do testów
var live_m := -1.0                  ## odległość do najbliższego żywego gracza w metrach (na tabliczce); -1 = nikt w pobliżu
const LIVE_RANGE_M := 30.0
var _hd: Sprite2D
var _ov: Node2D                     ## HD: nakładka (tabliczka, liczby, podsumowanie) nad sprite'em

var _total := 0.0                   ## serwer: seria
var _hits := 0
var _t_first := 0.0
var _t_last := -999.0
var _flash := 0.0
var _nums: Array = []               ## [{text, age, x, crit}]
var _summary := ""
var _summary_t := 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("range_targets")
	collision_layer = 32
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(12, H)
	cs.shape = sh
	cs.position = Vector2(0, -H * 0.5)
	add_child(cs)
	z_index = 1
	if Sprites.newitem and ItemsHd.has("range_target"):
		_hd = ItemsHd.make("range_target", self)
		_ov = Node2D.new()
		_ov.draw.connect(func() -> void: _draw_over(_ov))
		add_child(_ov)
	call_deferred("_find_line")

func _find_line() -> void:
	if not is_inside_tree():
		return
	var best := INF
	for l in get_tree().get_nodes_in_group("range_line"):
		var d: float = global_position.x - l.global_position.x
		if d > 0.0 and d < best:
			best = d
	if best < INF:
		distance_m = roundf(best / 16.0)

func head_y() -> float:
	return global_position.y - H * (1.0 - HEAD_FRAC)

func body_center() -> Vector2:
	return global_position + Vector2(0, -H * 0.5)

func is_threat() -> bool:
	return false

# ---------------------------------------------------------------- trafienia (serwer)

func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server():
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	if now - _t_last > SERIES_GAP:
		_total = 0.0
		_hits = 0
		_t_first = now
	_t_last = now
	var dealt := float(info["amount"])
	var crit := bool(info.get("crit", false))
	_total += dealt
	_hits += 1
	var dps := _total / maxf(0.5, now - _t_first) if _hits > 1 else 0.0
	if NoiseMgr.has_network():
		_show.rpc(dealt, crit, _total, _hits, dps)
	else:
		_show(dealt, crit, _total, _hits, dps)
	return {"hit": true, "dealt": dealt, "killed": false, "mat": Arsenal.Mat.WOOD, "crit": crit, "pass": true}

@rpc("authority", "call_local", "unreliable")
func _show(dealt: float, crit: bool, total: float, hits: int, dps: float) -> void:
	_flash = 0.12
	_nums.append({"text": str(int(roundf(dealt))), "age": 0.0, "x": randf_range(-8.0, 8.0), "crit": crit})
	if _nums.size() > 10:
		_nums.pop_front()
	_summary = "%d dmg  ·  %d hits" % [int(roundf(total)), hits] + (("  ·  %d dps" % int(roundf(dps))) if hits > 1 else "")
	_summary_t = SERIES_GAP + 2.0

func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_summary_t = maxf(0.0, _summary_t - delta)
	_update_live()
	if _hd != null:
		_hd.modulate = Color(1, 1, 1).lerp(Color(1.8, 1.7, 1.5), clampf(_flash / 0.12, 0.0, 1.0))
	for n in _nums:
		n["age"] = float(n["age"]) + delta
	while not _nums.is_empty() and float(_nums[0]["age"]) > 1.1:
		_nums.pop_front()
	queue_redraw()
	if _ov != null:
		_ov.queue_redraw()

## Odległość do najbliższego żywego gracza (poziomo, w metrach) — tabliczka na tarczy pokazuje ją na żywo, więc widać, czy stoisz na znaczniku 5/10/20 m.
func _update_live() -> void:
	var best := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.is_queued_for_deletion():
			continue
		var d := absf(p.global_position.x - global_position.x) / 16.0
		if d < best and absf(p.global_position.y - global_position.y) < 40.0:
			best = d
	live_m = best if best <= LIVE_RANGE_M else -1.0

# ---------------------------------------------------------------- rysowanie

func _draw() -> void:
	if _hd != null:
		return
	var wood := Color(0.5, 0.36, 0.22)
	var dark := Color(0.14, 0.1, 0.07)
	var paper := Color(0.86, 0.84, 0.75)
	if _flash > 0.0:
		wood = wood.lerp(Color(1, 0.95, 0.8), 0.7)
		paper = paper.lerp(Color(1, 1, 1), 0.5)
	# stojak
	draw_rect(Rect2(-1, -10, 2, 10), dark)
	draw_rect(Rect2(-6, -2, 12, 2), dark)
	# sylwetka: deska z tarczą — głowa na górze (złota strefa = crit), tułów niżej
	draw_rect(Rect2(-7, -H + 10, 14, 24), dark)
	draw_rect(Rect2(-6, -H + 11, 12, 22), wood)
	draw_circle(Vector2(0, -H + 5), 6.0, dark)
	draw_circle(Vector2(0, -H + 5), 5.0, wood)
	draw_circle(Vector2(0, -H + 5), 2.4, paper)
	draw_circle(Vector2(0, -H + 5), 0.9, Color(0.8, 0.15, 0.12))
	draw_circle(Vector2(0, -H + 22), 5.0, paper)
	draw_circle(Vector2(0, -H + 22), 3.0, wood)
	draw_circle(Vector2(0, -H + 22), 1.2, Color(0.8, 0.15, 0.12))
	_draw_over(self)

## Tabliczka z odległością gracza, podsumowanie serii i unoszące się liczby obrażeń (rysowane nad sprite'em tarczy).
func _draw_over(ci: CanvasItem) -> void:
	if live_m >= 0.0:
		var f := ThemeDB.fallback_font
		if _hd != null:
			Vfx.draw_bar(ci, Rect2(-12, 3.5, 24, 8), 1.0, Color(0.05, 0.05, 0.06, 0.85), Color(0.05, 0.05, 0.06, 0.85))
		else:
			ci.draw_rect(Rect2(-12, 3, 24, 8), Color(0.05, 0.05, 0.06, 0.85))
		ci.draw_string(f, Vector2(-12, 10), "%d m" % int(roundf(live_m)), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 7, Color(0.95, 0.75, 0.3))
	# podsumowanie serii nad tarczą
	var fnt := ThemeDB.fallback_font
	if _summary_t > 0.0:
		var a := minf(1.0, _summary_t)
		var w := fnt.get_string_size(_summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		ci.draw_rect(Rect2(-w * 0.5 - 3, -H - 18, w + 6, 10), Color(0.04, 0.04, 0.05, 0.8 * a))
		ci.draw_string(fnt, Vector2(-w * 0.5, -H - 10.5), _summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, a))
	# liczby obrażeń
	for n in _nums:
		var age := float(n["age"])
		var col := Color(1.0, 0.35, 0.25) if bool(n["crit"]) else Color(1.0, 0.92, 0.7)
		col.a = clampf(1.4 - age, 0.0, 1.0)
		ci.draw_string(fnt, Vector2(float(n["x"]) - 6.0, -H - 4.0 - age * 16.0), String(n["text"]), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 8 if not bool(n["crit"]) else 10, col)
