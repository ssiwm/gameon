extends RefCounted
## Wygląd gracza (kosmetyka, bez wpływu na rozgrywkę). Kod to jedna liczba (replikowana zmienna `player.look`, zapis w profilu):
##   bity 0–2  strój (OUTFITS)           bit 3   płeć (GENDERS)
##   bity 4–7  nakrycie głowy (HEADS)    bity 8–10 plecy / ekwipunek (BACKS)    bity 11–13 paleta kolorów (PALETTES)
## Dolny bajt jest zgodny wstecz (płeć × 8 + strój), więc zapisy z poprzednich wersji nadal działają, a nowe pola mają wartość 0 = domyślny.
## Arkusze HD 2D: `playerhd3h_<płeć>[_<strój>]` (tylko płeć i strój); paleta, głowa i plecy dotyczą modelu 3D (char3d.gd).
## Stroje, nakrycia i palety odblokowuje poziom profilu.

const GENDERS := ["male", "female"]
const OUTFITS := ["scavenger", "hazmat", "medic"]
const OUTFIT_NAMES := {"scavenger": "SCAVENGER '87", "hazmat": "HAZMAT TECH", "medic": "FIELD MEDIC"}
const OUTFIT_TEXT := {
	"scavenger": "Olive field jacket, cargo trousers, a canvas pack with a bedroll, a gas mask round the neck. What the patrol wore when it went into the trees.",
	"hazmat": "Yellow coverall with reflective strips, a hooded respirator and goggles, a small air tank and a geiger counter on the belt. Built for the stations nobody cleaned up.",
	"medic": "Grey-blue combat uniform, a white vest and helmet with red crosses and a heavy medical pack. The one you look for when the lights go out.",
}
## Poziom profilu potrzebny do stroju (Scavenger od początku).
const UNLOCK_LEVEL := {"scavenger": 1, "hazmat": 3, "medic": 5}

## Nakrycia głowy i plecy: miejsce na dodatki (GLB `art/char3d/acc_<id>.glb` mocowany do kości głowy / pleców). Dziś tylko „bez dodatku”.
const HEADS := ["none"]
const BACKS := ["none"]

## Palety kolorów stroju (model 3D): docelowa barwa (0..1 po kole; −1 = bez zmiany barwy), mnożnik nasycenia i jasności — tylko dla
## nasyconych, nie-skórnych pikseli tekstury, więc ten sam wybór daje spójny kolor na każdym stroju. Zostaje ~35% oryginalnych różnic barwy.
## id, nazwa, barwa docelowa, mnożnik nasycenia, mnożnik jasności, kolor próbki, poziom odblokowania.
const PALETTES := [
	{"id": "standard", "name": "STANDARD", "hue": -1.0, "sat": 1.0, "val": 1.0, "swatch": Color(0.42, 0.45, 0.28), "level": 1},
	{"id": "dusk", "name": "DUSK", "hue": -1.0, "sat": 0.7, "val": 0.72, "swatch": Color(0.24, 0.3, 0.36), "level": 1},
	{"id": "dust", "name": "DUST", "hue": -1.0, "sat": 0.5, "val": 1.15, "swatch": Color(0.68, 0.62, 0.5), "level": 2},
	{"id": "rust", "name": "RUST", "hue": 0.065, "sat": 0.85, "val": 0.92, "swatch": Color(0.58, 0.34, 0.18), "level": 3},
	{"id": "frost", "name": "FROST", "hue": 0.55, "sat": 0.7, "val": 1.05, "swatch": Color(0.4, 0.56, 0.64), "level": 4},
	{"id": "ember", "name": "EMBER", "hue": 0.99, "sat": 0.8, "val": 0.85, "swatch": Color(0.52, 0.18, 0.16), "level": 5},
]
const DEFAULT := 0

static func code(gender: int, outfit: int, head := 0, back := 0, palette := 0) -> int:
	return outfit | (gender << 3) | (head << 4) | (back << 8) | (palette << 11)

static func gender_of(c: int) -> int:
	return (c >> 3) & 1

static func outfit_of(c: int) -> int:
	return c & 7

static func head_of(c: int) -> int:
	return (c >> 4) & 15

static func back_of(c: int) -> int:
	return (c >> 8) & 7

static func palette_of(c: int) -> int:
	return (c >> 11) & 7

## Ten sam wygląd z inną paletą / głową / plecami.
static func with_palette(c: int, p: int) -> int:
	return (c & ~(7 << 11)) | (p << 11)

static func with_head(c: int, h: int) -> int:
	return (c & ~(15 << 4)) | (h << 4)

static func with_back(c: int, b: int) -> int:
	return (c & ~(7 << 8)) | (b << 8)

## Sama płeć i strój (bez dodatków i palety): to, co ma arkusz 2D i kafelek w warsztacie.
static func base(c: int) -> int:
	return c & 15

static func is_valid(c: int) -> bool:
	return c >= 0 and c < (1 << 14) and gender_of(c) < GENDERS.size() and outfit_of(c) < OUTFITS.size() \
			and head_of(c) < HEADS.size() and back_of(c) < BACKS.size() and palette_of(c) < PALETTES.size()

static func outfit_id(c: int) -> String:
	return String(OUTFITS[outfit_of(c)]) if is_valid(c) else "scavenger"

static func gender_id(c: int) -> String:
	return String(GENDERS[gender_of(c)]) if is_valid(c) else "male"

## Nazwa arkusza w art/sprites (bez rozszerzenia): tylko płeć i strój.
static func sheet(c: int) -> String:
	var o := outfit_id(c)
	return "playerhd3h_" + gender_id(c) + ("" if o == "scavenger" else "_" + o)

static func display_name(c: int) -> String:
	return String(OUTFIT_NAMES[outfit_id(c)])

static func palette_name(p: int) -> String:
	return String(PALETTES[clampi(p, 0, PALETTES.size() - 1)]["name"])

static func unlock_level(c: int) -> int:
	return maxi(int(UNLOCK_LEVEL[outfit_id(c)]), int(PALETTES[palette_of(c)]["level"]) if palette_of(c) < PALETTES.size() else 1)

static func is_unlocked(c: int, level: int) -> bool:
	return is_valid(c) and level >= unlock_level(c)
