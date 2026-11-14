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
## Efekt ciosu (dig_zone.gd `_hit_rpc`): snd: dźwięk uderzenia [klucz, głośność dB, wysokość], chip: kolor okruchów (cieniowane — nocą widać
## je tylko w świetle), dust: kolor obłoczka pyłu (alfa = gęstość; niska, bo pył powstaje tuż przy postaci i jej aurze), clods: grudki i okruchy na cios kilofem, sparks: szansa iskry stali o kamień.
const MATS := {
	"dirt": {"power": [255, 96, 255], "noise": 1.0, "tint": Color(1.0, 1.0, 1.0), "hit": "dust", "inclusion": "rock", "mix": 0.2, "loose": false,
		"snd": ["dig_dirt", -6.0, 1.0], "chip": Color(0.30, 0.23, 0.16), "dust": Color(0.46, 0.38, 0.28, 0.2), "clods": 9, "sparks": 0.0},
	"gravel": {"power": [255, 96, 255], "noise": 1.1, "tint": Color(1.12, 1.08, 1.02), "hit": "dust", "inclusion": "dirt", "mix": 0.25, "loose": true,
		"snd": ["dig_gravel", -6.0, 1.0], "chip": Color(0.44, 0.42, 0.38), "dust": Color(0.52, 0.49, 0.44, 0.14), "clods": 12, "sparks": 0.1},
	"rock": {"power": [56, 0, 255], "noise": 1.25, "tint": Color(0.74, 0.76, 0.82), "hit": "world", "inclusion": "vein", "mix": 0.15, "loose": false,
		"snd": ["dig_rock", -5.0, 1.0], "chip": Color(0.42, 0.43, 0.46), "dust": Color(0.58, 0.58, 0.58, 0.16), "clods": 8, "sparks": 0.35},
	"vein": {"power": [40, 0, 255], "noise": 1.25, "tint": Color(1.08, 0.74, 0.55), "hit": "world", "inclusion": "", "mix": 0.0, "loose": false,
		"snd": ["dig_rock", -5.0, 0.9], "chip": Color(0.55, 0.36, 0.24), "dust": Color(0.56, 0.42, 0.32, 0.16), "clods": 8, "sparks": 0.6},
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
