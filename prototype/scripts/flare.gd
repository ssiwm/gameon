extends Node2D
## Flara rzucana (F, 1.7.5): światło-przynęta. Leci łukiem, ląduje, pali się FLARE_LIFE s.
##
## Odciąga ćmy (światłolubne, enemy.gd `cma`) i budzi ciekawość Trzosków (`see_light`) — wabik BEZ hałasu
## (Q kosztuje Uwagę), za to ograniczony pulą flar (NoiseMgr.flares) i widoczny z daleka. Ćma, która
## doleci do flary, spala się przy niej — flara chroni przed ćmami, jeśli rzucisz ją daleko od siebie.
## Pozycja i lot są deterministyczne z parametrów startu, więc nie trzeba jej synchronizować.

const Lights := preload("res://scripts/lights.gd")
const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")
const Weapons := preload("res://scripts/weapons.gd")

const SHADOW_FLARES := 2            ## tyle flar naraz rzuca cienie (kolejne świecą bez nich)
const FLARE_LIFE := 25.0
const GRAVITY := 520.0
const LURE_EVERY := 0.5
const WATER_LIFE := 8.0           ## flara, która spadła do wody (basen areny Pijawki), gaśnie po tylu s — cień trzeba oświetlać stale
## Flara na spadochronie (nabój oświetlający 40 mm, jak M583): opada powoli, świeci jaśniej i dłużej, przyciąga wrogów jak zwykła.
const CHUTE_LIFE := 40.0
const CHUTE_FALL := 24.0          ## px/s opadania na spadochronie (≈ 2 m/s w skali świata 3D)
const CHUTE_DRIFT_DAMP := 0.6     ## /s wygaszania prędkości poziomej
## Zasypana flara (uwaga z gry 2026-11-22, 1.2: „flare można wrzucić w grunt”): rzucona do wnęki wykopu w żwirze leżała na dnie, a żwir
## osypujący się do wykopu (dig_zone.gd `_settle`) przykrywał ją — świeciła spod gruntu. Co BURY_CHECK s leżąca flara, nad którą jest skała
## strefy (BURY_DEPTH px nad nią — nie płytki styk konturu z gęstością), wychodzi na wierzch zsypu i spada na niego od nowa.
const BURY_CHECK := 0.2
const BURY_DEPTH := 6.0
const BURY_SMOTHER := 0.6        ## s: przysypana bez powietrza nad sobą dogasa (energia światła maleje z life / 3)

var vel := Vector2.ZERO
var life := FLARE_LIFE
var chute := false                ## ustawiane przed dodaniem do drzewa (level.spawn_flare)

var _landed := false
var _bury_t := 0.0
var _light: Lights.GameLight
var _t := 0.0
var _lure_t := 0.0
## HD (Sprites.newitem): tuba flary (obraca się w locie, leży po lądowaniu) i nakładka z płomieniem na czubku.
const HD_SCALE := 0.5
var _pv: Node2D
var _spin := 0.0
var _lie := 0.0

func _ready() -> void:
	add_to_group("flares")
	z_index = 2
	material = Lights.unshaded()
	# cienie tylko od dwóch najnowszych flar naraz: każde światło z cieniami wymusza dodatkowe rysowanie wszystkich sprite'ów w zasięgu
	# (zmierzone: 5 flar ≈ +0,7 ms przy 40 wrogach), a z daleka różnicy nie widać
	if chute:
		life = CHUTE_LIFE
	_light = Lights.make_light(Lights.radial(), 13.0 if chute else 8.0, Color(1.0, 0.82, 0.62) if chute else Color(1.0, 0.42, 0.2), 1.8 if chute else 1.5,
		get_tree().get_nodes_in_group("flares").size() <= SHADOW_FLARES)
	add_child(_light)
	if Sprites.newitem and ItemsHd.has("flare"):
		_pv = Node2D.new()
		add_child(_pv)
		var sp := ItemsHd.make("flare", _pv, HD_SCALE, 0.3)
		sp.position = Vector2(0, ItemsHd.body_wp("flare").y * HD_SCALE * 0.5)          # środek tuby w punkcie obrotu
		_spin = randf_range(-9.0, 9.0)
		_lie = (1.0 if randf() < 0.5 else -1.0) * randf_range(1.35, 1.75)
	Audio.play_at("flare_ignite", global_position, Audio.BUS_WORLD, -4.0)

