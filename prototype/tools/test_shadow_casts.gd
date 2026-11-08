extends SceneTree
## Test cieni widoku 3D (`scripts/shadow_casts.gd`):
## (1) wybór lamp z cieniem: najwyżej `limit`, najbliższe pierwsze, histereza (lampa z cieniem zostaje do `limit + keep`, dalej oddaje
##     miejsce), lampa wchodząca do zestawu w czasie gry dostaje cień, gdy jest wśród najbliższych (błąd do 1.7.523: nigdy),
## (2) kopie „tylko cień” siatek gracza: warstwa świata, SHADOWS_ONLY, ta sama siatka i szkielet, bez dzieci, bez powtórnych kopii,
##     widoczność za oryginałem, sprzątanie zwolnionych par i `clear`,
## (3) view3d.gd: lampy nie dostają cienia przy tworzeniu (tylko `_pick_shadows`), a rig gracza ma kopie cienia.
## godot --headless --path prototype -s tools/test_shadow_casts.gd      → ma wypisać PASS
const ShadowCasts := preload("res://scripts/shadow_casts.gd")
var _fail := 0
var _frames := 0

func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL  " + msg)
		_fail += 1

func _keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k

func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_test_pick()
	_test_casts()
	_test_view3d_source()
	print("PASS" if _fail == 0 else "FAILED: %d" % _fail)
	quit(0 if _fail == 0 else 1)
	return true

func _test_pick() -> void:
	# pusty zestaw → pięć najbliższych
	var r := ShadowCasts.pick([1, 2, 3, 4, 5, 6, 7], {}, 5, 1)
	_check(_keys(r) == [1, 2, 3, 4, 5], "pick: pięć najbliższych bez cieni, jest %s" % [_keys(r)])
	# mniej kandydatów niż limit
	r = ShadowCasts.pick([3, 9], {}, 5, 1)
	_check(_keys(r) == [3, 9], "pick: mniej świateł niż limit, jest %s" % [_keys(r)])
	# histereza: 6. z cieniem zostaje, nowy 5. czeka
	r = ShadowCasts.pick([1, 2, 3, 4, 8, 6, 7], {1: true, 2: true, 3: true, 4: true, 6: true}, 5, 1)
	_check(_keys(r) == [1, 2, 3, 4, 6], "pick: histereza trzyma cień na 6. miejscu, jest %s" % [_keys(r)])
	# 7. z cieniem oddaje go najbliższemu bez cienia
	r = ShadowCasts.pick([1, 2, 3, 4, 8, 9, 6], {1: true, 2: true, 3: true, 4: true, 6: true}, 5, 1)
	_check(_keys(r) == [1, 2, 3, 4, 8], "pick: 7. oddaje cień 5., jest %s" % [_keys(r)])
	# błąd do 1.7.523: lampy przy starcie (z cieniem) daleko, nowe przy graczu — cień przechodzi na nowe
	r = ShadowCasts.pick([20, 21, 22, 23, 24, 25, 1, 2, 3, 4, 5], {1: true, 2: true, 3: true, 4: true, 5: true}, 5, 1)
	_check(_keys(r) == [20, 21, 22, 23, 24], "pick: lampy przy graczu przejmują cień od lamp ze startu, jest %s" % [_keys(r)])
	# nigdy więcej niż limit
	r = ShadowCasts.pick([1, 2, 3, 4, 5, 6], {1: true, 2: true, 3: true, 4: true, 5: true, 6: true}, 5, 1)
	_check(r.size() == 5, "pick: najwyżej limit, jest %d" % r.size())

func _test_casts() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = BoxMesh.new()
	body.layers = 2
	body.skeleton = NodePath("..")
	skel.add_child(body)
	var child := MeshInstance3D.new()                       # dziecko oryginału (np. przypięta część): kopia go nie bierze, ale samo dostaje własną
	child.mesh = BoxMesh.new()
	child.layers = 2
	body.add_child(child)
	var other := MeshInstance3D.new()                       # inna warstwa — bez kopii
	other.mesh = BoxMesh.new()
	other.layers = 1
	root.add_child(other)
	var pairs := ShadowCasts.add(root, 2, 1)
	_check(pairs.size() == 2, "casts: kopia każdej siatki warstwy graczy (2), jest %d" % pairs.size())
	var c: MeshInstance3D = null
	for pr in pairs:
		if pr[0] == body:
			c = pr[1]
	_check(c != null, "casts: kopia ciała")
	if c != null:
		_check(c.layers == 1, "casts: kopia w warstwie świata")
		_check(c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "casts: kopia tylko rzuca cień")
		_check(c.mesh == body.mesh, "casts: ta sama siatka")
		_check(c.get_parent() == skel and c.skeleton == body.skeleton, "casts: ten sam szkielet (rodzeństwo oryginału)")
		_check(c.get_child_count() == 0, "casts: kopia bez dzieci")
		_check(body.layers == 2 and body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "casts: oryginał bez zmian")
	_check(ShadowCasts.add(root, 2, 1).is_empty(), "casts: drugie wywołanie nie kopiuje jeszcze raz")
	body.visible = false
	pairs = ShadowCasts.sync(pairs)
	_check(c != null and not c.visible, "casts: schowany oryginał chowa kopię")
	body.visible = true
	pairs = ShadowCasts.sync(pairs)
	_check(c != null and c.visible, "casts: pokazany oryginał pokazuje kopię")
	child.free()
	pairs = ShadowCasts.sync(pairs)
	_check(pairs.size() == 1, "casts: zwolniony oryginał wypada z listy, zostaje %d" % pairs.size())
	ShadowCasts.clear(pairs)
	_check(c == null or c.get_parent() == null, "casts: clear zdejmuje kopie")
	_check(not body.has_meta("shadow_src"), "casts: clear zdejmuje znacznik oryginału")
	_check(ShadowCasts.add(root, 2, 1).size() == 1, "casts: po clear kopie można zrobić od nowa")
	root.free()

func _test_view3d_source() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/view3d.gd")
	_check(src.contains("func _pick_shadows()"), "view3d: wybór cieni przy przeglądzie świateł")
	_check(src.contains("\t_pick_shadows()"), "view3d: _scan_lights woła _pick_shadows")
	_check(not src.contains("shadow_enabled = n <= SHADOW_LIGHTS"), "view3d: cień nie jest już przydzielany przy tworzeniu światła")
	_check(src.contains("\"casts\": ShadowCasts.add(actor, LAYER_ACTORS, LAYER_WORLD)"), "view3d: rig gracza ma kopie cienia")
	_check(src.contains("ShadowCasts.clear(rig.get(\"casts\""), "view3d: zwolnienie riga sprząta kopie")
