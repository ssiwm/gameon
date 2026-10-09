extends Control
## In-game HUD (English). Built in code on the shared theme (ui_theme.gd).
##
## Skala: cały HUD jest rysowany w 70% (UI_SCALE) — węzeł ma `scale` i logiczny rozmiar
## viewport / UI_SCALE (≈914×514), więc układ liczy się względem `size`, nie stałych 640×360.
## Layout (proporcje jak w viewporcie 640×360):
##   top-left    NOISE meter with thresholds and state (CALM / UNEASY / HUNTED) — the one gauge to watch
##   bottom-left SQUAD card: every player (own card largest, teammates above), slot-coloured badge,
##               hearts (gold = bonus), DOWN / REVIVING / CRITICAL state, bleed-out / revive bar
##   bottom-centre GEAR strip (flat, one row): weapon + noise cost, big magazine / team reserve, reload and
##               barrel-heat bars, weapon slots, LURE (Q), FLARE (F) charges, flashlight — centred and low so it never covers the boss
##   top-centre  objective card — phase, objective, hint, boss bar
##   top-right   session — host/client, players, mission clock
##   centre      threat warning (something listening / HE HEARS YOU), wipe
##   bottom      context prompt with progress (revive, extraction, bleed-out)
##   bottom      controls strip — shown for the first seconds, F1 toggles
##   full screen damage vignette; result card after extraction
## Adaptive music and the warning sting are driven from here (GDD §13).

const Weapons := preload("res://scripts/weapons.gd")
const Mission := preload("res://scripts/mission.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Hints := preload("res://scripts/hints.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Weather := preload("res://scripts/weather.gd")
const Codex := preload("res://scripts/codex.gd")
const RunLog := preload("res://scripts/run_log.gd")
const WorkshopUi := preload("res://scripts/workshop_ui.gd")
const Actions := preload("res://scripts/actions.gd")
const Captions := preload("res://scripts/captions.gd")

## HUD o 30% mniejszy niż w 1.6 (karty, paski, ikony i teksty razem; celownik ma własne CROSS_SCALE).
const UI_SCALE := 0.8
const MARGIN := 8.0              ## odstęp kart od krawędzi (jednostki logiczne HUD)
const CONTROLS_SHOW_S := 20.0
const NOISE_COL_CALM := Color(0.62, 0.72, 0.78)
const OBJ_W := 250.0             ## szerokość treści karty celu (zawijanie)
const SESSION_W := 152.0         ## szerokość bloku „sesja + zegar" w prawym górnym rogu
const WARN_Y := 0.255            ## wysokość ostrzeżenia nad środkiem ekranu (ułamek wysokości; 92/360)
const CENTER_Y := 0.39           ## napis „SQUAD DOWN" (140/360)
const HINT_Y := 0.66             ## karta podpowiedzi (nad paskiem kontekstowym)
const BRIEF_ROWS := 5             ## ile wierszy zagrożeń pokazuje odprawa (reszta: „+N more")
const PROMPT_Y := 0.76           ## pasek kontekstowy — nad paskiem broni (dół, środek)
## Układ wzorowany na koop-strzelankach (Left 4 Dead, Deep Rock Galactic, Helldivers): drużyna i zdrowie w lewym dolnym
## rogu (własna karta największa, koledzy nad nią), broń i zasoby w płaskim pasku na środku dołu, a w lewym górnym tylko miernik hałasu.
const BOTTOM_PAD := 20.0         ## odstęp kart dolnych od krawędzi (nad paskiem sterowania)
const SQUAD_W := 176.0
## Kolory slotów = kolory kurtek sprite'ów graczy (bake_sprites.PLAYER_VARIANTS).
const SLOT_COLORS := [Color(0.91, 0.62, 0.22), Color(0.25, 0.72, 0.85), Color(0.86, 0.28, 0.36), Color(0.45, 0.80, 0.30)]
const BOT_COLOR := Color(0.58, 0.60, 0.66)

## Horizontal bar with optional threshold ticks.
class Bar extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value := 0.0
	var fill := Color.WHITE
	var back := Color(1, 1, 1, 0.08)
	var ticks: Array = []          ## [[0..1, Color], ...]
	var seg := 0.0                 ## > 0: pasek „diodowy" — bloki szerokości seg z 1-pikselową przerwą (pixel art), zamiast gładkiej wypełnionej belki
	var _sb_back: StyleBoxFlat
	var _sb_fill: StyleBoxFlat

	## HD (--newui): gładka, zaokrąglona belka z jaśniejszą górną połową i delikatnymi rowkami segmentów zamiast bloków pikseli.
	func _draw_hd() -> void:
		if _sb_back == null:
			_sb_back = StyleBoxFlat.new()
			_sb_fill = StyleBoxFlat.new()
		var rad := int(size.y * 0.5)
		_sb_back.bg_color = back
		_sb_back.set_corner_radius_all(rad)
		draw_style_box(_sb_back, Rect2(Vector2.ZERO, size))
		var fw := size.x * clampf(value, 0.0, 1.0)
		if fw > 0.5:
			_sb_fill.bg_color = fill
			_sb_fill.set_corner_radius_all(mini(rad, int(fw * 0.5)))
			draw_style_box(_sb_fill, Rect2(Vector2.ZERO, Vector2(fw, size.y)))
			draw_rect(Rect2(Vector2(rad * 0.4, 0.5), Vector2(maxf(0.0, fw - rad * 0.8), size.y * 0.35)), Color(1, 1, 1, 0.22))
		if seg > 0.0:
			var x := seg
			while x < size.x - 0.5:
				draw_rect(Rect2(x - 0.5, 0, 1.0, size.y), Color(0, 0, 0, 0.35))
				x += seg
		for t in ticks:
			var tx: float = size.x * float(t[0])
			draw_rect(Rect2(tx - 0.5, -2.0, 1.0, size.y + 4.0), t[1])

	func _draw() -> void:
		if UiTheme.hd_on():
			_draw_hd()
			return
		var r := Rect2(Vector2.ZERO, size)
		if seg > 0.0:
			var filled_w := size.x * clampf(value, 0.0, 1.0)
			var x := 0.0
			while x < size.x - 0.5:
				var bw := minf(seg - 1.0, size.x - x)
				draw_rect(Rect2(x, 0, bw, size.y), fill if x + bw * 0.5 <= filled_w else back)
				x += seg
		else:
			draw_rect(r, back)
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), fill)
		for t in ticks:
			var x: float = size.x * float(t[0])
			draw_rect(Rect2(x - 0.5, -2.0, 1.0, size.y + 4.0), t[1])

## Wskaźnik hałasu jako analogowy VU-metr (UI_PLAN.md): półokrągła skala z trzema strefami CALM / UNEASY / HUNTED (progi z
## NoiseMgr, więc zgodne z Nocnym Dyżurem) i wskazówką z opóźnieniem. W strefie HUNTED wskazówka drży (nie przy „Reduce effects”).
class VuMeter extends Control:
	const A0 := PI * 1.10                 ## początek skali (lewo, nad poziomem)
	const A1 := PI * 1.90                 ## koniec skali (prawo)
	var value := 0.0                      ## 0..1 (poziom Uwagi)
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
		draw_arc(c, r, A0, A1, 28, Color(0, 0, 0, 0.55), 7.0, true)
		draw_arc(c, r, _ang(0.0), _ang(uneasy), 16, UiTheme.CALM.darkened(0.15), 4.0, true)
		draw_arc(c, r, _ang(uneasy), _ang(awake), 10, UiTheme.ACCENT, 4.0, true)
		draw_arc(c, r, _ang(awake), _ang(1.0), 12, UiTheme.DANGER, 4.0, true)
		# kreski: co 10%, próg ciszy dłuższą
		for i in range(0, 11):
			var f := float(i) / 10.0
			var a := _ang(f)
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r - 5.0), c + d * (r - (8.0 if i % 5 == 0 else 6.5)), Color(UiTheme.TEXT, 0.55), 1.0)
		var sa := _ang(sleep)
		draw_line(c + Vector2(cos(sa), sin(sa)) * (r - 5.0), c + Vector2(cos(sa), sin(sa)) * (r - 11.0), Color(UiTheme.TEXT, 0.9), 1.0)
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

## Row of icons (hearts or diamonds), `filled` of `count` lit.
class Pips extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := 3
	var filled := 3
	var shape := "heart"
	var on := Color(0.95, 0.28, 0.32)
	var off := Color(1, 1, 1, 0.14)
	var bonus_from := 99          ## ikony od tego indeksu to serca „ponad stan" (złote)
	var bonus := Color(1.0, 0.8, 0.25)
	var u := 1.0                  ## skala ikon (własne serca w karcie drużyny są większe)
	## Serce 9×8 pikseli: ciemny obrys (przesunięcia o 1 px) pod wypełnieniem i jasny piksel odblasku — jak sprite'y świata.
	const HEART := ["011000110", "111101111", "111111111", "111111111", "011111110", "001111100", "000111000", "000010000"]
	func _pixel_heart(o: Vector2, c: Color) -> void:
		var edge := Color(0.12, 0.05, 0.05, 0.9)
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_heart_rows(o + d, edge)
		_heart_rows(o, c)
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(1, 1)), c.lightened(0.55))
	func _heart_rows(o: Vector2, c: Color) -> void:
		for y in HEART.size():
			var row: String = HEART[y]
			var x := 0
			while x < row.length():
				if row[x] == "1":
					var x1 := x
					while x1 < row.length() and row[x1] == "1":
						x1 += 1
					draw_rect(Rect2(o + Vector2(float(x), float(y)), Vector2(float(x1 - x), 1.0)), c)
					x = x1
				else:
					x += 1
	## HD: serce z krzywej parametrycznej (wygładzone, z obrysem i połyskiem) — mieści się w tym samym polu 9×8 co pikselowe.
	func _smooth_heart(o: Vector2, c: Color) -> void:
		var pts := PackedVector2Array()
		for k in 36:
			var t := TAU * float(k) / 36.0
			var hx := 16.0 * pow(sin(t), 3.0)
			var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			pts.append(o + Vector2(4.5 + hx * 0.31, 3.7 - hy * 0.31))
		draw_colored_polygon(pts, Color(0.10, 0.04, 0.04, 0.9))
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(o + Vector2(4.5, 3.9) + (p - (o + Vector2(4.5, 3.9))) * 0.84)
		draw_colored_polygon(inner, c)
		draw_colored_polygon(PackedVector2Array([o + Vector2(2.0, 1.9), o + Vector2(3.3, 1.2), o + Vector2(4.0, 2.2), o + Vector2(2.8, 3.1)]), c.lightened(0.5) * Color(1, 1, 1, 0.8))
	## HD (horror): kropla krwi zamiast serca — ostry czubek, ciężkie ciemne dno, mokry połysk; pusta to ledwo widoczny kontur. Pole 9×8 jak serce.
	func _blood_drop(o: Vector2, c: Color, full: bool) -> void:
		var center := o + Vector2(4.5, 5.0)
		var r := 3.2
		var pts := PackedVector2Array([o + Vector2(4.5, -0.4)])
		var a0 := deg_to_rad(-43.8 + 6.0)
		var a1 := deg_to_rad(223.8 - 6.0)
		for k in 21:
			var a := lerpf(a0, a1, float(k) / 20.0)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		if not full:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, Color(0.7, 0.55, 0.55, 0.38), 0.9, true)
			return
		draw_colored_polygon(pts, c.darkened(0.55))
		var inner := PackedVector2Array()
		for q in pts:
			inner.append(center + Vector2(0, -0.6) + (q - (center + Vector2(0, -0.6))) * 0.82)
		draw_colored_polygon(inner, c)
		draw_colored_polygon(PackedVector2Array([o + Vector2(2.7, 4.2), o + Vector2(3.4, 3.4), o + Vector2(3.9, 4.2), o + Vector2(3.5, 5.6), o + Vector2(2.8, 5.7)]), Color(1.0, 0.75, 0.75, 0.55))
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
		for i in count:
			var c := on if i < filled else off
			if i >= bonus_from:
				c = bonus
			var o := Vector2(i * 11.0, 0.0)
			if shape == "heart" and UiTheme.hd_on():
				_blood_drop(o, c.lerp(Color(0.5, 0.05, 0.07), 0.45) if i < filled and i < bonus_from else c, i < filled)
			elif shape == "heart":
				_pixel_heart(o, c)
			elif shape == "ready" and UiTheme.hd_on():
				if i < filled:
					draw_circle(o + Vector2(4.5, 4.5), 4.5, c.darkened(0.45))
					draw_circle(o + Vector2(4.5, 4.5), 3.7, c)
					draw_circle(o + Vector2(3.4, 3.4), 1.2, c.lightened(0.55))
				else:
					draw_arc(o + Vector2(4.5, 4.5), 4.0, 0.0, TAU, 24, Color(1, 1, 1, 0.55), 1.0, true)
			elif shape == "ready":
				# gotowość w kryjówce: kwadracik pełny (gotowy) albo sam obrys
				if i < filled:
					draw_rect(Rect2(o + Vector2(0, 0), Vector2(9, 9)), c)
				else:
					draw_rect(Rect2(o + Vector2(0.5, 0.5), Vector2(8, 8)), Color(1, 1, 1, 0.55), false, 1.0)
			else:
				var dia := PackedVector2Array([o + Vector2(4.5, 0), o + Vector2(9, 4.5), o + Vector2(4.5, 9), o + Vector2(0, 4.5)])
				draw_colored_polygon(dia, c)
				if UiTheme.hd_on():
					draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), c.darkened(0.55), 1.0, true)
					draw_colored_polygon(PackedVector2Array([o + Vector2(4.5, 1.2), o + Vector2(6.4, 3.0), o + Vector2(4.5, 4.0), o + Vector2(2.6, 3.0)]), c.lightened(0.5) * Color(1, 1, 1, 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Karta zakotwiczona w obiekcie świata: panel z „ogonkiem” (strzałką) pod spodem, wskazującym obiekt.
class TailPanel extends PanelContainer:
	var tail := false
	var tail_color := Color.WHITE
	var pin := false               ## czerwona pinezka na środku górnej krawędzi (kartka przypięta do tablicy)
	func _init() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		if pin:
			var px := roundf(size.x * 0.5)
			draw_circle(Vector2(px, 1.0), 3.5, Color(0.45, 0.1, 0.08))
			draw_circle(Vector2(px, 0.0), 3.0, Color(0.82, 0.2, 0.15))
			draw_rect(Rect2(px - 1.0, -1.0, 1.0, 1.0), Color(1.0, 0.7, 0.6))
		if tail:
			var cx := roundf(size.x * 0.5)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 6.0, size.y - 3.0), Vector2(cx + 6.0, size.y - 3.0), Vector2(cx, size.y + 6.0)]), tail_color)

