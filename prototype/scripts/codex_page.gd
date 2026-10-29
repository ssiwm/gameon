extends HBoxContainer
## Strona kodeksu w menu pauzy: lista pozycji po lewej (z nagłówkami grup), szczegóły po prawej (portret, statystyki, paski porównawcze
## broni, opis, wskazówka). Dane dostarcza codex.gd; ten sam widok służy bestiariuszowi, broniom, sprzętowi i perkom.
## Bestiariusz z odkrywaniem (od 1.7.407): wpis wroga, którego gracz jeszcze nie spotkał, jest sylwetką z „???” (Codex.beast_view).

const UiTheme := preload("res://scripts/ui_theme.gd")
const Portrait := preload("res://scripts/codex_portrait.gd")
const Codex := preload("res://scripts/codex.gd")
const Actions := preload("res://scripts/actions.gd")

const LIST_W := 128.0
const DETAIL_W := 240.0                    ## najmniejsza szerokość szczegółów; rozciągają się na resztę strony
const PORTRAIT_H := 84.0
const THUMB_W := 34.0
const THUMB_H := 20.0
const BAR_LABEL_W := 52.0
const BAR_VALUE_W := 58.0

## Pasek porównawczy: wypełnienie = ta broń względem najlepszej w arsenale, kreska w kolorze lampy = broń przy sobie z tego samego slotu.
class StatBar extends Control:
	var frac := 0.0
	var mark := -1.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(60, 5)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(0, 0, roundf(size.x * frac), size.y), UiTheme.TEXT)
		if mark >= 0.0:
			var x := clampf(size.x * mark, 1.0, size.x - 1.0)
			draw_rect(Rect2(x - 0.75, -2.0, 1.5, size.y + 4.0), UiTheme.ACCENT)

var _entries: Array = []
var _buttons: Array[Button] = []
var _thumbs: Array = []                    ## miniatury przycisków (zakryte wpisy bestiariusza zmieniają się po spotkaniu)
var _portrait: Portrait
var _title: Label
var _tag: Label
var _stats: GridContainer
var _bars: VBoxContainer                   ## paski porównawcze broni (Codex.weapon_bars)
var _text: Label
var _tip: Label
var _access: Label
var _tiers: VBoxContainer                  ## lista ulepszeń broni (3 poziomy: zainstalowany / następny / dalszy)
var _sel := -1

func setup(entries: Array) -> void:
	_entries = entries
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(LIST_W + DETAIL_W + 8.0, 0)
	# lista
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ""
	for i in entries.size():
		var g := String(entries[i].get("group", ""))
		if g != group:
			group = g
			list.add_child(_group_header(g, i == 0))
		var b := Button.new()
		b.text = entries[i]["title"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.focus_entered.connect(select.bind(i))      # nawigacja fokusem (pad / klawiatura) od razu pokazuje wpis
		b.add_theme_font_size_override("font_size", 8)
		b.custom_minimum_size = Vector2(0, THUMB_H + 2.0)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBox = get_theme_stylebox(state, "Button").duplicate()
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			sb.content_margin_left = THUMB_W + 8.0           # miejsce na miniaturę
			b.add_theme_stylebox_override(state, sb)
		var th := Portrait.new()
		th.thumb = true
		th.position = Vector2(2, 1)
		th.size = Vector2(THUMB_W, THUMB_H)
		b.add_child(th)
		b.pressed.connect(select.bind(i))
		list.add_child(b)
		_buttons.append(b)
		_thumbs.append(th)
	_refresh_list()
	# szczegóły
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 3)
	# szczegóły mogą być wyższe niż strona (portret + statystyki + opis + lista ulepszeń) — przewijane, strona ma stałą wysokość
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dscroll.custom_minimum_size = Vector2(DETAIL_W + 8.0, 0)
	dscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(dscroll)
	dscroll.add_child(detail)
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(0, PORTRAIT_H)
	detail.add_child(_portrait)
	_title = UiTheme.label("", 14, UiTheme.ACCENT)
	detail.add_child(_title)
	_tag = UiTheme.label("", 8, UiTheme.MUTED)
	detail.add_child(_tag)
	_stats = GridContainer.new()
	_stats.columns = 4
	_stats.add_theme_constant_override("h_separation", 8)
	_stats.add_theme_constant_override("v_separation", 1)
	detail.add_child(_stats)
	_bars = VBoxContainer.new()
	_bars.add_theme_constant_override("separation", 2)
	detail.add_child(_bars)
	_text = UiTheme.label("", 8, UiTheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_text)
	_tip = UiTheme.label("", 8, UiTheme.ACCENT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_tip)
	_access = UiTheme.label("", 8, UiTheme.DANGER)
	_access.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_access)
	_tiers = VBoxContainer.new()
	_tiers.add_theme_constant_override("separation", 1)
	detail.add_child(_tiers)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh_list()                               # nowe spotkania od ostatniego otwarcia odsłaniają wpisy
			if _sel >= 0:
				select(_sel))                             # po zakupie w warsztacie poziomy i statystyki się zmieniły
	select(0)

## Nagłówek grupy na liście (np. ZWYKLI / ELITY / BOSSOWIE, BROŃ GŁÓWNA / BOCZNA / BIAŁA) — nie bierze fokusu.
func _group_header(g: String, first: bool) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 0 if first else 5)
	m.add_theme_constant_override("margin_left", 2)
	m.add_child(UiTheme.label(tr(g), 7, UiTheme.MUTED))
	return m

