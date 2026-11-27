extends RefCounted
## Kontrolki kart stanowisk (WORKSHOP_IMMERSION_PLAN.md R0.3): moneta złomu, paski, kafle broni, zaopatrzenia, perków i wyglądu,
## podgląd postaci. Wydzielone z workshop_ui.gd bez zmian; panel trzyma do nich aliasy (`const Tile := Widgets.Tile`), więc widoki
## stanowisk i testy sięgają po nie jak dawniej (`ui.Tile`).

const UiTheme := preload("res://scripts/ui_theme.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Char3D := preload("res://scripts/char3d.gd")
const GOLD := Color(0.95, 0.8, 0.4)

## Moneta złomu (8×8).
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

## Trzy kwadraciki poziomu ulepszeń.
class TierBar extends Control:
	var level := 0                ## odblokowane części broni
	var total := 3                ## wszystkie części broni (parts.gd)
	var maxed := false
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 7)
	func _draw() -> void:
		for i in total:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < level:
				var fc := Color(0.45, 1.0, 0.55) if maxed else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(UiTheme.BONE_DIM, 0.8), false)
			else:
				draw_rect(r, Color(UiTheme.BONE_DIM, 0.8), false, 1.0)

## Pasek na papierowej karcie (stan broni, zużycie części): ślad, wypełnienie i opcjonalna kreska granicy (np. do ilu czyszczenie przywróci stan).
class PaperBar extends Control:
	var frac := 0.0
	var cap := -1.0
	var col := UiTheme.INK
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(60, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PAPER_SEL)
		draw_rect(Rect2(0, 0, roundf(size.x * clampf(frac, 0.0, 1.0)), size.y), col)
		if cap >= 0.0:
			var x := clampf(size.x * cap, 1.0, size.x - 1.0)
			draw_rect(Rect2(x - 0.75, -2.0, 1.5, size.y + 4.0), UiTheme.INK_COST)

## Kropka „nowe” (perk właśnie odblokowany, część, której gracz jeszcze nie oglądał) — kolor lampy z ciemnym obrysem.
class NewDot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(7, 7)
		size = Vector2(7, 7)
	func _draw() -> void:
		draw_circle(Vector2(3.5, 3.5), 3.5, Color(0, 0, 0, 0.6))
		draw_circle(Vector2(3.5, 3.5), 2.6, UiTheme.ACCENT)

## Wspólny kafel stanowisk (bronie, zaopatrzenie, perki, wygląd): miniatura po lewej, nazwa, jedna linia stanu (albo cena z monetą)
## i najwyżej jeden wskaźnik z kropek przy prawej krawędzi — zawsze z podpisem w linii stanu albo z podpowiedzią.
class CardTile extends Button:
	var icon_node: Control
	var name_label: Label
	var state_label: Label
	var coin: Coin
	var price_label: Label
	var bar: Control
	var _new_dot: NewDot
	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		toggle_mode = false
		custom_minimum_size = Vector2(150.0, 46.0)
	var lit := false
	var box_normal: StyleBox              ## własne tło kafla (pudełko na półce, przegroda skrzyni); null — kafel stanowiska
	var box_lit: StyleBox
	## Światło jako kursor (STATION_CARDS_PLAN.md §5): wybrany kafel stoi w snopie lampy, reszta jest przygaszona — miniatura ciemnieje,
	## nazwa i cena zostają czytelne. Bez pomarańczowej ramki.
	func set_lit(on: bool) -> void:
		lit = on
		var sbox: StyleBox = (box_lit if on else box_normal) if box_normal != null else UiTheme.tile_box("selected" if on else "normal")
		for st in ["normal", "pressed", "focus"]:
			add_theme_stylebox_override(st, sbox)
		if icon_node != null:
			icon_node.self_modulate = Color.WHITE if on else Color(0.6, 0.58, 0.55)
		queue_redraw()
	func _draw() -> void:
		if lit:
			draw_texture_rect(UiTheme.lamp_pool(), Rect2(Vector2(-size.x * 0.12, -size.y * 0.55), Vector2(size.x * 0.75, size.y * 1.9)), false)
	## Kropka „nowe” w prawym górnym rogu kafla.
	func set_new(on: bool) -> void:
		if on and _new_dot == null:
			_new_dot = NewDot.new()
			_new_dot.position = Vector2(custom_minimum_size.x - 11.0, 4.0)
			add_child(_new_dot)
		if _new_dot != null:
			_new_dot.visible = on
	## Kropki wskaźnika przy prawej krawędzi, w linii stanu (szerokość z liczby kropek).
	func place_bar() -> void:
		if bar == null:
			return
		var n := int(bar.get("maxn")) if bar.get("maxn") != null else int(bar.get("total"))
		var w := maxf(7.0, float(n) * 9.0 - 2.0)
		bar.custom_minimum_size.x = w
		bar.position = Vector2(custom_minimum_size.x - 6.0 - w, custom_minimum_size.y - 19.0)

