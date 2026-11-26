extends MeshInstance3D
## Znacznik celu [E] w widoku 3D (INTERACT_PLAN.md I3): cztery narożniki wokół obiektu, który wybrał arbiter interakcji (interact.gd),
## i pasek postępu wzdłuż dolnej krawędzi przy przytrzymaniu. Język „ducha” drzwi (door_hint3d.gd): bez światła sceny, bez mgły i cienia,
## półprzezroczysty bursztyn; zawsze na wierzchu (bez testu głębi), żeby model obiektu nie zasłaniał ramki.
##
## Stan oferty → wygląd: możliwa — bursztyn z oddechem jasności (stały przy „Reduce effects”), trwa przytrzymanie — narożniki stałe, pasek
## zieleni postępu, niemożliwa (brak desek, broń zablokowana) — szary bez oddechu. Znacznik pojawia się po DWELL_S przy tym samym celu
## (przejście obok nie miga) i gaśnie w FADE_S. Ukrywa go widok 3D (`view3d._sync_interact_mark`): wyłączona opcja, oględziny, strzelnica.
## Prostokąt obiektu w pikselach świata 2D: rzut bryły modelu 3D obiektu na płaszczyznę gry (`project_box`, liczy go view3d.gd), a gdy
## obiekt nie ma modelu — ręczny `box` oferty. W 3D znacznik leży w płaszczyźnie gry (z = 0).

const Level3D := preload("res://scripts/level3d.gd")

const TINT := Color(1.0, 0.72, 0.30)          ## bursztyn podpowiedzi (jak door_hint3d.gd TINT)
const TINT_MUTED := Color(0.62, 0.6, 0.55)
const TINT_PROG := Color(0.62, 0.86, 0.55)
const DWELL_S := 0.15                         ## s przy tym samym celu, zanim znacznik się pokaże
const FADE_S := 0.2
const PULSE_S := 1.2                          ## okres oddechu jasności
const PAD_PX := 2.0                           ## odsunięcie narożników od prostokąta obiektu
const ARM_PX := 5.0                           ## najdłuższe ramię narożnika
const THICK_PX := 0.6                         ## grubość linii
const BAR_GAP_PX := 2.5                       ## pasek postępu pod dolną krawędzią
const ALPHA := 0.9

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float fade = 1.0;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * fade;
}
"""

static var _shader: Shader

var target: Node = null                       ## obiekt, wokół którego stoi znacznik (test, view3d)
var alpha := 0.0                              ## bieżąca widoczność 0..1 (bez oddechu)
var _dwell := 0.0
var _t := 0.0
var _im := ImmediateMesh.new()
var _sm: ShaderMaterial
var _key := ""                                ## rect, stan i postęp ostatnio zbudowanej siatki (bez przebudowy co klatkę)

func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_sm = ShaderMaterial.new()
	_sm.shader = _shader
	_sm.render_priority = 10
	mesh = _im
	material_override = _sm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

## Rzut brył `boxes` (AABB w metrach świata 3D) z oka kamery `eye` na płaszczyznę gry (z = 0) — prostokąt w pikselach świata 2D, który
## na ekranie dokładnie obejmuje bryły (perspektywa: model w głębi wychodzi mniejszy, przed płaszczyzną — większy). Pusty bez brył albo
## gdy całe leżą za okiem.
static func project_box(boxes: Array, eye: Vector3) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in boxes:
		var bb: AABB = b
		for i in 8:
			var p := bb.get_endpoint(i)
			if p.z >= eye.z - 0.01:
				continue
			var q := eye + (p - eye) * (eye.z / (eye.z - p.z))
			var px := Vector2(q.x, -q.y) / Level3D.PX
			lo = lo.min(px)
			hi = hi.max(px)
	return Rect2(lo, hi - lo) if lo.x <= hi.x else Rect2()

## Co klatkę: `node` — cel (null — brak), `offer` — jego oferta (interact.gd), `show` — czy znacznik może być widoczny, `calm` — bez oddechu,
## `fit` — rzut modelu celu (`project_box`; pusty — ramka z `box` oferty).
func tick(delta: float, node: Node, offer: Dictionary, show: bool, calm: bool, fit := Rect2()) -> void:
	_t += delta
	var box: Rect2 = (fit if fit.size != Vector2.ZERO else offer.get("box", Rect2())) if node != null else Rect2()
	var want := show and node != null and box.size != Vector2.ZERO
	if node != target:
		target = node
		_dwell = 0.0
		alpha = 0.0                               # nowy cel: bez przesuwania starej ramki — pojawia się od nowa
	if want:
		_dwell += delta
		if _dwell >= DWELL_S:
			alpha = move_toward(alpha, 1.0, delta / FADE_S)
	else:
		alpha = move_toward(alpha, 0.0, delta / FADE_S)
	visible = alpha > 0.001
	if not visible or box.size == Vector2.ZERO:
		return
	var muted := bool(offer.get("muted", false))
	var prog := float(offer.get("prog", -1.0))
	var holding := prog > 0.0
	var breath := 1.0 if (calm or muted or holding) else 0.7 + 0.3 * (0.5 + 0.5 * sin(_t * TAU / PULSE_S))
	_sm.set_shader_parameter("fade", alpha * breath)
	var key := "%.1f,%.1f,%.1f,%.1f|%s|%.2f" % [box.position.x, box.position.y, box.size.x, box.size.y, muted, prog]     # rzut modelu drga o setne piksela
	if key != _key:
		_key = key
		_build(box, TINT_MUTED if muted else TINT, prog)

## Siatka narożników i paska w metrach (płaszczyzna gry).
func _build(box: Rect2, col: Color, prog: float) -> void:
	_im.clear_surfaces()
	var r := box.grow(PAD_PX)
	var arm := minf(ARM_PX, minf(r.size.x, r.size.y) * 0.4)
	var t := THICK_PX
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(col, ALPHA)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	# narożniki: poziome i pionowe ramię każdego rogu (y w dół, jak w świecie 2D)
	for corner in [[x0, y0, 1.0, 1.0], [x1, y0, -1.0, 1.0], [x0, y1, 1.0, -1.0], [x1, y1, -1.0, -1.0]]:
		var cx: float = corner[0]
		var cy: float = corner[1]
		var sx: float = corner[2]
		var sy: float = corner[3]
		_quad(Rect2(Vector2(minf(cx, cx + sx * arm), minf(cy, cy + sy * t)), Vector2(arm, t)), c)
		_quad(Rect2(Vector2(minf(cx, cx + sx * t), minf(cy, cy + sy * arm)), Vector2(t, arm)), c)
	if prog >= 0.0:
		var by := y1 + BAR_GAP_PX
		var w := x1 - x0 - 2.0 * arm
		_quad(Rect2(Vector2(x0 + arm, by), Vector2(w, t)), Color(col, 0.25))
		if prog > 0.0:
			_quad(Rect2(Vector2(x0 + arm, by), Vector2(w * clampf(prog, 0.0, 1.0), t)), Color(TINT_PROG, ALPHA))
	_im.surface_end()

func _quad(r: Rect2, c: Color) -> void:
	var a := Level3D.px_to_m(r.position)
	var b := Level3D.px_to_m(Vector2(r.end.x, r.position.y))
	var d := Level3D.px_to_m(r.end)
	var e := Level3D.px_to_m(Vector2(r.position.x, r.end.y))
	for v in [a, b, d, a, d, e]:
		_im.surface_set_color(c)
		_im.surface_add_vertex(v)