## Wpis tak, jak go widzi gracz teraz: świeże statystyki broni i perków, zakryty albo odsłonięty wpis bestiariusza.
func _view(i: int) -> Dictionary:
	var e: Dictionary = _entries[i]
	if e.has("weapon_id"):
		return Codex.weapon_entry(int(e["weapon_id"]))          # świeże statystyki / poziomy ulepszeń
	if e.has("perk_id"):
		return Codex.perk_entry(String(e["perk_id"]))           # świeży status perku (poziom, założone sloty)
	return Codex.beast_view(e)

func _refresh_list() -> void:
	for i in _buttons.size():
		var e := Codex.beast_view(_entries[i])
		var id := String(_entries[i].get("beast", ""))
		# nowy wpis — kropka do pierwszego obejrzenia; tr() przed sklejeniem, inaczej przycisk nie znajduje klucza i zostaje po angielsku
		_buttons[i].text = tr(String(e["title"])) + ("  •" if id != "" and Profile.is_new("beast:" + id) else "")
		(_thumbs[i] as Portrait).show_spec(e["portrait"], e["accent"])

func select(i: int) -> void:
	if i < 0 or i >= _entries.size():
		return
	_sel = i
	for j in _buttons.size():
		_buttons[j].set_pressed_no_signal(j == i)
	var e := _view(i)
	var beast := String(_entries[i].get("beast", ""))
	if beast != "" and Profile.is_new("beast:" + beast):
		Profile.mark_seen("beast:" + beast)
		_buttons[i].text = String(e["title"])
	_portrait.show_spec(e["portrait"], e["accent"])
	_title.text = e["title"]
	_tag.text = e["tag"]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	for st in e["stats"]:
		_stats.add_child(UiTheme.label(st[0], 8, UiTheme.MUTED))
		_stats.add_child(UiTheme.label(UiTheme.num_text(tr(String(st[1]))), 8, UiTheme.TEXT))
	_fill_bars(e)
	_text.text = Actions.fmt(tr(e["text"]))                  # klawisze w opisach to znaczniki {akcja} — po przypisaniu gracza
	_tip.text = tr("TIP  ") + Actions.fmt(tr(e["tip"])) if String(e["tip"]) != "" else ""
	_tip.visible = _tip.text != ""
	_access.text = String(e.get("access", ""))
	_access.visible = _access.text != ""
	for c in _tiers.get_children():
		_tiers.remove_child(c)
		c.queue_free()
	var tiers: Array = e.get("tiers", [])
	if not tiers.is_empty():
		_tiers.add_child(UiTheme.label("PARTS", 8, UiTheme.MUTED))
		for t in tiers:
			var st := int(t["state"])
			var col: Color = UiTheme.OK if st == 0 else (Color(0.95, 0.8, 0.4) if st == 1 else UiTheme.MUTED)
			var tail := tr("fitted") if st == 0 else (tr("owned") if st == 1 else tr("%d scrap") % int(t["cost"]))
			var l := UiTheme.label("%s  —  %s   [%s]" % [t["head"], t["desc"], tail], 8, col)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_tiers.add_child(l)

## Paski porównawcze karty broni: ta broń (z częściami gracza) na tle najlepszej w arsenale i kreska broni przy sobie z tego samego slotu.
func _fill_bars(e: Dictionary) -> void:
	for c in _bars.get_children():
		_bars.remove_child(c)
		c.queue_free()
	if not e.has("weapon_id"):
		return
	var id := int(e["weapon_id"])
	var d: RefCounted = Codex.Weapons.def_build(id, Codex.Weapons.build_of(0, Profile.fit_code(id)))
	var carried: RefCounted = _carried_same_slot(id)
	for row in Codex.weapon_bars(d, carried):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var l := UiTheme.label(tr(String(row[0])), 7, UiTheme.MUTED)
		l.custom_minimum_size.x = BAR_LABEL_W
		h.add_child(l)
		var bar := StatBar.new()
		bar.frac = float(row[1])
		bar.mark = float(row[3])
		h.add_child(bar)
		var v := UiTheme.label(UiTheme.num_text(String(row[2])), 7, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size.x = BAR_VALUE_W
		h.add_child(v)
		_bars.add_child(h)
	if carried != null:
		_bars.add_child(UiTheme.label(tr("Orange mark: your %s") % String(carried.name), 7, UiTheme.ACCENT))

## Broń lokalnego gracza z tego samego slotu co `id` (z jego częściami) — do porównania na paskach; null, gdy brak albo to ta sama broń.
func _carried_same_slot(id: int) -> RefCounted:
	if not is_inside_tree():
		return null                                        # strona budowana przed wejściem menu do drzewa
	var slot: int = Codex.Weapons.base_def(id).slot
	for p in get_tree().get_nodes_in_group("players"):
		if p.is_bot or not p.is_multiplayer_authority() or p.get("weapons") == null:
			continue
		var wc: Node = p.weapons
		var owned: Array = Array(wc.loadout) + [int(wc.melee_id)]
		if owned.has(id):
			return null                                     # oglądana broń jest przy sobie: kreska pokazywałaby ją samą
		for w in owned:
			if Codex.Weapons.is_valid(int(w)) and Codex.Weapons.base_def(int(w)).slot == slot:
				return wc.def_of(int(w))
	return null
