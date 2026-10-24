extends SceneTree
## Regresje akcji: odzyskanie fazy ze snapshotu, przerwanie, kontakt kilofa, stopy i mechanika części.
## godot --headless --path prototype -s tools/test_combat_motion.gd
const Char3D := preload("res://scripts/char3d.gd")
const CharClips := preload("res://scripts/char_clips.gd")
const Motion := preload("res://scripts/weapon_motion.gd")
const LOOKS := ["male_scav", "female_scav", "male_hazmat", "female_hazmat", "male_medic", "female_medic"]
var c: Char3D
var ran := false
var failed := 0
var total := 0
var worst_aim := 0.0
var worst_floor := 0.0
var worst_foot := 0.0
var foot_at := ""

func check(label: String, ok: bool) -> void:
	total += 1
	if not ok:
		failed += 1
		if failed <= 20:
			print("FAIL combat: ", label)

func _initialize() -> void:
	c = Char3D.new()
	root.add_child(c)
	check("model MPFB", c.setup("male_scav", "kilof"))
	c._set_on_screen(true)

func clocks() -> void:
	for fps in [30, 60, 120]:
		var clock := Motion.new()
		var action := Vector4i(1, Motion.MELEE, 11, 0)
		clock.sample(action, Vector2(0.9, 0.18), 0.0)
		check("snapshot zaczyna w bieżącej fazie", is_equal_approx(clock.phase, 0.2))
		var previous := clock.phase
		for i in fps:
			clock.sample(action, Vector2(0.9, 0.18), 1.0 / float(fps)) # powtórki i brak nowych pakietów
			check("faza rośnie mimo zgubionych pakietów", clock.phase >= previous)
			previous = clock.phase
		check("nie zapętla skończonego ciosu", is_equal_approx(clock.phase, 1.0))
		clock.sample(Vector4i(2, Motion.RELOAD, 0, Motion.ROUND), Vector2(0.4, 0.0), 0.0)
		check("nowy nabój zaczyna nowy cykl", clock.started and is_zero_approx(clock.phase))
		clock.sample(Vector4i(2, Motion.NONE, 0, 0), Vector2.ZERO, 0.0)
		clock.sample(Vector4i(2, Motion.RELOAD, 0, 0), Vector2(0.4, 0.2), 0.0)
		check("pakiet nie wznawia przerwanej akcji", clock.phase < 0.0)
		clock.sample(action, Vector2(0.9, 0.5), 0.0)
		check("stara akcja jest odrzucona", clock.phase < 0.0)
	for key in Motion.RECOIL:
		var peak := 0.0
		for i in 121:
			peak = maxf(peak, Motion.recoil_at(key, float(i) / 120.0).x)
		check("odrzut bez teleportacji >5 cm " + key, peak > 0.0 and peak <= 0.05)
		check("odrzut wygasa " + key, Motion.recoil_at(key, 0.6).length() < 0.0001)

func pickaxe() -> void:
	for look in LOOKS:
		c.set_look(look)
		for state in ["idle", "crouch"]:
			for degrees in [-80, -50, 0, 50, 85]:
				for face in [1.0, -1.0]:
					var angle := deg_to_rad(float(degrees))
					var aim := Vector2(cos(angle) * face, -sin(angle))
					c.swing_t = -1.0
					for i in 24:
						c.update(1.0 / 60.0, state, face, aim, 0.0)
					var feet := [c._gp(c._b["LeftFoot"]).origin, c._gp(c._b["RightFoot"]).origin]
					for i in 101:
						c.swing_t = float(i) / 100.0
						c.update(0.009, state, face, aim, 0.0)
						var head := c._gun.transform * (c._gun_info["muzzle"] as Vector3)
						worst_floor = maxf(worst_floor, maxf(-head.y, 0.0))
						for side_index in 2:
							var side := "Left" if side_index == 0 else "Right"
							var drift := absf(c._gp(c._b[side + "Foot"]).origin.y - (feet[side_index] as Vector3).y)
							if drift > worst_foot:
								worst_foot = drift
								foot_at = "%s %s %d %f u=%.2f hip=%s foot=%s base=%s clip=%s" % [look, state, degrees, face, c.swing_t, c._gp(c._b["Hips"]).origin, c._gp(c._b[side + "Foot"]).origin, feet[side_index], c._clip_foot[side].origin]
						if i == 45:
							var error := absf(rad_to_deg((c.muzzle_px - Vector2(0, -9)).angle_to(aim)))
							worst_aim = maxf(worst_aim, error)
		check("klip istnieje na " + look, c._combat_clip == "combat_chop")
	check("kilof mieści się w stożku trafienia", worst_aim <= 50.0)
	check("głowica nie przechodzi pod podłoże", worst_floor < 0.005)
	check("nogi amortyzują z zachowaniem wysokości stóp", worst_foot < 0.01)
	var keys: Array = Char3D._combat_motion.chop.slide
	check("prowadząca dłoń przesuwa się po trzonku", float(keys[1][1]) - float(keys[2][1]) > 0.1)

func parts() -> void:
	c.set_look("male_scav")
	c.set_gun("m83")
	c.swing_t = -1.0
	c.reload_t = -1.0
	for i in 24:
		c.update(1.0 / 60.0, "idle", 1.0, Vector2.RIGHT, 0.0)
	var mags := c._gun.find_children("*__mag", "Node3D", true, false)
	check("magazynek wydzielony", not mags.is_empty())
	if mags.is_empty():
		return
	var mag: Node3D = mags[0]
	var rest := mag.transform
	c.reload_t = 0.48
	c.update(1.0 / 60.0, "idle", 1.0, Vector2.RIGHT, 0.0)
	check("magazynek podąża za dłonią", mag.position.distance_to(rest.origin) > 0.05)
	c.reload_t = -1.0
	c.update(1.0 / 60.0, "idle", 1.0, Vector2.RIGHT, 0.0)
	check("przerwanie przywraca mocowanie magazynka", mag.transform.is_equal_approx(rest))
	c.set_gun("srut8")
	var pumps := c._gun.find_children("*__pump", "Node3D", true, false)
	check("ruchoma pompka jest oddzielona od lufy", not pumps.is_empty())
	if not pumps.is_empty():
		var pump: Node3D = pumps[0]
		var origin := pump.position
		c.cycle_t = 0.42
		c.update(1.0 / 60.0, "idle", 1.0, Vector2.RIGHT, 0.0)
		check("pompka cofa się z dłonią o 17 cm", absf(pump.position.x - origin.x + 0.17) < 0.001)

func _process(_delta: float) -> bool:
	if ran:
		return true
	ran = true
	clocks()
	pickaxe()
	parts()
	print("FOOT ", foot_at)
	print("COMBAT max aim %.3f deg, floor penetration %.5f m, foot drift %.5f m" % [worst_aim, worst_floor, worst_foot])
	print("PASS combat motion (%d checks)" % total if failed == 0 else "FAIL combat motion (%d/%d failed)" % [failed, total])
	quit(0 if failed == 0 else 1)
	return true
