extends SceneTree
## ENet z migawką zapowiedzi i jawnym kontaktem; relay UDP wprowadza opóźnienie i straty.
const Enemy3D := preload("res://scripts/enemy3d.gd")
var actor: Node
var stalker: Node
var model: Node3D
var stalker_model: Node3D
var elapsed := 0.0
var started := -1.0
var sent := false
var server := false
var saw_wind := false
var saw_contact := false
var previous_seq := 0
var previous_grab := 0
var saw_grab := false
var priest: Node
var priest_model: Node3D
var priest_sent := false
var saw_summon := false
var priest_seq := 0
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
		finish(false, "ENet setup=" + str(result))
		return
	root.multiplayer.multiplayer_peer = peer
	actor = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	actor.name = "MotionActor"
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	stalker = (load("res://scenes/stalker.tscn") as PackedScene).instantiate()
	stalker.name = "MotionStalker"
	root.add_child(stalker)
	stalker.set_physics_process(false)
	stalker.set_process(false)
	priest = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	priest.name = "MotionPriest"
	priest.kind = "kaplan"
	root.add_child(priest)
	priest.set_physics_process(false)
	priest.set_process(false)
	if not server:
		model = Enemy3D.new()
		root.add_child(model)
		model.setup("wolek")
		stalker_model = Enemy3D.new()
		root.add_child(stalker_model)
		stalker_model.setup("stalker")
		priest_model = Enemy3D.new()
		root.add_child(priest_model)
		priest_model.setup("kaplan")

func finish(ok: bool, label: String) -> void:
	print(("PASS" if ok else "FAIL") + " enemy motion network: " + label)
	peer.close()
	for node in [model, stalker_model, priest_model, actor, stalker, priest]:
		if is_instance_valid(node): node.free()
	quit(0 if ok else 1)

func _process(dt: float) -> bool:
	if actor == null: return false
	elapsed += dt
	if elapsed > 15.0:
		finish(false, "timeout")
		return false
	if server:
		if started < 0.0 and elapsed > 1.0 and root.multiplayer.get_peers().size() == 1:
			started = elapsed
		if started < 0.0: return false
		var age := elapsed - started
		actor._sync.rpc(Vector2.ZERO, 10.0, true, true, age < 0.9, 3 if age < 0.9 else 0, -1, 1.0, maxf(0.9 - age, 0.0), 0.9, false)
		stalker._sync.rpc(Vector2.ZERO, true, age < 0.9, maxf(0.9 - age, 0.0), 0.9, -14.3)
		if not sent and age >= 0.9:
			sent = true
			actor.visual_attack("throw")
			stalker._visual_attack.rpc(1, -14.3, -1.0)
		if sent and age > 2.0 and int(actor.view_info()["attack_seq"]) == 1:
			actor.visual_attack("charge")
			actor.visual_attack("throw")
			stalker._visual_attack.rpc(3, -14.3, -1.0)
		if not priest_sent and age >= 1.5:
			priest_sent = true
			priest.visual_attack("summon")
			priest._priest_spawn.rpc("PriestSpawn_MotionPriest_1", Vector2(40.0, 0.0))
		if age > 5.0: finish(true, "server: windup + 3 resolved attacks + summon")
	else:
		var info: Dictionary = actor.view_info()
		var grab: Dictionary = stalker.view_info()
		stalker_model.motion_context(grab)
		if int(grab["attack_seq"]) > previous_grab:
			previous_grab = int(grab["attack_seq"])
			stalker_model.trigger("attack")
			stalker_model.pose(dt, "idle", false, Color.WHITE)
			if stalker_model.motion_phase() != "contact" or not is_equal_approx(float(grab["target_y"]), -14.3) or stalker._facing != -1.0:
				finish(false, "Stalker target/contact mismatch")
				return false
			saw_grab = true
		else:
			stalker_model.pose(dt, "windup" if grab["winding"] else "idle", false, Color.WHITE)
		var pi: Dictionary = priest.view_info()
		if int(pi["attack_seq"]) > priest_seq:
			priest_seq = int(pi["attack_seq"])
			priest_model.trigger("attack", String(pi["attack_action"]))
			priest_model.pose(dt, "idle", false, Color.WHITE)
			saw_summon = priest_model.motion_phase() == "contact" and priest_model.get("_motion_name") == "summon"
		model.motion_context(info)
		var sequence := int(info["attack_seq"])
		if sequence > previous_seq:
			model.trigger("attack", String(info["attack_action"]))
			previous_seq = sequence
			model.pose(dt, "idle", false, Color.WHITE)
			if model.motion_phase() != "contact" or model.get("_motion_name") != info["attack_action"]:
				finish(false, "contact or action mismatch")
				return false
			saw_contact = true
		else:
			model.pose(dt, "windup" if info["winding"] else "idle", false, Color.WHITE)
		if info["winding"] and sequence == 0:
			if model.motion_phase() != "anticipation" or info["windup_duration"] <= 0.0 or info["grounded"]:
				finish(false, "windup/grounded snapshot mismatch")
				return false
			saw_wind = true
		if sequence == 3 and previous_grab == 3:
			stalker._visual_attack(1, -100.0, 1.0)
			stalker._sync(Vector2.ZERO, true, false, 0.0, 0.0, -100.0)
			finish(saw_summon and root.has_node("PriestSpawn_MotionPriest_1") and saw_wind and saw_contact and saw_grab and stalker._facing == -1.0 and is_equal_approx(float(stalker.view_info()["target_y"]), -14.3), "client: snapshot, contact, action, 3 attacks, Stalker target/facing")
	return false
