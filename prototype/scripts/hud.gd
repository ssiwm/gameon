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

## HUD o 30% mniejszy niż w 1.6 (karty, paski, ikony i teksty razem; celownik ma własne CROSS_SCALE).
const UI_SCALE := 0.7
const MARGIN := 8.0              ## odstęp kart od krawędzi (jednostki logiczne HUD)
const CONTROLS_SHOW_S := 20.0
const NOISE_COL_CALM := Color(0.62, 0.72, 0.78)
const OBJ_W := 250.0             ## szerokość treści karty celu (zawijanie)
const SESSION_W := 152.0         ## szerokość bloku „sesja + zegar" w prawym górnym rogu
const WARN_Y := 0.255            ## wysokość ostrzeżenia nad środkiem ekranu (ułamek wysokości; 92/360)
const CENTER_Y := 0.39           ## napis „SQUAD DOWN" (140/360)
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
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, back)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), fill)
		for t in ticks:
			var x: float = size.x * float(t[0])
			draw_rect(Rect2(x - 0.5, -2.0, 1.0, size.y + 4.0), t[1])

## Miniatura broni z arkusza guns.png (wiersz = `gun_row`): sylwetka z obrysem i cieniem, warstwa świecąca,
## opcjonalnie „płytka" (ciemne tło z poświatą i paskiem w kolorze smugi pocisku). Całkowita skala `k` —
## ułamki rozmywają pixel-art. `tint` przygasza bronie niewybrane.
class GunIcon extends Control:
	const GUN_SHEET := "res://art/sprites/guns.png"
	const GUN_GLOW := "res://art/sprites/guns_glow.png"
	const FW := 24
	const FH := 9
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := -1
	var k := 1
	var plate := false
	var accent := Color(1.0, 0.85, 0.35)
	var tint := Color.WHITE
	func set_gun(r: int, col: Color, t: Color) -> void:
		if r == row and col == accent and t == tint:
			return
		row = r
		accent = col
		tint = t
		queue_redraw()
	func _draw() -> void:
		if plate:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.78))
			draw_rect(Rect2(0, 0, size.x, 1), Color(1, 1, 1, 0.07))
			draw_rect(Rect2(0, size.y - 2, size.x, 2), Color(accent.r, accent.g, accent.b, 0.85))
			# miękka poświata za bronią: kilka coraz mniejszych prostokątów
			for i in 4:
				var inset := 2.0 + i * 4.0
				draw_rect(Rect2(inset, inset * 0.5, size.x - 2.0 * inset, size.y - 2.0 - inset), Color(accent.r, accent.g, accent.b, 0.045))
		if row < 0 or not ResourceLoader.exists(GUN_SHEET):
			return
		var tex: Texture2D = load(GUN_SHEET)
		var gs := Vector2(FW * k, FH * k)
		var body := plate_inset()
		var dst := Rect2(((body - gs) * 0.5).round() + Vector2(0, 1), gs)
		var src := Rect2(0, row * FH, FW, FH)
		draw_texture_rect_region(tex, Rect2(dst.position + Vector2(0, k), dst.size), src, Color(0, 0, 0, 0.55))
		for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_texture_rect_region(tex, Rect2(dst.position + o * float(maxi(1, k / 2)), dst.size), src, Color(0, 0, 0, 0.85 * tint.a))
		draw_texture_rect_region(tex, dst, src, tint)
		if ResourceLoader.exists(GUN_GLOW):
			draw_texture_rect_region(load(GUN_GLOW), dst, src, Color(1, 1, 1, tint.a))
	## Obszar bez paska akcentu (płytka ma 2 px paska na dole).
	func plate_inset() -> Vector2:
		return Vector2(size.x, size.y - (2.0 if plate else 0.0))

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
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(u, u))
		for i in count:
			var c := on if i < filled else off
			if i >= bonus_from:
				c = bonus
			var o := Vector2(i * 11.0, 0.0)
			if shape == "heart":
				draw_circle(o + Vector2(2.5, 2.5), 2.6, c)
				draw_circle(o + Vector2(6.5, 2.5), 2.6, c)
				draw_colored_polygon(PackedVector2Array([o + Vector2(0, 3), o + Vector2(9, 3), o + Vector2(4.5, 8.5)]), c)
			else:
				draw_colored_polygon(PackedVector2Array([o + Vector2(4.5, 0), o + Vector2(9, 4.5), o + Vector2(4.5, 9), o + Vector2(0, 4.5)]), c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var _player: Node = null
var _blink := 0.0
var _warn_was := false
var _music_layer := -1
var _session_t := 0.0
## Pasek sterowania: -1 = auto (pierwsze CONTROLS_SHOW_S s), 0 = ukryty, 1 = pokazany (F1).
var _controls_mode := -1
var _hit_flash := 0.0
var _last_hp := -1

var _noise_bar: Bar
var _noise_val: Label
var _noise_state: Label
var _squad_card: PanelContainer
var _squad_box: VBoxContainer
var _squad_rows := {}            ## instance_id gracza -> słownik wiersza
var _gear_card: PanelContainer
var _reload_bar: Bar
var _charges: Pips
var _flares: Pips
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
var _result_stats: GridContainer
var _result_prompt: Label

var _slot_on: StyleBoxFlat
var _slot_off: StyleBoxFlat

func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pełny ekran w jednostkach logicznych: viewport / UI_SCALE, skala 0.7 od lewego górnego rogu
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(UI_SCALE, UI_SCALE)
	_build_noise_card()
	_build_squad_card()
	_build_gear_card()
	_build_objective_card()
	_build_session()
	_build_center()
	_build_prompt()
	_build_controls()
	_build_result()
	get_viewport().size_changed.connect(_fit)
	_fit()

## Dopasowuje rozmiar logiczny do viewportu i układa elementy przypięte do krawędzi / środka.
func _fit() -> void:
	size = get_viewport_rect().size / UI_SCALE
	var w := size.x
	var h := size.y
	_place(_session, Vector2(w - MARGIN - SESSION_W, MARGIN), Vector2(SESSION_W, 12))
	_place(_clock, Vector2(w - MARGIN - SESSION_W, MARGIN + 11.0), Vector2(SESSION_W, 14))
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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.add_child(UiTheme.label("NOISE", 8, UiTheme.MUTED))
	_noise_state = UiTheme.label("", 7, UiTheme.MUTED)
	head.add_child(_noise_state)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	_noise_val = UiTheme.label("0%", 9, UiTheme.TEXT)
	head.add_child(_noise_val)
	box.add_child(head)
	_noise_bar = Bar.new()
	_noise_bar.custom_minimum_size = Vector2(170, 6)
	# progi z NoiseMgr: 30 = zasypia, 40 = niepokój (szept), 60 = budzi się ON
	_noise_bar.ticks = [
		[NoiseMgr.SLEEP_THRESHOLD / 100.0, Color(1, 1, 1, 0.35)],
		[NoiseMgr.UNEASY_THRESHOLD / 100.0, Color(1.0, 0.72, 0.28, 0.8)],
		[NoiseMgr.AWAKE_THRESHOLD / 100.0, Color(1.0, 0.28, 0.22, 0.95)],
	]
	box.add_child(_noise_bar)

## Lewy dolny róg: karta drużyny (L4D / DRG). Wiersze powstają dynamicznie — _drive_squad().
func _build_squad_card() -> void:
	_squad_card = _card(Vector2(MARGIN, MARGIN))
	_squad_card.custom_minimum_size = Vector2(SQUAD_W, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 3)
	_squad_card.add_child(outer)
	outer.add_child(UiTheme.label("SQUAD", 6, UiTheme.MUTED))
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 5)
	outer.add_child(_squad_box)

