extends Area2D
## Pocisk SERWEROWY (GDD §19 poz. 1).
## Spawn i rozstrzyganie trafień dzieje się wyłącznie na serwerze. Klienci
## dostają informację o strzale (kierunki i broń) i animują pocisk lokalnie
## po prostej — to wizualizacja, trafienia liczy tylko serwer.
##
## Wcześniej klient odbierał pozycję pocisku przez RPC po ścieżce węzła, ale
## pociski mają automatyczne nazwy różne na każdym peerze, więc RPC nie miał
## adresata. Lot po prostej jest deterministyczny, więc nie potrzeba synchronizacji.

const Weapons := preload("res://scripts/weapons.gd")
const Vfx := preload("res://scripts/vfx.gd")

var speed := 320.0
var damage := 8.0
var life_max := 1.2
var weapon := 0

var direction := Vector2.RIGHT:
	set(value):
		direction = value
		rotation = value.angle()

var shooter_id := 1
var _life := 0.0
var _server_side := true

func _ready() -> void:
	_server_side = NoiseMgr.is_server()
	# smuga widoczna w ciemności
	material = preload("res://scripts/lights.gd").unshaded()
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_life += delta
	if _life >= life_max:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Klient: tylko znika wizualnie przy ścianie/wrogu. Obrażenia liczy serwer.
	if not _server_side:
		if _is_wall(body):
			Vfx.sparks(get_parent(), global_position, direction)
		if _is_wall(body) or body.is_in_group("enemies"):
			queue_free()
		return

	if _is_wall(body):
		Vfx.sparks(get_parent(), global_position, direction)
		Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, -12.0)
		Audio.play_variant_at("ricochet", 2, global_position, Audio.BUS_WORLD, -20.0, 1.0, 0.12)
		queue_free()
		return

	if body.is_in_group("players"):
		# własny pocisk (np. celowanie w dół z lufą w sobie) — leci dalej
		if body.player_id == shooter_id or body.dead:
			return
		# Friendly fire (GDD §2 filar 3, wariant 1.3.4): na jednej płaszczyźnie
		# drużyna stoi w kolejce, więc FF za HP karało za samo ustawienie —
		# seria M-83 w plecy kładła kolegę. Teraz pocisk PRZELATUJE przez
		# kolegę, a kosztem jest hałas (krzyk) i odrzut — konsekwencja w
		# głównym systemie gry, Uwadze. Bez wyjątków dla żadnej broni (1.5.2:
		# usunięty wyjątek strzelby z bliska — nadal raniła kolegów).
		(body as Node).deliver_ff(global_position)
		return

	if body.is_in_group("enemies"):
		Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, -14.0)
		# cele wrażliwe na kierunek (pancerny grzbiet Żyły) dostają też wektor lotu
		if body.has_method("take_bullet_dir"):
			body.take_bullet_dir(global_position, damage, direction)
		else:
			body.take_bullet(global_position, damage)
		queue_free()

## Ściana = kafle mapy (TileMapLayer) albo dawne StaticBody2D. Kładki
## jednokierunkowe są na innej warstwie (16) — maska pocisku ich nie widzi.
func _is_wall(body: Node) -> bool:
	return body is TileMapLayer or body is StaticBody2D

func _draw() -> void:
	draw_rect(Rect2(-3, -1, 6, 2), Color(1.0, 0.85, 0.35))
