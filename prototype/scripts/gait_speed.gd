extends RefCounted
## Prędkość pozioma wroga dla tempa kroku w widoku 3D (view3d.gd → `Enemy3D.pose(horizontal_speed)`), liczona z drogi w przesuwnym
## oknie WINDOW, a nie z jednej klatki obrazu.
##
## Symulacja przesuwa wrogów w krokach fizyki (60 Hz). Gdy obraz idzie szybciej (limit 120 / 144 / 240 kl./s albo bez limitu), w części
## klatek pozycja stoi, a w następnej skacze o cały krok. Dawne |Δx| / dt z jednej klatki dawało więc na przemian 0 (model przełączał się
## na „idle” — przy 144 kl./s waga klipu biegu Trzoska spadała do 0,01 i wilk sunął w pozie stojącej) i 2,4× prędkości (galop przy
## stępie). Różnica pozycji w oknie kilku kroków fizyki nie ma zer ani skoków i wybiera w modelu stęp / galop oraz postój; ruch tam
## i z powrotem w obrębie okna znosi się zamiast dodawać. Faza kroku idzie osobno z drogi w danej klatce (`st["gd"]` →
## `Enemy3D.pose(step_px)`), więc łapy nadążają za ruchem dokładnie przy każdym FPS, także przy ruszaniu i zawracaniu.

const WINDOW := 0.1                ## s: okno różnicy pozycji (6 kroków fizyki); po tylu sekundach bez ruchu prędkość spada do zera
const JUMP := 48.0                 ## px: większy skok pozycji naraz to przeniesienie (odrodzenie, punkt kontrolny), nie bieg

## `st` — stan wroga w view3d (klucze `gt`: zegar, `gs`: próbki z ostatniego okna na przemian czas, x — w float64, żeby zegar długiej
## sesji nie tracił dokładności; `gd`: droga w tym wywołaniu w px, 0 przy przeniesieniu), `x` — pozycja w px, `dt` — czas od
## poprzedniego wywołania. Zwraca |v| w px/s.
static func update(st: Dictionary, x: float, dt: float) -> float:
	var t := float(st.get("gt", 0.0)) + maxf(dt, 0.0)
	st["gt"] = t
	var gs: PackedFloat64Array = st.get("gs", PackedFloat64Array())
	var step := absf(x - gs[gs.size() - 1]) if gs.size() >= 2 else 0.0
	if step > JUMP:
		gs.clear()
		step = 0.0
	st["gd"] = step
	gs.append(t)
	gs.append(x)
	# zostaje jedna próbka sprzed okna (punkt odniesienia) i wszystkie nowsze
	var drop := 0
	while gs.size() - drop > 4 and gs[drop + 2] <= t - WINDOW:
		drop += 2
	if drop > 0:
		gs = gs.slice(drop)
	st["gs"] = gs
	var span := t - gs[0]
	if span <= 0.0:
		return 0.0
	return absf(x - gs[1]) / span
