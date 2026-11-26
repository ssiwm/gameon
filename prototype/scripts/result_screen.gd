extends Control
## Raport po akcji (RESULTS_PLAN.md): ekran po zakończonej misji zamiast dawnej statycznej karty wyniku.
##
## Kolejność odsłaniania: wynik (tytuł) → kafelki celów („za co”, z nagrodą) → złom drużyny → twoje XP z paskiem poziomu
## i awansem → drużyna z wyróżnieniami i gotowością → znaleziska → akcje. Całość ok. 5,2 s, pierwsze naciśnięcie pomija do końca,
## „Ogranicz efekty” pokazuje od razu stan końcowy.
##
## Dwie warstwy (RESULTS_PLAN.md §15): **skrót** (domyślny — wynik, nagrody, drużyna; każda liczba raz) i **Szczegóły** pod akcją
## `result_details` (pełne rozbicie złomu i XP, uzasadnienia wyróżnień, przebieg misji z legendą, próba, towarzysz AI). Tytuł, kafelki
## i stopka są wspólne, więc panel nie skacze. Liczniki złomu i XP to bębenki jak w liczniku magnetofonu, pasek XP jest „diodowy” jak
## miernik hałasu, awans przyszywa naszywkę, a karty mają fakturę papieru i mosiężną krawędź (materiał deski HUD-u).
## Od S2: nad tytułem wpis radiowy („KANAŁ n · BAZA ODEBRAŁA”, przy przerwanej serii „CISZA W ETERZE”) z krótkim szumem odbioru,
## a gracz to nieśmiertelnik — portret w stroju (art/portraits/look_*) i stalowa blaszka z wytłoczonym kryptonimem i liczbami.
## Od S3 skrót jest sceną: cele w lewej kolumnie, łup w prawej, nieśmiertelniki u dołu, a środek ekranu zostaje dla drużyny w 3D
## (kamera powoli odjeżdża nad wyjście — player.gd `_result_camera`; gdy Stalker się obudził, jego sylwetka staje na chwilę w linii
## drzew — view3d.gd `_sync_lurker`, czas z `lurk_t`). Szczegóły zostają panelem na środku.
##
## Dane: `collect(mission)` zbiera wszystko z węzłów i autoloadów do słownika `ctx`, a statyczne `build_model(ctx)` liczy z niego
## czysty model (tytuł, kafelki, liczniki, drużyna, czasy etapów) — test `--resulttest` sprawdza go bez rysowania.
## Animacja jest funkcją czasu `t` (`advance`), więc pominięcie to po prostu `t = end`.
##
## Każdy peer odtwarza raport sam; akcje rozstrzyga main.gd (`result_action`): host zmienia mapę, klient zgłasza gotowość.
## Przełączanie Szczegółów jest lokalne i nie idzie do main.gd.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Mission := preload("res://scripts/mission.gd")
const Actions := preload("res://scripts/actions.gd")
const NightShift := preload("res://scripts/night_shift.gd")
const Parts := preload("res://scripts/parts.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Look := preload("res://scripts/look.gd")

## Czasy sekwencji (s od otwarcia) — wszystkie w jednym miejscu (RESULTS_PLAN.md §4).
const T_TITLE := 0.25
const T_SUB := 0.55
const T_RADIO := 0.5                  ## wpis radiowy nad tytułem i szum odbioru (§15 pomysł 5)
const SUB_DUR := 0.45
const T_TILES := 0.9
const TILE_GAP := 0.22
const T_SCRAP := 1.9
const SCRAP_DUR := 0.9
const T_XP := 2.8
const XP_DUR := 1.6
const T_SQUAD := 4.4
const SQUAD_GAP := 0.1
const T_AWARDS := 4.7
const AWARD_GAP := 0.15
const T_FINDS := 5.0
const FIND_GAP := 0.15
const T_DONE := 5.2
const STAMP_DUR := 0.16
const FADE_DUR := 0.22
const HUD_FADE := 0.3                 ## s, w których HUD rozgrywki gaśnie pod raportem
const INPUT_LOCK := 0.6               ## s od otwarcia, przez które raport ignoruje wejście (E z ekstrakcji, Enter z czatu)
const DATA_WAIT := 1.5                ## s, które etap złomu / XP czeka na dane od serwera, zanim pójdzie dalej bez nich
const CUE_GAP := 0.4                  ## s: najmniejszy odstęp sygnałów raportu; z bliższych zostaje ważniejszy (CUE_PRIO)
## Waga sygnału przy zderzeniu w CUE_GAP: rekord > awans > pieczątka > licznik.
const CUE_PRIO := {"record": 3, "levelup": 2, "radio": 1, "stamp": 1, "tick": 0}
const LEVELUP_DUCK_DB := -6.0         ## przyciszenie kadencji wyniku pod `ui_levelup`
const LEVELUP_DUCK_S := 1.6
const LEVEL_FLASH := 0.12             ## s rozjaśnienia paska przy awansie
const DIM := 0.65                     ## ściemnienie świata pod Szczegółami
const DIM_SCENE := 0.18               ## ściemnienie świata pod skrótem — środek ma być widać (drużyna w 3D); krawędzie przyciemnia Scrim
const DESIGN := Vector2(1344, 756)    ## płótno raportu w jednostkach HUD (ekran HUD przy skali NORMAL); większa skala UI je pomniejsza
const EDGE := 36.0                    ## margines płótna
const COL_W := 330.0                  ## szerokość kolumn celów i łupu
const DET_W := 900.0                  ## szerokość panelu Szczegółów
const TAG_W := 310.0                  ## szerokość karty nieśmiertelnika
const TITLE_FS := 48                  ## tytuł sceny (przed _f): ok. 1/3 szerokości ekranu, jak w makiecie §15 (1.7.697: 34 — ok. 1/4)
const PORTRAIT := 50                  ## bok portretu na nieśmiertelniku (przed _f); 1.7.697: 27 — portret ginął przy 1080p
const TAG_GAP := 10

const PAD := 24.0
const FS := 1.4                       ## mnożnik krojów: HUD rysuje w ~0,48 (UI_SCALE × NORMAL), a raport ma mieć min. ~14 px przy 1080p
const XP_COL := Color(0.902, 0.886, 0.769)     ## liczba XP: kość (WARM)
const LOCKED := Color(0.42, 0.41, 0.37)        ## nagroda, której nie zdobyto
const BRASS := Color(0.54, 0.42, 0.20)         ## górna krawędź kart: mosiądz deski HUD-u (§15 pomysł 7)
const CARD_BG := Color("0e0f0d")
const XP_SEGS := 24
const UNLOCKS_SHORT := 2              ## odblokowania awansu w skrócie (reszta jako „+N”, pełna lista w Szczegółach)                   ## segmenty „diodowego” paska XP (jak miernik hałasu, §15 pomysł 6)
const PART_ICON := "res://art/hud/parts/%s.png"    ## ikony części z modeli (tools/bake_hud_icons.gd --parts)
const HUD_ICON := "res://art/hud/%s.png"
const LOOK_PORTRAIT := "res://art/portraits/look_%s_%s.png"   ## render stroju (tools/bake_look_portraits.gd) — portret na nieśmiertelniku
const STEEL := Color(0.56, 0.58, 0.59)          ## blacha nieśmiertelnika
const EMBOSS := Color(0.13, 0.14, 0.15)         ## wytłoczenie na blasze (z jasnym cieniem pod spodem)

## Dźwięki raportu: [klucz manifestu, głośność dB] — wysokość podaje etap. Generator: tools/bake_sfx.py (build_ui).
const SND := {
	"stamp": ["ui_stamp", -6.0], "tick": ["ui_tick", -14.0],
	"levelup": ["ui_levelup", -4.0], "skip": ["ui_confirm", -8.0], "record": ["radio_beep", -10.0],
	"radio": ["ui_radio_rx", -8.0], "toggle": ["ui_click", -10.0],
}
## Kolory slotów graczy — te same co w HUD (hud.gd SLOT_COLORS, kurtki postaci).
const SLOT_COLORS := [Color(0.91, 0.62, 0.22), Color(0.25, 0.72, 0.85), Color(0.86, 0.28, 0.36), Color(0.45, 0.80, 0.30)]

## Przebieg misji (P2): rodzaj zdarzenia → [znak, kolor]. Kolejność = legenda.
const MARKS := {
	"objective": ["◆", Color(0.851, 0.573, 0.18)], "stash": ["◇", Color(0.851, 0.573, 0.18)], "boss": ["■", Color(0.898, 0.282, 0.227)],
	"woke": ["▲", Color(0.898, 0.282, 0.227)], "down": ["✕", Color(0.898, 0.282, 0.227)], "revive": ["✚", Color(0.541, 0.659, 0.475)],
	"escape": ["!", Color(0.902, 0.886, 0.769)], "lure": ["○", Color(0.435, 0.639, 0.608)], "extract": ["┃", Color(0.541, 0.659, 0.475)],
}
const MARK_NAMES := {"objective": "objective", "boss": "boss", "woke": "Stalker woke", "down": "down", "revive": "revive",
	"escape": "close call", "lure": "lure", "extract": "extraction"}

## Warstwa Szczegóły (§15.2): wybór trwa do końca sesji (następny raport otwiera się w tej samej warstwie po sekwencji).
static var details_pref := false
static var _inst: WeakRef               ## bieżący raport (jeden na HUD) — dla `showing()` i `lurk_age()` bez szukania po drzewie

## Czy raport jest teraz na ekranie (celownik i plakietki graczy chowają się pod sceną raportu).
static func showing() -> bool:
	var n: Node = _inst.get_ref() if _inst != null else null
	return n != null and is_instance_valid(n) and (n as CanvasItem).is_visible_in_tree()

## Czas od otwarcia raportu, w którym Stalker może stanąć w linii drzew (view3d.gd `_sync_lurker`); −1 = nie teraz. Tylko po udanej
## misji z przebudzonym Stalkerem, poza Nocnym Dyżurem i bez „Ogranicz efekty”.
static func lurk_age() -> float:
	if not showing():
		return -1.0
	var n: Node = _inst.get_ref()
	return float(n.get("_age")) if bool((n.get("model") as Dictionary).get("lurk", false)) and Settings.fx_mult() > 0.0 else -1.0

## Karta raportu: ciemny papier z lekką fakturą i mosiężną górną krawędzią (materiał deski HUD-u i stanowisk kryjówki).
class Card extends PanelContainer:
	static var _grain: NoiseTexture2D
	var edge: Color = BRASS
	func _init(bg: Color, line: Color, pad: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = line
		sb.set_border_width_all(1)
		sb.set_content_margin_all(pad)
		add_theme_stylebox_override("panel", sb)
	func _ready() -> void:
		if _grain == null:
			var nz := FastNoiseLite.new()
			nz.noise_type = FastNoiseLite.TYPE_VALUE
			nz.frequency = 0.45
			nz.fractal_octaves = 2
			_grain = NoiseTexture2D.new()
			_grain.width = 96
			_grain.height = 96
			_grain.seamless = true
			_grain.noise = nz
		if not _grain.changed.is_connected(queue_redraw):
			_grain.changed.connect(queue_redraw)
	func _draw() -> void:
		if _grain != null:
			draw_texture_rect(_grain, Rect2(Vector2.ZERO, size), true, Color(1.0, 0.94, 0.8, 0.05))
		if edge.a > 0.0:
			draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), edge, 1.0)

