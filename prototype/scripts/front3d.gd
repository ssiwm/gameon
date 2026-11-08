extends RefCounted
## Pierwszy plan przed płaszczyzną gry (`FOREGROUND_PLAN.md`): rury, kable i łańcuchy 3,5–5 m przed płaszczyzną gry, w zakresach
## kolumn z wpisu `FRONT` w danych mapy (zestaw rodzajów, pas między stropem a podłogą). Paralaksa: przy kamerze NORMAL element 4 m
## przed płaszczyzną przesuwa się ×1,25 względem niej.
##
## Zasady (plan, „Zasady”):
##  - bryły leżą na `LAYER_FRONT`, którą widzi tylko kamera graczy (`VpActors`): gracz przy z ≈ 0 jest zawsze za elementem, a element
##    razem z graczami leży nad obrazem świata i wrogami (F0: trzeci SubViewport kosztował +0,4–0,7 ms za ten sam obraz);
##  - shader bez oświetlenia sceny (`unshaded`: lampy, latarka, ogień go nie dotykają; własny miękki klucz i kontra), bez cienia;
##  - element jest przycięty do pasa wpisu w rzucie na płaszczyznę gry (promień z kamery do z = 0), więc rura kończy się na linii
##    stropu i podłogi, a nie wystaje w niebo nad halą;
##  - wygaszanie ditheringiem Bayera 4 × 4 (przebieg nieprzezroczysty, bez sortowania) do krycia MIN_A w kole wokół graczy, celownika
##    i wrogów (do MAX_PTS punktów);
##  - ustawienie „Foreground” (Settings.FRONT_NAMES): ON, REDUCED (bez elementów w pasie wokół środka kadru), OFF; LOW: bez małych
##    elementów i z twardym kołem zamiast ditheringu.
## Tylko widok: bez kolizji, wzroku, hałasu i wpływu na celowanie.

const Level3D := preload("res://scripts/level3d.gd")

