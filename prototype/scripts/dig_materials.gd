extends RefCounted
## Materiały stref wydobycia (DESTRUCTION_PLAN.md D5): jedna tabela danych — z niej czyta `dig_zone.gd`, a później kopalnia FPP
## (`MINING_PLAN.md`, te same nazwy, kolory i dźwięki; siatki są różne, wspólne są dane).
##
## Siła ciosu (`power`) to gęstość zabrana z narożnika jednym uderzeniem danego narzędzia (0 = narzędzie tego nie bierze). Skała jest pełna
## przy 255, próg bryły 128, więc: 128–255 = 1 cios na wyrwę, 64–127 = 2, 43–63 = 3, 32–42 = 4.

const ORDER := ["dirt", "gravel", "rock", "vein"]     ## indeks = kod materiału w siatce strefy (PackedByteArray)

enum Tool { PICK, BLADE, BLAST }

## klucz → {power: [kilof, broń biała, wybuch], noise: mnożnik hałasu ciosu, tint: kolor wierzchołków siatki 3D (mnoży teksturę gruntu),
## hit: rodzaj trafienia dla efektu (Arsenal.Mat), inclusion: materiał wtrąceń (głazy w ziemi, żyła w skale), mix: domyślny udział wtrąceń,
## loose: luźny — bez podparcia spada i osypuje się do kąta 45° (dig_zone.gd `_settle`)}
const MATS := {
	"dirt": {"power": [255, 96, 255], "noise": 1.0, "tint": Color(1.0, 1.0, 1.0), "hit": "dust", "inclusion": "rock", "mix": 0.2, "loose": false},
	"gravel": {"power": [255, 96, 255], "noise": 1.1, "tint": Color(1.12, 1.08, 1.02), "hit": "dust", "inclusion": "dirt", "mix": 0.25, "loose": true},
	"rock": {"power": [56, 0, 255], "noise": 1.25, "tint": Color(0.74, 0.76, 0.82), "hit": "world", "inclusion": "vein", "mix": 0.15, "loose": false},
	"vein": {"power": [40, 0, 255], "noise": 1.25, "tint": Color(1.08, 0.74, 0.55), "hit": "world", "inclusion": "", "mix": 0.0, "loose": false},
}

static func code(key: String) -> int:
	return maxi(ORDER.find(key), 0)

static func key_of(c: int) -> String:
	return ORDER[clampi(c, 0, ORDER.size() - 1)]

static func power(c: int, tool: int) -> int:
	return int((MATS[key_of(c)]["power"] as Array)[tool])

static func tint(c: int) -> Color:
	return MATS[key_of(c)]["tint"]

static func loose(c: int) -> bool:
	return bool(MATS[key_of(c)]["loose"])
