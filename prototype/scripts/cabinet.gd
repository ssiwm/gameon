extends Node2D
## Gablota na broń w kryjówce (ARMORY_PLAN.md): znacznik „g" na mapie z `CABINET_SLOTS` > 0. W symulacji broń z gabloty to zwykłe przedmioty
## (pickup.gd ze static_display) rozstawione obok siebie na szerokości gabloty (SLOT_DX); wszystkie rzędy mają wspólny punkt interakcji.
## Zasięg [E], blokadę i zamianę broni rozstrzyga serwer.
## Obraz (korpus, ściana listwowa, haki, światło LED, drzwi) buduje view3d.gd z grupy „cabinets"; wybór broni w gablocie (↑ / ↓ w oględzinach)
## robi weapon_controller.gd. Przedmiot broni ma meta „cabinet" (numer gabloty), „slot" (rząd od góry) i „cab_x" (środek gabloty, px).

const WIDTH_PX := 21.0                ## szerokość gabloty w pikselach świata (1,7 m)
## przesunięcia przedmiotów broni od środka gabloty [px], w kolejności rzędów od góry (slot 0 wisi najwyżej)
const SLOT_DX := [-7.5, -2.5, 2.5, 7.5]

var index := 0                        ## numer gabloty od lewej (0, 1, …)
var slots := 4                        ## ile broni wisi w gablocie
var issued: Dictionary = {}           ## rząd → etykieta odbiorcy wspólnego egzemplarza

static func interaction_point(center: Vector2) -> Vector2:
	return center + Vector2(0, -8)

static func in_range(center: Vector2, hand: Vector2, radius: float) -> bool:
	return interaction_point(center).distance_to(hand) <= radius

func _ready() -> void:
	add_to_group("cabinets")
