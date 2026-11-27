extends RefCounted
## Ujęcie kamery świata na stanowisko warsztatu (WORKSHOP_IMMERSION_PLAN.md R1): po [E] kamera dojeżdża z kadru przekroju do stołu —
## oko na wysokości oczu stojącego, przed płaszczyzną gry, lekko z góry na blat — a stół ląduje w pasie ekranu, którego nie zasłania
## karta stanowiska (`band`: od–do w ułamku szerokości ekranu, workshop_ui.gd `focus_band`). Bryła widzenia zostaje symetryczna
## (mgła wolumetryczna Godota zakłada symetryczną, view3d.gd `_fog_rows`): stół trafia w pas przesunięciem oka w bok i pochyleniem
## kamery w dół, nie „shiftem” obiektywu. Same obliczenia — statyczne, sprawdza je tools/test_hub_camera.gd `[STATION-SHOT]`.

const PX := 1.8 / 22.0                  ## m na px świata (Level3D.PX)

## Domyślne ujęcie; stanowisko może nadpisać pola w `shot` (station.gd).
## eye_h — oko nad podłogą stanowiska [m], eye_z — oko przed płaszczyzną gry [m], fov — pionowy kąt widzenia [°],
## aim_h — punkt celowania nad podłogą (blat) [m], aim_v — gdzie ma wypaść w pionie (−1 dół … 1 góra ekranu),
## main — który model z `models` jest stołem (środek ujęcia).
const DEFAULT := {"eye_h": 1.55, "eye_z": 2.1, "fov": 50.0, "aim_h": 0.95, "aim_v": -0.12, "main": 0}
const TIME := 0.45                     ## s — najazd na stół i odjazd (plan R1: ≤ 0,45 s, przerywalny)
const MIN_BAND := 0.18                  ## węższy wolny pas (ława ARMS na cały ekran) — stół na środku, i tak zakryty kartą

## Krok wagi najazdu 0..1 (view3d.gd `_sp`): do `want` w TIME, od bieżącej wagi (zamknięcie w trakcie najazdu — od razu odwrót);
## „Reduce effects” (`cut`) — cięcie, bez najazdu.
static func step(w: float, want: float, dt: float, cut: bool) -> float:
	return want if cut else move_toward(w, want, dt / TIME)

static func param(shot: Dictionary, key: String) -> Variant:
	return shot.get(key, DEFAULT[key])

## Punkt celowania w świecie 3D [m]: środek modelu-stołu na wysokości blatu, w jego głębi. `marker` — znacznik stanowiska w px świata
## (stopy gracza przy [E]), `models` — [model, przesunięcie x w px, głębia z w m] (station.gd).
static func target(marker: Vector2, models: Array, shot: Dictionary) -> Vector3:
	var dx := 0.0
	var z := -1.0
	var i := int(param(shot, "main"))
	if i >= 0 and i < models.size():
		dx = float(models[i][1])
		z = float(models[i][2])
	return Vector3((marker.x + dx) * PX, -marker.y * PX + float(param(shot, "aim_h")), z)

## Środek wolnego pasa ekranu w ułamku szerokości (0 lewa krawędź, 1 prawa); wąski pas — środek ekranu.
static func band_center(band: Vector2) -> float:
	return (band.x + band.y) * 0.5 if band.y - band.x >= MIN_BAND else 0.5

## Kadr ujęcia: {eye: Vector3, basis: Basis, fov: float} dla proporcji ekranu `aspect` i wolnego pasa `band`.
static func frame(marker: Vector2, models: Array, shot: Dictionary, aspect: float, band: Vector2) -> Dictionary:
	var t := target(marker, models, shot)
	var fov := float(param(shot, "fov"))
	var th := tan(deg_to_rad(fov * 0.5))
	var floor_y := -marker.y * PX
	var eye := Vector3(t.x, floor_y + float(param(shot, "eye_h")), float(param(shot, "eye_z")))
	var d := eye.z - t.z
	var drop := eye.y - t.y                                    # o ile oko jest nad blatem
	# pochylenie w dół: blat leży `aim_v` od środka ekranu w pionie
	var pitch := atan2(drop, d) + atan(float(param(shot, "aim_v")) * th)
	var basis := Basis(Vector3.RIGHT, -pitch)
	# głębia stołu wzdłuż osi kamery (tylko pochylenie, bez skrętu) i przesunięcie oka w bok, żeby stół wypadł w środku wolnego pasa
	var depth := d * cos(pitch) + drop * sin(pitch)
	var u := band_center(band) * 2.0 - 1.0
	eye.x = t.x - u * depth * th * aspect
	return {"eye": eye, "basis": basis, "fov": fov}

## Rzut punktu świata na ekran w kadrze `fr` (frame): Vector2 w zakresie −1…1 (x w prawo, y w górę); z < 0 — punkt za kamerą.
static func project(p: Vector3, fr: Dictionary, aspect: float) -> Vector3:
	var b: Basis = fr["basis"]
	var c: Vector3 = b.inverse() * (p - (fr["eye"] as Vector3))   # przestrzeń kamery: patrzy w −z
	var depth := -c.z
	if depth <= 0.01:
		return Vector3(0.0, 0.0, -1.0)
	var th := tan(deg_to_rad(float(fr["fov"]) * 0.5))
	return Vector3(c.x / (depth * th * aspect), c.y / (depth * th), depth)
