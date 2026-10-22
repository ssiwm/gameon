extends Control
## In-game HUD (English). Built in code on the shared theme (ui_theme.gd).
##
## Skala: cały HUD jest rysowany w 70% (UI_SCALE) — węzeł ma `scale` i logiczny rozmiar
## viewport / UI_SCALE (≈914×514), więc układ liczy się względem `size`, nie stałych 640×360.
## Layout — HUD bez ramek (HUD_PLAN.md): czytelność dają dwa gradienty (góra, dół), a ważne rzeczy stoją w rogach:
##   top-left    noise: small VU meter, one NOISE line (safe room: SAFE), mission weather under it
##   top-centre  map view (hud_minimap.gd): ±38 m window of the level grid with fog (only tiles the squad has seen), goal / exit /
##               teammates / downed markers with distance; under it the boss bar
##               and the objective text, which shows for TOAST_S after the goal changes (always in the safe room, F1 recalls it)
##   top-right   mission title, difficulty · clock, scrap; level + XP bar only for a moment after gaining XP
##   bottom-left squad life: own row on top (life segments, ECG, CRITICAL / DOWN), teammates under it (slot-coloured diamond,
##               name (BOT), thin life segments, DOWN / REVIVING state + bar)
##   bottom-centre weapon as a 3D model (art/hud, tools/bake_hud_icons.gd): magazine / team reserve, name, mode and shot cost, thin reload
##               and barrel-heat lines; thumbnails of slots 1–4 appear for 2.5 s after a weapon change; context prompt sits above it
##   bottom-right gear as four 3D models: LURE (Q), FLARE (F), selected item (ALT), flashlight (L, battery line); count and key under each
##   centre      messages (message_view.gd): alerts, toasts, title card, tips; wipe
##   bottom      controls strip — only for beginners in the first seconds (TOAST_LEVEL_MAX), F1 toggles
##   full screen damage vignette; result card after extraction
## Adaptive music and the warning sting are driven from here (GDD §13).

const WeaponInspect := preload("res://scripts/weapon_inspect.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Mission := preload("res://scripts/mission.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const Throwables := preload("res://scripts/throwables.gd")
const Ammo := preload("res://scripts/ammo.gd")
const Hints := preload("res://scripts/hints.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const NotePaper := preload("res://scripts/note_paper.gd")
const MessageView := preload("res://scripts/message_view.gd")
const MiniMap := preload("res://scripts/hud_minimap.gd")
const JournalView := preload("res://scripts/journal_view.gd")
const Weather := preload("res://scripts/weather.gd")
const Codex := preload("res://scripts/codex.gd")
const RunLog := preload("res://scripts/run_log.gd")
const WorkshopUi := preload("res://scripts/workshop_ui.gd")
const Actions := preload("res://scripts/actions.gd")
const Captions := preload("res://scripts/captions.gd")
const W := preload("res://scripts/ui_widgets.gd")
const HudIcon := preload("res://scripts/hud_icon.gd")

## HUD o kolejne 30% mniejszy (0,8 → 0,56) po przebudowie na układ bez ramek; razem z mnożnikiem SMALL / NORMAL / LARGE (celownik ma własne CROSS_SCALE).
const UI_SCALE := 0.56
const MSG_SCALE := 0.8            ## komunikaty (alerty, toasty, karta tytułowa, porady, dziennik, notatki, pasek akcji) o 20% mniejsze niż reszta HUD-u
const MARGIN := 8.0              ## odstęp kart od krawędzi (jednostki logiczne HUD)
const CONTROLS_SHOW_S := 20.0
const TOAST_S := 9.0               ## s, przez które opis celu jest widoczny po zmianie celu / fazy (potem gaśnie; F1 przywołuje)
const TOAST_LEVEL_MAX := 2           ## pasek sterowania pokazuje się sam tylko początkującym (poziom profilu do tego)
const NOISE_COL_CALM := Color(0.62, 0.72, 0.78)
const OBJ_W := 250.0             ## szerokość treści karty celu (zawijanie)
const SESSION_W := 152.0         ## szerokość bloku „sesja + zegar" w prawym górnym rogu
const WARN_Y := 0.255            ## wysokość ostrzeżenia nad środkiem ekranu (ułamek wysokości; 92/360)
const CENTER_Y := 0.39           ## napis „SQUAD DOWN" (140/360)
const BRIEF_ROWS := 5             ## ile wierszy zagrożeń pokazuje odprawa (reszta: „+N more")
const PROMPT_Y := 0.76           ## pasek kontekstowy — nad paskiem broni (dół, środek)
## Układ wzorowany na koop-strzelankach (Left 4 Dead, Deep Rock Galactic, Helldivers): drużyna i zdrowie w lewym dolnym
## rogu (własny wiersz na górze, koledzy pod nim), broń i zasoby w płaskim pasku na środku dołu, a w lewym górnym tylko miernik hałasu.
const BOTTOM_PAD := 20.0         ## odstęp kart dolnych od krawędzi (nad paskiem sterowania)
const SQUAD_W := 150.0
const ROW_H := 68.0              ## dolny rząd: karty drużyny i ekwipunku (jednostki logiczne); pasek broni jest niższy (własna wysokość)
const TOP_H := 55.0              ## górny rząd: hałas, cel i RUN mają wspólną wysokość (dolne krawędzie się pokrywają)
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
	var cracked := -1             ## indeks serca „stłuczonego" (głaz Wołka: ukryte 0,5 HP) — przygaszone z pęknięciem
	var bonus := Color(1.0, 0.8, 0.25)
	var u := 1.0                  ## skala ikon (własne serca w karcie drużyny są większe)
	var edge_off := Color(0.29, 0.12, 0.10)   ## "drop": kontur pustej kropli
	var _sb := StyleBoxFlat.new()
	## Minimalny rozmiar wg kształtu: "drop" (makieta karty drużyny) 9×11 co 12 j.; reszta jak dotąd.
	func min_size() -> Vector2:
		if shape == "drop":
			return Vector2(count * 12.0 - 3.0, 11.0)
		if shape == "seg":
			return Vector2(count * 17.0 - 2.0, 2.6)
		return Vector2(count * 11.0 * u - 2.0, 9.0 * u)
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
		if shape == "seg":
			# cienkie segmenty życia (HUD bez ramek): pełny = kolor, pusty = ledwo widoczna linia, bonus = złoty, pęknięty = ciemniejszy
			for i in count:
				var sc := on if i < filled else off
				if i >= bonus_from:
					sc = bonus
				if i == cracked:
					sc = sc.darkened(0.35)
				draw_rect(Rect2(Vector2(i * 17.0, 0.0), Vector2(15.0, size.y if size.y > 0.5 else 2.6)), sc)
			return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
		for i in count:
			var c := on if i < filled else off
			if i >= bonus_from:
				c = bonus
			if i == cracked:
				c = c.darkened(0.35)
			var o := Vector2(i * 11.0, 0.0)
			if shape == "drop":
				# makieta Hud.dc.html: kropla 14×18 px (9×11 j.), pełna = kolor, pusta = sam kontur; dół zaokrąglony mocniej niż góra
				_sb.set_corner_radius_all(1)
				_sb.corner_radius_bottom_left = 4
				_sb.corner_radius_bottom_right = 4
				_sb.anti_aliasing = true
				var dr := Rect2(Vector2(i * 12.0, 0.0), Vector2(9.0, 11.0))
				if i < filled or i >= bonus_from:
					_sb.bg_color = c
					_sb.set_border_width_all(0)
				else:
					_sb.bg_color = Color(0, 0, 0, 0)
					_sb.border_color = edge_off
					_sb.set_border_width_all(1)
				draw_style_box(_sb, dr)
			elif shape == "heart" and UiTheme.hd_on():
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
				# ◆ pełny / ◇ pusty (makieta): płaski romb w kolorze zasobu, pusty to cienki kontur
				var dia := PackedVector2Array([o + Vector2(4.5, 0), o + Vector2(9, 4.5), o + Vector2(4.5, 9), o + Vector2(0, 4.5)])
				if i < filled or i >= bonus_from:
					draw_colored_polygon(dia, c)
				else:
					draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color(1, 1, 1, 0.3), 1.0, true)
			if i == cracked:
				# pęknięcie przez serce: pół punktu życia już zabrane (głaz Wołka), kolejne trafienie zabierze resztę
				var ox := float(i) * (12.0 if shape == "drop" else 11.0)
				draw_polyline(PackedVector2Array([Vector2(ox + 5.0, -0.5), Vector2(ox + 3.4, 3.2), Vector2(ox + 5.7, 5.0), Vector2(ox + 4.2, 8.5)]), Color(0.06, 0.02, 0.02, 0.95), 1.2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Mały przebieg EKG obok serc własnego gracza (makieta): linia "biegnie" co 1,2 s; przy "Reduce effects" stała.
class Ecg extends Control:
	const PTS := [Vector2(0, 8), Vector2(10, 8), Vector2(13, 2), Vector2(17, 14), Vector2(21, 8), Vector2(40, 8)]
	var color := Color(0.9, 0.28, 0.23)
	var _t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(25, 10)
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var kx := size.x / 40.0
		var ky := size.y / 16.0
		var head := 40.0 if Settings.fx_mult() <= 0.0 else fposmod(_t / 1.2, 1.0) * 52.0
		var pts := PackedVector2Array()
		for p in PTS:
			pts.append(Vector2(p.x * kx, p.y * ky))
		draw_polyline(pts, Color(color, 0.28), 1.0, true)
		var lit := PackedVector2Array()
		for i in PTS.size():
			var p: Vector2 = PTS[i]
			if p.x <= head:
				lit.append(pts[i])
			else:
				var q: Vector2 = PTS[i - 1]
				var f := clampf((head - q.x) / maxf(0.001, p.x - q.x), 0.0, 1.0)
				lit.append(pts[i - 1].lerp(pts[i], f))
				break
		if lit.size() >= 2:
			draw_polyline(lit, color, 1.0, true)

## Karta zakotwiczona w obiekcie świata: panel z „ogonkiem” (strzałką) pod spodem, wskazującym obiekt.
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

## Romb w kolorze slotu przed nazwą kolegi z drużyny (lista w lewym górnym rogu).
class Diamond extends Control:
	var col := Color.WHITE
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(7, 7)
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(3.5, 0), Vector2(7, 3.5), Vector2(3.5, 7), Vector2(0, 3.5)]), col)

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
var _journal: Control                ## dziennik komunikatów i porad (klawisz akcji „journal”): journal_view.gd
var _msgs: Control                   ## renderer kanałów komunikatów (alert, toasty, karta tytułowa): message_view.gd
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
var _squad_card: PanelContainer      ## życie drużyny (lewy dolny róg): własny wiersz, pod nim koledzy
var _self_box: VBoxContainer          ## własny wiersz życia (góra bloku drużyny)
var _noise_cap: Label
var _squad_box: VBoxContainer
var _squad_rows := {}            ## instance_id gracza -> słownik wiersza
var _gear_card: PanelContainer
var _equip_card: PanelContainer      ## zasoby (Q / F / ALT / L) — osobna karta w prawym dolnym rogu
var _reload_bar: Bar
var _gren_name: Label
var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_icons: Array[HudIcon] = []
var _slot_row: Control               ## rząd miniatur broni (1–4, V): widoczny chwilę po zmianie broni
var _slot_t := 0.0
var _slot_sig := -1
var _gun_main: HudIcon
var _q_icon: HudIcon
var _q_count: Label
var _f_icon: HudIcon
var _f_count: Label
var _a_icon: HudIcon
var _l_icon: HudIcon
var _scrim_t: TextureRect
var _scrim_b: TextureRect
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
var _minimap: MiniMap                ## rzut mapy w górnym środku (zastąpił pasek kierunku)
var _toast_box: VBoxContainer        ## opis celu (podpis, tekst, podpowiedź): pokazuje się na zmianę celu, potem gaśnie
var _toast_t := 0.0
var _toast_sig := ""
var _run_title: Label
var _xp_row: HBoxContainer
var _xp_show_t := 0.0
var _boss_bar: Bar
var _boss_name: Label