## Dół, środek: płaski pasek broni i zasobów w jednym rzędzie (nie zasłania bossa po prawej stronie sceny):
## [nazwa + koszt strzału] [magazynek / zapas] [stan + przeładowanie + ciepło lufy] [sloty] [wabik, flary, latarka].
func _build_gear_card() -> void:
	_gear_card = _card(Vector2(MARGIN, MARGIN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
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
	_gun_main.k = 2
	_gun_main.custom_minimum_size = Vector2(58, 26)
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
	_ammo_mag = UiTheme.label("", 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_mag.custom_minimum_size = Vector2(26, 0)
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
		ic.custom_minimum_size = Vector2(30, 12)
		var l := UiTheme.label("", 6, UiTheme.TEXT)
		l.position = Vector2(0, -2)
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
	pips.count = maxi(p.MAX_HP, hp)
	pips.bonus_from = p.MAX_HP
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
	_obj_caption = UiTheme.label("OBJECTIVE", 7, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
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
	_boss_row = VBoxContainer.new()
	_boss_row.add_theme_constant_override("separation", 2)
	_boss_name = UiTheme.label("THE VEIN — MOTHER OF NESTS", 7, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_boss_row.add_child(_boss_name)
	_boss_bar = Bar.new()
	_boss_bar.custom_minimum_size = Vector2(OBJ_W, 5)
	_boss_bar.fill = Color(0.88, 0.22, 0.2)
	_boss_bar.ticks = [[0.66, Color(1, 1, 1, 0.5)], [0.33, Color(1, 1, 1, 0.5)]]
	_boss_row.add_child(_boss_bar)
	box.add_child(_boss_row)

func _build_session() -> void:
	_session = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_session)
	_clock = UiTheme.label("", 10, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_clock)

func _build_center() -> void:
	_warn = UiTheme.label("", 14, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_warn)
	_warn_sub = UiTheme.label("", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_warn_sub)
	# krótkie komunikaty (np. „wabik już nie działa tutaj")
	_note = UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_note.modulate.a = 0.0
	add_child(_note)
	NoiseMgr.overcharge_stale.connect(func() -> void: show_note("They know this trick — move before you lure again"))
	_center = UiTheme.label("", 20, UiTheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
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
	_controls = UiTheme.label(
		"WASD move · SPACE jump · ↓+SPACE drop · SHIFT sneak · J/LMB fire · R reload · V/RMB melee · 1-3 gun · E take/revive · Q lure · F flare · G scream · L light",
		7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_controls)
	_f1 = UiTheme.label("F1  controls", 7, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_f1)

func _build_result() -> void:
	_result = _card(Vector2(MARGIN, MARGIN))
	_result.custom_minimum_size = Vector2(240, 0)
	var rb := UiTheme.panel_box()
	rb.bg_color = Color(0.02, 0.025, 0.035, 0.95)
	rb.border_color = Color(UiTheme.OK, 0.5)
	rb.set_content_margin_all(12)
	_result.add_theme_stylebox_override("panel", rb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_result.add_child(box)
	box.add_child(UiTheme.label("EXTRACTION COMPLETE", 16, UiTheme.OK, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UiTheme.label("The squad made it out of the woods.", 8, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_result_stats = GridContainer.new()
	_result_stats.columns = 2
	_result_stats.add_theme_constant_override("h_separation", 16)
	_result_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_result_stats)
	_result_prompt = UiTheme.label("", 9, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_result_prompt)
	_result.visible = false

# ---------------------------------------------------------------- klatka

func _process(delta: float) -> void:
	_drive_music()
	var in_session := NoiseMgr.has_network()
	visible = in_session
	if not in_session:
		_session_t = 0.0
		_last_hp = -1
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
	_drive_controls()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_controls_mode = 0 if _controls.visible else 1

## Krótki komunikat środkowy (znika po `secs`).
func show_note(text: String, secs := 3.0) -> void:
	_note.text = text
	_note.modulate.a = 1.0
	_note_t = secs

func _drive_noise() -> void:
	if _note_t > 0.0:
		_note_t -= get_process_delta_time()
		_note.modulate.a = clampf(_note_t / 0.6, 0.0, 1.0)
	var lvl := NoiseMgr.level
	_noise_val.text = "%d%%" % int(lvl)
	_noise_bar.value = lvl / 100.0
	var col := NOISE_COL_CALM
	if lvl >= NoiseMgr.AWAKE_THRESHOLD:
		col = UiTheme.DANGER.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_blink * 8.0)))
	elif lvl >= NoiseMgr.UNEASY_THRESHOLD:
		col = UiTheme.ACCENT
	_noise_bar.fill = col
	var awake: bool = NoiseMgr.stalker_awake
	_noise_state.text = "HUNTED" if awake else ("UNEASY" if lvl >= NoiseMgr.UNEASY_THRESHOLD else "CALM")
	_noise_state.add_theme_color_override("font_color", UiTheme.DANGER if awake else (UiTheme.ACCENT if lvl >= NoiseMgr.UNEASY_THRESHOLD else UiTheme.MUTED))
	_noise_val.add_theme_color_override("font_color", col if lvl >= NoiseMgr.UNEASY_THRESHOLD else UiTheme.TEXT)
	_noise_bar.queue_redraw()
	_charges.filled = NoiseMgr.overcharge_charges
	_charges.queue_redraw()
	_flares.filled = NoiseMgr.flares
	_flares.queue_redraw()

func _drive_status() -> void:
	_session.text = _net_status()
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
	_ammo_name.text = cur.name
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
		note = "RELOADING %d%%" % int(wc.reload_progress() * 100.0)
	elif wc.state == wc.State.CHARGE:
		note = "CHARGING %d%%" % int(wc.charge * 100.0)
	elif note == "" and cur.uses_ammo() and mag <= 0 and wc.ammo_enabled:
		note = "[R] RELOAD"
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
	_gear_card.position = Vector2((size.x - _gear_card.size.x) * 0.5, size.y - BOTTOM_PAD - _gear_card.size.y)

## Ostrzeżenie przed karą (GDD §8.1): niepokój ZANIM ON się obudzi.
func _drive_warning() -> void:
	var awake: bool = NoiseMgr.stalker_awake
	var uneasy: bool = (not awake) and NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD
	if awake:
		_warn.text = "HE HEARS YOU"
		_warn.add_theme_color_override("font_color", UiTheme.DANGER)
		_warn.modulate.a = 0.6 + 0.4 * sin(_blink * 6.0)
		_warn_sub.text = "Go quiet until the noise drops below 30% — or use Q to lure him off"
	elif uneasy:
		_warn.text = "SOMETHING IS LISTENING…"
		_warn.add_theme_color_override("font_color", UiTheme.ACCENT)
		_warn.modulate.a = 0.55 + 0.3 * sin(_blink * 3.0)
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
	_obj_card.visible = m.phase != Mission.Phase.SUCCESS
	_obj_caption.text = m.objective_caption()
	_obj_caption.add_theme_color_override("font_color", UiTheme.DANGER if m.phase == Mission.Phase.BOSS else (UiTheme.OK if m.phase == Mission.Phase.EXTRACT else UiTheme.ACCENT))
	_obj_text.text = m.objective_text()
	_obj_hint.text = m.objective_hint()
	_obj_hint.visible = _obj_hint.text != ""
	_boss_row.visible = boss != null and m.phase == Mission.Phase.BOSS
	if _boss_row.visible:
		_boss_bar.value = boss.hp / maxf(1.0, boss.max_hp)
		_boss_bar.queue_redraw()
		_boss_name.text = "THE VEIN — MOTHER OF NESTS" + ("   ·   ENRAGED" if boss.phase >= 2 else "")
	# karta celu: wyśrodkowana, szerokość wg treści
	_obj_card.reset_size()
	_obj_card.position = Vector2((size.x - _obj_card.size.x) * 0.5, MARGIN)
	# ostrzeżenie zawsze pod kartą celu (karta bossa jest wyższa)
	var wy := maxf(size.y * WARN_Y, _obj_card.position.y + _obj_card.size.y + 10.0)
	_warn.position.y = wy
	_warn_sub.position.y = wy + 20.0

	var show_result: bool = m.phase == Mission.Phase.SUCCESS
	if show_result and not _result.visible:
		_fill_result(m)
	_result.visible = show_result

func _fill_result(m: Node) -> void:
	for c in _result_stats.get_children():
		_result_stats.remove_child(c)
		c.free()
	var secs := int(m.elapsed)
	for row in [["Time", "%d:%02d" % [secs / 60, secs % 60]], ["Nests destroyed", "%d / %d" % [m.nests_total, m.nests_total]],
			["The Vein", "slain"], ["Squad downs", str(m.downs)], ["Attempt", "#%d" % m.attempts]]:
		_result_stats.add_child(UiTheme.label(row[0], 9, UiTheme.MUTED))
		_result_stats.add_child(UiTheme.label(row[1], 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	_result_prompt.text = "[ENTER]  New mission" if multiplayer.is_server() else "Waiting for the host to start a new mission…"
	_result.reset_size()
	_result.position = (size - _result.size) * 0.5

## Pasek kontekstowy: wipe, leżenie, podnoszenie, ekstrakcja.
func _drive_prompt() -> void:
	var text := ""
	var prog := -1.0
	var col := UiTheme.TEXT
	_center.text = ""
	_center_sub.text = ""
	var wipe_left: float = get_tree().current_scene.get("wipe_left") if get_tree().current_scene else 0.0
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if wipe_left > 0.0:
		_center.text = "SQUAD DOWN"
		_center_sub.text = "Extraction failed — restarting the mission in %d" % ceili(wipe_left)
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
	elif _player != null and _player.weapons.nearby_weapon_item() != null:
		var it: Node2D = _player.weapons.nearby_weapon_item()
		var nd: RefCounted = Weapons.def(it.arg)
		var wc2: Node = _player.weapons
		var swap_out: String = Weapons.def(wc2.loadout[wc2.slot if wc2.slot < 2 else 0]).name if nd.slot == Weapons.Slot.PRIMARY else Weapons.def(wc2.melee_id).name
		text = "[E]  Take %s  (drops %s)" % [nd.name, swap_out] if not wc2.carries(it.arg) else "[E]  Take ammo for %s" % nd.name
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
	var a := _hit_flash * 0.55
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