## Znacznik wroga w odprawie: sylwetka-kropka w kolorze rodzaju (z tabeli Enemy.KINDS).
class Swatch extends Control:
	var col := Color.WHITE
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(9, 9)
	func _draw() -> void:
		if col.a <= 0.0:
			return
		if UiTheme.hd_on():
			draw_circle(Vector2(4.5, 4.5), 4.0, Color(0.15, 0.1, 0.05))
			draw_circle(Vector2(4.5, 4.5), 3.2, col)
			draw_circle(Vector2(3.5, 3.5), 0.9, Color(0.95, 0.9, 0.8, 0.8))
			return
		draw_rect(Rect2(1, 1, 7, 8), Color(0.15, 0.1, 0.05))
		draw_rect(Rect2(2, 2, 5, 6), col)
		draw_rect(Rect2(3, 3, 1, 1), Color(0.95, 0.9, 0.8))

## Moneta złomu (8×8, pixel art) — obok licznika portfela.
class Coin extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8, 8)
	func _draw() -> void:
		var gold := Color(0.95, 0.78, 0.32)
		var dark := Color(0.5, 0.36, 0.1)
		if UiTheme.hd_on():
			draw_circle(Vector2(4, 4), 4.0, dark)
			draw_circle(Vector2(4, 4), 3.2, gold)
			draw_arc(Vector2(4, 4), 2.1, 0.0, TAU, 20, dark, 0.8, true)
			draw_arc(Vector2(4, 4), 2.9, PI * 1.1, PI * 1.6, 8, Color(1, 0.95, 0.7), 0.9, true)
			return
		draw_rect(Rect2(2, 0, 4, 8), dark)
		draw_rect(Rect2(0, 2, 8, 4), dark)
		draw_rect(Rect2(2, 1, 4, 6), gold)
		draw_rect(Rect2(1, 2, 6, 4), gold)
		draw_rect(Rect2(3, 2, 2, 4), dark)
		draw_rect(Rect2(3, 2, 1, 1), Color(1, 0.95, 0.7))

var _player: Node = null
var _blink := 0.0
var _warn_was := false
var _music_layer := -1
var _session_t := 0.0
## Pasek sterowania: -1 = auto (pierwsze CONTROLS_SHOW_S s), 0 = ukryty, 1 = pokazany (F1).
var _controls_mode := -1
var _hit_flash := 0.0
var _dev_noise := -1.0
var _dim: ColorRect                   ## ściemnienie HUD-u pod modalami (karta wyniku, warsztat)
var _calm_t := 0.0                    ## sekundy spokoju (poziomy HUD: T2 / T3 wygaszane po 4 s)
var _tier_k := 1.0                    ## 1 = pełny HUD, ~0.5 = wyciszony w spokoju
var _stats_sig := -1                  ## podpis statystyk graczy w karcie wyniku
var _result_players: GridContainer
var _xp_bar: Bar                      ## pasek poziomu na karcie wyniku (animowany: XP z misji „wlewa się” w poziom)
var _xp_note: Label
var _xp_anim := 0.0                   ## 0..1 postęp animacji
var _xp_key := Vector2i(-1, -1)       ## (XP przed, XP po) — zmiana zaczyna animację od nowa
var _captions := Captions.new()       ## napisy dla dźwięków (ustawienie „Sound captions”)
var _cap_card: PanelContainer
var _chat: Node                       ## węzeł Chat (main.gd; tworzony po HUD-zie, więc wiązany leniwie)
var _chat_log: VBoxContainer          ## ostatnie linie czatu (blakną po 9 s)
var _chat_lines: Array = []           ## {label, t}
var _chat_edit: LineEdit
var _cap_box: VBoxContainer
var _last_hp := -1

var _noise_bar: VuMeter
var _noise_val: Label
var _noise_state: Label
var _weather_row: Label                   ## pogoda misji i jej skutki pod miernikiem hałasu (tylko gdy jest pogoda)
var _squad_card: PanelContainer
var _squad_box: VBoxContainer
var _squad_rows := {}            ## instance_id gracza -> słownik wiersza
var _gear_card: PanelContainer
var _reload_bar: Bar
var _charges: Pips
var _flares: Pips
var _gren: Pips
var _gren_name: Label
var _note: Label
var _note_t := 0.0
var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_icons: Array[GunIcon] = []
var _gun_main: GunIcon
var _battery: Bar
var _battery_note: Label
var _ammo_name: Label
var _ammo_mag: Label
var _ammo_res: Label
var _ammo_note: Label
var _heat_bar: Bar
var _heat_note: Label

var _obj_card: PanelContainer
var _obj_caption: Label
var _obj_text: Label
var _obj_hint: Label
var _boss_row: VBoxContainer
var _boss_bar: Bar
var _boss_name: Label

var _session: Label
var _clock: Label
var _scrap: Label                    ## portfel złomu (bank) i łup z bieżącej misji
var _lv_label: Label                 ## poziom profilu i postęp XP (profile.gd)
var _xp_feed: Label                  ## „+12 XP” — sumuje XP z ostatnich sekund i blaknie
var _xp_acc := 0
var _xp_t := 0.0
var _result_xp_val: Label
var _warn: Label
var _warn_sub: Label
var _center: Label
var _center_sub: Label
var _prompt_card: PanelContainer
var _prompt: Label
var _prompt_bar: Bar
var _controls: Label
var _f1: Label
var _result: PanelContainer
var _hints := Hints.new()
var _hint_card: PanelContainer
var _hint_label: Label
var _result_stats: GridContainer
var _result_prompt: Label
var _result_title: Label
var _result_sub: Label
var _result_box: StyleBoxFlat
var _item: Dictionary = {}                ## karta statystyk broni leżącej w zasięgu [E] (stojak w kryjówce, łup z mapy)
var _noise_card: PanelContainer      ## karta hałasu (w kryjówce zastępuje ją znacznik SAFE)
var _safe_chip: PanelContainer
var _ready_pips: Pips              ## kwadraciki gotowości w pasku misji kryjówki
var _scrap_coin: Coin
var _brief: Dictionary = {}               ## karta odprawy przy tablicy w kryjówce
var _radio: Dictionary = {}               ## karta prognozy pogody przy radiostacji w kryjówce
var _radio_key := ""
var _item_id := -2
var _brief_id := ""
var _demo_footer: Control = null     ## stopka dema na ekranie wyniku — tylko na końcu kampanii / serii

var _slot_on: StyleBoxFlat
var _slot_off: StyleBoxFlat

func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pełny ekran w jednostkach logicznych: viewport / UI_SCALE, skala 0.7 od lewego górnego rogu
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(_scale_now(), _scale_now())
	_build_noise_card()
	_build_squad_card()
	_build_gear_card()
	_build_objective_card()
	_build_session()
	_build_center()
	_build_prompt()
	_build_controls()
	_build_hint()
	_build_captions()
	_build_chat()
	_build_result()
	_build_dim()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotnoise="):
			_dev_noise = float(a.substr("--shotnoise=".length()))
	_item = _make_info_card(250.0, 2, true)
	_brief = _make_info_card(310.0, 4, true)
	(_brief["card"] as TailPanel).pin = true
	_radio = _make_info_card(300.0, 2, true)
	(_radio["card"] as TailPanel).pin = true
	var wsp := WorkshopUi.new()
	wsp.z_index = 11                                           # nad ściemnieniem (_dim, z_index 10)
	add_child(wsp)
	get_viewport().size_changed.connect(_fit)
	Settings.changed.connect(_apply_scale)
	_fit()

## Skala HUD = bazowe 70% × ustawienie gracza (SMALL / NORMAL / LARGE).
func _scale_now() -> float:
	return UI_SCALE * Settings.ui_mult()

func _apply_scale() -> void:
	scale = Vector2(_scale_now(), _scale_now())
	_fit()

## Dopasowuje rozmiar logiczny do viewportu i układa elementy przypięte do krawędzi / środka.
func _fit() -> void:
	size = get_viewport_rect().size / _scale_now()
	var w := size.x
	var h := size.y
	_place(_session, Vector2(w - MARGIN - SESSION_W, MARGIN), Vector2(SESSION_W, 12))
	_place(_clock, Vector2(w - MARGIN - SESSION_W, MARGIN + 11.0), Vector2(SESSION_W, 14))
	_place(_scrap, Vector2(w - MARGIN - SESSION_W, MARGIN + 37.0), Vector2(SESSION_W, 12))
	_place(_lv_label, Vector2(w - MARGIN - SESSION_W, MARGIN + 50.0), Vector2(SESSION_W, 11))
	_place(_xp_feed, Vector2(w - MARGIN - SESSION_W, MARGIN + 61.0), Vector2(SESSION_W, 12))
	var cw := 400.0
	_place(_warn, Vector2((w - cw) * 0.5, h * WARN_Y), Vector2(cw, 20))
	_place(_warn_sub, Vector2((w - cw) * 0.5, h * WARN_Y + 20.0), Vector2(cw, 12))
	_place(_note, Vector2((w - cw) * 0.5, h * WARN_Y + 36.0), Vector2(cw, 14))
	_place(_center, Vector2((w - cw) * 0.5, h * CENTER_Y), Vector2(cw, 28))
	_place(_center_sub, Vector2((w - cw) * 0.5, h * CENTER_Y + 28.0), Vector2(cw, 16))
	_place(_controls, Vector2(MARGIN, h - 16.0), Vector2(w - 2.0 * MARGIN, 12))
	_place(_f1, Vector2(w - MARGIN - SESSION_W, MARGIN + 25.0), Vector2(SESSION_W, 12))

