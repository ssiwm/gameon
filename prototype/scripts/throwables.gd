extends RefCounted
## Zużywalne przedmioty ekwipunku (GDD §6.5–6.6, faza A1–A2): granaty, miny, ładunki i narzędzia drużynowe.
## Zapas jest WSPÓLNY dla drużyny (jak flary i ładunki Q), trzyma go Arsenal; przechodzi między misjami i sesjami (zapis u hosta),
## a kupuje się go w warsztacie (zakładka SUPPLIES, `price`) albo znajduje w skrzynkach z wrogów. Przed każdą misją dopełniany jest do zestawu `issue`. **lewy Alt** (macOS: lewy Cmd) używa wybranego przedmiotu, **X** zmienia wybór.
## Rodzaje użycia (`mode`):
##   throw — rzut łukiem (grenade.gd): odłamkowy, fosforowy, dymny
##   place — postawienie pod nogami (placed.gd): mina kierunkowa, ładunek wyburzeniowy
##   use   — narzędzie (przytrzymaj klawisz użycia przy celu / naciśnij): apteczka, defibrylator, skaner „Sowa” (player.gd `_gear_tick`)
## Nowy rodzaj = wpis w KINDS i ORDER plus obsługa w grenade.gd / placed.gd / arsenal.gd (`_use_server`).

const Actions := preload("res://scripts/actions.gd")

const ORDER := ["frag", "phos", "smoke", "mine", "charge", "medkit", "defib", "scanner", "cleankit"]
## Amunicja specjalna (ammo.gd, od 1.7.317): sklep i zapas jak przedmioty, ale `mode` = "ammo" — nie ma jej w wyborze [X], zapas liczy
## się w NABOJACH (`max`), a zakup dokłada pudełko (`box`). Broń bierze ją przy przeładowaniu, gdy gracz wybierze typ klawiszem [Z].
const AMMO_ORDER := ["ammo_us", "ammo_bz", "ammo_hot762", "ammo_slug", "ammo_inc", "ammo_rub", "ammo_mag12", "ammo_40buck", "ammo_40illum", "ammo_40smoke"]
## Stół pirotechniczny (WORKSHOP_PLAN.md W4b, od 1.7.355): długości zapalnika do wyboru dla drużyny (Scrap.fuses); środkowa = fabryczna `fuse`.
const FUSES := {"frag": [1.0, 1.8, 3.0], "phos": [0.8, 1.3, 2.5], "charge": [4.0, 8.0, 15.0]}

## Indeks fabrycznej długości zapalnika `kind` w FUSES.
static func fuse_default(kind: String) -> int:
	return maxi(0, (FUSES.get(kind, []) as Array).find(float(KINDS.get(kind, {}).get("fuse", 0.0))))

## Kolejność w zakładce SUPPLIES warsztatu.
const SHOP_ORDER := ORDER + AMMO_ORDER

