extends SceneTree
## Głos gracza wg płci (VOICE_MOCAP_PLAN.md A2–A3): każdy kobiecy klucz (`player_hurt_f_1/2`, `player_down_f`, `breath_loop_f`, `revive_f`)
## ma publiczny plik w audio/ i wpis w manifeście (zadyszka jako pętla), kobieta dostaje wariant `_f`, mężczyzna i nieważny wygląd — klucz
## bazowy, a klucz bez wariantu kobiecego wraca do bazowego. Mimik: wołanie wg modelu udawanego kolegi, echo wg płci krzyczącego.
##   godot --headless --path prototype -s tools/test_voice.gd     → ostatni wiersz: [VOICE] PASS / FAIL

const Look := preload("res://scripts/look.gd")
const AudioManifest := preload("res://scripts/audio_manifest.gd")

const BASES := ["player_hurt", "player_down", "breath_loop", "revive"]
const FEMALE_KEYS := ["player_hurt_f_1", "player_hurt_f_2", "player_down_f", "breath_loop_f", "revive_f"]

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[VOICE] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# player.gd używa autoloadów — ładowany po pierwszej klatce, nie przez preload
	var P: GDScript = load("res://scripts/player.gd")
	for k in FEMALE_KEYS:
		var path := String(AudioManifest.PATHS.get(k, ""))
		_check("%s: wpis w manifeście" % k, path != "")
		_check("%s: publiczny plik %s" % [k, path], path != "" and FileAccess.file_exists(path))
	_check("breath_loop_f to pętla", AudioManifest.LOOPS.has("breath_loop_f"))
	var female := Look.code(1, 0)
	var male := Look.code(0, 0)
	for outfit in 3:
		_check("strój %d: kobieta → player_hurt_f" % outfit, P.voice_key_for(Look.code(1, outfit), "player_hurt") == "player_hurt_f")
	for b in BASES:
		_check("%s: kobieta → %s_f" % [b, b], P.voice_key_for(female, b) == b + "_f")
		_check("%s: mężczyzna → %s" % [b, b], P.voice_key_for(male, b) == b)
		_check("%s: nieważny wygląd (-1) → %s" % [b, b], P.voice_key_for(-1, b) == b)
	_check("klucz bez wariantu kobiecego zostaje bazowy", P.voice_key_gender(true, "land_hard") == "land_hard")
	# Mimik (enemy_mimic.gd): wołanie wg pliku modelu udawanego kolegi, echo wg płci krzyczącego
	var M: GDScript = load("res://scripts/enemy_mimic.gd")
	var m = M.new()
	_check("echo kobiety → player_hurt_f", m.echo_voice(true) == "player_hurt_f")
	_check("echo mężczyzny → player_hurt", m.echo_voice(false) == "player_hurt")
	# krzycząca kobieta i mężczyzna w grupie „players” (female_at szuka gracza w miejscu krzyku)
	var root2d := Node2D.new()
	root.add_child(root2d)
	var she := _fake_player(Look.code(1, 2), Vector2(100, 50))
	var he := _fake_player(Look.code(0, 0), Vector2(300, 50))
	root2d.add_child(she)
	root2d.add_child(he)
	# w tej samej klatce: atrapy nie mają pól prawdziwego gracza, a autoloady przeglądają grupę „players” co klatkę
	var f_she: bool = P.female_at(self, Vector2(100, 50))
	var f_he: bool = P.female_at(self, Vector2(300, 50))
	var f_none: bool = P.female_at(self, Vector2(200, 50))
	for n in [she, he]:
		n.remove_from_group("players")
	root2d.free()
	_check("krzyk kobiety rozpoznany w miejscu krzyku", f_she)
	_check("krzyk mężczyzny nie jest kobiecy", not f_he)
	_check("pusty punkt → głos bazowy", not f_none)
	print("[VOICE] PASS (0)" if _fails == 0 else "[VOICE] FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)


func _fake_player(look_code: int, pos: Vector2) -> Node2D:
	var s := GDScript.new()
	s.source_code = "extends Node2D\nvar look := -1\nvar is_bot := false\nvar dead := false\n"
	s.reload()
	var n: Node2D = s.new()
	n.set("look", look_code)
	n.position = pos
	n.add_to_group("players")
	return n
