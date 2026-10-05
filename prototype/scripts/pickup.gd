extends Node2D
## Przedmiot na ziemi: apteczka (+1 HP), skrzynka z amunicją albo broń.
## Spawn, podniesienie i usunięcie idą przez level.gd (RPC ze stałą nazwą),
## więc istnieje identycznie na każdym peerze. Podniesienie rozstrzyga serwer.
##
##   health  dotknięcie leczy rannego (bot ustępuje człowiekowi)
##   ammo    dotknięcie dodaje `rounds` naboi do WSPÓLNEGO zapasu drużyny — o ile
##           ktoś z ludzi nosi tę broń i zapas nie jest pełny (nic się nie marnuje)
##   cache   skrzynia z mapy: dodaje amunicję do WSZYSTKICH broni głównych noszonych przez drużynę
##   weapon  nie podnosi się samo: gracz naciska E (wymiana broni to decyzja, a nie
##           wypadek); serwer sprawdza odległość i przyznaje (level.gd)

const Sprites := preload("res://scripts/sprites.gd")
const Lights := preload("res://scripts/lights.gd")
const Weapons := preload("res://scripts/weapons.gd")

const HEAL := 1
const PICK_R := 12.0
const WEAPON_R := 26.0            ## zasięg „E” po broń
const FALL_G := 700.0

const GLOW := {
	"health": Color(0.4, 1.0, 0.5),
	"ammo": Color(1.0, 0.78, 0.3),
	"weapon": Color(0.5, 0.85, 1.0),
	"cache": Color(1.0, 0.78, 0.3),
}

var kind := "health"
var arg := 0                      ## ammo/weapon: id broni
var rounds := 0                   ## ammo: ile naboi

var _vel := Vector2.ZERO
var _floor_y := 0.0
var _landed := false
var _t := 0.0
var _spr: Array = []
var _glow: PointLight2D

func _ready() -> void:
	add_to_group("pickups")
	z_index = 2
	# bez filtrowania liniowego: sprite broni 24×9 px rozmywał się przy skalowaniu okna
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind == "health" and Sprites.has("objects"):
		_spr = Sprites.attach(self, "objects")
		Sprites.play(_spr, "medkit", false)
	if kind != "health":
		material = Lights.unshaded()          # skrzynkę i broń widać w ciemności
		modulate = Color(0.88, 0.88, 0.88)
	# poświata — przedmiot widać w ciemności, ale nie oświetla okolicy
	_glow = Lights.make_light(Lights.radial(), 1.6, GLOW.get(kind, Color.WHITE), 0.6, false)
	_glow.position = Vector2(0, -8)
	add_child(_glow)
	_vel = Vector2(randf_range(-40.0, 40.0), -170.0)
	_floor_y = _find_floor(global_position)
	queue_redraw()

func _find_floor(from: Vector2) -> float:
	var q := PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), from + Vector2(0, 200), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else from.y

func _physics_process(delta: float) -> void:
	_t += delta
	if not _landed:
		# podskok i opad na podłogę (bez ciała fizycznego — to tylko znacznik)
		_vel.y += FALL_G * delta
		global_position += _vel * delta
		if _vel.y > 0.0 and global_position.y >= _floor_y:
			global_position = Vector2(roundf(global_position.x), _floor_y)   # lądowanie na pełnym pikselu
			_landed = true
	var bob := 0.0 if not _landed else sin(_t * 3.0) * 1.5 - 1.5
	if not _spr.is_empty():
		(_spr[0] as Node2D).position.y = bob
		if _spr[1] != null:
			(_spr[1] as Node2D).position.y = bob
			(_spr[1] as CanvasItem).modulate.a = 0.6 + 0.4 * sin(_t * 4.0)
	elif kind != "health":
		queue_redraw()
	if _glow != null:
		_glow.energy = 0.5 + 0.2 * sin(_t * 4.0)
	if _landed and NoiseMgr.is_server():
		_try_pickup()

# ---------------------------------------------------------------- rysowanie (ammo / broń)

