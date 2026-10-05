extends Area2D
## Pocisk SERWEROWY (GDD §19 poz. 1).
## Spawn i rozstrzyganie trafień dzieje się wyłącznie na serwerze. Klienci
## dostają informację o strzale (kierunki i broń) i animują pocisk lokalnie
## po prostej — to wizualizacja, trafienia liczy tylko serwer.
##
## Wcześniej klient odbierał pozycję pocisku przez RPC po ścieżce węzła, ale
## pociski mają automatyczne nazwy różne na każdym peerze, więc RPC nie miał
## adresata. Lot po prostej jest deterministyczny, więc nie potrzeba synchronizacji.

var speed := 320.0
var damage := 8.0
var life_max := 1.2

var direction := Vector2.RIGHT:
	set(value):
		direction = value
		rotation = value.angle()

var shooter_id := 1
var _life := 0.0
var _server_side := true

func _ready() -> void:
	_server_side = NoiseMgr.is_server()
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
		if body is StaticBody2D or body.is_in_group("enemies"):
			queue_free()
		return

	if body is StaticBody2D:
		Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, -12.0)
		Audio.play_variant_at("ricochet", 2, global_position, Audio.BUS_WORLD, -20.0, 1.0, 0.12)
		queue_free()
		return

	if body.is_in_group("players"):
		if body.player_id != shooter_id:
			# Głośniej przy bliższym trafieniu — zwykle odległość = kilka pikseli,
			# więc różnica głośności niesie informację o dystansie.
			var d := global_position.distance_to((body as Node2D).global_position)
			Audio.play_variant_at("impact_flesh", 3, global_position, Audio.BUS_WORLD,
				lerpf(-8.0, -18.0, clampf(d / 240.0, 0.0, 1.0)))
			# Friendly fire: 1 obrażenie, dostarczone właścicielowi postaci
			# (deliver_hit rozstrzyga lokalnie albo przez RPC do autorytetu).
			(body as Node).deliver_hit(1, global_position)
		queue_free()
		return

	if body.is_in_group("enemies"):
		Audio.play_variant_at("impact_hard", 3, global_position, Audio.BUS_WORLD, -14.0)
		body.take_bullet(global_position, damage)
		queue_free()

func _draw() -> void:
	draw_rect(Rect2(-3, -1, 6, 2), Color(1.0, 0.85, 0.35))
