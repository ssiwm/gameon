extends Node
## Zrzuty stanu stanowisk w świecie (WORKSHOP_IMMERSION_PLAN.md R4, station_state3d.gd): przy każdym stanowisku (prasa, tokarka, pracownia,
## ława, szafki) zrzut bez stanu i ze stanem — kadr kryjówki z graczem obok i ujęcie stołu po [E] (karta otwarta, R1).
## Stan tylko w pamięci: zapis `Scrap` i `Profile` wyłączony na starcie (okno inaczej nadpisałoby prawdziwą postać).
##
##   godot --path prototype --resolution 1600x900 -- --host --nobot --mission=z1_hub --stateshots=C:/tmp/r4 [--camidx=2]
##
## Pliki: `r4_<tryb>_<empty|state>_hub.png` i `r4_<tryb>_<empty|state>_card.png`. Linie `[R4SHOT]`.

const GROUPS := {"press": "press_bench", "lathe": "lathe_bench", "lab": "lab_bench", "bench": "workshop", "locker": "locker_station"}
const Interact := preload("res://scripts/interact.gd")
const StationState3D := preload("res://scripts/station_state3d.gd")

var dir := ""

func _ready() -> void:
	Scrap.persist = false
	Profile.persist = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stateshots="):
			dir = a.substr("--stateshots=".length())
	DirAccess.make_dir_recursive_absolute(dir)
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, false).timeout

## Zrzut i położenie stanowiska na nim (stopy znacznika w pikselach obrazu) — do kadrowania porównań.
func _shot(name: String, v3d: Node = null, st: Node2D = null) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("r4_%s.png" % name))
	var sp := Vector2(-1, -1)
	var cam: Camera3D = v3d.get("_cam_a") if v3d != null else null
	if cam != null and st != null and cam.is_inside_tree():
		var foot := Vector3(st.global_position.x * StationState3D.PX, -st.global_position.y * StationState3D.PX, -1.0)
		sp = cam.unproject_position(foot) / Vector2(cam.get_viewport().get_visible_rect().size) * Vector2(img.get_size())
	print("[R4SHOT] %s %.0f %.0f" % [name, sp.x, sp.y])

## Stan „pusty” albo „pełny” wszystkich stanowisk naraz (tylko pamięć).
func _set_state(full: bool) -> void:
	Profile.is_new("perk:quiet_steps")                       # pierwsze zapytanie ustala listę obejrzanych — przed dodaniem nowej części
	if full:
		Scrap.orders = ["ammo_hot762", "ammo_slug"]
		Scrap.deliveries = {"ammo_mag12": 6}
		Scrap.lathe = ["lr7_lens"]
		Scrap.samples = 4
		Scrap.geodes = 1
		Scrap.parts["m83_rpk40"] = true
		Profile.seen.erase("part:m83_rpk40")
		Profile.xp = Profile.xp_for_level(4)
		Profile.equipped = ["", ""]
	else:
		Scrap.orders = []
		Scrap.deliveries = {}
		Scrap.lathe = []
		Scrap.samples = 0
		Scrap.geodes = 0
		for pid in Scrap.parts:
			Profile.seen["part:" + String(pid)] = true
		for id in ["quiet_steps", "blood_flow", "wide_arm", "smith", "cold_blood", "scout", "second_chance", "veteran"]:
			Profile.seen["perk:" + id] = true
		Profile.equipped = ["quiet_steps", "blood_flow"]
	Scrap.changed.emit()

func _run() -> void:
	var v3d: Node = null
	var p: Node2D = null
	for i in 40:
		await _wait(0.5)
		v3d = get_tree().current_scene.get_node_or_null("View3D") if get_tree().current_scene else null
		p = Interact.local_player(get_tree())
		var curtain: CanvasLayer = v3d.get("_curtain") if v3d != null else null
		if v3d != null and p != null and get_tree().get_first_node_in_group("workshop") != null and (curtain == null or not curtain.visible):
			break
	if v3d == null or p == null:
		push_error("[R4SHOT] brak widoku 3D albo gracza")
		get_tree().quit(1)
		return
	var ui := get_tree().get_first_node_in_group("workshop_ui")
	for m in GROUPS:
		var st := get_tree().get_first_node_in_group(String(GROUPS[m])) as Node2D
		if st == null:
			print("[R4SHOT] brak stanowiska ", m)
			continue
		for full in [false, true]:
			_set_state(full)
			p.global_position = st.global_position + Vector2(-34.0, -2.0)
			p.velocity = Vector2.ZERO
			await _wait(1.6)
			var tag := "%s_%s" % [m, "state" if full else "empty"]
			await _shot(tag + "_hub", v3d, st)
			p.global_position = st.global_position + Vector2(0.0, -2.0)
			await _wait(0.3)
			ui.open(String(m))
			await _wait(1.2)
			await _shot(tag + "_card")
			ui.close()
			await _wait(0.6)
	print("[R4SHOT] PASS")
	get_tree().quit()
