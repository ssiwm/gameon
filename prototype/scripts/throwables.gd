extends RefCounted
## Rzucane przedmioty zużywalne (GDD §6.5, faza A1 rozbudowy ekwipunku): granat odłamkowy i fosforowy.
## Zapas jest WSPÓLNY dla drużyny (jak flary i ładunki Q), trzyma go Arsenal; rzut = klawisz T, zmiana rodzaju = X.
## Dane w jednym miejscu — nowy rodzaj to wpis w KINDS i ORDER plus obsługa w grenade.gd (`_detonate`).

const ORDER := ["frag", "phos"]

const KINDS := {
	"frag": {
		"name": "FRAG", "full": "Fragmentation grenade", "start": 2, "max": 4, "fuse": 1.8,
		"radius": 64.0, "damage": 90.0,                      # 4 m, 90 w środku (spadek do 50% na brzegu — Combat.BLAST_EDGE)
		"color": Color(0.5, 0.72, 0.4),
		"note": "Blast 4 m, 90 damage. Fuse 1.8 s. Hurts the squad too.",
	},
	"phos": {
		"name": "PHOS", "full": "Phosphorus grenade", "start": 1, "max": 3, "fuse": 1.3,
		"field_life": 15.0, "field_patches": 3, "noise": 3.0,   # pole ognia 15 s (3 plamy obok siebie) — mur dla Trzosków, Ślepców i Skoczków
		"color": Color(1.0, 0.85, 0.5),
		"note": "A field of fire for 15 s. Burns enemies, blocks shy ones, does not hurt the squad.",
	},
}

static func is_valid(kind: String) -> bool:
	return KINDS.has(kind)

static func start_stock() -> Dictionary:
	var out := {}
	for k in ORDER:
		out[k] = int(KINDS[k]["start"])
	return out
