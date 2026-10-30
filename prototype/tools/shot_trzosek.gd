extends SceneTree
## Zrzut kontrolny Trzoska (czworonog) w dowolnej pozie — lekki renderer pojedynczego modelu,
## do kalibracji animacji bez uruchamiania pelnej gry. Wymaga GPU (bez --headless).
##   godot --path prototype --script res://tools/shot_trzosek.gd -- [--anim=idle|run|sleep|windup] [--flip] [--out=PLIK.png] [--wait=12]
##       [--speed=PX_S] (prędkość biegu: chód / galop) [--vy=PX_S] (lot: − wznosi się, + opada) [--die] (śmierć od 1. klatki)
##       [--hit=N] / [--attack=N] (trafienie / cios N klatek przed zrzutem; cios po pełnej zapowiedzi)
const Enemy3D := preload("res://scripts/enemy3d.gd")
var _frames := 0
var _wait := 12
var _out := "C:/deadair87/gameon/concepts/trzosek_shot.png"
var _anim := "idle"
var _flip := false
var _e: Node3D
var _dt := 1.0 / 60.0
var _speed := NAN
var _vy := 0.0
var _die := false
var _hit := -1
var _attack := -1

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--wait="): _wait = int(a.substr(7))
		elif a.begins_with("--anim="): _anim = a.substr(7)
		elif a == "--flip": _flip = true
		elif a.begins_with("--speed="): _speed = float(a.substr(8))
		elif a.begins_with("--vy="): _vy = float(a.substr(5))
		elif a == "--die": _die = true
		elif a.begins_with("--hit="): _hit = int(a.substr(6))
		elif a.begins_with("--attack="): _attack = int(a.substr(9))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640, 640)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.15, 0.14)
	bg.size = Vector2(640, 640)
	root.add_child(bg)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.6)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-48, -28, 0)
	dl.light_energy = 1.3
	dl.shadow_enabled = true
	root.add_child(dl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL      # widok z boku jak kamera gry; kadr 2,6 m obejmuje całego Trzoska (ok. 1,7 m długości)
	cam.size = 2.6
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.75, 5.0), Vector3(0.0, 0.75, 0.0), Vector3.UP)
	cam.current = true
	_e = (Enemy3D as Script).new()
	root.add_child(_e)
	if not _e.setup("trzosek"):
		push_error("setup(trzosek) FAILED")
		quit()
		return

func _process(_d: float) -> bool:
	_frames += 1
	if _e != null and is_instance_valid(_e):
		if _die and _frames == 1: _e.die()
		if _hit >= 0 and _frames == _wait - _hit: _e.trigger("hit")
		if _attack >= 0 and _frames == _wait - _attack: _e.trigger("attack")
		var anim := _anim
		if _attack >= 0 and _frames < _wait - _attack: anim = "windup"          # zapowiedź do chwili ciosu
		_e.pose(_dt, anim, _flip, Color.WHITE, 0.0, 1, true, _vy, 0, false, _speed)
	if _frames == _wait:
		var img := root.get_texture().get_image()
		var err := img.save_png(_out)
		if "--bones" in OS.get_cmdline_user_args():          # dev: pozycje kości w przestrzeni szkieletu (do strojenia póz)
			var sk: Skeleton3D = _e.get("_sk")
			for bi in sk.get_bone_count():
				var o := sk.get_bone_global_pose(bi).origin
				print("BONE %2d %-28s parent=%2d  (%.3f, %.3f, %.3f)" % [bi, sk.get_bone_name(bi), sk.get_bone_parent(bi), o.x, o.y, o.z])
			print("SPINE ", _e.get("_spine"), " SCALE ", _e.get("_scale"))
		print("SAVED ", _out, " err=", err, " anim=", _anim, " flip=", _flip)
		quit()
	return false
