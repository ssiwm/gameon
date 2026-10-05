extends Control
## HUD: pasek hałasu, HP, ostrzeżenie o stalkerze, status sieci, broń, down/revive.

const Weapons := preload("res://scripts/weapons.gd")
const Mission := preload("res://scripts/mission.gd")

@onready var _bar: ProgressBar = $NoiseBar
@onready var _noise_label: Label = $NoiseLabel
@onready var _hearts: Label = $Hearts
@onready var _warn: Label = $StalkerWarn
@onready var _status: Label = $Status
@onready var _oc: Label = $Overcharge
@onready var _weapon: Label = $Weapon
@onready var _prompt: Label = $Prompt

var _player: Node = null
var _blink := 0.0
## Jeden stinger na wejście w stan, inaczej przy 10 Hz synchronizacji
## warn_pulse grzmiałby bez przerwy.
var _warn_was := false
var _music_layer := -1
var _objective: Label
var _battery: Label
var _boss_bar: ColorRect
var _boss_fill: ColorRect
var _result: Panel
var _result_text: Label

## Linia celu i ekran wyniku tworzone w kodzie — main.tscn zostaje prosty.
func _ready() -> void:
	_objective = Label.new()
	_objective.position = Vector2(170, 30)
	_objective.size = Vector2(300, 18)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_font_size_override("font_size", 11)
	_objective.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(_objective)

	_battery = Label.new()
	_battery.position = Vector2(12, 110)
	_battery.size = Vector2(300, 16)
	_battery.add_theme_font_size_override("font_size", 11)
	add_child(_battery)

	# pasek Żyły (faza BOSS) pod linią celu — dwa prostokąty, bo ProgressBar
	# ma minimalną wysokość z motywu (~27 px) i wychodził gruby
	_boss_bar = ColorRect.new()
	_boss_bar.position = Vector2(220, 50)
	_boss_bar.size = Vector2(200, 5)
	_boss_bar.color = Color(0.12, 0.04, 0.05, 0.85)
	_boss_bar.visible = false
	add_child(_boss_bar)
	_boss_fill = ColorRect.new()
	_boss_fill.size = Vector2(200, 5)
	_boss_fill.color = Color(0.85, 0.22, 0.2)
	_boss_bar.add_child(_boss_fill)

	_result = Panel.new()
	_result.position = Vector2(170, 80)
	_result.size = Vector2(300, 190)
	_result.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.05, 0.92)
	sb.border_color = Color(0.4, 1.0, 0.5, 0.7)
	sb.set_border_width_all(1)
	_result.add_theme_stylebox_override("panel", sb)
	add_child(_result)
	_result_text = Label.new()
	_result_text.position = Vector2(10, 10)
	_result_text.size = Vector2(280, 170)
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_text.add_theme_font_size_override("font_size", 12)
	_result.add_child(_result_text)