## Wylądowała na kaflu wody: dopala się tylko WATER_LIFE s (dym i plusk). Na oleju zapala plamę (serwer, `level.spawn_fire_patch`).
func _check_water() -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	if lvl == null or not lvl.has_method("surface_at"):
		return
	match String(lvl.surface_at(global_position)):
		"water":
			life = minf(life, WATER_LIFE)
			Audio.play_variant_at("step_water", 3, global_position, Audio.BUS_WORLD, -6.0, 1.4)
		"oil":
			if NoiseMgr.is_server() and lvl.has_method("spawn_fire_patch"):
				lvl.spawn_fire_patch(global_position + Vector2(0.0, -1.0), Weapons.HKM9, 0)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_t += delta
	if not _landed and chute:
		vel.y = minf(vel.y + GRAVITY * delta, CHUTE_FALL)
		vel.x *= maxf(0.0, 1.0 - CHUTE_DRIFT_DAMP * delta)
	if not _landed and not chute:
		vel.y += GRAVITY * delta
	if not _landed:
		var from := global_position
		var to := from + vel * delta
		var q := PhysicsRayQueryParameters2D.create(from, to, 1 | 16)
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
		else:
			var n: Vector2 = hit["normal"]
			global_position = hit["position"] + n
			if n.y < -0.5:
				_landed = true
				vel = Vector2.ZERO
				_check_water()
			else:
				vel = vel.bounce(n) * 0.4
	if _landed:
		_bury_t -= delta
		if _bury_t <= 0.0:
			_bury_t = BURY_CHECK
			_unbury()
	if _pv != null:
		if _landed:
			_pv.rotation = lerp_angle(_pv.rotation, _lie, minf(1.0, delta * 14.0))
			_pv.position.y = lerpf(_pv.position.y, -1.4, minf(1.0, delta * 14.0))
		else:
			_pv.rotation += _spin * delta
			_pv.position.y = 0.0
	# dogasanie na końcu i migotanie płomienia
	_light.energy = (1.35 + 0.35 * sin(_t * 17.0) * sin(_t * 5.1)) * minf(1.0, life / 3.0)
	if NoiseMgr.is_server():
		_lure_t -= delta
		if _lure_t <= 0.0:
			_lure_t = LURE_EVERY
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.has_method("see_light"):
					e.see_light(global_position)
	queue_redraw()

## Leżąca flara pod zsypem żwiru (`BURY_CHECK`): w górę do pierwszego powietrza w strefie i znów w locie — ląduje na wierzchu zsypu.
## Bez powietrza nad sobą w strefie (zsyp do stropu) gaśnie przysypana (BURY_SMOTHER s) — poza strefą w górę nie szuka: nad nią skała
## mapy, z której spadała z powrotem przez żwir (kolizja strefy to kontur, od środka bryły nic jej nie zatrzymywało).
func _unbury() -> void:
	for z in get_tree().get_nodes_in_group("dig_zones"):
		if not (z as Node2D).has_method("solid_at_px") or not z.solid_at_px(global_position + Vector2(0.0, -BURY_DEPTH)):
			continue
		var box: Rect2 = z.rect_px()
		var p := global_position + Vector2(0.0, -BURY_DEPTH)
		while p.y > box.position.y and z.solid_at_px(p):
			p.y -= 2.0
		if p.y <= box.position.y or z.solid_at_px(p):
			life = minf(life, BURY_SMOTHER)
			return
		global_position = p + Vector2(0.0, -1.0)
		_landed = false
		vel = Vector2.ZERO
		return
