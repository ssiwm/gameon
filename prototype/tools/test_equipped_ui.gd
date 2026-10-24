extends SceneTree
## Regresja HUD-u względem wyposażenia rzeczywistej postaci oraz brakującej ikony zestawu.
## godot --headless --path prototype -s tools/test_equipped_ui.gd
const Preview := preload("res://scripts/gun_preview.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
var total := 0
var failed := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		print("FAIL equipped UI: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.port = 8957
	root.add_child(main)
	current_scene = main
	main.host_game()
	await process_frame
	await process_frame
	var player: Node = main.get_node("UI/HUD")._find_local_player()
	check("lokalna postać", player != null)
	if player == null:
		quit(1)
		return
	var hud: Node = main.get_node("UI/HUD")
	hud._player = player
	var wc: Node = player.weapons
	wc.slot = 0
	wc.loadout[0] = 0
	var fitted := Parts.encode_ids("m83", ["m83_drum75", "m83_rpkbar", "m83_pbs1"])
	var short_fit := Parts.encode_ids("m83", ["m83_short", "m83_akms"])
	# Profile i odblokowania nie są źródłem obrazu: postać publikuje konkretny kod montażu.
	for fit in [0, fitted, short_fit, fitted, 0]:
		player.fits[0] = fit
		hud._drive_weapons()
		var sig := Preview.signature("m83", fit, wc.notches_of(0))
		check("główna broń ma bieżący fit %d" % fit, hud._gun_main._signature == sig)
		check("slot ma ten sam fit %d" % fit, hud._slot_icons[0]._signature == sig)
	wc.slot = 1
	hud._drive_weapons()
	check("przełączenie broni", hud._gun_main.key == String(wc.cur().key))
	wc.slot = 0
	player.fits[0] = fitted
	var gun := Preview.compose("m83", fitted, 0)
	root.add_child(gun)
	check("bęben zastępuje fabryczny magazynek", gun.find_children("*__mag", "Node3D", true, false).is_empty())
	check("długa lufa zastępuje fabryczny przód", gun.find_children("*__front", "Node3D", true, false).is_empty())
	check("fabryczna kolba pozostaje", not gun.find_children("*__stock", "Node3D", true, false).is_empty())
	for id in ["m83_drum75", "m83_rpkbar", "m83_pbs1"]:
		var found := false
		for node in gun.get_children():
			found = found or node.scene_file_path == "res://art/char3d/gunpart_%s.glb" % id
		check("dodatek zmontowany " + id, found)
	var bb := Preview.bounds(gun)
	check("model ma rzeczywiste wymiary", bb.size.x > 1.0 and bb.size.y > 0.15)
	gun.free()
	var texture := load("res://art/hud/cleankit.png") as Texture2D
	var img := texture.get_image() if texture != null else null
	check("ikona zestawu istnieje", img != null and not img.is_empty())
	if img != null and not img.is_empty():
		check("ikona ma przezroczyste tło", img.detect_alpha() != Image.ALPHA_NONE)
		check("ikona nie jest pustym polem", img.get_used_rect().get_area() > 20000)
	check("model zestawu dostępny", ResourceLoader.exists("res://art/items3d/cleankit.glb"))
	var arsenal := root.get_node("Arsenal")
	arsenal.throw_sel = Throwables.ORDER.find("cleankit")
	for amount in [2, 1, 0]:
		arsenal.stock["cleankit"] = amount
		hud._drive_noise()
		check("zestaw widoczny przy zapasie %d" % amount, hud._a_icon.key == "cleankit" and hud._a_icon._tex != null)
		check("licznik zapasu %d" % amount, hud._gren_name.text == str(amount))
		check("przygaszenie po zużyciu %d" % amount, is_equal_approx(hud._a_icon.tint.a, 0.28 if amount == 0 else 1.0))
	print("%s equipped UI: %d checks, %d errors" % ["PASS" if failed == 0 else "FAIL", total, failed])
	quit(0 if failed == 0 else 1)
