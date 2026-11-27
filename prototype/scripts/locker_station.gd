extends "res://scripts/station.gd"
## Szafki osobiste w kryjówce (znacznik „p", WORKSHOP_PLAN.md stanowisko 7, od 1.7.349): rząd metalowych szafek w świetlicy. Gdy lokalny gracz
## stoi przy nich, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „locker" (workshop_ui.gd) — perki i wygląd postaci,
## które wcześniej siedziały w zakładkach ławy. Ława zajmuje się już tylko bronią i zaopatrzeniem.

const REACH_X := 40.0
const REACH_Y := 40.0
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — rząd trzech szafek z otwartą środkową (kurtka, hełm, zdjęcia,
## buty) i ławka szatniowa; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Szafki stoją trochę na prawo od znacznika, żeby gracz przy [E] nie zasłaniał otwartej, ławka po lewej — dalej polowe łóżko i krzesło
## świetlicy. Bez modeli: trzy szafki z przedmiotów HD (`props`).
const MODELS := [["locker_row", 8.0, -1.1], ["locker_bench", -15.0, -0.6]]
const MODEL_CHECK := "res://art/items3d/locker_row.glb"

func _init() -> void:
	mode = "locker"
	group = "locker_station"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = [["locker", -0.9], ["locker", 0.0], ["locker", 0.9]]   # zapas, gdy brak modeli 3D
	key_box = Rect2(-16.0, -36.0, 32.0, 36.0)

## Podpowiedź paska akcji, gdy szafka jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Locker  ·  perks and look") % Actions.key("interact"), "col": UiTheme.ACCENT}
