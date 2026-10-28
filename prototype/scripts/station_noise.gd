extends RefCounted
## Hałas na kartach stanowisk (STATION_CARDS_PLAN.md §5a): poziom Uwagi od ciszy po typowym użyciu, w tej samej skali co VU-metr w HUD
## (0–100). Liczony z danych gry i wygaszania NoiseMgr, nie wpisany ręcznie — `--workshoptest` porównuje go z NoiseMgr.
##   broń i amunicja — jeden magazynek ciągłym ogniem (`mag_level`), przedmiot rzucany / ładunek — jeden przedmiot (`item_noise`)
##   i ile naraz potrzeba do niepokoju (`count_to`). Bieg (0,5/s) nie przebija wygaszania, więc perki biegu nie dostają VU.

const Throwables := preload("res://scripts/throwables.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const DT := 1.0 / 60.0

## Uwaga po jednym magazynku `d` (WeaponDef po częściach i amunicji) ciągłym ogniem od ciszy: rozgrzanie jak w `Weapons.simulate_heat`,
## Uwaga spada przy tym o `NoiseMgr.DECAY_LOUD` na sekundę (strzelanie to aktywność). Broń bez magazynka (wiązka, biała) — 3 s ognia.
static func mag_level(d: RefCounted) -> float:
	var shots := int(d.mag) if int(d.mag) > 0 else -1
	var cool := maxf(0.02, float(d.cooldown))
	var seconds := 3.0 if shots < 0 else cool * float(shots)
	var heat := 0.0
	var cd := 0.0
	var t := 0.0
	var lvl := 0.0
	var fired := 0
	while t < seconds and (shots < 0 or fired < shots):
		heat = maxf(0.0, heat - float(d.heat_decay) * DT)
		lvl = maxf(0.0, lvl - NoiseMgr.DECAY_LOUD * DT)
		cd -= DT
		if cd <= 0.0:
			lvl += float(d.noise(heat))
			heat = minf(1.0, heat + float(d.heat_gain))
			cd += cool
			fired += 1
		t += DT
	return minf(lvl, 100.0)

## Uwaga z jednego przedmiotu zaopatrzenia `kind` (wybuch, pole ognia, chmura) — 0, gdy przedmiot nie hałasuje albo jest używany w czasie.
static func item_noise(kind: String) -> float:
	var k: Dictionary = Throwables.KINDS.get(kind, {})
	match String(k.get("mode", "")):
		"throw", "place":
			return float(k.get("noise", NoiseMgr.N_GRENADE))
	return 0.0

## Ile takich zdarzeń naraz wystarczy, żeby przejść próg `threshold` (0 — nigdy).
static func count_to(amount: float, threshold: float) -> int:
	return 0 if amount <= 0.0 else ceili(threshold / amount)

## Progi skali dla `VuMeter.ticks`, takie same jak w HUD.
static func ticks() -> Array:
	return [
		[NoiseMgr.SLEEP_THRESHOLD / 100.0, Color(1, 1, 1, 0.35)],
		[NoiseMgr.UNEASY_THRESHOLD / 100.0, UiTheme.ACCENT],
		[NoiseMgr.AWAKE_THRESHOLD / 100.0, UiTheme.DANGER],
	]
