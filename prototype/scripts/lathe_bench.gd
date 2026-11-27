extends "res://scripts/station.gd"
## Tokarka i szlifierka w kryjówce (znacznik „d", WORKSHOP_PLAN.md stanowisko 6, od 1.7.358): warsztat mechaniczny w maszynowni na dole,
## obok generatora. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „lathe"
## (workshop_ui.gd) — wykonanie części ze schematów z pracowni (Scrap.request_machining, gotowe po udanej misji) i ostrzenie broni białej.

const REACH_X := 32.0
const REACH_Y := 40.0
## Wyposażenie: ława z imadłem i tokarką, skrzynka z prętami — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["workshop", 0.0], ["crate", -1.8]]       ## zapas, gdy brak modeli 3D stanowiska (skrzynka po lewej — po prawej generator)
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — tokarka i szlifierka, Poly Haven CC0 — wózek z imadłem, skrzynia
## z wiertarką stołową; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m]. Generator stoi
## 22 px na prawo od znacznika: tokarka (19,6 px) stoi tuż przed nim, reszta ciasno w lewo, żeby zmieścić się w kręgu lampy stanowiska.
const MODELS := [["lathe", 8.3, -1.0], ["lathe_cart", -10.7, -1.05], ["bench_grinder", -25.0, -0.85], ["drill_chest", -36.0, -1.1]]
const MODEL_CHECK := "res://art/items3d/lathe.glb"

func _init() -> void:
	mode = "lathe"
	group = "lathe_bench"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = PROPS

## Uśpione stanowisko (HUB_LAYOUT_PLAN.md E4): tokarka bez schematu i bez zużycia — [E] nic nie robi, a widok 3D gasi lampę nad nim, nakrywa je plandeką
## i przygasza tabliczkę (view3d.gd `_sync_dormant`).
func dormant() -> bool:
	return not Scrap.lathe_open()

## Podpowiedź paska akcji, gdy tokarka jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Lathe and grinder  ·  %d schematics") % [Actions.key("interact"), Scrap.schematics.size()], "col": UiTheme.ACCENT}