## Znak stanu celu: ✓ w kółku (zaliczony) albo ✕ (stracony). Kształt, nie tylko kolor (RESULTS_PLAN.md §9).
class Mark extends Control:
	var ok := true
	func _init(is_ok: bool, s: float) -> void:
		ok = is_ok
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var col: Color = UiTheme.OK if ok else UiTheme.MUTED
		draw_circle(c, r, Color(col, 0.12))
		draw_arc(c, r, 0.0, TAU, 28, col, 1.2, true)
		if ok:
			draw_polyline(PackedVector2Array([c + Vector2(-0.45, 0.02) * r, c + Vector2(-0.1, 0.38) * r, c + Vector2(0.5, -0.42) * r]),
				UiTheme.OK.lightened(0.2), maxf(1.5, r * 0.22), true)
		else:
			var d := r * 0.42
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), col, 1.4, true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), col, 1.4, true)

## Moneta złomu (zamiast słowa „złomu” przy nagrodzie).
class Coin extends Control:
	var dim := false
	func _init(s: float, is_dim := false) -> void:
		dim = is_dim
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var a := 0.45 if dim else 1.0
		draw_circle(c, r, Color(0.5, 0.36, 0.1, a))
		draw_circle(c, r * 0.8, Color(0.95, 0.78, 0.32, a))
		draw_arc(c, r * 0.52, 0.0, TAU, 20, Color(0.5, 0.36, 0.1, a), 0.8, true)

## Kreska przez nagrodę, której nie zdobyto (zamiast słów „nie zdobyto:”).
class Strike extends Control:
	var col: Color
	func _init(c: Color) -> void:
		col = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_line(Vector2(0, size.y * 0.55), Vector2(size.x, size.y * 0.55), col, 1.0)

## Ikona statystyki gracza: czaszka (zabójstwa), ✕ (upadki), krzyż (podniesienia) — zamiast nagłówka „ZAB. · UPADKI · PODN.”.
class StatIcon extends Control:
	var kind := ""
	var col: Color = UiTheme.MUTED
	func _init(k: String, s: float) -> void:
		kind = k
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var w := size.x
		var h := size.y
		match kind:
			"kills":
				draw_circle(Vector2(w * 0.5, h * 0.42), w * 0.38, col)
				draw_rect(Rect2(w * 0.3, h * 0.55, w * 0.4, h * 0.33), col)
				draw_circle(Vector2(w * 0.36, h * 0.44), w * 0.1, UiTheme.GROUND)
				draw_circle(Vector2(w * 0.64, h * 0.44), w * 0.1, UiTheme.GROUND)
			"downs":
				draw_line(Vector2(w * 0.18, h * 0.18), Vector2(w * 0.82, h * 0.82), col, maxf(1.5, w * 0.16))
				draw_line(Vector2(w * 0.82, h * 0.18), Vector2(w * 0.18, h * 0.82), col, maxf(1.5, w * 0.16))
			"revives":
				draw_rect(Rect2(w * 0.38, h * 0.1, w * 0.24, h * 0.8), col)
				draw_rect(Rect2(w * 0.1, h * 0.38, w * 0.8, h * 0.24), col)

