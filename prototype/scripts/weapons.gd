extends RefCounted
## Tabela broni — jedno źródło prawdy dla rytmu strzału, obrażeń i HAŁASU
## (GDD §8.1 „Model rozgrzania lufy\", §23). Identyczna w trybie solo i sieciowym.
##
## Hałas strzału = lerp(n_min, n_max, heat), gdzie heat rośnie o heat_gain na
## strzał i spada o HEAT_DECAY/s. Krótka seria jest tania, ciągły ogień drogi.

const M83 := 0
const SPREAD12 := 1
const P64 := 2
const COUNT := 3

const HEAT_DECAY := 1.2

const DEFS := [
	{
		"name": "M-83", "auto": true, "cooldown": 0.12, "damage": 8.0,
		"pellets": 1, "spread_deg": 0.0, "jitter_deg": 1.2,
		"speed": 320.0, "life": 1.2,
		"n_min": 0.6, "n_max": 2.6, "heat_gain": 0.10,
		"sfx": "m83_shot", "sfx_count": 4, "sfx_pitch": 1.0, "sfx_vol": -7.0,
		"shake": 0.7, "kick": 0.0,
	},
	{
		"name": "SPREAD-12", "auto": false, "cooldown": 0.26, "damage": 7.0,
		"pellets": 5, "spread_deg": 14.0, "jitter_deg": 1.5,
		"speed": 300.0, "life": 0.45,
		"n_min": 3.5, "n_max": 5.0, "heat_gain": 0.40,
		"sfx": "m83_shot", "sfx_count": 4, "sfx_pitch": 0.62, "sfx_vol": -3.0,
		"shake": 2.4, "kick": 55.0,
	},
	{
		"name": "P-64", "auto": false, "cooldown": 0.20, "damage": 10.0,
		"pellets": 1, "spread_deg": 0.0, "jitter_deg": 0.6,
		"speed": 340.0, "life": 1.0,
		"n_min": 1.0, "n_max": 1.6, "heat_gain": 0.08,
		"sfx": "p64_shot", "sfx_count": 3, "sfx_pitch": 1.0, "sfx_vol": -8.0,
		"shake": 0.5, "kick": 0.0,
	},
]

static func def(id: int) -> Dictionary:
	return DEFS[clampi(id, 0, COUNT - 1)]

## Hałas strzału dla danego rozgrzania (0–1).
static func shot_noise(id: int, heat: float) -> float:
	var d := def(id)
	return lerpf(d["n_min"], d["n_max"], clampf(heat, 0.0, 1.0))