# ---------------------------------------------------------------- budowa

## Pozycja i rozmiar PO dodaniu do drzewa: wcześniej etykieta nie ma motywu,
## liczy minimalny rozmiar domyślną czcionką 16 px i zostaje za szeroka.
func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz

func _card(pos: Vector2) -> PanelContainer:
	var c := PanelContainer.new()
	c.position = pos
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c

## Cienka linia oddzielająca grupy w karcie (czytelniejsza hierarchia niż same odstępy).
func _hr(parent: Container) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.08)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)

func _row(parent: Container, caption: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var cap := UiTheme.label(caption, 7, UiTheme.MUTED)
	cap.custom_minimum_size = Vector2(62, 0)
	r.add_child(cap)
	parent.add_child(r)
	return r

## Lewy górny róg: sam miernik hałasu — jedyny wskaźnik, na który trzeba patrzeć bez przerwy (filar ciszy).
func _build_noise_card() -> void:
	var card := _card(Vector2(MARGIN, MARGIN))
	_noise_card = card
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	card.add_child(outer)
	_noise_bar = VuMeter.new()                 # analogowy VU-metr; progi z NoiseMgr: 30 = zasypia, 40 = niepokój, 60 = budzi się ON
	_noise_bar.custom_minimum_size = Vector2(72, 40)
	_noise_bar.ticks = [
		[NoiseMgr.SLEEP_THRESHOLD / 100.0, Color(1, 1, 1, 0.35)],
		[NoiseMgr.UNEASY_THRESHOLD / 100.0, UiTheme.ACCENT],
		[NoiseMgr.AWAKE_THRESHOLD / 100.0, UiTheme.DANGER],
	]
	outer.add_child(_noise_bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(box)
	box.add_child(UiTheme.heading("NOISE", 8, UiTheme.MUTED))
	_noise_state = UiTheme.label("", 7, UiTheme.MUTED)
	box.add_child(_noise_state)
	_noise_val = UiTheme.mono(UiTheme.label("0%", 12, UiTheme.TEXT))
	box.add_child(_noise_val)
	_weather_row = UiTheme.label("", 7, UiTheme.MUTED)
	_weather_row.visible = false
	box.add_child(_weather_row)
	# w kryjówce miernik hałasu nic nie mówi (zawsze 0%) — zastępuje go mały znacznik SAFE
	_safe_chip = _card(Vector2(MARGIN, MARGIN))
	_safe_chip.add_child(UiTheme.heading("SAFE", 8, UiTheme.OK))
	_safe_chip.visible = false

## Lewy dolny róg: karta drużyny (L4D / DRG). Wiersze powstają dynamicznie — _drive_squad().
func _build_squad_card() -> void:
	_squad_card = _card(Vector2(MARGIN, MARGIN))
	_squad_card.custom_minimum_size = Vector2(SQUAD_W, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 3)
	_squad_card.add_child(outer)
	outer.add_child(UiTheme.heading("SQUAD", 8, UiTheme.MUTED))
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 5)
	outer.add_child(_squad_box)

## Dół, środek: płaski pasek broni i zasobów w jednym rzędzie (nie zasłania bossa po prawej stronie sceny):
## [nazwa + koszt strzału] [magazynek / zapas] [stan + przeładowanie + ciepło lufy] [sloty] [wabik, flary, latarka].
func _build_gear_card() -> void:
	_gear_card = _card(Vector2(MARGIN, MARGIN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_gear_card.add_child(row)

	_slot_on = UiTheme.panel_box()
	_slot_on.bg_color = Color(0.25, 0.18, 0.06, 0.9)
	_slot_on.border_color = UiTheme.ACCENT
	_slot_on.set_content_margin_all(2)
	_slot_on.shadow_size = 0                  # cień karty na małych slotach tylko brudzi
	_slot_off = UiTheme.panel_box()
	_slot_off.bg_color = Color(1, 1, 1, 0.04)
	_slot_off.set_content_margin_all(2)
	_slot_off.shadow_size = 0

	# 0) miniatura aktualnej broni na ciemnej płytce z paskiem w kolorze smugi pocisku
	_gun_main = GunIcon.new()
	_gun_main.plate = true
	_gun_main.k = 0.75
	_gun_main.custom_minimum_size = Vector2(50, 26)
	_gun_main.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gun_main)

	# 1) nazwa broni nad kosztem następnego strzału (ile Uwagi — GDD §8.1)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 0)
	name_col.custom_minimum_size = Vector2(54, 0)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ammo_name = UiTheme.label("", 9, UiTheme.TEXT)
	name_col.add_child(_ammo_name)
	_heat_note = UiTheme.label("", 7, UiTheme.MUTED)
	name_col.add_child(_heat_note)
	row.add_child(name_col)

	# 2) magazynek (duży) i zapas drużyny
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 3)
	_ammo_mag = UiTheme.heading("", 24, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_mag.custom_minimum_size = Vector2(38, 0)
	nums.add_child(_ammo_mag)
	_ammo_res = UiTheme.label("", 9, UiTheme.MUTED)
	_ammo_res.size_flags_vertical = Control.SIZE_SHRINK_END
	nums.add_child(_ammo_res)
	row.add_child(nums)

	# 3) stan (RELOADING / NO AMMO) nad paskami: przeładowanie i ciepło lufy
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	bars.custom_minimum_size = Vector2(78, 0)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ammo_note = UiTheme.label("", 7, UiTheme.MUTED)
	bars.add_child(_ammo_note)
	_reload_bar = Bar.new()
	_reload_bar.custom_minimum_size = Vector2(0, 3)
	_reload_bar.fill = UiTheme.ACCENT
	bars.add_child(_reload_bar)
	_heat_bar = Bar.new()
	_heat_bar.custom_minimum_size = Vector2(0, 3)
	bars.add_child(_heat_bar)
	row.add_child(bars)

	# 4) sloty: same klawisze, aktywny podświetlony
	var wr := HBoxContainer.new()
	wr.add_theme_constant_override("separation", 3)
	wr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 4:
		var sl := PanelContainer.new()
		var ic := GunIcon.new()
		ic.k = 0.375
		ic.custom_minimum_size = Vector2(30, 12)
		var l := UiTheme.label("", 6, UiTheme.TEXT)
		l.position = Vector2(0, -2)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # miniatura rysuje NEAREST; tekst ma zostać gładki
		ic.add_child(l)                     # numer klawisza w rogu miniatury
		sl.add_child(ic)
		_slot_icons.append(ic)
		wr.add_child(sl)
		_slots.append(sl)
		_slot_labels.append(l)
	row.add_child(wr)

	# 5) zasoby: wabik (Q) i flary (F) w jednym wierszu, pod nimi latarka (L)
	var res := VBoxContainer.new()
	res.add_theme_constant_override("separation", 2)
	res.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qf := HBoxContainer.new()
	qf.add_theme_constant_override("separation", 3)
	qf.add_child(UiTheme.label("Q", 7, UiTheme.MUTED))
	_charges = Pips.new()
	_charges.shape = "diamond"
	_charges.count = NoiseMgr.OVERCHARGE_MAX
	_charges.on = UiTheme.ACCENT
	_charges.u = 0.8
	_charges.custom_minimum_size = Vector2(NoiseMgr.OVERCHARGE_MAX * 11.0 * 0.8 - 2.0, 7.2)
	qf.add_child(_charges)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(4, 0)
	qf.add_child(gap)
	qf.add_child(UiTheme.label("F", 7, UiTheme.MUTED))
	_flares = Pips.new()
	_flares.shape = "diamond"
	_flares.count = NoiseMgr.FLARE_MAX
	_flares.on = Color(1.0, 0.5, 0.25)
	_flares.u = 0.8
	_flares.custom_minimum_size = Vector2(NoiseMgr.FLARE_MAX * 11.0 * 0.8 - 2.0, 7.2)
	qf.add_child(_flares)
	res.add_child(qf)
	var tg := HBoxContainer.new()                  # przedmioty (lewy Alt użyj, X zmiana rodzaju): rodzaj i zapas drużyny
	tg.add_theme_constant_override("separation", 3)
	tg.add_child(UiTheme.label("ALT" if OS.get_name() != "macOS" else "CMD", 7, UiTheme.MUTED))
	_gren = Pips.new()
	_gren.shape = "diamond"
	_gren.count = 4
	_gren.on = Color(0.5, 0.72, 0.4)
	_gren.u = 0.8
	_gren.custom_minimum_size = Vector2(4 * 11.0 * 0.8 - 2.0, 7.2)
	tg.add_child(_gren)
	_gren_name = UiTheme.label("FRAG", 7, UiTheme.MUTED)
	tg.add_child(_gren_name)
	res.add_child(tg)
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 4)
	lr.add_child(UiTheme.label("L", 7, UiTheme.MUTED))
	_battery = Bar.new()
	_battery.custom_minimum_size = Vector2(34, 3)
	_battery.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lr.add_child(_battery)
	_battery_note = UiTheme.label("OFF", 7, UiTheme.MUTED)
	lr.add_child(_battery_note)
	res.add_child(lr)
	row.add_child(res)

# ---------------------------------------------------------------- karta drużyny

## Jeden wiersz: plakietka w kolorze slotu, serca (złote ponad bazę), stan (DOWN / REVIVING / CRITICAL / AI)
## i pasek pod spodem, gdy ktoś leży (czerwony = wykrwawianie, zielony = podnoszenie).
func _make_squad_row(p: Node, is_self: bool) -> Dictionary:
	var slot := ((int(p.display_id) - 1) % 4) + 1
	var col: Color = BOT_COLOR if p.is_bot else SLOT_COLORS[slot - 1]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	var badge := UiTheme.label("AI" if p.is_bot else "P%d" % slot, 9 if is_self else 7, Color(0.04, 0.04, 0.06), HORIZONTAL_ALIGNMENT_CENTER)
	var bg := StyleBoxFlat.new()
	bg.bg_color = col
	bg.set_corner_radius_all(2)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 1
	bg.content_margin_bottom = 1
	badge.add_theme_stylebox_override("normal", bg)
	badge.add_theme_constant_override("outline_size", 0)
	badge.custom_minimum_size = Vector2(26 if is_self else 20, 0)
	top.add_child(badge)
	var pips := Pips.new()
	pips.u = 1.4 if is_self else 1.0
	top.add_child(pips)
	var status := UiTheme.label("", 7, UiTheme.MUTED)
	top.add_child(status)
	root.add_child(top)
	var bar := Bar.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.visible = false
	root.add_child(bar)
	_squad_box.add_child(root)
	return {"root": root, "pips": pips, "status": status, "bar": bar, "hp": maxi(p.hp, 0), "flash": 0.0, "self": is_self, "bot": p.is_bot}

func _drive_squad(delta: float) -> void:
	var list: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			list.append(p)
	# koledzy rosnąco po slocie, własna karta na dole (najbliżej rogu)
	list.sort_custom(func(a: Node, b: Node) -> bool:
		if (a == _player) != (b == _player):
			return b == _player
		return a.display_id < b.display_id)
	var present := {}
	for idx in list.size():
		var p: Node = list[idx]
		var id := p.get_instance_id()
		present[id] = true
		var is_self: bool = p == _player
		var row: Dictionary = _squad_rows.get(id, {})
		if row.is_empty() or bool(row["self"]) != is_self or bool(row["bot"]) != p.is_bot:
			if not row.is_empty():
				(row["root"] as Node).queue_free()
			row = _make_squad_row(p, is_self)
			_squad_rows[id] = row
		_squad_box.move_child(row["root"], idx)
		_update_squad_row(p, row, delta)
	for id in _squad_rows.keys():
		if not present.has(id):
			(_squad_rows[id]["root"] as Node).queue_free()
			_squad_rows.erase(id)
	_squad_card.reset_size()
	_squad_card.position = Vector2(MARGIN, size.y - BOTTOM_PAD - _squad_card.size.y)

func _update_squad_row(p: Node, row: Dictionary, delta: float) -> void:
	var hp := maxi(p.hp, 0)
	var pips: Pips = row["pips"]
	pips.count = maxi(p.max_hp(), hp)
	pips.bonus_from = p.max_hp()
	pips.filled = hp
	pips.on = Color(0.5, 0.2, 0.22) if p.dead else Color(0.95, 0.28, 0.32)
	pips.custom_minimum_size = Vector2(pips.count * 11.0 * pips.u - 2.0, 9.0 * pips.u)
	pips.queue_redraw()
	# błysk wiersza po utracie zdrowia
	if hp < int(row["hp"]):
		row["flash"] = 1.0
	row["hp"] = hp
	row["flash"] = maxf(0.0, float(row["flash"]) - delta * 2.2)
	var f := float(row["flash"])
	(row["root"] as Control).modulate = Color(1.0, 1.0 - 0.55 * f, 1.0 - 0.55 * f, 0.55 if p.dead else 1.0)
	var status: Label = row["status"]
	var bar: Bar = row["bar"]
	var txt := ""
	var col := UiTheme.MUTED
	bar.visible = false
	if p.dead:
		(row["root"] as Control).modulate.a = 1.0
		bar.visible = true
		if p.revive_progress > 0.0:
			txt = "REVIVING"
			col = UiTheme.OK
			bar.value = p.revive_progress
			bar.fill = UiTheme.OK
		else:
			txt = "DOWN  %ds" % ceili(p.bleed_left)
			col = UiTheme.DANGER
			bar.value = p.bleed_left / maxf(0.1, p.bleed_time())
			bar.fill = UiTheme.DANGER
		bar.queue_redraw()
	elif hp == 1:
		txt = "CRITICAL"
		col = UiTheme.DANGER.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_blink * 7.0)))
	elif bool(row["self"]):
		txt = "YOU"
	elif p.is_bot:
		txt = "AI"
	status.text = txt
	status.add_theme_color_override("font_color", col)

