extends Node
## Komunikaty w grze (MESSAGES_PLAN.md): jedna kolejka z arbitrem zamiast osobnych węzłów tekstowych. Producenci (hud.gd, hints.gd, mission.gd, main.gd,
## radiostacja, tablica) wołają `post()` (zdarzenie z czasem życia) albo `hold()` (stan: żyje, dopóki jest odświeżany co klatkę), a HUD tylko rysuje to,
## co zwraca `current(kanał)` / `toasts()`. Arbiter pilnuje, że na kanał przypada jedna wiadomość naraz (wygrywa waga, przy remisie nowsza), a duplikat
## o tym samym `id` aktualizuje wiadomość w miejscu zamiast mnożyć karty (np. kolejne +XP sumują się w jednym toaście).
##
## Sześć kanałów (kolejność w `Ch` = kolejność w MESSAGES_PLAN.md §3):
##   NOTE   notatka związana z miejscem (odprawa, prognoza, cena), papier przy obiekcie
##   ALERT  zagrożenie i stan drużyny (hałas, SQUAD DOWN, odliczanie wyjścia), pod kartą celu
##   TOAST  zdarzenia (XP, awans, pogoda, sieć), stos pod kartą RUN
##   TITLE  start misji (tytuł, radio, reguła), dolna trzecia po lewej
##   TIP    porada dla nowego gracza, tylko w spokojnych chwilach
##   ACTION pasek akcji (co mogę zrobić teraz), dół, środek
## Wszystko, co zostało pokazane jako zdarzenie, trafia do dziennika (ostatnie JOURNAL_MAX wpisów, klawisz dziennika w HUD).
## Teksty przychodzą już przetłumaczone (`tr()` / `Actions.fmt()` u producenta); tu nic się nie tłumaczy.

enum Ch { NOTE, ALERT, TOAST, TITLE, TIP, ACTION }
enum Style { INFO, ACTION, SUCCESS, WARN, DANGER, LORE }

const CH_NAMES := ["note", "alert", "toast", "title", "tip", "action"]
const TOAST_MAX := 3                   ## tyle toastów naraz (reszta czeka, najstarsze o najniższej wadze odpadają)
const JOURNAL_MAX := 30
const LEASE_S := 0.2                   ## `hold()` gaśnie po tylu sekundach bez odświeżenia
## Domyślny czas życia zdarzenia [s] wg kanału
const DEFAULT_TTL := [4.0, 3.0, 4.0, 6.0, 7.0, 3.0]

signal journaled(entry: Dictionary)

var journal: Array = []                ## [{t, text, sub, ch, style}] od najstarszego
var _live := {}                        ## id → wiadomość
var _seq := 0
var _clock := 0.0                      ## sekundy od startu sesji (znacznik czasu w dzienniku)

func _process(delta: float) -> void:
	tick(delta)

## Zdarzenie: żyje `ttl` sekund (domyślnie wg kanału). `o`: sub (druga linia), style (Style.*), prio (waga, domyślnie 50), ttl, progress (0..1, -1 = brak),
## material ("dossier" / "printout" / "scrawl" dla notatek), rows (wiersze tabeli notatki), keys (id akcji do stopki), log (false = bez wpisu w dzienniku),
## amount + fmt (duplikat o tym samym id sumuje `amount` i składa tekst z `fmt % suma`, np. +XP).
func post(id: String, ch: int, text: String, o := {}) -> void:
	_put(id, ch, text, o, false)

## Stan: wiadomość żyje, dopóki producent wołał `hold()` w ostatnich LEASE_S sekundach (pasek akcji, ostrzeżenie hałasu, odliczanie).
## Domyślnie bez wpisu w dzienniku (`log` = true, jeśli stan ma zostać w dzienniku przy pierwszym pojawieniu się).
func hold(id: String, ch: int, text: String, o := {}) -> void:
	_put(id, ch, text, o, true)

func withdraw(id: String) -> void:
	_live.erase(id)

func clear(ch := -1) -> void:
	for id in _live.keys():
		if ch < 0 or int(_live[id]["ch"]) == ch:
			_live.erase(id)

