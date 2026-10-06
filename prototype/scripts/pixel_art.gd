extends RefCounted
## Ostre skalowanie pixel-artu w UI. Dwa powody rozmycia miniatur: (1) kontrolki rysowały z domyślnym
## filtrem liniowym (reszta gry ustawia NEAREST), (2) skala HUD (0,7) i rozciągnięcie okna dawały
## nieliczbową liczbę pikseli ekranu na piksel rysunku — nawet z NEAREST wychodziły nierówne piksele.
##
## Tu liczymy skalę lokalną tak, żeby na EKRANIE jeden piksel rysunku = całkowita liczba pikseli ekranu.

## Ile pikseli ekranu przypada na jedną jednostkę lokalną kontrolki (skala HUD × warstwa × rozciągnięcie okna).
static func device_scale(ci: CanvasItem) -> float:
	var s := ci.get_global_transform_with_canvas().get_scale().x
	var vp := ci.get_viewport()
	if vp != null:
		s *= vp.get_stretch_transform().get_scale().x
	return maxf(s, 0.05)

## Skala lokalna dla ramki `frame` w polu `avail` (jednostki lokalne): największa całkowita liczba pikseli
## ekranu na piksel rysunku, która się mieści (maks. `max_n`). Gdy ramka nie mieści się nawet 1:1,
## schodzi do 1/2, 1/3… (równe zmniejszenie zamiast rozmycia).
static func fit(ci: CanvasItem, frame: Vector2, avail: Vector2, max_n := 12) -> float:
	var dev := device_scale(ci)
	var raw := minf(avail.x / frame.x, avail.y / frame.y) * dev     # pikseli ekranu na piksel rysunku
	if raw >= 1.0:
		return float(mini(int(floor(raw)), max_n)) / dev
	return (1.0 / ceilf(1.0 / maxf(raw, 0.01))) / dev

## Skala lokalna najbliższa `want`, ale dająca całkowitą liczbę pikseli ekranu na piksel rysunku (min. 1).
static func snap_scale(ci: CanvasItem, want: float) -> float:
	var dev := device_scale(ci)
	return maxf(1.0, roundf(want * dev)) / dev

## Przyciąga punkt (jednostki lokalne) do siatki pikseli ekranu.
static func snap(ci: CanvasItem, p: Vector2) -> Vector2:
	var dev := device_scale(ci)
	return (p * dev).round() / dev