const LAYER_FRONT := 256                   ## warstwa wizualna pierwszego planu (bit 9); kamera świata jej nie widzi
const MAX_PTS := 16
const MIN_A := 0.15                        ## krycie w środku koła wygaszania
const FADE_OUT := 1.7                      ## koło przechodzi w pełne krycie między r a r × FADE_OUT
const BIG_SPACING := Vector2(21.0, 28.0)   ## m: odstęp dużych elementów — najwyżej jeden w kadrze NORMAL (kadr na z = 4 m ma ok. 21 m)
const SMALL_MIN := 6.0                     ## m: mały element najbliżej dużego
const Z_RANGE := Vector2(3.5, 5.0)         ## m: przed płaszczyzną gry
const MARGIN := 2.0                        ## m: od brzegu zakresu
const R_PLAYER := 1.8                      ## m: promień wygaszania wokół gracza (środek na wysokości piersi)
const R_AIM := 1.0
const R_ENEMY := 1.6
const ABOVE := 8.0                         ## m: geometria sięga tyle za pas wpisu (przy kamerze wyżej albo niżej od pasa rzut i tak jest przycięty)
const REDUCED_BAND := 0.3                  ## REDUCED: pół wysokości pasa bez elementów, jako część wysokości kadru
## Zestawy: duże (rury) i małe (kable, łańcuchy) rodzaje, odcień sylwetki i kontry. Klucze to wartości "set" we wpisach `FRONT`.
const SETS := {
	"station": {"big": ["pipe", "pipes2"], "small": ["chain", "cables"], "tint": Color(0.026, 0.023, 0.021), "rim": Color(0.11, 0.07, 0.04)},
	"tunnel": {"big": ["pipe", "pipes2"], "small": ["cables", "chain"], "tint": Color(0.024, 0.024, 0.026), "rim": Color(0.06, 0.06, 0.065)},
}
const BIG_KINDS := ["pipe", "pipes2"]

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 pts[16];                      // xy: punkt na płaszczyźnie gry [m], z: promień [m]
uniform int npts = 0;
uniform int nplayers = 0;                  // pierwsze punkty to gracze: ich poświata oświetla element z boku zwróconego ku nim
uniform vec3 glow_col : source_color = vec3(0.55, 0.47, 0.36);
uniform float glow_r = 7.0;                // m: zasięg poświaty gracza (element stoi 3,5–5 m przed nim)
uniform float max_a = 1.0;
uniform float min_a = 0.15;
uniform float fade_out = 1.7;
uniform bool hard = false;                 // LOW: twarde koło zamiast ditheringu
uniform float mid_y = 0.0;                 // środek kadru na płaszczyźnie gry [m]
uniform float band = 0.0;                  // REDUCED: pół wysokości pasa bez pierwszego planu [m]; 0 = wył.
uniform vec3 key_dir = vec3(-0.45, 0.6, 0.65);
instance uniform vec4 clip = vec4(-1e6, 1e6, -1e6, 1e6);   // x0, x1, y0, y1 na płaszczyźnie gry [m]
instance uniform vec4 tint = vec4(0.03, 0.03, 0.03, 1.0);
instance uniform vec4 rim_col = vec4(0.08, 0.06, 0.04, 1.0);
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float k = cam.z / max(cam.z - wpos.z, 0.001);
	vec2 q = cam.xy + (wpos.xy - cam.xy) * k;      // ten piksel na płaszczyźnie gry (z = 0)
	if (q.x < clip.x || q.x > clip.y || q.y < clip.z || q.y > clip.w) { discard; }
	if (band > 0.0 && abs(q.y - mid_y) < band) { discard; }
	float a = max_a;
	for (int i = 0; i < npts; i++) {
		float d = length(q - pts[i].xy);
		a = min(a, mix(min_a, max_a, smoothstep(pts[i].z, pts[i].z * fade_out, d)));
	}
	if (a < (hard ? 0.5 : bayer4(FRAGCOORD.xy))) { discard; }
	vec3 n = normalize(wnrm);
	float key = 0.55 + 0.45 * clamp(dot(n, normalize(key_dir)), 0.0, 1.0);
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float glow = 0.0;
	for (int i = 0; i < nplayers; i++) {
		vec3 lp = vec3(pts[i].xy, 0.0) - wpos;
		float dl = length(lp);
		glow += clamp(dot(n, lp / max(dl, 0.001)), 0.0, 1.0) / (1.0 + (dl / glow_r) * (dl / glow_r) * 4.0);
	}
	ALBEDO = tint.rgb * key + rim_col.rgb * rim + glow_col * min(glow, 1.0) * 0.5;
}
"""

static var _mat: ShaderMaterial
static var _root: Node3D

## Krycie w odległości `d` od punktu o promieniu `r` — ta sama funkcja co w shaderze (test).
static func fade(d: float, r: float, max_a := 1.0, min_a := MIN_A) -> float:
	return lerpf(min_a, max_a, smoothstep(r, r * FADE_OUT, d))


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("min_a", MIN_A)
		_mat.set_shader_parameter("fade_out", FADE_OUT)
	return _mat


## Pas wpisu na płaszczyźnie gry [x0, x1, y0, y1] w metrach: kolumny c0..c1, od górnej krawędzi podłogi (r1) do dolnej krawędzi stropu (r0).
static func clip_of(e: Dictionary) -> Vector4:
	var T := Level3D.T
	return Vector4(float(e["c0"]) * T, float(int(e["c1"]) + 1) * T, -float(e["r1"]) * T, -float(int(e["r0"]) + 1) * T)


static func _skipped(x: float, skip: Array) -> bool:
	for s in skip:
		if x >= float(s[0]) * Level3D.T - MARGIN and x <= float(int(s[1]) + 1) * Level3D.T + MARGIN:
			return true
	return false


## Rozmieszczenie (bez węzłów, do testu i budowy): [{kind, x, z, big, clip, set}] dla wpisów `FRONT`, z pominięciem `skip`
## ([c0, c1]); `low` pomija małe elementy. Stałe ziarno z wpisu, więc ten sam układ u wszystkich graczy.
static func layout(front: Array, skip: Array, low := false) -> Array:
	var out := []
	for e: Dictionary in front:
		var st: Dictionary = SETS.get(String(e.get("set", "")), {})
		if st.is_empty():
			continue
		var clip := clip_of(e)
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xF407 + int(e["c0"]) * 131 + int(e["r0"]) * 7
		var xs := []
		var x := clip.x + MARGIN + rng.randf_range(2.0, 8.0)
		while x < clip.y - MARGIN:
			xs.append(x)
			x += rng.randf_range(BIG_SPACING.x, BIG_SPACING.y)
		var bi := 0
		for i in xs.size():
			var xb: float = xs[i]
			if not _skipped(xb, skip):
				var kb: String = st["big"][bi % (st["big"] as Array).size()]
				bi += 1
				out.append({"kind": kb, "x": xb, "z": rng.randf_range(Z_RANGE.x, Z_RANGE.y), "big": true, "clip": clip, "set": e["set"]})
			var nx: float = xs[i + 1] if i + 1 < xs.size() else clip.y - MARGIN
			var xm := (xb + nx) * 0.5 + rng.randf_range(-3.0, 3.0)
			var ks: String = st["small"][rng.randi() % (st["small"] as Array).size()]
			var want := rng.randf() < 0.6
			if want and not low and xm - xb >= SMALL_MIN and nx - xm >= SMALL_MIN and xm < clip.y - MARGIN and not _skipped(xm, skip):
				out.append({"kind": ks, "x": xm, "z": rng.randf_range(Z_RANGE.x, Z_RANGE.y), "big": false, "clip": clip, "set": e["set"]})
	return out


static func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Siatka jednego elementu (wszystkie części scalone w jedną powierzchnię): środek u góry w (0, y_top), w dół do y_bot.
static func _element_mesh(kind: String, y_top: float, y_bot: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	var h := y_top - y_bot
	var ym := (y_top + y_bot) * 0.5
	match kind:
		"pipe":
			st.append_from(_cyl(0.2, h, 14), 0, Transform3D(Basis.IDENTITY, Vector3(0.0, ym, 0.0)))
			var flange := _cyl(0.27, 0.1, 14)
			var y := y_bot + rng.randf_range(0.0, 2.4)
			while y < y_top:
				st.append_from(flange, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)))
				y += 2.4
			for i in 2:                                          # kable wzdłuż rury
				st.append_from(_cyl(0.026, h, 6), 0, Transform3D(Basis.IDENTITY, Vector3(0.36 + 0.08 * float(i), ym, -0.12)))
		"pipes2":
			st.append_from(_cyl(0.15, h, 12), 0, Transform3D(Basis.IDENTITY, Vector3(-0.24, ym, 0.0)))
			st.append_from(_cyl(0.1, h, 10), 0, Transform3D(Basis.IDENTITY, Vector3(0.2, ym, -0.05)))
			var clamp_m := BoxMesh.new()
			clamp_m.size = Vector3(0.78, 0.07, 0.36)
			var yc := y_bot + rng.randf_range(0.0, 3.0)
			while yc < y_top:                                    # obejmy co 3 m
				st.append_from(clamp_m, 0, Transform3D(Basis.IDENTITY, Vector3(-0.02, yc, -0.02)))
				yc += 3.0
		"cables":
			var n := rng.randi_range(3, 5)
			for i in n:
				var tilt := rng.randf_range(-0.035, 0.035)
				var r := rng.randf_range(0.018, 0.034)
				st.append_from(_cyl(r, h, 6), 0, Transform3D(Basis(Vector3.BACK, tilt), Vector3(float(i) * 0.09 + rng.randf_range(-0.02, 0.02), ym, -0.06 * float(i))))
		"chain":
			var link := TorusMesh.new()
			link.inner_radius = 0.032
			link.outer_radius = 0.058
			link.rings = 8
			link.ring_segments = 6
			var pitch := 0.085
			var len_m := rng.randf_range(3.5, 7.0)               # zwisa ze stropu (przycięcie pasa ucina górę na linii stropu)
			var yl := y_top
			var i := 0
			while yl > y_top - ABOVE - len_m and yl > y_bot:
				var b := Basis(Vector3.RIGHT, PI * 0.5) * (Basis(Vector3.FORWARD, PI * 0.5) if i % 2 == 1 else Basis.IDENTITY)
				st.append_from(link, 0, Transform3D(b.scaled(Vector3(1.0, 1.0, 1.35)), Vector3(0.0, yl, 0.0)))
				yl -= pitch
				i += 1
			var hook := TorusMesh.new()
			hook.inner_radius = 0.07
			hook.outer_radius = 0.11
			hook.rings = 10
			hook.ring_segments = 6
			st.append_from(hook, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, yl - 0.1, 0.0)))
	return st.commit()


## Buduje elementy pod `parent` (węzeł „Front”). Zwraca liczbę elementów.
static func build(parent: Node3D, front: Array, skip: Array, low: bool) -> int:
	_root = null
	if front.is_empty():
		return 0
	_root = Node3D.new()
	_root.name = "Front"
	parent.add_child(_root)
	var mat := material()
	var items := layout(front, skip, low)
	for it: Dictionary in items:
		var clip: Vector4 = it["clip"]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(float(it["x"]) * 100.0)
		var mesh := _element_mesh(String(it["kind"]), clip.w + ABOVE, clip.z - ABOVE, rng)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%d" % [it["kind"], roundi(float(it["x"]))]
		mi.mesh = mesh
		mi.material_override = mat
		mi.layers = LAYER_FRONT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.position = Vector3(float(it["x"]), 0.0, float(it["z"]))
		var st: Dictionary = SETS[it["set"]]
		mi.set_instance_shader_parameter("clip", clip)
		mi.set_instance_shader_parameter("tint", st["tint"])
		mi.set_instance_shader_parameter("rim_col", st["rim"])
		_root.add_child(mi)
	return items.size()


## Stan z ustawień: widoczność (OFF), pas REDUCED, twarde koło na LOW.
static func apply_settings(mode: int, low: bool) -> void:
	if _root != null and is_instance_valid(_root):
		_root.visible = mode != 2
	material().set_shader_parameter("hard", low)


## Co klatkę: punkty wygaszania ([Vector3(x, y, promień)] na płaszczyźnie gry, w kolejności ważności; pierwsze `nplayers` to gracze —
## ich poświata oświetla element), środek i wysokość kadru [m].
static func update(points: Array, nplayers: int, mid_y: float, frame_h: float, reduced: bool) -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_PTS)
	var n := mini(points.size(), MAX_PTS)
	for i in n:
		var p: Vector3 = points[i]
		arr[i] = Vector4(p.x, p.y, p.z, 0.0)
	var m := material()
	m.set_shader_parameter("pts", arr)
	m.set_shader_parameter("npts", n)
	m.set_shader_parameter("nplayers", mini(nplayers, n))
	m.set_shader_parameter("mid_y", mid_y)
	m.set_shader_parameter("band", frame_h * REDUCED_BAND if reduced else 0.0)
