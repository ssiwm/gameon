extends RefCounted
## Amunicja według kalibru (GUNSMITH_PLAN.md §3, etap 1, od 1.7.317) — dane i reguły, bez stanu.
##
## Kaliber (`WeaponDef.caliber`) łączy bronie, które strzelają tym samym nabojem: SPREAD-12 i PELLET-8 biorą 12/70 z jednego zapasu
## drużyny. Broń bez kalibru ma zapas tylko dla siebie (jak dawniej). Każdy kaliber ma typy naboi; indeks 0 to nabój zwykły
## (zapas startowy misji, łup z wrogów), dalsze to amunicja specjalna — kupowana w warsztacie (zakładka SUPPLIES, wpisy `ammo_*`
## w throwables.gd), trzymana we wspólnym zapasie zaopatrzenia (Arsenal.stock, liczona w nabojach) i zapisywana jak granaty.
##
## Typ naboju zmienia definicję broni tak samo jak ulepszenie: modyfikatory [pole, "mul"|"add"|"set", wartość]. Kilka reguł nie da
## się zapisać jednym modyfikatorem — opisują je flagi: `slug` (śrut → jeden pocisk), `subsonic` (bez trzasku kuli; z tłumikiem
## znacznie ciszej). Gracz wybiera typ klawiszem [Z]; wchodzi on z NASTĘPNYM magazynkiem (wymiana od razu przeładowuje broń).

## Prędkość dźwięku w skali prędkości kul gry (px/s ≈ m/s × 3,4) — taka sama jak Weapons.SOUND_PX.
const SOUND_PX := 1165.0
## Mnożnik hałasu naboju poddźwiękowego: bez tłumika zostaje huk wylotowy, z tłumikiem znika też trzask kuli.
const SUBSONIC_NOISE := 0.85
const SUBSONIC_SUPPRESSED := 0.5

## Kolejność kalibrów (indeks wchodzi do klucza zapasu, patrz `pool_key`).
const ORDER := ["762", "918", "12g"]

const CALIBERS := {
	"762": {"name": "7.62×39"},
	"918": {"name": "9×18"},
	"12g": {"name": "12/70"},
}

## kaliber → typy; `kind` = wpis zaopatrzenia (throwables.gd), z którego bierze się amunicję specjalną.
const TYPES := {
	"762": [
		{"id": "ps", "short": "PS", "name": "PS ball", "mods": [],
			"note": "Standard steel-core ball round. Supersonic: the bullet cracks."},
		{"id": "us", "short": "US", "name": "US subsonic", "kind": "ammo_us", "subsonic": true,
			"mods": [["speed", "mul", 0.42], ["damage", "mul", 0.75], ["falloff_start", "mul", 0.6], ["cam_kick", "mul", 0.7]],
			"note": "Heavy subsonic bullet. Weaker and slower, no supersonic crack: a little quieter on its own, very quiet with a suppressor."},
		{"id": "bz", "short": "BZ", "name": "BZ armour-piercing incendiary", "kind": "ammo_bz",
			"mods": [["armor_pen", "add", 0.7], ["ignite", "add", 1.0], ["pierce", "add", 1]],
			"note": "Hardened core with an incendiary charge: ignores most armour, passes through one body, sets the target alight briefly."},
	],
	"918": [
		{"id": "pm", "short": "PM", "name": "9×18 ball", "mods": [], "subsonic": true,
			"note": "Pistol round, subsonic by nature (≈315 m/s)."},
	],
	"12g": [
		{"id": "buck", "short": "BUCK", "name": "Buckshot", "mods": [],
			"note": "Standard buckshot: a cone of pellets, deadly up close, weak at range."},
		{"id": "slug", "short": "SLUG", "name": "Brenneke slug", "kind": "ammo_slug", "slug": true,
			"mods": [["knock", "mul", 1.5], ["pierce", "add", 1], ["armor_pen", "add", 0.3], ["cam_kick", "mul", 1.2]],
			"note": "One heavy lead slug instead of a pellet cone: no spread, twice the range, passes through one body. You have to aim."},
		{"id": "inc", "short": "INC", "name": "Incendiary shells", "kind": "ammo_inc",
			"mods": [["ignite", "add", 2.0], ["damage", "mul", 0.7]],
			"note": "Burning pellets set every target hit on fire for 2 s. Weaker pellets."},
		{"id": "rub", "short": "RUB", "name": "Rubber shells", "kind": "ammo_rub",
			"mods": [["damage", "mul", 0.25], ["stun", "add", 1.0], ["knock", "mul", 1.3], ["crit_mult", "set", 1.0]],
			"note": "Less-lethal rubber balls (like the KS-23 Volna-R): stun up to 1.5 s and knock back, barely wound."},
	],
}