func _draw() -> void:
	if kind == "health":
		return
	var bob := 0.0 if not _landed else sin(_t * 3.0) * 1.5 - 1.5
	var c: Color = GLOW.get(kind, Color.WHITE)
	if kind == "cache":
		# skrzynia z zapasem: większa, z pasami i mosiężnymi okuciami
		draw_rect(Rect2(-8, -11 + bob, 16, 10), Color(0.26, 0.28, 0.19))
		draw_rect(Rect2(-8, -11 + bob, 16, 2), Color(0.4, 0.43, 0.3))
		draw_rect(Rect2(-8, -6 + bob, 16, 1), Color(0.85, 0.68, 0.3))
		draw_rect(Rect2(-1, -11 + bob, 2, 10), Color(0.85, 0.68, 0.3, 0.7))
		draw_rect(Rect2(-8, -2 + bob, 16, 1), Color(0.12, 0.13, 0.09))
	elif kind == "ammo":
		# skrzynka z amunicją: oliwkowe pudło z mosiężnym paskiem w kolorze rodzaju broni
		draw_rect(Rect2(-5, -8 + bob, 10, 7), Color(0.28, 0.3, 0.2))
		draw_rect(Rect2(-5, -8 + bob, 10, 1), Color(0.4, 0.42, 0.3))
		draw_rect(Rect2(-4, -5 + bob, 8, 2), Weapons.def(arg).tracer_color.lerp(Color(0.85, 0.68, 0.3), 0.4))
		draw_rect(Rect2(-5, -2 + bob, 10, 1), Color(0.14, 0.15, 0.1))
	else:
		# broń: sylwetka z arkusza guns.png nad ciemną skrzynką-podstawką
		# pozycje na CAŁYCH pikselach — ułamki rozmywają pixel-art
		var ibob := roundf(bob)
		draw_rect(Rect2(-8, -4 + ibob, 16, 3), Color(0.12, 0.13, 0.16))
		draw_rect(Rect2(-8, -4 + ibob, 16, 1), c.darkened(0.4))
		var tex := Sprites.texture(Sprites.DIR + "guns.png")
		if tex != null and Sprites.has("guns"):
			var fs := Sprites.frame_size("guns")
			var row := int(Weapons.def(arg).gun_row)
			var dst := Rect2(roundf(-fs.x * 0.5), -4.0 - fs.y + ibob, fs.x, fs.y)
			var src := Rect2(0, row * fs.y, fs.x, fs.y)
			# ciemny kontur 1 px — sylwetka czytelna na jasnym i ciemnym tle
			for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_texture_rect_region(tex, Rect2(dst.position + o, dst.size), src, Color(0, 0, 0, 0.85))
			draw_texture_rect_region(tex, dst, src)
			var glow_tex := Sprites.texture(Sprites.DIR + "guns_glow.png")
			if glow_tex != null:
				draw_texture_rect_region(glow_tex, dst, src)
		else:
			draw_rect(Rect2(-6, -7 + bob, 12, 3), c)

# ---------------------------------------------------------------- podnoszenie (serwer)

func _try_pickup() -> void:
	match kind:
		"health":
			_try_health()
		"ammo":
			_try_ammo()
		"cache":
			_try_cache()

func _near(p: Node2D) -> bool:
	return (p.global_position + Vector2(0, -8)).distance_to(global_position + Vector2(0, -6)) <= PICK_R + 6.0

func _level() -> Node:
	return get_tree().get_first_node_in_group("level")

## Pierwszy ranny w zasięgu. Bot nie zabiera apteczki, gdy obok jest
## ranny człowiek — ludzie mają pierwszeństwo.
func _try_health() -> void:
	var hurt_human_near := false
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and not p.dead and p.hp < p.MAX_HP and p.global_position.distance_to(global_position) < 80.0:
			hurt_human_near = true
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.hp >= p.MAX_HP:
			continue
		if p.is_bot and hurt_human_near:
			continue
		if _near(p):
			p.deliver_heal(HEAL)
			_level().take_item(name)
			return

## Amunicja: bierze ją każdy człowiek w zasięgu, ale tylko jeśli ktoś z ludzi nosi
## tę broń (P-64 ma nieskończoną amunicję — jej skrzynek nie ma) i zapas nie jest pełny.
func _try_ammo() -> void:
	if Arsenal.is_full(arg):
		return
	var carried := false
	var near_human := false
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		if p.carries(arg):
			carried = true
		if _near(p):
			near_human = true
	if carried and near_human:
		var got := Arsenal.add_reserve(arg, rounds)
		if got > 0:
			_level().take_item(name)

## Skrzynia z mapy: uzupełnia zapas każdej broni głównej, którą drużyna nosi; zostaje,
## dopóki cokolwiek się mieści (nic się nie marnuje).
func _try_cache() -> void:
	var near := false
	var carried := {}
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or p.dead:
			continue
		if _near(p):
			near = true
		for w in p.kit_primaries():
			carried[w] = true
	if not near:
		return
	var added := 0
	for w in carried:
		added += Arsenal.add_reserve(w, maxi(1, int(Weapons.def(w).pickup_rounds * 0.6)))
	if added > 0:
		_level().take_item(name)

## Broń leży na ziemi i czeka na E — czy ten gracz stoi dość blisko?
func in_reach(p: Node2D) -> bool:
	return (p.global_position + Vector2(0, -8)).distance_to(global_position + Vector2(0, -6)) <= WEAPON_R
