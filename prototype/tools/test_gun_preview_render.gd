extends SceneTree
## Test renderera na GPU/llvmpipe: zbieżne żądania, stary wynik po zmianie broni, cache i brak ciągłego renderu.
## godot --path prototype --rendering-driver opengl3 -s tools/test_gun_preview_render.gd
const Preview := preload("res://scripts/gun_preview.gd")
const Icon := preload("res://scripts/equipped_gun_icon.gd")
const Parts := preload("res://scripts/parts.gd")
var total := 0
var failed := 0

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		print("FAIL gun preview render: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var button := Button.new()
	root.add_child(button)
	var input := root.get_node("InputSetup")
	input._on_node_added(button)
	check("ponowne node_added nie dubluje dźwięku przycisku", button.mouse_entered.get_connections().size() == 1)
	button.free()
	var a := Icon.new()
	var b := Icon.new()
	root.add_child(a)
	root.add_child(b)
	var fit := Parts.encode_ids("m83", ["m83_drum75", "m83_rpkbar", "m83_pbs1"])
	a.set_weapon("m83", fit, 0)
	b.set_weapon("m83", fit, 0)
	# Natychmiastowa zmiana, zanim wspólny render starego zestawu wróci do ikon.
	b.set_weapon("p64", 0, 0)
	var service: Node = Preview.service(self)
	for frame in 90:
		await process_frame
		if service.render_count > 0:
			break
	check("jeden render dla dwóch żądań", service.render_count == 1)
	check("przełączony slot zachowuje pistolet", b.key == "p64" and b._tex == Icon.texture_of("p64"))
	check("wyposażony karabin ma obraz", a._tex != null)
	if a._tex != null:
		var img := a._tex.get_image()
		check("obraz ma rzeczywistą zawartość", img.get_used_rect().get_area() > 5000)
		check("obraz mieści się w budżecie", img.get_width() <= Preview.FRAME.x and img.get_height() <= Preview.FRAME.y)
		check("tło przezroczyste", img.detect_alpha() != Image.ALPHA_NONE)
		check("mipmapy do małych ikon", img.has_mipmaps())
	b.set_weapon("m83", fit, 0)
	check("slot i główna broń współdzielą teksturę", a._tex == b._tex)
	for frame in 30:
		a.set_weapon("m83", fit, 0, Color(1, 1, 1, 0.45))
		await process_frame
	check("bez ponownego renderu w bezruchu i przygaszeniu", service.render_count == 1)
	check("viewport wyłączony po wypieku", service._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	check("model zwolniony po wypieku", service._model == null)
	# Wróć do fabrycznej i ponownie do identycznego zestawu: nowy render nie jest potrzebny.
	a.set_weapon("m83", 0, 0)
	check("fabryczna konfiguracja wraca do gotowej ikony", a._tex == Icon.texture_of("m83"))
	a.set_weapon("m83", fit, 0)
	check("powrót do zestawu używa cache", a._tex == b._tex and service.render_count == 1)
	print("%s gun preview render: %d checks, %d errors" % ["PASS" if failed == 0 else "FAIL", total, failed])
	quit(0 if failed == 0 else 1)