## Bębenek licznika (cyfra przewija się w okienku). `v` 0..10: część ułamkowa to obrót do następnej cyfry.
class Drum extends Control:
	var v := 0.0
	var blank := false
	var font: Font
	var fs := 16
	var col := Color.WHITE
	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0b0c0a"))
		if font != null:
			var base := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
			if blank:
				var ds := font.get_string_size("-", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, Vector2((size.x - ds.x) * 0.5, base), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, 0.5))
			else:
				var d := int(floorf(v)) % 10
				var f := v - floorf(v)
				for k in 2:
					var s := str((d + k) % 10)
					var ss := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
					draw_string(font, Vector2((size.x - ss.x) * 0.5, base + (float(k) - f) * size.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_rect(Rect2(0, 0, size.x, size.y * 0.2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(0, size.y * 0.8, size.x, size.y * 0.2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE2, false, 1.0)

## Licznik bębnowy jak w magnetofonie (§15 pomysł 4): wyższa cyfra obraca się dopiero przy przeniesieniu.
class Odometer extends HBoxContainer:
	var text := ""                    ## to, co licznik pokazuje („+228” albo „…”) — test i czytniki
	var _drums: Array = []
	func _init(n: int, fs: int, col: Color) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		var plus := UiTheme.mono(UiTheme.label("+", fs, col))
		plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(plus)
		var font := UiTheme.mono_font()
		var dw := font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		for i in n:
			var d := Drum.new()
			d.font = font
			d.fs = fs
			d.col = col
			d.custom_minimum_size = Vector2(ceilf(dw), ceilf(float(fs) * 1.3))
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(d)
			_drums.append(d)
	func set_value(v: float, is_ready: bool) -> void:
		text = ("+%d" % int(round(v))) if is_ready else "…"
		var n := _drums.size()
		for i in n:
			var p := n - 1 - i
			var big := pow(10.0, float(p))
			var x := v / big
			var f := 0.0
			if p == 0:
				f = x - floorf(x)
			else:
				var low := fmod(v, big)
				if low > big - 1.0:
					f = low - (big - 1.0)
			var dr: Drum = _drums[i]
			dr.v = fmod(floorf(x), 10.0) + f
			dr.blank = not is_ready
			dr.queue_redraw()

## Pasek poziomu „diodowy” (§15 pomysł 6): segmenty jak miernik hałasu; przy awansie krótko jaśnieje.
class XpBar extends Control:
	var value := 0.0
	var flash := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var gap := 2.0
		var w := (size.x - gap * float(XP_SEGS - 1)) / float(XP_SEGS)
		var fill: Color = UiTheme.CALM.lerp(UiTheme.WARM, clampf(flash, 0.0, 1.0))
		for i in XP_SEGS:
			var r := Rect2(float(i) * (w + gap), 0.0, w, size.y)
			var q := clampf(value * float(XP_SEGS) - float(i), 0.0, 1.0)
			draw_rect(r, Color("1a1b18"))
			if q > 0.0:
				draw_rect(r, Color(fill, 0.3 + 0.7 * q))
			draw_rect(r, fill.lightened(0.25) if q >= 1.0 else UiTheme.LINE, false, 1.0)

## Naszywka awansu (§15 pomysł 6): tarcza z numerem poziomu, przeszyta nicią koloru lampy.
class Patch extends Control:
	var lv := 1
	func _init(level: int, s: float) -> void:
		lv = level
		custom_minimum_size = Vector2(s, s * 1.12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var outer := PackedVector2Array([Vector2(1, 1), Vector2(w - 1, 1), Vector2(w - 1, h * 0.6), Vector2(w * 0.5, h - 1), Vector2(1, h * 0.6)])
		draw_colored_polygon(outer, Color("2c3122"))
		var inner := [Vector2(4, 4), Vector2(w - 4, 4), Vector2(w - 4, h * 0.58), Vector2(w * 0.5, h - 4.5), Vector2(4, h * 0.58)]
		for i in inner.size():
			draw_dashed_line(inner[i], inner[(i + 1) % inner.size()], UiTheme.ACCENT, 1.0, 2.5)
		var font := UiTheme.heading_font()
		var fs := int(h * 0.48)
		var s := str(lv)
		var ss := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, Vector2((w - ss.x) * 0.5, h * 0.5 + font.get_ascent(fs) * 0.38), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.ACCENT.lightened(0.35))

## Tło sceny: ciemne pasy gradientu przy krawędziach (pod kolumnami, nieśmiertelnikami i tytułem); środek przezroczysty.
class Scrim extends Control:
	var col_w := 0.0
	var bottom_h := 0.0
	var top_h := 0.0
	var a := 1.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _band(r: Rect2, c0: Color, c1: Color, horizontal: bool) -> void:
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var cols := PackedColorArray([c0, c1, c1, c0]) if horizontal else PackedColorArray([c0, c0, c1, c1])
		draw_polygon(pts, cols)
	func _draw() -> void:
		var dark := Color(0.012, 0.016, 0.012, 0.8 * a)
		var clear := Color(dark, 0.0)
		var w := col_w * 1.3
		_band(Rect2(0, 0, w, size.y), dark, clear, true)
		_band(Rect2(size.x - w, 0, w, size.y), clear, dark, true)
		_band(Rect2(0, size.y - bottom_h * 1.35, size.x, bottom_h * 1.35), clear, dark, false)
		_band(Rect2(0, 0, size.x, top_h * 1.2), Color(dark, 0.7 * a), clear, false)

## Dioda odbioru przy wpisie radiowym (zielona: baza odebrała, czerwona: cisza w eterze).
class Lamp extends Control:
	var col: Color = UiTheme.CALM
	func _init(c: Color, s: float) -> void:
		col = c
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(col, 0.25))
		draw_circle(c, r * 0.6, col.lightened(0.2))

## Portret na nieśmiertelniku: głowa i ramiona z renderu stroju (górny kwadrat obrazka), w ramce koloru slotu.
class Portrait extends Control:
	var tex: Texture2D
	var slot_col: Color = UiTheme.MUTED
	var gone := false
	func _init(t: Texture2D, c: Color, s: float, is_gone: bool) -> void:
		tex = t
		slot_col = c
		gone = is_gone
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("15161a"))
		if tex != null:
			var w := tex.get_width()
			var src := Rect2(w * 0.14, 0.0, w * 0.68, w * 0.68)
			var mod := Color(0.5, 0.5, 0.5, 0.8) if gone else Color(0.9, 0.88, 0.84)
			draw_texture_rect_region(tex, Rect2(Vector2(2, 1), size - Vector2(3, 2)), src, mod)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE2, false, 1.0)
		draw_rect(Rect2(0, 0, 2, size.y), slot_col if not gone else UiTheme.MUTED)

## Stalowa blaszka nieśmiertelnika: zaokrąglona z lewej, z otworem na łańcuszek i jaśniejszym połyskiem u góry.
class DogTag extends PanelContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = STEEL
		sb.set_corner_radius_all(3)
		sb.corner_radius_top_left = 9
		sb.corner_radius_bottom_left = 9
		sb.border_color = STEEL.lightened(0.25)
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.content_margin_left = 17
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 2
		sb.shadow_offset = Vector2(0, 1)
		add_theme_stylebox_override("panel", sb)
	func _draw() -> void:
		draw_rect(Rect2(8, 1, size.x - 10, size.y * 0.35), Color(1, 1, 1, 0.08))
		var hc := Vector2(8.0, size.y * 0.5)
		draw_circle(hc, 3.2, Color("101112"))
		draw_arc(hc, 3.4, PI * 0.1, PI * 0.9, 8, Color(1, 1, 1, 0.35), 1.0, true)

## Przebieg misji jako taśma: oś czasu i znaki zdarzeń (RESULTS_PLAN.md P2, wzór: dziennik Hunt: Showdown).
class RunStrip extends Control:
	var length := 1.0
	var marks: Array = []                 ## [[t, kind, slot]]
	var reveal := 1.0                     ## 0..1 — taśma „przewija się” razem z sekwencją
	var font: Font
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var y := size.y * 0.5
		var w := size.x * clampf(reveal, 0.0, 1.0)
		draw_line(Vector2(0, y), Vector2(size.x, y), UiTheme.HAIR, 1.0)
		draw_line(Vector2(0, y), Vector2(w, y), UiTheme.LINE.lightened(0.25), 1.0)
		for i in 5:
			var tx := size.x * float(i) / 4.0
			draw_line(Vector2(tx, y - 2.0), Vector2(tx, y + 2.0), UiTheme.LINE.lightened(0.25), 1.0)
		if font == null:
			return
		for mk in marks:
			var fx: float = size.x * clampf(float(mk[0]) / maxf(1.0, length), 0.0, 1.0)
			if fx > w + 0.5:
				continue
			var spec: Array = MARKS.get(String(mk[1]), ["·", UiTheme.TEXT])
			var glyph: String = spec[0]
			var gs := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(font, Vector2(fx - gs.x * 0.5, y + 5.0), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, spec[1])

var model: Dictionary = {}
var t := 0.0                          ## czas sekwencji (zatrzymuje się, gdy etap czeka na dane)
var _age := 0.0                       ## czas od otwarcia (płynie zawsze — blokada wejścia)
var hold_at := -1.0                   ## dev (--shotresultt=S): sekwencja staje w chwili S — zrzut z połowy animacji
var _waited := 0.0
var _skipped := false
var _mission: Node = null
var _ctx_sig := 0
var _ctx_t := 0.0
var _anims: Array = []                ## [{node, t, kind}] — „fade” (alfa), „stamp” (alfa + skala), „title”
var _cues: Array = []                 ## [{t, snd, pitch}] — dźwięki etapów, każdy raz
var _cue_i := 0
var _cued := {}                       ## sekcje raportu, które mają już swój sygnał (jeden na sekcję)
var _det_on := false                  ## czy widać teraz warstwę Szczegóły

var _panel: Control                   ## płótno raportu (DESIGN), skalowane do ekranu
var _scrim: Scrim
var _top: VBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _tags: HBoxContainer
var _foot: HBoxContainer
var _sub: Label
var _scrap_val: Odometer
var _xp_val: Odometer
var _xp_bar: XpBar
var _lv_lo: Label
var _lv_hi: Label
var _strip: RunStrip
var _sum_box: Control                 ## skrót jako scena: kolumny celów i łupu, nieśmiertelniki
var _det_box: Control                 ## panel Szczegółów (rozbicie | wyróżnienia, przebieg)
var _det_btn: Button
var _foot_l: Label
var _prompt_box: HBoxContainer
var _skip_hint: Label
var _ready_note: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_inst = weakref(self)

# ---------------------------------------------------------------- otwieranie i stan

## Otwiera raport dla bieżącej misji (faza SUCCESS albo FAILED). Sekwencja startuje od zera.
func open(m: Node) -> void:
	_mission = m
	t = 0.0
	_age = 0.0
	_waited = 0.0
	_skipped = Settings.fx_mult() <= 0.0
	_cue_i = 0
	var ctx := collect(m)
	_ctx_sig = hash(_sig_of(ctx))
	model = build_model(ctx)
	_rebuild()
	if _skipped:
		t = float(model["end_t"])
		_cue_i = _cues.size()
	visible = true
	Audio.music_result(int(m.phase) == Mission.Phase.SUCCESS)      # kadencja wyniku; muzyka rozgrywki cichnie (MUSIC_PLAN.md E5)
	_animate()

func close() -> void:
	visible = false
	_mission = null

## Czy sekwencja doszła do końca (albo została pominięta).
func is_done() -> bool:
	return not model.is_empty() and t >= float(model["end_t"]) - 0.0001

## Czy widać warstwę Szczegóły (dopiero po sekwencji — w trakcie zawsze skrót).
func details_shown() -> bool:
	return _det_on

## 1 = HUD rozgrywki widoczny, 0 = schowany pod raportem.
func hud_fade() -> float:
	if not visible:
		return 1.0
	return 0.0 if _skipped else 1.0 - clampf(_age / HUD_FADE, 0.0, 1.0)

## Ściemnienie świata pod raportem: pod skrótem lekkie (środek zostaje dla drużyny), pod Szczegółami pełne.
func dim_alpha() -> float:
	if not visible:
		return 0.0
	var full := DIM if _det_on else DIM_SCENE
	return full if _skipped else full * clampf(_age / 0.4, 0.0, 1.0)

## Krok sekwencji. Etap złomu / XP czeka do DATA_WAIT s na dane od serwera; potem idzie dalej, a wartość dolicza się bez animacji.
func advance(delta: float) -> void:
	if model.is_empty():
		return
	_age += delta
	var end: float = float(model["end_t"])
	if hold_at >= 0.0:
		end = minf(end, hold_at)
	if t < end:
		var wait_scrap: bool = bool(model["scrap"]["show"]) and not bool(model["scrap"]["ready"]) and t >= T_SCRAP
		var wait_xp: bool = bool(model["xp"]["show"]) and not bool(model["xp"]["ready"]) and t >= T_XP
		if (wait_scrap or wait_xp) and _waited < DATA_WAIT:
			_waited += delta
		else:
			t = minf(end, t + delta)
	_fire_cues()

## Pierwsze naciśnięcie w trakcie sekwencji: stan końcowy od razu (jeden dźwięk zamiast wszystkich zaległych).
func skip() -> void:
	if model.is_empty() or is_done():
		return
	t = float(model["end_t"])
	_age = maxf(_age, HUD_FADE)
	_skipped = true
	_cue_i = _cues.size()
	_play("skip")
	_animate()

## Akcja raportu („continue”, „next” albo „details”). Zwraca, co się stało: "locked", "skipped", "details" albo "act".
func press(kind: String) -> String:
	if not visible or model.is_empty():
		return "locked"
	if _age < INPUT_LOCK:
		return "locked"
	if not is_done():
		skip()
		return "skipped"
	if kind == "details":
		details_pref = not details_pref
		_play("toggle")
		_animate()
		return "details"
	var main := get_tree().current_scene
	if main != null and main.has_method("result_action"):
		main.result_action(kind)
	return "act"

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event.is_action_pressed("result_continue") or event.is_action_pressed("restart"):
		press("continue")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("result_next"):
		press("next")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("result_details"):
		press("details")
		get_viewport().set_input_as_handled()

## Co klatkę (HUD): dane, które dochodzą później (XP, złom, gotowość, statystyki) przebudowują raport bez zmiany czasu sekwencji.
func refresh(delta: float) -> void:
	if _mission == null or not is_instance_valid(_mission):
		return
	_ctx_t -= delta
	if _ctx_t <= 0.0:
		_ctx_t = 0.2
		var ctx := collect(_mission)
		var sig := hash(_sig_of(ctx))
		if sig != _ctx_sig:
			_ctx_sig = sig
			model = build_model(ctx)
			_rebuild()
			_cue_i = 0
			while _cue_i < _cues.size() and float(_cues[_cue_i]["t"]) <= t:
				_cue_i += 1                        # dźwięki, które już zagrały, nie grają drugi raz
	advance(delta)
	_animate()

func _sig_of(ctx: Dictionary) -> String:
	return str([ctx["players"], ctx["xp"]["ready"], ctx["xp"]["end"], ctx["scrap_info"], ctx["levels"], ctx["record"], ctx["gains"], Actions.pad_mode,
		TranslationServer.get_locale()])

# ---------------------------------------------------------------- dane

## Zbiera dane raportu z misji i autoloadów (każdy peer ma je lokalnie: replikowane albo z własnego profilu).
func collect(m: Node) -> Dictionary:
	var lvl := get_tree().get_first_node_in_group("level")
	var map_id := String(lvl.map_id) if lvl != null else ""
	var success: bool = int(m.phase) == Mission.Phase.SUCCESS
	var xp_ready: bool = success and Profile.result_ms > 0 and Profile.result_ms >= _open_ms() - 5000
	var players: Array = []
	var ids: Array = (m.player_stats as Dictionary).keys()
	ids.sort()
	var peers: Array = Array(multiplayer.get_peers()) if multiplayer.has_multiplayer_peer() else []
	var pnodes: Node = get_tree().current_scene.get_node_or_null("Players") if get_tree().current_scene != null else null
	for id in ids:
		var st: Dictionary = m.player_stats[id]
		var nm := String(st.get("name", "P1"))
		var pn: Node = pnodes.get_node_or_null(str(id)) if pnodes != null else null
		var look_c: int = int(pn.get("look")) if pn != null and pn.get("look") != null else -1
		players.append({"id": int(id), "call": String(st.get("call", nm)), "slot": clampi(int(nm.substr(1)) - 1, 0, 3) if nm.begins_with("P") else 0,
			"kills": int(st.get("kills", 0)), "downs": int(st.get("downs", 0)), "revives": int(st.get("revives", 0)),
			"me": int(id) == NoiseMgr.local_id(), "host": int(id) == 1, "ready": bool((m.result_ready as Dictionary).get(int(id), false)), "look": look_c,
			"gone": int(id) != 1 and int(id) != NoiseMgr.local_id() and not peers.is_empty() and not peers.has(int(id))})
	var main := get_tree().current_scene
	var demo_last := false
	if Settings.DEMO and lvl != null:
		demo_last = (int(m.phase) == Mission.Phase.FAILED or m.shift_complete()) if NightShift.active else map_id == String(lvl.CAMPAIGN[lvl.CAMPAIGN.size() - 1])
	return {
		"success": success, "kind": String(m.kind), "map_id": map_id, "map_title": String(lvl.title) if lvl != null else "",
		"difficulty": String(Difficulty.level_name()), "elapsed": float(m.elapsed), "downs": int(m.downs), "attempts": int(m.attempts),
		"goal_total": int(m.goal_total), "nests_total": int(m.nests_total), "stash_found": int(m.stashes_found), "stash_total": int(m.stash_total),
		"peak": float(m.peak_noise), "silent_counts": bool(m.silent_counts()), "silent_ok": bool(m.silent_ok()), "silent_cap": int(m.SILENT_CAP),
		"stealth_cap": int(m.STEALTH_CAP), "side_done": bool(m.side_done()),
		"night": {"active": NightShift.active, "stage": NightShift.stage, "missions": NightShift.MISSIONS, "cleared": int(m.shift_cleared),
			"time": float(m.shift_time), "downs": int(m.shift_downs), "record": bool(m.shift_record), "complete": bool(m.shift_complete()),
			"best_c": int(Settings.shift_best_cleared), "best_t": float(Settings.shift_best_time)},
		"scrap_enabled": Scrap.enabled() and not NightShift.active, "scrap_info": (m.result_info as Dictionary).duplicate(true),
		"xp": {"ready": xp_ready, "mission": Profile.last_mission_xp, "run": Profile.last_run_xp, "rows": Profile.last_mission_rows.duplicate(true),
			"end": Profile.xp},
		"record": Profile.last_record.duplicate() if success else {}, "gains": Profile.mission_gains() if success else {},
		"players": players, "awards": Mission.awards(m.player_stats, bool(m.stalker_woke)), "levels": (m.result_levels as Dictionary).duplicate(),
		"timeline": (m.result_info as Dictionary).get("timeline", []),
		"companion": main == null or main.get("companion_on") != false, "server": not multiplayer.has_multiplayer_peer() or multiplayer.is_server(),
		"local_ready": bool((m.result_ready as Dictionary).get(NoiseMgr.local_id(), false)), "demo_last": demo_last,
		"stalker_woke": bool(m.stalker_woke),
	}

func _open_ms() -> int:
	return Time.get_ticks_msec() - int(_age * 1000.0)

static func _tr(s: String) -> String:
	return TranslationServer.translate(s)

static func mmss(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d" % [s / 60, s % 60]

## Czysty model raportu z `ctx` (collect). Teksty już przetłumaczone; czasy etapów wyliczone (kafelki, awanse, znaleziska, koniec).
## Model trzyma dane obu warstw: skrót (kafelki, sumy, chipy XP, tytuły wyróżnień) i Szczegóły (wiersze rozbicia, uzasadnienia, stopka).
static func build_model(ctx: Dictionary) -> Dictionary:
	var night: Dictionary = ctx["night"]
	var success: bool = ctx["success"]
	var kind := String(ctx["kind"])
	var md := {"success": success, "night": bool(night["active"])}
	# --- tytuł i podpis (D1: podpis tylko tam, gdzie mówi coś nowego — boss i Nocny Dyżur)
	var title := "EXTRACTION COMPLETE"
	var sub := ""
	var col: Color = UiTheme.OK
	if bool(night["active"]):
		if not success:
			title = "SERIES BROKEN"
			sub = "The night took the squad."
			col = UiTheme.DANGER
		elif bool(night["complete"]):
			title = "SHIFT COMPLETE"
			sub = "The whole night, survived."
		else:
			title = _tr("MISSION %d CLEARED") % int(night["stage"])
			sub = "Night Shift — the next one is harder."
	elif kind == "boss":
		title = "THE LEECH IS DEAD"
		sub = "The hall is quiet again — only the water drips."
	md["title"] = _tr(title)
	md["sub"] = _tr(sub) if sub != "" else ""
	# wpis radiowy (§15 pomysł 5): kanał z mapy (stały dla mapy); przerwana seria Nocnego Dyżuru — cisza w eterze („dead air”)
	var ch: int = absi(hash(String(ctx["map_id"]))) % 9 + 1
	var heard: bool = success or not bool(night["active"])
	md["lurk"] = success and not bool(night["active"]) and bool(ctx.get("stalker_woke", false))
	md["radio"] = {"text": (_tr("CHANNEL %d · BASE RECEIVED") if heard else _tr("CHANNEL %d · DEAD AIR")) % ch, "ok": heard}
	md["color"] = col
	var head := []
	if String(ctx["map_title"]) != "":
		head.append(_tr(String(ctx["map_title"])))
	head.append(_tr(String(ctx["difficulty"])))
	md["header_l"] = "  ·  ".join(head).to_upper()
	if bool(night["active"]):
		md["header_r"] = (_tr("SERIES %s") % mmss(float(night["time"]))).to_upper()
	else:
		md["header_r"] = ((_tr("ATTEMPT #%d") % int(ctx["attempts"]) + "  ·  ").to_upper() if int(ctx["attempts"]) > 1 else "") + mmss(float(ctx["elapsed"]))
	# --- kafelki celów (albo drabinka Nocnego Dyżuru); etykieta = nazwa celu, wartość z progiem, nagroda osobno (XP, złom)
	var tiles: Array = []
	if bool(night["active"]):
		for i in int(night["missions"]):
			var n := i + 1
			var done: bool = n <= int(night["cleared"])
			var cur: bool = n == int(night["stage"])
			tiles.append({"id": "stage", "label": _tr("MISSION %d") % n, "what": _tr("cleared") if done else (_tr("fell here") if cur and not success else "—"),
				"value": "✓" if done else ("✕" if cur and not success else "·"), "ok": done, "xp": 0, "scrap": 0, "stamp": done or (cur and not success)})
	elif success:
		var main_what: String = {"tags": "Dog tags", "generators": "Generators started", "boss": "The Leech", "nests": "Nests destroyed"}.get(kind, "Nests destroyed")
		var main_lab: String = {"tags": "DOG TAGS", "generators": "GENERATORS", "boss": "THE LEECH", "nests": "NESTS"}.get(kind, "NESTS")
		var main_val := "%d / %d" % [int(ctx["goal_total"]), int(ctx["goal_total"])]
		if kind == "boss":
			main_val = _tr("slain")
		elif kind == "nests":
			main_val = "%d / %d" % [int(ctx["nests_total"]), int(ctx["nests_total"])]
		tiles.append({"id": "main", "label": _tr(main_lab), "what": _tr(main_what), "value": main_val, "ok": true,
			"xp": Profile.XP_MISSION + (Profile.XP_BOSS if kind == "boss" else 0), "scrap": Scrap.BONUS_CLEAR, "stamp": true})
		if kind == "nests":
			tiles.append({"id": "vein", "label": _tr("THE VEIN"), "what": _tr("Brood mother"), "value": _tr("slain"), "ok": true, "xp": 0, "scrap": 0,
				"stamp": true})
		if (kind == "tags" or kind == "nests") and int(ctx["stash_total"]) > 0:       # skrytki: 1.1, od 1.7.551 też 1.3
			tiles.append({"id": "side", "label": _tr("STASHES"), "what": _tr("Hidden stashes"),
				"value": "%d / %d" % [int(ctx["stash_found"]), int(ctx["stash_total"])], "ok": bool(ctx["side_done"]), "xp": Profile.XP_SIDE,
				"scrap": Scrap.BONUS_SIDE, "stamp": true})
		elif kind == "generators":
			tiles.append({"id": "side", "label": _tr("STEALTH"), "what": _tr("Attention below %d") % int(ctx["stealth_cap"]),
				"value": "%d / %d" % [int(ctx["peak"]), int(ctx["stealth_cap"])], "ok": bool(ctx["side_done"]), "xp": Profile.XP_SIDE, "scrap": Scrap.BONUS_SIDE,
				"stamp": true})
		tiles.append({"id": "no_downs", "label": _tr("NO DOWNS"), "what": _tr("Squad downs"), "value": str(int(ctx["downs"])), "ok": int(ctx["downs"]) == 0,
			"xp": Profile.XP_NO_DOWNS, "scrap": Scrap.BONUS_NO_DOWNS, "stamp": true})
		if bool(ctx["silent_counts"]):
			tiles.append({"id": "silent", "label": _tr("SILENT RUN"), "what": _tr("Attention peak (limit %d)") % int(ctx["silent_cap"]),
				"value": "%d / %d" % [int(ctx["peak"]), int(ctx["silent_cap"])], "ok": bool(ctx["silent_ok"]), "xp": 0, "scrap": Scrap.BONUS_SILENT, "stamp": true})
	var scrap_on: bool = bool(ctx["scrap_enabled"]) and success
	for i in tiles.size():
		var tl: Dictionary = tiles[i]
		tl["t"] = T_TILES + TILE_GAP * float(i)
		tl["reward_xp"] = int(tl["xp"])
		tl["reward_scrap"] = int(tl["scrap"]) if scrap_on else 0
	md["tiles"] = tiles
	md["ladder"] = bool(night["active"])
	# --- złom drużyny: łup + premie (rozbicie od serwera w mission.result_info); skrót pokazuje sumę i „łup · premie”
	var info: Dictionary = ctx["scrap_info"]
	var scrap := {"show": scrap_on, "ready": info.has("gain"), "total": int(info.get("gain", 0)), "rows": [], "loot": 0, "bonus": 0}
	if scrap_on and info.has("gain"):
		var bonus := 0
		var rows: Array = []
		for b in Array(info.get("bonus", [])):
			bonus += int(b[1])
			rows.append([_tr({"clear": "bonus: mission", "side": "bonus: side objective", "no_downs": "bonus: no downs", "silent": "bonus: silent run"}.get(String(b[0]), String(b[0]))), int(b[1])])
		rows.push_front([_tr("mission loot"), maxi(0, int(info["gain"]) - bonus)])
		scrap["rows"] = rows
		scrap["loot"] = maxi(0, int(info["gain"]) - bonus)
		scrap["bonus"] = bonus
	md["scrap"] = scrap
	# --- XP gracza: licznik od (koniec − zdobyte) do końca, przelania poziomów z czasem i odblokowaniami;
	#     skrót: chipy tylko za to, czego nie ma na kafelkach (pierwsze przejście, walka, Nocny Dyżur)
	var xd: Dictionary = ctx["xp"]
	var earned: int = int(xd["mission"]) + int(xd["run"])
	var xp := {"show": success, "ready": bool(xd["ready"]), "earned": earned, "end": int(xd["end"]), "start": maxi(0, int(xd["end"]) - earned),
		"rows": [], "levels": [], "chips": []}
	if success and bool(xd["ready"]):
		var rows: Array = []
		var chips: Array = []
		for r in Array(xd["rows"]):
			rows.append([_tr(String(r[0])).to_lower(), int(r[1])])
			if String(r[0]) == "First clear" and not bool(night["active"]):
				chips.append({"text": "%s +%d" % [_tr("FIRST CLEAR"), int(r[1])], "stamp": true})
		if bool(night["active"]) and not rows.is_empty():
			rows = [[_tr("night shift (half)"), int(xd["mission"])]]
			chips.append({"text": _tr("night shift +%d") % int(xd["mission"]), "stamp": false})
		if int(xd["run"]) > 0:
			rows.append([_tr("kills and revives"), int(xd["run"])])
			chips.append({"text": _tr("combat +%d") % int(xd["run"]), "stamp": false})
		xp["rows"] = rows
		xp["chips"] = chips
		var lv0 := Profile.level_of(int(xp["start"]))
		var lv1 := Profile.level_of(int(xp["end"]))
		for lv in range(lv0 + 1, lv1 + 1):
			var q := clampf(float(Profile.xp_for_level(lv) - int(xp["start"])) / float(maxi(1, earned)), 0.0, 1.0)
			var tl := T_XP + (1.0 - pow(1.0 - q, 1.0 / 3.0)) * XP_DUR               # odwrotność ease-out cubic licznika
			xp["levels"].append({"lv": lv, "t": tl, "unlocks": unlocks_at(lv)})
	md["xp"] = xp
	# --- drużyna: wiersze z wyróżnieniami-pieczątkami i stanem gotowości (skrót: sam tytuł; Szczegóły: tytuł + uzasadnienie)
	var by_id := {}
	for a in Array(ctx["awards"]):
		var pid: int = int(a[3]) if (a as Array).size() > 3 else -1
		var aid := String(a[0])
		var note := _tr(String(Mission.AWARD_NOTES[aid]))
		var why: String = note if aid == "ghost" else "%s: %d" % [note, int(a[2])]
		if not by_id.has(pid):
			by_id[pid] = []
		(by_id[pid] as Array).append({"title": _tr(String(Mission.AWARD_TITLES[aid])), "why": why, "kind": "award"})
	var squad: Array = []
	var players: Array = ctx["players"]
	var solo := players.size() <= 1
	var levels: Dictionary = ctx["levels"]
	var k := 0
	var others := 0
	var ready_n := 0
	for i in players.size():
		var p: Dictionary = players[i]
		var aws: Array = (by_id.get(int(p["id"]), []) as Array).duplicate()
		if not bool(p["me"]) and levels.has(int(p["id"])):
			var lvp: Array = levels[int(p["id"])]
			if int(lvp[1]) > int(lvp[0]):
				aws.append({"title": _tr("LEVEL UP") + " → %d" % int(lvp[1]), "why": "%d → %d" % [int(lvp[0]), int(lvp[1])], "kind": "level"})
		for a in aws:
			(a as Dictionary)["t"] = T_AWARDS + AWARD_GAP * float(k)
			k += 1
		# §15.1 p. 6: napis tylko wtedy, gdy coś mówi — GOTOWY albo rozłączony (brak napisu = jeszcze czyta; host widzi „N / M gotowych”)
		var status := ""
		var scol: Color = UiTheme.MUTED
		if solo or bool(p["host"]):
			status = ""
		elif bool(p["gone"]):
			status = _tr("disconnected")
			scol = UiTheme.DANGER
		elif bool(p["ready"]):
			status = _tr("READY")
			scol = UiTheme.OK
		if not bool(p["host"]) and not bool(p["gone"]):
			others += 1
			if bool(p["ready"]):
				ready_n += 1
		var nm := String(p["call"])
		squad.append({"id": int(p["id"]), "name": nm, "slot": int(p["slot"]), "me": bool(p["me"]), "portrait": portrait_of(int(p.get("look", -1)), int(p["slot"])),
			"kills": int(p["kills"]), "downs": int(p["downs"]), "revives": int(p["revives"]), "status": status, "status_col": scol,
			"gone": bool(p["gone"]), "awards": aws, "t": T_SQUAD + SQUAD_GAP * float(i)})
	md["squad"] = squad
	# --- znaleziska, rekordy, wprawa, kodeks (część i bateria z ikoną modelu — §15 pomysł 3; pierwsze przejście jest przy XP)
	var finds: Array = []
	if success and not bool(night["active"]):
		var rec: Dictionary = ctx["record"]
		if bool(rec.get("new", false)) and not bool(rec.get("first", false)) and float(rec.get("prev", 0.0)) > 0.0:
			finds.append({"text": _tr("NEW RECORD %s") % mmss(float(rec["time"])), "why": _tr("(was %s)") % mmss(float(rec["prev"])), "stamp": true,
				"color": UiTheme.DANGER, "snd": "record"})
		var fi: Dictionary = info.get("finds", {})
		for pid in Array(fi.get("parts", [])):
			var pd := Parts.get_part(String(pid))
			var pname := _tr(String(pd.get("name", pid)))
			var ico := PART_ICON % String(pid)
			if ResourceLoader.exists(ico):
				finds.append({"text": pname, "icon": ico, "stamp": false, "color": UiTheme.ACCENT})
			else:
				finds.append({"text": _tr("NEW PART: %s") % pname, "stamp": false, "color": UiTheme.TEXT})
		if int(fi.get("samples", 0)) > 0:
			finds.append({"text": _tr("+%d lab sample") % int(fi["samples"]), "stamp": false, "color": UiTheme.TEXT})
		if int(fi.get("geodes", 0)) > 0:                       # geoda z żyły (DIG_LOOT_PLAN.md K4): otwierana w pracowni
			finds.append({"text": _tr("+%d geode for the lab") % int(fi["geodes"]), "stamp": false, "color": UiTheme.TEXT})
		if int(fi.get("batteries", 0)) > 0:
			finds.append({"text": "× %d" % int(fi["batteries"]), "icon": HUD_ICON % "battery", "stamp": false, "color": UiTheme.TEXT})
		if bool(fi.get("trophy", false)):
			finds.append({"text": _tr("TROPHY WEAPON UNLOCKED"), "stamp": false, "color": UiTheme.ACCENT})
		var gains: Dictionary = ctx["gains"]
		for g in Array(gains.get("mastery", [])):
			var wid := Weapons.index_of(String(g[0]))
			var wn: String = String(Weapons.base_def(wid).name) if Weapons.is_valid(wid) else String(g[0]).to_upper()
			var wico := HUD_ICON % String(g[0])
			if ResourceLoader.exists(wico):
				finds.append({"text": _tr("mastery %d → %d") % [int(g[1]), int(g[2])], "icon": wico, "stamp": false, "color": UiTheme.TEXT})
			else:
				finds.append({"text": _tr("%s: mastery %d → %d") % [wn, int(g[1]), int(g[2])], "stamp": false, "color": UiTheme.TEXT})
		for b in Array(gains.get("beasts", [])):
			finds.append({"text": _tr("NEW CODEX ENTRY: %s") % _tr(Codex.beast_name(String(b))), "stamp": false, "color": UiTheme.TEXT})
	elif bool(night["active"]) and bool(night["record"]):
		finds.append({"text": _tr("NEW RECORD"), "stamp": true, "color": UiTheme.DANGER, "snd": "record"})
	for i in finds.size():
		(finds[i] as Dictionary)["t"] = T_FINDS + FIND_GAP * float(i)
	md["finds"] = finds
	# --- przebieg misji (Szczegóły, D2)
	var marks: Array = ctx["timeline"]
	md["timeline"] = {"show": success and not bool(night["active"]) and not marks.is_empty(), "len": float(ctx["elapsed"]), "marks": marks}
	# --- stopka Szczegółów (próba, towarzysz AI, gracze, rekord mapy) i akcje
	var foot: Array = []
	if bool(night["active"]):
		foot.append(_tr("Missions cleared %d / %d") % [int(night["cleared"]), int(night["missions"])])
		foot.append(_tr("Squad downs %d") % int(night["downs"]))
		if int(night["best_c"]) > 0:
			foot.append(_tr("Best %d / %d") % [int(night["best_c"]), int(night["missions"])] + ((" · " + mmss(float(night["best_t"]))) if float(night["best_t"]) > 0.0 else ""))
	else:
		foot.append(_tr("ATTEMPT #%d") % int(ctx["attempts"]))
		foot.append(_tr("AI companion: %s") % _tr("on" if bool(ctx["companion"]) else "off"))
		if not solo:
			foot.append(_tr("%d players") % players.size())
		var rec2: Dictionary = ctx["record"]
		if float(rec2.get("best", 0.0)) > 0.0 and not bool(rec2.get("new", false)):
			foot.append(_tr("Map record %s") % mmss(float(rec2["best"])))
	md["foot_l"] = "  ·  ".join(foot)
	var prompts: Array = []
	var note := ""
	if bool(ctx["server"]):
		if bool(night["active"]):
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("New shift" if (not success or bool(night["complete"])) else "Next mission")})
		elif success:
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Safe room")})
			prompts.append({"kind": "next", "action": "result_next", "label": _tr("Next mission")})
		else:
			prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Continue")})
		if others > 0:
			note = _tr("%d / %d ready") % [ready_n, others]
	elif bool(ctx["local_ready"]):
		note = _tr("Waiting for the host to continue…")
	else:
		prompts.append({"kind": "continue", "action": "result_continue", "label": _tr("Ready")})
	md["prompts"] = prompts
	md["ready_note"] = note
	md["demo_footer"] = bool(ctx["demo_last"])
	# --- koniec sekwencji: ostatnia pieczątka (+ czas jej „przybicia”) albo T_DONE
	var end := T_DONE
	for a_row in squad:
		for a in Array((a_row as Dictionary)["awards"]):
			end = maxf(end, float((a as Dictionary)["t"]) + STAMP_DUR)
	for f in finds:
		end = maxf(end, float((f as Dictionary)["t"]) + STAMP_DUR)
	for lv in Array(xp["levels"]):
		end = maxf(end, float((lv as Dictionary)["t"]) + 0.5)
	md["end_t"] = end
	return md

