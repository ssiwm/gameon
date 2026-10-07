extends RefCounted
## Katalog perków (GDD §10.2) — dane bez logiki. Perk odblokowuje się poziomem profilu (profile.gd), zakłada się w kryjówce
## (2 sloty: od poziomu 2 i 4). Skutki podpina faza B3 (hooki w player.gd, voice.gd, upgrades.gd, scanner_view.gd); tu tylko opisy
## i progi, żeby ekran w kryjówce (B2) i testy miały jedno źródło prawdy. Wartości liczbowe w `params` czytają hooki.

const ORDER := ["quiet_steps", "blood_flow", "wide_arm", "smith", "cold_blood", "scout", "second_chance", "veteran"]

const PERKS := {
	"quiet_steps": {
		"name": "Quiet steps", "level": 2, "params": {"run_noise_mult": 0.5},
		"desc": "Running makes half the noise (0.25 instead of 0.5 per second).",
	},
	"blood_flow": {
		"name": "Bloodflow", "level": 2, "params": {"revive_time": 2.5},
		"desc": "You lift a downed teammate faster: 2.5 s instead of 4 s.",
	},
	"wide_arm": {
		"name": "Wide arm", "level": 2, "params": {"throw_mult": 1.3},
		"desc": "Grenades and other thrown items fly 30% farther.",
	},
	"smith": {
		"name": "Smith", "level": 2, "params": {"upgrade_cost_mult": 0.8},
		"desc": "Weapon upgrades you buy cost 20% less.",
	},
	"cold_blood": {
		"name": "Cold blood", "level": 4, "params": {"scream_cap": 10.0},
		"desc": "Your scream into the microphone costs at most +10 Attention.",
	},
	"scout": {
		"name": "Scout", "level": 4, "params": {"scan_stalker_range": 160.0},
		"desc": "Your scanner shows the Stalker within 10 m.",
	},
	"second_chance": {
		"name": "Second chance", "level": 4, "params": {"self_revive_after": 8.0},
		"desc": "Once per mission you get back up on your own after 8 s (1 heart).",
	},
	"veteran": {
		"name": "Veteran", "level": 6, "params": {"extra_hearts": 1},
		"desc": "One more heart.",
	},
}

static func is_valid(id: String) -> bool:
	return PERKS.has(id)

static func unlock_level(id: String) -> int:
	return int(PERKS[id]["level"]) if PERKS.has(id) else 99

static func display_name(id: String) -> String:
	return String(PERKS[id]["name"]) if PERKS.has(id) else id

static func param(id: String, key: String, fallback: float = 0.0) -> float:
	if not PERKS.has(id):
		return fallback
	return float((PERKS[id]["params"] as Dictionary).get(key, fallback))

## Perki, które odblokowuje dokładnie ten poziom (komunikat o awansie).
static func unlocked_at(level: int) -> Array:
	var out: Array = []
	for id in ORDER:
		if unlock_level(String(id)) == level:
			out.append(id)
	return out
