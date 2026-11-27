extends "res://scripts/station.gd"
## Prasa elaboracyjna w kryjówce (znacznik „x", WORKSHOP_PLAN.md stanowisko 3, od 1.7.354): stół z prasą i skrzynkami amunicji w magazynie
## na dole. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „press" (workshop_ui.gd) —
## zamówienia partii amunicji specjalnej (Scrap.request_order), gotowych po następnej udanej misji. Ława nie sprzedaje już amunicji.

const REACH_X := 32.0
const REACH_Y := 40.0
## Wyposażenie: stół (prasa, wagi) i skrzynki z łuskami obok — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["ammo", 1.3], ["ammo", 1.9], ["crate", -1.6]]   ## zapas, gdy brak modeli 3D stanowiska
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół elaboracyjny z prasą i regał z amunicją, Poly Haven CC0 —
## taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m]. Skrzynie magazynu stoją
## 32–48 px na prawo od znacznika (HUB_PROPS): stół tuż przed nimi (gracz przy znaczniku go nie zasłania), regał w lewo.
const MODELS := [["reload_bench", 12.0, -1.0], ["ammo_shelf", -15.0, -1.3], ["stool_metal", 6.0, -0.5]]
const MODEL_CHECK := "res://art/items3d/reload_bench.glb"

func _init() -> void:
	mode = "press"
	group = "press_bench"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = PROPS

## Podpowiedź paska akcji, gdy prasa jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Reloading press  ·  %d / %d batches ordered") % [Actions.key("interact"), Scrap.orders.size(), Scrap.PRESS_SLOTS], "col": UiTheme.ACCENT}
