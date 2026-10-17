extends SceneTree
## Test arbitra komunikatów (scripts/messages.gd), bez gry i bez autoloadów: priorytet, deduplikacja, czas życia, dzierżawa stanów, stos toastów,
## sumowanie XP w jednym toaście i dziennik.
##   godot --headless --path prototype -s tools/test_messages.gd     → ostatni wiersz: PASS / FAIL

const Messages := preload("res://scripts/messages.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	print("[MESSAGES] %s  %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fails += 1


func _init() -> void:
	var m: Node = Messages.new()
	var ALERT: int = Messages.Ch.ALERT
	var TOAST: int = Messages.Ch.TOAST
	var TITLE: int = Messages.Ch.TITLE
	var ACTION: int = Messages.Ch.ACTION

	# 1. Wygrywa waga, przy remisie nowsza; kanały są niezależne.
	m.post("noise", ALERT, "Something is listening…", {"prio": 40})
	m.post("down", ALERT, "SQUAD DOWN", {"prio": 90})
	m.post("late", ALERT, "Later, same weight", {"prio": 90})
	m.post("t", TITLE, "1.1  MISSING PATROL")
	_check("alert: wygrywa waga, przy remisie nowszy", String(m.current(ALERT)["id"]) == "late")
	m.withdraw("late")
	_check("alert: po wycofaniu zostaje następny wg wagi", String(m.current(ALERT)["id"]) == "down")
	_check("kanały niezależne (tytuł obok alertu)", String(m.current(TITLE)["id"]) == "t")
	_check("pusty kanał zwraca pusty słownik", m.current(Messages.Ch.TIP).is_empty())

	# 2. Zdarzenie wygasa po ttl, stan po dzierżawie.
	m.clear()
	m.post("ev", ALERT, "event", {"ttl": 1.0})
	m.hold("st", ACTION, "state")
	m.tick(0.5)
	_check("zdarzenie żyje przed końcem ttl", m.has("ev"))
	_check("stan wygasa po LEASE_S bez odświeżenia", not m.has("st"))
	m.hold("st2", ACTION, "state2")
	m.tick(0.1)
	m.hold("st2", ACTION, "state2")
	m.tick(0.15)
	_check("stan odświeżany co klatkę żyje", m.has("st2"))
	m.tick(0.6)
	_check("zdarzenie wygasło po ttl", not m.has("ev"))
	_check("stan bez odświeżenia wygasł", not m.has("st2"))

	# 3. Duplikat po id aktualizuje w miejscu (jedna karta), XP sumuje się.
	m.clear()
	m.post("xp", TOAST, "", {"amount": 20, "fmt": "+%d XP"})
	m.post("xp", TOAST, "", {"amount": 30, "fmt": "+%d XP"})
	_check("XP: jeden toast, suma w tekście (%s)" % [m.current(TOAST).get("text", "")], m.toasts().size() == 1 and String(m.toasts()[0]["text"]) == "+50 XP")

	# 4. Stos toastów: najwyżej TOAST_MAX, odpada najstarszy o najniższej wadze.
	m.clear()
	m.post("a", TOAST, "a", {"prio": 50})
	m.post("b", TOAST, "b", {"prio": 50})
	m.post("c", TOAST, "c", {"prio": 50})
	m.post("d", TOAST, "d", {"prio": 50})
	var ids: Array = m.toasts().map(func(x: Dictionary) -> String: return String(x["id"]))
	_check("stos toastów ma najwyżej %d, odpada najstarszy (%s)" % [Messages.TOAST_MAX, str(ids)], ids == ["b", "c", "d"])
	m.post("hi", TOAST, "hi", {"prio": 90})
	m.post("e", TOAST, "e", {"prio": 30})
	ids = m.toasts().map(func(x: Dictionary) -> String: return String(x["id"]))
	_check("toast o niskiej wadze odpada pierwszy (%s)" % str(ids), ids.has("hi") and not ids.has("e") or ids.size() == Messages.TOAST_MAX)

	# 5. Dziennik: zdarzenia tak, stany domyślnie nie; limit i brak dubla w ciągu sekundy.
	var j: Node = Messages.new()
	j.post("x", Messages.Ch.TOAST, "Level up")
	j.hold("s", ACTION, "[E] Take")
	j.post("y", Messages.Ch.TOAST, "Level up")
	_check("dziennik: zdarzenie zapisane, stan nie, duble w sekundzie pominięte (%d)" % j.journal.size(), j.journal.size() == 1)
	for i in 40:
		j.tick(2.0)
		j.post("n%d" % i, Messages.Ch.TOAST, "wpis %d" % i)
	_check("dziennik: limit %d wpisów (%d)" % [Messages.JOURNAL_MAX, j.journal.size()], j.journal.size() == Messages.JOURNAL_MAX)
	_check("dziennik: zostają najnowsze", String(j.journal.back()["text"]) == "wpis 39")
	j.note_to_journal("Radio: transmitter humming", Messages.Ch.TITLE)
	_check("note_to_journal dopisuje bez wyświetlania", String(j.journal.back()["text"]).begins_with("Radio") and j.current(TITLE).is_empty())

	m.free()
	j.free()
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
