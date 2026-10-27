extends HBoxContainer
## Prezentacja ławy ARMS. Dane i operacje należą do WorkshopUI; ten panel tylko wybiera i pokazuje.
const UiTheme := preload("res://scripts/ui_theme.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const Actions := preload("res://scripts/actions.gd")

signal weapon_selected(index: int)
signal slot_selected(slot: String)
signal option_selected(index: int)
signal inspect_requested
signal save_requested

var stage: GunStage
var _rack: VBoxContainer
var _rack_scroll: ScrollContainer
var _rack_all: Button
var _rack_carried: Button
var _slots: HBoxContainer
var _parts: HBoxContainer
var _part_scroll: ScrollContainer
var _title: Label
var _meta: Label
var _state: Label
var _part_title: Label
var _summary: VBoxContainer
var _summary_scroll: ScrollContainer
var _scroll_fraction := 0.0
var _details: Button
var _scroll_hint: Label
var _motion: Button
var _inspect: Button
var _save: Button
var _overlay: Control
var _hotspots: Array = []
var _payload: Dictionary = {}
var _rack_signature := ""
var _slot_signature := ""
var _part_signature := ""
var _show_all := false
var _show_details := false

class Anchors extends Control:
	var lines: Array = []
	func _draw() -> void:
		for ln in lines:
			draw_line(ln[0], ln[1], Color(0.77, 0.69, 0.44, 0.65), 0.6, true)
			draw_circle(ln[0], 2.0, Color(0.93, 0.69, 0.3))

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	var rack_box := VBoxContainer.new()
	rack_box.custom_minimum_size.x = 98
	add_child(rack_box)
	var rack_modes := HBoxContainer.new()
	rack_modes.add_theme_constant_override("separation", 2)
	rack_box.add_child(rack_modes)
	_rack_carried = _button(tr("CARRIED"), func(): _set_rack(false))
	_rack_carried.tooltip_text = tr("Weapons you carry.")
	_rack_all = _button(tr("ALL"), func(): _set_rack(true))
	_rack_all.tooltip_text = tr("The full armoury, including weapons you do not carry.")
	for b in [_rack_carried, _rack_all]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rack_modes.add_child(b)
	_rack_scroll = _scroll(rack_box)
	_rack = VBoxContainer.new()
	_rack.add_theme_constant_override("separation", 3)
	_rack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rack_scroll.add_child(_rack)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 4)
	add_child(middle)
	var head := HBoxContainer.new()
	_title = UiTheme.heading("", 17, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_inspect = _button(tr("Inspect"), func(): inspect_requested.emit())
	head.add_child(_inspect)
	_motion = _button(tr("Animations: on"), _toggle_motion)
	_motion.tooltip_text = tr("Part pull-out, camera drift and the mount animation on the bench (reduced motion turns them off).")
	head.add_child(_motion)
	middle.add_child(head)
	stage = GunStage.new()
	stage.bench_mode = true
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 104
	middle.add_child(stage)
	stage.slot_clicked.connect(func(slot: String): slot_selected.emit(slot))
	_overlay = Anchors.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_overlay)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 2)
	middle.add_child(_slots)
	_part_scroll = ScrollContainer.new()
	_part_scroll.custom_minimum_size.y = 71
	_part_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(_part_scroll)
	_parts = HBoxContainer.new()
	_parts.add_theme_constant_override("separation", 4)
	_part_scroll.add_child(_parts)
	var paper := PanelContainer.new()
	paper.custom_minimum_size.x = 165
	paper.add_theme_stylebox_override("panel", _paper_box())
	add_child(paper)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	paper.add_child(card)
	_state = _ink("", 9)
	card.add_child(_state)
	_part_title = _ink("", 12)
	_part_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_part_title)
	_meta = _ink("", 8)
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta.max_lines_visible = 3
	card.add_child(_meta)
	var content := _scroll(card)
	_summary_scroll = content
	_summary = VBoxContainer.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_constant_override("separation", 4)
	content.add_child(_summary)
	_details = _button(tr("All parameters"), _toggle_details)
	card.add_child(_details)
	_scroll_hint = _ink("", 7)
	_scroll_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_scroll_hint)
	_save = _button(tr("Save current set"), func(): save_requested.emit())
	card.add_child(_save)
	visibility_changed.connect(_visibility)
	stage.set_reduced_motion(Settings.reduce_fx)
	_motion.text = tr("Animations: off") if stage.reduced_motion else tr("Animations: on")

