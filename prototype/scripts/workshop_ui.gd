extends Control
const Controller := preload("res://scripts/weapon_controller.gd")
## Wspólny panel siedmiu stanowisk: broń i części, konserwacja, prasa, pirotechnika, pracownia, tokarka oraz szafki.
## Lista broni odpowiada operacjom stanowiska; szczegóły porównują bieżący montaż z podglądem i pokazują pracę drużyny.
## Odblokowania i złom są wspólne, montaż prywatny; zakupy i dostawy rozstrzyga serwer (scrap.gd).
## Otwiera go workshop.gd ([E] przy ławie). Na czas panelu akcje gry są wycięte z InputMap (Settings.block_game_input), więc panel
## czyta własne akcje menu z rejestru (actions.gd: menu_left/right/up/down, menu_accept, menu_back, menu_tab, menu_slot_1/2 —
## klawiatura i D-pad / A / B / RB). Mysz: kafel wybiera, przycisk kupuje.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Codex := preload("res://scripts/codex.gd")
const Parts := preload("res://scripts/parts.gd")
const Throwables := preload("res://scripts/throwables.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const PerkIcon := preload("res://scripts/perk_icon.gd")
const Perks := preload("res://scripts/perks.gd")
const GunIcon := preload("res://scripts/gun_icon.gd")
const GunStage := preload("res://scripts/gun_stage.gd")
const GunsmithPanel := preload("res://scripts/gunsmith_panel.gd")
const Look := preload("res://scripts/look.gd")
const Sprites := preload("res://scripts/sprites.gd")
const Char3D := preload("res://scripts/char3d.gd")
const Actions := preload("res://scripts/actions.gd")
const Ammo := preload("res://scripts/ammo.gd")
const WeaponDefinition := preload("res://scripts/weapon_def.gd")
const StationKit := preload("res://scripts/station_kit.gd")
const StationNoise := preload("res://scripts/station_noise.gd")
const VuMeter := preload("res://scripts/vu_meter.gd")
const SupplyArt := preload("res://scripts/station_supply_art.gd")
const NotePaletteRef := preload("res://scripts/note_palette.gd")
const SupplyView := preload("res://scripts/stations/supply_view.gd")
const ServiceView := preload("res://scripts/stations/service_view.gd")
const LabView := preload("res://scripts/stations/lab_view.gd")
const LockerView := preload("res://scripts/stations/locker_view.gd")
const ServiceArt := preload("res://scripts/station_service_art.gd")
const LabArt := preload("res://scripts/station_lab_art.gd")

const GOLD := Color(0.95, 0.8, 0.4)
const COLS := 2
const TILE_W := 150.0
const TILE_H := 46.0
const DETAIL_W := 270.0
## Dodatkowe pola zmieniane przez części, poza podstawową kartą. Jednostki symulacji: 16 px = 1 m.
const PART_METRICS := {
	"ammo_per_shot": ["Ammo per shot", "%d", 1.0], "arc_deg": ["Swing half arc", "%.1f°", 1.0],
	"arm_dist": ["Arming distance", "%.2f m", 1.0 / 16.0], "auto": ["Automatic fire", "bool", 1.0],
	"blast_damage": ["Blast damage", "%.1f", 1.0], "blast_radius": ["Blast radius", "%.2f m", 1.0 / 16.0],
	"charge_time": ["Charge time", "%.2f s", 1.0], "cluster": ["Cluster bomblets", "%d", 1.0],
	"execute_frac": ["Finisher threshold", "%.0f%%", 100.0], "falloff_start": ["Damage falloff starts", "%.2f m", 1.0 / 16.0],
	"flash_light": ["Flash light", "%.2f", 1.0], "flash_size": ["Flash radius", "%.2f m", 1.0 / 16.0],
	"homing": ["Tracking turn rate", "%.1f°/s", 180.0 / PI], "homing_cone": ["Acquisition cone", "%.1f°", 1.0],
	"homing_range": ["Acquisition range", "%.2f m", 1.0 / 16.0], "ignite": ["Burn duration", "%.2f s", 1.0],
	"knock": ["Impact push speed", "%.2f m/s", 1.0 / 16.0], "patch_every": ["Fire patch interval", "%.2f s", 1.0],
	"patch_life": ["Fire patch duration", "%.2f s", 1.0], "pull": ["Pull speed", "%.2f m/s", 1.0 / 16.0],
	"shake": ["Camera shake", "%.2f", 1.0], "speed": ["Projectile speed", "%.2f m/s", 1.0 / 16.0],
	"stun": ["Stun duration", "%.2f s", 1.0], "suppressor": ["Suppressor fitted", "bool", 1.0],
	"wall_pierce": ["Wall penetration", "%.2f m", 1.0 / 16.0], "wear": ["Gun wear", "×%.2f", 1.0],
}
## Karta prasy: modyfikatory naboju (ammo.gd) jako porównanie z nabojem zwykłym — [etykieta, kierunek (1: więcej = lepiej), zapis dodawania].
const AMMO_FIELDS := {
	"damage": ["Damage", 1, "num"], "speed": ["Bullet speed", 1, "num"], "pen": ["Penetration", 1, "num"], "armor_pen": ["Armour bypass", 1, "pct"],
	"falloff_start": ["Full-damage range", 1, "m"], "cam_kick": ["Recoil", -1, "num"], "wear": ["Gun wear", -1, "num"], "ignite": ["Sets on fire", 1, "s"],
	"knock": ["Knock-back", 1, "num"], "stun": ["Stun", 1, "s"], "crit_mult": ["Headshot bonus", 1, "num"],
}
## Dźwięk udanej operacji przy stanowisku (obok potwierdzenia UI): [nagranie, liczba wariantów; 0 = jedno bez numeru].
const STATION_SOUNDS := {"bench": ["mech_mag_in", 3], "service": ["mech_bolt_fwd", 3], "press": ["reload_shell", 3], "pyro": ["item_pickup", 0],
	"lab": ["reload_cell", 2], "lathe": ["mech_bolt_back", 2], "locker": ["item_pickup", 0]}
const FUSE_NAMES := ["SHORT", "MID", "LONG"]                 ## „MEDIUM” ma już tłumaczenie żeńskie (jakość efektów) — zapalnik jest męski
## Pracownia i tokarka: droga części broni specjalnej od próbek do montażu.
const LAB_STEPS := ["SAMPLES", "RESEARCH", "SCHEMATIC", "LATHE", "BENCH"]
## Gniazdo nazwane inaczej niż wspólne SLOT_NAMES, bo jego części siedzą gdzie indziej (PELLET-8: ładownica na komorze w gnieździe „stock”).
const SLOT_LABELS := {"srut8:stock": "Carrier"}
## Kolejność siatki: bronie od początku, potem do kupienia za złom, na końcu zablokowane do późniejszych stref.
const LIST := [Weapons.M83, Weapons.SPREAD12, Weapons.P64, Weapons.LR7, Weapons.HKM9, Weapons.SRUT8, Weapons.GNIEW4, Weapons.WIDMO1, Weapons.SOKOL6, Weapons.CIEGNO6, Weapons.MACZETA, Weapons.KILOF]

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

var _open := false
var _page := 0                        ## 0 = ARMS (bronie i ulepszenia), 1 = SUPPLIES (granaty, miny, narzędzia), 2 = PERKS, 3 = LOOK
var _mode := "bench"                  ## „bench" — ława (ARMS, SUPPLIES), „locker" — szafki osobiste (PERKS, LOOK); od 1.7.349, WORKSHOP_PLAN.md W1
## „service" — stół konserwacji (od 1.7.350, W2): zakładka ARMS bez części i zestawów, tylko czyszczenie i części eksploatacyjne broni
## „press" — prasa elaboracyjna (od 1.7.354, W4): zakładka SUPPLIES z samą amunicją specjalną, zamówienia zamiast zakupu (Scrap.request_order)
## „pyro" — stół pirotechniczny (od 1.7.355, W4b): granaty, miny, ładunki i naboje 40 mm, klawisze 1 / 2 zmieniają zapalnik (ustawienie drużyny)
## „lab" — pracownia elektroniki i próbek (od 1.7.357, W6a): zakładka ARMS z samymi częściami broni specjalnych do zbadania (Scrap.request_research)
## „lathe" — tokarka i szlifierka (od 1.7.358, W6b): części broni specjalnych ze schematów (Scrap.request_machining) i ostrzenie broni białej
const MODE_PAGES := {"bench": [0, 1], "locker": [2, 3], "service": [0], "press": [1], "pyro": [1], "lab": [0], "lathe": [0]}
const MODE_GROUP := {"bench": "workshop", "locker": "locker_station", "service": "service_bench", "press": "press_bench", "pyro": "pyro_bench", "lab": "lab_bench",
	"lathe": "lathe_bench"}      ## grupa stanowiska: panel zamyka się, gdy gracz od niego odejdzie
const SERVICE_IDS := ["clean", "barrel", "springs"]
var _title: Label
var _sup_sel := 0
var _arms_body: HBoxContainer
var _sup_body: HBoxContainer
var _sup_tiles: Array = []            ## kafle zaopatrzenia (SupplyTile) — kolejność = _supply_kinds()
var _sup_grid: GridContainer          ## ława: siatka narzędzi
var _sup_left: VBoxContainer          ## lewa kolumna zaopatrzenia (siatka / regał / skrzynia)
var _shelves: VBoxContainer           ## prasa: regał, półka na kaliber
var _notch: Control                   ## prasa: ząbek etykiety partii pod wybranym pudełkiem
var _crate: PanelContainer            ## stół pirotechniczny: skrzynia z przegrodami
var _crate_grid: GridContainer
var _lid: PanelContainer              ## ramka karty zaopatrzenia (wieko skrzyni przy pirotechnice)
var _sup_paper: PanelContainer
var _dies: PanelContainer             ## prasa: matryce — miejsca na partie
var _dies_list: VBoxContainer
var _s_main: VBoxContainer            ## karta zaopatrzenia: kolumna główna
var _s_side: VBoxContainer            ## karta zaopatrzenia: druga kolumna (prasa — porównanie i hałas)
var _s_blast: Control                 ## pirotechnika: schemat działania w skali
var _s_cord: Control                  ## pirotechnika: lont o długości czasu zapalnika
var _s_icon: ItemIcon
var _s_title: Label
var _s_tag: Label
var _s_stats: GridContainer
var _s_text: Label
var _s_action: Button
var _sup_note: Label                  ## podpowiedź pod siatką zaopatrzenia ławy: gdzie kupić granaty, miny i amunicję
var _s_fuse: VBoxContainer            ## stół pirotechniczny: przełącznik krótki / średni / długi zapalnik (ustawienie drużyny)
var _s_cmp: VBoxContainer             ## prasa: porównanie naboju z nabojem zwykłym
var _s_queue: VBoxContainer           ## prasa: miejsca na partie (Scrap.PRESS_SLOTS)
var _page_btns: Array[Button] = []
var _look_body: HBoxContainer
var _look_sel := 0
var _look_pal := 0                          ## wybrana paleta kolorów (Look.PALETTES) w zakładce LOOK
var _pal_row: HBoxContainer
var _pal_btns: Array = []
var _look_tiles: Array = []
var _l_view: Control                  ## LookView (arkusz 2D)
var _l_view3: Control                 ## Look3DView (model 3D na żywo) — tworzony przy pierwszym użyciu
var _l_box: VBoxContainer
var _l_title: Label
var _l_tag: Label
var _l_text: Label
var _l_action: Button
var _perk_body: HBoxContainer
var _perk_sel := 0
var _perk_slot := 0
var _perk_tiles: Array = []
var _slot_chips: Array = []           ## [{root, icon, name, sub}] dla dwóch slotów
var _lvl_label: Label
var _lvl_bar: LevelBar
var _xp_label: Label
var _p_icon: PerkIcon
var _p_title: Label
var _p_tag: Label
var _p_stats: GridContainer
var _p_text: Label
var _p_action: Button
var _remembered: Dictionary = {}      ## osobny wybór broni dla każdego stanowiska
var _claiming := false
var _sel := 0
var _opt := 0                         ## kursor części w szczegółach broni (indeks w `_options`): klawisze 1 / 2 albo kliknięcie wiersza
var _clean_w := -1                    ## broń czyszczona teraz przy ławie (-1 — żadna); od 1.7.347 czyszczenie kosztuje czas, nie złom
var _clean_t := 0.0                   ## s od początku czyszczenia
var _clean_total := 0.0               ## s potrzebne na całe czyszczenie (Profile.clean_time w chwili startu)
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _card: PanelContainer
var _wallet: Label
var _tiles: Array = []
var _svc_todo: Label                  ## stół konserwacji: co zrobić z każdą bronią (lewa kolumna pod kaflami)
var _svc_note: Control                ## kartka (SCRAWL) z listą do zrobienia, przypięta taśmą
var _arms_paper: PanelContainer       ## karta szczegółów broni (na stole konserwacji bez papieru — przyrządy na blacie)
var _gauges := {}                     ## stół konserwacji: przyrządy „clean” / „barrel” / „springs” (ServiceArt.Gauge)
var _arms_left: VBoxContainer         ## lewa kolumna zakładki broni (kafle, kartka, rulony schematów, szlifierka)
var _arms_side: VBoxContainer         ## prawa kolumna pracowni / tokarki (słoje i odczyt / zlecenie)
var _arms_detail: VBoxContainer       ## zawartość karty broni (kolejność: akta, scena, tytuł…)
var _cork: Control                    ## pracownia: tablica korkowa z łańcuchem kroków
var _dossier_head: Label              ## pracownia: nagłówek akt Obiektu 86
var _redacted: Control                ## pracownia: linia akt z zaczernieniami
var _jars: Control                    ## pracownia: słoje z próbkami (D2a)
var _jars_cap: Label
var _lab_board: PanelContainer        ## pracownia: tablica PROJEKTY pod kaflami (miejsca badań, schematy, co zostało na każdą broń)
var _lab_board_cap: Label
var _lab_board_rows: VBoxContainer
var _lab_tall := 0.0                  ## pracownia: największa wysokość treści od otwarcia panelu (karta nie skacze przy zmianie broni)
var _printout: PanelContainer         ## pracownia: odczyt części na wydruku (PRINTOUT)
var _printout_head: Label
var _blueprint: Control               ## tokarka: rysunek części z drukarki
var _order: Control                   ## tokarka: zlecenie na szpikulcu (SCRAWL)
var _order_box: VBoxContainer
var _order_stamp: Control
var _grinder: PanelContainer          ## tokarka: szlifierka (ostrze broni białej, iskry w trakcie)
var _grinder_text: Label
var _grinder_bar: ColorRect
var _sparks: Control
var _hold_clean := false              ## czyszczenie trzymane klawiszem: puszczenie przerywa
var _perk_paper: PanelContainer       ## szafka: strona książeczki (SCRAWL) z opisem perka
var _book_stamps: Control             ## szafka: pieczątki poziomów w książeczce
var _book_photo: Control              ## szafka: zdjęcie przyklejone taśmą (portret założonego wyglądu)
var _p_vu: HBoxContainer              ## szafka: VU perka zmieniającego hałas (krzyk)
var _p_vu_meter: VuMeter
var _p_vu_text: Label
var _d_stage: Control                 ## ława 3D: wybrana broń z częściami, część spod kursora świeci i wysuwa się z gniazda (gun_stage.gd)
var _d_title: Label
var _d_tag: Label
var _d_panel: VBoxContainer           ## karta stanowiska: konserwacja — paski stanu i zużycia, pracownia / tokarka — droga części
var _d_stats: GridContainer
var _d_tiers: VBoxContainer
var _d_text: Label
var _action: Button
var _msg: Label
var _hint: RichTextLabel              ## taśma z klawiszami pod kartą (StationKit.tape_text)
var _plate: StationKit.StationPlate   ## tabliczka znamionowa stanowiska w nagłówku (tytuł `_title` w środku)
var _drum: StationKit.DrumCounter     ## licznik złomu z bębnami (`_wallet` zostaje jako ukryta etykieta z kwotą)
var _papers: Array = []               ## karty papierowe (PanelContainer) — pieczątka trafia na widoczną
var _s_vu: HBoxContainer              ## karta zaopatrzenia: VU-metr hałasu z podpisem (§5a)
var _s_vu_meter: VuMeter
var _s_vu_text: Label
var _knock_prev := 0.0                ## d7: poprzednia wartość knock_flash (zbocze = stuknięcie)
var _edge_flash: ColorRect            ## czerwony błysk od strony drzwi D-7
var _knock_label: Label               ## napis dźwięku z kierunkiem (nakładka poza układem karty)
var _msg_t := 0.0
var _bank_shown := -1                 ## kwota w portfelu na ekranie (odlicza do Scrap.bank po zakupie)
var _wallet_tween: Tween
var _workbench: GunsmithPanel
var _legacy_stage: GunStage
var _shade: ColorRect
var _bench_slot := ""
var _session := 0
var _selection_revision := 0
var _pending_part: Dictionary = {}
var _buying := -1

var _v_supply = SupplyView.new(self)          # widok stanowiska (stations/supply_view.gd)
var _v_service = ServiceView.new(self)          # widok stanowiska (stations/service_view.gd)
var _v_lab = LabView.new(self)          # widok stanowiska (stations/lab_view.gd)
var _v_locker = LockerView.new(self)          # widok stanowiska (stations/locker_view.gd)

func _ready() -> void:
	add_to_group("workshop_ui")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = ColorRect.new()
	_shade.color = Color(0.015, 0.018, 0.014, 0.65)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.station_box())
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	_card.add_child(root)
	# nagłówek: tytuł, portfel
	var head := HBoxContainer.new()
	_title = UiTheme.heading("WORKSHOP", 16, UiTheme.TEXT)
	_plate = StationKit.StationPlate.new(_title)
	head.add_child(_plate)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	for pi in 4:
		var pb := Button.new()                                 # zakładki ARMS / SUPPLIES / PERKS / LOOK (Tab przełącza)
		pb.text = ["ARMS", "SUPPLIES", "PERKS", "LOOK"][pi]
		pb.toggle_mode = true
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_font_size_override("font_size", 9)
		pb.pressed.connect(_set_page.bind(pi))
		head.add_child(pb)
		_page_btns.append(pb)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	head.add_child(gap)
	_wallet = UiTheme.label("", 11, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)       # kwota w tekście (ukryta): licznik bębnowy pokazuje ją cyframi
	_wallet.visible = false
	head.add_child(_wallet)
	_drum = StationKit.DrumCounter.new()
	_drum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_drum)
	root.add_child(head)
	root.add_child(_rule())
	# korpus: siatka broni | szczegóły
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	root.add_child(_scroll_body(body))
	_arms_body = body
	_sup_body = _build_supplies()
	root.add_child(_scroll_body(_sup_body))
	_sup_body.get_parent().visible = false
	_sup_body.visible = false
	_perk_body = _build_perks()
	root.add_child(_scroll_body(_perk_body))
	_perk_body.get_parent().visible = false
	_perk_body.visible = false
	_look_body = _build_look()
	root.add_child(_scroll_body(_look_body))
	_look_body.get_parent().visible = false
	_look_body.visible = false
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_arms_left = left
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i in LIST.size():
		var t := _make_tile(int(LIST[i]), i)
		grid.add_child(t)
		_tiles.append(t)
	_svc_todo = UiTheme.label("", 9, UiTheme.MUTED)                   # stół konserwacji: lista „do zrobienia” pod kaflami (puste miejsce przy kilku broniach)
	_svc_todo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_svc_todo.custom_minimum_size.x = COLS * TILE_W - 24.0
	_svc_todo.visible = false
	var scrawl := NotePaletteRef.palette(NotePaletteRef.Note.SCRAWL)
	_svc_todo.add_theme_font_override("font", UiTheme.note_font(NotePaletteRef.Note.SCRAWL))   # kartka odręczna (ST-02): Caveat, atrament kartki
	_svc_todo.add_theme_font_size_override("font_size", UiTheme.note_size(NotePaletteRef.Note.SCRAWL, 10))
	_svc_todo.add_theme_color_override("font_color", scrawl["ink"])
	_svc_todo.add_theme_constant_override("outline_size", 0)
	_svc_note = ServiceArt.Scrawl.new()
	_svc_note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_svc_note.visible = false
	_svc_note.add_child(_svc_todo)
	left.add_child(_svc_note)
	_arms_paper = _paper(_build_detail())
	body.add_child(_arms_paper)
	_build_lab_lathe(left, body)
	_legacy_stage = _d_stage as GunStage
	_workbench = GunsmithPanel.new()
	_workbench.custom_minimum_size = Vector2(606, 240)
	root.add_child(_workbench)
	_workbench.visible = false
	_workbench.weapon_selected.connect(_select)
	_workbench.slot_selected.connect(_pick_slot)
	_workbench.option_selected.connect(_pick_opt)
	_workbench.inspect_requested.connect(_inspect)
	_workbench.save_requested.connect(_save_current_preset)
	# Główna akcja zawsze pod ręką; przewija się treść, nie przycisk zakupu/montażu/odbioru.
	_action.reparent(root)
	_s_action.reparent(root)
	_s_action.visible = false
	for extra in [_p_action, _l_action]:
		extra.reparent(root)
		extra.visible = false
	root.add_child(_rule())
	_msg = UiTheme.label("", 9, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_msg)
	var tape := PanelContainer.new()                     # taśma maskująca z klawiszami (§5): nazwy z rejestru akcji, klawisze w ramkach
	tape.add_theme_stylebox_override("panel", StationKit.tape_box())
	tape.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tape)
	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	_hint.scroll_active = false
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 606
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("normal_font_size", 8)
	_hint.add_theme_color_override("default_color", UiTheme.TEXT.darkened(0.08))
	_hint.text = StationKit.tape_text(_controls_hint())
	tape.add_child(_hint)
	_edge_flash = ColorRect.new()                        # pukanie do D-7: czerwony błysk od strony drzwi
	_edge_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_flash.color = Color(UiTheme.DANGER, 0.0)
	add_child(_edge_flash)
	_knock_label = UiTheme.label("", 12, UiTheme.DANGER)
	_knock_label.modulate.a = 0.0
	add_child(_knock_label)
	Scrap.changed.connect(_refresh)
	Scrap.purchase_result.connect(_on_result)
	Scrap.supply_result.connect(_on_supply_result)
	Scrap.part_result.connect(_on_part_result)
	Scrap.service_result.connect(_on_service_result)
	Scrap.order_result.connect(_on_order_result)
	Scrap.research_result.connect(_on_research_result)
	Scrap.machining_result.connect(_on_machining_result)
	Profile.changed.connect(_refresh)
	Arsenal.stock_changed.connect(_refresh)
	multiplayer.server_disconnected.connect(_connection_lost)
	multiplayer.connection_failed.connect(_connection_lost)