var _session: Label
var _clock: Label
var _scrap: Label                    ## portfel złomu (bank) i łup z bieżącej misji
var _lv_label: Label                 ## plakietka „LV n” w karcie RUN (profile.gd)
var _run_card: PanelContainer        ## karta RUN (prawy górny róg): trudność, zegar, złom, poziom i pasek XP
var _run_xp_bar: Bar                  ## pasek XP w karcie RUN
var _xp_txt: Label
var _squad_info: Label               ## „HOST · 1/4 +1 AI” w nagłówku karty drużyny
var _result_xp_val: Label
var _prompt_card: PanelContainer
var _prompt: RichTextLabel             ## pasek akcji: tekst z klawiszami jako klawisze (UiTheme.keycaps)
var _prompt_bar: Bar
var _controls: Label
var _controls_range := false            ## pasek sterowania pokazuje ściągę strzelnicy (kontekst „range”)
var _f1: Label
var _result: PanelContainer
var _hints := Hints.new()
var _result_stats: GridContainer
var _result_prompt: Label
var _result_title: Label
var _result_sub: Label
var _result_box: StyleBoxFlat
var _inspect: Control                   ## oględziny broni ([F]): rozmyte tło, model 3D i statystyki — weapon_inspect.gd
var _noise_card: PanelContainer      ## karta hałasu (w kryjówce zastępuje ją znacznik SAFE)
var _safe_chip: Control
var _ready_pips: Pips              ## kwadraciki gotowości w pasku misji kryjówki
var _scrap_coin: Coin
var _brief: Dictionary = {}               ## karta odprawy przy tablicy w kryjówce
var _radio: Dictionary = {}               ## karta prognozy pogody przy radiostacji w kryjówce
var _radio_key := ""
var _brief_id := ""
var _demo_footer: Control = null     ## stopka dema na ekranie wyniku — tylko na końcu kampanii / serii


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pełny ekran w jednostkach logicznych: viewport / UI_SCALE, skala 0.7 od lewego górnego rogu
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(_scale_now(), _scale_now())
	_build_scrims()
	_build_noise_card()
	_build_squad_card()
	_build_gear_card()
	_build_objective_card()
	_build_session()
	_build_center()
	_build_prompt()
	_build_controls()
	_build_captions()
	_build_chat()
	_build_result()
	_build_dim()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotnoise="):
			_dev_noise = float(a.substr("--shotnoise=".length()))
	_inspect = WeaponInspect.new()
	add_child(_inspect)
	_brief = _make_info_card(310.0, 4, UiTheme.Note.DOSSIER)         # odprawa: akta sztabu (maszynopis, pieczątka)
	(_brief["card"] as NotePaper).stamp = tr("CLASSIFIED")
	_radio = _make_info_card(300.0, 2, UiTheme.Note.PRINTOUT)        # prognoza: wydruk z radia
	_build_world_notes()
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
	_scrim_t.position = Vector2.ZERO
	_scrim_t.size = Vector2(w, h * 0.22)
	_scrim_b.size = Vector2(w, h * 0.26)
	_scrim_b.position = Vector2(0.0, h - _scrim_b.size.y)
	_run_card.reset_size()
	_run_card.position = Vector2(w - 2.0 * MARGIN - _run_card.size.x, 2.0 * MARGIN)
	_msgs.scale = Vector2.ONE * MSG_SCALE
	_msgs.position = Vector2.ZERO
	_msgs.size = size / MSG_SCALE
	_journal.scale = Vector2.ONE * MSG_SCALE
	_journal.position = Vector2.ZERO
	_journal.size = size / MSG_SCALE
	_place(_controls, Vector2(MARGIN, h - 16.0), Vector2(w - 2.0 * MARGIN, 12))
	_place(_f1, Vector2(w - MARGIN - SESSION_W, h - 16.0), Vector2(SESSION_W, 12))   # dół, prawy koniec paska podpowiedzi

# ---------------------------------------------------------------- budowa

## Pozycja i rozmiar PO dodaniu do drzewa: wcześniej etykieta nie ma motywu,
## liczy minimalny rozmiar domyślną czcionką 16 px i zostaje za szeroka.
func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz

func _card(pos: Vector2, flat := true) -> PanelContainer:
	var c := PanelContainer.new()
	c.position = pos
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if flat:
		c.add_theme_stylebox_override("panel", StyleBoxEmpty.new())     # HUD bez ramek: czytelność robią gradienty u góry i u dołu (_build_scrims)
	add_child(c)
	return c

## Dwa miękkie gradienty (góra i dół ekranu) pod tekstem i ikonami zamiast ramek kart; rysowane pod wszystkim innym.
func _build_scrims() -> void:
	for top in [true, false]:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55 if top else 0.6))
		g.set_color(1, Color(0, 0, 0, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0 if top else 1)
		gt.fill_to = Vector2(0, 1 if top else 0)
		gt.width = 4
		gt.height = 64
		var tr_ := TextureRect.new()
		tr_.texture = gt
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr_)
		move_child(tr_, 0)
		if top:
			_scrim_t = tr_
		else:
			_scrim_b = tr_

## Nagłówek karty w stylu makiety: mały mono, rozstrzelony (em = ułamek rozmiaru).
func _cap(text: String, color: Color, spacing := 0.2, size := 7) -> Label:
	var l := UiTheme.label(text, size, color)
	if UiTheme.hd_on():
		var fv := FontVariation.new()
		fv.base_font = UiTheme.mono_font()
		fv.spacing_glyph = int(round(float(size) * spacing))
		l.add_theme_font_override("font", fv)
		l.add_theme_constant_override("outline_size", 0)
	return l

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

## Lewy górny róg: mały VU-metr i jedna linia stanu hałasu (filar ciszy: jedyny wskaźnik, na który trzeba patrzeć bez przerwy),
## pod nią pogoda misji. W kryjówce hałas nic nie mówi (zawsze 0%), więc zostaje sam znacznik SAFE.
func _build_noise_card() -> void:
	var card := _card(Vector2(MARGIN, MARGIN))
	_noise_card = card
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 9)
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(outer)
	_noise_bar = VuMeter.new()                 # analogowy VU-metr; progi z NoiseMgr: 30 = zasypia, 40 = niepokój, 60 = budzi się ON
	_noise_bar.custom_minimum_size = Vector2(52, 31)
	_noise_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_noise_bar.ticks = [
		[NoiseMgr.SLEEP_THRESHOLD / 100.0, Color(1, 1, 1, 0.35)],
		[NoiseMgr.UNEASY_THRESHOLD / 100.0, UiTheme.ACCENT],
		[NoiseMgr.AWAKE_THRESHOLD / 100.0, UiTheme.DANGER],
	]
	outer.add_child(_noise_bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(box)
	var nz := HBoxContainer.new()
	nz.add_theme_constant_override("separation", 5)
	box.add_child(nz)
	_noise_cap = _cap("NOISE", UiTheme.MUTED, 0.22)
	nz.add_child(_noise_cap)
	_noise_state = _cap("", UiTheme.MUTED, 0.14)
	nz.add_child(_noise_state)
	_noise_val = UiTheme.mono(UiTheme.label("0%", 8, UiTheme.TEXT))
	nz.add_child(_noise_val)
	_safe_chip = UiTheme.heading("SAFE", 8, UiTheme.OK)
	_safe_chip.visible = false
	nz.add_child(_safe_chip)
	_weather_row = UiTheme.label("", 7, UiTheme.MUTED)
	_weather_row.visible = false
	box.add_child(_weather_row)

## Lewy dolny róg: życie drużyny (L4D / DRG) — na górze własny wiersz, pod nim koledzy (romb w kolorze slotu, nazwa, cienkie
## segmenty życia). Wiersze powstają dynamicznie — _drive_squad().
func _build_squad_card() -> void:
	_squad_card = _card(Vector2(MARGIN, MARGIN))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	_squad_card.add_child(outer)
	_squad_info = _cap("", UiTheme.MUTED, 0.1)
	outer.add_child(_squad_info)
	_self_box = VBoxContainer.new()
	_self_box.add_theme_constant_override("separation", 2)
	outer.add_child(_self_box)
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 7)
	outer.add_child(_squad_box)

