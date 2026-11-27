extends "res://scripts/station.gd"
## Stół pirotechniczny w kryjówce (znacznik „z", WORKSHOP_PLAN.md stanowisko 4, od 1.7.355): stół między skrzyniami na dole, przy wojskowej
## skrzyni. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „pyro" (workshop_ui.gd) —
## granaty, miny, ładunki i naboje 40 mm oraz wybór długości zapalnika dla drużyny (Scrap.request_fuse). Ława zostawia sobie narzędzia.

const REACH_X := 32.0
const REACH_Y := 40.0
## Wyposażenie: stół z zapalnikami, skrzynki z korpusami granatów — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["crate", 1.5], ["crate", -1.5]]       ## zapas, gdy brak modeli 3D stanowiska
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół pirotechniczny z osłoną i szafa na materiały wybuchowe,
## Poly Haven CC0 — gaśnica i taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Wojskowa skrzynia magazynu stoi 16 px na lewo od znacznika, beczka 32 px na prawo (HUB_PROPS): stół między znacznikiem a beczką (gracz
## przy [E] go nie zasłania), szafa pod ścianą za skrzynią — dalej w lewo stoi już filar.
const MODELS := [["pyro_bench", 12.0, -1.0], ["expl_locker", -26.0, -1.35], ["pyro_ext", 24.0, -0.9], ["stool_metal", 8.0, -0.45]]
const MODEL_CHECK := "res://art/items3d/pyro_bench.glb"

func _init() -> void:
	mode = "pyro"
	group = "pyro_bench"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = PROPS

## Podpowiedź paska akcji, gdy stół pirotechniczny jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Pyrotechnics  ·  grenades, mines, fuses") % Actions.key("interact"), "col": UiTheme.ACCENT}
