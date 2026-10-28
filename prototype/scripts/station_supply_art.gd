extends RefCounted
## Prasa i stół pirotechniczny (STATION_CARDS_PLAN.md E2, §6 ST-03 / ST-04): rysunki kart wzięte z przedmiotów przy znacznikach —
## regał z pudełkami amunicji (pasek jak oznaczenie czubka), etykieta partii z ząbkiem pod wybranym pudełkiem, paski porównania od zera,
## skrzynia saperska z przegrodami, pokrętło zapalnika, lont o długości czasu i schemat wybuchu w skali z sylwetką kolegi.
## Tylko prezentacja (workshop_ui.gd układa kafle i wypełnia dane).

const UiTheme := preload("res://scripts/ui_theme.gd")
const ItemIcon := preload("res://scripts/item_icon.gd")
const Throwables := preload("res://scripts/throwables.gd")
const PX_PER_M := 16.0                       ## jak w kodeksie: 1 m projektowy = 16 px świata

## Pasek na pudełku jak oznaczenie czubka pocisku: [kolor pudełka, kolor 1, kolor 2]. Radzieckie oznaczenia: poddźwiękowy — czarny z zielonym,
## przeciwpancerno-zapalający — czarny z czerwonym; śrut — kolor łuski. Rodzaj bez wpisu bierze kolor z Throwables.KINDS.
const TIPS := {
	"ammo_us": [Color("3f4229"), Color("121210"), Color("3f8f4a")],
	"ammo_bz": [Color("3f4229"), Color("121210"), Color("b3322a")],
	"ammo_hot762": [Color("3f4229"), Color("c98a2a"), Color("c98a2a")],
	"ammo_slug": [Color("6a2a20"), Color("d8d0b8"), Color("d8d0b8")],
	"ammo_inc": [Color("4c241c"), Color("c86a2a"), Color("c86a2a")],
	"ammo_rub": [Color("23383a"), Color("5fa3a0"), Color("5fa3a0")],
	"ammo_mag12": [Color("4a2420"), Color("8c8a84"), Color("8c8a84")],
}
const LABEL_PAPER := Color("8f7d5a")         ## etykieta na pudełku (nocna, jak papier stanowisk)
const WOOD := Color("3a2c1c")
const WOOD_HI := Color("5a4630")
const WOOD_LO := Color("1e160d")

## Pudełko amunicji na półce prasy: ciało w kolorze partii, etykieta z nazwą (krój nagłówków), pasek oznaczenia, w dolnym okienku
## widać naboje (ile pudełek drużyna ma przy sobie). Zastępuje miniaturę ItemIcon na kafelku, ta sama metoda `set_item`.
class BoxFace extends ItemIcon:
	var title := ""
	var stock := 0                           ## pudełka przy sobie (okienka z nabojami)
	var stock_max := 4
	func _draw() -> void:
		var tip: Array = TIPS.get(kind, [Color("3f4229"), Throwables.KINDS.get(kind, {}).get("color", Color.GRAY), Throwables.KINDS.get(kind, {}).get("color", Color.GRAY)])
		var body: Color = tip[0]
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.45))              # cień na półce
		draw_rect(r, Color(body.r * tint.r, body.g * tint.g, body.b * tint.b))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.08))               # krawędź wieczka
		draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)
		# etykieta
		var lab := Rect2(r.position + Vector2(5, 6), Vector2(r.size.x - 10, 15))
		draw_rect(lab, Color(LABEL_PAPER.r * tint.r, LABEL_PAPER.g * tint.g, LABEL_PAPER.b * tint.b))
		var font := UiTheme.heading_font()
		draw_string(font, Vector2(lab.position.x, lab.position.y + 11.5), title, HORIZONTAL_ALIGNMENT_CENTER, lab.size.x, 11, Color("15100a"))
		# pasek oznaczenia czubka: dwa kolory jak na pocisku
		var band := Rect2(r.position.x, lab.end.y + 6, r.size.x, 4)
		draw_rect(Rect2(band.position, Vector2(band.size.x * 0.45, band.size.y)), (tip[1] as Color) * tint)
		draw_rect(Rect2(band.position + Vector2(band.size.x * 0.45, 0), Vector2(band.size.x * 0.55, band.size.y)), (tip[2] as Color) * tint)
		# okienka z nabojami: pełne = pudełka przy sobie
		var n := clampi(stock_max, 1, 6)
		var w := 5.0
		var gap := 3.0
		var x0 := r.position.x + 6.0
		var y0 := r.end.y - 11.0
		for i in n:
			var cr := Rect2(x0 + i * (w + gap), y0, w, 8)
			draw_rect(cr, Color(0, 0, 0, 0.55))
			if i < stock:
				draw_rect(cr.grow(-1.0), Color("b08a3c") * tint)

