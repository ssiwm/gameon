extends RefCounted
## Wygląd gracza (kosmetyka, bez wpływu na rozgrywkę): płeć × strój. Kod = płeć × 8 + strój (mieści się w jednym bajcie i w replikowanej zmiennej `player.look`).
## Arkusze HD postaci: `playerhd3h_<płeć>` (Scavenger '87) oraz `playerhd3h_<płeć>_<strój>` (tools/pack_chars3d.py). Stroje odblokowuje poziom profilu.

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
const DEFAULT := 0

static func code(gender: int, outfit: int) -> int:
	return gender * 8 + outfit

static func gender_of(c: int) -> int:
	return c / 8

static func outfit_of(c: int) -> int:
	return c % 8

static func is_valid(c: int) -> bool:
	return c >= 0 and gender_of(c) < GENDERS.size() and outfit_of(c) < OUTFITS.size()

static func outfit_id(c: int) -> String:
	return String(OUTFITS[outfit_of(c)]) if is_valid(c) else "scavenger"

static func gender_id(c: int) -> String:
	return String(GENDERS[gender_of(c)]) if is_valid(c) else "male"

## Nazwa arkusza w art/sprites (bez rozszerzenia).
static func sheet(c: int) -> String:
	var o := outfit_id(c)
	return "playerhd3h_" + gender_id(c) + ("" if o == "scavenger" else "_" + o)

static func display_name(c: int) -> String:
	return String(OUTFIT_NAMES[outfit_id(c)])

static func unlock_level(c: int) -> int:
	return int(UNLOCK_LEVEL[outfit_id(c)])

static func is_unlocked(c: int, level: int) -> bool:
	return is_valid(c) and level >= unlock_level(c)