## Kafel broni w siatce stanowiska: stan zależny od stanowiska (stan techniczny, ostrze, części) albo miejsce zakupu.
class Tile extends CardTile:
	var weapon := 0
	var marks: ServiceMarks

## Stół konserwacji, kafel broni: dwie ikonki części eksploatacyjnych przy prawej krawędzi — lufa (rura z wylotem) i sprężyny (zygzak).
## Stan 0 — ukryta, 1 — do wymiany (złoto), 2 — pilna (czerwień). Same wymiany: stan czyszczenia mówi linia STAN.
class ServiceMarks extends Control:
	var barrel := 0
	var springs := 0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(30, 9)
		size = custom_minimum_size
	func _col(state: int) -> Color:
		return UiTheme.DANGER if state >= 2 else Color(0.95, 0.8, 0.4)          # złoto jak GOLD panelu
	func _draw() -> void:
		if barrel > 0:
			var c := _col(barrel)
			draw_rect(Rect2(0, 3, 11, 3), c)                          # rura lufy
			draw_rect(Rect2(10, 2, 2, 5), c)                          # wylot
		if springs > 0:
			var c2 := _col(springs)
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2(17.0 + i * 2.0, 1.0 if i % 2 == 0 else 8.0))
			draw_polyline(pts, c2, 1.5)

## Kropki zapasu drużyny: `have` wypełnionych z `maxn` (jak kwadraciki poziomu ulepszeń broni).
class StockBar extends Control:
	var have := 0
	var maxn := 3
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(36, 7)
	func _draw() -> void:
		for i in maxn:
			var r := Rect2(float(i) * 9.0, 0, 7, 7)
			if i < have:
				var fc := Color(0.45, 1.0, 0.55) if have >= maxn else Color(1.0, 0.72, 0.28)
				if UiTheme.hd_on():
					UiTheme.pill(self, r, fc, true)
				else:
					draw_rect(r, fc)
			elif UiTheme.hd_on():
				UiTheme.pill(self, r, Color(UiTheme.BONE_DIM, 0.8), false)
			else:
				draw_rect(r, Color(UiTheme.BONE_DIM, 0.8), false, 1.0)

## Pasek poziomu profilu: wypełnienie = postęp XP w bieżącym poziomie.
class LevelBar extends Control:
	var frac := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 7)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	func _draw() -> void:
		if UiTheme.hd_on():
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9), true)
			if frac > 0.0:
				UiTheme.pill(self, Rect2(1, 1, maxf(size.y - 2.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0), true)
			UiTheme.pill(self, Rect2(Vector2.ZERO, size), Color(UiTheme.BONE_DIM, 0.8), false)
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.BONE_DIM, 0.8), false, 1.0)
		draw_rect(Rect2(1, 1, maxf(0.0, (size.x - 2.0) * frac), size.y - 2.0), Color(0.55, 0.8, 1.0))

## Kafel perku w siatce: miniatura + nazwa + stan (poziom odblokowania / założony / dostępny).
## Podgląd postaci z arkusza HD (256×384 na klatkę): animowany (bieg/idle) w kafelku i w szczegółach zakładki LOOK. Arkusz ładowany leniwie (z mipmapami).
class LookView extends Control:
	var code := 0
	var anim := "idle"
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func set_code(c: int) -> void:
		if c != code:
			code = c
			queue_redraw()

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var sheet := Look.sheet(code)
		if not Sprites.has(sheet):
			return
		var man: Dictionary = Sprites.manifest()["sheets"][sheet]
		var an: Dictionary = man["anims"].get(anim, man["anims"]["idle"])
		var fr: Array = man["frame"]
		var frame := int(_t * float(an["fps"])) % maxi(1, int(an["frames"]))
		var tex := Sprites.mip_texture(Sprites.DIR + sheet + ".png")
		if tex == null:
			return
		var s := minf(size.x / float(fr[0]), size.y / float(fr[1]))
		var w := Vector2(float(fr[0]), float(fr[1])) * s
		draw_texture_rect_region(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), Rect2(frame * fr[0], int(an["row"]) * fr[1], fr[0], fr[1]))

