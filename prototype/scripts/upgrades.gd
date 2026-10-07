extends RefCounted
## Ulepszenia broni (GDD §6.4, złom faza C): 3 poziomy na broń, kupowane w warsztacie. Poziomy są wspólne dla drużyny
## (scrap.gd je replikuje i zapisuje), a Weapons.def() zwraca definicję z naniesionymi modyfikatorami — więc cała gra
## (kontroler, pociski, HUD, karty stojaków) czyta ulepszone statystyki bez żadnych zmian po swojej stronie.
##
## Modyfikator: [pole WeaponDef, "mul"|"add", wartość]. Pola całkowite (mag, pierce, rezerwa) zostają całkowite.
## Poziomy kumulują się: poziom 2 = modyfikatory poziomu 1 + 2.

const MAX_LEVEL := 3
const COSTS := [60, 120, 220]            ## cena poziomu 1, 2, 3 (taka sama dla każdej broni)

## klucz broni (weapons.gd) → trzy poziomy {name, desc, mods}
const TIERS := {
	"m83": [
		{"name": "Extended magazine", "desc": "+10 rounds per magazine, bigger reserve", "mods": [["mag", "add", 10], ["reserve_max", "add", 30]]},
		{"name": "Tuned action", "desc": "+15% damage, 15% faster reload", "mods": [["damage", "mul", 1.15], ["reload_time", "mul", 0.85]]},
		{"name": "Suppressor", "desc": "Much quieter: noise −40% / −30%", "mods": [["n_min", "mul", 0.6], ["n_max", "mul", 0.7]]},
	],
	"p64": [
		{"name": "Extended magazine", "desc": "+4 rounds per magazine", "mods": [["mag", "add", 4]]},
		{"name": "Match barrel", "desc": "+20% damage", "mods": [["damage", "mul", 1.2]]},
		{"name": "Suppressor", "desc": "Quieter: noise −30%", "mods": [["n_min", "mul", 0.7], ["n_max", "mul", 0.7]]},
	],
	"spread12": [
		{"name": "Shell pouch", "desc": "+6 shells per magazine, bigger reserve", "mods": [["mag", "add", 6], ["reserve_max", "add", 24]]},
		{"name": "Choke", "desc": "Tighter spread (−20%), +15% damage", "mods": [["spread_deg", "mul", 0.8], ["damage", "mul", 1.15]]},
		{"name": "Long barrel", "desc": "+25% range, damage holds up further out", "mods": [["range_px", "mul", 1.25], ["falloff_start", "mul", 1.3]]},
	],
	"srut8": [
		{"name": "Shell pouch", "desc": "+4 shells per magazine, bigger reserve", "mods": [["mag", "add", 4], ["reserve_max", "add", 16]]},
		{"name": "Hair trigger", "desc": "+15% damage, 12% faster cycling", "mods": [["damage", "mul", 1.15], ["cooldown", "mul", 0.88]]},
		{"name": "Baffled muzzle", "desc": "Quieter (−25%), longer stun", "mods": [["n_min", "mul", 0.75], ["n_max", "mul", 0.75], ["stun", "add", 0.15]]},
	],
	"lr7": [
		{"name": "Extended cell", "desc": "+20 charge per cell, bigger reserve", "mods": [["mag", "add", 20], ["reserve_max", "add", 60]]},
		{"name": "Overdrive coil", "desc": "+20% beam damage", "mods": [["damage", "mul", 1.2]]},
		{"name": "Focusing lens", "desc": "The beam pierces one more target", "mods": [["pierce", "add", 1]]},
	],
	"hkm9": [
		{"name": "Extended tank", "desc": "+20 fuel per tank, bigger reserve", "mods": [["mag", "add", 20], ["reserve_max", "add", 60]]},
		{"name": "Hot mix", "desc": "+25% damage, burns 30% longer", "mods": [["damage", "mul", 1.25], ["ignite", "mul", 1.3]]},
		{"name": "Long nozzle", "desc": "+30% flame range", "mods": [["range_px", "mul", 1.3]]},
	],
}

static func has_tiers(key: String) -> bool:
	return TIERS.has(key)

static func tier(key: String, level: int) -> Dictionary:
	if not TIERS.has(key) or level < 1 or level > MAX_LEVEL:
		return {}
	return (TIERS[key] as Array)[level - 1]

## Nakłada modyfikatory poziomów 1..level na świeżo zbudowaną definicję.
static func apply(d: RefCounted, level: int) -> void:
	for lv in range(1, mini(level, MAX_LEVEL) + 1):
		var t := tier(String(d.key), lv)
		for m in t.get("mods", []):
			var cur: Variant = d.get(String(m[0]))
			var out: float = float(cur) * float(m[2]) if String(m[1]) == "mul" else float(cur) + float(m[2])
			d.set(String(m[0]), int(roundf(out)) if typeof(cur) == TYPE_INT else out)