func _build_objective_card() -> void:
	_obj_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_obj_card.add_child(box)
	_obj_caption = UiTheme.heading("OBJECTIVE", 8, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_obj_caption)
	_hr(box)
	_obj_text = UiTheme.label("", 10, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_obj_text.custom_minimum_size = Vector2(OBJ_W, 0)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_obj_text)
	_obj_hint = UiTheme.label("", 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_obj_hint.custom_minimum_size = Vector2(OBJ_W, 0)
	_obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_obj_hint)
	# kryjówka: kwadraciki gotowości (jeden na człowieka) — widać, na kogo czeka drużyna
	_ready_pips = Pips.new()
	_ready_pips.shape = "ready"
	_ready_pips.on = UiTheme.OK
	_ready_pips.visible = false
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_child(_ready_pips)
	box.add_child(pip_row)
	_boss_row = VBoxContainer.new()
	_boss_row.add_theme_constant_override("separation", 2)
	_boss_name = UiTheme.heading("THE VEIN — MOTHER OF NESTS", 8, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_row.add_child(_boss_name)
	_boss_bar = Bar.new()
	_boss_bar.custom_minimum_size = Vector2(OBJ_W, 5)
	_boss_bar.fill = Color(0.88, 0.22, 0.2)
	_boss_bar.seg = 4.0
	_boss_bar.ticks = [[0.66, Color(1, 1, 1, 0.5)], [0.33, Color(1, 1, 1, 0.5)]]
	_boss_row.add_child(_boss_bar)
	box.add_child(_boss_row)

func _build_session() -> void:
	_session = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_session)
	_clock = UiTheme.mono(UiTheme.label("", 10, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	add_child(_clock)
	_scrap = UiTheme.mono(UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
	add_child(_scrap)
	_scrap_coin = Coin.new()
	add_child(_scrap_coin)
	_lv_label = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_lv_label)
	_xp_feed = UiTheme.label("", 9, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	_xp_feed.modulate.a = 0.0
	add_child(_xp_feed)
	Profile.xp_gained.connect(_on_xp_gained)
	Profile.leveled_up.connect(_on_level_up)

func _build_center() -> void:
	_warn = UiTheme.heading("", 16, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_warn)
	_warn_sub = UiTheme.whisper(UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	add_child(_warn_sub)
	# krótkie komunikaty (np. „wabik już nie działa tutaj")
	_note = UiTheme.whisper(UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_note.modulate.a = 0.0
	add_child(_note)
	NoiseMgr.overcharge_stale.connect(func() -> void: show_note("They know this trick — move before you lure again"))
	_center = UiTheme.heading("", 24, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_center)
	_center_sub = UiTheme.label("", 10, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_center_sub)

func _build_prompt() -> void:
	_prompt_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_prompt_card.add_child(box)
	_prompt = UiTheme.label("", 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_prompt)
	_prompt_bar = Bar.new()
	_prompt_bar.custom_minimum_size = Vector2(180, 3)
	box.add_child(_prompt_bar)

func _build_controls() -> void:
	_controls = UiTheme.label(Actions.hud_line(), 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_controls)
	_f1 = UiTheme.label(tr("%s  controls") % Actions.key("help"), 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var refresh_keys := func() -> void:        # klawiatura ↔ pad albo zmiana przypisań: podpowiedzi pokazują właściwe klawisze
		_controls.text = Actions.hud_line()
		_f1.text = tr("%s  controls") % Actions.key("help")
	InputSetup.device_changed.connect(func(_pad: bool) -> void: refresh_keys.call())
	Settings.bindings_changed.connect(refresh_keys)
	add_child(_f1)

## Ściemnienie pod modalami: nad kartami HUD (z_index), pod kartą wyniku i warsztatem.
func _build_dim() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.5)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = 10
	_dim.visible = false
	add_child(_dim)
	_result.z_index = 11

## Czat drużyny (chat.gd): log nad kartą drużyny i pole wpisywania pod klawiszem T (Enter wysyła, Esc anuluje). Na czas pisania
## akcje gry są wycięte (Settings.block_game_input), więc klawisze nie ruszają postaci.
func _build_chat() -> void:
	_chat_log = VBoxContainer.new()
	_chat_log.add_theme_constant_override("separation", 1)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chat_log)
	_chat_edit = LineEdit.new()
	_chat_edit.name = "ChatEdit"
	_chat_edit.max_length = 120
	_chat_edit.placeholder_text = tr("Message to the squad…  (Enter sends, Esc cancels)")
	_chat_edit.custom_minimum_size = Vector2(300, 0)
	_chat_edit.visible = false
	_chat_edit.text_submitted.connect(func(t: String) -> void:
		if _chat != null:
			_chat.send(t)
		_close_chat())
	_chat_edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled())
	add_child(_chat_edit)
	if "--shotchat" in OS.get_cmdline_user_args():
		# dev: przykładowe linie i otwarte pole do zrzutu
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			_on_chat_line("P1", "Flare at the east door, go quiet")
			_on_chat_line("P2", "On my way")
			_on_chat_line("P1", "Don't shoot the nest yet")
			_open_chat()
			_chat_edit.text = "Reloading, cover me")

func _open_chat() -> void:
	_chat_edit.text = ""
	_chat_edit.visible = true
	Settings.block_game_input(true)
	_chat_edit.grab_focus()

func _close_chat() -> void:
	_chat_edit.release_focus()
	_chat_edit.visible = false
	_chat_edit.text = ""
	Settings.block_game_input(false)

func _on_chat_line(who: String, text: String) -> void:
	var l := UiTheme.label("%s: %s" % [who, text], 9, UiTheme.TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log.add_child(l)
	_chat_lines.append({"label": l, "t": 9.0})
	while _chat_lines.size() > 5:
		var old: Dictionary = _chat_lines.pop_front()
		(old["label"] as Node).queue_free()

func _drive_chat(delta: float) -> void:
	if _chat == null:
		_chat = get_tree().current_scene.get_node_or_null("Chat") if get_tree().current_scene != null else null
		if _chat != null:
			_chat.line_added.connect(_on_chat_line)
	for i in range(_chat_lines.size() - 1, -1, -1):
		var e: Dictionary = _chat_lines[i]
		e["t"] = float(e["t"]) - delta
		(e["label"] as Control).modulate.a = clampf(float(e["t"]) / 1.5, 0.0, 1.0) if not _chat_edit.visible else 1.0
		if float(e["t"]) <= 0.0 and not _chat_edit.visible:
			(e["label"] as Node).queue_free()
			_chat_lines.remove_at(i)
	var base_y := _squad_card.position.y - 6.0
	_chat_edit.position = Vector2(MARGIN, base_y - 20.0)
	_chat_log.reset_size()
	_chat_log.position = Vector2(MARGIN, base_y - _chat_log.size.y - (22.0 if _chat_edit.visible else 0.0))
	_chat_log.visible = not _result.visible

## Poziomy HUD: T1 (zdrowie, amunicja, wskaźnik hałasu) zawsze w pełni; T2 (karta celu) i T3 (zegar, XP, sesja, sterowanie)
## przygasają po 4 s spokoju — bez wystrzałów i bez Uwagi ponad próg niepokoju — i wracają przy pierwszym hałasie.
func _drive_tiers(delta: float) -> void:
	var calm: bool = NoiseMgr.level < NoiseMgr.UNEASY_THRESHOLD and not NoiseMgr.stalker_awake \
			and not Input.is_action_pressed("fire") and _hit_flash <= 0.01
	_calm_t = _calm_t + delta if calm else 0.0
	var target := 0.5 if _calm_t > 4.0 else 1.0
	_tier_k = lerpf(_tier_k, target, minf(1.0, delta * (1.5 if target < 1.0 else 6.0)))
	_obj_card.modulate.a = lerpf(1.0, 0.6, (1.0 - _tier_k) * 2.0)
	for c in [_session, _clock, _scrap, _lv_label, _f1, _controls]:
		(c as Control).self_modulate.a = lerpf(1.0, 0.45, (1.0 - _tier_k) * 2.0)
	# ściemnienie pod karta wyniku i warsztatem
	var ws := get_tree().get_first_node_in_group("workshop_ui")
	var modal: bool = _result.visible or (ws != null and ws.is_open())
	_dim.visible = modal
	if modal:
		_dim.size = size

## Napisy dla dźwięków: wąska karta przy prawej krawędzi, linie z kierunkiem do źródła (captions.gd).
func _build_captions() -> void:
	_cap_card = _card(Vector2(MARGIN, MARGIN))
	_cap_card.visible = false
	var cb := UiTheme.panel_box()
	cb.bg_color.a = 0.8
	cb.set_content_margin_all(5)
	_cap_card.add_theme_stylebox_override("panel", cb)
	_cap_box = VBoxContainer.new()
	_cap_box.add_theme_constant_override("separation", 1)
	_cap_card.add_child(_cap_box)
	Audio.caption.connect(func(text: String, pos: Vector2, priority: int) -> void:
		if not Settings.captions:
			return
		var lp: Node = _player if _player != null and is_instance_valid(_player) else null
		var listener: Vector2 = (lp as Node2D).global_position if lp != null else pos
		if _captions.push(tr(text), pos, priority, listener, tr("  (far)")):
			_rebuild_captions())
	if "--shotcaps" in OS.get_cmdline_user_args():
		# dev: napisy włączone na stałe i kilka przykładowych linii do zrzutu
		Settings.captions = true
		var tm := Timer.new()
		tm.wait_time = 1.0
		tm.autostart = true
		tm.timeout.connect(func() -> void:
			var at: Vector2 = (_player as Node2D).global_position if _player != null else Vector2.ZERO
			Audio.caption.emit("[Gunfire]", at + Vector2(140, 0), 1)
			Audio.caption.emit("[Low growl]", at + Vector2(-520, 0), 3)
			Audio.caption.emit("[Glass breaks]", at + Vector2(90, 0), 2))
		add_child(tm)

func _rebuild_captions() -> void:
	for c in _cap_box.get_children():
		_cap_box.remove_child(c)
		c.queue_free()
	for l in _captions.lines():
		var lab := UiTheme.label(String(l["text"]), 8, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		lab.modulate.a = float(l["alpha"])
		_cap_box.add_child(lab)

func _drive_captions(delta: float) -> void:
	if not Settings.captions:
		if _cap_card.visible:
			_captions.clear()
			_cap_card.visible = false
		return
	if _captions.tick(delta) or _cap_card.visible:
		_rebuild_captions()
	var any := _cap_box.get_child_count() > 0
	_cap_card.visible = any and not _result.visible
	if _cap_card.visible:
		_cap_card.reset_size()
		_cap_card.position = Vector2(size.x - _cap_card.size.x - MARGIN, size.y * 0.30)

## Podpowiedź dla nowego gracza: wąska karta nad paskiem kontekstowym (hints.gd decyduje, co i kiedy).
func _build_hint() -> void:
	_hint_card = _card(Vector2(MARGIN, MARGIN))
	_hint_card.visible = false
	var hb := UiTheme.panel_box()
	hb.border_color = Color(UiTheme.ACCENT, 0.45)
	hb.set_content_margin_all(7)
	_hint_card.add_theme_stylebox_override("panel", hb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	_hint_card.add_child(row)
	row.add_child(UiTheme.heading("TIP", 8, UiTheme.ACCENT))
	_hint_label = UiTheme.whisper(UiTheme.label("", 9, UiTheme.TEXT))
	_hint_label.custom_minimum_size = Vector2(330, 0)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_hint_label)

func _drive_hint(delta: float) -> void:
	# jeden komunikat naraz: ostrzeżenie o hałasie i krótkie noty mają pierwszeństwo — podpowiedź czeka (jej czas stoi)
	var busy := _warn.text != "" or _note_t > 0.0
	var text := _hints.update(0.0 if busy else delta, _player)
	_hint_card.visible = text != "" and not _result.visible and not busy
	if not _hint_card.visible:
		return
	_hint_label.text = text
	_hint_card.modulate.a = _hints.alpha
	_hint_card.reset_size()
	_hint_card.position = Vector2((size.x - _hint_card.size.x) * 0.5, size.y * HINT_Y)

func _build_result() -> void:
	_result = _card(Vector2(MARGIN, MARGIN))
	_result.custom_minimum_size = Vector2(240, 0)
	var rb := UiTheme.panel_box()
	rb.bg_color = Color(0.02, 0.025, 0.035, 0.95)
	rb.border_color = Color(UiTheme.OK, 0.5)
	rb.set_content_margin_all(12)
	_result.add_theme_stylebox_override("panel", rb)
	_result_box = rb
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_result.add_child(box)
	_result_title = UiTheme.heading("EXTRACTION COMPLETE", 16, UiTheme.OK, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_result_title)
	_result_sub = UiTheme.label("The squad made it out of the woods.", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_result_sub)
	_result_stats = GridContainer.new()
	_result_stats.columns = 2
	_result_stats.add_theme_constant_override("h_separation", 16)
	_result_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_result_stats)
	_result_players = GridContainer.new()                 # tabela graczy: zabójstwa / upadki / podniesienia (mission.player_stats)
	_result_players.columns = 4
	_result_players.add_theme_constant_override("h_separation", 14)
	_result_players.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_result_players)
	_xp_bar = Bar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 5)
	_xp_bar.fill = UiTheme.CALM
	box.add_child(_xp_bar)
	_xp_note = UiTheme.label("", 8, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_xp_note)
	_result_prompt = UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_result_prompt)
	if Settings.DEMO:
		# wersja demo: zachęta do listy życzeń (tekst do dopracowania razem ze stroną sklepu); pokazuje ją _fill_result
		var foot := VBoxContainer.new()
		foot.add_theme_constant_override("separation", 6)
		var rule := ColorRect.new()
		rule.color = Color(1, 1, 1, 0.10)
		rule.custom_minimum_size = Vector2(0, 1)
		foot.add_child(rule)
		foot.add_child(UiTheme.heading("THANKS FOR PLAYING THE DEMO", 8, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		foot.add_child(UiTheme.label("Wishlist DEAD AIR '87 on Steam — more zones, weapons and monsters are coming.", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		if Settings.STORE_URL != "":
			foot.add_child(UiTheme.label(tr("[%s]  Open the Steam page") % Actions.key("open_store"), 8, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(foot)
		_demo_footer = foot
	_result.visible = false

# ---------------------------------------------------------------- klatka

func _process(delta: float) -> void:
	_drive_music()
	var in_session := NoiseMgr.has_network()
	visible = in_session
	if not in_session:
		_session_t = 0.0
		_last_hp = -1
		_hints.reset()
		return
	_session_t += delta
	_blink += delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 1.8)
	_player = _find_local_player()

	_drive_noise()
	_drive_warning()
	_drive_squad(delta)
	_drive_status()
	_drive_mission()
	_drive_prompt()
	_drive_cards()
	_drive_hint(delta)
	_drive_captions(delta)
	_drive_chat(delta)
	_drive_tiers(delta)
	_drive_controls()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not _chat_edit.visible and NoiseMgr.has_network() and _chat != null:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help"):
		_controls_mode = 0 if _controls.visible else 1
	elif Settings.STORE_URL != "" and _result.visible and _demo_footer != null and _demo_footer.visible and event.is_action_pressed("open_store"):
		OS.shell_open(Settings.STORE_URL)

## Krótki komunikat środkowy (znika po `secs`).
func show_note(text: String, secs := 3.0) -> void:
	_note.text = text
	_note.modulate.a = 1.0
	_note_t = secs

func _drive_noise() -> void:
	_noise_card.visible = not NoiseMgr.safe_zone
	_safe_chip.visible = NoiseMgr.safe_zone
	if _note_t > 0.0:
		_note_t -= get_process_delta_time()
		_note.modulate.a = clampf(_note_t / 0.6, 0.0, 1.0)
	var lvl := _dev_noise if _dev_noise >= 0.0 else NoiseMgr.level          # dev: --shotnoise=N pokazuje wskaźnik przy zadanym poziomie
	_noise_val.text = "%d%%" % int(lvl)
	_noise_bar.value = lvl / 100.0
	var col := UiTheme.CALM
	if lvl >= NoiseMgr.AWAKE_THRESHOLD:
		col = UiTheme.DANGER.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_blink * 8.0)) * Settings.fx_mult())
	elif lvl >= NoiseMgr.UNEASY_THRESHOLD:
		col = UiTheme.ACCENT
	_noise_bar.fill = col
	var awake: bool = NoiseMgr.stalker_awake
	_noise_state.text = "HUNTED" if awake else ("UNEASY" if lvl >= NoiseMgr.UNEASY_THRESHOLD else "CALM")
	# ostrzeżenie pulsuje tylko w pościgu (HUNTED); „Reduce effects" zostawia stałą jasność
	_noise_state.modulate.a = lerpf(1.0, 0.55 + 0.45 * sin(_blink * 6.0), Settings.fx_mult()) if awake else 1.0
	_noise_state.add_theme_color_override("font_color", UiTheme.DANGER if awake else (UiTheme.ACCENT if lvl >= NoiseMgr.UNEASY_THRESHOLD else UiTheme.MUTED))
	_noise_val.add_theme_color_override("font_color", col if lvl >= NoiseMgr.UNEASY_THRESHOLD else UiTheme.TEXT)
	_noise_bar.queue_redraw()
	# pogoda misji (weather.gd): nazwa w kolorze pogody + skutki, żeby gracz widział, dlaczego hałas działa inaczej
	var wid := Weather.active_id()
	_weather_row.visible = wid != "" and not NightShift.active
	if _weather_row.visible:
		_weather_row.text = "%s  ·  %s" % [tr(Weather.name_of(wid)), tr(Weather.short_of(wid))]
		_weather_row.add_theme_color_override("font_color", Weather.color_of(wid))
	_charges.filled = NoiseMgr.overcharge_charges
	_charges.queue_redraw()
	_flares.filled = NoiseMgr.flares
	_flares.queue_redraw()
	var gk := Arsenal.selected_throwable()
	_gren.on = Throwables.KINDS[gk]["color"]
	_gren.count = int(Throwables.KINDS[gk]["max"])
	_gren.filled = Arsenal.get_throwable(gk)
	_gren.queue_redraw()
	_gren_name.text = "%s  [%s]" % [Throwables.KINDS[gk]["name"], Actions.key("throw_next")]
	_gren_name.add_theme_color_override("font_color", UiTheme.TEXT if Arsenal.get_throwable(gk) > 0 else UiTheme.MUTED)

func _on_xp_gained(amount: int, _reason: String) -> void:
	_xp_acc += amount
	_xp_t = 2.5

func _on_level_up(lv: int) -> void:
	var msg := "LEVEL %d" % lv
	if Profile.SLOT_LEVELS.has(lv):
		msg += "  —  perk slot unlocked"
	var names: Array = []
	for id in Profile.Perks.unlocked_at(lv):
		names.append(Profile.Perks.display_name(String(id)))
	if not names.is_empty():
		msg += "  —  new perks: " + ", ".join(names)
	show_note(msg, 5.0)
	Audio.play("ui_confirm", Audio.BUS_UI, -6.0)

func _drive_status() -> void:
	var lp := Profile.level_progress()
	_lv_label.text = "LV %d  ·  %d / %d XP" % [Profile.level(), int(lp[0]), int(lp[1])]
	if _xp_t > 0.0:
		_xp_t -= get_process_delta_time()
		_xp_feed.text = "+%d XP" % _xp_acc
		_xp_feed.modulate.a = clampf(_xp_t / 0.6, 0.0, 1.0)
		if _xp_t <= 0.0:
			_xp_acc = 0
	_session.text = _net_status()
	_scrap.visible = Scrap.enabled()
	_scrap_coin.visible = _scrap.visible
	_scrap.text = "%d%s" % [Scrap.bank, ("  +%d" % Scrap.loot) if Scrap.loot > 0 else ""]
	var sf := _scrap.get_theme_font("font")
	var tw := sf.get_string_size(_scrap.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x if sf != null else 30.0
	_scrap_coin.position = Vector2(_scrap.position.x + _scrap.size.x - tw - 12.0, _scrap.position.y + 1.0)
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if m != null:
		var secs := int(m.elapsed)
		_clock.text = "%02d:%02d" % [secs / 60, secs % 60]
	_gear_card.visible = _player != null
	if _player == null:
		return
	var hp: int = maxi(_player.hp, 0)
	if _last_hp >= 0 and hp < _last_hp:
		_hit_flash = 1.0
	_last_hp = hp
	_drive_weapons()
	var pct: float = _player.battery / _player.BATTERY_MAX
	_battery.value = pct
	_battery.fill = Color(1.0, 0.95, 0.72) if _player.flashlight else (UiTheme.DANGER if pct < 0.2 else UiTheme.MUTED)
	_battery.queue_redraw()
	_battery_note.text = ("ON %d%%" if _player.flashlight else "OFF %d%%") % int(pct * 100.0)
	_battery_note.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72) if _player.flashlight else UiTheme.MUTED)

## Karta broni: sloty z aktualnego zestawu, magazynek / zapas, ciepło lufy i koszt hałasu.
func _drive_weapons() -> void:
	var wc: Node = _player.weapons
	var cur: RefCounted = wc.cur()
	var names: Array = []
	for i in 3:
		names.append(wc.def_of_slot(i).name)
	names.append(Weapons.def(wc.melee_id).name)
	for i in _slots.size():
		var sel: bool = (i == wc.slot) if i < 3 else (wc.state == wc.State.MELEE)
		var key := str(i + 1) if i < 3 else "V"
		_slot_labels[i].text = key
		var d: RefCounted = wc.def_of_slot(i) if i < 3 else Weapons.def(wc.melee_id)
		_slot_icons[i].set_gun(int(d.gun_row), d.tracer_color, Color.WHITE if sel else Color(0.5, 0.52, 0.58, 0.9))
		_slots[i].tooltip_text = names[i]
		_slots[i].add_theme_stylebox_override("panel", _slot_on if sel else _slot_off)
		_slot_labels[i].add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.MUTED)
	_ammo_name.text = cur.name + ("  ·  BURST" if wc.is_burst(cur) else ("  ·  AUTO" if cur.burst_size > 0 else ""))
	_gun_main.set_gun(int(cur.gun_row), cur.tracer_color, Color.WHITE)
	var mag: int = wc.mag_of(cur.id)
	var note := ""
	var col := UiTheme.TEXT
	if not cur.uses_ammo():
		_ammo_mag.text = "—"
		_ammo_res.text = ""
	elif cur.infinite:
		_ammo_mag.text = str(mag)
		_ammo_res.text = "/ ∞"
	else:
		var res := Arsenal.get_reserve(cur.id)
		_ammo_mag.text = str(mag)
		_ammo_res.text = "/ %d" % res
		if mag <= 0 and res <= 0:
			col = UiTheme.DANGER
			note = "NO AMMO"
		elif mag <= maxi(1, int(cur.mag * 0.25)):
			col = UiTheme.ACCENT if mag > 0 else UiTheme.DANGER
	if wc.state == wc.State.RELOAD:
		note = tr("RELOADING %d%%") % int(wc.reload_progress() * 100.0)
	elif wc.state == wc.State.CHARGE:
		note = tr("CHARGING %d%%") % int(wc.charge * 100.0)
	elif note == "" and cur.uses_ammo() and mag <= 0 and wc.ammo_enabled:
		note = tr("[%s] RELOAD") % Actions.key("reload")
	_ammo_mag.add_theme_color_override("font_color", col)
	_ammo_note.text = note
	# pasek przeładowania / ładowania szyny pod liczbami
	_reload_bar.value = wc.reload_progress() if wc.state == wc.State.RELOAD else (wc.charge if wc.state == wc.State.CHARGE else 0.0)
	_reload_bar.queue_redraw()
	_ammo_note.add_theme_color_override("font_color", UiTheme.ACCENT if note != "" and col != UiTheme.DANGER else col)
	var heat: float = wc.heat_of(cur.id)
	_heat_bar.value = heat if cur.n_max > cur.n_min else 0.0
	_heat_bar.fill = Color(0.62, 0.72, 0.78).lerp(Color(1.0, 0.3, 0.2), clampf(heat * 1.15, 0.0, 1.0))
	_heat_bar.queue_redraw()
	if cur.is_melee():
		_heat_note.text = ""
	elif cur.n_max > cur.n_min:
		_heat_note.text = "%.1f→%.1f" % [cur.noise(heat), cur.n_max]
	else:
		_heat_note.text = "%.1f" % cur.noise(0.0)
	_gear_card.reset_size()
	# pasek broni: środek ekranu, ale nie na karcie drużyny; gdy się nie mieści (duży HUD) — nad kartą drużyny
	var gw := _gear_card.size.x
	var gh := _gear_card.size.y
	var gx := maxf((size.x - gw) * 0.5, _squad_card.position.x + _squad_card.size.x + MARGIN)
	var gy := size.y - BOTTOM_PAD - gh
	if gx + gw > size.x - MARGIN:
		gx = maxf((size.x - gw) * 0.5, MARGIN)
		gy = _squad_card.position.y - gh - 4.0
	_gear_card.position = Vector2(gx, gy)