const KINDS := {
	"frag": {
		"mode": "throw", "name": "FRAG", "full": "Fragmentation grenade", "issue": 1, "price": 100, "max": 4, "fuse": 1.8,
		"radius": 64.0, "damage": 90.0,                      # 4 m, 90 w środku (spadek do 50% na brzegu — Combat.BLAST_EDGE)
		"color": Color(0.5, 0.72, 0.4),
		"note": "Blast 4 m, 90 damage. Fuse 1.8 s. Hurts the squad too.",
	},
	"phos": {
		"mode": "throw", "name": "PHOS", "full": "Phosphorus grenade", "issue": 0, "price": 150, "max": 3, "fuse": 1.3,
		"field_life": 15.0, "field_patches": 3, "noise": 3.0,   # pole ognia 15 s (3 plamy obok siebie) — mur dla Trzosków, Ślepców i Skoczków
		"color": Color(1.0, 0.85, 0.5),
		"note": "A field of fire for 15 s. Burns enemies, blocks shy ones, does not hurt the squad.",
	},
	"smoke": {
		"mode": "throw", "name": "SMOKE", "full": "Smoke grenade", "issue": 0, "price": 80, "max": 3, "fuse": 1.0,
		"cloud_life": 12.0, "noise": 2.0,                      # chmura 12 s: wrogowie nie widzą przez nią celu (enemy.gd `_clear_line`)
		"color": Color(0.7, 0.72, 0.75),
		"note": "A cloud for 12 s. Enemies cannot see through it. Sound still carries.",
	},
	"mine": {
		"mode": "place", "name": "MINE", "full": "Directional mine", "issue": 0, "price": 140, "max": 3,
		"arm": 1.0, "range": 84.0, "half_deg": 38.0, "damage": 120.0, "noise": 10.0,
		"color": Color(0.9, 0.35, 0.3),
		"note": "Placed facing your aim. Arms in 1 s, fires 120 damage in a 76° cone at the first awake enemy. Spares the squad.",
	},
	"charge": {
		"mode": "place", "name": "CHARGE", "full": "Demolition charge", "issue": 0, "price": 250, "max": 2, "fuse": 4.0,
		"radius": 80.0, "damage": 150.0, "noise": 20.0,
		"color": Color(1.0, 0.7, 0.25),
		"note": "Fuse 4 s, blast 5 m, 150 damage. Breaks brick walls, wounds a boss. Loudest item. Hurts the squad.",
	},
	"medkit": {
		"mode": "use", "name": "MEDKIT", "full": "Medkit", "issue": 1, "price": 70, "max": 3, "time": 5.0, "range": 36.0,
		"color": Color(0.4, 1.0, 0.5),
		"note": "Hold the item key (L-Alt / L-Cmd) for 5 s next to a wounded teammate (or yourself): +1 heart. Damage interrupts it.",
	},
	"cleankit": {                       # zestaw do czyszczenia broni (GUNSMITH_PLAN §6.3, od 1.7.329): stan trzymanej broni +40 %, usuwa zacięcie
		"mode": "use", "name": "CLEAN KIT", "full": "Cleaning kit", "issue": 1, "price": 50, "max": 2, "time": 6.0, "restore": 40.0,
		"color": Color(0.85, 0.72, 0.42),
		"note": "Hold the item key (L-Alt / L-Cmd) for 6 s: strip and clean the gun in your hands — +40% condition and any jam cleared. Quiet; damage interrupts it.",
	},
	"defib": {
		"mode": "use", "name": "DEFIB", "full": "Defibrillator", "issue": 1, "price": 0, "max": 1, "time": 1.5, "range": 160.0,
		"color": Color(0.5, 0.85, 1.0),
		"note": "Hold the item key (L-Alt / L-Cmd) for 1.5 s: revives a downed teammate up to 10 m away in line of sight. One per mission.",
	},
	"ammo_us": {
		"mode": "ammo", "name": "7.62 US", "full": "7.62×39 US subsonic", "issue": 0, "price": 60, "max": 120, "box": 30,
		"color": Color(0.55, 0.75, 0.95),
		"note": "Box of 30 subsonic rounds for the M-83. Slower and weaker, no supersonic crack — with the suppressor the shot barely carries.",
	},
	"ammo_bz": {
		"mode": "ammo", "name": "7.62 BZ", "full": "7.62×39 BZ armour-piercing incendiary", "issue": 0, "price": 120, "max": 90, "box": 30,
		"color": Color(0.95, 0.4, 0.3),
		"note": "Box of 30 rounds for the M-83: ignore most armour, pass through one body, set the target alight.",
	},
	"ammo_hot762": {                    # prasa elaboracyjna (W4, od 1.7.354) — tylko z prasy, jak cała amunicja specjalna
		"mode": "ammo", "name": "7.62 HOT", "full": "7.62×39 hot load", "issue": 0, "price": 100, "max": 90, "box": 30,
		"color": Color(1.0, 0.62, 0.25),
		"note": "Batch of 30 hot-loaded rounds for the M-83: +12% damage and speed, goes through more — but the gun wears twice as fast.",
	},
	"ammo_mag12": {
		"mode": "ammo", "name": "12 MAG", "full": "12/70 magnum buckshot", "issue": 0, "price": 60, "max": 40, "box": 10,
		"color": Color(0.9, 0.5, 0.35),
		"note": "Batch of 10 heavy shells for both shotguns: +15% per pellet, a brutal kick, twice the wear on the gun.",
	},
	"ammo_slug": {
		"mode": "ammo", "name": "12 SLUG", "full": "12/70 Brenneke slug", "issue": 0, "price": 50, "max": 40, "box": 10,
		"color": Color(0.8, 0.8, 0.85),
		"note": "Box of 10 slugs for both shotguns: one heavy projectile, no spread, twice the range.",
	},
	"ammo_inc": {
		"mode": "ammo", "name": "12 INC", "full": "12/70 incendiary shells", "issue": 0, "price": 60, "max": 30, "box": 10,
		"color": Color(1.0, 0.55, 0.2),
		"note": "Box of 10 incendiary shells for both shotguns: every pellet sets the target on fire for 2 s.",
	},
	"ammo_rub": {
		"mode": "ammo", "name": "12 RUB", "full": "12/70 rubber shells", "issue": 0, "price": 40, "max": 30, "box": 10,
		"color": Color(0.45, 0.5, 0.45),
		"note": "Box of 10 less-lethal rubber shells for both shotguns: stun and knock back, barely wound.",
	},
	"ammo_40buck": {
		"mode": "ammo", "name": "40 BUCK", "full": "40 mm buckshot round", "issue": 0, "price": 90, "max": 12, "box": 6,
		"color": Color(0.75, 0.7, 0.5),
		"note": "Six buckshot rounds for the WRATH-4: a wide cone of pellets, deadly up close where a grenade would not arm. No blast.",
	},
	"ammo_40illum": {
		"mode": "ammo", "name": "40 ILLUM", "full": "40 mm parachute flare", "issue": 0, "price": 80, "max": 8, "box": 4,
		"color": Color(1.0, 0.9, 0.7),
		"note": "Four illumination rounds for the WRATH-4: a parachute flare at the top of the arc lights the area for about 40 s. Light draws enemies.",
	},
	"ammo_40smoke": {
		"mode": "ammo", "name": "40 SMOKE", "full": "40 mm smoke round", "issue": 0, "price": 60, "max": 8, "box": 4,
		"color": Color(0.7, 0.72, 0.75),
		"note": "Four smoke rounds for the WRATH-4: a smoke cloud where the round lands, enemies cannot see through it.",
	},
	"scanner": {
		"mode": "use", "name": "OWL", "full": "Motion scanner (Owl)", "issue": 0, "price": 120, "max": 3, "time": 10.0, "range": 240.0, "noise": 1.0,
		"color": Color(0.9, 0.9, 0.5),
		"note": "10 s: shows enemy silhouettes through walls within 15 m. Emits 1 noise per second.",
	},
}