## Zob. stations/supply_view.gd.
func _build_supplies() -> HBoxContainer:
	return _v_supply._build_supplies()

## Zob. stations/supply_view.gd.
func _make_shelf(cal: String) -> Control:
	return _v_supply._make_shelf(cal)

## Zob. stations/supply_view.gd.
func _arrange_supplies() -> void:
	_v_supply._arrange_supplies()

## Zob. stations/supply_view.gd.
func _make_supply_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_supply_tile(kd, idx)

## Zob. stations/supply_view.gd.
func _build_supply_detail() -> Control:
	return _v_supply._build_supply_detail()

## Zob. stations/supply_view.gd.
func _is_press_kind(k: String) -> bool:
	return _v_supply._is_press_kind(k)

## Zob. stations/supply_view.gd.
func _is_pyro_kind(k: String) -> bool:
	return _v_supply._is_pyro_kind(k)

## Zob. stations/supply_view.gd.
func _make_box_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_box_tile(kd, idx)

## Zob. stations/supply_view.gd.
func _make_bay_tile(kd: String, idx: int) -> SupplyTile:
	return _v_supply._make_bay_tile(kd, idx)

## Zob. stations/locker_view.gd.
func _look_code(i: int) -> int:
	return _v_locker._look_code(i)

## Zob. stations/locker_view.gd.
func _build_look() -> HBoxContainer:
	return _v_locker._build_look()

## Zob. stations/locker_view.gd.
func _select_palette(pi: int) -> void:
	_v_locker._select_palette(pi)

## Zob. stations/locker_view.gd.
func _select_look(i: int) -> void:
	_v_locker._select_look(i)

## Zob. stations/locker_view.gd.
func _act_look() -> void:
	_v_locker._act_look()

## Zob. stations/locker_view.gd.
func _refresh_look() -> void:
	_v_locker._refresh_look()

## Zob. stations/locker_view.gd.
func _build_perks() -> HBoxContainer:
	return _v_locker._build_perks()

## Zob. stations/locker_view.gd.
func _make_perk_tile(id: String, idx: int) -> PerkTile:
	return _v_locker._make_perk_tile(id, idx)

## Zob. stations/locker_view.gd.
func _make_slot_chip(si: int) -> Control:
	return _v_locker._make_slot_chip(si)

## Zob. stations/locker_view.gd.
func _build_perk_detail() -> Control:
	return _v_locker._build_perk_detail()

## Zob. stations/locker_view.gd.
func _select_perk(i: int) -> void:
	_v_locker._select_perk(i)

## Zob. stations/locker_view.gd.
func _perk_slot_of(id: String) -> int:
	return _v_locker._perk_slot_of(id)

## Zob. stations/locker_view.gd.
func _act_perk() -> void:
	_v_locker._act_perk()

## Zob. stations/locker_view.gd.
func _refresh_perks() -> void:
	_v_locker._refresh_perks()

func _select_supply(i: int) -> void:
	if i != _sup_sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_sup_sel = i
	_refresh()

func _buy_selected_supply() -> void:
	var k := String(_supply_kinds()[_sup_sel])
	if int(Scrap.deliveries.get(k, 0)) > 0:
		_claiming = true
		Scrap.request_claim(k)
	elif Throwables.is_ammo(k):
		_claiming = false
		Scrap.request_order(k)                                   # amunicja: zamówienie w prasie (gotowe po misji)
	else:
		Scrap.request_buy_supply(k)

## Indeksy kafli zaopatrzenia (w _supply_kinds) widoczne w tym trybie: ława — przedmioty, prasa — amunicja specjalna.
func _sup_list() -> Array:
	var out: Array = []
	var kinds := _supply_kinds()
	for i in kinds.size():
		if _sup_in_mode(String(kinds[i])):
			out.append(i)
	return out

## Czy rodzaj `k` należy do stanowiska: prasa — amunicja specjalna bez 40 mm, pirotechnika — granaty, miny, ładunki i 40 mm, ława — narzędzia.
func _sup_in_mode(k: String) -> bool:
	var m := String(Throwables.KINDS[k]["mode"])
	var forty := Throwables.is_ammo(k) and String(Ammo.from_kind(k).get("cal", "")) == "40mm"
	match _mode:
		"press":
			return Throwables.is_ammo(k) and not forty
		"pyro":
			return m == "throw" or m == "place" or forty
		_:
			return m == "use"

## Zob. stations/supply_view.gd.
func _fill_noise(k: String) -> void:
	_v_supply._fill_noise(k)

## Zob. stations/supply_view.gd.
func _fill_blast(k: String) -> void:
	_v_supply._fill_blast(k)

## Zob. stations/supply_view.gd.
func _step_fuse(d: int) -> void:
	_v_supply._step_fuse(d)

## Zob. stations/supply_view.gd.
func _set_fuse(k: String, ni: int) -> void:
	_v_supply._set_fuse(k, ni)

## Zob. stations/supply_view.gd.
func _fill_fuse(k: String) -> void:
	_v_supply._fill_fuse(k)

## Zob. stations/supply_view.gd.
func _fill_ammo_cmp(k: String) -> void:
	_v_supply._fill_ammo_cmp(k)

## Zob. stations/supply_view.gd.
func _ammo_rows(k: String) -> Array:
	return _v_supply._ammo_rows(k)

## Zob. stations/supply_view.gd.
func _fill_press_queue() -> void:
	_v_supply._fill_press_queue()

## Zob. stations/supply_view.gd.
func _fill_dies() -> void:
	_v_supply._fill_dies()