## Dół, środek: broń jako model 3D bez ramki — [miniatury slotów 1–4 (chwilę po zmianie)] / [model + magazynek i zapas] /
## [nazwa, tryb i koszt strzału] / [stan] / [cienkie linie przeładowania i ciepła lufy]. Sprzęt (Q, F, ALT, L) — prawy dolny róg.
func _build_gear_card() -> void:
	_gear_card = _card(Vector2(MARGIN, MARGIN))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_gear_card.add_child(col)

	# 0) rząd miniatur: same klawisze pod modelami, aktywny w kolorze lampy; wygasa po chwili (_drive_weapons)
	var wr := HBoxContainer.new()
	wr.add_theme_constant_override("separation", 13)
	wr.alignment = BoxContainer.ALIGNMENT_CENTER
	wr.modulate.a = 0.0
	_slot_row = wr
	for i in 4:
		var sl := PanelContainer.new()
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sl.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		var ic := HudIcon.new()
		ic.custom_minimum_size = Vector2(46, 13)
		v.add_child(ic)
		var l := UiTheme.mono(UiTheme.label("", 6, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(l)
		sl.add_child(v)
		_slot_icons.append(ic)
		wr.add_child(sl)
		_slots.append(sl)
		_slot_labels.append(l)
	col.add_child(wr)

	# 1) model aktualnej broni i magazynek / zapas drużyny
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_gun_main = HudIcon.new()
	_gun_main.custom_minimum_size = Vector2(166, 50)
	_gun_main.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gun_main)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 3)
	nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ammo_mag = UiTheme.heading("", 36, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_mag.custom_minimum_size = Vector2(52, 0)
	nums.add_child(_ammo_mag)
	_ammo_res = UiTheme.label("", 9, UiTheme.MUTED)
	_ammo_res.size_flags_vertical = Control.SIZE_SHRINK_END
	nums.add_child(_ammo_res)
	row.add_child(nums)

	# 2) nazwa broni, tryb i koszt następnego strzału (ile Uwagi — GDD §8.1)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 7)
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	_ammo_name = UiTheme.heading("", 12, UiTheme.TEXT)
	nm.add_child(_ammo_name)
	_heat_note = _cap("", UiTheme.MUTED, 0.14)
	_heat_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(_heat_note)
	col.add_child(nm)

	# 3) stan (RELOADING / NO AMMO) i dwie cienkie linie: przeładowanie i ciepło lufy
	_ammo_note = UiTheme.label("", 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_ammo_note)
	_reload_bar = Bar.new()
	_reload_bar.custom_minimum_size = Vector2(150, 1.6)
	_reload_bar.fill = UiTheme.ACCENT
	_reload_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_reload_bar)
	_heat_bar = Bar.new()
	_heat_bar.custom_minimum_size = Vector2(150, 1.0)
	_heat_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_heat_bar)

	# 4) sprzęt w prawym dolnym rogu: cztery modele 3D bez ramek, liczba przy rogu, klawisz pod spodem
	_equip_card = _card(Vector2(MARGIN, MARGIN))
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 12)
	res.alignment = BoxContainer.ALIGNMENT_END
	_equip_card.add_child(res)
	var q := _tile("Q", "lure", true)
	_q_icon = q["icon"]
	_q_count = q["count"]
	res.add_child(q["root"])
	var f := _tile("F", "flare", true)
	_f_icon = f["icon"]
	_f_count = f["count"]
	res.add_child(f["root"])
	var a := _tile("ALT" if OS.get_name() != "macOS" else "CMD", "frag", true)      # przedmiot (lewy Alt użyj, X zmiana rodzaju)
	_a_icon = a["icon"]
	_gren_name = a["count"]
	res.add_child(a["root"])
	var lt := _tile("L", "flashlight", false)
	_l_icon = lt["icon"]
	_battery = Bar.new()
	_battery.custom_minimum_size = Vector2(26, 1.6)
	_battery.back = Color("1f1e19")
	_battery.position = Vector2(5, 38)
	(lt["box"] as Control).add_child(_battery)
	_battery_note = UiTheme.mono(UiTheme.label("100%", 6, UiTheme.MUTED))                  # procent baterii obok klawisza
	(lt["keyrow"] as Control).add_child(_battery_note)
	res.add_child(lt["root"])

## Kafelek sprzętu: model 3D (36×40) z liczbą w prawym górnym rogu i klawiszem pod spodem (podkreślona litera).
func _tile(key_text: String, icon_key: String, counted: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := Control.new()
	box.custom_minimum_size = Vector2(38, 42)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := HudIcon.new()
	icon.set_key(icon_key)
	icon.position = Vector2(2, 1)
	icon.size = Vector2(32, 38)
	box.add_child(icon)
	var count: Label = null
	if counted:
		count = UiTheme.mono(UiTheme.label("0", 8, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
		count.position = Vector2(20, -1)
		count.size = Vector2(18, 11)
		box.add_child(count)
	root.add_child(box)
	var kr := HBoxContainer.new()
	kr.add_theme_constant_override("separation", 4)
	kr.alignment = BoxContainer.ALIGNMENT_CENTER
	kr.add_child(_key(key_text))
	root.add_child(kr)
	return {"root": root, "box": box, "icon": icon, "count": count, "keyrow": kr}

## Klawisz w HUD-zie: sama litera z cienkim podkreśleniem (bez kapsla — HUD jest bez ramek).
func _key(s: String) -> Control:
	var l := UiTheme.mono(UiTheme.label(s, 7, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(UiTheme.TEXT, 0.45)
	sb.border_width_bottom = 1
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# ---------------------------------------------------------------- karta drużyny

## Jeden wiersz: [romb w kolorze slotu] nazwa (+ BOT / YOU), stan (DOWN / REVIVING / CRITICAL), pod spodem cienkie segmenty życia
## (złote ponad bazę) i pasek, gdy ktoś leży (czerwony = wykrwawianie, zielony = podnoszenie). Własny wiersz stoi nad kolegami.
func _make_squad_row(p: Node, is_self: bool) -> Dictionary:
	var slot := ((int(p.display_id) - 1) % 4) + 1
	var slot_col: Color = SLOT_COLORS[slot - 1]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	if not is_self:
		var dia := Diamond.new()
		dia.col = Color("8d8a7c") if p.is_bot else slot_col
		dia.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(dia)
	var nm := UiTheme.mono(UiTheme.label("P%d" % int(p.display_id), 9, slot_col if is_self else UiTheme.TEXT))
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(nm)
	var tag := _cap(tr("YOU") if is_self else (tr("BOT") if p.is_bot else ""), UiTheme.MUTED, 0.18, 6)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tag)
	var status := _cap("", UiTheme.MUTED, 0.1)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(status)
	root.add_child(top)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 7)
	var pips := Pips.new()
	pips.shape = "seg"
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.on = UiTheme.DANGER if is_self else (Color("8d8a7c") if p.is_bot else UiTheme.TEXT)
	pips.off = Color(1, 1, 1, 0.14)
	prow.add_child(pips)
	if is_self:
		var ecg := Ecg.new()
		ecg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prow.add_child(ecg)
	root.add_child(prow)
	var bar := Bar.new()
	bar.custom_minimum_size = Vector2(0, 2)
	bar.visible = false
	root.add_child(bar)
	(_self_box if is_self else _squad_box).add_child(root)
	return {"root": root, "pips": pips, "status": status, "bar": bar, "hp": maxi(p.hp, 0), "flash": 0.0, "self": is_self, "bot": p.is_bot}

func _drive_squad(delta: float) -> void:
	var list: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			list.append(p)
	# koledzy rosnąco po slocie (własny wiersz ma osobne pudełko nad nimi)
	list.sort_custom(func(a: Node, b: Node) -> bool: return a.display_id < b.display_id)
	var present := {}
	var mate_idx := 0
	for node in list:
		var p: Node = node
		var id := p.get_instance_id()
		present[id] = true
		var is_self: bool = p == _player
		var row: Dictionary = _squad_rows.get(id, {})
		if row.is_empty() or bool(row["self"]) != is_self or bool(row["bot"]) != p.is_bot:
			if not row.is_empty():
				(row["root"] as Node).queue_free()
			row = _make_squad_row(p, is_self)
			_squad_rows[id] = row
		if not is_self:
			_squad_box.move_child(row["root"], mate_idx)
			mate_idx += 1
		_update_squad_row(p, row, delta)
	for id in _squad_rows.keys():
		if not present.has(id):
			(_squad_rows[id]["root"] as Node).queue_free()
			_squad_rows.erase(id)
	_squad_box.visible = mate_idx > 0
	_squad_card.reset_size()
	_squad_card.position = Vector2(2.0 * MARGIN, size.y - BOTTOM_PAD - _squad_card.size.y)
	_noise_card.reset_size()
	_noise_card.position = Vector2(2.0 * MARGIN, 2.0 * MARGIN)

func _update_squad_row(p: Node, row: Dictionary, delta: float) -> void:
	var hp := maxi(p.hp, 0)
	var pips: Pips = row["pips"]
	pips.count = maxi(p.max_hp(), hp)
	pips.bonus_from = p.max_hp()
	pips.filled = hp
	pips.cracked = hp - 1 if hp > 0 and float(p.get("chip")) > 0.0 else -1        # ukryte 0,5 HP z głazu: ostatnie pełne serce pęknięte
	var base_col: Color = UiTheme.DANGER if bool(row["self"]) else (Color("8d8a7c") if p.is_bot else UiTheme.TEXT)
	pips.on = Color(0.45, 0.17, 0.15) if p.dead else base_col
	pips.custom_minimum_size = pips.min_size()
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
		if p.taken:
			txt = "TAKEN  %ds" % ceili(p.taken_t)
			col = Color(1.0, 0.45, 0.2)
			bar.value = p.taken_t / 20.0
			bar.fill = Color(1.0, 0.45, 0.2)
		elif p.revive_progress > 0.0:
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
	elif p.stun_t > 0.0:
		txt = "STUNNED"
		col = Color(0.95, 0.75, 0.3)
	elif hp == 1:
		txt = "CRITICAL"
		col = UiTheme.DANGER.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_blink * 7.0)))
	status.text = txt
	status.add_theme_color_override("font_color", col)