## Nazwa klawisza użycia przedmiotu do podpowiedzi i HUD (rejestr akcji: lewy Alt, na macOS lewy Cmd).
static func key_name() -> String:
	return Actions.key("throw")

static func is_valid(kind: String) -> bool:
	return KINDS.has(kind)

static func mode_of(kind: String) -> String:
	return String(KINDS[kind]["mode"]) if KINDS.has(kind) else ""

## Zestaw wydawany za darmo przed każdą misją (do tej liczby stan zapasu jest dopełniany); resztę kupuje się w warsztacie (price > 0).
static func issue_stock() -> Dictionary:
	var out := {}
	for k in ORDER:
		out[k] = int(KINDS[k]["issue"])
	return out

## Amunicja specjalna (wpis `ammo_*`)?
static func is_ammo(kind: String) -> bool:
	return mode_of(kind) == "ammo"

## Ile sztuk dokłada jeden zakup: pudełko naboi albo jeden przedmiot.
static func box_of(kind: String) -> int:
	return int(KINDS[kind].get("box", 1)) if KINDS.has(kind) else 1

## Zapas pokazany w warsztacie w sztukach zakupu (pudełka amunicji zaokrąglone w górę, przedmioty jak są).
static func units(kind: String, have: int) -> int:
	var b := box_of(kind)
	return (have + b - 1) / b

static func price_of(kind: String) -> int:
	return int(KINDS[kind].get("price", 0)) if KINDS.has(kind) else 0

## Waga losowania przedmiotu wypadającego z wrogów (skrzynka zaopatrzenia) — tanie i częste częściej niż ładunek.
const DROP_WEIGHTS := {"frag": 3, "medkit": 3, "smoke": 2, "phos": 1, "mine": 1, "scanner": 1}

static func drop_kind() -> String:
	var total := 0
	for k in DROP_WEIGHTS:
		total += int(DROP_WEIGHTS[k])
	var roll := randi() % total
	for k in DROP_WEIGHTS:
		roll -= int(DROP_WEIGHTS[k])
		if roll < 0:
			return String(k)
	return "frag"
