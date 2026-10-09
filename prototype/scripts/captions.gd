extends RefCounted
## Napisy dla dźwięków (dostępność; gra jest o hałasie): kolejka krótkich linii „← [Gunfire]” z kierunkiem do źródła.
## Źródło: sygnał `Audio.caption` (audio_director.gd, tabela CAPTIONS w audio_manifest.gd). Kolejką zarządza HUD
## (`hud.gd` — ustawienie „Sound captions”); klasa nie ma zależności od sceny, więc da się ją testować osobno.

const MAX_LINES := 4
const LIFE_S := 2.6
const MIN_PRIORITY := 1              ## priorytet 0 (kroki, szelest, łuski) pomijamy — zalałyby ekran
const NEAR_PX := 24.0                ## bliżej w poziomie: bez strzałki
const FAR_PX := 420.0                ## dalej: dopisek „far”

var _lines: Array = []               ## {base, text, t}

## Dodaje napis (albo odświeża ten sam) z kierunkiem względem słuchacza. Zwraca, czy coś się zmieniło.
func push(text: String, pos: Vector2, priority: int, listener: Vector2) -> bool:
	if priority < MIN_PRIORITY:
		return false
	var shown := text
	var dx := pos.x - listener.x
	if dx <= -NEAR_PX:
		shown = "←  " + shown
	elif dx >= NEAR_PX:
		shown = "→  " + shown
	if pos.distance_to(listener) > FAR_PX:
		shown += "  (far)"
	for l in _lines:
		if String(l["base"]) == text:
			l["text"] = shown
			l["t"] = LIFE_S
			return true
	_lines.append({"base": text, "text": shown, "t": LIFE_S})
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	return true

## Upływ czasu; zwraca, czy lista się zmieniła (wygasły linie).
func tick(delta: float) -> bool:
	var changed := false
	for i in range(_lines.size() - 1, -1, -1):
		_lines[i]["t"] = float(_lines[i]["t"]) - delta
		if float(_lines[i]["t"]) <= 0.0:
			_lines.remove_at(i)
			changed = true
	return changed

func clear() -> void:
	_lines.clear()

## Aktualne linie: [{text, alpha}] od najstarszej; ostatnie 0,5 s wygasa.
func lines() -> Array:
	var out: Array = []
	for l in _lines:
		out.append({"text": String(l["text"]), "alpha": clampf(float(l["t"]) / 0.5, 0.0, 1.0)})
	return out
