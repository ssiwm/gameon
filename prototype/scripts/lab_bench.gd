extends "res://scripts/station.gd"
## Pracownia elektroniki i próbek w kryjówce (znacznik „c", WORKSHOP_PLAN.md stanowisko 5, od 1.7.357): stół z aparaturą na górze, pod
## radiostacją. Gdy lokalny gracz stoi przy nim, HUD podpowiada [E]; naciśnięcie otwiera panel warsztatu w trybie „lab" (workshop_ui.gd) —
## badania części broni specjalnych za próbki z elit i bossów (Scrap.request_research), gotowe po następnej udanej misji.

const REACH_X := 32.0
const REACH_Y := 40.0
## Wyposażenie: stół z aparaturą, regał z częściami, skaner na stole — [nazwa przedmiotu HD, przesunięcie w kaflach]
const PROPS := [["table", 0.0], ["shelf", 1.6], ["scanner", -0.2]]   ## zapas, gdy brak modeli 3D stanowiska
## Modele 3D stanowiska (view3d.gd, grupa „station_props”; źródła: Meshy — stół z aparaturą i gablota z preparatami, Poly Haven CC0 —
## taboret; `tools/prep_items3d.py`): [model z art/items3d/, przesunięcie x w pikselach świata, głębia z w m]. Na lewo od znacznika stoi
## filar piętra (ok. 32–40 px), na prawo krzesło dekoracji (ok. 50 px): stół tuż na prawo od znacznika (gracz przy [E] go nie zasłania),
## gablota między filarem a znacznikiem — oba w kręgu lampy.
const MODELS := [["lab_desk", 14.0, -1.0], ["specimen_case", -17.0, -1.25], ["stool_metal", 9.0, -0.45]]
const MODEL_CHECK := "res://art/items3d/lab_desk.glb"

func _init() -> void:
	mode = "lab"
	group = "lab_bench"
	reach = Vector2(REACH_X, REACH_Y)
	models = MODELS
	model_check = MODEL_CHECK
	props = PROPS

## Uśpione stanowisko (HUB_LAYOUT_PLAN.md E4): pracownia bez próbek, badań i części — [E] nic nie robi, a widok 3D gasi lampę nad nim, nakrywa je plandeką
## i przygasza tabliczkę (view3d.gd `_sync_dormant`).
func dormant() -> bool:
	return not Scrap.lab_open()

## Podpowiedź paska akcji, gdy laboratorium jest celem [E] (hud.gd czyta ją od celu arbitra, INTERACT_PLAN.md I2): tekst, postęp, kolor.
func interact_hint(_me: Node2D) -> Dictionary:
	var k := Actions.key("interact")
	if Scrap.geodes > 0:                                       # geody z żyły (DIG_LOOT_PLAN.md K4): otwiera się je w karcie pracowni
		return {"text": tr("[%s]  Lab  ·  %d geodes to crack open") % [k, Scrap.geodes], "col": UiTheme.ACCENT}
	if Scrap.has_lab_weapon():
		return {"text": tr("[%s]  Lab  ·  %d samples  ·  research for special weapons") % [k, Scrap.samples], "col": UiTheme.ACCENT}
	return {"text": tr("[%s]  Lab  ·  %d samples  ·  buy a special weapon at the workshop first") % [k, Scrap.samples], "col": UiTheme.ACCENT}
