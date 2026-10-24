extends SceneTree
## Rzeczywiste ENet: rozstrzygnięcie ataku dociera do obserwatora bez przejścia winding.
var actor: Node
var elapsed := 0.0
var sent := false
var server := false
var peer := ENetMultiplayerPeer.new()

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	server = "--motion-server" in OS.get_cmdline_user_args()
	var port := 18974
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--motion-port="): port = arg.substr(14).to_int()
	var result := peer.create_server(port, 1) if server else peer.create_client("127.0.0.1", port)
	if result != OK:
		push_error("ENet setup failed: " + str(result))
		quit(1)
		return
	root.multiplayer.multiplayer_peer = peer
	actor = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	actor.name = "MotionActor"
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)

func _process(dt: float) -> bool:
	if actor == null: return false
	elapsed += dt
	if elapsed > 12.0:
		print("FAIL enemy motion network: timeout")
		peer.close()
		quit(1)
	if server:
		if not sent and elapsed > 1.5 and root.multiplayer.get_peers().size() == 1:
			sent = true
			actor.visual_attack()
			actor.visual_attack()
			actor.visual_attack()
		if sent and elapsed > 4.0:
			print("PASS enemy motion network server: 3 attacks")
			peer.close()
			quit()
	elif int(actor.view_info()["attack_seq"]) == 3:
		print("PASS enemy motion network client: 3 attacks without winding")
		peer.close()
		quit()
	return false