func _scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll

func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 8)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": UiTheme.TILE_BG, "disabled": Color("181b15")}.get(state_name, UiTheme.TILE_BG_SEL)
		box.border_color = UiTheme.TILE_EDGE if state_name == "disabled" else UiTheme.TILE_EDGE_HOVER
		box.set_border_width_all(1)
		box.content_margin_left = 4
		box.content_margin_right = 4
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		b.add_theme_stylebox_override(state_name, box)
	b.add_theme_color_override("font_disabled_color", UiTheme.MUTED)        # wyłączony = stan („oglądasz”), musi dać się przeczytać
	b.pressed.connect(callback)
	return b

func _paper_box() -> StyleBoxFlat:
	return UiTheme.paper_box()

func _ink(text: String, font_size: int) -> Label:
	var label := UiTheme.ink(text, font_size)
	label.custom_minimum_size.x = 149
	return label

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func present(data: Dictionary) -> void:
	_payload = data
	_title.text = String(data["name"])
	_meta.text = String(data["meta"])
	_meta.tooltip_text = String(data["tag"])
	_state.text = tr("AWAITING CONFIRMATION") if bool(data["pending"]) else (tr("LOCKED WEAPON") if not bool(data["unlocked"]) else (tr("PREVIEW · NOT FITTED") if bool(data["preview"]) else tr("CURRENT FIT")))
	_part_title.text = String(data["part_name"]) if int(data["option"]) >= 0 else tr("Gunsmith's card")
	_save.disabled = not bool(data["unlocked"]) or bool(data["pending"])
	_inspect.disabled = int(data["option"]) < 0
	_present_rack()
	_present_slots()
	_present_parts()
	_present_summary()

func _present_rack() -> void:
	var records: Array = _payload["weapons"]
	for record in records:
		if bool(record["selected"]) and not bool(record["carried"]):
			_show_all = true
	_rack_all.add_theme_color_override("font_color", UiTheme.ACCENT if _show_all else UiTheme.TEXT)
	_rack_carried.add_theme_color_override("font_color", UiTheme.TEXT if _show_all else UiTheme.ACCENT)
	var sig := str(records) + str(_show_all)
	if sig == _rack_signature:
		return
	_rack_signature = sig
	_clear(_rack)
	for record in records:
		if not _show_all and not bool(record["carried"]):
			continue
		var b := _button("", func(): weapon_selected.emit(int(record["index"])))
		b.custom_minimum_size = Vector2(94, 46)
		b.tooltip_text = String(record["name"]) + " · " + String(record["status"])
		var icon := GunIcon.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(4, 4)
		icon.size = Vector2(86, 22)
		icon.set_gun(int(record["row"]), record["color"], Color.WHITE)
		b.add_child(icon)
		var label := UiTheme.label(String(record["name"]), 9, UiTheme.ACCENT if bool(record["selected"]) else UiTheme.TEXT)
		label.position = Vector2(4, 26)
		b.add_child(label)
		var status := UiTheme.label(String(record["status"]), 7, UiTheme.TEXT)
		status.position = Vector2(4, 36)
		b.add_child(status)
		if bool(record["selected"]):
			b.modulate = Color(1.15, 1.1, 0.85)
		_rack.add_child(b)

