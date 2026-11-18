extends RefCounted
## Taśmy (DIG_LOOT_PLAN.md K4, GDD §3 „znajdźki: taśmy, listy robotników”): kasety magnetofonowe ludzi z Obiektu 86 i zaginionego
## patrolu — dwie na mapę strefy I. Jedna leży zakopana w głębokiej strefie wydobycia (opcja `{"tape": id}` w DIG_ZONES, dig_zone.gd),
## druga w sejfie patrolu (1.1, 1.2: strongbox.gd po otwarciu) albo w ukrytej skrytce (1.3: antresola Składu, pickup.gd `_try_stash`).
## Podnosi ją człowiek (bot nie); serwer ogłasza znalezisko wszystkim peerom i każdy dopisuje taśmę do swojego profilu (Profile.tapes),
## więc w co-opie cała drużyna dostaje wpis. Zebrane taśmy czyta się w menu pauzy, karta ARCHIWUM (codex.gd `archive`).
##
## TEKSTY SĄ SZKICEM (decyzja 5 z DIG_LOOT_PLAN.md §5): autor redaguje je przed scaleniem. Angielski tekst jest kluczem tłumaczenia,
## polski w translations/ui.csv — zmiana jednego wymaga zmiany drugiego. Daty (klucze tłumaczenia, po polsku z miesiącem rzymskim): ostatnia transmisja z Obiektu ok. 2 X 1987, akcja 14 dni później.

## Kolejność = indeks taśmy (arg przedmiotu „tape”, zapis profilu po id, więc kolejność można zmieniać).
const ORDER := ["m1_dig", "m1_box", "m2_dig", "m2_box", "m3_dig", "m3_stash"]

## id → {map, src („dig” / „box” / „stash”), cell (stash: kafel skrytki), title, who, date, text}
const TAPES := {
	"m1_dig": {"map": "z1_m1", "src": "dig", "title": "SURVEY PIT No. 7", "who": "Miner V. Semyonov, survey crew", "date": "2 Sep 1987",
		"text": "Is it recording? Good. Pit seven, four metres down. This vein isn't ore — it's warm. Warm, in September, in granite. Kolya swung the pick and the rock rang like a bell. Then something rang back. Three blows, three answers, the same rhythm, from deeper in. We stopped. So did it. The comrade engineer says it's an echo off a cavity. An echo doesn't wait for you to finish. I'm leaving the recorder here and we're filling the pit in. If anyone digs this up — don't knock."},
	"m1_box": {"map": "z1_m1", "src": "box", "title": "PATROL LOG, UNIT 2187", "who": "Cpl. Laskin, patrol radio operator", "date": "4 Oct 1987",
		"text": "Day three. Petrenko went missing at the ford. He called to us from the trees and we answered — that was the mistake. Lieutenant's orders: no voices, hand signals only. Whoever falls, leave his tag where he lies, so the next ones can follow our trail. The radio stays on. No call sign, only breathing, and it comes closer whenever one of us speaks. I'm locking this tape and the spare battery in the box. If you came looking for us — don't call our names."},
	"m2_dig": {"map": "z1_m2", "src": "dig", "title": "GEOPHONE LINE B", "who": "I. Orlova, geophysicist", "date": "19 Sep 1987",
		"text": "Geophone line B, three a.m. reading. The forest is quiet, the station is off the air, and the needle still moves. Steps. Slow, heavy, a pause after each one, as if listening. They come in under the line, stop under the mast and stay there. When Grisha dropped a wrench, every trace jumped at once — and then every trace went still. I've buried the reels with the sensors. Officially: settling ground. Unofficially — it hears us better than we hear it."},
	"m2_box": {"map": "z1_m2", "src": "box", "title": "STATION ORDER 86/14", "who": "Sgt. Dubin, radio station chief", "date": "29 Sep 1987",
		"text": "Order from the Object, read out and recorded as instructed. From today the station transmits carrier only, round the clock, no voice traffic. The generators are not to stop, not even for maintenance. Nobody tells us why. Last night all four went down for eleven minutes. In that silence the mast hummed on its own — a low note, like a man humming with his mouth shut. When the power came back, it stopped. I don't sleep in the hut by the mast any more."},
	"m3_dig": {"map": "z1_m3", "src": "dig", "title": "ROOTS IN THE ROCK", "who": "Foreman A. Ryabov, crew 3", "date": "24 Sep 1987",
		"text": "There are no trees above us, so these aren't roots. Grey, thick as an arm, running through the clay toward the sawmill. Warm to the touch. We cut one with an axe — it bled, and the whole wall twitched, as if something far away had flinched. Since then the crew finds new ones every morning, always where we worked loudest the day before. Management says keep cutting. I say we're feeding it."},
	"m3_stash": {"map": "z1_m3", "src": "stash", "cell": Vector2i(127, 21), "title": "FOR ANYA", "who": "Miner P. Gusev", "date": "1 Oct 1987",
		"text": "Anya, it's me. I'm whispering, forgive me. We're up on the loft above the store, eight of us, no light. Down below it walks between the shelves and stops whenever someone breathes too loud. The radio in the office keeps playing our voices — Misha's laugh, the foreman's orders from last week — but Misha is sitting right here next to me. If this reaches you, don't come for me and don't send anyone. And if you hear me on the radio, it isn't me. Don't answer."},
}

