extends Control
## In-game HUD (English). Built in code on the shared theme (ui_theme.gd).
##
## Skala: cały HUD jest rysowany w 70% (UI_SCALE) — węzeł ma `scale` i logiczny rozmiar
## viewport / UI_SCALE (≈914×514), więc układ liczy się względem `size`, nie stałych 640×360.
## Layout (proporcje jak w viewporcie 640×360):
##   top-left    status card — NOISE meter with thresholds, HEALTH hearts,
##               OVERCHARGE charges, weapon slots, flashlight battery
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
const PROMPT_Y := 0.81           ## pasek kontekstowy (292/360)

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
	func _draw() -> void:
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
var _hearts: Pips
var _health_note: Label
var _charges: Pips
var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _battery: Bar
var _battery_note: Label
var _ammo_name: Label
var _ammo_count: Label
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
	_build_status_card()
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
	_place(_center, Vector2((w - cw) * 0.5, h * CENTER_Y), Vector2(cw, 28))
	_place(_center_sub, Vector2((w - cw) * 0.5, h * CENTER_Y + 28.0), Vector2(cw, 16))
	_place(_controls, Vector2(MARGIN, h - 16.0), Vector2(w - 2.0 * MARGIN, 12))
	_place(_f1, Vector2(w - MARGIN - SESSION_W, h - 16.0), Vector2(SESSION_W, 12))

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

func _row(parent: Container, caption: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var cap := UiTheme.label(caption, 7, UiTheme.MUTED)
	cap.custom_minimum_size = Vector2(62, 0)
	r.add_child(cap)
	parent.add_child(r)
	return r

func _build_status_card() -> void:
	var card := _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var noise_head := HBoxContainer.new()
	noise_head.add_child(UiTheme.label("NOISE", 8, UiTheme.MUTED))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	noise_head.add_child(spring)
	_noise_val = UiTheme.label("0%", 8, UiTheme.TEXT)
	noise_head.add_child(_noise_val)
	box.add_child(noise_head)
	_noise_bar = Bar.new()
	_noise_bar.custom_minimum_size = Vector2(160, 5)
	# progi z NoiseMgr: 30 = zasypia, 40 = niepokój (szept), 60 = budzi się ON
	_noise_bar.ticks = [
		[NoiseMgr.SLEEP_THRESHOLD / 100.0, Color(1, 1, 1, 0.35)],
		[NoiseMgr.UNEASY_THRESHOLD / 100.0, Color(1.0, 0.72, 0.28, 0.8)],
		[NoiseMgr.AWAKE_THRESHOLD / 100.0, Color(1.0, 0.28, 0.22, 0.95)],
	]
	box.add_child(_noise_bar)

	var hr := _row(box, "HEALTH")
	_hearts = Pips.new()
	_hearts.custom_minimum_size = Vector2(34, 9)
	hr.add_child(_hearts)
	_health_note = UiTheme.label("", 7, UiTheme.DANGER)
	hr.add_child(_health_note)

	var qr := _row(box, "OVERCHARGE  Q")
	_charges = Pips.new()
	_charges.shape = "diamond"
	_charges.count = NoiseMgr.OVERCHARGE_MAX
	_charges.on = UiTheme.ACCENT
	_charges.custom_minimum_size = Vector2(34, 9)
	qr.add_child(_charges)

	_slot_on = UiTheme.panel_box()
	_slot_on.bg_color = Color(0.25, 0.18, 0.06, 0.9)
	_slot_on.border_color = UiTheme.ACCENT
	_slot_on.set_content_margin_all(2)
	_slot_off = UiTheme.panel_box()
	_slot_off.bg_color = Color(1, 1, 1, 0.04)
	_slot_off.set_content_margin_all(2)
	# amunicja: nazwa broni, magazynek / zapas drużyny, status (przeładowanie, brak naboi)
	var ar := _row(box, "AMMO")
	_ammo_name = UiTheme.label("", 8, UiTheme.TEXT)
	ar.add_child(_ammo_name)
	_ammo_count = UiTheme.label("", 10, UiTheme.TEXT)
	_ammo_count.custom_minimum_size = Vector2(52, 0)
	ar.add_child(_ammo_count)
	_ammo_note = UiTheme.label("", 7, UiTheme.MUTED)
	ar.add_child(_ammo_note)
	# rozgrzanie lufy → hałas strzału (GDD §8.1): gracz widzi, ile Uwagi kosztuje następny strzał
	var hr2 := _row(box, "BARREL")
	_heat_bar = Bar.new()
	_heat_bar.custom_minimum_size = Vector2(60, 4)
	_heat_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr2.add_child(_heat_bar)
	_heat_note = UiTheme.label("", 7, UiTheme.MUTED)
	hr2.add_child(_heat_note)

	var wr := HBoxContainer.new()
	wr.add_theme_constant_override("separation", 3)
	for i in 4:
		var sl := PanelContainer.new()
		sl.custom_minimum_size = Vector2(52, 0)
		var l := UiTheme.label("", 7, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		sl.add_child(l)
		wr.add_child(sl)
		_slots.append(sl)
		_slot_labels.append(l)
	box.add_child(wr)

	var lr := _row(box, "LIGHT  L")
	_battery = Bar.new()
	_battery.custom_minimum_size = Vector2(60, 4)
	_battery.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lr.add_child(_battery)
	_battery_note = UiTheme.label("OFF", 7, UiTheme.MUTED)
	lr.add_child(_battery_note)

func _build_objective_card() -> void:
	_obj_card = _card(Vector2(MARGIN, MARGIN))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_obj_card.add_child(box)
	_obj_caption = UiTheme.label("OBJECTIVE", 7, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_obj_caption)
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
		"WASD move · SPACE jump · ↓+SPACE drop · SHIFT sneak · J/LMB fire · R reload · V/RMB melee · 1-3 gun · E take/revive · Q lure · L light",
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
	_drive_status()
	_drive_mission()
	_drive_prompt()
	_drive_controls()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		_controls_mode = 0 if _controls.visible else 1

func _drive_noise() -> void:
	var lvl := NoiseMgr.level
	_noise_val.text = "%d%%" % int(lvl)
	_noise_bar.value = lvl / 100.0
	var col := NOISE_COL_CALM
	if lvl >= NoiseMgr.AWAKE_THRESHOLD:
		col = UiTheme.DANGER.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_blink * 8.0)))
	elif lvl >= NoiseMgr.UNEASY_THRESHOLD:
		col = UiTheme.ACCENT
	_noise_bar.fill = col
	_noise_val.add_theme_color_override("font_color", col if lvl >= NoiseMgr.UNEASY_THRESHOLD else UiTheme.TEXT)
	_noise_bar.queue_redraw()
	_charges.filled = NoiseMgr.overcharge_charges
	_charges.queue_redraw()