func _build_objective_card() -> void:
	_obj_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_obj_card.add_child(box)
	_minimap = MiniMap.new()
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_minimap)
	_boss_row = VBoxContainer.new()
	_boss_row.add_theme_constant_override("separation", 2)
	_boss_name = UiTheme.heading("THE VEIN — MOTHER OF NESTS", 8, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_row.add_child(_boss_name)
	_boss_bar = Bar.new()
	_boss_bar.custom_minimum_size = Vector2(OBJ_W, 4)
	_boss_bar.fill = Color(0.88, 0.22, 0.2)
	_boss_bar.seg = 4.0
	_boss_bar.ticks = [[0.66, Color(1, 1, 1, 0.5)], [0.33, Color(1, 1, 1, 0.5)]]
	_boss_row.add_child(_boss_bar)
	box.add_child(_boss_row)
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 2)
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_toast_box)
	_obj_caption = _cap("OBJECTIVE", UiTheme.ACCENT, 0.3)
	_obj_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_box.add_child(_obj_caption)
	_obj_text = UiTheme.heading("", 14, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_obj_text.custom_minimum_size = Vector2(OBJ_W, 0)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_box.add_child(_obj_text)
	_obj_hint = UiTheme.whisper(UiTheme.label("", UiTheme.T_BODY - 1, UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_obj_hint.custom_minimum_size = Vector2(OBJ_W, 0)
	_obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_box.add_child(_obj_hint)
	# kryjówka: kwadraciki gotowości (jeden na człowieka) — widać, na kogo czeka drużyna
	_ready_pips = Pips.new()
	_ready_pips.shape = "ready"
	_ready_pips.on = UiTheme.OK
	_ready_pips.visible = false
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_child(_ready_pips)
	_toast_box.add_child(pip_row)

func _build_session() -> void:
	# prawy górny róg jako sam tekst: [tytuł misji] / [trudność · zegar] / [złom]; poziom i pasek XP tylko chwilę po zdobyciu XP
	_run_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_run_card.add_child(box)
	_run_title = UiTheme.heading("", 13, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_run_title)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_END
	head.add_theme_constant_override("separation", 5)
	_session = _cap("", UiTheme.MUTED, 0.14)                 # trudność; kolor wg poziomu (_drive_status)
	head.add_child(_session)
	head.add_child(_cap("·", UiTheme.MUTED, 0.0))
	_clock = UiTheme.mono(UiTheme.label("", 8, UiTheme.MUTED))
	head.add_child(_clock)
	box.add_child(head)
	var main := HBoxContainer.new()
	main.alignment = BoxContainer.ALIGNMENT_END
	main.add_theme_constant_override("separation", 5)
	_scrap_coin = Coin.new()
	_scrap_coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main.add_child(_scrap_coin)
	_scrap = UiTheme.mono(UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
	main.add_child(_scrap)
	box.add_child(main)
	var xp := HBoxContainer.new()
	_xp_row = xp
	xp.visible = false
	xp.add_theme_constant_override("separation", 5)
	_lv_label = UiTheme.mono(UiTheme.label("LV 1", 7, UiTheme.TEXT))
	var badge := StyleBoxFlat.new()
	badge.bg_color = Color(0, 0, 0, 0)                  # sam obrys: ciemny tekst na jasnym tle wychodził zbyt gruby
	badge.border_color = Color("3d3a30")
	badge.set_border_width_all(1)
	badge.content_margin_left = 3
	badge.content_margin_right = 3
	badge.content_margin_top = 1
	badge.content_margin_bottom = 1
	_lv_label.add_theme_stylebox_override("normal", badge)
	_lv_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp.add_child(_lv_label)
	_run_xp_bar = Bar.new()
	_run_xp_bar.custom_minimum_size = Vector2(56, 2)
	_run_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_run_xp_bar.fill = UiTheme.MUTED
	_run_xp_bar.back = Color("1f1e19")
	xp.add_child(_run_xp_bar)
	_xp_txt = UiTheme.mono(UiTheme.label("", 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	xp.add_child(_xp_txt)
	box.add_child(xp)
	Profile.xp_gained.connect(_on_xp_gained)
	Profile.leveled_up.connect(_on_level_up)

func _build_center() -> void:
	_msgs = MessageView.new()
	add_child(_msgs)
	_journal = JournalView.new()
	add_child(_journal)
	NoiseMgr.overcharge_stale.connect(func() -> void: show_note(tr("They know this trick — move before you lure again")))
	add_child((load("res://scripts/taken_arrow.gd") as GDScript).new())      # strzałka ku porwanemu graczowi poza kadrem (Żerca, F4d)
	if "--shotjournal" in OS.get_cmdline_user_args():
		# dev: dziennik otwarty z kilkoma przykładowymi wpisami (zrzut: --shotjournal --shot=PLIK)
		var tm := Timer.new()
		tm.wait_time = 1.5
		tm.one_shot = true
		tm.autostart = true
		tm.timeout.connect(func() -> void:
			Msg.note_to_journal("1.2  RADIO SILENCE", Msg.Ch.TITLE, Msg.Style.DANGER, "WEATHER — RAIN: every noise is 25% quieter")
			Msg.tick(3.0)
			Msg.note_to_journal("+50 XP", Msg.Ch.TOAST, Msg.Style.SUCCESS)
			Msg.tick(20.0)
			Msg.note_to_journal("Something is listening…", Msg.Ch.ALERT, Msg.Style.WARN, "Above 60% noise he wakes up")
			Msg.tick(40.0)
			Msg.note_to_journal("LEVEL 24  —  perk slot unlocked", Msg.Ch.TOAST, Msg.Style.SUCCESS)
			_journal.set_open(true))
		add_child(tm)

func _build_prompt() -> void:
	_prompt_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_prompt_card.add_child(box)
	_prompt = RichTextLabel.new()
	_prompt.bbcode_enabled = true
	_prompt.fit_content = true
	_prompt.scroll_active = false
	_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("normal_font_size", UiTheme.T_BODY)
	_prompt.add_theme_color_override("default_color", UiTheme.TEXT)
	_prompt.add_theme_constant_override("outline_size", 2)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_child(_prompt)
	_prompt_bar = Bar.new()
	_prompt_bar.custom_minimum_size = Vector2(180, 3)
	box.add_child(_prompt_bar)

func _build_controls() -> void:
	_controls = UiTheme.label(Actions.hud_line(), 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_controls)
	_f1 = UiTheme.label(tr("%s  controls") % Actions.key("help"), 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var refresh_keys := func() -> void:        # klawiatura ↔ pad albo zmiana przypisań: podpowiedzi pokazują właściwe klawisze
		_controls.text = Actions.range_hud_line() if _controls_range else Actions.hud_line()
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
	_squad_box.modulate.a = lerpf(1.0, 0.55, (1.0 - _tier_k) * 2.0)       # koledzy przygasają; własne życie (T1) zawsze w pełni
	_run_card.modulate.a = lerpf(1.0, 0.65, (1.0 - _tier_k) * 2.0)
	for c in [_f1, _controls]:
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

func _drive_hint(delta: float) -> void:
	# jeden komunikat naraz: alert, toast i karta tytułowa mają pierwszeństwo — porada czeka (jej czas stoi), pokazuje się w spokojnej chwili
	var busy := not Msg.current(Msg.Ch.ALERT).is_empty() or not Msg.toasts().is_empty() or not Msg.current(Msg.Ch.TITLE).is_empty()
	var text := _hints.update(0.0 if busy else delta, _player)
	if text != "" and not _result.visible and not busy:
		Msg.hold("hud.tip", Msg.Ch.TIP, text, {"style": Msg.Style.INFO, "prio": 30, "alpha": _hints.alpha, "log": true})

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
	visible = in_session and not Settings.dev_nohud
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
	elif event.is_action_pressed("journal") and NoiseMgr.has_network():
		_journal.set_open(not _journal.open)
		get_viewport().set_input_as_handled()
	elif _journal.open and event.is_action_pressed("pause"):
		_journal.set_open(false)                      # Esc zamyka dziennik (menu pauzy otwiera się jak zwykle)
	elif Settings.STORE_URL != "" and _result.visible and _demo_footer != null and _demo_footer.visible and event.is_action_pressed("open_store"):
		OS.shell_open(Settings.STORE_URL)

## Krótki komunikat środkowy (znika po `secs`).
func show_note(text: String, secs := 3.0) -> void:
	Msg.post("hud.note.%d" % text.hash(), Msg.Ch.TOAST, text, {"ttl": secs, "style": Msg.Style.WARN, "prio": 60})

func _drive_noise() -> void:
	var safe: bool = NoiseMgr.safe_zone
	_noise_bar.visible = not safe
	_noise_cap.visible = not safe
	_noise_state.visible = not safe
	_noise_val.visible = not safe
	_safe_chip.visible = safe
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
	var qn: int = NoiseMgr.overcharge_charges
	_q_count.text = str(qn)
	_q_count.add_theme_color_override("font_color", UiTheme.TEXT if qn > 0 else UiTheme.DANGER)
	_q_icon.set_key("lure", Color.WHITE if qn > 0 else Color(1, 1, 1, 0.28))
	var fn: int = NoiseMgr.flares
	_f_count.text = str(fn)
	_f_count.add_theme_color_override("font_color", UiTheme.TEXT if fn > 0 else UiTheme.DANGER)
	_f_icon.set_key("flare", Color.WHITE if fn > 0 else Color(1, 1, 1, 0.28))
	var gk := Arsenal.selected_throwable()
	var gn := Arsenal.get_throwable(gk)
	_gren_name.text = str(gn)
	_gren_name.tooltip_text = "%s  —  %s" % [Throwables.KINDS[gk]["name"], tr("%s switches item") % Actions.key("throw_next")]
	_gren_name.add_theme_color_override("font_color", UiTheme.TEXT if gn > 0 else UiTheme.DANGER)
	_a_icon.set_key(String(gk), Color.WHITE if gn > 0 else Color(1, 1, 1, 0.28))

func _on_xp_gained(amount: int, _reason: String) -> void:
	_xp_show_t = 4.0
	Msg.post("hud.xp", Msg.Ch.TOAST, "", {"amount": amount, "fmt": "+%d XP", "style": Msg.Style.SUCCESS, "ttl": 2.5, "prio": 20, "log": false})

func _on_level_up(lv: int) -> void:
	_xp_show_t = 6.0
	var msg := tr("LEVEL %d") % lv
	if Profile.SLOT_LEVELS.has(lv):
		msg += "  —  " + tr("perk slot unlocked")
	var names: Array = []
	for id in Profile.Perks.unlocked_at(lv):
		names.append(Profile.Perks.display_name(String(id)))
	if not names.is_empty():
		msg += "  —  " + tr("new perks: ") + ", ".join(names)
	Msg.post("hud.level", Msg.Ch.TOAST, msg, {"style": Msg.Style.SUCCESS, "ttl": 5.0, "prio": 80})
	Audio.play("ui_confirm", Audio.BUS_UI, -6.0)

func _drive_status() -> void:
	var lp := Profile.level_progress()
	_lv_label.text = "LV %d" % Profile.level()
	_xp_txt.text = "%d/%d" % [int(lp[0]), int(lp[1])]
	_run_xp_bar.value = float(lp[0]) / float(maxi(1, int(lp[1])))
	_run_xp_bar.queue_redraw()
	_session.text = tr(Difficulty.level_name())
	_session.add_theme_color_override("font_color", [UiTheme.OK, UiTheme.TEXT, UiTheme.DANGER][clampi(Difficulty.level, 0, 2)])
	_squad_info.text = _net_status()
	_scrap.visible = Scrap.enabled()
	_scrap_coin.visible = _scrap.visible
	_scrap.text = "%d%s" % [Scrap.bank, ("  +%d" % Scrap.loot) if Scrap.loot > 0 else ""]
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if m != null:
		var secs := int(m.elapsed)
		_clock.text = "%02d:%02d" % [secs / 60, secs % 60]
	var lvl_n := get_tree().get_first_node_in_group("level")
	_run_title.text = String(lvl_n.title) if lvl_n != null and m != null and m.kind != "hub" else ""
	_run_title.visible = _run_title.text != ""
	_xp_show_t = maxf(0.0, _xp_show_t - get_process_delta_time())
	_xp_row.visible = _xp_show_t > 0.0
	_run_card.reset_size()
	_run_card.position = Vector2(size.x - 2.0 * MARGIN - _run_card.size.x, 2.0 * MARGIN)
	_gear_card.visible = _player != null
	_equip_card.visible = _player != null
	if _player == null:
		return
	var hp: int = maxi(_player.hp, 0)
	if _last_hp >= 0 and hp < _last_hp:
		_hit_flash = 1.0
	_last_hp = hp
	_drive_weapons()
	var pct: float = _player.battery / _player.BATTERY_MAX
	_battery.value = pct
	_battery.fill = UiTheme.DANGER if pct < 0.2 else (Color("e8e2c4") if _player.flashlight else UiTheme.CALM)
	_battery.queue_redraw()
	_battery_note.text = "%d%%" % int(ceil(pct * 100.0))
	_battery_note.add_theme_color_override("font_color", UiTheme.DANGER if pct < 0.2 else (UiTheme.TEXT if _player.flashlight else UiTheme.MUTED))

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
		_slot_icons[i].set_key(String(GunIcon.HD_KEYS.get(int(d.gun_row), "")), Color.WHITE if sel else Color(1, 1, 1, 0.45))
		_slots[i].tooltip_text = names[i]
		_slot_labels[i].add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.MUTED)
	_ammo_name.text = cur.name
	var mode_tag := "BURST" if wc.is_burst(cur) else ("AUTO" if cur.burst_size > 0 else "")
	_gun_main.set_key(String(GunIcon.HD_KEYS.get(int(cur.gun_row), "")))
	# rząd miniatur pokazujemy ~2,5 s po zmianie slotu / rodzaju broni
	var sig: int = wc.slot * 10 + (1 if wc.state == wc.State.MELEE else 0)
	if _slot_sig >= 0 and sig != _slot_sig:
		_slot_t = 2.5
	_slot_sig = sig
	_slot_t = maxf(0.0, _slot_t - get_process_delta_time())
	_slot_row.modulate.a = clampf(_slot_t / 0.5, 0.0, 1.0)
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
		var t_next: int = wc.next_ammo_of(cur.id)
		var res := Arsenal.get_reserve(cur.id, t_next)
		_ammo_mag.text = str(mag)
		_ammo_res.text = "/ %d" % res
		if Ammo.count(String(cur.caliber)) > 1:
			# typ naboju w magazynku; wybrany inny na następny magazynek — strzałka (zapas pokazuje ten następny typ)
			var cal := String(cur.caliber)
			_ammo_res.text += "  " + Ammo.short_of(cal, int(cur.ammo))
			if t_next != int(cur.ammo):
				_ammo_res.text += "→" + Ammo.short_of(cal, t_next)
		if mag <= 0 and res <= 0:
			col = UiTheme.DANGER
			note = "NO AMMO"
		elif mag <= maxi(1, int(cur.mag * 0.25)):
			col = UiTheme.ACCENT if mag > 0 else UiTheme.DANGER
	var jam: String = wc.jammed(cur.id)
	if wc.state == wc.State.RELOAD and wc.clearing:
		note = tr("CLEARING %d%%") % int(wc.reload_progress() * 100.0)
	elif jam == "overheat":
		col = UiTheme.DANGER
		note = tr("CELL OVERHEATED")
	elif jam == "arc":
		col = UiTheme.DANGER
		note = tr("CAPACITOR ARCED — RECHARGE")
	elif jam != "":
		col = UiTheme.DANGER
		note = tr("MISFIRE — PULL AGAIN") if (jam == "misfire" and String(cur.key) == "p64") else tr("JAMMED — [%s] CLEAR") % Actions.key("reload")
	elif wc.state == wc.State.RELOAD:
		note = tr("RELOADING %d%%") % int(wc.reload_progress() * 100.0)
	elif wc.state == wc.State.CHARGE:
		note = tr("CHARGING %d%%") % int(wc.charge * 100.0)
	elif note == "" and cur.uses_ammo() and mag <= 0 and wc.ammo_enabled:
		note = tr("[%s] RELOAD") % Actions.key("reload")
	elif note == "" and Settings.reliability_mult() > 0.0 and not cur.is_melee() and wc.condition_of(cur.id) < wc.DIRTY_AT:
		note = tr("DIRTY %d%%") % int(wc.condition_of(cur.id))           # brudna broń zacina się częściej — wyczyść ją przy ławie
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
	var noise_txt := ""
	if cur.is_melee():
		noise_txt = ""
	elif cur.n_max > cur.n_min:
		noise_txt = "%.1f→%.1f" % [cur.noise(heat), cur.n_max]
	else:
		noise_txt = "%.1f" % cur.noise(0.0)
	_heat_note.text = mode_tag + (" · " if mode_tag != "" and noise_txt != "" else "") + noise_txt
	_gear_card.reset_size()
	# broń: środek dołu (nad gradientem); sprzęt: prawy dolny róg w jednej linii podstawy z bronią
	var gw := _gear_card.size.x
	var gh := _gear_card.size.y
	_gear_card.position = Vector2((size.x - gw) * 0.5, size.y - BOTTOM_PAD - gh)
	_equip_card.reset_size()
	_equip_card.position = Vector2(size.x - 2.0 * MARGIN - _equip_card.size.x, size.y - BOTTOM_PAD - _equip_card.size.y)
	_equip_card.modulate.a = lerpf(1.0, 0.55, (1.0 - _tier_k) * 2.0)

## Ostrzeżenie przed karą (GDD §8.1): niepokój ZANIM ON się obudzi.
func _drive_warning() -> void:
	var awake: bool = NoiseMgr.stalker_awake
	var uneasy: bool = (not awake) and NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD
	if awake:
		Msg.hold("hud.noise.awake", Msg.Ch.ALERT, tr("He hears you…"), {"sub": tr("Go quiet until the noise drops below 30% — or use Q to lure him off"), "style": Msg.Style.DANGER, "prio": 60})
	elif uneasy:
		Msg.hold("hud.noise.uneasy", Msg.Ch.ALERT, tr("Something is listening…"), {"sub": tr("Above 60% noise he wakes up"), "style": Msg.Style.WARN, "prio": 40})
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
	var in_range := _in_range()                      # strzelnica FPP: cel kryjówki i jej opis zasłaniałyby tunel i tablicę wyników
	_obj_card.visible = m.phase != Mission.Phase.SUCCESS and m.phase != Mission.Phase.FAILED and not in_range
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
		var cd := float(main_n.get("hub_countdown"))
		var fl := float(main_n.get("hub_cancel_flash"))
		if fl > 0.05:
			Msg.hold("hud.hubcancel", Msg.Ch.ALERT, "✕", {"big": true, "sub": tr("Departure cancelled"), "style": Msg.Style.DANGER, "prio": 75})
		elif cd > 0.0:
			var sub := tr("Step out of the launch zone to cancel") if bool(main_n.get("hub_in_zone")) else Actions.fmt(tr("[{restart}]  cancel"))
			Msg.hold("hud.hubcount", Msg.Ch.ALERT, str(ceili(cd)), {"big": true, "sub": sub, "style": Msg.Style.SUCCESS, "prio": 70})
	_boss_row.visible = boss != null and m.phase == Mission.Phase.BOSS
	if _boss_row.visible:
		_boss_bar.value = boss.hp / maxf(1.0, boss.max_hp)
		_boss_bar.queue_redraw()
		var bname: String = String(boss.get("boss_name")) if boss.get("boss_name") != null else "THE VEIN — MOTHER OF NESTS"
		_boss_name.text = bname + ("   ·   ENRAGED" if boss.phase >= 2 else "")
	_drive_strip(m)
	# opis celu pokazuje się po zmianie celu / fazy (i w kryjówce, i na F1), potem gaśnie; rzut mapy zostaje
	var sig := "%s|%d|%d|%d|%d" % [m.kind, m.phase, m.goal_left, m.nests_left, m.stashes_found]
	if sig != _toast_sig:
		_toast_sig = sig
		_toast_t = TOAST_S
	var dt := get_process_delta_time()
	_toast_t = maxf(0.0, _toast_t - dt)
	var want := 1.0 if (in_hub or _toast_t > 0.0 or _controls_mode == 1) and not in_range else 0.0
	_toast_box.modulate.a = move_toward(_toast_box.modulate.a, want, dt * (4.0 if want > 0.0 else 1.5))
	_toast_box.visible = _toast_box.modulate.a > 0.01
	# karta celu: wyśrodkowana, szerokość wg treści
	_obj_card.reset_size()
	_obj_card.position = Vector2((size.x - _obj_card.size.x) * 0.5, 2.0 * MARGIN)
	_msgs.obj_bottom = (_obj_card.position.y + _obj_card.size.y) / MSG_SCALE
	_msgs.run_bottom = (_run_card.position.y + _run_card.size.y) / MSG_SCALE
	_msgs.squad_top = _squad_card.position.y / MSG_SCALE

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

## Najbliższy węzeł grupy (po osi X względem gracza), który spełnia warunek; null, gdy brak.
func _nearest(group: String, ok: Callable) -> Node2D:
	var best: Node2D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group(group):
		if not (n is Node2D) or not is_instance_valid(n) or n.is_queued_for_deletion() or not bool(ok.call(n)):
			continue
		var d := (n as Node2D).global_position.distance_squared_to(_player.global_position)
		if d < bd:
			bd = d
			best = n
	return best

## Znaczniki rzutu mapy: cel (najbliższy), wyjście / drezyna w ekstrakcji, koledzy z drużyny, powaleni.
func _drive_strip(m: Node) -> void:
	_minimap.visible = m.kind != "hub" and _player != null
	if not _minimap.visible:
		return
	_minimap.player_pos = _player.global_position
	var mk: Array = []
	var goal: Node2D = null
	var label := ""
	match m.phase:
		Mission.Phase.OBJECTIVE:
			match String(m.kind):
				"tags":
					goal = _nearest("pickups", func(n: Node) -> bool: return String(n.get("kind")) == "tag")
					label = tr("TAG")
				"generators":
					goal = _nearest("generators", func(n: Node) -> bool: return not bool(n.get("running")))
					label = tr("GEN")
				"boss":
					goal = _nearest("boss", func(_n: Node) -> bool: return true)
					label = tr("BOSS")
				_:
					goal = _nearest("nests", func(n: Node) -> bool: return bool(n.get("alive")))
					label = tr("NEST")
		Mission.Phase.BOSS:
			goal = _nearest("boss", func(_n: Node) -> bool: return true)
			label = tr("BOSS")
		Mission.Phase.EXTRACT:
			var car := _nearest("handcar", func(n: Node) -> bool: return not bool(n.get("arrived")))
			if car != null:
				mk.append({"pos": car.global_position, "kind": "obj", "label": tr("CAR"), "col": UiTheme.ACCENT})
			mk.append({"pos": m.exit_pos, "kind": "exit", "label": tr("EXIT"), "col": Color(UiTheme.TEXT, 0.8)})
	if goal != null:
		mk.append({"pos": goal.global_position, "kind": "obj", "label": label, "col": UiTheme.ACCENT})
	for node in get_tree().get_nodes_in_group("players"):
		var pl: Node = node
		if pl == _player or not is_instance_valid(pl) or pl.is_queued_for_deletion():
			continue
		var slot := ((int(pl.display_id) - 1) % 4) + 1
		var col: Color = UiTheme.DANGER if pl.dead else (Color("8d8a7c") if pl.is_bot else SLOT_COLORS[slot - 1])
		mk.append({"pos": (pl as Node2D).global_position, "kind": "down" if pl.dead else "mate", "label": "P%d" % int(pl.display_id), "col": col})
	_minimap.markers = mk

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
## Karta informacyjna. `note` >= 0 to notatka-papier (NotePaper) w materiale UiTheme.Note.*: kolory i krój z palety notatki, tło rysuje komponent;
## -1 to ciemna karta HUD. Zwraca słownik z węzłami do wypełnienia przez `_fill_info`.
func _make_info_card(width: float, cols: int, note := -1) -> Dictionary:
	var paper: bool = note >= 0
	var card: PanelContainer
	var pal: Dictionary = UiTheme.note_palette(note) if paper else {}
	if paper:
		var np := NotePaper.new()
		np.set_kind(note)
		np.position = Vector2(MARGIN, MARGIN)
		add_child(np)
		card = np
	else:
		card = _card(Vector2(MARGIN, MARGIN))
	card.custom_minimum_size = Vector2(width, 0)
	card.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var title := UiTheme.heading("", UiTheme.note_size(note, 11) if paper else 8, pal.get("accent", UiTheme.ACCENT))
	var tag := UiTheme.label("", UiTheme.note_size(note, 7) if paper else UiTheme.T_CAPTION, pal.get("dim", UiTheme.MUTED))
	var text := UiTheme.label("", UiTheme.note_size(note, 8) if paper else UiTheme.T_CAPTION, pal.get("ink", UiTheme.TEXT))
	if paper:
		for l in [title, tag, text]:
			(l as Label).add_theme_font_override("font", UiTheme.note_font(note))
			(l as Label).add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	box.add_child(tag)
	if paper:
		var r := ColorRect.new()
		r.color = Color(pal["ink"], 0.4)
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
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(width - 52.0 if paper else width - 26.0, 0)
	box.add_child(text)
	return {"card": card, "title": title, "tag": tag, "grid": grid, "text": text, "cols": cols, "paper": paper, "mat": note}

func _fill_info(c: Dictionary, title: String, tag: String, rows: Array, text: String, accent: Color) -> void:
	var paper: bool = bool(c.get("paper", false))
	var mat: int = int(c.get("mat", -1))
	var pal: Dictionary = UiTheme.note_palette(mat) if paper else {}
	(c["title"] as Label).text = title
	(c["title"] as Label).add_theme_color_override("font_color", pal["accent"] if paper else accent)
	if paper:
		(c["title"] as Label).add_theme_font_size_override("font_size", UiTheme.note_size(mat, 11 if title.length() <= 18 else 9))   # długie tytuły (odprawa) mniejszym krojem
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
			var gl := UiTheme.label(String(r[i]), UiTheme.note_size(mat, 8) if paper else 9, (pal["dim"] if i == 0 else pal["ink"]) if paper else (UiTheme.MUTED if i == 0 else UiTheme.TEXT))
			if paper:
				gl.add_theme_font_override("font", UiTheme.note_font(mat))
				gl.add_theme_constant_override("outline_size", 0)
			grid.add_child(gl)
	(c["card"] as Control).reset_size()

## Papier w świecie 3D (MESSAGES_PLAN.md, 2b): te same notatki (odprawa przy tablicy, prognoza nad radiostacją) rysowane do tekstury w SubViewport.
## view3d.gd (_sync_world_notes) kładzie ją na kartce przypiętej do tablicy / ściany, oświetlonej lampami sceny. Karta HUD zostaje jako widok „czytam z bliska”
## (papier w świecie chowa się, gdy karta HUD jest widoczna). Zawartość odświeża się tylko przy zmianie klucza (cel misji, pogoda, zużycie).
const WORLD_NOTE_K := 2.0                         ## ostrość tekstury papieru w świecie (piksele na jednostkę HUD)
var _wn := {}                                     ## rodzaj ("brief" / "radio") → {vp, info, key, busy}

func _build_world_notes() -> void:
	for spec in [["brief", 310.0, 4, UiTheme.Note.DOSSIER], ["radio", 300.0, 2, UiTheme.Note.PRINTOUT]]:
		var info := _make_info_card(float(spec[1]), int(spec[2]), int(spec[3]))
		var card := info["card"] as NotePaper
		remove_child(card)
		card.visible = true
		card.tail = false                          # w świecie kartka wisi na tablicy, bez ogonka wskazującego obiekt
		if String(spec[0]) == "brief":
			card.stamp = tr("CLASSIFIED")
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.size = Vector2i(16, 16)
		vp.add_to_group("world_note")
		vp.set_meta("kind", String(spec[0]))
		add_child(vp)
		vp.add_child(card)
		card.scale = Vector2.ONE * WORLD_NOTE_K
		_wn[String(spec[0])] = {"vp": vp, "info": info, "key": "", "busy": false}

func _wn_hide(kind: String, hud_visible: bool) -> void:
	if _wn.has(kind):
		((_wn[kind] as Dictionary)["vp"] as SubViewport).set_meta("hide", hud_visible)

## Co klatkę tanio sprawdza klucze treści; przy zmianie wypełnia kartę, czeka na układ i raz renderuje teksturę.
func _refresh_world_notes() -> void:
	if get_tree().get_first_node_in_group("board") == null and get_tree().get_first_node_in_group("radio_set") == null:
		return
	var main := get_tree().current_scene
	var target := String(main.get("after_hub")) if main != null else ""
	var wear_i := int(clampf(float(RunLog.total_downs()) / 10.0, 0.0, 1.0) * 10.0)
	for kind in _wn:
		var d: Dictionary = _wn[kind]
		var key := ("%s|%d" % [target, wear_i]) if kind == "brief" else ("%s|%s|%d" % [Weather.forecast, target, wear_i])
		if key != String(d["key"]) and not bool(d["busy"]):
			d["key"] = key
			_update_world_note(String(kind), target)

func _update_world_note(kind: String, target: String) -> void:
	var d: Dictionary = _wn[kind]
	d["busy"] = true
	var info: Dictionary = d["info"]
	var card := info["card"] as NotePaper
	var lvl := get_tree().get_first_node_in_group("level")
	if kind == "brief":
		_fill_brief(lvl.briefing(target) if lvl != null and target != "" else {}, info)
	else:
		_fill_radio(info, target)
	card.wear = clampf(float(RunLog.total_downs()) / 10.0, 0.0, 1.0)
	card.tally = RunLog.entries.size()
	card.scale = Vector2.ONE
	card.reset_size()
	await get_tree().process_frame
	card.reset_size()
	var pad := Vector2(14.0, 18.0)
	var vp := d["vp"] as SubViewport
	vp.size = Vector2i((card.size + pad * 2.0) * WORLD_NOTE_K)
	card.scale = Vector2.ONE * WORLD_NOTE_K
	card.position = pad * WORLD_NOTE_K
	await get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	d["busy"] = false

## Notatki zależą od otoczenia: w półmroku ciemniejsze (jasność z koloru ciemności mapy), a zużycie rośnie z upadkami drużyny w kampanii (RunLog).
func _dress_note(c: Dictionary) -> void:
	var n := c["card"] as NotePaper
	var lvl := get_tree().get_first_node_in_group("level")
	var amb: Color = lvl.ambient if lvl != null else Color(0.1, 0.1, 0.1)
	var lit := clampf(0.62 + amb.get_luminance() * 1.6, 0.6, 1.0)
	n.modulate = Color(lit, lit, lit, 1.0)
	n.wear = clampf(float(RunLog.total_downs()) / 10.0, 0.0, 1.0)
	n.tally = RunLog.entries.size()

## Karty: statystyki broni w zasięgu [E] (nad paskiem kontekstowym) i odprawa przy tablicy (u góry, pod kartą celu).
func _drive_cards() -> void:
	if _in_range():                                  # strzelnica FPP: postać stoi zaparkowana w kryjówce — jej tablica i radio nie dotyczą tunelu
		_inspect.close()
		(_brief["card"] as Control).visible = false
		(_radio["card"] as Control).visible = false
		return
	# --- oględziny broni ([F] przy stojaku albo broni na ziemi): ekran z rozmytym tłem, bronią i panelem statystyk; gra się nie zatrzymuje
	var it: Node2D = null
	if _player != null and not _player.dead and _player.weapons.inspect_item != null and is_instance_valid(_player.weapons.inspect_item):
		it = _player.weapons.inspect_item
	_inspect.position = Vector2.ZERO
	_inspect.size = size
	if it != null:
		var wid := int(it.arg)
		var wc: Node = _player.weapons
		var nd: RefCounted = Weapons.def(wid)
		var lvl_i := get_tree().get_first_node_in_group("level")
		var locked: bool = lvl_i != null and lvl_i.is_locked_item(it)
		var hand: int = wc.melee_id if nd.slot == Weapons.Slot.MELEE else wc.loadout[wc.slot if wc.slot < 2 else 0]
		var gk = it.get("_hd_gun")
		var foot := Actions.fmt(tr("[{flare}]  Close")) if locked else Actions.fmt(tr("[{interact}]  Take   ·   [{flare}]  Close"))
		var cab := it.has_meta("cabinet")                     # gablota: kamera patrzy na gablotę, ↑ / ↓ wybiera broń
		if cab:
			foot = Actions.fmt(tr("[{move_up}] [{move_down}]  Select")) + "   ·   " + foot
		_inspect.show_weapon(wid, String(gk) if gk != null and String(gk) != "" else String(nd.key), hand, Scrap.lock_text(wid) if locked else "", foot, cab)
	else:
		_inspect.close()
	# --- odprawa przy tablicy
	var near_board := false
	var board: Node2D = null
	for b in get_tree().get_nodes_in_group("board"):
		if b.local_in_range:
			near_board = true
			board = b
			break
	var bc: Control = _brief["card"]
	bc.visible = near_board and Msg.current(Msg.Ch.ALERT).is_empty()      # alert (odliczanie wyjścia) ma pierwszeństwo przed notatką
	_wn_hide("brief", bc.visible)
	if bc.visible:
		_dress_note(_brief)
		var main := get_tree().current_scene
		var target := String(main.get("after_hub")) if main != null else ""
		var lvl := get_tree().get_first_node_in_group("level")
		if target != _brief_id and lvl != null:
			_brief_id = target
			_fill_brief(lvl.briefing(target))
		# nad tablicą (jak karta broni), więc nie zasłania stojącego przy niej gracza
		var btop: Vector2 = get_viewport().get_canvas_transform() * (board.global_position + Vector2(0, -46))
		bc.scale = Vector2.ONE * MSG_SCALE
		bc.pivot_offset = Vector2(bc.size.x * 0.5, bc.size.y)
		bc.position = Vector2(clampf(btop.x / scale.x - bc.size.x * 0.5, 6.0, maxf(6.0, size.x - bc.size.x - 6.0)), maxf(6.0, btop.y / scale.y - bc.size.y - 12.0))
	_drive_radio()
	_refresh_world_notes()

## Prognoza z radiostacji (weather.gd): nazwa pogody, jej plusy i minusy, tytuł następnej misji.
## Treść prognozy (nazwa pogody, plusy i minusy, tytuł następnej misji) do karty HUD albo papieru w świecie.
func _fill_radio(c: Dictionary, target: String) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var info: Dictionary = lvl.briefing(target) if lvl != null and target != "" else {}
	var tag := ("Next: " + String(info["title"])) if not info.is_empty() else "Next mission"
	var id: String = Weather.forecast
	_fill_info(c, "WEATHER FORECAST", tag, [[Weather.color_of(id), Weather.name_of(id)]], Weather.text_of(id), UiTheme.ACCENT)

func _drive_radio() -> void:
	var near := false
	var rset: Node2D = null
	for rs in get_tree().get_nodes_in_group("radio_set"):
		if rs.local_in_range:
			near = true
			rset = rs
			break
	var rc: Control = _radio["card"]
	rc.visible = near and Msg.current(Msg.Ch.ALERT).is_empty()
	_wn_hide("radio", rc.visible)                  # papier w świecie chowa się, gdy ta sama treść jest czytelna w karcie HUD
	if not rc.visible:
		return
	_dress_note(_radio)
	var main := get_tree().current_scene
	var target := String(main.get("after_hub")) if main != null else ""
	var key := "%s|%s" % [Weather.forecast, target]
	if key != _radio_key:
		_radio_key = key
		_fill_radio(_radio, target)
	var rtop: Vector2 = get_viewport().get_canvas_transform() * (rset.global_position + Vector2(0, -40))
	rc.scale = Vector2.ONE * MSG_SCALE
	rc.pivot_offset = Vector2(rc.size.x * 0.5, rc.size.y)
	rc.position = Vector2(clampf(rtop.x / scale.x - rc.size.x * 0.5, 6.0, maxf(6.0, size.x - rc.size.x - 6.0)), maxf(6.0, rtop.y / scale.y - rc.size.y - 12.0))

func _fill_brief(info: Dictionary, c := {}) -> void:
	if c.is_empty():
		c = _brief
	if info.is_empty():
		_fill_info(c, "BRIEFING", "No orders yet", [], "", UiTheme.ACCENT)
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
	_fill_info(c, "BRIEFING  ·  " + String(info["title"]), "", rows, String(info["brief"]), UiTheme.ACCENT)

## Czy lokalny gracz stoi przy ławie warsztatu (kryjówka) i panel jest zamknięty.
func _near_workshop() -> bool:
	for w in get_tree().get_nodes_in_group("workshop"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy tokarce (kryjówka) i panel jest zamknięty.
func _near_lathe() -> bool:
	for w in get_tree().get_nodes_in_group("lathe_bench"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy pracowni (kryjówka, badania) i panel jest zamknięty.
func _near_lab() -> bool:
	for w in get_tree().get_nodes_in_group("lab_bench"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy stole pirotechnicznym (kryjówka) i panel jest zamknięty.
func _near_pyro() -> bool:
	for w in get_tree().get_nodes_in_group("pyro_bench"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy prasie elaboracyjnej (kryjówka, zamówienia amunicji specjalnej) i panel jest zamknięty.
func _near_press() -> bool:
	for w in get_tree().get_nodes_in_group("press_bench"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy stole konserwacji (kryjówka, czyszczenie i części eksploatacyjne) i panel jest zamknięty.
func _near_service() -> bool:
	for w in get_tree().get_nodes_in_group("service_bench"):
		if w.local_in_range:
			var ui := get_tree().get_first_node_in_group("workshop_ui")
			return ui == null or not ui.is_open()
	return false

## Czy lokalny gracz stoi przy szafkach osobistych (kryjówka, perki i wygląd) i panel jest zamknięty.
func _near_lockers() -> bool:
	for w in get_tree().get_nodes_in_group("locker_station"):
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
## Kandydaci paska akcji (kanał ACTION): kolejność na liście = waga (pierwszy najważniejszy), każdy z własnym warunkiem. Arbiter (Msg) wybiera
## najwyższą wagę — dawny łańcuch elif jako dane. Pusty tekst też bywa kandydatem: zagłusza niższe wagi (panel oględzin, wipe).
func _prompt_candidates() -> Array:
	var out: Array = []
	var add := func(text: String, prog := -1.0, col := UiTheme.TEXT) -> void:
		out.append({"text": text, "prog": prog, "col": col})
	var wipe_left: float = get_tree().current_scene.get("wipe_left") if get_tree().current_scene else 0.0
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	var gen := _near_generator()
	var car := get_tree().get_first_node_in_group("handcar")
	var grab_boss := _grab_boss()
	var tide_boss := _tide_boss()
	var alive: bool = _player != null and not _player.dead
	if wipe_left > 0.0:
		add.call("")                                                      # wipe: komunikat idzie kanałem alertu
	if grab_boss != null and alive:
		# chwyt Pijawki (QTE drużyny): ofiara i koledzy widzą ten sam pasek — ile obrażeń jeszcze brakuje do uwolnienia
		var mine: bool = int(grab_boss.grab_victim_id) == int(_player.player_id)
		add.call((tr("GRABBED — shoot the leech to break free  ·  %.0fs") if mine else tr("Teammate grabbed — shoot the leech!  ·  %.0fs")) % float(grab_boss.grab_time_left), float(grab_boss.grab_progress), UiTheme.DANGER)
	if tide_boss != null and alive:
		if String(tide_boss.surge_state) == "warn":
			add.call(tr("THE TIDE IS RISING — climb to the high catwalks!"), clampf(float(tide_boss._surge_t) / (float(tide_boss.SURGE_WARN) * Difficulty.m("boss_tide")), 0.0, 1.0), UiTheme.ACCENT)
		else:
			add.call(tr("FLOODED — stay on the high catwalks"), -1.0, UiTheme.DANGER)
	if _player != null and _player.dead:
		if _player.revive_progress > 0.0:
			add.call(tr("Being revived…"), _player.revive_progress, UiTheme.OK)
		elif _player.taken:
			add.call(tr("You were taken — your squad must kill the creature in %ds, or you return to the start without your kit") % ceili(_player.taken_t), _player.taken_t / 20.0, UiTheme.DANGER)
		else:
			add.call(tr("You're down — a teammate can revive you (bleeding out in %ds)") % ceili(_player.bleed_left), _player.bleed_left / _player.bleed_time(), UiTheme.DANGER)
	if _player != null and _player.revive_hint() != "":
		add.call(_player.revive_hint(), -1.0, UiTheme.OK)
	if _player != null and _player.gear_text != "":
		# narzędzia (lewy Alt): apteczka, defibrylator, skaner — podpowiedź albo trwające użycie
		add.call(_player.gear_text, _player.gear_progress, UiTheme.OK if _player.gear_progress > 0.0 else UiTheme.ACCENT)
	if car != null and car.local_state != "" and _player != null:
		match String(car.local_state):
			"nopower":
				add.call(tr("The handcar has no power — start all the generators"), -1.0, UiTheme.MUTED)
			"near":
				add.call(tr("Step onto the handcar"), -1.0, UiTheme.ACCENT)
			"aboard":
				add.call(Actions.fmt(tr("Hold [{interact}]  Pump  (you can't shoot while pumping)")), -1.0, UiTheme.ACCENT)
			"pumping":
				add.call(Actions.fmt(tr("Pumping…  release [{interact}] to shoot")), -1.0, UiTheme.OK)
	if gen != null and _player != null and _player.weapons.nearby_weapon_item() == null:
		if gen.progress > 0.0:
			add.call(tr("Starting the generator…"), gen.progress, UiTheme.OK)
		else:
			add.call(Actions.fmt(tr("Hold [{interact}]  Start the generator  (loud)")), -1.0, UiTheme.ACCENT)
	if _near_workshop():
		add.call(tr("[%s]  Workshop  ·  SCRAP %d") % [Actions.key("interact"), Scrap.bank], -1.0, UiTheme.ACCENT)
	if _near_lathe():
		add.call(tr("[%s]  Lathe and grinder  ·  %d schematics") % [Actions.key("interact"), Scrap.schematics.size()], -1.0, UiTheme.ACCENT)
	if _near_lab():
		add.call(tr("[%s]  Lab  ·  %d samples  ·  research for special weapons") % [Actions.key("interact"), Scrap.samples], -1.0, UiTheme.ACCENT)
	if _near_pyro():
		add.call(tr("[%s]  Pyrotechnics  ·  grenades, mines, fuses") % Actions.key("interact"), -1.0, UiTheme.ACCENT)
	if _near_press():
		add.call(tr("[%s]  Reloading press  ·  %d / %d batches ordered") % [Actions.key("interact"), Scrap.orders.size(), Scrap.PRESS_SLOTS], -1.0, UiTheme.ACCENT)
	if _near_service():
		add.call(tr("[%s]  Maintenance  ·  clean, barrels, springs") % Actions.key("interact"), -1.0, UiTheme.ACCENT)
	if _near_lockers():
		add.call(tr("[%s]  Locker  ·  perks and look") % Actions.key("interact"), -1.0, UiTheme.ACCENT)
	var rdoor := _near_range_door()
	if rdoor != null:
		var rb := float(rdoor.best())
		add.call((tr("[%s]  Shooting range  ·  squad record %.2f s") % [Actions.key("interact"), rb]) if rb >= 0.0 else tr("[%s]  Shooting range") % Actions.key("interact"), -1.0, UiTheme.ACCENT)
	if _player != null and _player.weapons.inspect_item != null:
		add.call("")                                                      # klawisze są w panelu oględzin
	if _player != null and _player.weapons.nearby_weapon_item() != null:
		var it: Node2D = _player.weapons.nearby_weapon_item()
		var nd: RefCounted = Weapons.def(it.arg)
		var lvl_p := get_tree().get_first_node_in_group("level")
		if lvl_p != null and lvl_p.is_locked_item(it):
			add.call(tr("LOCKED  ·  %s   ·   [%s]  Inspect") % [Scrap.lock_text(it.arg), Actions.key("flare")], -1.0, UiTheme.MUTED)
		else:
			var wc2: Node = _player.weapons
			var swap_out: String = Weapons.def(wc2.loadout[wc2.slot if wc2.slot < 2 else 0]).name if nd.slot == Weapons.Slot.PRIMARY else Weapons.def(wc2.melee_id).name
			var take_key := Actions.key("interact")
			var look_key := Actions.key("flare")
			add.call(tr("[%s]  Take %s  (drops %s)   ·   [%s]  Inspect") % [take_key, nd.name, swap_out, look_key] if not wc2.carries(it.arg) else tr("[%s]  Take ammo for %s   ·   [%s]  Inspect") % [take_key, nd.name, look_key], -1.0, UiTheme.ACCENT)
	if m != null and m.phase == Mission.Phase.EXTRACT:
		var st: Dictionary = m.local_extract_state()
		if st.get("inside", false):
			if m.extract_progress > 0.0:
				add.call(tr("EVACUATING…"), m.extract_progress, UiTheme.OK)
			else:
				add.call(tr("Hold here — the whole squad must reach the flare"), -1.0, UiTheme.ACCENT)
	return out

## Kolor akcji -> styl komunikatu (do dziennika i spójnego wyglądu).
func _style_of(col: Color) -> int:
	if col == UiTheme.DANGER:
		return Msg.Style.DANGER
	if col == UiTheme.OK:
		return Msg.Style.SUCCESS
	if col == UiTheme.ACCENT:
		return Msg.Style.ACTION
	return Msg.Style.INFO

## Karta tytułowa startu misji (kanał TITLE, dolna trzecia): tytuł, linie radia i jedna linia pogody; w Nocnym Dyżurze zasady serii.
## Cel misji zostaje w karcie celu (bez powtórzeń).
func _post_title(m: Node) -> void:
	var lvl := get_tree().get_first_node_in_group("level")
	var lines: Array = []
	var head := ""
	var kicker := ""
	if NightShift.active:
		head = NightShift.title()
		lines.append(String(lvl.title) if lvl != null else "")
		for id in NightShift.mods:
			lines.append("%s — %s" % [NightShift.MODS[id]["name"], NightShift.MODS[id]["text"]])
		if NightShift.stage > 1:
			lines.append(tr("Enemies +%d%% HP") % int(round(NightShift.HP_STEP * float(NightShift.stage - 1) * 100.0)))
		elif NightShift.mods.is_empty():
			lines.append(tr("The first mission — no modifiers"))
	else:
		head = String(lvl.title) if lvl != null else ""
		if lvl != null and not (lvl.radio as Array).is_empty():
			kicker = tr("RADIO")
			for rl in lvl.radio:
				lines.append(tr(String(rl)))
	if not NightShift.active and Weather.active_id() != "":
		lines.append(tr("WEATHER — %s: %s") % [Weather.name_of(Weather.active_id()), Weather.text_of(Weather.active_id())])
	Msg.hold("hud.title", Msg.Ch.TITLE, head, {"sub": "\n".join(lines), "kicker": kicker, "style": Msg.Style.DANGER, "prio": 50, "log": true})

func _drive_prompt() -> void:
	var text := ""
	var prog := -1.0
	var col := UiTheme.TEXT
	var wipe_left: float = get_tree().current_scene.get("wipe_left") if get_tree().current_scene else 0.0
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if wipe_left > 0.0:
		Msg.hold("hud.wipe", Msg.Ch.ALERT, tr("SQUAD DOWN"), {"sub": (tr("Extraction failed — the shift ends in %d") if NightShift.active else tr("Extraction failed — restarting the mission in %d")) % ceili(wipe_left), "style": Msg.Style.DANGER, "prio": 90})
	var in_range := _in_range()
	var cands := [] if in_range else _prompt_candidates()
	for i in cands.size():
		var c: Dictionary = cands[i]
		Msg.hold("hud.action.%d" % i, Msg.Ch.ACTION, String(c["text"]), {"prio": 100 - i * 4, "progress": float(c["prog"]), "style": _style_of(c["col"]), "color": c["col"]})
	var cur: Dictionary = Msg.current(Msg.Ch.ACTION)
	if not cur.is_empty():
		text = String(cur["text"])
		prog = float(cur["progress"])
		col = cur.get("color", UiTheme.TEXT)
	if wipe_left <= 0.0 and m != null and m.banner_visible() and not _inspect.visible and not in_range:
		_post_title(m)
	# ostatnia transmisja patrolu w finale misji 1.1 (zamiast baneru tytułu)
	if wipe_left <= 0.0 and m != null and m.finale_radio_line() != "":
		Msg.hold("hud.finale", Msg.Ch.TITLE, tr("PATROL SEVEN — RADIO"), {"sub": m.finale_radio_line(), "kicker": tr("RADIO"), "style": Msg.Style.DANGER, "prio": 80, "log": true})
	_prompt_card.visible = text != ""
	if _prompt_card.visible:
		_prompt.text = "[center]" + UiTheme.keycaps(text) + "[/center]"
		_prompt.add_theme_color_override("default_color", col)
		_prompt_bar.visible = prog >= 0.0
		_prompt_bar.value = prog
		_prompt_bar.fill = col
		_prompt_bar.queue_redraw()
		_prompt_card.reset_size()
		_prompt_card.scale = Vector2.ONE * MSG_SCALE
		_prompt_card.pivot_offset = Vector2(_prompt_card.size.x * 0.5, 0.0)
		_prompt_card.position = Vector2((size.x - _prompt_card.size.x) * 0.5, _gear_card.position.y - _prompt_card.size.y * MSG_SCALE - 8.0)

## Drzwi strzelnicy FPP, przy których stoi lokalny gracz (range_door.gd), albo null.
func _near_range_door() -> Node:
	for d in get_tree().get_nodes_in_group("range_door"):
		if bool(d.local_in_range):
			return d
	return null

## Lokalny gracz jest na strzelnicy FPP (scripts/range3d/fp_mode.gd).
func _in_range() -> bool:
	if _player != null and is_instance_valid(_player) and _player.get("fp") != null:
		return true
	var rv := get_tree().get_first_node_in_group("range_view")     # wyjście: tunel jeszcze gaśnie (range_view.gd, faza OUT)
	return rv != null and bool(rv.call("fading_out"))

func _drive_controls() -> void:
	var show := (_session_t < CONTROLS_SHOW_S and Profile.level() <= TOAST_LEVEL_MAX) if _controls_mode < 0 else _controls_mode == 1
	var range_ctx := _in_range()
	if range_ctx != _controls_range or (show and not _controls.visible):     # kontekst „range”: ściąga strzelnicy (Actions.RANGE_SHEET)
		_controls_range = range_ctx
		_controls.text = Actions.range_hud_line() if range_ctx else Actions.hud_line()
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

## Skład sesji do nagłówka karty drużyny: „HOST · 1/4 +1 AI” (solo: „SOLO”).
func _net_status() -> String:
	if not NoiseMgr.has_network():
		return "SOLO"
	var humans := 0
	var bots := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot:
			bots += 1
		else:
			humans += 1
	var who := "HOST" if multiplayer.is_server() else "CLIENT"
	return "%s · %d/4%s" % [who, humans, (" +%d AI" % bots) if bots > 0 else ""]