## Portfel odlicza do nowej kwoty (zakup, zamówienie, odbiór) zamiast skakać i krótko przygasa na czerwono przy wydatku — widać, ile kosztowało.
func _tick_wallet() -> void:
	var target := Scrap.bank
	if _bank_shown < 0 or Settings.reduce_fx:
		_bank_shown = target
		_wallet.text = "%d" % target
		_drum.shown = float(target)
		return
	if target == _bank_shown and (_wallet_tween == null or not _wallet_tween.is_running()):
		return
	if _wallet_tween != null and _wallet_tween.is_running():
		if _wallet_tween.get_meta("to", -1) == target:
			return
		_wallet_tween.kill()
	var from := _bank_shown
	_wallet_tween = create_tween()
	_wallet_tween.set_meta("to", target)
	_wallet_tween.tween_method(func(v: float) -> void:
		_bank_shown = int(round(v))
		_drum.shown = v                                     # bębny obracają się płynnie jak w liczniku mechanicznym
		_wallet.text = "%d" % _bank_shown, float(from), float(target), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

## Udana operacja: potwierdzenie UI, dźwięk stanowiska (magazynek na ławie, łuski przy prasie, ogniwo w pracowni…) i krótki błysk wybranego kafla.
func _success_fx(vol_db := -4.0) -> void:
	Audio.play("ui_confirm", Audio.BUS_UI, vol_db)
	var snd: Array = STATION_SOUNDS.get(_mode, [])
	if not snd.is_empty():
		if int(snd[1]) > 0:
			Audio.play_variant(String(snd[0]), int(snd[1]), Audio.BUS_UI, vol_db - 2.0)
		else:
			Audio.play(String(snd[0]), Audio.BUS_UI, vol_db - 2.0)
	_stamp()
	if Settings.reduce_fx:
		return
	var tile: Control = null
	match _page:
		0:
			tile = _tiles[_sel] if not (_mode == "bench") else null      # ława 3D ma własną animację montażu
		1:
			tile = _sup_tiles[_sup_sel]
		2:
			tile = _perk_tiles[_perk_sel]
		3:
			tile = _look_tiles[_look_sel]
	if tile == null or not tile.is_visible_in_tree():
		return
	tile.modulate = Color(1.55, 1.4, 0.95)
	create_tween().tween_property(tile, "modulate", Color.WHITE, 0.35)

func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## Cena kafla: przedmiot — sklep ławy, amunicja — partia w prasie.
func _sup_price(k: String) -> int:
	return Scrap.press_price(k) if Throwables.is_ammo(k) else Throwables.price_of(k)

func _on_order_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s collected. Remaining delivery: %d rounds.") % [nm, int(Scrap.deliveries.get(kind, 0))] if _claiming else tr("%s ordered — ready after the next mission (%d / %d batches in the press).") % [nm, Scrap.orders.size(), Scrap.PRESS_SLOTS], UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.press_price(kind), UiTheme.DANGER)
		"busy":
			_say(tr("The press is full — %d batches per mission.") % Scrap.PRESS_SLOTS, UiTheme.MUTED)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Rodzaje do kupienia (z ceną) w kolejności karuzeli: przedmioty, potem amunicja specjalna.
func _supply_kinds() -> Array:
	var out: Array = []
	for k in Throwables.SHOP_ORDER:
		if Throwables.price_of(String(k)) > 0:
			out.append(k)
	return out

func _set_page(p: int) -> void:
	if p == _page:
		_page_btns[p].set_pressed_no_signal(true)
		return
	_page = p
	Audio.play("ui_click", Audio.BUS_UI, -12.0, 1.1)
	_refresh()

## Długie porównania i kolejki pozostają dostępne także w bazowej rozdzielczości 640×360.
func _scroll_body(body: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(TILE_W * COLS + DETAIL_W + 50.0, 250.0)        # +14: marginesy papierowej karty
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return scroll

func _make_tile(w: int, idx: int) -> Tile:
	var t := Tile.new()
	t.weapon = w
	var ic := GunIcon.new()
	var d: RefCounted = Weapons.base_def(w)
	ic.plate = true
	ic.k = 0.3
	ic.set_gun(int(d.gun_row), d.tracer_color, Color.WHITE)
	_dress_tile(t, ic, String(d.name))
	_add_bar(t, TierBar.new())
	t.pressed.connect(_select.bind(idx))
	return t

## Wspólna ramka kafla: style stanów, miniatura w polu po lewej, nazwa i (pusta) linia stanu. Wysoki kafel (wygląd) — obie linie wyśrodkowane.
func _dress_tile(t: CardTile, icon: Control, title: String) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(st, UiTheme.tile_box("hover" if st == "hover" else "normal"))
	icon.position = Vector2(4, 5)
	icon.size = Vector2(54, t.custom_minimum_size.y - 10.0)
	t.add_child(icon)
	t.icon_node = icon
	var mid := (t.custom_minimum_size.y - TILE_H) * 0.5
	t.name_label = UiTheme.label(title, 10, UiTheme.TEXT)
	t.name_label.position = Vector2(64, 6.0 + mid)
	t.add_child(t.name_label)
	t.state_label = UiTheme.label("", 8, UiTheme.MUTED)
	t.state_label.position = Vector2(64, 25.0 + mid)
	t.add_child(t.state_label)

## Cena z monetą w linii stanu (zaopatrzenie).
func _add_price(t: CardTile) -> void:
	t.coin = Coin.new()
	t.coin.position = Vector2(64, 26)
	t.add_child(t.coin)
	t.price_label = UiTheme.label("", 10, GOLD)
	t.price_label.position = Vector2(76, 23)
	t.add_child(t.price_label)

## Jedyny wskaźnik kafla: kropki przy prawej krawędzi.
func _add_bar(t: CardTile, bar: Control) -> void:
	t.bar = bar
	t.add_child(bar)
	t.place_bar()

func _build_detail() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_theme_constant_override("separation", 4)
	_arms_detail = v
	_cork = LabArt.CorkChain.new()                        # pracownia (ST-05): tablica korkowa z łańcuchem kroków
	_cork.visible = false
	v.add_child(_cork)
	_dossier_head = UiTheme.mono(UiTheme.ink("", 7, UiTheme.INK_MUTED))       # akta Obiektu 86 (sprzęt bunkra — cyrylica, D1a)
	_dossier_head.visible = false
	v.add_child(_dossier_head)
	_redacted = LabArt.Redacted.new()
	_redacted.color = UiTheme.INK
	_redacted.visible = false
	v.add_child(_redacted)
	_blueprint = LabArt.Blueprint.new()                   # tokarka (ST-06): rysunek części z drukarki zamiast sceny z bronią
	_blueprint.visible = false
	v.add_child(_blueprint)
	_d_stage = GunStage.new()
	_d_stage.custom_minimum_size = Vector2(0, 76)
	v.add_child(_d_stage)
	_d_title = _ink_heading()
	v.add_child(_d_title)
	_d_tag = UiTheme.ink("", 8, UiTheme.INK_MUTED)
	v.add_child(_d_tag)
	_d_panel = VBoxContainer.new()
	_d_panel.add_theme_constant_override("separation", 3)
	v.add_child(_d_panel)
	_d_stats = GridContainer.new()
	_d_stats.columns = 4                                  # parametr | teraz | → po zmianie | korzyść / koszt
	_d_stats.add_theme_constant_override("h_separation", 10)
	_d_stats.add_theme_constant_override("v_separation", 1)
	v.add_child(_d_stats)
	v.add_child(_paper_rule())
	_d_tiers = VBoxContainer.new()
	_d_tiers.add_theme_constant_override("separation", 1)
	v.add_child(_d_tiers)
	_d_text = UiTheme.ink("", 8)
	_d_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_text.custom_minimum_size = Vector2(DETAIL_W, 0)
	v.add_child(_d_text)
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.add_theme_font_size_override("font_size", 10)
	_action.add_theme_color_override("font_disabled_color", UiTheme.BONE_DIM)     # wyłączona akcja niesie podpowiedź („wybierz gniazdo”)
	_action.pressed.connect(_act)
	v.add_child(_action)
	return v

# ---------------------------------------------------------------- otwieranie

func is_open() -> bool:
	return _open

## `mode`: „bench" — ława warsztatu (bronie, części, zaopatrzenie), „locker" — szafki osobiste (perki, wygląd). Zakładki spoza trybu są ukryte.
func open(mode := "bench") -> void:
	if _open:
		return
	_open = true
	visible = true
	_mode = mode if MODE_PAGES.has(mode) else "bench"
	_session += 1
	_lab_tall = 0.0
	_bench_slot = ""
	_title.text = {"locker": tr("LOCKER"), "service": tr("MAINTENANCE"), "press": tr("RELOADING PRESS"), "pyro": tr("PYROTECHNICS"), "lab": tr("LAB"), "lathe": tr("LATHE")}.get(_mode, tr("WORKSHOP"))
	_plate.set_station(_mode)
	_arrange_supplies()
	for pi in _page_btns.size():
		(_page_btns[pi] as Button).visible = (MODE_PAGES[_mode] as Array).has(pi) and (MODE_PAGES[_mode] as Array).size() > 1
	_msg.text = ""
	_hint.text = StationKit.tape_text(_controls_hint())
	_sel = _initial_selection()
	_opt = _first_part_opt()
	_bank_shown = -1                                       # po otwarciu portfel od razu pokazuje stan, odlicza dopiero zmianę
	_page = int((MODE_PAGES[_mode] as Array)[0])
	var allowed := _sup_list()
	if not allowed.has(_sup_sel) and not allowed.is_empty():
		_sup_sel = int(allowed[0])
	Settings.block_game_input(true)
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE            # w grze celownik zastępuje kursor; panel potrzebuje myszy
	Audio.play("ui_click", Audio.BUS_UI, -10.0)
	_refresh()

func close() -> void:
	if not _open:
		return
	_remembered[_mode] = _sel
	_session += 1
	_workbench.stage.cancel_mount()
	_workbench.stage.set_rendering(false)
	_legacy_stage.set_rendering(false)
	_stop_clean()
	_open = false
	visible = false
	Settings.block_game_input(false)
	Input.mouse_mode = _prev_mouse
	Audio.play("ui_click", Audio.BUS_UI, -10.0)

func _process(delta: float) -> void:
	if not _open:
		return
	_msg_t = maxf(0.0, _msg_t - delta)
	if _msg_t <= 0.0:
		_msg.text = ""
	# panel zamyka się, gdy gracz odejdzie od ławy / zginie / misja się zmieni (przerwane czyszczenie trzeba zacząć od nowa)
	var wk := get_tree().get_first_node_in_group(String(MODE_GROUP[_mode]))
	if wk == null or not wk.local_in_range or not NoiseMgr.safe_zone:
		close()
		return
	tick_clean(delta)
	_hub_events()
	var hud := get_parent() as Control
	if hud != null:
		size = hud.size
	# Ława 3D ma stałą skalę ×1,4; pozostałe stanowiska dostają tyle samo, ile zmieści szerokość ekranu (dawniej ×1 — drobny tekst
	# w ~46% szerokości ekranu). Wysokość przewijanej treści liczona już w jednostkach skali, żeby karta nie wyszła poza ekran.
	var immersive := _mode == "bench" and _page == 0
	var card_scale := 1.4 if immersive else clampf((size.x - 48.0) / maxf(1.0, _card.get_combined_minimum_size().x), 1.0, 1.4)
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		var tall := clampf(size.y / card_scale - 156.0, 150.0, 400.0)      # 156: nagłówek z tabliczką, dźwignia, komunikat, taśma, odstępy
		if _mode == "lab" and body == _arms_body:
			_lab_tall = maxf(_lab_tall, body.get_combined_minimum_size().y)
			tall = minf(tall, maxf(150.0, _lab_tall))     # pracownia: karta na wysokość treści (dawniej ~1/4 pustego pasa nad przyciskiem)
		(body.get_parent() as ScrollContainer).custom_minimum_size.y = tall
	var overhead := maxf(118.0, _card.size.y - _workbench.size.y)
	_workbench.custom_minimum_size = Vector2(clampf(size.x / card_scale - 34.0, 606.0, 1050.0), clampf(size.y / card_scale - overhead - 14.0, 190.0, 620.0))
	_card.scale = Vector2.ONE * card_scale
	# Kontener sam się nie kurczy: po wyższej stronie (zaopatrzenie, inne stanowisko) karta ławy ×1,4 wychodziła poza ekran.
	if not _card.size.is_equal_approx(_card.get_combined_minimum_size()):
		_card.reset_size()
	_card.position = ((size - _card.size * card_scale) * 0.5).round()

## Zdarzenia Kryjówki na karcie (STATION_CARDS_PLAN.md §5): stuknięcie zza D-7 — papiery
## drgają, czerwony błysk od strony drzwi i napis dźwięku z kierunkiem. „Reduce effects” wyłącza migotanie, drganie i błysk (napis zostaje).
func _hub_events() -> void:
	# burza: przygasa tylko lampa generatora w świecie (view3d.gd) — karta nie (od 1.7.421: skok jasności całej karty z tekstem
	# co kilka sekund wyglądał jak migotanie ekranu i utrudniał czytanie)
	var d7: Node2D = null
	for n in get_tree().get_nodes_in_group("hub_props"):
		if String(n.get("kind")) == "d7":
			d7 = n as Node2D
			break
	if d7 == null:
		return
	var k := float(d7.get("knock_flash"))
	if k >= 0.95 and _knock_prev < 0.95:
		_on_knock(d7)
	_knock_prev = k

func _on_knock(d7: Node2D) -> void:
	var me: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			me = p
	var left := me != null and d7.global_position.x < me.global_position.x
	if _jars != null and _jars.is_visible_in_tree():
		(_jars as LabArt.Jars).hear(-1.0 if left else 1.0)         # D2a: kształty w słojach zwracają się w stronę stukania
	# napis dźwięku po stronie drzwi, nad kartą — nie zmienia układu karty (wiersz komunikatów zostaje dla wyników operacji)
	_knock_label.text = ("◀  " if left else "") + tr("Knocking behind D-7") + ("" if left else "  ▶")
	_knock_label.reset_size()
	var cr := _card.get_global_rect()
	_knock_label.position = Vector2(cr.position.x + 8.0 if left else cr.end.x - _knock_label.size.x - 8.0, maxf(2.0, cr.position.y - _knock_label.size.y - 2.0))
	_knock_label.modulate.a = 1.0
	var kt := create_tween()
	kt.tween_interval(1.4)
	kt.tween_property(_knock_label, "modulate:a", 0.0, 0.6)
	if Settings.fx_mult() <= 0.0:
		return
	_edge_flash.size = Vector2(size.x * 0.16, size.y)
	_edge_flash.position = Vector2(0.0 if left else size.x - _edge_flash.size.x, 0.0)
	_edge_flash.color = Color(UiTheme.DANGER, 0.22)
	create_tween().tween_property(_edge_flash, "color:a", 0.0, 0.9)
	for p in _papers:
		var pc := p as Control
		if not pc.is_visible_in_tree():
			continue
		pc.pivot_offset = pc.size * Vector2(0.5, 0.0)
		var tw := create_tween()
		for r in [0.9, -0.6, 0.35, 0.0]:
			tw.tween_property(pc, "rotation_degrees", r * (-1.0 if left else 1.0), 0.07)

func _exit_tree() -> void:
	if _open:
		Settings.block_game_input(false)
		Input.mouse_mode = _prev_mouse

# ---------------------------------------------------------------- sterowanie

## Linia sterowania pod panelem: klawisze z rejestru akcji, a gdy jest pad — jego przyciski.
func _controls_hint() -> String:
	var pad := Actions.pad_mode
	var nav := StationKit.KEY_OPEN + ("D-PAD" if pad else Actions.cluster(["menu_up", "menu_left", "menu_down", "menu_right"]).to_upper()) + StationKit.KEY_CLOSE
	if _mode == "bench" and _page == 0:
		return tr("%s weapon · %s slot · %s / %s part · %s fit · %s inspect · %s tabs · %s close") % [
			_cap("menu_up", pad) + "/" + _cap("menu_down", pad), _cap("menu_left", pad) + "/" + _cap("menu_right", pad),
			_cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_inspect", pad),
			_cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "lathe":
		return tr("%s select   ·   %s / %s job   ·   %s machine / sharpen   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "lab":
		return tr("%s select   ·   %s / %s part   ·   %s research   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "press":
		return tr("%s select   ·   %s order a batch   ·   %s close   ·   or click") % [nav, _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "pyro":
		return tr("%s select   ·   %s / %s fuse   ·   %s buy / order   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "service":
		return tr("%s gun   ·   %s instrument   ·   %s hold: clean / replace   ·   %s close   ·   or click") % [
			_cap("menu_up", pad) + " " + _cap("menu_down", pad), _cap("menu_left", pad) + " " + _cap("menu_right", pad), _cap("menu_accept", pad), _cap("menu_back", pad)]
	if _mode == "locker" and _page == 3:
		return tr("%s select   ·   %s wear   ·   %s perks / look   ·   %s close   ·   or click") % [
			nav, _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "bench" and _page == 1:
		return tr("%s select   ·   %s buy   ·   %s arms / supplies   ·   %s close   ·   or click") % [
			nav, _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	if _mode == "locker":
		return tr("%s select   ·   %s / %s perk slot   ·   %s equip   ·   %s perks / look   ·   %s close   ·   or click") % [
			nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]
	return tr("%s select   ·   %s / %s part   ·   %s buy / fit   ·   %s save set   ·   %s arms / supplies   ·   %s close   ·   or click") % [
		nav, _cap("menu_slot_1", pad), _cap("menu_slot_2", pad), _cap("menu_accept", pad), _cap("menu_alt", pad), _cap("menu_tab", pad), _cap("menu_back", pad)]

## Nazwa klawisza oznaczona dla taśmy sterowania (StationKit.tape_text rysuje ją w ramce klawisza).
func _cap(id: String, pad: bool) -> String:
	return StationKit.KEY_OPEN + _menu_key(id, pad) + StationKit.KEY_CLOSE

func _menu_key(id: String, pad: bool) -> String:
	return Actions.text(id, true, Actions.DEV_PAD if pad else Actions.DEV_KEY).to_upper()

## Krok zaznaczenia z akcji menu (strzałki / WASD / D-pad): ±1 w poziomie, ±COLS w pionie, 0 = to nie nawigacja.
func _nav_step(event: InputEvent) -> int:
	if event.is_action_pressed("menu_left"):
		return -1
	if event.is_action_pressed("menu_right"):
		return 1
	if event.is_action_pressed("menu_up"):
		return -COLS
	if event.is_action_pressed("menu_down"):
		return COLS
	return 0

## Następny kafel w kierunku kroku `step` (±1 poziomo, ±COLS pionowo) wg położenia na ekranie: regał prasy ma półki różnej długości,
## skrzynia 4 przegrody w rzędzie, siatka ławy 2 kolumny — światło idzie za fokusem tak, jak kafle stoją. -1, gdy w tę stronę nic nie ma.
func _spatial_step(tiles: Array, vis: Array, cur: int, step: int) -> int:
	if vis.is_empty() or not vis.has(cur):
		return int(vis[0]) if not vis.is_empty() else -1
	var horiz := absi(step) == 1
	var c := (tiles[cur] as Control).get_global_rect().get_center()
	var best := -1
	var best_d := INF
	for i in vis:
		if int(i) == cur:
			continue
		var p := (tiles[int(i)] as Control).get_global_rect().get_center()
		var d := p - c
		var along := d.x if horiz else d.y
		var across := d.y if horiz else d.x
		if signf(along) != signf(float(step)) or absf(along) < 4.0:
			continue
		if horiz and absf(across) > 8.0:
			continue                                       # w poziomie tylko ten sam rząd (półka, rząd przegród)
		var score := absf(along) + absf(across) * 3.0
		if score < best_d:
			best_d = score
			best = int(i)
	if best < 0 and horiz:
		var at := vis.find(cur) + signi(step)                 # koniec rzędu: dalej po kolejności (następna półka)
		best = int(vis[at]) if at >= 0 and at < vis.size() else -1
	return best

func _input(event: InputEvent) -> void:
	if _open and _hold_clean and (event is InputEventKey or event is InputEventJoypadButton) and event.is_action_released("menu_accept"):
		_hold_clean = false
		if _clean_w >= 0:                                  # czynność w czasie trzymana klawiszem: puszczenie przerywa (ST-02)
			_stop_clean()
			_say(tr("Interrupted — hold to finish."), UiTheme.MUTED)
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if not _open or not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("menu_tab") or event.is_action_pressed("menu_tab_prev"):
		var pages: Array = MODE_PAGES[_mode]
		_set_page(int(pages[posmod(pages.find(_page) + (1 if event.is_action_pressed("menu_tab") else -1), pages.size())]))
		get_viewport().set_input_as_handled()
		return
	var step := _nav_step(event)
	var accept := event.is_action_pressed("menu_accept")
	var back := event.is_action_pressed("menu_back")
	if _mode == "bench" and _page == 0:
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
			_move(-1 if event.is_action_pressed("menu_up") else 1)
		elif event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
			_move_slot(-1 if event.is_action_pressed("menu_left") else 1)
		elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
			_move_opt(-1 if event.is_action_pressed("menu_slot_1") else 1)
		elif event.is_action_pressed("menu_inspect"):
			_inspect()
		elif event.is_action_pressed("menu_details"):
			_workbench._toggle_details()
		elif event.is_action_pressed("menu_alt"):
			_save_current_preset()
		elif accept:
			_act()
		elif back:
			close()
	elif _page == 3:
		if step != 0 and _look_sel + step >= 0 and _look_sel + step < Look.GENDERS.size() * Look.OUTFITS.size():
			_look_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_look()
		elif back:
			close()
	elif _page == 2:
		if step != 0 and _perk_sel + step >= 0 and _perk_sel + step < Perks.ORDER.size():
			_perk_sel += step
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
			_perk_slot = 0 if event.is_action_pressed("menu_slot_1") else 1
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif accept:
			_act_perk()
		elif back:
			close()
	elif _page == 1:
		var nxt := _spatial_step(_sup_tiles, _sup_list(), _sup_sel, step) if step != 0 else -1
		if nxt >= 0:
			_sup_sel = nxt
			Audio.play("ui_click", Audio.BUS_UI, -14.0)
			_refresh()
		elif _mode == "pyro" and (event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2")):
			_step_fuse(-1 if event.is_action_pressed("menu_slot_1") else 1)
		elif accept:
			_buy_selected_supply()
		elif back:
			close()
	elif _mode == "service" and step != 0:
		# stół konserwacji (ST-02): w górę / w dół — broń, w lewo / w prawo — przyrząd
		if absi(step) == 1:
			_move_opt(step)
		else:
			_move(signi(step))
	elif step != 0:
		_move(step)
	elif event.is_action_pressed("menu_slot_1") or event.is_action_pressed("menu_slot_2"):
		_move_opt(-1 if event.is_action_pressed("menu_slot_1") else 1)
	elif event.is_action_pressed("menu_alt"):
		_save_preset()
	elif accept:
		var ops2 := _options(int(LIST[_sel]))
		var timed := _opt >= 0 and _opt < ops2.size() and String(ops2[_opt]["slot"]) == "service" and String(ops2[_opt]["id"]) in ["clean", "sharpen"]
		_act()
		_hold_clean = timed and _clean_w >= 0
	elif back:
		close()
	get_viewport().set_input_as_handled()

## Opcje części broni `w` w kolejności gniazd: [{slot, id}] — id "" to element fabryczny gniazda. Na końcu „SERVICE / clean”: czyszczenie
## broni przy ławie (etap 4a GUNSMITH_PLAN — stan techniczny), gdy broń jest kupiona, strzela i niezawodność nie jest wyłączona.
func _options(w: int) -> Array:
	var key := String(Weapons.def(w).key)
	var out: Array = []
	if _mode == "lathe":
		if Scrap.is_unlocked(w) and Weapons.def(w).is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "sharpen"})        # szlifierka: ostrze broni białej
		elif key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "lab":
		if key in Scrap.LAB_WEAPONS:
			for s in Parts.slots_of(key):
				for p in Parts.in_slot(key, String(s)):
					out.append({"slot": s, "id": String(p["id"])})
		return out
	if _mode == "service":
		var d := Weapons.def(w)
		if Scrap.is_unlocked(w) and not d.is_melee() and Settings.reliability_mult() > 0.0:
			out.append({"slot": "service", "id": "clean"})
			if d.can_jam():                                      # broń na naboje: lufa i sprężyny (energetyczna ma swoje usterki — WeaponDef.fault)
				out.append({"slot": "service", "id": "barrel"})
				out.append({"slot": "service", "id": "springs"})
		return out
	for s in Parts.slots_of(key):
		out.append({"slot": s, "id": ""})
		for p in Parts.in_slot(key, String(s)):
			out.append({"slot": s, "id": String(p["id"])})
	if Scrap.is_unlocked(w) and not Parts.slots_of(key).is_empty():
		for i in Profile.PRESETS:
			out.append({"slot": "preset", "id": str(i)})       # zestawy części gracza (WORKSHOP_PLAN.md U6)
	return out

func _move_opt(d: int) -> void:
	if _mode == "bench":
		var ops := _options(int(LIST[_sel]))
		var indices: Array = []
		for i in ops.size():
			if String(ops[i]["slot"]) == _bench_slot:
				indices.append(i)
		if not indices.is_empty():
			_pick_opt(int(indices[posmod(indices.find(_opt) + d, indices.size())]))
		return
	var n := _options(int(LIST[_sel])).size()
	if n == 0:
		return
	_opt = posmod(_opt + d, n)
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()
	_reveal_option()

func _pick_opt(i: int) -> void:
	var ops := _options(int(LIST[_sel]))
	if i < 0 or i >= ops.size():
		return
	if i != _opt:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_opt = i
	_selection_revision += 1
	if _mode == "bench":
		_bench_slot = String(ops[i]["slot"])
		_workbench.stage.cancel_mount()
	_refresh()
	_reveal_option()

## Nawigacja klawiszami/padem nie zostawia wybranej operacji poza przewijanym kadrem.
func _reveal_option() -> void:
	call_deferred("_reveal_current_option")

func _reveal_current_option() -> void:
	if not _open or _page != 0 or _mode == "bench":
		return
	var buttons := _d_tiers.get_children().filter(func(c: Node) -> bool: return c is Button)
	if _opt >= 0 and _opt < buttons.size():
		_ensure_arm_option_visible.call_deferred(buttons[_opt])

## Przebudowa części może odłączyć przycisk przed odroczonym przewinięciem fokusu.
func _ensure_arm_option_visible(button: Control) -> void:
	if not is_instance_valid(button) or not is_instance_valid(_arms_body):
		return
	var scroll := _arms_body.get_parent() as ScrollContainer
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)

func _move(d: int) -> void:
	var choices := _arms_list()
	var pos := choices.find(_sel)
	var next := pos + d
	if next < 0 or next >= choices.size():
		return
	var n := int(choices[next])
	if n < 0 or n >= LIST.size():
		return
	_stop_clean()
	_sel = n
	_selection_revision += 1
	_bench_slot = ""
	(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
	_opt = _first_part_opt()
	Audio.play("ui_click", Audio.BUS_UI, -14.0)
	_refresh()

func _select(i: int) -> void:
	if not _arms_list().has(i):
		return
	if i != _sel:
		Audio.play("ui_click", Audio.BUS_UI, -14.0)
		_stop_clean()
		_sel = i
		_selection_revision += 1
		_bench_slot = ""
		(_arms_body.get_parent() as ScrollContainer).scroll_vertical = 0
		_opt = _first_part_opt()
	_refresh()

## Kursor na pierwszej części (nie na elemencie fabrycznym) — po wyborze broni widać od razu, co można kupić.
## Siatka i nawigacja korzystają z tej samej listy rzeczywistych opcji stanowiska.
func _arms_list() -> Array:
	var out: Array = []
	for i in LIST.size():
		var w := int(LIST[i])
		if _mode == "bench" or _mode == "locker" or not _options(w).is_empty():
			out.append(i)
	return out

func _initial_selection() -> int:
	var choices := _arms_list()
	if choices.is_empty():
		return 0
	var jobs: Array = Scrap.lathe if _mode == "lathe" else (Scrap.research if _mode == "lab" else [])
	if _mode == "lathe" and jobs.is_empty():
		jobs = Scrap.schematics.keys()
	for id in jobs:
		var w := Weapons.index_of(String(Parts.get_part(String(id)).get("weapon", "")))
		var i := LIST.find(w)
		if choices.has(i):
			return i
	var remembered := int(_remembered.get(_mode, -1))
	if choices.has(remembered):
		return remembered
	var controller := _local_wc()
	if controller != null:
		var i := LIST.find(controller.cur().id)
		if choices.has(i):
			return i
	for i in choices:
		if Scrap.is_unlocked(int(LIST[int(i)])):
			return int(i)
	return int(choices[0])

## Stan wspólnej pracy, także gdy panel pokazuje inną broń.
func _queue_summary(skip_batches := false) -> String:
	var lines: Array[String] = []
	for entry in [[tr("Research"), Scrap.research], [tr("Machining"), Scrap.lathe]]:
		for id in entry[1]:
			lines.append(tr("%s: %s — after a successful mission") % [String(entry[0]), tr(String(Parts.get_part(String(id)).get("name", id)))])
	for id in Scrap.schematics:
		if not Scrap.lathe.has(id):
			lines.append(tr("Schematic: %s — take to the lathe") % tr(String(Parts.get_part(String(id)).get("name", id))))
	for kind in ([] if skip_batches else Scrap.orders):          # prasa pokazuje partie w swoich miejscach (_fill_press_queue)
		lines.append(tr("Batch: %s — after a successful mission") % tr(String(Throwables.KINDS[String(kind)]["name"])))
	for kind in Scrap.deliveries:
		var station := tr("PYROTECHNICS") if Scrap.supply_station(String(kind)) == "pyro_bench" else tr("RELOADING PRESS")
		lines.append(tr("Ready: %s · %d rounds — collect at %s") % [tr(String(Throwables.KINDS[String(kind)]["name"])), int(Scrap.deliveries[kind]), station])
	return "\n".join(lines)

func _slot_label(key: String, slot: String) -> String:
	return tr(String(SLOT_LABELS.get("%s:%s" % [key, slot], Parts.SLOT_NAMES[slot])))

## Te same dane broni dla obu kolumn; porównanie nie zakłada naboju standardowego.
func _comparison_rows(d: RefCounted) -> Array:
	var rows: Array = Codex._weapon_stats(d)
	for row in rows:
		match String(row[0]):
			"Magazine":
				row[1] = "%d%s" % [d.mag, "+1" if d.chamber else ""]
			"Damage":
				if d.kind == WeaponDefinition.Kind.LAUNCHER:
					row[1] = tr("%d blast") % int(d.blast_damage)
				elif d.pellets > 1:
					row[1] = tr("%d × %d pellets") % [int(d.damage), d.pellets]
				elif d.is_continuous():
					row[1] = tr("%d / tick") % int(d.damage)
			"Fire rate":
				if d.is_continuous():
					row[1] = tr("continuous")
				elif d.kind == WeaponDefinition.Kind.RAIL:
					row[1] = tr("%.1f s charge") % d.charge_time
			"Reload":
				if d.reload_per_round:
					row[1] = tr("%.2f s / round") % d.reload_time
			"Noise":
				if d.n_max <= 0.0:
					row[1] = tr("silent")
		row[0] = tr(String(row[0]))
	if d.uses_ammo():
		rows.append([tr("Shared reserve"), "∞" if d.infinite else "%d" % Arsenal.get_reserve(d.id, d.ammo)])
	rows.append([tr("Draw"), tr("%.2f s") % d.draw_time])
	if not d.is_melee():
		rows.append([tr("Spread"), "±%.2f°" % d.jitter_deg + (" / ±%.2f°" % d.spread_deg if d.pellets > 1 else "")])
		rows.append([tr("Bloom"), "+%.2f° / %.2f°" % [d.bloom_per_shot, d.bloom_max]])
		rows.append([tr("Recoil"), "%.2f / %.2f" % [d.cam_kick, d.recoil]])
		rows.append([tr("Penetration"), _penetration_text(d)])
		rows.append([tr("Armour bypass"), "%d%%" % int(d.armor_pen * 100.0)])
		rows.append([tr("Heating"), "%.1f%% / %.1f%%" % [d.barrel_heat * 100.0, d.heat_gain * 100.0]])
	var fields := {}
	for part in Parts.of(String(d.key)):
		for modifier in part.get("mods", []):
			fields[String(modifier[0])] = true
	for field in PART_METRICS:
		if not fields.has(field):
			continue
		var spec: Array = PART_METRICS[field]
		var value := float(d.get(field))
		var text := (tr("Yes") if value != 0 else tr("No")) if spec[1] == "bool" else String(spec[1]) % (value * float(spec[2]))
		rows.append([tr(String(spec[0])), text])
	return rows

## Przebicie zrozumiale: energia kuli w przeszkodach (skrzynia, ciało) i dodatkowe cele promienia, szyny, bełtu (dawniej „0,00 / 1”).
func _penetration_text(d: RefCounted) -> String:
	var parts: Array = []
	if d.pen > 0.0:
		parts.append(tr("%.1f obstacles") % d.pen)
	if d.pierce > 0:
		parts.append(tr_n("+%d target", "+%d targets", d.pierce) % d.pierce)          # formy mnogie: translations/plural.csv
	return " · ".join(parts) if not parts.is_empty() else "—"

## Wiersz z paskiem na papierowej karcie: etykieta, pasek, napis wartości.
func _paper_bar(label: String, frac: float, value: String, col: Color, cap := -1.0) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UiTheme.ink(label, 9, UiTheme.INK_MUTED)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	var bar := PaperBar.new()
	bar.custom_minimum_size.x = 90
	bar.frac = frac
	bar.cap = cap
	bar.col = col
	h.add_child(bar)
	var v := UiTheme.ink(UiTheme.num_text(value), 9, col, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size.x = 100
	h.add_child(v)
	_d_panel.add_child(h)

## Zob. stations/service_view.gd.
func _service_advice(w: int) -> Dictionary:
	return _v_service._service_advice(w)

## Kolor zalecenia na papierze: pilne — koszt, warto — cena, drobiazg — atrament, nic — zysk.
static func _advice_ink(level: int) -> Color:
	return [UiTheme.INK_GAIN, UiTheme.INK, UiTheme.INK_PRICE, UiTheme.INK_COST][clampi(level + 1, 0, 3)]

## Zob. stations/service_view.gd.
func _refresh_service_todo() -> void:
	_v_service._refresh_service_todo()

## Zob. stations/service_view.gd.
func _wear_ink(wear: float) -> Color:
	return _v_service._wear_ink(wear)

## Zob. stations/service_view.gd.
func _fill_service_panel(base: RefCounted, cur: RefCounted) -> void:
	_v_service._fill_service_panel(base, cur)

## Zob. stations/lab_view.gd.
func _build_lab_lathe(left: VBoxContainer, body: HBoxContainer) -> void:
	_v_lab._build_lab_lathe(left, body)

## Zob. stations/lab_view.gd.
func _dress_lab_lathe(w: int, o: Dictionary) -> void:
	_v_lab._dress_lab_lathe(w, o)

## Zob. stations/lab_view.gd.
func _dress_lathe(w: int, o: Dictionary, key: String, part: bool) -> void:
	_v_lab._dress_lathe(w, o, key, part)

## Zob. stations/lab_view.gd.
func _recolor_printout(root: Node) -> void:
	_v_lab._recolor_printout(root)

## Zob. stations/service_view.gd.
func _service_skin(on: bool) -> void:
	_v_service._service_skin(on)

## Zob. stations/lab_view.gd.
func _fill_lab_chain(key: String, slot: String, id: String) -> void:
	_v_lab._fill_lab_chain(key, slot, id)

func _first_part_opt() -> int:
	if _mode == "bench":
		return -1
	var ops := _options(int(LIST[_sel]))
	if _mode == "service":                                # stół konserwacji: kursor od razu na tym, co zalecane
		var adv := _service_advice(int(LIST[_sel]))
		for i in ops.size():
			if not adv.is_empty() and String(ops[i]["id"]) == String(adv["id"]):
				return i
	for i in ops.size():
		if String(ops[i]["id"]) != "":
			return i
	return 0

## Akcja na wybranej broni: kup broń (zablokowana), a odblokowanej — kup część pod kursorem, zamontuj ją albo wróć do fabrycznej.
func _act() -> void:
	if not _pending_part.is_empty() or _buying >= 0:
		return
	var w: int = LIST[_sel]
	if not Scrap.is_unlocked(w):
		if _mode in ["service", "lab", "lathe"]:
			_say(tr("Buy it at the workshop bench first."), UiTheme.MUTED)
		else:
			_buying = w
			Scrap.request_buy(w)
		return
	var ops := _options(w)
	if ops.is_empty():
		return
	if _mode == "bench" and _opt < 0:
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	var key := String(Weapons.def(w).key)
	var id := String(o["id"])
	if String(o["slot"]) == "preset":
		var pi := int(o["id"])
		if Profile.preset(key, pi).is_empty():
			_save_preset()
		elif Profile.is_preset_fitted(key, pi):
			_say(tr("Set %d is already fitted.") % (pi + 1), UiTheme.MUTED)
		else:
			var before := Profile.fit_code(w)
			var skipped := Profile.load_preset(key, pi)
			_success_fx(-6.0)
			_say((tr("Fitted set %d.") % (pi + 1)) if skipped == 0 else (tr("Fitted set %d — %d parts the squad no longer has stay as they were.") % [pi + 1, skipped]),
				UiTheme.OK if skipped == 0 else UiTheme.MUTED)
			_present_committed(w, before)
		return
	if String(o["slot"]) == "service" and id in Profile.WEAR_PARTS:
		if not Profile.service_due(key, id):
			_say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		else:
			Scrap.request_service(w, id)
		return
	if String(o["slot"]) == "service":
		if _clean_w == w:
			_stop_clean()
			_say(tr("Cleaning stopped."), UiTheme.MUTED)
			_refresh()
		elif id == "sharpen" and Profile.sharpen_time(key) <= 0.0:
			_say(tr("Already sharp."), UiTheme.MUTED)
		elif id != "sharpen" and Profile.clean_time(key) <= 0.0:
			_say(tr("Already clean."), UiTheme.MUTED)
		else:
			_start_clean(w)
		return
	if _mode == "lathe" and String(o["slot"]) != "service":
		if Scrap.has_part(id):
			_say(tr("Already made — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.lathe.has(id):
			_say(tr("On the lathe — ready after the next mission."), UiTheme.MUTED)
		elif Scrap.schematics.has(id):
			Scrap.request_machining(id)
		else:
			_say(tr("No schematic — research it at the lab first."), UiTheme.MUTED)
		return
	if _mode == "lab":
		if Scrap.schematics.has(id) or Scrap.lathe.has(id):
			_say(tr("Already researched — make it on the lathe downstairs."), UiTheme.MUTED)
			return
		if Scrap.has_part(id):
			_say(tr("Already known — fit it at the workshop bench."), UiTheme.MUTED)
		elif Scrap.research.has(id):
			_say(tr("Being researched — ready after the next mission."), UiTheme.MUTED)
		else:
			Scrap.request_research(id)
		return
	if id != "" and not Scrap.has_part(id):
		if Scrap.is_lab_part(id) and not Scrap.found.has(id):
			_say(tr("Special-weapon parts are researched at the lab upstairs."), UiTheme.MUTED)
		else:
			_pending_part = {"id": id, "w": w, "fit": Profile.fit_code(w), "session": _session, "revision": _selection_revision}
			_refresh()
			Scrap.request_part(id)
	elif Profile.fitted(key, String(o["slot"])) != id:
		var before := Profile.fit_code(w)
		Profile.set_fit(key, String(o["slot"]), id)
		_success_fx(-6.0)
		_say(tr("Fitted: %s.") % (tr(Parts.get_part(id)["name"]) if id != "" else tr("factory part")), UiTheme.OK)
		_present_committed(w, before)

func _on_result(w: int, ok: bool, reason: String) -> void:
	if _buying == w:
		_buying = -1
	if not _open:
		return
	var name := String(Weapons.def(w).name)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s unlocked — take it from the rack.") % name, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.price_of(w), UiTheme.DANGER)
		"owned":
			_say(tr("%s is already unlocked.") % name, UiTheme.MUTED)
		"later":
			_say("Not available yet — a later zone.", UiTheme.MUTED)
		"reward":
			_say("Defeat the Leech to unlock it.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

## Zestaw pod kursorem: zapisuje bieżący montaż broni (nadpisuje). Poza wierszem zestawu nic nie robi.
func _save_preset() -> void:
	if _page != 0:
		return
	var w: int = LIST[_sel]
	var ops := _options(w)
	if ops.is_empty():
		return
	var o: Dictionary = ops[clampi(_opt, 0, ops.size() - 1)]
	if String(o["slot"]) != "preset":
		return
	Profile.save_preset(String(Weapons.def(w).key), int(o["id"]))
	_success_fx(-6.0)
	_say(tr("Current fit saved as set %d.") % (int(o["id"]) + 1), UiTheme.OK)
	_refresh()

## „1 próbka” / „3 próbki” (badania kosztują 1–2 próbki).
func _samples_text(n: int) -> String:
	return tr_n("%d sample", "%d samples", n) % n                # plural.csv: 1 próbka / 2–4 próbki / 5 próbek

## Kontroler broni lokalnego gracza (masa ekwipunku w nagłówku ławy) albo null.
func _local_wc() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if not p.is_bot and p.is_multiplayer_authority():
			return p.weapons
	return null

## Krótki opis zestawu: nazwy części (bez fabrycznych), „factory", gdy same fabryczne, „—" dla pustego.
func _preset_summary(key: String, i: int) -> String:
	var p := Profile.preset(key, i)
	if p.is_empty():
		return "—"
	var names: Array = []
	for s in Parts.slots_of(key):
		var id := String(p.get(s, ""))
		if id != "":
			names.append(tr(String(Parts.get_part(id)["name"])))
	var txt := ", ".join(names) if not names.is_empty() else tr("factory")
	return txt if txt.length() <= 30 else txt.substr(0, 29) + "…"

## Czyszczenie przy ławie (stan siedzi w profilu gracza, więc serwer nie bierze udziału): trwa Profile.clean_time, panel musi zostać
## otwarty, a gracz przy ławie — odejście, zmiana broni albo ponowne [E] przerywa i trzeba zacząć od nowa.
func _start_clean(w: int) -> void:
	_clean_w = w
	_clean_t = 0.0
	var melee := Weapons.def(w).is_melee()
	_clean_total = Profile.sharpen_time(String(Weapons.def(w).key)) if melee else Profile.clean_time(String(Weapons.def(w).key))
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -8.0, 0.85)
	_say((tr("Sharpening the %s…") if melee else tr("Stripping the %s…")) % String(Weapons.def(w).name), UiTheme.TEXT)
	_refresh()

func _stop_clean() -> void:
	_clean_w = -1
	_clean_t = 0.0

## Klatka czyszczenia (z `_process`; testy wołają ją ręcznie).
func tick_clean(delta: float) -> void:
	if _clean_w < 0:
		return
	_clean_t += delta
	var ck := String(Weapons.def(_clean_w).key)
	var melee := Weapons.def(_clean_w).is_melee()
	if _clean_t < _clean_total:
		_action.text = (tr("Sharpening…  %d%%  (again to stop)") if melee else tr("Cleaning…  %d%%  (again to stop)")) % int(100.0 * _clean_t / _clean_total)
		if String(_action.get_meta("st", "")) != "busy":
			_act_state(_action, "busy", 0)
			_dress_action(_action)
		if not melee:
			var c0 := Profile.condition(ck)                 # brud schodzi z broni w trakcie (ława 3D)
			(_d_stage as GunStage).set_dirt(1.0 - lerpf(c0, Profile.clean_cap(ck), _clean_t / _clean_total) / 100.0)
			if _gauges.has("clean") and is_instance_valid(_gauges["clean"]):            # przyrząd czyszczenia: wskazówka idzie do limitu
				(_gauges["clean"] as ServiceArt.Gauge).dial.value = lerpf(c0, Profile.clean_cap(ck), _clean_t / _clean_total) / 100.0
		return
	var w := _clean_w
	_stop_clean()
	if melee:
		Profile.sharpen(ck)                                 # szlifierka (W6b)
		_stamp()
		_say(tr("%s sharpened — edge 100%%.") % String(Weapons.def(w).name), UiTheme.OK)
		Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.3)
		_refresh()
		return
	Profile.clean(ck)
	_stamp()
	_say(tr("%s stripped and cleaned — condition %d%%.") % [String(Weapons.def(w).name), int(Profile.condition(ck))], UiTheme.OK)
	Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.0)
	_refresh()

func _on_machining_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s on the lathe — ready after the next mission.") % nm, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.machine_price(id), UiTheme.DANGER)
		"busy":
			_say(tr_n("The lathe is busy — %d job per mission.", "The lathe is busy — %d jobs per mission.", Scrap.LATHE_SLOTS) % Scrap.LATHE_SLOTS, UiTheme.MUTED)
		"noschem":
			_say(tr("No schematic — research it at the lab first."), UiTheme.MUTED)
		"owned":
			_say(tr("Already made."), UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_service_result(w: int, part: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"early":
			_say(tr("Still serviceable — replace from %d%% wear.") % int(Profile.SERVICE_DUE), UiTheme.MUTED)
		"ok":
			_say((tr("New barrel in the %s.") if part == "barrel" else tr("New springs in the %s.")) % String(Weapons.def(w).name), UiTheme.OK)
			Audio.play_variant("reload_bolt", 1, Audio.BUS_UI, -6.0, 1.1)
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % int(Scrap.SERVICE_COST.get(part, 0)), UiTheme.DANGER)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_research_result(id: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	var cost := Scrap.research_cost(id)
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s: research started — ready after the next mission.") % nm, UiTheme.OK)
			_success_fx()
			(_jars as LabArt.Jars).hear(1.0 if randf() < 0.5 else -1.0)  # D2a: próbki „słyszą” pracę pracowni
		"samples":
			_say(tr("Not enough samples (%d needed) — elites and bosses drop them.") % cost.x, UiTheme.DANGER)
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % cost.y, UiTheme.DANGER)
		"busy":
			_say(tr_n("The lab is busy — %d project per mission.", "The lab is busy — %d projects per mission.", Scrap.LAB_SLOTS) % Scrap.LAB_SLOTS, UiTheme.MUTED)
		"locked":
			_say(tr("Buy the gun at the workshop bench first."), UiTheme.MUTED)
		"owned":
			_say(tr("Already known."), UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _on_part_result(id: String, ok: bool, reason: String) -> void:
	var context: Dictionary = _pending_part.duplicate() if String(_pending_part.get("id", "")) == id else {}
	if not context.is_empty():
		_pending_part.clear()
	if not _open:
		return
	var nm := tr(String(Parts.get_part(id).get("name", id)))
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s unlocked for the squad and fitted to your gun.") % nm, UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Scrap.part_cost(id), UiTheme.DANGER)
		"owned":
			_say(tr("The squad already has %s.") % nm, UiTheme.MUTED)
		"locked":
			_say("Unlock the weapon first.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	if ok and not context.is_empty() and int(context["session"]) == _session and int(context["revision"]) == _selection_revision and int(LIST[_sel]) == int(context["w"]):
		_present_committed(int(context["w"]), int(context["fit"]))
	else:
		_refresh()

func _say(text: String, col: Color) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", col)
	_msg_t = 3.0

# ---------------------------------------------------------------- odświeżanie

func _refresh() -> void:
	_refresh_body()
	if _open:
		for b in [_action, _s_action, _p_action, _l_action]:
			_dress_action(b)

func _refresh_body() -> void:
	if not _open:
		return
	_tick_wallet()
	for pi in _page_btns.size():
		_page_btns[pi].set_pressed_no_signal(pi == _page)
	var immersive := _mode == "bench" and _page == 0
	_workbench.visible = immersive
	_shade.visible = true                              # każde stanowisko przygasza scenę jak ława — uwaga na panelu
	_d_stage = _workbench.stage if immersive else _legacy_stage
	_legacy_stage.set_rendering(_page == 0 and not immersive)
	_workbench.stage.set_rendering(immersive)
	_hint.text = StationKit.tape_text(_controls_hint())
	_card.add_theme_stylebox_override("panel", UiTheme.panel_box() if immersive else UiTheme.station_box())
	_arms_body.visible = _page == 0 and not immersive
	_sup_body.visible = _page == 1
	_perk_body.visible = _page == 2
	_look_body.visible = _page == 3
	_action.visible = _page == 0
	_s_action.visible = _page == 1
	_p_action.visible = _page == 2
	_l_action.visible = _page == 3
	for body in [_arms_body, _sup_body, _perk_body, _look_body]:
		body.get_parent().visible = body.visible
	if _page == 3:
		_refresh_look()
		_card.reset_size()
		return
	if _page == 2:
		_refresh_perks()
		_card.reset_size()
		return
	if _page == 1:
		_refresh_supplies()
		_card.reset_size()
		return
	var arms := _arms_list()
	if not arms.is_empty() and not arms.has(_sel):
		_sel = _initial_selection()
	for i in _tiles.size():
		(_tiles[i] as Tile).visible = arms.has(i)
		_refresh_tile(_tiles[i] as Tile, i == _sel)
	_refresh_service_todo()
	_refresh_detail(int(LIST[_sel]))

## Zob. stations/supply_view.gd.
func _refresh_supplies() -> void:
	_v_supply._refresh_supplies()

func _on_supply_result(kind: String, ok: bool, reason: String) -> void:
	if not _open:
		return
	var nm := String(Throwables.KINDS[kind]["name"]) if Throwables.is_valid(kind) else kind
	match reason:
		"station":
			_say(tr("Approach the correct station in the hideout."), UiTheme.MUTED)
		"repeat":
			_say(tr("Please wait before repeating this action."), UiTheme.MUTED)
		"serviced":
			_say(tr("This part was already replaced during this visit."), UiTheme.MUTED)
		"ok":
			_say(tr("%s bought — the squad now carries %d.") % [nm, Arsenal.get_throwable(kind)], UiTheme.OK)
			_success_fx()
		"poor":
			_drum.broke()
			_say(tr("Not enough scrap (%d needed).") % Throwables.price_of(kind), UiTheme.DANGER)
		"full":
			_say(tr("The squad cannot carry more %s.") % nm, UiTheme.MUTED)
		"off":
			_say("No scrap in this mode.", UiTheme.MUTED)
		_:
			_say("Cannot do that.", UiTheme.DANGER)
	_refresh()

func _refresh_tile(t: Tile, selected: bool) -> void:
	var w := t.weapon
	t.set_lit(selected)
	var unlocked := Scrap.is_unlocked(w)
	var later := Scrap.is_later(w)
	(t.icon_node as GunIcon).set_gun(int(Weapons.base_def(w).gun_row), Weapons.base_def(w).tracer_color, Color.WHITE if unlocked else Color(0.45, 0.5, 0.55))
	t.name_label.add_theme_color_override("font_color", UiTheme.ACCENT if selected else (UiTheme.TEXT if unlocked else UiTheme.MUTED))
	t.bar.visible = false
	if t.marks != null:
		t.marks.visible = false                       # ikonki wymian tylko na stole konserwacji (włącza je gałąź „service” niżej)
	t.state_label.add_theme_color_override("font_color", UiTheme.MUTED)
	# Kafle są tylko na stanowiskach pomocniczych (ława ma własny stojak): broń kupuje się wyłącznie przy ławie, więc bez ceny.
	# Linia stanu mówi to, co liczy się PRZY TYM stanowisku: stół konserwacji — stan, szlifierka — ostrze, reszta — odblokowane części.
	if unlocked:
		var key := String(Weapons.def(w).key)
		var melee: bool = Weapons.base_def(w).is_melee()
		var total := Parts.of(key).size()
		var owned := Scrap.parts_owned(w)
		t.tooltip_text = tr("Unlocked parts: %d / %d. Equipment is chosen separately.") % [owned, total]
		if _mode == "service" and not melee:
			var cond := Profile.condition(key)
			t.state_label.text = (tr("Condition %d%%") % int(cond)).to_upper()
			t.state_label.add_theme_color_override("font_color", UiTheme.DANGER if cond < 70.0 else (GOLD if cond < 95.0 else UiTheme.OK))
			t.tooltip_text = tr("Below 70% a gun starts to jam.")
			# ikonki części do wymiany (lufa, sprężyny) w miejscu kropek części — na stole konserwacji kropek nie ma
			var tile := t as Tile
			if tile != null:
				if tile.marks == null:
					tile.marks = ServiceMarks.new()
					tile.marks.position = Vector2(TILE_W - 6.0 - tile.marks.size.x, TILE_H - 19.0)
					tile.add_child(tile.marks)
				for pid in Profile.WEAR_PARTS:
					var pw := Profile.part_wear(key, String(pid))
					var st := 0 if not (Weapons.def(w).can_jam() and Profile.service_due(key, String(pid))) else (2 if pw >= Profile.SERVICE_URGENT else 1)
					tile.marks.set(String(pid), st)
				tile.marks.visible = true
				tile.marks.queue_redraw()
		elif _mode == "lathe" and melee:
			t.state_label.text = (tr("Edge %d%%") % int(Profile.edge_of(key))).to_upper()
		else:
			t.state_label.text = tr("PARTS") if total > 0 else ""
			t.bar.visible = total > 0
			t.bar.set("level", owned)
			t.bar.set("total", total)
			t.bar.set("maxed", owned >= total)
			t.place_bar()
			t.bar.queue_redraw()
	elif later:
		t.state_label.text = tr("BOSS REWARD") if Scrap.is_gated(w) else tr("LATER ZONE")
	else:
		t.state_label.text = tr("BUY AT THE BENCH")

func _refresh_detail(w: int) -> void:
	_service_skin(_mode == "service")
	_action.disabled = false
	_act_state(_action, "", 0)
	var base: RefCounted = Weapons.base_def(w)
	var key := String(base.key)
	var unlocked := Scrap.is_unlocked(w)
	var ops := _options(w)
	_opt = clampi(_opt, -1 if _mode == "bench" else 0, maxi(ops.size() - 1, 0))
	var mine := Profile.fit_code(w)
	var controller := _local_wc()
	var ammo_type: int = controller.ammo_of(w) if controller != null else 0
	var cur: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, mine))
	# podgląd: broń z częścią spod kursora zamontowaną w jej gnieździe (reszta jak teraz)
	var preview: RefCounted = null
	var o: Dictionary = ops[_opt] if not ops.is_empty() and _opt >= 0 else {}
	if _mode == "bench" and not o.is_empty():
		_bench_slot = String(o["slot"])
	if unlocked and not o.is_empty() and String(o["id"]) != "" and not String(o["slot"]) in ["preset", "service"]:
		Profile.mark_seen("part:" + String(o["id"]))          # część pod kursorem jest obejrzana — kropka „nowe” gaśnie
	var pv_code := mine
	if unlocked and not o.is_empty():
		var choice := {}
		for s in Parts.slots_of(key):
			choice[s] = Profile.fitted(key, String(s))
		if String(o["slot"]) == "preset":                      # zestaw: cała broń z tym zestawem (części, których drużyna nie ma, zostają jak są)
			var pset := Profile.preset(key, int(o["id"]))
			for s in pset:
				if String(pset[s]) == "" or Scrap.has_part(String(pset[s])):
					choice[s] = String(pset[s])
		else:
			choice[String(o["slot"])] = String(o["id"])
		pv_code = Parts.encode(key, choice)
		if pv_code != mine:
			preview = Weapons.def_build(w, Weapons.build_of(ammo_type, pv_code))
	# na ławie broń już z częścią spod kursora; ona (albo fabryczny element gniazda) świeci i jest wysunięta
	var hl_part := unlocked and not o.is_empty() and String(o["slot"]) != "preset" and String(o["slot"]) != "service"
	var hl_slot := String(o.get("slot", "")) if hl_part else ("barrel" if unlocked and not o.is_empty() and String(o["id"]) == "barrel" else "")
	(_d_stage as GunStage).show_gun(w, Parts.decode(key, pv_code), String(o.get("id", "")) if hl_part else "", hl_slot, not unlocked)
	(_d_stage as GunStage).set_dirt((1.0 - Profile.condition(key) / 100.0) if unlocked and not base.is_melee() else 0.0)   # brud wg stanu broni (W2)
	(_d_stage as GunStage).set_strip(_clean_w == w)
	_d_title.text = String(base.name)
	var tag := tr(Codex._slot_name(base))
	if unlocked and not Parts.of(key).is_empty():
		tag += tr("  ·  UNLOCKED %d / %d") % [Scrap.parts_owned(w), Parts.of(key).size()]
		tag += tr("  ·  FITTED %d") % Parts.decode(key, mine).size()
	elif not unlocked:
		tag += tr("  ·  LOCKED")
	if unlocked and Profile.kills(key) > 0:
		tag += tr("  ·  KILLS %d") % Profile.kills(key)                    # historia broni (etap 5b)
	if unlocked:
		# wprawa (etap 5a): stopień i punkty do następnego
		var ml := Profile.mastery_level(key)
		var mp := Profile.mastery_points(key)
		if ml < Profile.MASTERY_XP.size() - 1:
			tag += tr("  ·  MASTERY %s  (%d / %d)") % [["0", "I", "II", "III", "IV", "V"][ml], mp, int(Profile.MASTERY_XP[ml + 1])]
		else:
			tag += tr("  ·  MASTERY %s") % ["0", "I", "II", "III", "IV", "V"][ml]
	if _mode == "lab":
		tag += tr("  ·  SAMPLES %d") % Scrap.samples + ((tr(" (+%d this mission)") % Scrap.samples_loot) if Scrap.samples_loot > 0 else "")
	if _mode == "bench" and Settings.realistic_handling:
		var lp := _local_wc()
		if lp != null:
			var km: float = lp.kit_mass()
			tag += UiTheme.num_text(tr("  ·  KIT %.1f kg  (run noise %+d%%)") % [km, int(round((lp.mass_noise_mult() - 1.0) * 100.0))])   # masa ekwipunku (W5)
	if cur.uses_ammo() and Ammo.name_of(String(cur.caliber), ammo_type) != "":         # ogniwo LR-7 nie ma nazwy naboju
		tag += tr("  ·  AMMO %s") % Ammo.name_of(String(cur.caliber), ammo_type)
	_d_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_tag.custom_minimum_size.x = DETAIL_W
	_d_tag.text = tag
	var jobs := _queue_summary()
	if jobs != "":
		_d_tag.text += "\n" + jobs
	# statystyki: broń, jaką masz teraz, i ta sama z częścią spod kursora (złote wartości — zmiany względem bieżącego montażu)
	for ch in _d_stats.get_children():
		_d_stats.remove_child(ch)
		ch.free()
	var now_rows: Array = _comparison_rows(cur)
	var next_rows: Array = _comparison_rows(preview) if preview != null else []
	if next_rows.is_empty():
		next_rows = now_rows.duplicate(true)
	if controller != null and (controller.loadout.has(w) or controller.melee_id == w):
		var km: float = controller.kit_mass()
		var next_mass: float = km + (preview.mass - cur.mass if preview != null else 0.0)
		now_rows.append([tr("Kit mass"), tr("%.2f kg") % km])
		next_rows.append([tr("Kit mass"), tr("%.2f kg") % next_mass])
		var speed: float = clampf(1.0 - Controller.MASS_SPEED * (next_mass - Controller.mass_ref()), Controller.MASS_SPEED_RANGE.x, Controller.MASS_SPEED_RANGE.y) if Settings.realistic_handling else 1.0
		var noise: float = clampf(1.0 + Controller.MASS_NOISE * (next_mass - Controller.mass_ref()), Controller.MASS_NOISE_RANGE.x, Controller.MASS_NOISE_RANGE.y) if Settings.realistic_handling else 1.0
		now_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(controller.mass_speed_mult() - 1.0) * 100.0, (controller.mass_noise_mult() - 1.0) * 100.0]])
		next_rows.append([tr("Run speed / noise"), "%+.1f%% / %+.1f%%" % [(speed - 1.0) * 100.0, (noise - 1.0) * 100.0]])
	for i in now_rows.size():
		var r: Array = now_rows[i]
		# Podgląd części/zestawu zaczyna od rzeczywistych zmian. Pełna karta jest widoczna bez zmiany montażu.
		if preview != null and i < next_rows.size() and String(next_rows[i][1]) == String(r[1]):
			continue
		_d_stats.add_child(UiTheme.ink(String(r[0]), 9, UiTheme.INK_MUTED))
		_d_stats.add_child(UiTheme.ink(UiTheme.num_text(String(r[1])), 9))
		# zmiana: nowa wartość i słowna ocena („korzyść” / „koszt” — od 1.7.460; kompromisem jest cała część, nie jeden parametr) — kolor tylko ją wzmacnia. Strzałka „→” nie ocenia: więcej
		# nie zawsze znaczy lepiej (masa, grzanie), więc ↑ / ↓ myliłyby kierunek liczby z oceną.
		var nv := ""
		var verdict := ""
		var kind := 0
		if i < next_rows.size() and String(next_rows[i][1]) != String(r[1]):
			kind = _change_kind(String(r[0]), cur, preview) if preview != null else 0
			nv = "→ %s" % String(next_rows[i][1])
			verdict = tr("Gain") if kind > 0 else (tr("Cost") if kind < 0 else "")
		var col := UiTheme.INK_GAIN if kind > 0 else (UiTheme.INK_COST if kind < 0 else UiTheme.INK)
		_d_stats.add_child(UiTheme.ink(UiTheme.num_text(nv), 9, col))
		_d_stats.add_child(UiTheme.ink(verdict.to_lower(), 7, col))
	_clear_children(_d_panel)
	if unlocked and (_mode == "service" or (_mode == "lathe" and base.is_melee())):          # szlifierka: pasek ostrza
		_clear_children(_d_stats)                         # przy czyszczeniu liczy się stan i zużycie, nie 22 parametry balistyczne
		_fill_service_panel(base, cur)
	elif (_mode == "lab" or _mode == "lathe") and not o.is_empty() and String(o["slot"]) != "service":
		_fill_lab_chain(key, String(o["slot"]), String(o["id"]))
	# części w gniazdach: nagłówek gniazda, element fabryczny i części (zamontowana — zielona, odblokowana — atrament, do kupienia — z ceną)
	for ch in _d_tiers.get_children():
		_d_tiers.remove_child(ch)
		ch.queue_free()                  # wiersz może właśnie obsługiwać swoje kliknięcie (_pick_opt) — natychmiastowe free() jest wtedy błędem
	var last_slot := ""
	for i in ops.size():
		var op: Dictionary = ops[i]
		var slot := String(op["slot"])
		if slot != last_slot:
			last_slot = slot
			var head_txt := tr("Service") if slot == "service" else (tr("Sets") if slot == "preset" else _slot_label(String(Weapons.def(int(LIST[_sel])).key), slot))
			_d_tiers.add_child(UiTheme.ink(head_txt.to_upper(), 7, UiTheme.INK_MUTED))
		if slot == "preset":
			var pi := int(op["id"])
			var pfit := Profile.is_preset_fitted(key, pi)
			_tier_row(i, tr("Set %d  ·  %s") % [pi + 1, _preset_summary(key, pi)],
				tr("empty") if Profile.preset(key, pi).is_empty() else (tr("fitted") if pfit else tr("saved")), UiTheme.INK_GAIN if pfit else UiTheme.INK)
			continue
		if slot == "service":
			var cc := Profile.clean_time(key)
			var sid := String(op["id"])
			var pw := Profile.part_wear(key, sid) if sid != "clean" else 0.0
			var due := (cc > 0.0) if sid == "clean" else Profile.service_due(key, sid)
			var cap := Profile.clean_cap(key)
			if sid == "sharpen":
				var st := Profile.sharpen_time(key)
				_tier_row(i, tr("Sharpen  ·  edge %d%%") % int(Profile.edge_of(key)), tr("%d s") % ceili(st) if st > 0.0 else tr("sharp"), UiTheme.INK_COST if st > 0.0 else UiTheme.INK_GAIN)
			elif sid == "clean":
				var ctxt := (tr("Clean  ·  condition %d%%") % int(Profile.condition(key))) if cap >= 99.5 else (tr("Clean  ·  condition %d%% (max %d%%)") % [int(Profile.condition(key)), int(cap)])
				_tier_row(i, ctxt, tr("%d s") % ceili(cc) if cc > 0.0 else tr("clean"), UiTheme.INK_COST if due else UiTheme.INK_GAIN)
			else:
				var pname := tr("Barrel") if sid == "barrel" else tr("Springs")
				# poniżej progu bez ceny (nie da się wymienić), od progu cena, od SERVICE_URGENT cena w kolorze kosztu
				var ptail := tr("%d scrap") % int(Scrap.SERVICE_COST[sid]) if due else (tr("like new") if pw < 0.5 else tr("from %d%%") % int(Profile.SERVICE_DUE))
				var pcol := (UiTheme.INK_COST if pw >= Profile.SERVICE_URGENT else UiTheme.INK_PRICE) if due else (UiTheme.INK_GAIN if pw < 0.5 else UiTheme.INK_MUTED)
				_tier_row(i, tr("%s  ·  worn %d%%") % [pname, int(pw)], ptail, pcol)
			continue
		var id := String(op["id"])
		var fitted := Profile.fitted(key, slot) == id
		var owned := id == "" or Scrap.has_part(id)
		var nm := tr("Factory") if id == "" else tr(String(Parts.get_part(id)["name"]))
		var tail := tr("fitted") if fitted else ("" if id == "" else (tr("owned") if owned else (tr("found — extract") if Scrap.found.has(id) else tr("%d scrap") % Scrap.part_cost(id))))
		if id != "" and not owned and not Scrap.found.has(id) and Scrap.is_lab_part(id):
			var rc := Scrap.research_cost(id)
			if Scrap.lathe.has(id):
				tail = tr("on the lathe")
			elif Scrap.schematics.has(id):
				tail = (tr("%d scrap") % Scrap.machine_price(id)) if _mode == "lathe" else tr("schematic")
			elif Scrap.research.has(id):
				tail = tr("researching")
			elif _mode == "lab":
				tail = tr("%s · %d scrap") % [_samples_text(rc.x), rc.y]
			else:
				tail = tr("no schematic") if _mode == "lathe" else tr("lab")
		elif (_mode == "lab" or _mode == "lathe") and owned:
			tail = tr("known") if _mode == "lab" else tr("made")
		_tier_row(i, nm, tail, UiTheme.INK_GAIN if fitted else (UiTheme.INK if owned else UiTheme.INK_PRICE))
	var notes: Array = Codex.WEAPON_TEXT.get(key, ["", ""])
	var desc := Actions.fmt(tr(String(notes[0])))
	if unlocked and not o.is_empty() and String(o["slot"]) == "preset":
		desc = tr("Your saved sets of parts for this gun (only yours — the squad shares the unlocks, not the build). %s fits the set, %s saves your current fit over it.") % [
			_menu_key("menu_accept", Actions.pad_mode), _menu_key("menu_alt", Actions.pad_mode)]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "barrel":
		desc = tr("Every shot wears the bore, a hot one three times faster; a worn barrel spreads wider (up to +60%%). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["barrel"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		desc = tr("Every swing dulls the edge a little. A dull blade hurts less — down to %d%% damage when fully blunt. Sharpening costs no scrap, only time at the grinder.") % int(Profile.EDGE_MIN * 100.0)
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service" and String(o["id"]) == "springs":
		desc = tr("Springs tire with every shot; tired ones keep cleaning from restoring the gun fully (100 − half the wear). Replace from %d%% wear for %d scrap.") % [int(Profile.SERVICE_DUE), int(Scrap.SERVICE_COST["springs"])]
	elif unlocked and not o.is_empty() and String(o["slot"]) == "service":
		desc = tr("Strip and clean the gun: no scrap, only time — the dirtier, the longer. Every shot fouls it (faster hot or suppressed); below 70% it starts to jam.")
	elif unlocked and not o.is_empty() and String(o["id"]) != "":
		desc = tr(String(Parts.get_part(String(o["id"]))["desc"]))
	elif unlocked and not o.is_empty():
		desc = tr("Factory part: no gain, no cost.")
	_d_text.text = desc
	# przycisk akcji
	if not unlocked and Scrap.is_later(w):
		_action.text = "Reward for the Leech" if Scrap.is_gated(w) else "Available in a later zone"
		_act_state(_action, "wait", 0)
	elif not unlocked:
		_action.text = tr("Buy it at the workshop bench") if _mode in ["service", "lab", "lathe"] else tr("Buy  ·  %d scrap") % Scrap.price_of(w)
		_act_state(_action, "wait" if _mode in ["service", "lab", "lathe"] else "ready", 0 if _mode in ["service", "lab", "lathe"] else Scrap.price_of(w))
	elif o.is_empty():
		_action.text = tr("Nothing to service") if _mode == "service" else (tr("Nothing to research — not a special weapon") if _mode == "lab" else (tr("Nothing for the lathe") if _mode == "lathe" else "No parts for this weapon"))
		_act_state(_action, "wait", 0)
	elif String(o["slot"]) == "preset":
		var api := int(o["id"])
		if Profile.preset(key, api).is_empty():
			_action.text = tr("Save current fit as set %d") % (api + 1)
		elif Profile.is_preset_fitted(key, api):
			_action.text = tr("Set %d fitted  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
		else:
			_action.text = tr("Fit set %d  ·  %s overwrite") % [api + 1, _menu_key("menu_alt", Actions.pad_mode)]
	elif String(o["slot"]) == "service" and String(o["id"]) == "sharpen":
		var stime := Profile.sharpen_time(key)
		if _clean_w == w:
			_action.text = tr("Sharpening…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
			_act_state(_action, "busy", 0)
		else:
			_action.text = tr("Sharpen  ·  %d s") % ceili(stime) if stime > 0.0 else tr("Already sharp")
			_act_state(_action, "wait" if stime <= 0.0 else "ready", 0)
	elif String(o["slot"]) == "service" and String(o["id"]) in Profile.WEAR_PARTS:
		# skutek wymiany w liczbach (lufa: rozrzut, sprężyny: granica czyszczenia); poniżej progu przycisk wygaszony z progiem
		var sid2 := String(o["id"])
		var pw2 := Profile.part_wear(key, sid2)
		if not Profile.service_due(key, sid2):
			_action.text = tr("Like new") if pw2 < 0.5 else tr("Still serviceable  ·  replace from %d%% wear") % int(Profile.SERVICE_DUE)
			_act_state(_action, "wait", 0)
			_action.disabled = true
		elif sid2 == "barrel":
			_action.text = tr("Replace barrel  ·  %d scrap  ·  spread +%d%% → +0%%") % [int(Scrap.SERVICE_COST[sid2]), int(round(Controller.BARREL_SPREAD * pow(pw2 / 100.0, 2.0) * 100.0))]
			_act_state(_action, "ready", int(Scrap.SERVICE_COST[sid2]))
		else:
			_action.text = tr("Replace springs  ·  %d scrap  ·  cleans to %d%% → 100%%") % [int(Scrap.SERVICE_COST[sid2]), int(Profile.clean_cap(key))]
			_act_state(_action, "ready", int(Scrap.SERVICE_COST[sid2]))
	elif String(o["slot"]) == "service":
		var ctime := Profile.clean_time(key)
		if _clean_w == w:
			_action.text = tr("Cleaning…  %d%%  (again to stop)") % int(100.0 * _clean_t / maxf(0.01, _clean_total))
			_act_state(_action, "busy", 0)
		else:
			_action.text = tr("Clean  ·  %d s") % ceili(ctime) if ctime > 0.0 else tr("Already clean")
			_act_state(_action, "wait" if ctime <= 0.0 else "ready", 0)
	else:
		var id2 := String(o["id"])
		if _mode == "lathe":
			if Scrap.has_part(id2):
				_action.text = tr("Made  ·  fit it at the bench")
				_act_state(_action, "wait", 0)
			elif Scrap.lathe.has(id2):
				_action.text = tr("On the lathe  ·  ready after the mission")
				_act_state(_action, "busy", 0)
			elif not Scrap.schematics.has(id2):
				_action.text = tr("No schematic  ·  research it at the lab")
				_act_state(_action, "wait", 0)
			elif Scrap.lathe.size() >= Scrap.LATHE_SLOTS:
				_action.text = tr_n("The lathe is busy  ·  %d job per mission", "The lathe is busy  ·  %d jobs per mission", Scrap.LATHE_SLOTS) % Scrap.LATHE_SLOTS
				_act_state(_action, "busy", 0)
			else:
				_action.text = tr("Machine  ·  %d scrap  ·  ready after the mission") % Scrap.machine_price(id2)
				_act_state(_action, "ready", Scrap.machine_price(id2))
		elif _mode == "lab":
			var rc2 := Scrap.research_cost(id2)
			if Scrap.schematics.has(id2) or Scrap.lathe.has(id2):
				_action.text = tr("Researched  ·  make it on the lathe")
				_act_state(_action, "wait", 0)
			elif Scrap.has_part(id2):
				_action.text = tr("Known  ·  fit it at the bench")
				_act_state(_action, "wait", 0)
			elif Scrap.research.has(id2):
				_action.text = tr("Researching  ·  ready after the mission")
				_act_state(_action, "busy", 0)
			elif Scrap.research.size() >= Scrap.LAB_SLOTS:
				_action.text = tr_n("The lab is busy  ·  %d project per mission", "The lab is busy  ·  %d projects per mission", Scrap.LAB_SLOTS) % Scrap.LAB_SLOTS
				_act_state(_action, "busy", 0)
			else:
				_action.text = tr("Research  ·  %s  ·  %d scrap") % [_samples_text(rc2.x), rc2.y]
				_act_state(_action, "ready", rc2.y)
		elif id2 != "" and not Scrap.has_part(id2) and Scrap.is_lab_part(id2) and not Scrap.found.has(id2):
			_action.text = tr("Research it at the lab")
			_act_state(_action, "wait", 0)
		elif id2 != "" and not Scrap.has_part(id2):
			_action.text = tr("Buy part  ·  %d scrap") % Scrap.part_cost(id2)
			_act_state(_action, "ready", Scrap.part_cost(id2))
		elif Profile.fitted(key, String(o["slot"])) == id2:
			_action.text = "Fitted"
			_act_state(_action, "wait", 0)
		else:
			_action.text = "Fit to my gun" if id2 != "" else "Fit the factory part"
	if _mode == "bench":
		_present_bench(w, cur, preview, now_rows, next_rows, ops, o)
	_dress_lab_lathe(w, o)
	_card.reset_size()

## Jawne oględziny nie oznaczają wyboru fabrycznego elementu do montażu.
func _connection_lost() -> void:
	_pending_part.clear()
	_buying = -1
	if _open:
		close()

func _inspect() -> void:
	_opt = -1
	_selection_revision += 1
	_workbench.stage.cancel_mount()
	_refresh()

func _bench_slots() -> Array:
	var slots: Array = Parts.slots_of(String(Weapons.def(int(LIST[_sel])).key)).duplicate()
	if Scrap.is_unlocked(int(LIST[_sel])) and not slots.is_empty():
		slots.append("preset")
	return slots

func _pick_slot(slot: String) -> void:
	if not _bench_slots().has(slot):
		return
	var w := int(LIST[_sel])
	var key := String(Weapons.def(w).key)
	var ops := _options(w)
	var fitted := Profile.fitted(key, slot)
	for i in ops.size():
		if String(ops[i]["slot"]) == slot and (slot == "preset" or String(ops[i]["id"]) == fitted):
			_pick_opt(i)
			return

func _move_slot(direction: int) -> void:
	var slots := _bench_slots()
	if slots.is_empty():
		return
	_pick_slot(String(slots[posmod(slots.find(_bench_slot) + direction, slots.size())]))

func _save_current_preset() -> void:
	if not _pending_part.is_empty() or _buying >= 0:
		return
	if _bench_slot != "preset":
		_pick_slot("preset")
		_say(tr("Choose a set, then save your current fit."), UiTheme.TEXT)
		return
	_save_preset()

func _present_committed(w: int, before: int) -> void:
	var key := String(Weapons.def(w).key)
	var after := Profile.fit_code(w)
	if _mode == "bench" and _page == 0 and int(LIST[_sel]) == w:
		_opt = -1
		_refresh()
		if before != after:
			_workbench.stage.animate_mount(w, Parts.decode(key, before), Parts.decode(key, after))
	else:
		_refresh()

func _present_bench(w: int, cur: RefCounted, preview: RefCounted, now_rows: Array, next_rows: Array, ops: Array, selected: Dictionary) -> void:
	var key := String(cur.key)
	var unlocked := Scrap.is_unlocked(w)
	var slots: Array = []
	for slot in _bench_slots():
		var fitted := Profile.fitted(key, String(slot))
		var name := tr("Sets") if slot == "preset" else _slot_label(key, String(slot))
		var short_name: String = name if SLOT_LABELS.has("%s:%s" % [key, slot]) else {"stock": tr("Grip") if cur.is_melee() else tr("Stock"), "optic": tr("Sight"), "preset": tr("Sets")}.get(slot, name)
		slots.append({"id": slot, "name": name, "short": short_name,
			"fitted": tr("Factory") if fitted == "" else tr(String(Parts.get_part(fitted)["name"]))})
	if _bench_slot == "" and not slots.is_empty():
		_bench_slot = String(slots[0]["id"])
	var records: Array = []
	for i in ops.size():
		var op: Dictionary = ops[i]
		if String(op["slot"]) != _bench_slot:
			continue
		var id := String(op["id"])
		var name := tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id)))
		var fitted := Profile.fitted(key, String(op["slot"])) == id
		var status := tr("fitted") if fitted else (tr("owned") if id == "" or Scrap.has_part(id) else tr("%d scrap") % Scrap.part_cost(id))
		if String(op["slot"]) == "preset":
			name = tr("Set %d") % (int(id) + 1)
			fitted = Profile.is_preset_fitted(key, int(id))
			status = tr("empty") if Profile.preset(key, int(id)).is_empty() else (tr("fitted") if fitted else tr("saved"))
		elif id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				status = tr("found — extract")
			elif Scrap.is_lab_part(id):
				status = tr("on the lathe") if Scrap.lathe.has(id) else (tr("schematic") if Scrap.schematics.has(id) else (tr("researching") if Scrap.research.has(id) else tr("lab")))
		var delta := _part_delta(w, cur, String(op["slot"]), id) if String(op["slot"]) != "preset" and not fitted else []
		records.append({"index": i, "name": name, "status": status, "fitted": fitted,
			"new": id != "" and String(op["slot"]) != "preset" and Profile.is_new("part:" + id), "delta": delta})
	var weapons: Array = []
	var wc := _local_wc()
	for i in LIST.size():
		var wid := int(LIST[i])
		var definition: RefCounted = Weapons.base_def(wid)
		var carried: bool = wc != null and (wc.loadout.has(wid) or wc.melee_id == wid)
		var status := tr("Carried") if carried else (tr("Unlocked") if Scrap.is_unlocked(wid) else (tr("Boss reward") if Scrap.is_gated(wid) else (tr("Later zone") if Scrap.is_later(wid) else tr("%d scrap") % Scrap.price_of(wid))))
		var fresh := Parts.of(String(definition.key)).any(func(pp: Dictionary) -> bool: return Profile.is_new("part:" + String(pp["id"])))
		weapons.append({"index": i, "name": String(definition.name), "row": int(definition.gun_row), "color": definition.tracer_color,
			"status": status, "carried": carried, "selected": i == _sel, "new": fresh})
	var rows: Array = []
	for i in now_rows.size():
		rows.append([now_rows[i][0], now_rows[i][1], next_rows[i][1] if i < next_rows.size() else now_rows[i][1],
			_change_kind(String(now_rows[i][0]), cur, preview) if preview != null else 0])
	var part_name := ""
	var id := String(selected.get("id", ""))
	if not selected.is_empty():
		part_name = tr("Set %d") % (int(id) + 1) if String(selected["slot"]) == "preset" else (tr("Factory") if id == "" else tr(String(Parts.get_part(id).get("name", id))))
	var pending := not _pending_part.is_empty() or _buying >= 0
	_action.disabled = pending or (unlocked and selected.is_empty()) or (not unlocked and (Scrap.is_later(w) or Scrap.bank < Scrap.price_of(w)))
	if pending:
		_action.text = tr("Waiting for confirmation…")
		_act_state(_action, "busy", 0)
	elif unlocked and selected.is_empty():
		_action.text = tr("Inspecting · choose a slot or a part")
	elif unlocked and String(selected.get("slot", "")) != "preset":
		if id != "" and not Scrap.has_part(id):
			if Scrap.found.has(id):
				_action.text = tr("Found · schematic after extraction") if Scrap.is_lab_part(id) else tr("Found · extract to unlock")
				_action.disabled = true
			elif Scrap.is_lab_part(id):
				_action.text = tr("Research and make it at the lab / lathe")
				_action.disabled = true
			else:
				_action.text = tr("Unlock & fit · %d scrap") % Scrap.part_cost(id)
				_act_state(_action, "ready", Scrap.part_cost(id))
				_action.disabled = Scrap.bank < Scrap.part_cost(id)
		else:
			_action.disabled = Profile.fitted(key, String(selected["slot"])) == id
	var meta := tr("Condition %d%%") % int(Profile.condition(key)) if not cur.is_melee() else tr("Edge %d%%") % int(Profile.edge_of(key))
	var kills := Profile.kills(key)
	meta += " · " + tr("Mastery %s") % ["0", "I", "II", "III", "IV", "V"][Profile.mastery_level(key)] + " · " + tr_n("%d kill", "%d kills", kills) % kills
	var ammo_name := Ammo.name_of(String(cur.caliber), wc.ammo_of(w) if wc != null else 0) if cur.uses_ammo() else ""
	if ammo_name != "":
		meta += "\n" + tr(ammo_name)
	var description := _d_text.text
	if id != "" and String(selected.get("slot", "")) != "preset" and not GunStage.GunModel.has_model(id):
		description += "\n" + tr("Internal modification · compare its effects on the card.")
	# metryka broni (E5, ST-01): numer, zabójstwa, wprawa i hałas magazynka od ciszy (§5a; cień = obecny montaż przy podglądzie)
	var mp := Profile.mastery_points(key)
	var ml := Profile.mastery_level(key)
	var noise_now := StationNoise.mag_level(cur) if cur.uses_ammo() else -1.0
	var noise_new := StationNoise.mag_level(preview) if preview != null and cur.uses_ammo() else -1.0
	_workbench.present({"name": String(cur.name), "meta": meta, "tag": _d_tag.text, "preview": preview != null,
		"serial": "86-%04d" % (absi(hash(key)) % 10000), "kills": kills, "mastery": ml, "mastery_points": mp,
		"mastery_next": int(Profile.MASTERY_XP[mini(ml + 1, Profile.MASTERY_XP.size() - 1)]), "ammo": ammo_name, "noise": [noise_now, noise_new],
		"pending": pending, "part_name": part_name, "option": _opt, "unlocked": unlocked, "slot": _bench_slot,
		"weapons": weapons, "slots": slots, "options": records, "rows": rows, "description": description, "melee": cur.is_melee()})

## Główne zmiany po zamontowaniu części `id` w gnieździe `slot` broni `w` (kafel części na ławie): do dwóch wierszy [parametr, nowa wartość,
## ocena −1 / 0 / 1] — pierwsza korzyść i pierwszy kompromis (albo zmiana bez oceny); [] — bez zmian w liczbach (część o samym opisie).
func _part_delta(w: int, cur: RefCounted, slot: String, id: String) -> Array:
	var key := String(cur.key)
	var choice := {}
	for s in Parts.slots_of(key):
		choice[s] = Profile.fitted(key, String(s))
	choice[slot] = id
	var wc := _local_wc()
	var ammo_type: int = wc.ammo_of(w) if wc != null else 0
	var after: RefCounted = Weapons.def_build(w, Weapons.build_of(ammo_type, Parts.encode(key, choice)))
	var before_rows := _comparison_rows(cur)
	var after_rows := _comparison_rows(after)
	var gain: Array = []
	var cost: Array = []
	var neutral: Array = []
	for i in mini(before_rows.size(), after_rows.size()):
		if String(before_rows[i][1]) == String(after_rows[i][1]):
			continue
		var kind := _change_kind(String(before_rows[i][0]), cur, after)
		var row := [String(before_rows[i][0]), UiTheme.num_text(String(after_rows[i][1])), kind]
		if kind > 0 and gain.is_empty():
			gain = row
		elif kind < 0 and cost.is_empty():
			cost = row
		elif kind == 0 and neutral.is_empty():
			neutral = row
	var out: Array = []
	for r in [gain, cost]:
		if not r.is_empty():
			out.append(r)
	if out.is_empty() and not neutral.is_empty():
		out.append(neutral)
	return out

## Kolor jest pomocniczy: korzyści i kompromisy mają również podpis. Mieszane zmiany pozostają neutralne.
func _change_kind(metric: String, before: RefCounted, after: RefCounted) -> int:
	for field in PART_METRICS:
		if metric == tr(String(PART_METRICS[field][0])):
			if field == "auto":
				return 0 # tryb ognia jest wyborem sposobu użycia
			var direction := -1.0 if Parts.LOWER_IS_BETTER.has(field) or field == "ammo_per_shot" else 1.0
			return int(signf((float(after.get(field)) - float(before.get(field))) * direction))
	if metric == tr("Damage"):
		var old_damage: float = before.blast_damage if before.kind == WeaponDefinition.Kind.LAUNCHER else before.damage * before.pellets
		var new_damage: float = after.blast_damage if after.kind == WeaponDefinition.Kind.LAUNCHER else after.damage * after.pellets
		return int(signf(new_damage - old_damage))
	var fields := {tr("Damage"): ["damage", 1], tr("Magazine"): ["mag", 1], tr("Noise"): ["n_max", -1],
		tr("Mass"): ["mass", -1], tr("Kit mass"): ["mass", -1], tr("Run speed / noise"): ["mass", -1],
		tr("Draw"): ["draw_time", -1], tr("Armour bypass"): ["armor_pen", 1]}
	if fields.has(metric):
		var spec: Array = fields[metric]
		return int(signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[1])))
	if metric == tr("Range") or metric == tr("Reach"):
		return int(signf(after.range_m() - before.range_m()))
	if metric == tr("Fire rate") or metric == tr("Swing rate"):
		return int(signf(after.rpm() - before.rpm()))
	if metric == tr("Reload"):
		return int(signf(before.full_reload_time() - after.full_reload_time()))
	if metric == tr("DPS"):
		return int(signf(after.dps() - before.dps()))
	var pairs := {tr("Spread"): ["jitter_deg", "spread_deg", -1], tr("Bloom"): ["bloom_per_shot", "bloom_max", -1],
		tr("Recoil"): ["cam_kick", "recoil", -1], tr("Penetration"): ["pen", "pierce", 1], tr("Heating"): ["barrel_heat", "heat_gain", -1]}
	if pairs.has(metric):
		var spec: Array = pairs[metric]
		var a := signf((float(after.get(spec[0])) - float(before.get(spec[0]))) * float(spec[2]))
		var b := signf((float(after.get(spec[1])) - float(before.get(spec[1]))) * float(spec[2]))
		return int(signf(a + b)) if a * b >= 0 else 0
	return 0

## Kolumna szczegółów na papierze (jak karta ławy): marginesy karty, napisy atramentem (UiTheme.ink).
## Stan dźwigni akcji (StationKit.action_boxes): `st` "ready" / "wait" / "busy" / "collect" ("" — z `disabled`), `price` > złomu = brak złomu.
func _act_state(b: Button, st: String, price: int) -> void:
	b.set_meta("st", st)
	b.set_meta("price", price)

func _dress_action(b: Button) -> void:
	var st := String(b.get_meta("st", ""))
	if st == "":
		st = "wait" if b.disabled else "ready"
	if st == "busy":
		st = "wait"
	if st == "ready" and (b.disabled or (int(b.get_meta("price", 0)) > Scrap.bank and Scrap.enabled())):
		st = "broke" if int(b.get_meta("price", 0)) > Scrap.bank else "wait"
	if String(b.get_meta("dressed", "")) == st:
		return
	b.set_meta("dressed", st)
	var boxes := StationKit.action_boxes(st)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, boxes[k])
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(c, boxes["fg"])
	b.add_theme_constant_override("outline_size", 0)

func _paper(inner: Control) -> PanelContainer:
	var paper := PanelContainer.new()
	paper.add_theme_stylebox_override("panel", UiTheme.paper_box())
	paper.add_child(inner)
	var stamp := StationKit.Stamp.new()                  # pieczątka skutku akcji (nakładka, nie zmienia układu)
	paper.add_child(stamp)
	paper.set_meta("stamp", stamp)
	_papers.append(paper)
	return paper

## Pieczątka na widocznej karcie po udanej operacji stanowiska (ZAMÓWIONO, WYDANO, ZBADANO…).
func _stamp() -> void:
	for p in _papers:
		var pc := p as PanelContainer
		if pc.is_visible_in_tree():
			(pc.get_meta("stamp") as StationKit.Stamp).play(tr(String(StationKit.STAMPS.get(_mode, "DONE"))))
			return

func _paper_rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.PAPER_EDGE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Tytuł karty na papierze: krój nagłówków, atrament, bez obrysu.
func _ink_heading() -> Label:
	var l := UiTheme.heading("", 16, UiTheme.INK)
	l.add_theme_constant_override("outline_size", 0)
	return l

## Wiersz listy części / czynności na papierze. Zaznaczony ma ciemniejszy pasek i znacznik „»” (nie tylko inny kolor), stan w nawiasie.
func _tier_row(i: int, text: String, tail: String, col: Color) -> void:
	var sel := i == _opt
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_constant_override("outline_size", 0)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, col)
	b.text = ("%s %s   [%s]" % ["»" if sel else " ", text, tail]) if tail != "" else ("%s %s" % ["»" if sel else " ", text])
	b.custom_minimum_size = Vector2(DETAIL_W, 0)
	if _mode == "lathe":                                  # tokarka (ST-06): schematy jako rulony przy kaflach — kolory blatu
		b.flat = false
		var light := {UiTheme.INK: UiTheme.TEXT, UiTheme.INK_MUTED: UiTheme.MUTED, UiTheme.INK_GAIN: UiTheme.OK, UiTheme.INK_COST: UiTheme.DANGER, UiTheme.INK_PRICE: UiTheme.ACCENT}
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, light.get(col, UiTheme.TEXT))
		b.custom_minimum_size = Vector2(COLS * TILE_W, 22)
		for st in ["normal", "hover", "pressed", "focus"]:
			var roll := StyleBoxFlat.new()
			roll.bg_color = Color("2a2216") if sel else (Color("1b1c18") if st != "hover" else Color("23241f"))
			roll.border_color = UiTheme.LAMP_LINE if sel else UiTheme.LINE
			roll.set_border_width_all(1)
			roll.set_corner_radius_all(9)
			roll.content_margin_left = 12.0
			roll.content_margin_top = 2.0
			roll.content_margin_bottom = 2.0
			b.add_theme_stylebox_override(st, roll)
		b.pressed.connect(_pick_opt.bind(i))
		_d_tiers.add_child(b)
		return
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBox = StyleBoxEmpty.new()
		if sel or st == "hover":
			var band := StyleBoxFlat.new()
			band.bg_color = UiTheme.PAPER_SEL if sel else Color(UiTheme.PAPER_SEL, 0.55)
			sb = band
		sb.content_margin_top = 1.0                         # wiersz bez marginesów przycisku — lista części mieści się w karcie
		sb.content_margin_bottom = 1.0
		sb.content_margin_left = 2.0
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(_pick_opt.bind(i))
	_d_tiers.add_child(b)

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.LINE2
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
