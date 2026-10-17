extends PanelContainer
## Notatka-papier w HUD (kanał NOTE, MESSAGES_PLAN.md §4): tło rysuje ten węzeł, treść (etykiety, siatka) wkłada do niego hud.gd.
## Trzy materiały zależne od źródła informacji (UiTheme.Note): akta sztabu (odprawa), wydruk z radia (prognoza), kartka odręczna (ostrzeżenia, porady).
## Ciemna paleta po zmroku z UiTheme.note_palette; tekstura papieru i plamy rysowane kodem, bez plików obrazów.
## `wear` (0..1, z liczby upadków w kampanii) brudzi i przypala brzegi, nigdy tekst; `lit` (0..1) przyciemnia notatkę w półmroku.

const UiTheme := preload("res://scripts/ui_theme.gd")

var mat := UiTheme.Note.DOSSIER
var tail := true                   ## ogonek ku obiektowi, do którego notatka jest przypięta
var pin := true                    ## akta: pinezka, kartka: taśma, wydruk: bez
var wear := 0.0:
	set(v):
		wear = clampf(v, 0.0, 1.0)
		queue_redraw()
var tally := 0                     ## kartka: kreski za ukończone misje (grupy po pięć)
var stamp := ""                    ## akta: pieczątka na rogu (np. POUFNE)

static var _noise_tex: ImageTexture
var _seed := 1

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_seed = randi() % 9000 + 1

## Materiał ustawia też marginesy treści (perforacja wydruku i margines kartki zajmują miejsce po bokach).
func set_kind(m: int) -> void:
	mat = m
	var sb := StyleBoxEmpty.new()
	match m:
		UiTheme.Note.PRINTOUT:
			sb.content_margin_left = 25.0
			sb.content_margin_right = 25.0
			sb.content_margin_top = 8.0
			sb.content_margin_bottom = 14.0
			pin = false
		UiTheme.Note.SCRAWL:
			sb.content_margin_left = 27.0
			sb.content_margin_right = 10.0
			sb.content_margin_top = 11.0
			sb.content_margin_bottom = 10.0
			pin = true
		_:
			sb.content_margin_left = 11.0
			sb.content_margin_right = 11.0
			sb.content_margin_top = 10.0
			sb.content_margin_bottom = 9.0
	add_theme_stylebox_override("panel", sb)
	queue_redraw()

static func _noise() -> ImageTexture:
	if _noise_tex == null:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.55
		nz.fractal_octaves = 2
		var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		for y in 96:
			for x in 96:
				var v := nz.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, clampf((v - 0.35) * 0.55, 0.0, 0.3)))
		_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex

## Obrys papieru: lekko nierówny prostokąt (kartka bardziej poszarpana, wydruk z zębami na dole).
func _outline(r: Rect2) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var pts := PackedVector2Array()
	var j := 1.2 if mat == UiTheme.Note.DOSSIER else (2.0 if mat == UiTheme.Note.SCRAWL else 0.0)
	var steps := maxi(3, int(r.size.x / 22.0))
	for i in steps + 1:                                     # góra, od lewej do prawej
		pts.append(Vector2(r.position.x + r.size.x * float(i) / float(steps), r.position.y + rng.randf_range(0.0, j)))
	var vs := maxi(2, int(r.size.y / 26.0))
	for i in range(1, vs + 1):                              # prawy bok w dół
		pts.append(Vector2(r.end.x - rng.randf_range(0.0, j), r.position.y + r.size.y * float(i) / float(vs)))
	if mat == UiTheme.Note.PRINTOUT:                        # dół: zęby po oderwaniu wydruku
		var tooth := 6.0
		var n := int(r.size.x / tooth)
		for i in range(n, -1, -1):
			pts.append(Vector2(r.position.x + minf(r.size.x, float(i) * tooth), r.end.y - (3.0 if i % 2 == 0 else 0.0)))
	else:
		for i in range(steps - 1, -1, -1):                  # dół od prawej do lewej
			pts.append(Vector2(r.position.x + r.size.x * float(i) / float(steps), r.end.y - rng.randf_range(0.0, j)))
	for i in range(vs - 1, 0, -1):                          # lewy bok w górę
		pts.append(Vector2(r.position.x + rng.randf_range(0.0, j), r.position.y + r.size.y * float(i) / float(vs)))
	return pts

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var pal := UiTheme.note_palette(mat)
	var bg: Color = pal["bg"]
	var bg2: Color = pal["bg2"]
	var edge: Color = pal["edge"]
	var r := Rect2(Vector2.ZERO, size)
	var body := r
	if mat == UiTheme.Note.PRINTOUT:
		body = Rect2(0.0, 0.0, size.x, size.y - 3.0)
	var pts := _outline(body)
	# cień papieru
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(2.0, 3.0))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.5))
	# korpus z lekkim ciemnieniem ku dołowi
	var cols := PackedColorArray()
	for p in pts:
		cols.append(bg.lerp(bg2, clampf(p.y / maxf(1.0, size.y), 0.0, 1.0)))
	draw_polygon(pts, cols)
	draw_texture_rect(_noise(), body.grow(-1.0), true, Color(1, 1, 1, 0.9))
	match mat:
		UiTheme.Note.PRINTOUT:
			_draw_printout(pal, body)
		UiTheme.Note.SCRAWL:
			_draw_scrawl(pal, body)
		_:
			_draw_dossier(pal, body)
	# plamy i przypalenie na brzegach (z kampanii), nigdy na środku tekstu
	if wear > 0.02:
		_draw_wear(body, mat != UiTheme.Note.PRINTOUT)
	if tail:
		var cx := roundf(size.x * 0.5)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 6.0, size.y - 3.5), Vector2(cx + 6.0, size.y - 3.5), Vector2(cx, size.y + 6.0)]), bg2.lerp(Color.BLACK, 0.12))
	if pin:
		var px := roundf(size.x * 0.5)
		if mat == UiTheme.Note.SCRAWL:                      # taśma zamiast pinezki
			draw_set_transform(Vector2(px - 18.0, -3.0), 0.08)
			draw_rect(Rect2(0, 0, 36, 10), Color(0.62, 0.58, 0.40, 0.62))
			draw_set_transform(Vector2.ZERO, 0.0)
		else:
			draw_circle(Vector2(px, 1.0), 3.5, Color(0.30, 0.07, 0.05))
			draw_circle(Vector2(px, 0.0), 3.0, Color(0.62, 0.15, 0.11))
			draw_rect(Rect2(px - 1.0, -1.0, 1.0, 1.0), Color(0.86, 0.58, 0.5))

