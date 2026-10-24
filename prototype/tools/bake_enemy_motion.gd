extends SceneTree
## Odtwarzalny zapis autorskich klipów riga do natywnej AnimationLibrary Godota.
const Motion := preload("res://scripts/enemy_motion.gd")
func _initialize() -> void:
	var error := ResourceSaver.save(Motion.build(), Motion.PATH)
	print("%s bake enemy motion" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