## Wiadomość, która wygrywa w kanale: najwyższa waga, przy remisie nowsza; pusty słownik, gdy nic nie ma.
func current(ch: int) -> Dictionary:
	var best: Dictionary = {}
	for id in _live:
		var m: Dictionary = _live[id]
		if int(m["ch"]) != ch:
			continue
		if best.is_empty() or int(m["prio"]) > int(best["prio"]) or (int(m["prio"]) == int(best["prio"]) and int(m["seq"]) > int(best["seq"])):
			best = m
	return best

## Stos toastów: najwyżej TOAST_MAX, od najstarszego do najnowszego.
func toasts() -> Array:
	var all: Array = []
	for id in _live:
		if int(_live[id]["ch"]) == Ch.TOAST:
			all.append(_live[id])
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seq"]) < int(b["seq"]))
	while all.size() > TOAST_MAX:
		var drop := 0                   # odpada najstarszy o najniższej wadze
		for i in all.size():
			if int(all[i]["prio"]) < int(all[drop]["prio"]):
				drop = i
		all.remove_at(drop)
	return all

func has(id: String) -> bool:
	return _live.has(id)

## Upływ czasu: starzeje wiadomości i usuwa wygasłe (zdarzenia po `ttl`, stany po wygaśnięciu dzierżawy).
func tick(delta: float) -> void:
	_clock += delta
	for id in _live.keys():
		var m: Dictionary = _live[id]
		m["age"] = float(m["age"]) + delta
		if float(m["age"]) >= float(m["ttl"]):
			_live.erase(id)

## Ułamek życia wiadomości, który już minął (0..1): do wygaszania kart.
static func life(m: Dictionary) -> float:
	return clampf(float(m["age"]) / maxf(0.001, float(m["ttl"])), 0.0, 1.0)

## Zapis do dziennika bez wyświetlania (np. linie radia, które już pokazał baner).
func note_to_journal(text: String, ch: int, style := Style.INFO, sub := "") -> void:
	_journal_add(text, sub, ch, style)

func _put(id: String, ch: int, text: String, o: Dictionary, lease: bool) -> void:
	var prev: Dictionary = _live.get(id, {})
	var is_new := prev.is_empty()
	var m: Dictionary = prev if not is_new else {"id": id, "age": 0.0, "amount": 0}
	m["ch"] = ch
	m["style"] = int(o.get("style", Style.INFO))
	m["prio"] = int(o.get("prio", 50))
	m["sub"] = String(o.get("sub", ""))
	m["progress"] = float(o.get("progress", -1.0))
	m["material"] = String(o.get("material", ""))
	m["color"] = o.get("color", Color.WHITE)
	m["rows"] = o.get("rows", [])
	m["keys"] = o.get("keys", [])
	m["lease"] = lease
	m["ttl"] = LEASE_S if lease else float(o.get("ttl", DEFAULT_TTL[clampi(ch, 0, DEFAULT_TTL.size() - 1)]))
	m["age"] = 0.0                       # odświeżenie wydłuża życie (też dla zdarzeń z tym samym id)
	if o.has("amount"):
		m["amount"] = int(m.get("amount", 0)) + int(o["amount"])
		m["text"] = String(o.get("fmt", "%d")) % int(m["amount"])
	else:
		m["text"] = text
	if is_new:
		_seq += 1
		m["seq"] = _seq
		_live[id] = m
		if bool(o.get("log", not lease)):
			_journal_add(String(m["text"]), String(m["sub"]), ch, int(m["style"]))

func _journal_add(text: String, sub: String, ch: int, style: int) -> void:
	if text == "":
		return
	if not journal.is_empty():
		var last: Dictionary = journal.back()
		if String(last["text"]) == text and _clock - float(last["t"]) < 1.0:
			return                       # ten sam wpis w ciągu sekundy: bez dubla
	var e := {"t": _clock, "text": text, "sub": sub, "ch": ch, "style": style}
	journal.append(e)
	while journal.size() > JOURNAL_MAX:
		journal.pop_front()
	journaled.emit(e)