## Deska półki pod rzędem pudełek: przód z krawędzią, cień na ścianie.
class Plank extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 7)
	func _draw() -> void:
		draw_rect(Rect2(0, 0, size.x, 5), Color("4a3a26"))
		draw_rect(Rect2(0, 0, size.x, 1), Color("6a5438"))
		draw_rect(Rect2(0, 5, size.x, 2), Color(0, 0, 0, 0.5))

## Ząbek etykiety partii: trójkąt w kolorze papieru, wskazujący środek wybranego pudełka (`target`).
class Notch extends Control:
	var target: Control
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 8)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		if target == null or not target.is_visible_in_tree():
			return
		var x := (target.get_global_rect().get_center().x - get_global_rect().position.x) / maxf(0.01, get_global_transform().get_scale().x)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 8, size.y + 1), Vector2(x, 0), Vector2(x + 8, size.y + 1)]), UiTheme.PAPER)
		draw_polyline(PackedVector2Array([Vector2(x - 8, size.y), Vector2(x, 0), Vector2(x + 8, size.y)]), UiTheme.PAPER_EDGE, 1.0)

## Pasek porównania z nabojem zwykłym od zera: kreska zera na środku, zysk w prawo, koszt w lewo (kolor wzmacnia znak ▲▼ obok).
class CmpBar extends Control:
	var value := 0.0                         ## -1..1
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(90, 9)
	func _draw() -> void:
		var mid := size.x * 0.5
		draw_rect(Rect2(0, 2, size.x, size.y - 4), Color(0, 0, 0, 0.14))
		var w := clampf(absf(value), 0.06, 1.0) * mid
		if value >= 0.0:
			draw_rect(Rect2(mid, 2, w, size.y - 4), UiTheme.INK_GAIN)
		else:
			draw_rect(Rect2(mid - w, 2, w, size.y - 4), UiTheme.INK_COST)
		draw_rect(Rect2(mid - 0.5, 0, 1.5, size.y), UiTheme.INK)

## Pokrętło zapalnika: tarcza z kreskami pozycji, wskazówka na wybranej (pad: klawisze pozycji obracają pokrętło).
class FuseDial extends Control:
	var count := 3
	var index := 1
	var _shown := 1.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(46, 46)
	func _process(delta: float) -> void:
		var k := 1.0 if Settings.fx_mult() <= 0.0 else minf(1.0, delta * 12.0)
		_shown = lerpf(_shown, float(index), k)
		queue_redraw()
	func _ang(i: float) -> float:
		return lerpf(PI * 1.2, PI * 1.8, i / maxf(1.0, float(count - 1)))
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, Color("1a1a16"))
		draw_arc(c, r, 0, TAU, 32, Color("3d3a30"), 2.0, true)
		draw_circle(c, r * 0.62, Color("26251f"))
		for i in count:
			var a := _ang(float(i))
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r - 6.0), c + d * (r - 1.5), UiTheme.TEXT if i == index else Color(UiTheme.TEXT, 0.4), 2.0, true)
		var pa := _ang(_shown)
		draw_line(c, c + Vector2(cos(pa), sin(pa)) * (r * 0.62), UiTheme.ACCENT, 3.0, true)
		draw_circle(c, 3.0, UiTheme.ACCENT)

## Lont zapalnika: długość = czas (pełna szerokość = `max_s`), iskra na końcu.
class FuseCord extends Control:
	var seconds := 1.8
	var max_s := 3.0
	var _t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 10)
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var len := size.x * clampf(seconds / maxf(0.1, max_s), 0.05, 1.0)
		var y := size.y * 0.5
		var x := 0.0
		while x < len:
			draw_line(Vector2(x, y), Vector2(minf(x + 4.0, len), y), UiTheme.INK, 2.0)
			x += 6.0
		var flick := 1.0 if Settings.fx_mult() <= 0.0 else 0.8 + 0.2 * sin(_t * 23.0)
		draw_circle(Vector2(len, y), 4.5 * flick, Color(UiTheme.ACCENT, 0.35))
		draw_circle(Vector2(len, y), 2.2, UiTheme.ACCENT)