## Portret gracza na nieśmiertelniku: render jego stroju; nieznany wygląd → domyślny wg numeru gracza (jak player._look_code).
static func portrait_of(look_c: int, slot: int) -> String:
	var c := look_c if Look.is_valid(look_c) else Look.code(0 if slot % 2 == 0 else 1, 0)
	var path := LOOK_PORTRAIT % [Look.gender_id(c), Look.outfit_id(c)]
	return path if ResourceLoader.exists(path) else ""

## Co odblokowuje poziom `lv`: slot perka, perki, stroje i barwy (te same tabele co menu PERKS i ekran wyglądu).
static func unlocks_at(lv: int) -> Array:
	var out: Array = []
	if Profile.SLOT_LEVELS.has(lv):
		out.append(_tr("perk slot %d") % (Profile.SLOT_LEVELS.find(lv) + 1))
	for id in Profile.Perks.unlocked_at(lv):
		out.append(_tr("perk %s") % _tr(Profile.Perks.display_name(String(id))))
	for o in Look.UNLOCK_LEVEL:
		if int(Look.UNLOCK_LEVEL[o]) == lv and lv > 1:
			out.append(_tr("outfit %s") % _tr(String(Look.OUTFIT_NAMES[o])))
	for p in Look.PALETTES:
		if int(p["level"]) == lv and lv > 1:
			out.append(_tr("colours %s") % _tr(String(p["name"])))
	return out

