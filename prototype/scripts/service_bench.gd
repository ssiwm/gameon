extends "res://scripts/station.gd"
## Stół konserwacji w kryjówce (znacznik „j", WORKSHOP_PLAN.md stanowisko 2, od 1.7.350): stół z taboretem obok ławy warsztatu. Gdy lokalny
## gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „service" (workshop_ui.gd) — czyszczenie broni
## (rozłożonej na ławie 3D) i wymiana części eksploatacyjnych: lufy i sprężyn (Profile.WEAR_PARTS, Scrap.SERVICE_COST).

const REACH_X := 18.0                   ## węższy niż ława (44 px) — stoją 4 kafle od siebie i zasięgi nie mogą się nakładać
const REACH_Y := 40.0
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół rusznikarza z rozłożonym karabinem i szafka na drobne
## części, Poly Haven CC0 — taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m].
## Na lewo od znacznika wisi tablica wyników, na prawo (od ok. 42 px) stoi ława: stół i szafka mieszczą się między nimi, stół tuż na
## prawo od znacznika (gracz przy [E] go nie zasłania). Bez modeli: stół i taboret z przedmiotów HD.
const MODELS := [["clean_bench", 15.0, -1.0], ["parts_cabinet", 33.0, -1.2], ["stool_metal", 7.0, -0.45]]
const MODEL_CHECK := "res://art/items3d/clean_bench.glb"

func _init() -> void:
	mode = "service"
	group = "service_bench"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = [["table", 0.0], ["stool", 1.4]]   # zapas, gdy brak modeli 3D
	key_box = Rect2(-14.0, -24.0, 28.0, 24.0)

## Uśpione stanowisko (HUB_LAYOUT_PLAN.md E4): zużycie broni wyłączone — [E] nic nie robi, a widok 3D gasi lampę nad nim, nakrywa je plandeką
## i przygasza tabliczkę (view3d.gd `_sync_dormant`).
func dormant() -> bool:
	return Settings.reliability_mult() <= 0.0

## Podpowiedź paska akcji, gdy stół konserwacji jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	return {"text": tr("[%s]  Maintenance  ·  clean, barrels, springs") % Actions.key("interact"), "col": UiTheme.ACCENT}