func _process(delta: float) -> void:
	_bar.value = NoiseMgr.level
	_noise_label.text = "HAŁAS %d%%" % int(NoiseMgr.level)
	_bar.modulate = Color(1, 1, 1).lerp(Color(1, 0.25, 0.2), NoiseMgr.level / 100.0)

	_drive_music()
	_drive_warning(delta)

	# ładunki Przesterowania (GDD §8.4) — to decyzja, więc musi być widoczna
	var full := NoiseMgr.overcharge_charges
	var empty := maxi(0, NoiseMgr.OVERCHARGE_MAX - full)
	_oc.text = "Q PRZESTEROWANIE: " + "|".repeat(full) + "_".repeat(empty)
	_oc.modulate = Color(1, 0.85, 0.4) if full > 0 else Color(0.4, 0.4, 0.42)

	_drive_mission()

	_player = _find_local_player()
	_status.text = _net_status()
	if _player == null:
		_hearts.text = ""
		_prompt.text = ""
		_battery.text = ""
		return
	var hp: int = maxi(_player.hp, 0)
	_hearts.text = "HP " + "|".repeat(hp) + "_".repeat(maxi(0, 3 - hp))
	_weapon.text = "BROŃ: %s  [1/2/3]" % Weapons.def(_player.weapon)["name"]
	# latarka (GDD §14: licznik baterii) — światło to hałas, więc widoczny stan
	var pct := int(_player.battery / _player.BATTERY_MAX * 100.0)
	_battery.text = "LATARKA [L]: %s %d%%" % ["WŁ" if _player.flashlight else "wył", pct]
	_battery.add_theme_color_override("font_color",
		Color(1.0, 0.95, 0.7) if _player.flashlight else (Color(0.85, 0.4, 0.35) if pct < 20 else Color(0.6, 0.62, 0.66)))
	_prompt.remove_theme_color_override("font_color")
	var wipe_left: float = get_tree().current_scene.get("wipe_left") if get_tree().current_scene else 0.0
	if wipe_left > 0.0:
		# wipe = nieudana ekstrakcja, restart misji (GDD §4)
		_prompt.text = "WSZYSCY LEŻĄ — restart misji za %ds" % ceili(wipe_left)
		_prompt.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	elif _player.dead:
		# down: wykrwawianie 25 s — kolega może podnieść (GDD §4)
		_hearts.text += "  [LEŻYSZ — wykrwawienie za %ds]" % ceili(_player.bleed_left)
		if _player.revive_progress > 0.0:
			_prompt.text = "Podnoszą cię… %d%%" % int(_player.revive_progress * 100.0)
		else:
			_prompt.text = "Czekaj na pomoc kolegi…"
	else:
		_prompt.text = _player.revive_hint()


## Muzyka adaptacyjna: 4 warstwy po progach Uwagi (GDD §13). Progi są sztywne,
## bo potrzebujemy przewidywalnych przejść, a NoiseMgr ma już swoje progi
## (60 obudzenie, 30 sen) i nie chcemy ich dublować.
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


func _drive_warning(delta: float) -> void:
	_blink += delta
	var awake: bool = NoiseMgr.stalker_awake
	# faza niepokoju (GDD §8.1): ostrzeżenie ZANIM zacznie się kara
	var uneasy: bool = (not awake) and NoiseMgr.level >= NoiseMgr.UNEASY_THRESHOLD
	_warn.visible = awake or uneasy
	if awake:
		_warn.text = "ON SŁYSZY"
		_warn.add_theme_color_override("font_color", Color(1, 0.2, 0.15))
		_warn.modulate.a = 0.55 + 0.45 * sin(_blink * 6.0)
	elif uneasy:
		_warn.text = "COŚ SŁUCHA…"
		_warn.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
		_warn.modulate.a = 0.5 + 0.3 * sin(_blink * 3.0)
	if awake and not _warn_was:
		Audio.play("warn_pulse", Audio.BUS_UI, -12.0)
	_warn_was = awake

func _drive_mission() -> void:
	var m: Node = get_tree().current_scene.get("mission") if get_tree().current_scene else null
	if m == null or not NoiseMgr.has_network():
		_objective.text = ""
		_result.visible = false
		_boss_bar.visible = false
		return
	_objective.text = m.objective_text()
	var boss := get_tree().get_first_node_in_group("boss")
	_boss_bar.visible = boss != null and m.phase == Mission.Phase.BOSS
	if _boss_bar.visible:
		_boss_fill.size.x = 200.0 * clampf(boss.hp / maxf(1.0, boss.max_hp), 0.0, 1.0)
	_result.visible = m.phase == Mission.Phase.SUCCESS
	if _result.visible:
		var secs := int(m.elapsed)
		_result_text.text = "EKSTRAKCJA UDANA\n\nCzas: %d:%02d\nGniazda: %d/%d\nUpadki drużyny: %d\nPróba: %d\n\n%s" % [
			secs / 60, secs % 60, m.nests_total, m.nests_total, m.downs, m.attempts,
			"[Enter] nowa misja" if multiplayer.is_server() else "Czekaj — host zaczyna nową misję"]

func _find_local_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		# boty też mają autorytet hosta — HUD pokazuje tylko człowieka
		if not p.is_bot and p.is_multiplayer_authority():
			return p
	return null

func _net_status() -> String:
	if not NoiseMgr.has_network():
		return "SOLO"
	if multiplayer.is_server():
		return "HOST · %d/4" % (multiplayer.get_peers().size() + 1)
	return "KLIENT"