func _present_slots() -> void:
	var slots: Array = _payload["slots"]
	var sig := str(slots) + String(_payload["slot"])
	if sig == _slot_signature:
		return
	_slot_signature = sig
	_clear(_slots)
	_clear(_overlay)
	_hotspots.clear()
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var selected := String(slot["id"]) == String(_payload["slot"])
		var preset := String(slot["id"]) == "preset"
		if preset:
			var gap := Control.new()
			gap.custom_minimum_size.x = 8
			_slots.add_child(gap)
		var b := _button(String(slot["short"]) if preset else "%d %s" % [i + 1, slot["short"]], func(): slot_selected.emit(String(slot["id"])))
		b.tooltip_text = String(slot["name"]) + " · " + String(slot["fitted"])
		b.size_flags_horizontal = Control.SIZE_FILL if preset else Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", UiTheme.ACCENT if selected else UiTheme.TEXT)
		_slots.add_child(b)
		if preset:
			continue
		var hotspot := _button(str(i + 1), func(): slot_selected.emit(String(slot["id"])))
		hotspot.custom_minimum_size = Vector2(20, 18)
		hotspot.tooltip_text = b.tooltip_text
		hotspot.add_theme_color_override("font_color", UiTheme.ACCENT if selected else UiTheme.TEXT)
		_overlay.add_child(hotspot)
		_hotspots.append({"button": hotspot, "slot": slot["id"], "index": i})

func _present_parts() -> void:
	var records: Array = _payload["options"]
	var sig := str(records) + str(_payload["option"])
	if sig == _part_signature:
		return
	_part_signature = sig
	_clear(_parts)
	for record in records:
		var b := _button("", func(): option_selected.emit(int(record["index"])))
		b.custom_minimum_size = Vector2(83, 54)
		b.tooltip_text = String(record["name"]) + " · " + String(record["status"])
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 5
		box.offset_right = -5
		box.offset_top = 4
		box.add_theme_constant_override("separation", 2)
		b.add_child(box)
		var nm := UiTheme.label(String(record["name"]), 9, UiTheme.ACCENT if int(record["index"]) == int(_payload["option"]) else UiTheme.TEXT)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size.x = 73
		nm.max_lines_visible = 2
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(nm)
		box.add_child(UiTheme.label(String(record["status"]), 8, UiTheme.OK if bool(record["fitted"]) else UiTheme.TEXT))
		_parts.add_child(b)
	call_deferred("_reveal_part")

func _reveal_part() -> void:
	if not is_visible_in_tree():
		return
	var records: Array = _payload.get("options", [])
	for i in mini(records.size(), _parts.get_child_count()):
		if int(records[i]["index"]) == int(_payload.get("option", -1)):
			var row := _parts.get_child(i) as Control
			if _part_scroll.is_ancestor_of(row):
				_part_scroll.ensure_control_visible(row)

