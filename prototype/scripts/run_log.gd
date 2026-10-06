extends RefCounted
## Dziennik ukończonych misji kampanii (ściana wyników w kryjówce, GDD §10.3 „Ściana pamięci"). Stan statyczny:
## każdy peer zapisuje wynik sam, gdy zobaczy SUCCESS (serwer w mission._success, klient przy zmianie fazy w _sync),
## więc nie trzeba go osobno replikować. Nocny Dyżur ma własne sumy (night_shift.gd) i tu nie trafia.

const MAX_ENTRIES := 8

## Wpis: {id, title, time, downs, attempts, stealth} — stealth: 1 cel poboczny zaliczony, 0 stracony, -1 brak celu.
static var entries: Array = []

static func add(id: String, title: String, time: float, downs: int, attempts: int, stealth: int) -> void:
	entries.append({"id": id, "title": title, "time": time, "downs": downs, "attempts": attempts, "stealth": stealth})
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()

static func clear() -> void:
	entries.clear()

static func total_time() -> float:
	var t := 0.0
	for e in entries:
		t += float(e["time"])
	return t

static func total_downs() -> int:
	var n := 0
	for e in entries:
		n += int(e["downs"])
	return n

static func fmt_time(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]