## Skąd taśma (podpowiedź na zakrytym wpisie archiwum i w statystykach odsłoniętego).
const SRC_TEXT := {"dig": "buried in a dig zone", "box": "in the patrol strongbox", "stash": "in a hidden stash"}
const MAP_CODE := {"z1_m1": "1.1", "z1_m2": "1.2", "z1_m3": "1.3"}
const MAP_GROUP := {"z1_m1": "1.1  MISSING PATROL", "z1_m2": "1.2  RADIO SILENCE", "z1_m3": "1.3  THE NEST"}

static func has(id: String) -> bool:
	return TAPES.has(id)

static func index_of(id: String) -> int:
	return ORDER.find(id)

static func id_at(i: int) -> String:
	return String(ORDER[i]) if i >= 0 and i < ORDER.size() else ""

static func data(id: String) -> Dictionary:
	return TAPES.get(id, {})

## Taśma mapy `map_id` ze źródła `src` („dig” / „box” / „stash”) albo "". Skrytka: tylko ta z kafla `cell` (na 1.3 są dwie skrytki).
static func for_source(map_id: String, src: String, cell := Vector2i(-1, -1)) -> String:
	for id in ORDER:
		var t: Dictionary = TAPES[id]
		if String(t["map"]) != map_id or String(t["src"]) != src:
			continue
		if src == "stash" and t.get("cell", Vector2i(-1, -1)) != cell:
			continue
		return String(id)
	return ""

## „1.1 — buried in a dig zone” (przetłumaczone części sklejone): gdzie szukać.
static func where(id: String) -> String:
	var t := data(id)
	if t.is_empty():
		return ""
	return "%s — %s" % [String(MAP_CODE.get(t["map"], "?")), TranslationServer.translate(String(SRC_TEXT.get(t["src"], "")))]

# ---------------------------------------------------------------- zestawy (K4): komplet taśm mapy → pamiątka w kwaterach kryjówki

## Mapy z taśmami w kolejności archiwum; pamiątka mapy wisi na ścianie kwater (z1_hub.gd HUB_PROPS „memento”, view3d.gd `_build_memento`),
## a komplet wszystkich sześciu stawia na stole kwater magnetofon szpulowy („recorder”). Czysto kosmetyczne i lokalne: liczy się archiwum
## profilu gracza (Profile.tapes), więc każdy w co-opie widzi w kryjówce własne pamiątki.
const SET_MAPS := ["z1_m1", "z1_m2", "z1_m3"]
## Nazwa pamiątki mapy (komunikat o komplecie, statystyka „Set” w archiwum).
const MEMENTO := {"z1_m1": "The patrol photo", "z1_m2": "The station map", "z1_m3": "The Store floor plan"}

## Taśmy mapy w kolejności ORDER.
static func set_of(map_id: String) -> Array:
	var out: Array = []
	for id in ORDER:
		if String(TAPES[id]["map"]) == map_id:
			out.append(String(id))
	return out

## Ile taśm mapy jest w archiwum `owned` (Profile.tapes: id → true).
static func set_count(map_id: String, owned: Dictionary) -> int:
	var n := 0
	for id in set_of(map_id):
		if owned.has(id):
			n += 1
	return n

static func set_complete(map_id: String, owned: Dictionary) -> bool:
	var s := set_of(map_id)
	return not s.is_empty() and set_count(map_id, owned) == s.size()

static func all_complete(owned: Dictionary) -> bool:
	for id in ORDER:
		if not owned.has(id):
			return false
	return true
