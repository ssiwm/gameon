extends "res://scripts/stalker_test.gd"
## Cień przeszkód w poświacie snopu latarki we mgle wolumetrycznej (view3d.gd `_sync_camera`, symetryczna bryła kamery świata).
##
##   godot --path . -- --host --nobot --mission=z1_m1 --shotweather=fog --fogshadowtest --fogshots=KATALOG --autoquit=90
##   (tylko w oknie; najpierw override.cfg z osobnym katalogiem zapisu)
##
## Przeszkoda (deska 6 cm, potem ściana 1 m; wysokość 2,2 m, cała głębokość korytarza) stoi 2,5 m przed graczem, latarka świeci w nią poziomo.
## Jasność powietrza i gruntu za przeszkodą w obu trybach kamery: dawny „shift” (`fog_sym = 0`) i bryła symetryczna (`fog_sym = 2`). Kontrole: kadr gry
## w tym samym miejscu ekranu w obu trybach, cień reflektora wyłączony, tryb domyślny (bryła symetryczna tylko w gęstej mgle). Na koniec czas
## GPU obu trybów. Wynik: linie [FOG-SHADOW].

const Level3D := preload("res://scripts/level3d.gd")
const View3D := preload("res://scripts/view3d.gd")

const WALL_H := 2.2                     ## m: wysokość przeszkody od podłogi
const DIST := 2.5                       ## m: od gracza do przeszkody

var v3d: Node
var wall: MeshInstance3D

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
	print("[FOG-SHADOW] %s  %s" % ["PASS" if ok else "FAIL", label])

func info(label: String) -> void:
	print("[FOG-SHADOW] INFO  %s" % label)

func _finish() -> void:
	print("[FOG-SHADOW] ==== %s (%d/%d) ====" % ["PASS" if failed == 0 else "FAIL", total - failed, total])
	Audio.quit_game(1 if failed > 0 else 0)

func run(m: Node2D) -> void:
	main = m
	level = m.level
	await get_tree().create_timer(2.0).timeout
	player = m.get_node("Players").get_node_or_null("1")
	v3d = m.get_node_or_null("View3D")
	if DisplayServer.get_name() == "headless" or v3d == null or player == null:
		info("test tylko w oknie (widok 3D)")
		_finish()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	Director.set_process(false)
	_place_player(Vector2(7.5 * 16.0, 23.0 * 16.0 - 2.0))
	await _frames(0.6)
	player.flashlight = true
	player.aim_dir = Vector2.RIGHT
	player._update_lights()
	player.set_physics_process(false)
	player.set_process(false)
	_build_wall()
	await _frames(1.0)                                # `_lights` widoku 3D skanuje się co 0,5 s
	var env: Environment = (v3d.get("_cam_a") as Camera3D).environment
	var dens := float(v3d.get("_fog_dens"))
	info("mgła wolumetryczna %s, długość %.1f m, gęstość bryły ×%.2f" % [env.volumetric_fog_enabled, env.volumetric_fog_length, dens])
	var dense := dens >= View3D.FOG_SYM_DENS
	check("tryb domyślny: bryła symetryczna %s (gęstość ×%.2f)" % ["jest" if dense else "nie ma", dens], (int(v3d.get("_fog_rows")) > 0) == dense)
	var res := {}
	for sym in [false, true]:
		v3d.set("fog_sym", 2 if sym else 0)
		var tag := "sym" if sym else "shift"
		wall.visible = false
		await _frames(0.6)                            # reprojekcja mgły w czasie wygasa po kilkunastu klatkach
		_check_frame(tag)
		var none := await _lum_behind()
		await _shot("%s_none" % tag)
		for t in [0.06, 1.0]:
			(wall.mesh as BoxMesh).size.x = t
			wall.visible = true
			await _frames(0.6)
			var l := await _lum_behind()
			res["%s_%s" % [tag, t]] = [none, l]
			info("%-5s przeszkoda %.2f m: powietrze za nią %.4f (bez przeszkody %.4f, %.0f%%), grunt %.4f (%.4f, %.0f%%)" % [tag, t, l.y, none.y,
				_pct(l.y, none.y), l.x, none.x, _pct(l.x, none.x)])
			await _shot("%s_wall_%dcm" % [tag, roundi(t * 100.0)])
	for t in [0.06, 1.0]:
		var r: Array = res["sym_%s" % t]
		check("bryła symetryczna: za przeszkodą %.2f m powietrze we mgle ciemniejsze o > 30%%" % t, r[1].y < r[0].y * 0.7)
		check("bryła symetryczna: grunt za przeszkodą %.2f m w cieniu" % t, r[1].x < r[0].x * 0.7)
	var old_r: Array = res["shift_1.0"]
	info("dawny „shift”: powietrze za ścianą 1 m %.0f%% jasności bez ściany (poświata i cień liczone 2–4 m wyżej, niż widać)" % _pct(old_r[1].y, old_r[0].y))
	# kontrola: bez cienia reflektora powietrze za ścianą wraca do jasności jak bez ściany — cień w mgle pochodzi z mapy cieni snopu
	var sp := _beam_light()
	if sp != null:
		sp.shadow_enabled = false
		await _frames(0.6)
		var off := await _lum_behind()
		await _shot("sym_wall_100cm_noshadow")
		sp.shadow_enabled = true
		await _frames(0.6)
		var on := await _lum_behind()
		info("ściana 1 m, cień snopu wł. / wył.: powietrze %.4f / %.4f" % [on.y, off.y])
		check("ciemniej za ścianą tylko z cieniem reflektora (wył. jaśniej o > 30%)", on.y < off.y * 0.7)
	await _measure()
	_finish()