## Podgląd postaci 3D na żywo (gdy gra używa modeli 3D): ten sam render co w misji, ale w pełnej jakości (MSAA, cienie, rim, `ss` do 16)
## i na stole obrotowym — widać plecak, kieszenie, szwy i twarz. Z zakładką LOOK w warsztacie i (później) z lobby.
class Look3DView extends Control:
	var code := 0
	var _c3d: Node2D
	var _holder: Node2D
	var _t := 0.0
	var _name := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		custom_minimum_size = Vector2(0, 190)

	func _ready() -> void:
		_holder = Node2D.new()
		add_child(_holder)
		resized.connect(_layout)
		_layout()

	## Postać (22 j. świata) zajmuje ~92% wysokości kontrolki; `ss` renderu dobrany do rozmiaru na ekranie (tekstura ≥ 1 px na piksel).
	func _layout() -> void:
		if _holder == null:
			return
		var k := size.y * 0.92 / 22.0
		_holder.scale = Vector2(k, k)
		_holder.position = Vector2(size.x * 0.5, size.y * 0.97)

	func _want_ss() -> int:
		var px_per_unit := get_global_transform().get_scale().x * float(get_window().size.y) / 360.0
		var k := size.y * 0.92 / 22.0
		return clampi(int(ceil(k * px_per_unit)), 6, 16)

	func set_code(c: int) -> void:
		code = c
		var nm := Char3D.char_name_for(Look.gender_id(c), Look.outfit_id(c))
		if _c3d == null:
			_c3d = Char3D.new()
			_c3d.preview = true
			_c3d.preview_ss = _want_ss()
			_holder.add_child(_c3d)
			if not _c3d.setup(nm):
				_c3d.queue_free()
				_c3d = null
				return
			_name = nm
		elif nm != _name:
			_c3d.set_look(nm)
			_name = nm
		_c3d.set_palette(Look.palette_of(c))

	func _process(delta: float) -> void:
		if _c3d == null or not is_visible_in_tree():
			return
		_t += delta
		_c3d.set_view_yaw(fmod(_t * 28.0, 360.0))
		_c3d.update(delta, "idle", 1.0, Vector2(1.0, 0.0), 0.0, true, Color.WHITE)

## Kafel stroju (wyższy — postać na całą wysokość).
## Miniatura stroju z renderu modelu 3D (tools/bake_look_portraits.gd → art/portraits/look_<płeć>_<strój>.png), stopami na dole kafla.
class LookPortrait extends Control:
	var tex: Texture2D
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	func set_code(c: int) -> void:
		var path := "res://art/portraits/look_%s_%s.png" % [Look.gender_id(c), Look.outfit_id(c)]
		tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
		queue_redraw()
	func _draw() -> void:
		if tex == null:
			return
		var ts := tex.get_size()
		var s := minf(size.x / ts.x, size.y / ts.y)
		var w := ts * s
		draw_texture_rect(tex, Rect2(Vector2((size.x - w.x) * 0.5, size.y - w.y), w), false)

## Kafel stroju (wyższy — postać na całą wysokość).
class LookTile extends CardTile:
	var code := 0
	var view: Control

## Kafel perku: stan (założony / dostępny / poziom odblokowania).
class PerkTile extends CardTile:
	var perk := ""

## Kafel zaopatrzenia: cena z monetą w linii stanu, kropki = zapas drużyny.
class SupplyTile extends CardTile:
	var kind := ""

## Tło pod kartą stanowiska (WORKSHOP_IMMERSION_PLAN.md R1.3): zamiast jednolitej zasłony 0,65 lekkie przyciemnienie i winieta, żeby
## w wolnym pasie było widać stół w Kryjówce (kamera świata najeżdża na niego, view3d.gd). Ciemniej przy krawędziach ekranu i przy
## brzegu karty (karta odcina się od sceny), środek wolnego pasa najjaśniejszy. `card` — prostokąt karty w układzie tego węzła;
## `full` — stara zasłona (ława ARMS zajmuje cały ekran, nie ma wolnego pasa). Łapie mysz, żeby kliknięcie obok karty nie szło do gry.
class StationScrim extends Control:
	const DIM := 0.1                     ## przyciemnienie całości (dawniej 0,65)
	const EDGE := 0.4                   ## krycie winiety przy krawędzi ekranu i przy brzegu karty
	const FULL := 0.65                   ## zasłona bez wolnego pasa
	var card := Rect2()
	var full := true
	var tint := Color(0.015, 0.018, 0.014)
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _band(r: Rect2, c0: Color, c1: Color, horizontal: bool) -> void:
		var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var cols := PackedColorArray([c0, c1, c1, c0]) if horizontal else PackedColorArray([c0, c0, c1, c1])
		draw_polygon(pts, cols)
	func _draw() -> void:
		if full:
			draw_rect(Rect2(Vector2.ZERO, size), Color(tint, FULL))
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(tint, DIM))
		var dark := Color(tint, EDGE)
		var clear := Color(tint, 0.0)
		var ew := size.x * 0.06
		var eh := size.y * 0.1
		_band(Rect2(0, 0, size.x, eh), dark, clear, false)
		_band(Rect2(0, size.y - eh, size.x, eh), clear, dark, false)
		var card_right := card.get_center().x > size.x * 0.5
		if card_right:                                            # wolny pas po lewej: ciemno przy lewej krawędzi i przy karcie
			_band(Rect2(0, 0, ew, size.y), dark, clear, true)
			_band(Rect2(card.position.x - ew * 0.6, 0, ew * 0.6, size.y), clear, dark, true)
		else:
			_band(Rect2(size.x - ew, 0, ew, size.y), clear, dark, true)
			_band(Rect2(card.end.x, 0, ew * 0.6, size.y), dark, clear, true)