## Ostrzeżenie przed karą (GDD §8.1): niepokój ZANIM ON się obudzi.
func _drive_warning() -> void:
	var awake: bool = NoiseMgr.stalker_awake
	var uneasy: bool = (not awake) and NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD
	if awake:
		_warn.text = "HE HEARS YOU"
		_warn.add_theme_color_override("font_color", UiTheme.DANGER)
		_warn.modulate.a = lerpf(1.0, 0.6 + 0.4 * sin(_blink * 6.0), Settings.fx_mult())
		_warn_sub.text = "Go quiet until the noise drops below 30% — or use Q to lure him off"
	elif uneasy:
		_warn.text = "SOMETHING IS LISTENING…"
		_warn.add_theme_color_override("font_color", UiTheme.ACCENT)
		_warn.modulate.a = lerpf(0.85, 0.55 + 0.3 * sin(_blink * 3.0), Settings.fx_mult())
		_warn_sub.text = "Above 60% noise he wakes up"
	else:
		_warn.text = ""
		_warn_sub.text = ""
	_warn_sub.modulate.a = _warn.modulate.a
	if awake and not _warn_was:
		Audio.play("warn_pulse", Audio.BUS_UI, -12.0)
	_warn_was = awake

func _drive_mission() -> void:
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if m == null:
		_obj_card.visible = false
		_result.visible = false
		return
	var boss := get_tree().get_first_node_in_group("boss")
	_obj_card.visible = m.phase != Mission.Phase.SUCCESS and m.phase != Mission.Phase.FAILED
	_obj_caption.text = m.objective_caption()
	_obj_caption.add_theme_color_override("font_color", UiTheme.DANGER if m.phase == Mission.Phase.BOSS else (UiTheme.OK if m.phase == Mission.Phase.EXTRACT else UiTheme.ACCENT))
	_obj_text.text = m.objective_text()
	_obj_hint.text = m.objective_hint()
	_obj_hint.visible = _obj_hint.text != ""
	var in_hub: bool = m.kind == "hub"
	_ready_pips.visible = in_hub
	if in_hub:
		var main_n := get_tree().current_scene
		var total: int = maxi(1, int(main_n.get("hub_total")))
		_ready_pips.count = total
		_ready_pips.filled = int(main_n.get("hub_ready_n"))
		_ready_pips.custom_minimum_size = Vector2(float(total) * 11.0 - 2.0, 9.0)
		_ready_pips.queue_redraw()
	_boss_row.visible = boss != null and m.phase == Mission.Phase.BOSS
	if _boss_row.visible:
		_boss_bar.value = boss.hp / maxf(1.0, boss.max_hp)
		_boss_bar.queue_redraw()
		var bname: String = String(boss.get("boss_name")) if boss.get("boss_name") != null else "THE VEIN — MOTHER OF NESTS"
		_boss_name.text = bname + ("   ·   ENRAGED" if boss.phase >= 2 else "")
	# karta celu: wyśrodkowana, szerokość wg treści
	_obj_card.reset_size()
	_obj_card.position = Vector2((size.x - _obj_card.size.x) * 0.5, MARGIN)
	# ostrzeżenie zawsze pod kartą celu (karta bossa jest wyższa)
	var wy := maxf(size.y * WARN_Y, _obj_card.position.y + _obj_card.size.y + 10.0)
	_warn.position.y = wy
	_warn_sub.position.y = wy + 20.0

	var show_result: bool = m.phase == Mission.Phase.SUCCESS or m.phase == Mission.Phase.FAILED
	var just_shown: bool = show_result and not _result.visible
	if just_shown:
		_fill_result(m)
		UiTheme.fade_in(_result)
	_result.visible = show_result
	if show_result:
		_fill_players(m)
	if show_result and _result_xp_val != null and is_instance_valid(_result_xp_val):
		_drive_xp(get_process_delta_time())

