extends Node
## Rejestruje akcje wejściowe w kodzie, żeby project.godot był prosty. Lista akcji i ich klawisze są w `actions.gd`.
## Dodatkowo wykrywa, z jakiego urządzenia gracz korzysta (klawiatura / mysz albo pad), żeby podpowiedzi pokazywały
## właściwe przyciski; ekrany odświeżają się po sygnale `device_changed`.

signal device_changed(pad: bool)

const Actions := preload("res://scripts/actions.gd")
const STICK_ON := 0.5                ## odchylenie drążka / spustu uznawane za „gracz używa pada"
const MOUSE_MOVE := 4.0              ## ruch myszy (piksele na zdarzenie) uznawany za „gracz używa myszy"

func _enter_tree() -> void:
	Actions.register()
	get_tree().node_added.connect(_on_node_added)         # dźwięk najechania na każdy przycisk (bez zmian w kodzie ekranów)

func _on_node_added(n: Node) -> void:
	if n is BaseButton and DisplayServer.get_name() != "headless":
		(n as BaseButton).mouse_entered.connect(_hover.bind(n))

func _hover(b: BaseButton) -> void:
	if is_instance_valid(b) and not b.disabled and b.is_visible_in_tree():
		Audio.play("ui_click", Audio.BUS_UI, -24.0, 1.6)

func _input(event: InputEvent) -> void:
	var pad := Actions.pad_mode
	if event is InputEventJoypadButton and event.pressed:
		pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= STICK_ON:
		pad = true
	elif event is InputEventKey and event.pressed:
		pad = false
	elif event is InputEventMouseButton and event.pressed:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() >= MOUSE_MOVE:
		pad = false
	if pad != Actions.pad_mode:
		Actions.pad_mode = pad
		device_changed.emit(pad)