## Kadr gry w tym samym miejscu ekranu: stopy gracza z widoku 3D (`screen_point`) kontra pozycja 2D na ekranie.
func _check_frame(tag: String) -> void:
	var p3: Vector2 = v3d.call("screen_point", Level3D.px_to_m(player.global_position))
	var p2: Vector2 = get_viewport().get_canvas_transform() * player.global_position
	var vp_bg := v3d.get("_vp_bg") as SubViewport
	var cam := v3d.get("_cam_a") as Camera3D
	info("%-5s viewport świata %s, wierszy nad kadrem %d, przesunięcie bryły %.5f, stopy 3D %s / 2D %s" % [tag, vp_bg.size, int(v3d.get("_fog_rows")),
		cam.frustum_offset.y, p3, p2])
	check("%s: kadr 3D na kadrze 2D (stopy gracza < 1,5 px)" % tag, p3.distance_to(p2) < 1.5)
	# warstwa graczy (bez mgły wolumetrycznej) zostaje przy „shifcie” i rozmiarze kadru — postacie na tym samym miejscu co świat
	var cam_b := v3d.get("_cam_b") as Camera3D
	var vp_fg := v3d.get("_vp_fg") as SubViewport
	var pb: Vector2 = get_viewport().get_canvas_transform() * ((v3d.get("_spr_fg") as Sprite2D).global_transform *
		(cam_b.unproject_position(Level3D.px_to_m(player.global_position)) - Vector2(vp_fg.size) * 0.5))
	check("%s: warstwa graczy na kadrze świata (< 1,5 px, viewport %s)" % [tag, vp_fg.size], pb.distance_to(p3) < 1.5)
	if tag == "sym":
		check("sym: bryła kamery symetryczna (przesunięcie < 1 px) i pas nad kadrem", int(v3d.get("_fog_rows")) > 0 and
			absf(cam.frustum_offset.y) < cam.size / float(vp_bg.size.y))

func _build_wall() -> void:
	var px: Vector3 = Level3D.px_to_m(player.global_position)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, WALL_H, Level3D.DEPTH_FRONT + Level3D.DEPTH_BACK)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.18, 0.11)
	mat.roughness = 0.88
	wall = MeshInstance3D.new()
	wall.name = "FogShadowWall"
	wall.mesh = bm
	wall.material_override = mat
	wall.layers = 1
	wall.position = Vector3(px.x + DIST, px.y + WALL_H * 0.5, (Level3D.DEPTH_FRONT - Level3D.DEPTH_BACK) * 0.5)
	(v3d.get("_world") as Node3D).add_child(wall)

func _beam_light() -> SpotLight3D:
	var ent = (v3d.get("_lights") as Dictionary).get(player.get("_beam").get_instance_id())
	return null if ent == null else ent[1] as SpotLight3D

func _pct(a: float, b: float) -> float:
	return a / maxf(b, 1e-6) * 100.0

## Średnia luminancja ekranu za przeszkodą (0,3–8 m za jej tylną ścianą): x — grunt (0–1 m nad podłogą), y — powietrze (1–2 m).
func _lum_behind() -> Vector2:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var scale := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var floor_y := wall.position.y - WALL_H * 0.5
	var back := wall.position.x + 0.5
	var out := Vector2.ZERO
	for k in 2:
		var y0 := floor_y + (0.0 if k == 0 else 1.0)
		var a: Vector2 = v3d.call("screen_point", Vector3(back + 0.3, y0 + 1.0, 0.0)) * scale
		var b: Vector2 = v3d.call("screen_point", Vector3(back + 8.0, y0, 0.0)) * scale
		var r := Rect2i(Vector2i(a), Vector2i(b - a)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var sum := 0.0
		var n := 0
		for j in range(r.position.y, r.end.y, 3):
			for i in range(r.position.x, r.end.x, 3):
				sum += img.get_pixel(i, j).get_luminance()
				n += 1
		out[k] = sum / maxf(n, 1)
	return out

## Zrzut do `--fogshots=KATALOG`.
func _shot(name: String) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fogshots="):
			dir = a.substr("--fogshots=".length())
	if dir == "":
		return
	await _frames(0.3)
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	info("zrzut %s" % dir.path_join(name + ".png"))

# ---------------------------------------------------------------- koszt

func _vps() -> Array:
	var out: Array = [get_viewport().get_viewport_rid()]
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		out.append((n as SubViewport).get_viewport_rid())
	return out

## Średni czas GPU wszystkich viewportów przez `n` klatek obrazu.
func _gpu_avg(n: int) -> float:
	for v in _vps():
		RenderingServer.viewport_set_measure_render_time(v, true)
	for _k in 30:
		await get_tree().process_frame
	var s := 0.0
	for _k in n:
		await get_tree().process_frame
		for v in _vps():
			s += RenderingServer.viewport_get_measured_render_time_gpu(v)
	return s / float(n)

## Czas GPU „shift” kontra bryła symetryczna (bez przeszkody), dwa przebiegi w odwróconej kolejności — dryf zegara GPU wychodzi w różnicy.
func _measure() -> void:
	wall.visible = false
	var res := {false: [], true: []}
	for order in [[false, true, true, false], [true, false, false, true]]:
		for sym in order:
			v3d.set("fog_sym", 2 if sym else 0)
			(res[sym] as Array).append(await _gpu_avg(240))
	var a := _avg(res[false])
	var b := _avg(res[true])
	info("GPU „shift” %.3f ms (%s), bryła symetryczna %.3f ms (%s): %+.3f ms, viewport świata %s" % [a, _fmt(res[false]), b, _fmt(res[true]), b - a,
		(v3d.get("_vp_bg") as SubViewport).size])
	v3d.set("fog_sym", 1)

func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(a.size(), 1)

func _fmt(a: Array) -> String:
	return " / ".join(a.map(func(x): return "%.3f" % float(x)))