## Schemat działania przedmiotu w skali (1 m = `px_m`): wybuch — półkole promienia, mina — stożek, fosfor — pole ognia, dym — chmura;
## sylwetka kolegi stoi w środku zasięgu (rani albo nie, z danych) i druga poza nim — granat rani drużynę, więc widać, gdzie stać.
class BlastDiagram extends Control:
	var kind := "frag"
	var lines: Array = []                    ## podpisy: [tekst nad zasięgiem, podpis kolegi w środku, podpis kolegi poza]
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 74)
	func _figure(x: float, ground: float, col: Color) -> void:
		draw_circle(Vector2(x, ground - 19.0), 3.0, col)
		draw_line(Vector2(x, ground - 16.0), Vector2(x, ground - 6.0), col, 3.0)
		draw_line(Vector2(x, ground - 6.0), Vector2(x - 2.5, ground), col, 2.0)
		draw_line(Vector2(x, ground - 6.0), Vector2(x + 2.5, ground), col, 2.0)
	func _draw() -> void:
		var d: Dictionary = Throwables.KINDS.get(kind, {})
		var ground := size.y - 12.0
		var cx := size.x * 0.32
		var font := UiTheme.mono_font()
		var reach := 0.0
		var px_m := 0.0
		match kind:
			"frag", "charge":
				reach = float(d.get("radius", 64.0)) / PX_PER_M
			"mine":
				reach = float(d.get("range", 84.0)) / PX_PER_M
			"phos":
				reach = 3.0
			"smoke":
				reach = 3.5
		if reach <= 0.0:
			return
		px_m = minf((size.x - cx - 24.0) / (reach + 1.5), (ground - 16.0) / reach)          # 16 px u góry na podpis zasięgu
		var rp := reach * px_m
		var fill := Color(UiTheme.INK_COST, 0.22)
		var edge := UiTheme.INK_COST
		match kind:
			"frag", "charge":
				draw_arc(Vector2(cx, ground), rp, PI, TAU, 40, edge, 1.5, true)
				var pts := PackedVector2Array([Vector2(cx - rp, ground)])
				for i in 41:
					var a := PI + PI * float(i) / 40.0
					pts.append(Vector2(cx, ground) + Vector2(cos(a), sin(a)) * rp)
				draw_colored_polygon(pts, fill)
			"mine":
				var half := deg_to_rad(float(d.get("half_deg", 38.0)))
				var tri := PackedVector2Array([Vector2(cx, ground - 4.0)])
				for i in 13:
					var a := -half + 2.0 * half * float(i) / 12.0
					tri.append(Vector2(cx, ground - 4.0) + Vector2(cos(a), sin(a) * 0.45) * rp)
				draw_colored_polygon(tri, fill)
				draw_polyline(tri + PackedVector2Array([tri[0]]), edge, 1.2, true)
			"phos":
				for i in 3:
					var fx := cx + (float(i) - 1.0) * rp * 0.66
					draw_colored_polygon(PackedVector2Array([Vector2(fx - rp * 0.34, ground), Vector2(fx, ground - 14.0), Vector2(fx + rp * 0.34, ground)]), fill)
				cx -= rp * 0.66
			"smoke":
				for i in 5:
					draw_circle(Vector2(cx - rp * 0.5 + rp * 0.25 * i, ground - 12.0 - 6.0 * sin(i * 1.7)), rp * 0.32, Color(UiTheme.INK, 0.14))
		draw_line(Vector2(0, ground), Vector2(size.x, ground), UiTheme.INK_MUTED, 1.0)
		draw_circle(Vector2(cx, ground - 2.0), 2.5, UiTheme.INK)
		if lines.size() > 0:
			draw_string(font, Vector2(4.0, 9.0), String(lines[0]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 8.0, 8, UiTheme.INK)
		if kind in ["frag", "charge", "mine"]:
			var hurt := bool(d.get("ff", kind != "mine"))
			var near := cx + rp * 0.55
			var far := cx + rp + px_m * 1.0
			_figure(near, ground, UiTheme.INK if hurt else UiTheme.INK_MUTED)
			_figure(far, ground, UiTheme.INK_MUTED)
			if lines.size() > 2:
				# podpisy pod ziemią: kolega w zasięgu — do lewej od sylwetki, poza zasięgiem — do prawej (nie nachodzą na siebie)
				draw_string(font, Vector2(near - 104.0, ground + 9.0), String(lines[1]), HORIZONTAL_ALIGNMENT_RIGHT, 108.0, 7, UiTheme.INK_COST if hurt else UiTheme.INK_MUTED)
				draw_string(font, Vector2(far - 4.0, ground + 9.0), String(lines[2]), HORIZONTAL_ALIGNMENT_LEFT, size.x - far, 7, UiTheme.INK_MUTED)

## Drewno skrzyni saperskiej i wieka (ramka karty na stole pirotechnicznym).
static func wood_box(margin := 6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = WOOD
	b.border_color = WOOD_LO
	b.set_border_width_all(2)
	b.border_width_bottom = 3
	b.set_corner_radius_all(2)
	b.set_content_margin_all(margin)
	return b

## Przegroda skrzyni: ciemne wnętrze, krawędź deski.
static func bay_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color("14120d")
	b.border_color = WOOD_HI
	b.set_border_width_all(1)
	b.set_content_margin_all(0)
	return b
