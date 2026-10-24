extends "res://scripts/hud_icon.gd"
## Ikona HUD-u z faktycznie zamontowanymi częściami gracza, bez dopisywania odblokowanych części.
const Preview := preload("res://scripts/gun_preview.gd")
var _signature := ""
var _renderer: Node

func set_weapon(k: String, fit: int, notches: int, t := Color.WHITE) -> void:
	var sig := Preview.signature(k, fit, notches)
	if sig == _signature:
		if tint != t:
			tint = t
			queue_redraw()
		return
	_signature = sig
	key = k
	tint = t
	if fit == 0 and notches == 0:
		_tex = texture_of(k)
	else:
		if not is_instance_valid(_renderer):
			_renderer = Preview.service(get_tree())
			_renderer.rendered.connect(_accept_texture)
		_tex = _renderer.request(k, fit, notches)
	queue_redraw()

func _accept_texture(sig: String, tex: Texture2D) -> void:
	if sig != _signature:
		return # poprzedni zestaw skończył się wypiekać już po przełączeniu broni
	_tex = tex if tex != null else texture_of(key)
	queue_redraw()