static func is_caliber(cal: String) -> bool:
	return CALIBERS.has(cal)

static func types_of(cal: String) -> Array:
	return TYPES.get(cal, []) as Array

## Ile typów ma kaliber (broń bez kalibru: jeden — zwykły).
static func count(cal: String) -> int:
	return maxi(1, types_of(cal).size())

static func type_of(cal: String, t: int) -> Dictionary:
	var ts := types_of(cal)
	return ts[t] if t >= 0 and t < ts.size() else {}

static func valid(cal: String, t: int) -> bool:
	return t == 0 or (t > 0 and t < types_of(cal).size())

static func short_of(cal: String, t: int) -> String:
	return String(type_of(cal, t).get("short", ""))

static func name_of(cal: String, t: int) -> String:
	return String(type_of(cal, t).get("name", ""))

## Wpis zaopatrzenia z amunicją specjalną typu `t` ("" = nabój zwykły, z zapasu misji).
static func kind_of(cal: String, t: int) -> String:
	return String(type_of(cal, t).get("kind", "")) if t > 0 else ""

## Odwrotnie: kaliber i typ dla wpisu zaopatrzenia `ammo_*` (pusty słownik, gdy to nie amunicja).
static func from_kind(kind: String) -> Dictionary:
	for cal in ORDER:
		var ts := types_of(String(cal))
		for t in ts.size():
			if String(ts[t].get("kind", "")) == kind:
				return {"cal": cal, "t": t}
	return {}

## Klucz zapasu naboi zwykłych: broń z kalibrem dzieli go z innymi bronią tego kalibru (100 + indeks kalibru), broń bez kalibru
## ma klucz = własne id (jak przed 1.7.317 — zapisy i testy liczone po id broni dalej działają).
static func pool_key(w: int, cal: String) -> int:
	var i := ORDER.find(cal)
	return w if i < 0 else 100 + i

## Nakłada typ naboju `t` na świeżo zbudowaną definicję (po ulepszeniach). Typ 0 nic nie zmienia.
static func apply(d: RefCounted, t: int) -> void:
	d.set("ammo", t)
	if t <= 0:
		return
	var ty := type_of(String(d.caliber), t)
	if ty.is_empty():
		return
	if bool(ty.get("slug", false)) and int(d.pellets) > 1:
		# śrut → jeden pocisk: obrażenia ok. 85% całego snopa, bez rozrzutu śrutu, zasięg ×2, pełne obrażenia do połowy zasięgu
		d.set("damage", float(d.damage) * float(d.pellets) * 0.85)
		d.set("pellets", 1)
		d.set("spread_deg", 0.0)
		d.set("jitter_deg", float(d.jitter_deg) * 0.6)
		d.set("range_px", float(d.range_px) * 2.0)
		d.set("falloff_start", float(d.range_px) * 0.5)
		d.set("falloff_min", 0.6)
	for m in ty.get("mods", []):
		var cur: Variant = d.get(String(m[0]))
		var out: float
		match String(m[1]):
			"mul":
				out = float(cur) * float(m[2])
			"set":
				out = float(m[2])
			_:
				out = float(cur) + float(m[2])
		d.set(String(m[0]), int(roundf(out)) if typeof(cur) == TYPE_INT else out)
	if bool(ty.get("subsonic", false)):
		var k := SUBSONIC_SUPPRESSED if float(d.suppressor) > 0.0 else SUBSONIC_NOISE
		d.set("n_min", float(d.n_min) * k)
		d.set("n_max", float(d.n_max) * k)

## Sprawdza tabele: kalibry z bronią, pola modyfikatorów istnieją, amunicja specjalna ma wpis zaopatrzenia, poddźwiękowa leci
## wolniej niż dźwięk. Wołane przez --weapontest.
static func validate(defs: Array, shop: Dictionary) -> Array:
	var errs: Array = []
	var used := {}
	for d in defs:
		var cal := String(d.caliber)
		if cal == "":
			continue
		if not is_caliber(cal):
			errs.append("%s: nieznany kaliber '%s'" % [d.key, cal])
			continue
		used[cal] = true
	for cal in ORDER:
		if not used.has(cal):
			errs.append("kaliber %s bez broni" % cal)
		var ts := types_of(String(cal))
		for t in ts.size():
			var ty: Dictionary = ts[t]
			for m in ty.get("mods", []):
				if not (String(m[0]) in defs[0]):
					errs.append("%s/%s: nieznane pole '%s'" % [cal, ty["id"], m[0]])
			if t > 0 and not shop.has(String(ty.get("kind", ""))):
				errs.append("%s/%s: brak wpisu zaopatrzenia" % [cal, ty["id"]])
	return errs
