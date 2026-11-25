extends RefCounted
## Marki lampowe (1.7.684, plan Łupacza w skorupie: `reports/lupacz-pancerz-2026-11-25`): mosiężne żetony górników z lampowni Obiektu 86.
## Górnik zawieszał markę na tablicy lampowni przy zjeździe i zabierał ją po wyjeździe — pusty haczyk znaczył, kto został pod ziemią.
## Łupacz wkleja w skorupę to, co wykopał, także hełmy górników: rozbicie płyty karku (z hełmem, enemy_mole.gd) zrzuca markę jako przedmiot
## fabularny (pickup.gd „lamptoken”, model nieśmiertelnika). Podnosi ją człowiek; serwer ogłasza znalezisko i każdy peer dopisuje markę do
## swojego profilu (Profile.lamp_tokens), jak taśmy. Czyta się je w menu pauzy, karta ARCHIWUM (codex.gd `archive`, grupa „LAMP TOKENS”).
## Łupacz wychodzi tylko na mapach 1.1 i 1.2 (na 1.3 w wykopie mieszka Ślepiec), więc marki są dwie na każdą z tych map; Łupacz nosi
## pierwszą markę swojej mapy, której gospodarz jeszcze nie ma (`for_map`).
##
## TEKSTY SĄ SZKICEM: autor redaguje je przed scaleniem (jak taśmy). Angielski tekst jest kluczem tłumaczenia, polski w translations/ui.csv.
## Postacie łączą się z taśmami: Siemionow i Kola z dołu nr 7 (m1_dig), Grisza z linii geofonów B (m2_dig), noc postoju generatorów (m2_box).

const ORDER := ["m1_214", "m1_227", "m2_3105", "m2_3112"]

## id → {map, title, who, text}
const TOKENS := {
	"m1_214": {"map": "z1_m1", "title": "LAMP TOKEN No. 214", "who": "V. Semyonov, survey crew",
		"text": "Brass lamp token No. 214, stamped OBJECT 86 — SHAFT 2. Every miner hung his token on the lamp-room board when he went down and took it back when he came up. The board in the lamp room still has an empty hook under 214. The ledger for 2 September: down at 06:10. Up: a dash."},
	"m1_227": {"map": "z1_m1", "title": "LAMP TOKEN No. 227", "who": "N. Kolesnikov, survey crew",
		"text": "Token No. 227, worn smooth on one side where a thumb rubbed it. The ledger has Kolesnikov N. going down at 06:10, the same minute as Semyonov. Later someone pencilled next to both names: pit filled in by order. The pit was filled with sand. The token came out of the shell of a thing that digs."},
	"m2_3105": {"map": "z1_m2", "title": "LAMP TOKEN No. 3105", "who": "G. Fedin, geophone crew",
		"text": "Token No. 3105, radio station, geophone crew. The ledger has Fedin G. signing out at 03:20 on 19 September to check line B. The next line is in another hand: Fedin did not return. Line B reads steps."},
	"m2_3112": {"map": "z1_m2", "title": "LAMP TOKEN No. 3112", "who": "P. Zaitsev, lineman",
		"text": "Token No. 3112, its hook bent from being torn off in a hurry. Zaitsev P., lineman, went down to splice the cable under the mast on 28 September, the night the generators stopped for eleven minutes. The ledger is blank after that. His lamp was found on the outside of the mast fence, still lit."},
}

const MAP_GROUP := "LAMP TOKENS"
const WHERE := {"z1_m1": "on a Shalebreaker's shell, 1.1", "z1_m2": "on a Shalebreaker's shell, 1.2"}

static func has(id: String) -> bool:
	return TOKENS.has(id)

static func index_of(id: String) -> int:
	return ORDER.find(id)

static func id_at(i: int) -> String:
	return String(ORDER[i]) if i >= 0 and i < ORDER.size() else ""

static func data(id: String) -> Dictionary:
	return TOKENS.get(id, {})

## Gdzie szukać marki (zakryty wpis archiwum, statystyka odsłoniętego).
static func where(id: String) -> String:
	return String(WHERE.get(String(data(id).get("map", "")), ""))

## Marka, którą nosi Łupacz na mapie `map_id`: pierwsza z tej mapy, której nie ma w `owned`; mapa bez marek albo wszystkie zebrane — "".
static func for_map(map_id: String, owned: Dictionary) -> String:
	for id in ORDER:
		if String(TOKENS[id]["map"]) == map_id and not owned.has(id):
			return String(id)
	return ""
