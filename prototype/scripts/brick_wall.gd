extends Node2D
## Zamurowane przejście (marker „q" w mapie): cegły wypełniają wąskie przejście od podłogi do sufitu i zasłaniają skrytkę.
## Rozbija je tylko kilof (WeaponDef.breaks_walls) albo wybuch (WRATH-4): ~3 uderzenia kilofem. Kule i maczeta odbijają się.
## Ściana jest bryłą (ciało na warstwie świata), więc blokuje wszystkich i pociski; dla nawigacji liczy się jako kafel
## (level.gd `_wall_cells`), dzięki czemu boty i wrogowie nie planują drogi przez nią ani do skrytki za nią.
## Obrażenia liczy serwer; rozbicie idzie do wszystkich peerów przez level.gd (`break_wall`).
##
## Stopy w (0, 0) = dół ściany, środek kafla w poziomie; `rows` = wysokość w kaflach (level.gd liczy do sufitu).

const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")

const TILE := 16.0
const WALL_HP := 120.0
const N_HIT := 1.5               ## hałas jednego uderzenia
const N_BREAK := 6.0             ## hałas rozbicia — słychać w całej hali

var rows := 3
var hp := WALL_HP
var _flash := 0.0
var _seed := 0

func _ready() -> void:
	add_to_group("breakables")
	z_index = 1
	_seed = absi(String(name).hash())
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(TILE, TILE * float(rows))
	cs.shape = rs
	cs.position = Vector2(0, -TILE * float(rows) * 0.5)
	body.add_child(cs)
	add_child(body)

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

## Prostokąt ściany w współrzędnych świata (trafianie, wybuch, podpowiedź).
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-TILE * 0.5, -TILE * float(rows)), Vector2(TILE, TILE * float(rows)))

func body_center() -> Vector2:
	return hit_rect().get_center()

func is_threat() -> bool:
	return false

func hit_radius() -> float:
	return TILE * 0.8

## Serwer: kilof i wybuch niszczą, reszta tylko odbija się z brzękiem (hit = false — bez znacznika trafienia).
func take_hit(info: Dictionary) -> Dictionary:
	if not NoiseMgr.is_server() or hp <= 0.0:
		return {}
	var t: String = info.get("type", "")
	var breaker: bool = t == "melee" and Weapons.is_valid(int(info.get("w", -1))) and Weapons.def(int(info["w"])).breaks_walls
	if not breaker and t != "blast":
		return {"hit": false, "dealt": 0.0, "killed": false, "mat": 0}
	hp -= float(info["amount"])
	NoiseMgr.add_noise(N_HIT, global_position)
	var broken := hp <= 0.0
	var frac := clampf(hp / WALL_HP, 0.0, 1.0)
	if NoiseMgr.has_network():
		_hit_fx.rpc(frac)
	else:
		_hit_fx(frac)
	if broken:
		NoiseMgr.add_noise(N_BREAK, global_position)
		var lvl := get_tree().get_first_node_in_group("level")
		if lvl != null:
			lvl.break_wall(String(name))
	return {"hit": true, "dealt": float(info["amount"]), "killed": broken, "mat": 4}

@rpc("authority", "call_local", "unreliable")
func _hit_fx(frac: float) -> void:
	hp = WALL_HP * frac
	_flash = 0.12
	var lvl := get_tree().get_first_node_in_group("level")
	Vfx.dust(lvl if lvl != null else self, hit_rect().get_center(), 1.0)
	Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_WORLD, -4.0, 1.4)
	queue_redraw()

## Rozbicie (u wszystkich peerów, z level.gd): gruz i kurz, potem ściana znika.
func crumble() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var parent: Node = lvl if lvl != null else get_parent()
	var rc := hit_rect()
	for i in 10:
		var p := Vector2(rc.position.x + randf() * rc.size.x, rc.position.y + randf() * rc.size.y)
		Vfx.debris(parent, p, Vector2(randf_range(-60.0, 60.0), randf_range(-90.0, -20.0)), Vector2(3, 3), Color(0.5, 0.3, 0.24))
	Vfx.dust(parent, rc.get_center(), 2.5)
	Audio.play_variant_at("amb_thud", 2, global_position, Audio.BUS_WORLD, 0.0, 0.7)
	queue_free()

func _draw() -> void:
	var w := TILE
	var h := TILE * float(rows)
	var dmg := 1.0 - clampf(hp / WALL_HP, 0.0, 1.0)
	var brick := Color(0.42, 0.24, 0.2).lerp(Color(1, 1, 1), 0.5 if _flash > 0.0 else 0.0)
	var mortar := Color(0.16, 0.12, 0.11)
	draw_rect(Rect2(-w * 0.5, -h, w, h), mortar)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var y := 0.0
	var row := 0
	while y < h:
		var bh := 5.0
		var off := 0.0 if row % 2 == 0 else 4.0
		var x := -w * 0.5 - off
		while x < w * 0.5:
			var bw := 8.0
			var shade := rng.randf_range(-0.05, 0.05)
			var r := Rect2(maxf(x, -w * 0.5) + 0.5, -y - bh + 0.5, minf(x + bw, w * 0.5) - maxf(x, -w * 0.5) - 1.0, bh - 1.0)
			if r.size.x > 0.0:
				draw_rect(r, Color(brick.r + shade, brick.g + shade * 0.6, brick.b + shade * 0.5))
			x += bw
		y += bh
		row += 1
	# pęknięcia rosną z obrażeniami; nawet nietknięta ściana ma jedno — to podpowiedź „da się to rozbić"
	var cracks := 1 + int(dmg * 5.0)
	for i in cracks:
		var cx := rng.randf_range(-w * 0.35, w * 0.35)
		var cy := -rng.randf_range(4.0, h - 4.0)
		var seg := PackedVector2Array([Vector2(cx, cy), Vector2(cx + rng.randf_range(-3.0, 3.0), cy - 4.0), Vector2(cx + rng.randf_range(-3.0, 3.0), cy - 8.0)])
		draw_polyline(seg, Color(0.08, 0.06, 0.05), 1.0)