# ---------------------------------------------------------------- budowa widoku

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_anims.clear()
	_cues.clear()
	_cued.clear()
	_strip = null
	_sub = null
	_scrap_val = null
	_xp_val = null
	# tło sceny: ciemne pasy przy krawędziach (kolumny, nieśmiertelniki), środek zostaje dla drużyny w 3D
	_scrim = Scrim.new()
	add_child(_scrim)
	# płótno projektu (DESIGN): całość skalowana jednym mnożnikiem, żeby zmieścić się przy każdej skali UI
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.size = DESIGN
	add_child(_panel)
	_anim(_panel, 0.1, "fade")
	# A + B — u góry: nagłówek (mapa · trudność … czas), wpis radiowy, tytuł, podpis
	_top = VBoxContainer.new()
	_top.add_theme_constant_override("separation", 6)
	_panel.add_child(_top)
	var head := HBoxContainer.new()
	var hl := UiTheme.mono(UiTheme.label(String(model["header_l"]), _f(7), UiTheme.MUTED))
	hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hl)
	head.add_child(_spacer())
	var tape := PanelContainer.new()
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("0b0c0a")
	tsb.border_color = UiTheme.LINE2
	tsb.set_border_width_all(1)
	tsb.content_margin_left = 5
	tsb.content_margin_right = 5
	tape.add_theme_stylebox_override("panel", tsb)
	tape.add_child(UiTheme.mono(UiTheme.label(String(model["header_r"]), _f(8), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)))
	head.add_child(tape)
	_top.add_child(head)
	# wpis radiowy nad tytułem: dioda odbioru i kanał; szum odbioru gra pod wejściem kadencji wyniku
	var rd: Dictionary = model["radio"]
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	rrow.add_theme_constant_override("separation", 7)
	var rcol: Color = UiTheme.CALM if bool(rd["ok"]) else UiTheme.DANGER
	rrow.add_child(Lamp.new(rcol, float(_f(5))))
	var rl := UiTheme.mono(UiTheme.label(String(rd["text"]), _f(7), rcol))
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rrow.add_child(rl)
	_top.add_child(rrow)
	_anim(rrow, T_RADIO, "fade")
	_cue(T_RADIO, "radio", 1.0)
	var title := UiTheme.heading(String(model["title"]), _f(TITLE_FS), Color(model["color"]).lightened(0.12), HORIZONTAL_ALIGNMENT_CENTER)
	_top.add_child(title)
	_anim(title, T_TITLE, "title")                 # bez dźwięku: tytuł niesie wejście kadencji wyniku (Audio.music_result)
	if String(model["sub"]) != "":
		_sub = UiTheme.whisper(UiTheme.label(String(model["sub"]), _f(10), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER))
		_top.add_child(_sub)
	if bool(model["demo_footer"]):
		_top.add_child(UiTheme.heading("THANKS FOR PLAYING THE DEMO", _f(8), UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		_top.add_child(UiTheme.label("Wishlist DEAD AIR '87 on Steam — more zones, weapons and monsters are coming.", _f(8), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		if Settings.STORE_URL != "":
			_top.add_child(UiTheme.label(tr("[%s]  Open the Steam page") % Actions.key("open_store"), _f(8), UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	# skrót jako scena: C — cele w lewej kolumnie, D — łup w prawej, nieśmiertelniki u dołu; środek wolny
	_sum_box = Control.new()
	_sum_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_sum_box)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	var tiles: Array = model["tiles"]
	for i in tiles.size():
		_left.add_child(_tile(tiles[i], i))
	_sum_box.add_child(_left)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	var rc := Card.new(Color(CARD_BG, 0.92), UiTheme.LINE, 12)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 6)
	_build_loot(rbox)
	if rbox.get_child_count() > 0:
		rc.add_child(rbox)
		_right.add_child(rc)
	else:
		rbox.free()
		rc.free()
	_sum_box.add_child(_right)
	_tags = HBoxContainer.new()
	_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	_tags.add_theme_constant_override("separation", TAG_GAP)
	_build_squad(_tags)
	_sum_box.add_child(_tags)
	# Szczegóły: panel na środku (rozbicie | wyróżnienia, przebieg misji)
	_det_box = PanelContainer.new()
	_det_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.043, 0.047, 0.043, 0.96)
	dsb.border_color = UiTheme.PANEL_EDGE
	dsb.set_border_width_all(1)
	dsb.border_width_bottom = 2
	dsb.set_content_margin_all(PAD * 0.75)
	dsb.shadow_color = Color(0, 0, 0, 0.55)
	dsb.shadow_size = 18
	_det_box.add_theme_stylebox_override("panel", dsb)
	_det_box.add_child(_build_details())
	_panel.add_child(_det_box)
	# F — stopka: [V] Szczegóły, (w Szczegółach) próba · towarzysz AI · gracze, gotowość, akcje
	_foot = HBoxContainer.new()
	_foot.add_theme_constant_override("separation", 12)
	_det_btn = _prompt_button("result_details", tr("Details"), "details")
	_foot.add_child(_det_btn)
	_foot_l = UiTheme.mono(UiTheme.label(String(model["foot_l"]), _f(7), UiTheme.MUTED))
	_foot_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(_foot_l)
	_foot.add_child(_spacer())
	_ready_note = UiTheme.mono(UiTheme.label(String(model["ready_note"]), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	_ready_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(_ready_note)
	_skip_hint = UiTheme.label("[%s]  %s" % [Actions.key("result_continue"), tr("Skip")], _f(9), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_foot.add_child(_skip_hint)
	_prompt_box = HBoxContainer.new()
	_prompt_box.add_theme_constant_override("separation", 14)
	for p in Array(model["prompts"]):
		_prompt_box.add_child(_prompt_button(String(p["action"]), String(p["label"]), String(p["kind"])))
	_foot.add_child(_prompt_box)
	_panel.add_child(_foot)
	_cue_counters()
	_cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	_cues = thin_cues(_cues)
	_apply_layer(true)
	_layout()

func _prompt_button(action: String, label: String, kind: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = "[%s]  %s" % [Actions.key(action), label]
	b.add_theme_font_size_override("font_size", _f(10))
	var main_col: Color = UiTheme.MUTED if kind == "details" else UiTheme.ACCENT
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, main_col if st == "font_color" else UiTheme.WARM)
	b.pressed.connect(func() -> void: press(kind))
	return b

## Warstwa: skrót w trakcie sekwencji, potem wybór gracza (details_pref). `force` — po przebudowie widoku.
func _apply_layer(force := false) -> void:
	var want := details_pref and is_done()
	if want == _det_on and not force:
		return
	_det_on = want
	if _sum_box != null:
		_sum_box.visible = not want
	if _det_box != null:
		_det_box.visible = want
	if _scrim != null:
		_scrim.visible = not want
	if _foot_l != null:
		_foot_l.visible = want and _foot_l.text != ""
	if _det_btn != null:
		_det_btn.text = "[%s]  %s" % [Actions.key("result_details"), tr("Summary") if want else tr("Details")]

func _tile(td: Dictionary, i: int) -> Control:
	var ok: bool = td["ok"]
	var ladder: bool = model["ladder"]
	var tile := Card.new(CARD_BG, Color(UiTheme.OK, 0.45) if ok else UiTheme.LINE, 9)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, 40 if ladder else 0)
	if not ok:
		tile.edge = Color(BRASS, 0.35)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	tile.add_child(outer)
	var show_mark: bool = ok or bool(td.get("stamp", true))
	if show_mark:
		outer.add_child(Mark.new(ok, float(_f(14 if not ladder else 10))))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var lab := UiTheme.heading(String(td["label"]), _f(10), UiTheme.TEXT if ok else UiTheme.MUTED)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lab.clip_text = true
	top.add_child(lab)
	if not ok and bool(td.get("stamp", true)):               # D3: pieczątka tylko na wyjątku — STRACONE
		var stamp := _stamp(_tr("LOST"), UiTheme.DANGER, _f(8), 1)
		stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(stamp)
		stamp.rotation = deg_to_rad(-6.0 + 2.0 * float(i % 3))
		_anim(stamp, float(td["t"]) + 0.08, "stamp")
	if not ladder:
		var val := UiTheme.mono(UiTheme.label(String(td["value"]).replace(" / ", "/"), _f(12), UiTheme.WARM if ok else UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(val)
	box.add_child(top)
	if not ladder:
		var rx: int = td["reward_xp"]
		var rs: int = td["reward_scrap"]
		if rx > 0 or rs > 0:
			var rc: Color = UiTheme.ACCENT if ok else LOCKED
			var wrap := MarginContainer.new()
			wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var rew := HBoxContainer.new()
			rew.add_theme_constant_override("separation", 3)
			if rx > 0:
				rew.add_child(UiTheme.mono(UiTheme.label("+%d XP" % rx, _f(8), rc)))
			if rs > 0:
				if rx > 0:
					rew.add_child(_gap(6))
				rew.add_child(UiTheme.mono(UiTheme.label("+%d" % rs, _f(8), rc)))
				rew.add_child(Coin.new(float(_f(7)), not ok))
			wrap.add_child(rew)
			if not ok:
				wrap.add_child(Strike.new(LOCKED))
			box.add_child(wrap)
	else:
		box.add_child(UiTheme.label(String(td["what"]), _f(7), UiTheme.MUTED))
	_anim(tile, float(td["t"]), "fade")
	if ok:
		_cue_once("tiles", float(td["t"]) + 0.08, "stamp", 1.0)
	return tile

func _build_squad(box: BoxContainer) -> void:
	var squad: Array = model["squad"]
	if squad.is_empty():
		return
	for p in squad:
		var pd: Dictionary = p
		var row := Card.new(Color(0.063, 0.067, 0.059, 0.92), UiTheme.LINE, 0)
		row.edge = Color(0, 0, 0, 0)
		row.custom_minimum_size = Vector2(TAG_W, 0)
		row.size_flags_vertical = Control.SIZE_SHRINK_END
		var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
		sb.content_margin_left = 5
		sb.content_margin_right = 6
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		var slot_col: Color = SLOT_COLORS[clampi(int(pd["slot"]), 0, 3)]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var ptex: Texture2D = load(String(pd["portrait"])) as Texture2D if String(pd["portrait"]) != "" else null
		hb.add_child(Portrait.new(ptex, slot_col, float(_f(PORTRAIT)), bool(pd["gone"])))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 3)
		# blaszka: ▸ kryptonim (własna — kolor lampy), gotowość, liczby z ikonami — wszystko „wytłoczone”
		var tag := DogTag.new()
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		var me: bool = pd["me"]
		var nm := _emboss(UiTheme.mono(UiTheme.label(("▸ " if me else "") + String(pd["name"]).to_upper(), _f(11), Color("6a3a00") if me else EMBOSS)))
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		trow.add_child(nm)
		if String(pd["status"]) != "":
			var stc: Color = Color("1d4a22") if Color(pd["status_col"]) == UiTheme.OK else Color("6e1410")
			var stl := _emboss(UiTheme.mono(UiTheme.label(String(pd["status"]), _f(8), stc, HORIZONTAL_ALIGNMENT_RIGHT)))
			stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			trow.add_child(stl)
			_anim(stl, T_DONE, "fade")
		var nums := HBoxContainer.new()
		nums.add_theme_constant_override("separation", 3)
		nums.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for s in ["kills", "downs", "revives"]:
			if s != "kills":
				nums.add_child(_gap(6))
			var ic := StatIcon.new(String(s), float(_f(8)))
			ic.col = EMBOSS
			nums.add_child(ic)
			nums.add_child(_emboss(UiTheme.mono(UiTheme.label(str(int(pd[s])), _f(11), EMBOSS))))
		var tcol := VBoxContainer.new()                  # dwa wiersze wytłoczenia jak na prawdziwym nieśmiertelniku: kryptonim, liczby
		tcol.add_theme_constant_override("separation", 0)
		tcol.add_child(trow)
		tcol.add_child(nums)
		tag.add_child(tcol)
		if bool(pd["gone"]):
			tag.modulate = Color(0.6, 0.6, 0.6, 0.8)
		mid.add_child(tag)
		var aws: Array = pd["awards"]
		if not aws.is_empty():
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 5)
			flow.add_theme_constant_override("v_separation", 3)
			for a in aws:
				var ad: Dictionary = a
				var ac: Color = UiTheme.CALM if String(ad.get("kind", "")) == "level" else UiTheme.ACCENT
				var st := _stamp(String(ad["title"]), ac, _f(8), 1)
				st.rotation = deg_to_rad(-2.5)
				flow.add_child(st)
				_anim(st, float(ad["t"]), "stamp")
				_cue_once("awards", float(ad["t"]), "stamp", 0.8)
			mid.add_child(flow)
		hb.add_child(mid)
		row.add_child(hb)
		box.add_child(row)
		_anim(row, float(pd["t"]), "fade")

func _build_loot(box: VBoxContainer) -> void:
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]):
		var blk := VBoxContainer.new()
		blk.add_theme_constant_override("separation", 2)
		var h := HBoxContainer.new()
		var cap := UiTheme.mono(UiTheme.label(tr("SQUAD SCRAP"), _f(7), UiTheme.MUTED))
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cap)
		h.add_child(_spacer())
		_scrap_val = Odometer.new(maxi(3, str(int(sc["total"])).length()), _f(18), UiTheme.ACCENT)
		h.add_child(_scrap_val)
		blk.add_child(h)
		if bool(sc["ready"]) and int(sc["bonus"]) > 0:
			var sl := UiTheme.mono(UiTheme.label(tr("loot %d · bonuses %d") % [int(sc["loot"]), int(sc["bonus"])], _f(7), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
			blk.add_child(sl)
			_anim(sl, T_SCRAP + SCRAP_DUR, "fade")
		box.add_child(blk)
		_anim(blk, T_SCRAP - 0.05, "fade")
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]):
		if bool(sc["show"]):
			box.add_child(_rule())
		var blk := VBoxContainer.new()
		blk.add_theme_constant_override("separation", 4)
		var h := HBoxContainer.new()
		var cap := UiTheme.mono(UiTheme.label(tr("YOUR XP"), _f(7), UiTheme.MUTED))
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(cap)
		h.add_child(_spacer())
		_xp_val = Odometer.new(maxi(3, str(int(xd["earned"])).length()), _f(18), XP_COL)
		h.add_child(_xp_val)
		blk.add_child(h)
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 6)
		_lv_lo = UiTheme.mono(UiTheme.label("LV 1", _f(7), UiTheme.BONE_DIM))
		bar_row.add_child(_lv_lo)
		_xp_bar = XpBar.new()
		_xp_bar.custom_minimum_size = Vector2(0, 9)
		_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_row.add_child(_xp_bar)
		_lv_hi = UiTheme.mono(UiTheme.label("LV 2", _f(7), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		bar_row.add_child(_lv_hi)
		blk.add_child(bar_row)
		for lv in Array(xd["levels"]):
			var ld: Dictionary = lv
			var lr := HBoxContainer.new()
			lr.add_theme_constant_override("separation", 8)
			var patch := Patch.new(int(ld["lv"]), float(_f(20)))
			lr.add_child(patch)
			_anim(patch, float(ld["t"]) + 0.05, "stamp")
			_cue_once("levelup", float(ld["t"]), "levelup", 1.0)
			var lt := VBoxContainer.new()
			lt.add_theme_constant_override("separation", 0)
			lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lt.add_child(UiTheme.heading(tr("LEVEL UP · LEVEL %d") % int(ld["lv"]), _f(9), UiTheme.WARM))
			var un: Array = ld["unlocks"]
			if not un.is_empty():                   # skrót: najwyżej UNLOCKS_SHORT pozycji i „+N”; pełna lista w Szczegółach
				var short: Array = un.slice(0, UNLOCKS_SHORT)
				var more := un.size() - short.size()
				lt.add_child(UiTheme.label(", ".join(short) + ("  +%d" % more if more > 0 else ""), _f(8), UiTheme.BONE_DIM))
			lr.add_child(lt)
			_anim(lt, float(ld["t"]) + 0.3, "fade")
			blk.add_child(lr)
		var chips: Array = xd["chips"]
		if not chips.is_empty():
			var cf := HFlowContainer.new()
			cf.add_theme_constant_override("h_separation", 10)
			cf.add_theme_constant_override("v_separation", 3)
			for c in chips:
				var cd: Dictionary = c
				var n: Control
				if bool(cd["stamp"]):
					n = _stamp(String(cd["text"]), UiTheme.WARM, _f(8), 1)
					n.rotation = deg_to_rad(-3.0)
				else:
					n = UiTheme.mono(UiTheme.label(String(cd["text"]), _f(7), UiTheme.BONE_DIM))
					n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				cf.add_child(n)
			blk.add_child(cf)
			_anim(cf, T_XP + XP_DUR, "fade")
		box.add_child(blk)
		_anim(blk, T_XP - 0.05, "fade")
	var finds: Array = model["finds"]
	if not finds.is_empty():
		box.add_child(_rule())
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 4)
		for f in finds:
			var fd: Dictionary = f
			var n: Control
			if bool(fd["stamp"]):
				n = _stamp(String(fd["text"]), Color(fd["color"]), _f(8), 1, String(fd.get("why", "")))
				n.rotation = deg_to_rad(-4.0)
				_anim(n, float(fd["t"]), "stamp")
				_cue_once("finds", float(fd["t"]), String(fd.get("snd", "stamp")), 0.95)
			elif fd.has("icon"):
				var hb := HBoxContainer.new()
				hb.add_theme_constant_override("separation", 5)
				var tr_ := TextureRect.new()
				tr_.texture = load(String(fd["icon"]))
				tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr_.custom_minimum_size = Vector2(_f(44), _f(15))
				tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tr_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				hb.add_child(tr_)
				var nl := UiTheme.label(String(fd["text"]), _f(8), Color(fd["color"]))
				nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				hb.add_child(nl)
				n = hb
				_anim(n, float(fd["t"]), "stamp")
				_cue_once("finds", float(fd["t"]), "stamp", 0.95)
			else:
				n = UiTheme.label("◆ " + String(fd["text"]), _f(8), Color(fd["color"]))
				_anim(n, float(fd["t"]), "fade")
			flow.add_child(n)
		box.add_child(flow)

## Warstwa Szczegóły: pełne rozbicie złomu i XP | wyróżnienia z uzasadnieniem; pod spodem przebieg misji z legendą.
func _build_details() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]):
		left.add_child(_det_head(tr("SQUAD SCRAP"), "+%d" % int(sc["total"]) if bool(sc["ready"]) else "…", UiTheme.ACCENT))
		left.add_child(_rows_grid(sc["rows"]))
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]):
		left.add_child(_det_head(tr("YOUR XP"), "+%d" % int(xd["earned"]) if bool(xd["ready"]) else "…", XP_COL))
		left.add_child(_rows_grid(xd["rows"]))
		for lv in Array(xd["levels"]):                    # pełna lista odblokowań, po jednym w siatce (bez zawijania — stała wysokość warstwy)
			left.add_child(UiTheme.label(tr("LEVEL UP · LEVEL %d") % int((lv as Dictionary)["lv"]), _f(8), UiTheme.TEXT))
			var un: Array = (lv as Dictionary)["unlocks"]
			if not un.is_empty():
				var ug := GridContainer.new()
				ug.columns = 3
				ug.add_theme_constant_override("h_separation", 12)
				ug.add_theme_constant_override("v_separation", 0)
				for u in un:
					ug.add_child(UiTheme.label(String(u), _f(8), UiTheme.BONE_DIM))
				left.add_child(ug)
	if left.get_child_count() > 0:
		hb.add_child(left)
	else:
		left.free()
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	right.add_child(UiTheme.mono(UiTheme.label(tr("AWARDS"), _f(7), UiTheme.MUTED)))
	var any := false
	for p in Array(model["squad"]):
		for a in Array((p as Dictionary)["awards"]):
			var ad: Dictionary = a
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var st := _stamp(String(ad["title"]), UiTheme.CALM if String(ad.get("kind", "")) == "level" else UiTheme.ACCENT, _f(8), 1)
			st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(st)
			var why := UiTheme.label("%s · %s" % [String((p as Dictionary)["name"]), String(ad["why"])], _f(8), UiTheme.BONE_DIM)
			why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			why.clip_text = true
			row.add_child(why)
			right.add_child(row)
			any = true
	if any:
		hb.add_child(right)
	else:
		right.free()
	if hb.get_child_count() > 0:
		outer.add_child(hb)
	else:
		hb.free()
	var tl: Dictionary = model["timeline"]
	if bool(tl["show"]):
		outer.add_child(_build_strip(tl))
	return outer

