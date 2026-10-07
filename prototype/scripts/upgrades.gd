extends RefCounted
## Ulepszenia broni (GDD §6.4, złom faza C): 3 poziomy na broń, kupowane w warsztacie. Poziomy są wspólne dla drużyny
## (scrap.gd je replikuje i zapisuje), a Weapons.def() zwraca definicję z naniesionymi modyfikatorami — więc cała gra
## (kontroler, pociski, HUD, karty stojaków) czyta ulepszone statystyki bez żadnych zmian po swojej stronie.
##
## Modyfikator: [pole WeaponDef, "mul"|"add", wartość]. Pola całkowite (mag, pierce, rezerwa) zostają całkowite.
## Poziomy kumulują się: poziom 2 = modyfikatory poziomu 1 + 2.

const MAX_LEVEL := 3
const COSTS := [60, 120, 220]            ## bazowa cena poziomu 1, 2, 3 — mnożona przez klasę broni (COST_MULT), patrz cost()
## Mnożnik ceny wg klasy broni: lekkie i białe tańsze, ciężkie (wybuchowe, szyna, kusza) droższe. Brak wpisu = 1,0.
const COST_MULT := {
	"p64": 0.8, "maczeta": 0.8, "kilof": 0.8,
	"srut8": 1.2, "lr7": 1.2, "hkm9": 1.2, "sokol6": 1.3,
	"gniew4": 1.5, "ciegno6": 1.5, "widmo1": 1.7,
}

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
		{"name": "Incendiary shells", "desc": "Every pellet sets the target on fire (2 s)", "mods": [["ignite", "add", 2.0]]},
	],
	"srut8": [
		{"name": "Shell pouch", "desc": "+4 shells per magazine, bigger reserve", "mods": [["mag", "add", 4], ["reserve_max", "add", 16]]},
		{"name": "Hair trigger", "desc": "+15% damage, 12% faster cycling", "mods": [["damage", "mul", 1.15], ["cooldown", "mul", 0.88]]},
		{"name": "Concussion shells", "desc": "Stun up to 1.5 s, +30% knock-back", "mods": [["stun", "add", 1.0], ["knock", "mul", 1.3]]},
	],
	"lr7": [
		{"name": "Extended cell", "desc": "+20 charge per cell, bigger reserve", "mods": [["mag", "add", 20], ["reserve_max", "add", 40]]},
		{"name": "Overdrive coil", "desc": "+20% beam damage", "mods": [["damage", "mul", 1.2]]},
		{"name": "Focusing lens", "desc": "The beam pierces one more target", "mods": [["pierce", "add", 1]]},
	],
	"hkm9": [
		{"name": "Extended tank", "desc": "+20 fuel per tank, bigger reserve", "mods": [["mag", "add", 20], ["reserve_max", "add", 60]]},
		{"name": "Hot mix", "desc": "+25% damage, burns 30% longer", "mods": [["damage", "mul", 1.25], ["ignite", "mul", 1.3]]},
		{"name": "Long nozzle", "desc": "+30% flame range", "mods": [["range_px", "mul", 1.3]]},
	],
	"gniew4": [
		{"name": "Bandolier", "desc": "+2 grenades per magazine, bigger reserve", "mods": [["mag", "add", 2], ["reserve_max", "add", 12]]},
		{"name": "Heavy warhead", "desc": "+25% blast damage, +12% radius", "mods": [["blast_damage", "mul", 1.25], ["blast_radius", "mul", 1.12]]},
		{"name": "Cluster warheads", "desc": "Two bomblets scatter after the blast (half damage, no extra noise)", "mods": [["cluster", "add", 2]]},
	],
	"sokol6": [
		{"name": "Extended belt", "desc": "+20 rockets per belt, bigger reserve", "mods": [["mag", "add", 20], ["reserve_max", "add", 60]]},
		{"name": "Sharper seeker", "desc": "+40% turn rate, +30% lock range, +15% damage", "mods": [["homing", "mul", 1.4], ["homing_range", "mul", 1.3], ["damage", "mul", 1.15]]},
		{"name": "Triple salvo", "desc": "Each trigger pull launches three rockets for two rounds (slower rate)", "mods": [["pellets", "add", 2], ["spread_deg", "add", 8.0], ["ammo_per_shot", "add", 1], ["damage", "mul", 0.8], ["cooldown", "mul", 1.5]]},
	],
	"widmo1": [
		{"name": "Extended capacitor", "desc": "+2 rounds per magazine, bigger reserve", "mods": [["mag", "add", 2], ["reserve_max", "add", 10]]},
		{"name": "Fast capacitor", "desc": "Charges 30% faster, 15% faster reload", "mods": [["charge_time", "mul", 0.7], ["reload_time", "mul", 0.85]]},
		{"name": "Armor-piercing slug", "desc": "The shot passes through one layer of wall", "mods": [["wall_pierce", "add", 24.0]]},
	],
	"ciegno6": [
		{"name": "Twin bolt", "desc": "Two bolts in the magazine", "mods": [["mag", "add", 1], ["reserve_max", "add", 2]]},
		{"name": "Waxed quiver", "desc": "Bigger reserve, 20% faster reload", "mods": [["reserve_max", "add", 6], ["reload_time", "mul", 0.8]]},
		{"name": "Barbed tether", "desc": "Pierces one more enemy, +20% damage; a line yanks hit enemies toward you", "mods": [["pierce", "add", 1], ["stun", "add", 0.4], ["damage", "mul", 1.2], ["pull", "add", 260.0]]},
	],
	"maczeta": [
		{"name": "Honed edge", "desc": "+20% damage", "mods": [["damage", "mul", 1.2]]},
		{"name": "Wide swing", "desc": "+50% arc, +6 px reach", "mods": [["arc_deg", "mul", 1.5], ["reach", "add", 6.0]]},
		{"name": "Executioner", "desc": "Kills any enemy below 35% HP outright", "mods": [["execute_frac", "add", 0.35]]},
	],
	"kilof": [
		{"name": "Sharpened pick", "desc": "+15% damage, 12% faster swing", "mods": [["damage", "mul", 1.15], ["cooldown", "mul", 0.88]]},
		{"name": "Heavy head", "desc": "+0.6 s stun, +30% knock-back", "mods": [["stun", "add", 0.6], ["knock", "mul", 1.3]]},
		{"name": "Seismic head", "desc": "A wider arc (+60%) and a longer stun (+0.8 s)", "mods": [["arc_deg", "mul", 1.6], ["stun", "add", 0.8]]},
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

## Cena poziomu `level` (1..3) broni `key`: baza × mnożnik klasy, zaokrąglona do 5.
static func cost(key: String, level: int) -> int:
	var base := float(COSTS[clampi(level, 1, MAX_LEVEL) - 1])
	return int(roundf(base * float(COST_MULT.get(key, 1.0)) / 5.0)) * 5

## Sprawdza tabelę: każdy klucz to istniejąca broń, każdy modyfikator wskazuje istniejące pole, trzy poziomy na broń. Wołane przez --weapontest.
static func validate(defs: Array) -> Array:
	var errs: Array = []
	var keys := {}
	for d in defs:
		keys[String(d.key)] = d
	for k in TIERS:
		if not keys.has(k):
			errs.append("ulepszenia: nieznana broń '%s'" % k)
			continue
		var tiers: Array = TIERS[k]
		if tiers.size() != MAX_LEVEL:
			errs.append("ulepszenia: %s ma %d poziomów (oczekiwano %d)" % [k, tiers.size(), MAX_LEVEL])
		for t in tiers:
			for m in t.get("mods", []):
				if not (String(m[0]) in keys[k]):
					errs.append("ulepszenia: %s / %s — nieznane pole '%s'" % [k, t.get("name", "?"), m[0]])
	return errs
