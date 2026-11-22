extends SceneTree
## Flara zasypana żwirem (uwaga z gry 2026-11-22, 1.2: „flare można wrzucić w grunt”): strefa żwiru 6 × 4 kafle z korytarzem po prawej
## (jak test_dig_face, domieszka 0,25 jak DigZone1 w 1.2), wnęka wykopana przy czole na wysokości podłogi, flara wrzucona do wnęki.
## Żwir nad wnęką osypuje się (dig_zone.gd `_settle`) i przykrywa dno — flara (flare.gd `_unbury`) ma wyjść na wierzch zsypu. Sprawdza po 5 s:
##  1. kontrola testu: miejsce, w którym flara wylądowała, jest teraz pod żwirem (zsyp naprawdę zasypał wnękę);
##  2. flara leży (wylądowała) i nie jest zasypana: BURY_DEPTH px nad nią nie ma skały strefy;
##  3. flara nie wyszła ponad strefę (szuka najbliższego wierzchu, a nie wyskakuje z gruntu).
## godot --headless --path prototype -s tools/test_flare_dig.gd   → ma wypisać [FLARE-DIG] PASS

var Flare: GDScript             ## load w _setup: flare.gd i dig_zone.gd potrzebują autoloadów (Audio, Scrap)

const C0 := 10
const R0 := 10
const C1 := 15
const R1 := 13
const T := 16.0
const BLAST := 2                ## dig_materials.gd Tool.BLAST

var _z: Node2D
var _f: Node2D
var _frames := 0
var _fails := 0
var _land_at := Vector2.INF

func _check(label: String, ok: bool) -> void:
	print("[FLARE-DIG] %s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _physics_process(_dt: float) -> bool:
	_frames += 1
	if _frames == 2:
		_setup()
	elif _frames == 4:
		# wykop przy czole na wysokości podłogi (2 kafle w głąb, 1,5 wysokości) i flara wrzucona na jego dno — luźny żwir nad wykopem
		# zsypuje się w kilkanaście klatek, a flara leży już na dnie (w grze: rzut do wnęki tuż po uderzeniu kilofem)
		var r := Rect2(Vector2((C1 - 1) * T, (R1 + 1) * T - 24.0), Vector2(2.0 * T, 24.0))
		for k in 4:
			_z.apply_dig(r.get_center(), r.size * 0.5, 2.0, BLAST)
		_f = Flare.new()
		_f.position = Vector2((C1 + 1) * T - 12.0, (R1 + 1) * T - 3.0)
		root.add_child(_f)
	elif _frames == 4 + 300:
		_verify()
		return true
	elif _frames > 4 and _land_at == Vector2.INF and _f != null and bool(_f.get("_landed")):
		_land_at = _f.global_position
	return false

func _setup() -> void:
	Flare = load("res://scripts/flare.gd")
	_z = load("res://scripts/dig_zone.gd").new()
	root.add_child(_z)
	var map_solid := func(c: int, r: int) -> bool:
		return not (c > C1 and c < C1 + 12 and r > R0 and r <= R1)
	_z.setup([C0, R0, C1, R1, "gravel", 1201, 0.25], map_solid, func(_c: int, _r: int) -> bool: return true)
	var floor_body := StaticBody2D.new()                       # podłoga korytarza i strefy (wiersz R1 + 1) — kafle mapy
	floor_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2((C1 + 14 - C0) * T, T)
	cs.shape = sh
	cs.position = Vector2(C0 * T, (R1 + 1) * T) + sh.size * 0.5
	floor_body.add_child(cs)
	root.add_child(floor_body)

func _verify() -> void:
	var depth := 6.0
	_check("kontrola: flara wylądowała we wnęce (%s)" % _land_at, _land_at != Vector2.INF and _land_at.x < (C1 + 1) * T)
	_check("kontrola: dno wnęki pod zsypem żwiru", _land_at != Vector2.INF and _z.solid_at_px(_land_at + Vector2(0.0, -depth)))
	var at := _f.global_position
	_check("flara leży na wierzchu (%s), nie pod żwirem" % at, bool(_f.get("_landed")) and not _z.solid_at_px(at + Vector2(0.0, -depth)))
	_check("flara w strefie albo przy niej, nie nad nią (%s)" % at, at.y >= R0 * T - 4.0)
	print("[FLARE-DIG] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