func _det_head(cap: String, val: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_child(UiTheme.mono(UiTheme.label(cap, _f(7), UiTheme.MUTED)))
	h.add_child(_spacer())
	h.add_child(UiTheme.mono(UiTheme.label(val, _f(10), col, HORIZONTAL_ALIGNMENT_RIGHT)))
	return h

func _rows_grid(rows: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 0)
	for r in rows:
		grid.add_child(_row_cell(String(r[0]), int(r[1])))
	return grid

func _build_strip(tl: Dictionary) -> Control:
	var blk := VBoxContainer.new()
	blk.add_theme_constant_override("separation", 1)
	var h := HBoxContainer.new()
	h.add_child(UiTheme.mono(UiTheme.label(tr("MISSION TIMELINE"), _f(7), UiTheme.MUTED)))
	h.add_child(_spacer())
	var seen := {}
	for mk in Array(tl["marks"]):
		seen[String(mk[1])] = true
	var legend: Array = []
	for k in MARK_NAMES:
		if seen.has(k):
			legend.append("%s %s" % [MARKS[k][0], tr(String(MARK_NAMES[k]))])
	h.add_child(UiTheme.label("   ".join(legend), _f(7), UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	h.add_child(UiTheme.mono(UiTheme.label("  " + mmss(float(tl["len"])), _f(7), UiTheme.MUTED)))
	blk.add_child(h)
	_strip = RunStrip.new()
	_strip.custom_minimum_size = Vector2(0, 18)
	_strip.length = float(tl["len"])
	_strip.marks = tl["marks"]
	_strip.font = UiTheme.mono_font()
	blk.add_child(_strip)
	return blk

func _row_cell(label: String, v: int) -> Control:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(170, 0)
	var l := UiTheme.label(label, _f(8), UiTheme.BONE_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	hb.add_child(l)
	hb.add_child(UiTheme.mono(UiTheme.label("+%d" % v, _f(8), UiTheme.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)))
	return hb

## Pieczątka: tekst w ramce koloru tuszu (rotację i „przybicie” ustawia wołający).
func _stamp(text: String, col: Color, fsize: int, border: int, why := "") -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.06)
	sb.border_color = Color(col, 0.9)
	sb.set_border_width_all(border)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.add_child(UiTheme.heading(text, fsize, col))
	if why != "":
		var w := UiTheme.label(why, fsize, Color(col, 0.85))
		w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(w)
	pc.add_child(hb)
	return pc

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.HAIR
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

## Napis wytłoczony w blasze: ciemna litera z jasnym cieniem o piksel niżej.
func _emboss(l: Label) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.38))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_constant_override("outline_size", 0)
	return l

func _gap(w: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(w, 0)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

func _anim(n: Control, t0: float, kind: String) -> void:
	_anims.append({"node": n, "t": t0, "kind": kind})

func _cue(t0: float, snd: String, pitch: float) -> void:
	_cues.append({"t": t0, "snd": snd, "pitch": pitch})

## Jeden sygnał na sekcję raportu (cele, awans, wyróżnienia, znaleziska): gra pierwsza pozycja, reszta tylko się animuje.
func _cue_once(section: String, t0: float, snd: String, pitch: float) -> void:
	if _cued.has(section):
		return
	_cued[section] = true
	_cue(t0, snd, pitch)

## Liczniki złomu i XP: jedno cyknięcie, gdy licznik dojdzie do końca (zamiast cyknięcia na każdy krok).
## Przy awansie licznik XP milczy — jego sygnałem jest `ui_levelup`.
func _cue_counters() -> void:
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]) and bool(sc["ready"]) and int(sc["total"]) > 0:
		_cue(T_SCRAP + SCRAP_DUR, "tick", 1.3)
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]) and bool(xd["ready"]) and int(xd["earned"]) > 0 and Array(xd["levels"]).is_empty():
		_cue(T_XP + XP_DUR, "tick", 0.96)

