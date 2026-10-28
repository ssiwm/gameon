extends Control
## Wskaźnik hałasu jako analogowy VU-metr (UI_PLAN.md): półokrągła skala liniowa 0–100 Uwagi z trzema strefami CALM / UNEASY / HUNTED
## (progi z NoiseMgr) i wskazówką z opóźnieniem. W strefie HUNTED wskazówka drży (nie przy „Reduce effects”).
## Ta sama klasa w rogu HUD (bieżący poziom) i na kartach stanowisk (STATION_CARDS_PLAN.md §5a: poziom po typowym użyciu od ciszy,
## `ghost` = to samo bez zmiany, np. bez tłumika). Wydzielona z hud.gd w 1.7.415.

const UiTheme := preload("res://scripts/ui_theme.gd")
const A0 := PI * 1.10                 ## początek skali (lewo, nad poziomem)
const A1 := PI * 1.90                 ## koniec skali (prawo)
var value := 0.0                      ## 0..1 (poziom Uwagi)
var ghost := -1.0                     ## 0..1: cień wskazówki (wartość przed zmianą); < 0 — bez cienia
var fill := Color.WHITE               ## kolor wskazówki
var ticks: Array = []                 ## [[próg ciszy, kolor], [próg niepokoju, kolor], [próg pościgu, kolor]]
var _shown := 0.0
var _t := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	_shown = lerpf(_shown, value, minf(1.0, delta * 9.0))
	queue_redraw()

func _ang(f: float) -> float:
	return lerpf(A0, A1, clampf(f, 0.0, 1.0))

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y - 5.0)
	var r := minf(size.x * 0.5 - 4.0, size.y - 9.0)
	var uneasy := 0.4
	var awake := 0.6
	var sleep := 0.3
	if ticks.size() >= 3:
		sleep = float(ticks[0][0])
		uneasy = float(ticks[1][0])
		awake = float(ticks[2][0])
	# tło skali i strefy
	var sw := clampf(size.y * 0.085, 4.0, 6.0)         # grubość pasa skali rośnie z rozmiarem miernika
	draw_arc(c, r, A0, A1, 28, Color(0, 0, 0, 0.55), sw + 3.0, true)
	draw_arc(c, r, _ang(0.0), _ang(uneasy), 16, UiTheme.CALM.darkened(0.15), sw, true)
	draw_arc(c, r, _ang(uneasy), _ang(awake), 10, UiTheme.ACCENT, sw, true)
	draw_arc(c, r, _ang(awake), _ang(1.0), 12, UiTheme.DANGER, sw, true)
	# kreski: co 10%, próg ciszy dłuższą
	for i in range(0, 11):
		var f := float(i) / 10.0
		var a := _ang(f)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 5.0), c + d * (r - (8.0 if i % 5 == 0 else 6.5)), Color(UiTheme.TEXT, 0.55), 1.0)
	var sa := _ang(sleep)
	draw_line(c + Vector2(cos(sa), sin(sa)) * (r - 5.0), c + Vector2(cos(sa), sin(sa)) * (r - 11.0), Color(UiTheme.TEXT, 0.9), 1.0)
	if ghost >= 0.0:
		var ga := _ang(ghost)
		draw_line(c, c + Vector2(cos(ga), sin(ga)) * (r - 1.0), Color(fill, 0.3), 1.6, true)
	# wskazówka
	var f2 := clampf(_shown, 0.0, 1.0)
	var shake := 0.0
	if f2 >= awake and Settings.fx_mult() > 0.0:
		shake = sin(_t * 47.0) * 0.035 + sin(_t * 23.0) * 0.02
	var na := _ang(f2) + shake
	var tip := c + Vector2(cos(na), sin(na)) * (r - 1.0)
	draw_line(c, tip, Color(0, 0, 0, 0.7), 3.0, true)
	draw_line(c, tip, fill, 1.6, true)
	draw_circle(c, 3.0, Color(0.1, 0.1, 0.1))
	draw_circle(c, 1.6, fill)
