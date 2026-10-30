extends RefCounted
## Światło i ciemność (GDD §8.3). Opis świateł gry (`GameLight` — w scenie stawia je widok 3D), materiał „unshaded" i
## reguła „kogo oświetla latarka" — używane przez gracza, wrogów, Stalkera,
## gniazda i znacznik ekstrakcji.
##
## Skala: 16 px = 1 m projektowy (jak w HUD ekstrakcji i kodeksie) — zasięgi w GDD są w tych metrach. Świat 3D ma skalę prawdziwą
## (`Level3D.PX`: 1 px = 0,082 m, postać 1,8 m = 22 px), więc metr projektowy to w obrazie ok. 1,31 m.

const PX_PER_M := 16.0

## Domyślny kolor ciemności mapy (`level.ambient`, stan) i tło nieba. Strojony pomiarem luminancji ekranu w czasach obrazu 2D (1.3.6, 1.6.7).
## Obraz 3D bierze z niego tylko „ciepło” (kryjówka: bursztynowe otoczenie, `Level3D.build_environment`) i jasność papieru notatek
## (hud.gd); samą noc w 3D stroi światło otoczenia sceny, a jasność ekranu — ustawienie jasności (`Settings.exposure_mult`).
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

static var _unshaded: CanvasItemMaterial

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

## Źródło światła w symulacji: sam opis — pozycja i obrót z węzła, kolor, energia, zasięg, kula albo stożek. Niczego nie rysuje:
## światło w scenie stawia widok 3D (view3d.gd: _scan_lights, grupa „game_lights"), a właściciel steruje nim jak dotąd
## (`energy`, `color`, `enabled`, `position`, `rotation`).
class GameLight extends Node2D:
	var color := Color.WHITE
	var energy := 1.0
	var enabled := true
	var range_px := 96.0                  ## zasięg [px świata]
	var is_cone := false                  ## stożek (latarka) zamiast kuli
	var shadow_enabled := false           ## życzenie właściciela; o cieniach w scenie decyduje widok 3D (najbliższe światła)
	func _enter_tree() -> void:
		add_to_group("game_lights")

## Rodzaj światła dla `make_light`: kula albo stożek latarki.
static func radial() -> String:
	return "radial"

static func cone() -> String:
	return "cone"

static func make_light(kind: String, meters: float, color: Color, energy: float, shadows: bool) -> GameLight:
	var l := GameLight.new()
	l.is_cone = kind == "cone"
	l.range_px = meters * PX_PER_M
	l.color = color
	l.energy = energy
	l.shadow_enabled = shadows
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
		if d.length() > reach * float(p.get("beam_mult") if p.get("beam_mult") != null else 1.0) or d.length() < 1.0:      # ćmy na szkle skracają snop
			continue
		if absf(d.angle_to(p.aim_dir)) > half:
			continue
		var q := PhysicsRayQueryParameters2D.create(from, pos, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		return p
	return null
