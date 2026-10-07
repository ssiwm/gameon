extends RefCounted
## Zużywalne przedmioty ekwipunku (GDD §6.5–6.6, faza A1–A2): granaty, miny, ładunki i narzędzia drużynowe.
## Zapas jest WSPÓLNY dla drużyny (jak flary i ładunki Q), trzyma go Arsenal; przechodzi między misjami i sesjami (zapis u hosta),
## a kupuje się go w warsztacie (zakładka SUPPLIES, `price`) albo znajduje w skrzynkach z wrogów. Przed każdą misją dopełniany jest do zestawu `issue`. **lewy Alt** (macOS: lewy Cmd) używa wybranego przedmiotu, **X** zmienia wybór.
## Rodzaje użycia (`mode`):
##   throw — rzut łukiem (grenade.gd): odłamkowy, fosforowy, dymny
##   place — postawienie pod nogami (placed.gd): mina kierunkowa, ładunek wyburzeniowy
##   use   — narzędzie (przytrzymaj klawisz użycia przy celu / naciśnij): apteczka, defibrylator, skaner „Sowa” (player.gd `_gear_tick`)
## Nowy rodzaj = wpis w KINDS i ORDER plus obsługa w grenade.gd / placed.gd / arsenal.gd (`_use_server`).

const ORDER := ["frag", "phos", "smoke", "mine", "charge", "medkit", "defib", "scanner"]

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
	"defib": {
		"mode": "use", "name": "DEFIB", "full": "Defibrillator", "issue": 1, "price": 0, "max": 1, "time": 1.5, "range": 160.0,
		"color": Color(0.5, 0.85, 1.0),
		"note": "Hold the item key (L-Alt / L-Cmd) for 1.5 s: revives a downed teammate up to 10 m away in line of sight. One per mission.",
	},
	"scanner": {
		"mode": "use", "name": "OWL", "full": "Motion scanner (Owl)", "issue": 0, "price": 120, "max": 3, "time": 10.0, "range": 240.0, "noise": 1.0,
		"color": Color(0.9, 0.9, 0.5),
		"note": "10 s: shows enemy silhouettes through walls within 15 m. Emits 1 noise per second.",
	},
}

## Nazwa klawisza użycia przedmiotu do podpowiedzi i HUD (input_setup.gd: lewy Alt, na macOS lewy Cmd).
static func key_name() -> String:
	return "L-CMD" if OS.get_name() == "macOS" else "L-ALT"

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