func _draw_dossier(pal: Dictionary, r: Rect2) -> void:
	var deco: Color = pal["deco"]
	var accent: Color = pal["accent"]
	draw_rect(Rect2(10.0, -7.0, 44.0, 8.0), deco)             # zakładka teczki
	# kółko po kawie
	draw_arc(Vector2(size.x - 22.0, size.y - 20.0), 13.0, 0.0, TAU, 26, Color(0.16, 0.09, 0.03, 0.10 + 0.22 * wear), 2.2)
	if stamp != "":
		var font := UiTheme.note_font(UiTheme.Note.DOSSIER)
		draw_set_transform(Vector2(size.x - 70.0, -6.0), 0.15)
		draw_rect(Rect2(0, 0, 66, 14), Color(accent, 0.20))
		draw_rect(Rect2(0, 0, 66, 14), Color(accent, 0.85), false, 1.5)
		draw_string(font, Vector2(5.0, 11.0), stamp, HORIZONTAL_ALIGNMENT_LEFT, 58.0, 9, Color(accent, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0)

func _draw_printout(pal: Dictionary, r: Rect2) -> void:
	var edge: Color = pal["edge"]
	var hole: Color = pal["deco"]
	draw_rect(Rect2(0.0, 0.0, 21.0, r.size.y), edge)
	draw_rect(Rect2(r.size.x - 21.0, 0.0, 21.0, r.size.y), edge)
	var y := 8.0
	while y < r.size.y - 4.0:
		draw_circle(Vector2(10.5, y), 3.0, hole)
		draw_circle(Vector2(r.size.x - 10.5, y), 3.0, hole)
		y += 14.0
	draw_line(Vector2(21.5, 0.0), Vector2(21.5, r.size.y), Color(0, 0, 0, 0.4), 1.0)
	draw_line(Vector2(r.size.x - 21.5, 0.0), Vector2(r.size.x - 21.5, r.size.y), Color(0, 0, 0, 0.4), 1.0)
	y = 23.0
	while y < r.size.y:                                       # linie pasa głowicy drukarki
		draw_line(Vector2(22.0, y), Vector2(r.size.x - 22.0, y), Color(0, 0, 0, 0.17), 1.0)
		y += 2.0

func _draw_scrawl(pal: Dictionary, r: Rect2) -> void:
	var y := 34.0
	while y < r.size.y - 6.0:                                 # kratka zeszytu: niebieskie linie
		draw_line(Vector2(5.0, y), Vector2(r.size.x - 5.0, y), Color(0.14, 0.24, 0.37, 0.42), 1.0)
		y += 13.0
	draw_line(Vector2(21.0, 3.0), Vector2(21.0, r.size.y - 3.0), Color(0.47, 0.12, 0.09, 0.55), 1.5)   # czerwony margines
	if tally > 0:                                             # kreski za ukończone misje, po pięć
		var ink: Color = pal["ink"]
		var n := mini(tally, 15)
		var x := r.size.x - 14.0 - 15.0 * float((n - 1) / 5)
		var base_y := r.size.y - 9.0
		for g in range((n - 1) / 5 + 1):
			var cnt := mini(5, n - g * 5)
			var gx := x + 15.0 * float(g)
			for k in mini(4, cnt):
				draw_line(Vector2(gx + 2.5 * float(k), base_y - 9.0), Vector2(gx + 2.5 * float(k) + 0.5, base_y), Color(ink, 0.8), 1.2)
			if cnt == 5:
				draw_line(Vector2(gx - 1.5, base_y - 2.0), Vector2(gx + 10.0, base_y - 8.0), Color(ink, 0.8), 1.2)

func _draw_wear(r: Rect2, burn: bool) -> void:
	var w := wear
	draw_circle(Vector2(r.size.x - 12.0, 16.0), 11.0 + 8.0 * w, Color(0.30, 0.04, 0.03, 0.30 * w))
	draw_circle(Vector2(r.size.x - 9.0, 24.0), 5.0 + 5.0 * w, Color(0.28, 0.03, 0.02, 0.35 * w))
	draw_circle(Vector2(9.0, r.size.y - 12.0), 6.0 + 5.0 * w, Color(0.28, 0.04, 0.03, 0.26 * w))
	if burn:
		var s := 8.0 + 22.0 * w
		draw_colored_polygon(PackedVector2Array([Vector2(r.size.x, r.size.y - s), Vector2(r.size.x, r.size.y), Vector2(r.size.x - s, r.size.y)]), Color(0.04, 0.02, 0.01, 0.25 + 0.55 * w))