func _fill_result(m: Node) -> void:
	for c in _result_stats.get_children():
		_result_stats.remove_child(c)
		c.free()
	var rows: Array
	var prompt := "Continue"
	if NightShift.active:
		rows = _shift_result(m)
		prompt = "New shift" if (m.phase == Mission.Phase.FAILED or m.shift_complete()) else "Next mission"
	else:
		if m.kind == "tags":
			_style_result("EXTRACTION COMPLETE", "The patrol's tags are with the squad — time to go home.", UiTheme.OK)
			rows = [["Time", _mmss(m.elapsed)], ["Dog tags found", "%d / %d" % [m.goal_total, m.goal_total]],
				["Hidden stashes", ("%d / %d" % [m.stashes_found, m.stash_total]) + ("  — bonus" if m.side_done() else "")],
				["Squad downs", str(m.downs)], ["Attempt", "#%d" % m.attempts], ["Scrap banked", "+%d" % Scrap.last_gain]]
		elif m.kind == "boss":
			_style_result("THE LEECH IS DEAD", "The hall is quiet again — only the water drips.", UiTheme.OK)
			rows = [["Time", _mmss(m.elapsed)], ["The Leech", "slain"], ["Squad downs", str(m.downs)], ["Attempt", "#%d" % m.attempts], ["Scrap banked", "+%d" % Scrap.last_gain]]
		elif m.kind == "generators":
			_style_result("EXTRACTION COMPLETE", "The broadcast is over — the squad is out.", UiTheme.OK)
			rows = [["Time", _mmss(m.elapsed)], ["Generators started", "%d / %d" % [m.goal_total, m.goal_total]],
				["Stealth (Attention < %d)" % int(m.STEALTH_CAP), "kept" if m.stealth_ok() else "lost  (peak %d)" % int(m.peak_noise)],
				["Squad downs", str(m.downs)], ["Attempt", "#%d" % m.attempts], ["Scrap banked", "+%d" % Scrap.last_gain]]
		else:
			_style_result("EXTRACTION COMPLETE", "The squad made it out of the woods.", UiTheme.OK)
			rows = [["Time", _mmss(m.elapsed)], ["Nests destroyed", "%d / %d" % [m.nests_total, m.nests_total]],
				["The Vein", "slain"], ["Squad downs", str(m.downs)], ["Attempt", "#%d" % m.attempts], ["Scrap banked", "+%d" % Scrap.last_gain]]
	for row in rows:
		_result_stats.add_child(UiTheme.label(row[0], 9, UiTheme.MUTED))
		_result_stats.add_child(UiTheme.label(row[1], 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	_result_stats.add_child(UiTheme.label("XP", 9, UiTheme.MUTED))
	_result_xp_val = UiTheme.label("", 9, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)      # uzupełniany co klatkę — XP przychodzi od serwera chwilę po zmianie fazy
	_result_stats.add_child(_result_xp_val)
	_result_prompt.text = "[%s]  %s" % [Actions.key("restart"), tr(prompt)] if multiplayer.is_server() else "Waiting for the host to continue…"
	if _demo_footer != null:
		# stopka dema: koniec kampanii (ostatnia misja Strefy I) albo koniec serii Nocnego Dyżuru
		var lvl := get_tree().get_first_node_in_group("level")
		var last: bool = lvl != null and lvl.map_id == String(lvl.CAMPAIGN[lvl.CAMPAIGN.size() - 1])
		_demo_footer.visible = (m.phase == Mission.Phase.FAILED or m.shift_complete()) if NightShift.active else last
	_result.reset_size()
	_result.position = (size - _result.size) * 0.5

## XP z misji „wlewa się” w pasek poziomu (1,6 s; przy „Reduce effects” od razu): licznik rośnie, a przy awansie pasek się
## przelewa i pojawia się „LEVEL UP”. XP przychodzi od serwera chwilę po zmianie fazy — zmiana wartości zaczyna animację od nowa.
func _drive_xp(delta: float) -> void:
	var end_xp: int = Profile.xp
	var start_xp: int = maxi(0, end_xp - Profile.last_mission_xp)
	var key := Vector2i(start_xp, end_xp)
	if key != _xp_key:
		_xp_key = key
		_xp_anim = 0.0 if Settings.fx_mult() > 0.0 else 1.0
	_xp_anim = minf(1.0, _xp_anim + delta / 1.6)
	var e: float = 1.0 - pow(1.0 - _xp_anim, 3.0)
	var shown: int = start_xp + int(round(float(end_xp - start_xp) * e))
	var lv: int = Profile.level_of(shown)
	var lo: int = Profile.xp_for_level(lv)
	var hi: int = Profile.xp_for_level(lv + 1)
	_xp_bar.value = float(shown - lo) / float(maxi(1, hi - lo))
	_xp_bar.queue_redraw()
	var gained: int = int(round(float(Profile.last_mission_xp) * e))
	var xt := "+%d  ·  LV %d" % [gained, lv]
	if _result_xp_val.text != xt:
		_result_xp_val.text = xt
		_result.reset_size()
	var leveled: bool = Profile.level_of(end_xp) > Profile.level_of(start_xp)
	var note: String = (tr("LEVEL UP — LV %d") % Profile.level_of(end_xp)) if (leveled and _xp_anim >= 1.0) else ""
	if _xp_note.text != note:
		_xp_note.text = note

## Tabela graczy na karcie wyniku (odświeżana, gdy statystyki od serwera się zmienią).
func _fill_players(m: Node) -> void:
	var sig: int = hash(str(m.player_stats))
	if sig == _stats_sig:
		return
	_stats_sig = sig
	for c in _result_players.get_children():
		_result_players.remove_child(c)
		c.free()
	var ids: Array = m.player_stats.keys()
	ids.sort()
	_result_players.visible = not ids.is_empty()
	if ids.is_empty():
		return
	for h in ["", "KILLS", "DOWNS", "REVIVED"]:
		_result_players.add_child(UiTheme.label(h, 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT if h != "" else HORIZONTAL_ALIGNMENT_LEFT))
	for id in ids:
		var st: Dictionary = m.player_stats[id]
		var mine: bool = int(id) == NoiseMgr.local_id()
		var col: Color = UiTheme.ACCENT if mine else UiTheme.TEXT
		_result_players.add_child(UiTheme.label(("%s  (you)" % st["name"]) if mine else String(st["name"]), 9, col))
		for k in ["kills", "downs", "revived"]:
			_result_players.add_child(UiTheme.label(str(int(st[k])), 9, col, HORIZONTAL_ALIGNMENT_RIGHT))
	_result.reset_size()
	_result.position = (size - _result.size) * 0.5

func _mmss(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]

func _style_result(title: String, sub: String, col: Color) -> void:
	_result_title.text = title
	_result_title.add_theme_color_override("font_color", col)
	_result_sub.text = sub
	_result_box.border_color = Color(col, 0.5)

## Karta wyniku w Nocnym Dyżurze: ukończona misja, koniec serii (porażka) albo cała seria.
func _shift_result(m: Node) -> Array:
	var best_c: int = Settings.shift_best_cleared
	var best_t: float = Settings.shift_best_time
	var rows: Array
	if m.phase == Mission.Phase.FAILED:
		_style_result("SHIFT OVER", "The night took the squad.", UiTheme.DANGER)
		rows = [["Missions cleared", "%d / %d" % [m.shift_cleared, NightShift.MISSIONS]], ["Series time", _mmss(m.shift_time)],
			["Squad downs", str(m.shift_downs)], ["Best", "%d / %d" % [best_c, NightShift.MISSIONS]]]
	elif m.shift_complete():
		_style_result("SHIFT COMPLETE", "The whole night, survived.", UiTheme.OK)
		rows = [["Series time", _mmss(m.shift_time)], ["Squad downs", str(m.shift_downs)],
			["Best time", _mmss(best_t) if best_t > 0.0 else "—"]]
	else:
		_style_result("MISSION %d CLEARED" % NightShift.stage, "Night Shift — the next one is harder.", UiTheme.OK)
		rows = [["Mission time", _mmss(m.elapsed)], ["Missions cleared", "%d / %d" % [m.shift_cleared, NightShift.MISSIONS]],
			["Series time", _mmss(m.shift_time)], ["Squad downs", str(m.shift_downs)]]
	if m.shift_record:
		rows.append(["", "NEW RECORD"])
	return rows

## Karta informacyjna: tytuł, podpis, siatka wierszy i opis. `cols` = liczba kolumn siatki (2 = etykieta + wartość).
## `paper`: karta przy obiekcie świata — papier z tekstem tuszem i ogonkiem wskazującym obiekt (zamiast ciemnego panelu HUD).
func _make_info_card(width: float, cols: int, paper := false) -> Dictionary:
	var card: PanelContainer
	if paper:
		var tp := TailPanel.new()
		tp.tail = true
		tp.tail_color = UiTheme.PAPER_EDGE
		tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tp.position = Vector2(MARGIN, MARGIN)
		tp.add_theme_stylebox_override("panel", UiTheme.paper_box())
		add_child(tp)
		card = tp
	else:
		card = _card(Vector2(MARGIN, MARGIN))
	card.custom_minimum_size = Vector2(width, 0)
	card.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var title := UiTheme.heading("", 16 if paper else 8, UiTheme.INK_ACCENT if paper else UiTheme.ACCENT)
	if paper:
		title.add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	var tag := UiTheme.label("", 8, UiTheme.INK_MUTED if paper else UiTheme.MUTED)
	if paper:
		tag.add_theme_constant_override("outline_size", 0)
	box.add_child(tag)
	if paper:
		var r := ColorRect.new()
		r.color = Color(UiTheme.INK, 0.35)
		r.custom_minimum_size = Vector2(0, 1)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	else:
		_hr(box)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 1)
	box.add_child(grid)
	var text := UiTheme.label("", 8, UiTheme.INK if paper else UiTheme.TEXT)
	if paper:
		text.add_theme_constant_override("outline_size", 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(width - 26.0, 0)
	box.add_child(text)
	return {"card": card, "title": title, "tag": tag, "grid": grid, "text": text, "cols": cols, "paper": paper}

func _fill_info(c: Dictionary, title: String, tag: String, rows: Array, text: String, accent: Color) -> void:
	var paper: bool = bool(c.get("paper", false))
	(c["title"] as Label).text = title
	(c["title"] as Label).add_theme_color_override("font_color", UiTheme.INK_ACCENT if paper else accent)
	if paper:
		(c["title"] as Label).add_theme_font_size_override("font_size", 16 if title.length() <= 12 else 8)   # długie tytuły (odprawa) mniejszą czcionką
	(c["tag"] as Label).text = tag
	(c["tag"] as Label).visible = tag != ""
	(c["text"] as Label).text = text
	(c["text"] as Label).visible = text != ""
	var grid: GridContainer = c["grid"]
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.free()
	for r in rows:
		for i in (r as Array).size():
			if r[i] is Color:
				var sw := Swatch.new()
				sw.col = r[i]
				grid.add_child(sw)
				continue
			var gl := UiTheme.label(String(r[i]), 9, (UiTheme.INK_MUTED if i == 0 else UiTheme.INK) if paper else (UiTheme.MUTED if i == 0 else UiTheme.TEXT))
			if paper:
				gl.add_theme_constant_override("outline_size", 0)
			grid.add_child(gl)
	(c["card"] as Control).reset_size()

## Karty: statystyki broni w zasięgu [E] (nad paskiem kontekstowym) i odprawa przy tablicy (u góry, pod kartą celu).
func _drive_cards() -> void:
	# --- broń na stojaku w zasięgu [E]: karta tylko w kryjówce (w misjach zasłaniałaby grę; tam wystarcza pasek „[E] Take…")
	var it: Node2D = null
	if NoiseMgr.safe_zone and _player != null and not _player.dead:
		it = _player.weapons.nearby_weapon_item()
	var wid: int = int(it.arg) if it != null else -1
	var lvl_i := get_tree().get_first_node_in_group("level")
	var locked: bool = it != null and lvl_i != null and lvl_i.is_locked_item(it)
	var key := wid + (1000 if locked else 0)
	if key != _item_id:
		_item_id = key
		if wid >= 0:
			var d: RefCounted = Weapons.def(wid)
			var notes: Array = Codex.WEAPON_TEXT.get(String(d.key), ["", ""])
			var tag: String = Codex._slot_name(d)
			if locked:
				tag += "  ·  LOCKED — " + Scrap.lock_text(wid)
			_fill_info(_item, String(d.name), tag, Codex._weapon_stats(d), String(notes[0]), d.tracer_color)
	var ic: Control = _item["card"]
	ic.visible = it != null
	if ic.visible:
		# nad stojakiem: punkt tuż nad deską w świecie → ekran (macierz kamery, z zoomem) → jednostki HUD; karta nie zasłania gracza ani broni
		var top: Vector2 = get_viewport().get_canvas_transform() * (it.global_position + Vector2(0, -42))
		var hx := top.x / scale.x
		var hy := top.y / scale.y
		ic.position = Vector2(clampf(hx - ic.size.x * 0.5, 6.0, maxf(6.0, size.x - ic.size.x - 6.0)), maxf(6.0, hy - ic.size.y - 12.0))
	# --- odprawa przy tablicy
	var near_board := false
	var board: Node2D = null
	for b in get_tree().get_nodes_in_group("board"):
		if b.local_in_range:
			near_board = true
			board = b
			break
	var bc: Control = _brief["card"]
	bc.visible = near_board
	if near_board:
		var main := get_tree().current_scene
		var target := String(main.get("after_hub")) if main != null else ""
		var lvl := get_tree().get_first_node_in_group("level")
		if target != _brief_id and lvl != null:
			_brief_id = target
			_fill_brief(lvl.briefing(target))
		# nad tablicą (jak karta broni), więc nie zasłania stojącego przy niej gracza
		var btop: Vector2 = get_viewport().get_canvas_transform() * (board.global_position + Vector2(0, -46))
		bc.position = Vector2(clampf(btop.x / scale.x - bc.size.x * 0.5, 6.0, maxf(6.0, size.x - bc.size.x - 6.0)), maxf(6.0, btop.y / scale.y - bc.size.y - 12.0))
	_drive_radio()

## Prognoza z radiostacji (weather.gd): nazwa pogody, jej plusy i minusy, tytuł następnej misji.
func _drive_radio() -> void:
	var near := false
	var rset: Node2D = null
	for rs in get_tree().get_nodes_in_group("radio_set"):
		if rs.local_in_range:
			near = true
			rset = rs
			break
	var rc: Control = _radio["card"]
	rc.visible = near
	if not near:
		return
	var main := get_tree().current_scene
	var target := String(main.get("after_hub")) if main != null else ""
	var key := "%s|%s" % [Weather.forecast, target]
	if key != _radio_key:
		_radio_key = key
		var lvl := get_tree().get_first_node_in_group("level")
		var info: Dictionary = lvl.briefing(target) if lvl != null and target != "" else {}
		var tag := ("Next: " + String(info["title"])) if not info.is_empty() else "Next mission"
		var id: String = Weather.forecast
		_fill_info(_radio, "WEATHER FORECAST", tag, [[Weather.color_of(id), Weather.name_of(id)]], Weather.text_of(id), UiTheme.ACCENT)
	var rtop: Vector2 = get_viewport().get_canvas_transform() * (rset.global_position + Vector2(0, -40))
	rc.position = Vector2(clampf(rtop.x / scale.x - rc.size.x * 0.5, 6.0, maxf(6.0, size.x - rc.size.x - 6.0)), maxf(6.0, rtop.y / scale.y - rc.size.y - 12.0))

func _fill_brief(info: Dictionary) -> void:
	if info.is_empty():
		_fill_info(_brief, "BRIEFING", "No orders yet", [], "", UiTheme.ACCENT)
		return
	var rows: Array = []                          # [kolor znacznika, nazwa, liczba, opis]
	var counts: Dictionary = info["counts"]
	var kinds: Array = counts.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	for k in kinds:
		for e in Codex.ENEMIES:
			if e[0] == k:
				rows.append([Codex.Enemy.KINDS[k]["color"], String(e[3]), "x%d" % int(counts[k]), String(e[4])])
	if bool(info["stalker"]):
		rows.append([Color(0.2, 0.2, 0.24), "STALKER", "x1", "Cannot be killed"])
	if int(info.get("tags", 0)) > 0:
		rows.append([Color(0.62, 0.85, 1.0), "DOG TAG", "x%d" % int(info["tags"]), "Mission objective"])
	if int(info.get("stashes", 0)) > 0:
		rows.append([Color(0.95, 0.75, 0.35), "STASH", "x%d" % int(info["stashes"]), "Side goal — hidden"])
	if int(info["nests"]) > 0:
		rows.append([Color(0.85, 0.4, 0.35), "NEST", "x%d" % int(info["nests"]), "Mission objective"])
	if bool(info["boss"]):
		rows.append([Color(0.7, 0.25, 0.3), String(info.get("boss_name", "THE VEIN")), "x1", "Boss — Mother of Nests" if String(info.get("boss_name", "")) != "THE LEECH" else "Boss — hides under water"])
	if rows.size() > BRIEF_ROWS:                  # krótka lista: karta nad tablicą ma się mieścić nad graczem
		var extra := rows.size() - (BRIEF_ROWS - 1)
		rows = rows.slice(0, BRIEF_ROWS - 1)
		rows.append([Color(0, 0, 0, 0), "+%d more" % extra, "", "see the bestiary (Esc)"])
	_fill_info(_brief, "BRIEFING  ·  " + String(info["title"]), "", rows, String(info["brief"]), UiTheme.ACCENT)

## Czy lokalny gracz stoi przy ławie warsztatu (kryjówka) i panel jest zamknięty.
func _near_workshop() -> bool:
	for w in get_tree().get_nodes_in_group("workshop"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Pijawka trzymająca teraz kogoś (chwyt, QTE) albo null.
## Boss z trwającą falą przypływu (zapowiedź albo wysoka woda) — pasek ostrzeżenia w HUD.
func _tide_boss() -> Node:
	var b := get_tree().get_first_node_in_group("boss")
	if b != null and b.get("surge_state") != null and (String(b.surge_state) == "warn" or String(b.surge_state) == "on"):
		return b
	return null

func _grab_boss() -> Node:
	var b := get_tree().get_first_node_in_group("boss")
	if b != null and b.get("grab_victim_id") != null and int(b.grab_victim_id) != 0:
		return b
	return null

## Generator, przy którym stoi lokalny gracz (misja 1.2) albo null.
func _near_generator() -> Node:
	for g in get_tree().get_nodes_in_group("generators"):
		if g.local_in_range:
			return g
	return null

## Pasek kontekstowy: wipe, leżenie, podnoszenie, ekstrakcja.
func _drive_prompt() -> void:
	var text := ""
	var prog := -1.0
	var col := UiTheme.TEXT
	_center.text = ""
	_center_sub.text = ""
	var wipe_left: float = get_tree().current_scene.get("wipe_left") if get_tree().current_scene else 0.0
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	var gen := _near_generator()
	var car := get_tree().get_first_node_in_group("handcar")
	var grab_boss := _grab_boss()
	var tide_boss := _tide_boss()
	if wipe_left > 0.0:
		_center.text = "SQUAD DOWN"
		_center_sub.text = ("Extraction failed — the shift ends in %d" if NightShift.active else "Extraction failed — restarting the mission in %d") % ceili(wipe_left)
	elif grab_boss != null and _player != null and not _player.dead:
		# chwyt Pijawki (QTE drużyny): ofiara i koledzy widzą ten sam pasek — ile obrażeń jeszcze brakuje do uwolnienia
		var mine: bool = int(grab_boss.grab_victim_id) == int(_player.player_id)
		text = ("GRABBED — shoot the leech to break free  ·  %.0fs" if mine else "Teammate grabbed — shoot the leech!  ·  %.0fs") % float(grab_boss.grab_time_left)
		prog = float(grab_boss.grab_progress)
		col = UiTheme.DANGER
	elif tide_boss != null and _player != null and not _player.dead:
		if String(tide_boss.surge_state) == "warn":
			text = "THE TIDE IS RISING — climb to the high catwalks!"
			prog = clampf(float(tide_boss._surge_t) / (float(tide_boss.SURGE_WARN) * Difficulty.m("boss_tide")), 0.0, 1.0)
			col = UiTheme.ACCENT
		else:
			text = "FLOODED — stay on the high catwalks"
			col = UiTheme.DANGER
	elif _player != null and _player.dead:
		if _player.revive_progress > 0.0:
			text = "Being revived…"
			prog = _player.revive_progress
			col = UiTheme.OK
		else:
			text = "You're down — a teammate can revive you (bleeding out in %ds)" % ceili(_player.bleed_left)
			prog = _player.bleed_left / _player.bleed_time()
			col = UiTheme.DANGER
	elif _player != null and _player.revive_hint() != "":
		text = _player.revive_hint()
		col = UiTheme.OK
	elif _player != null and _player.gear_text != "":
		text = _player.gear_text                     # narzędzia (lewy Alt): apteczka, defibrylator, skaner — podpowiedź albo trwające użycie
		prog = _player.gear_progress
		col = UiTheme.OK if prog > 0.0 else UiTheme.ACCENT
	elif car != null and car.local_state != "" and _player != null:
		match String(car.local_state):
			"nopower":
				text = "The handcar has no power — start all the generators"
				col = UiTheme.MUTED
			"near":
				text = "Step onto the handcar"
				col = UiTheme.ACCENT
			"aboard":
				text = Actions.fmt(tr("Hold [{interact}]  Pump  (you can't shoot while pumping)"))
				col = UiTheme.ACCENT
			"pumping":
				text = Actions.fmt(tr("Pumping…  release [{interact}] to shoot"))
				col = UiTheme.OK
	elif gen != null and _player != null and _player.weapons.nearby_weapon_item() == null:
		if gen.progress > 0.0:
			text = "Starting the generator…"
			prog = gen.progress
			col = UiTheme.OK
		else:
			text = Actions.fmt(tr("Hold [{interact}]  Start the generator  (loud)"))
			col = UiTheme.ACCENT
	elif _near_workshop():
		text = tr("[%s]  Workshop  ·  SCRAP %d") % [Actions.key("interact"), Scrap.bank]
		col = UiTheme.ACCENT
	elif _player != null and _player.weapons.nearby_weapon_item() != null:
		var it: Node2D = _player.weapons.nearby_weapon_item()
		var nd: RefCounted = Weapons.def(it.arg)
		var lvl_p := get_tree().get_first_node_in_group("level")
		if lvl_p != null and lvl_p.is_locked_item(it):
			text = tr("LOCKED  ·  %s") % Scrap.lock_text(it.arg)
			col = UiTheme.MUTED
		else:
			var wc2: Node = _player.weapons
			var swap_out: String = Weapons.def(wc2.loadout[wc2.slot if wc2.slot < 2 else 0]).name if nd.slot == Weapons.Slot.PRIMARY else Weapons.def(wc2.melee_id).name
			var take_key := Actions.key("interact")
			text = tr("[%s]  Take %s  (drops %s)") % [take_key, nd.name, swap_out] if not wc2.carries(it.arg) else tr("[%s]  Take ammo for %s") % [take_key, nd.name]
			col = UiTheme.ACCENT
	elif m != null and m.phase == Mission.Phase.EXTRACT:
		var st: Dictionary = m.local_extract_state()
		if st.get("inside", false):
			if m.extract_progress > 0.0:
				text = "EVACUATING…"
				prog = m.extract_progress
				col = UiTheme.OK
			else:
				text = "Hold here — the whole squad must reach the flare"
				col = UiTheme.ACCENT
	if wipe_left <= 0.0 and m != null and m.banner_visible() and not (bool(_item["card"].visible) or bool(_brief["card"].visible) or bool(_radio["card"].visible)):
		# tytuł misji w pierwszych sekundach; w Nocnym Dyżurze także zasady serii
		var lvl := get_tree().get_first_node_in_group("level")
		var lines: Array = []
		if NightShift.active:
			lines.append(String(lvl.title) if lvl != null else "")
			for id in NightShift.mods:
				lines.append("%s — %s" % [NightShift.MODS[id]["name"], NightShift.MODS[id]["text"]])
			if NightShift.stage > 1:
				lines.append("Enemies +%d%% HP" % int(round(NightShift.HP_STEP * float(NightShift.stage - 1) * 100.0)))
			elif NightShift.mods.is_empty():
				lines.append("The first mission — no modifiers")
			_center.text = NightShift.title()
		elif lvl != null and not (lvl.radio as Array).is_empty():
			_center.text = String(lvl.title)
			for rl in lvl.radio:
				lines.append(String(rl))
		else:
			_center.text = String(lvl.title) if lvl != null else ""
			lines.append(m.objective_text())
		if not NightShift.active and Weather.active_id() != "":
			lines.append("WEATHER — %s: %s" % [Weather.name_of(Weather.active_id()), Weather.text_of(Weather.active_id())])
		_center_sub.text = "\n".join(lines)
	# ostatnia transmisja patrolu w finale misji 1.1 (zamiast baneru tytułu)
	if wipe_left <= 0.0 and m != null and m.finale_radio_line() != "":
		_center.text = "PATROL SEVEN — RADIO"
		_center_sub.text = m.finale_radio_line()
	_prompt_card.visible = text != ""
	if _prompt_card.visible:
		_prompt.text = text
		_prompt.add_theme_color_override("font_color", col)
		_prompt_bar.visible = prog >= 0.0
		_prompt_bar.value = prog
		_prompt_bar.fill = col
		_prompt_bar.queue_redraw()
		_prompt_card.reset_size()
		_prompt_card.position = Vector2((size.x - _prompt_card.size.x) * 0.5, size.y * PROMPT_Y)

func _drive_controls() -> void:
	var show := _session_t < CONTROLS_SHOW_S if _controls_mode < 0 else _controls_mode == 1
	_controls.visible = show
	_f1.visible = not show

## Muzyka adaptacyjna: 4 warstwy po progach Uwagi (GDD §13).
func _drive_music() -> void:
	var lvl := NoiseMgr.level
	var layer := 0
	if lvl >= 20.0:
		layer = 1
	if lvl >= 45.0:
		layer = 2
	if lvl >= 70.0:
		layer = 3
	if layer != _music_layer:
		_music_layer = layer
		Audio.music_set_layer(layer)

## Winieta: błysk po trafieniu, puls przy 1 HP, mrok przy leżeniu.
func _draw() -> void:
	var a := _hit_flash * 0.55 * lerpf(0.4, 1.0, Settings.fx_mult())
	if _player != null:
		if _player.dead:
			a = maxf(a, 0.45)
		elif _player.hp == 1:
			a = maxf(a, 0.18 + 0.1 * sin(_blink * 4.0))
	if a <= 0.01:
		return
	var sz := size
	var steps := 10
	for i in steps:
		var t := float(i) / steps
		var w := 4.0 + i * 5.0
		var c := Color(0.55, 0.0, 0.03, a * (1.0 - t) * 0.35)
		draw_rect(Rect2(0, 0, sz.x, w), c)
		draw_rect(Rect2(0, sz.y - w, sz.x, w), c)
		draw_rect(Rect2(0, 0, w, sz.y), c)
		draw_rect(Rect2(sz.x - w, 0, w, sz.y), c)

func _find_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		# boty też mają autorytet hosta — HUD pokazuje tylko człowieka
		if not p.is_bot and p.is_multiplayer_authority():
			return p
	return null

func _net_status() -> String:
	var diff: String = Difficulty.level_name()
	if not NoiseMgr.has_network():
		return "SOLO  ·  %s" % diff
	var humans := 0
	var bots := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			bots += 1
		else:
			humans += 1
	var who := "HOST" if multiplayer.is_server() else "CLIENT"
	return "%s  ·  %d/4 players%s  ·  %s" % [who, humans, ("  +%d AI" % bots) if bots > 0 else "", diff]
