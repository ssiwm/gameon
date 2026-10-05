extends Control
## HUD: pasek hałasu, HP, ostrzeżenie o stalkerze, status sieci, broń, down/revive.

const Weapons := preload("res://scripts/weapons.gd")

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

	_player = _find_local_player()
	_status.text = _net_status()
	if _player == null:
		_hearts.text = ""
		_prompt.text = ""
		return
	var hp: int = maxi(_player.hp, 0)
	_hearts.text = "HP " + "|".repeat(hp) + "_".repeat(maxi(0, 3 - hp))
	_weapon.text = "BROŃ: %s  [1/2/3]" % Weapons.def(_player.weapon)["name"]
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