func _present_summary() -> void:
	_clear(_summary)
	var rows: Array = _payload["rows"]
	var changes: Array = rows.filter(func(row: Array) -> bool: return String(row[1]) != String(row[2]))
	var shown: Array = rows if _show_details else (changes if not changes.is_empty() else rows)
	for i in mini(shown.size(), shown.size() if _show_details else 4):
		var row: Array = shown[i]
		var kind := int(row[3])
		var caption := String(row[0])
		if String(row[1]) != String(row[2]) and kind != 0:
			caption += " · " + (tr("Gain") if kind > 0 else tr("Trade-off"))
		var changed := String(row[1]) != String(row[2])
		var value := UiTheme.num_text(String(row[1]))
		if changed:
			value = ("[%s] → [%s]" if value.contains("→") or String(row[2]).contains("→") else "%s → %s") % [UiTheme.num_text(String(row[1])), UiTheme.num_text(String(row[2]))]
		var value_label := _ink(value, 10)
		if changed and kind != 0:
			value_label.add_theme_color_override("font_color", UiTheme.INK_GAIN if kind > 0 else UiTheme.INK_COST)
		var line: BoxContainer = VBoxContainer.new() if changed else HBoxContainer.new()
		line.add_theme_constant_override("separation", 0 if changed else 4)
		var caption_label := _ink(caption, 8)
		if not changed:
			caption_label.custom_minimum_size.x = 0                       # _ink daje pełną szerokość karty — w wierszu dzielą ją dwa napisy
			value_label.custom_minimum_size.x = 0
			caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(caption_label)
		line.add_child(value_label)
		_summary.add_child(line)
	if not _show_details and changes.size() > 4:
		var more := changes.size() - 4
		_summary.add_child(_ink(tr_n("%d more change in parameters", "%d more changes in parameters", more) % more, 8))      # formy mnogie: translations/plural.csv
	var desc := _ink(String(_payload["description"]), 8)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(desc)
	var scope := _ink(tr("Configuration only. Handling also depends on the edge and mastery.") if bool(_payload.get("melee", false))
		else tr("Configuration + loaded ammo. Handling also depends on wear, heat and mastery."), 7)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(scope)
	_details.text = (tr("Main changes") if _show_details else tr("All parameters")) + " · " + Actions.text("menu_details")
	_scroll_hint.text = tr("Scroll card: %s") % Actions.cluster(["menu_scroll_up", "menu_scroll_down"], " / ")

func _set_rack(all: bool) -> void:
	if all == _show_all:
		return
	_show_all = all
	# Wybrana broń spoza ekwipunku nie wymusza powrotu do pełnej listy podczas tego przełączenia.
	_rack_signature = ""
	if not _show_all:
		var records: Array = _payload["weapons"]
		for record in records:
			if bool(record["carried"]):
				weapon_selected.emit(int(record["index"]))
				return
	_present_rack()

func _toggle_details() -> void:
	_show_details = not _show_details
	_present_summary()

func _toggle_motion() -> void:
	stage.set_reduced_motion(not stage.reduced_motion)
	_motion.text = tr("Animations: off") if stage.reduced_motion else tr("Animations: on")

func _visibility() -> void:
	stage.set_rendering(is_visible_in_tree())
	if not is_visible_in_tree():
		stage.cancel_mount()
		_scroll_fraction = 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var scroll := Input.get_axis("menu_scroll_up", "menu_scroll_down")
	if absf(scroll) > 0.15:
		_scroll_fraction += scroll * 180.0 * delta
		var step := int(_scroll_fraction)
		_summary_scroll.scroll_vertical += step
		_scroll_fraction -= step
	else:
		_scroll_fraction = 0.0
	var lines: Array = []
	var lanes: Array = [[], []]
	for item in _hotspots:
		var b: Button = item["button"]
		var anchor: Vector2 = stage.slot_screen_position(String(item["slot"]))
		b.visible = anchor.is_finite() and stage.size.x > 0
		if not b.visible:
			continue
		var lower: bool = String(item["slot"]) in ["feed", "special", "head"]
		lanes[1 if lower else 0].append({"button": b, "anchor": anchor})
	for lane in 2:
		lanes[lane].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["anchor"] as Vector2).x < (b["anchor"] as Vector2).x)
		var previous := -24.0
		for item in lanes[lane]:
			var anchor: Vector2 = item["anchor"]
			var b: Button = item["button"]
			var x := clampf(maxf(anchor.x - 10.0, previous + 24.0), 2.0, stage.size.x - 22.0)
			b.position = Vector2(x, 5.0 if lane == 0 else stage.size.y - 24.0)
			previous = x
		for i in range(lanes[lane].size() - 2, -1, -1):
			var b: Button = lanes[lane][i]["button"]
			var next: Button = lanes[lane][i + 1]["button"]
			b.position.x = minf(b.position.x, next.position.x - 24.0)
		for item in lanes[lane]:
			var b: Button = item["button"]
			lines.append([item["anchor"], b.position + Vector2(10, 9)])
	_overlay.lines = lines
	_overlay.queue_redraw()