func _drive_status() -> void:
	_session.text = _net_status()
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if m != null:
		var secs := int(m.elapsed)
		_clock.text = "%02d:%02d" % [secs / 60, secs % 60]
	if _player == null:
		return
	var hp: int = maxi(_player.hp, 0)
	if _last_hp >= 0 and hp < _last_hp:
		_hit_flash = 1.0
	_last_hp = hp
	_hearts.count = maxi(3, hp)
	_hearts.bonus_from = _player.MAX_HP
	_hearts.custom_minimum_size.x = _hearts.count * 11.0 - 2.0
	_hearts.filled = hp
	_hearts.queue_redraw()
	_health_note.text = "DOWN  %ds" % ceili(_player.bleed_left) if _player.dead else ""
	_drive_weapons()
	var pct: float = _player.battery / _player.BATTERY_MAX
	_battery.value = pct
	_battery.fill = Color(1.0, 0.95, 0.72) if _player.flashlight else (UiTheme.DANGER if pct < 0.2 else UiTheme.MUTED)
	_battery.queue_redraw()
	_battery_note.text = ("ON  %d%%" if _player.flashlight else "OFF  %d%%") % int(pct * 100.0)
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
		_slot_labels[i].text = "%s  %s" % [key, names[i]]
		_slots[i].add_theme_stylebox_override("panel", _slot_on if sel else _slot_off)
		_slot_labels[i].add_theme_color_override("font_color", UiTheme.ACCENT if sel else UiTheme.MUTED)
	_ammo_name.text = cur.name
	var mag: int = wc.mag_of(cur.id)
	var note := ""
	var col := UiTheme.TEXT
	if not cur.uses_ammo():
		_ammo_count.text = "—"
	elif cur.infinite:
		_ammo_count.text = "%d / ∞" % mag
	else:
		var res := Arsenal.get_reserve(cur.id)
		_ammo_count.text = "%d / %d" % [mag, res]
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
	_ammo_count.add_theme_color_override("font_color", col)
	_ammo_note.text = note
	_ammo_note.add_theme_color_override("font_color", UiTheme.ACCENT if note != "" and col != UiTheme.DANGER else col)
	var heat: float = wc.heat_of(cur.id)
	_heat_bar.value = heat if cur.n_max > cur.n_min else 0.0
	_heat_bar.fill = Color(0.62, 0.72, 0.78).lerp(Color(1.0, 0.3, 0.2), clampf(heat * 1.15, 0.0, 1.0))
	_heat_bar.queue_redraw()
	if cur.is_melee():
		_heat_note.text = ""
	elif cur.n_max > cur.n_min:
		_heat_note.text = "SHOT %.1f → %.1f" % [cur.noise(heat), cur.n_max]
	else:
		_heat_note.text = "SHOT %.1f" % cur.noise(0.0)

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
