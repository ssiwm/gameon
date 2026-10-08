extends RefCounted
## Światło i ciemność (GDD §8.3). Wspólne tekstury, materiał „unshaded" i
## reguła „kogo oświetla latarka" — używane przez gracza, wrogów, Stalkera,
## gniazda i znacznik ekstrakcji.
##
## Skala: 16 px = 1 m (jak w HUD ekstrakcji). Tekstury mają promień 128 px
## przy texture_scale = 1, więc skala = metry * 16 / 128.

const PX_PER_M := 16.0
const TEX_RADIUS := 128.0

## Światło otoczenia (CanvasModulate) i tło nieba. Strojone pomiarem
## luminancji ekranu (1.3.6), potem −30% (1.6.7: ambient i aura gracza ×0,7): przy 0,13 świat poza aurą był prawie tak jasny
## jak przy graczu (0,035 vs 0,077) — ciemność nie robiła różnicy.
const AMBIENT := Color(0.0245, 0.0266, 0.0406)
const SKY := Color(0.008, 0.010, 0.017)
const AURA_ENERGY := 0.525

const BASE_M := 6.0          ## widoczność bazowa wokół gracza
const FLASHLIGHT_M := 8.0    ## stożek latarki
const FLARE_M := 12.0        ## flara (znacznik ekstrakcji)
const CONE_HALF_DEG := 24.0

const Weapons := preload("res://scripts/weapons.gd")

## Błysk z lufy jako sygnał świetlny (faza 3 przeglądu broni): strzał o błysku ≥ FLASH_MIN widać przez FLASH_LIFE_MS.
## Budzi i przyciąga ćmy (enemy.gd `_nearest_light`) — głośna broń ma drugą cenę poza hałasem.
const FLASH_MIN := 1.6                ## `flash_light` broni od tej wartości (strzelba i cięższe) liczy się jako sygnał
const FLASH_LIFE_MS := 600
const LIGHT_WEAPON_M := 10.0          ## wiązka i płomień widoczne dla Stalkera z tej odległości (jak flashlight_on, bez stożka)
static var flashes: Array = []        ## [{pos, until, node}] — tylko serwer ich używa

static func add_flash(pos: Vector2, power: float, node: Node2D) -> void:
	if power < FLASH_MIN:
		return
	var now := Time.get_ticks_msec()
	flashes = flashes.filter(func(f: Dictionary) -> bool: return int(f["until"]) > now)
	flashes.append({"pos": pos, "until": now + FLASH_LIFE_MS, "node": node})
	if flashes.size() > 12:
		flashes.pop_front()

static func active_flashes() -> Array:
	var now := Time.get_ticks_msec()
	return flashes.filter(func(f: Dictionary) -> bool: return int(f["until"]) > now)

## Gracz strzelający wiązką albo płomieniem (broń cicha, ale jasna) w zasięgu `LIGHT_WEAPON_M` i bez ściany do `pos` — albo null.
## Stalker idzie do takiego światła tak samo jak do latarki.
static func light_weapon_on(pos: Vector2, tree: SceneTree, space: PhysicsDirectSpaceState2D) -> Node2D:
	for p in tree.get_nodes_in_group("players"):
		if p.dead or not p.w_firing:
			continue
		var k: int = Weapons.def(int(p.weapon)).kind
		if k != Weapons.Kind.BEAM and k != Weapons.Kind.FLAME:
			continue
		var from: Vector2 = p.global_position + Vector2(0, -9)
		if from.distance_to(pos) > LIGHT_WEAPON_M * PX_PER_M:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters2D.create(from, pos, 1)).is_empty():
			continue
		return p
	return null

## Migotanie wszystkich świateł graczy do tej chwili (ms) — krzyk Żyły w fazie 3.
static var flicker_until_ms := 0

static func flickering() -> bool:
	return Time.get_ticks_msec() < flicker_until_ms

## Mnożnik energii przy migotaniu: krótkie zaniki, jak przy słabym kontakcie.
static func flicker_mult() -> float:
	if not flickering():
		return 1.0
	return 0.08 if randf() < 0.35 else 1.0

static var _radial: Texture2D
static var _cone: Texture2D
static var _unshaded: CanvasItemMaterial

static func scale_for(meters: float) -> float:
	return meters * PX_PER_M / TEX_RADIUS

## Miękkie koło: pełne światło w środku, zanik do zera na krawędzi.
static func radial() -> Texture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 256
		t.height = 256
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_radial = t
	return _radial

## Stożek latarki: wierzchołek w środku tekstury, świeci w +X (obracamy
## światło kątem celowania). Miękkie brzegi kątowe i zanik z odległością.
static func cone() -> Texture2D:
	if _cone == null:
		var n := 256
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n * 0.5, n * 0.5)
		var half := deg_to_rad(CONE_HALF_DEG)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var a := 0.0
				var r := d.length() / (n * 0.5)
				if d.x > 0.0 and r <= 1.0:
					var ang := absf(d.angle())
					var edge := 1.0 - smoothstep(half * 0.65, half, ang)
					var fall := 1.0 - smoothstep(0.45, 1.0, r)
					# „gorący punkt" przy lufie, żeby snop nie zaczynał się od zera
					var near := 1.0 - smoothstep(0.0, 0.08, r)
					a = maxf(edge * fall, near * 0.6)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_cone = ImageTexture.create_from_image(img)
	return _cone

## Materiał dla rzeczy, które mają być czytelne w ciemności niezależnie od
## światła: etykiety graczy, paski, oczy, flara, smugi pocisków.
static func unshaded() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded

## Nakładka „unshaded" rysowana przez właściciela: host._draw_overlay(ov).
static func add_overlay(host: Node2D) -> Node2D:
	var ov := Node2D.new()
	ov.name = "Overlay"
	ov.material = unshaded()
	ov.draw.connect(host._draw_overlay.bind(ov))
	host.add_child(ov)
	return ov

## Wysokość świateł (px) nad płaszczyzną sprite'ów — używana tylko przez sprite'y z mapą normalnych (arkusze HD „normal”); płaskie sprite'y i kafle jej nie czują.
const LIGHT_HEIGHT := 80.0

static func make_light(tex: Texture2D, meters: float, color: Color, energy: float, shadows: bool) -> PointLight2D:
	var l := PointLight2D.new()
	l.height = LIGHT_HEIGHT
	l.texture = tex
	l.texture_scale = scale_for(meters)
	l.color = color
	l.energy = energy
	l.shadow_enabled = shadows
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_color = Color(0, 0, 0, 1)
	return l

## Gracz, którego latarka oświetla punkt `pos` (zasięg, kąt stożka i brak
## ściany po drodze), albo null. Działa na każdym peerze — `flashlight`
## i `aim_dir` są replikowane.
static func flashlight_on(pos: Vector2, tree: SceneTree, space: PhysicsDirectSpaceState2D) -> Node2D:
	var reach := FLASHLIGHT_M * PX_PER_M
	var half := deg_to_rad(CONE_HALF_DEG)
	for p in tree.get_nodes_in_group("players"):
		if not p.flashlight or p.dead:
			continue
		var from: Vector2 = p.global_position + Vector2(0, -9)
		var d := pos - from
		if d.length() > reach or d.length() < 1.0:
			continue
		if absf(d.angle_to(p.aim_dir)) > half:
			continue
		var q := PhysicsRayQueryParameters2D.create(from, pos, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		return p
	return null