## Odstęp sygnałów (posortowanych po czasie): dwa bliżej niż CUE_GAP nie grają oba — zostaje ten z wyższym CUE_PRIO,
## przy równym wcześniejszy.
static func thin_cues(cues: Array) -> Array:
	var kept: Array = []
	for c in cues:
		var cd: Dictionary = c
		if kept.is_empty() or float(cd["t"]) - float(kept.back()["t"]) >= CUE_GAP - 0.0001:
			kept.append(cd)
		elif int(CUE_PRIO.get(String(cd["snd"]), 0)) > int(CUE_PRIO.get(String(kept.back()["snd"]), 0)):
			kept[kept.size() - 1] = cd
	return kept

# ---------------------------------------------------------------- klatka

## Płótno raportu (DESIGN) na środku ekranu HUD, pomniejszone, gdy duża skala UI by je wypchnęła; w środku układ sceny: góra (tytuł),
## lewa kolumna (cele), prawa (łup), dół (nieśmiertelniki, stopka); Szczegóły — panel na środku między tytułem a stopką.
func _layout() -> void:
	var host := get_parent() as Control
	var area: Vector2 = host.size if host != null else get_viewport_rect().size
	size = area
	position = Vector2.ZERO
	var k := minf(1.0, minf(area.x / DESIGN.x, area.y / DESIGN.y))
	_panel.size = DESIGN
	_panel.scale = Vector2(k, k)
	_panel.position = ((area - DESIGN * k) * 0.5).floor()
	var inner := DESIGN.x - 2.0 * EDGE
	_top.size = Vector2(inner, 0)
	_top.reset_size()
	_top.size.x = inner
	_top.position = Vector2(EDGE, 14.0)
	var top_end := _top.position.y + _top.size.y + 14.0
	_foot.size = Vector2(inner, 0)
	_foot.reset_size()
	_foot.size.x = inner
	_foot.position = Vector2(EDGE, DESIGN.y - _foot.size.y - 10.0)
	_sum_box.position = Vector2.ZERO
	_sum_box.size = DESIGN
	_tags.size = Vector2(inner, 0)
	_tags.reset_size()
	_tags.size.x = inner
	_tags.position = Vector2(EDGE, _foot.position.y - _tags.size.y - 10.0)
	for side in [_left, _right]:
		var c: Control = side
		c.size = Vector2(COL_W, 0)
		c.reset_size()
		c.size.x = COL_W
	_left.position = Vector2(EDGE, top_end)
	_right.position = Vector2(DESIGN.x - EDGE - COL_W, top_end)
	_det_box.reset_size()
	var dw := minf(inner, DET_W)
	_det_box.size = Vector2(dw, 0)
	_det_box.reset_size()
	_det_box.size.x = dw
	var room := _foot.position.y - 12.0 - top_end
	_det_box.position = Vector2((DESIGN.x - dw) * 0.5, top_end + maxf(0.0, (room - _det_box.size.y) * 0.5))
	if _scrim != null:
		_scrim.size = area
		_scrim.col_w = (EDGE + COL_W + 24.0) * k
		_scrim.bottom_h = (DESIGN.y - _tags.position.y + 16.0) * k + (area.y - DESIGN.y * k) * 0.5
		_scrim.top_h = top_end * k + (area.y - DESIGN.y * k) * 0.5
		_scrim.queue_redraw()

## Czy kolumny skrótu nie wchodzą na nieśmiertelniki ani tytuł (test mieszczenia).
func scene_overlaps() -> Array:
	var bad: Array = []
	if _sum_box == null or not _sum_box.visible:
		return bad
	var tags_top := _tags.position.y if _tags.get_child_count() > 0 else _foot.position.y
	for side in [_left, _right]:
		var c: Control = side
		if c.get_child_count() > 0 and c.position.y + c.size.y > tags_top - 4.0:
			bad.append("%s do %.0f, nieśmiertelniki od %.0f" % ["lewa kolumna" if c == _left else "prawa kolumna", c.position.y + c.size.y, tags_top])
	if _tags.size.x > DESIGN.x - 2.0 * EDGE + 1.0:
		bad.append("nieśmiertelniki szersze niż ekran (%.0f)" % _tags.size.x)
	return bad

func _animate() -> void:
	if model.is_empty() or _panel == null:
		return
	_apply_layer()
	_layout()
	for a in _anims:
		var n: Control = a["node"]
		if not is_instance_valid(n):
			continue
		var t0: float = a["t"]
		match String(a["kind"]):
			"fade":
				n.modulate.a = _ease(clampf((t - t0) / FADE_DUR, 0.0, 1.0))
			"title":
				var p := _ease(clampf((t - t0) / STAMP_DUR, 0.0, 1.0))
				n.modulate.a = p
				n.pivot_offset = n.size * 0.5
				n.scale = Vector2.ONE * lerpf(1.18, 1.0, p)
			"stamp":
				var p := _ease(clampf((t - t0) / STAMP_DUR, 0.0, 1.0))
				n.modulate.a = p
				n.pivot_offset = n.size * 0.5
				n.scale = Vector2.ONE * lerpf(1.35, 1.0, p)
	if _sub != null:
		_sub.visible_ratio = clampf((t - T_SUB) / SUB_DUR, 0.0, 1.0)
	if _scrim != null:
		_scrim.a = 1.0 if _skipped else clampf(_age / 0.4, 0.0, 1.0)
		_scrim.queue_redraw()
	_drive_counters()
	var done := is_done()
	_prompt_box.modulate.a = 1.0 if done else 0.35
	_det_btn.modulate.a = 1.0 if done else 0.35
	_skip_hint.visible = not done
	if _strip != null:
		_strip.reveal = 1.0
		_strip.queue_redraw()

func _drive_counters() -> void:
	var sc: Dictionary = model["scrap"]
	if bool(sc["show"]) and _scrap_val != null:
		var p := _ease(clampf((t - T_SCRAP) / SCRAP_DUR, 0.0, 1.0))
		_scrap_val.set_value(float(sc["total"]) * p, bool(sc["ready"]))
	var xd: Dictionary = model["xp"]
	if bool(xd["show"]) and _xp_val != null:
		var p := _ease(clampf((t - T_XP) / XP_DUR, 0.0, 1.0))
		var gained_f := float(xd["earned"]) * p
		var shown: int = int(xd["start"]) + int(round(gained_f))
		_xp_val.set_value(gained_f, bool(xd["ready"]))
		var lv := Profile.level_of(shown)
		var lo := Profile.xp_for_level(lv)
		var hi := Profile.xp_for_level(lv + 1)
		_lv_lo.text = "LV %d" % lv
		_lv_hi.text = "LV %d" % (lv + 1)
		_xp_bar.value = float(shown - lo) / float(maxi(1, hi - lo)) if bool(xd["ready"]) else 0.0
		var fl := 0.0
		if not _skipped:
			for l in Array(xd["levels"]):
				var lt: float = (l as Dictionary)["t"]
				if t >= lt and t < lt + LEVEL_FLASH:
					fl = 1.0
		_xp_bar.flash = fl
		_xp_bar.queue_redraw()

func _fire_cues() -> void:
	while _cue_i < _cues.size() and float(_cues[_cue_i]["t"]) <= t:
		var c: Dictionary = _cues[_cue_i]
		_cue_i += 1
		if not _skipped:
			_play(String(c["snd"]), float(c["pitch"]))

func _play(id: String, pitch := 1.0) -> void:
	if not SND.has(id) or Audio == null:
		return
	var spec: Array = SND[id]
	Audio.play(String(spec[0]), Audio.BUS_UI, float(spec[1]), pitch)
	if id == "levelup":
		Audio.duck_result(LEVELUP_DUCK_DB, LEVELUP_DUCK_S)      # awans słychać nad kadencją wyniku

static func _f(n: int) -> int:
	return int(round(float(n) * FS))

static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
