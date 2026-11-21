extends RefCounted
## Pomosty pod gołym niebem z natury i z historii miejsca (STEPS_PLAN.md): zamiast desek na nogach podmyta skarpa, wykrot, ostaniec granitowy
## albo konary sosen (1.1), ciepłociąg i narośl Żyły (1.3), schody na dach, stacja słupowa i pole antenowe radiostacji (1.2). Czysta oprawa: mapa, kolizja kładki, nawigacja i skok bez zmian; pomost z wpisu nie ma modelu desek ani nóg
## (`Level3D.step_cells`), a wierzch elementu, po którym się chodzi, leży na wysokości pokładu na całej długości ciągu.
## Zasada fizyczna: pod pomostem gracz chodzi w pasie gry (z ≈ 0), więc w pasie |z| < STRIP od podłoża do CLEAR nad nim nie ma niczego —
## nośność daje masa za pasem (z < −0,9), wspornik (konar, płyta skalna, nawis darni) albo kłoda leżąca w poprzek ścieżki.
## Wpis w danych mapy (`STEPS`, czyta `level.gd`): {"kind" (z `KINDS`), "decks": [[wiersz, pierwsza kolumna], …], "posts": [kolumny słupów `w`,
## które znikają], "cache": true (ostaniec: nisza ze skrytką, lina i strzałka patrolu), "legs": [kolumny nóg kratowych pomostu przy maszcie] (pole antenowe), "trunks": [[kolumna, wiersz podłoża], …] (konary: dodatkowa sosna)}.

const Level3D := preload("res://scripts/level3d.gd")
const Front3D := preload("res://scripts/front3d.gd")
const T := Level3D.T

const KINDS := ["bank", "windfall", "tor", "boughs", "heat", "vein", "porch", "pole", "antenna"]
const CLEAR := 1.85                        ## m: wolne nad podłożem w pasie gry (sprawdza `tools/test_steps.gd`)
const STRIP := 0.45                        ## m: połowa głębokości pasu gry, w którym chodzą postacie
const ROOT_CLEAR := 2.15                   ## m: korzenie spod nawisu skarpy kończą się w pasie gry najniżej tyle nad ścieżką
const TOP_TOL := 0.03                      ## m: wierzch elementu najwyżej tyle nad pokładem
const BOUGH_REACH := 3.5                   ## kafli: sosna niesie pomost, gdy stoi najdalej tyle od jego końca
const BOUGH_RUN := 6                       ## kafli: najkrótszy ciąg słupa `w`, który staje się sosną z konarami
const BOUGH_R := Vector2(0.30, 0.13)       ## m: promień konaru u nasady (przy pomoście) i na końcu
const LIMB_STEP := 0.4                     ## m: odcinki konaru (wierzch płaski z dokładnością zmiany promienia na odcinek)
const BARK_TEX := "res://art/world3d/forest/pine_bark_%s_2k.jpg"
const BARK_TILE := 1.3                     ## m kory na powtórzenie tekstury (jak `Front3D.BARK_TILE`)

const HEAT_R := 0.25                       ## m: promień rury ciepłociągu w płaszczu (⌀ 0,5 m)
const HEAT_SPAN := 3.0                     ## m: najdłuższy odstęp wsporników Γ
const HEAT_MAIN_Y := 0.55                  ## m: oś magistrali za placem nad gruntem
const VEIN_STEP := 1.3                     ## m: odstęp półłuków narośli Żyły
const PORCH_Z := Vector2(-1.0, -3.8)       ## m: przedni i tylny rząd słupów schodów na dach (spocznik od tylnego do przedniej krawędzi)
const PORCH_BANDS := [Vector2(-2.05, -2.8), Vector2(-3.0, -3.7)]   ## m: pasy biegów schodów w głębi (przód, tył), na zmianę
const POLE_Z := Vector2(-1.3, -2.9)        ## m: żerdzie bramki stacji słupowej (przednia, tylna)
const POLE_DECK_Z := -3.2                  ## m: tylna krawędź podestu stacji słupowej
const POLE_SPAN := 6.5                     ## m: najdłuższy odstęp bramek stacji słupowej
const POLE_LINE := 4.6                     ## m: martwa linia nad najwyższym podestem
const POLE_WIRES := [-0.8, -2.1, -3.4]     ## m: przewody linii w głąb
const POLE_WIRE_OUT := 8.0                 ## m: linia wychodzi tyle za skrajne podesty
const ANT_Z := -1.6                        ## m: oś masztu anteny w głąb
const ANT_A := 0.7                         ## m: bok kratownicy masztu anteny
const GALLERY_Z := Vector2(-1.15, -2.05)   ## m: kratownice pomostu obsługi przy dużym maszcie
const BOUGH_CROWN := 5.5                   ## m: korona sosny z konarami zaczyna się tyle nad najwyższym niesionym pomostem (suche dolne konary, korona nad kadrem)

## Tkanka Żyły (mata i spływ narośli): ciemne mięso z grzbietami żył z szumu wartości 3D (grzbiet |2n − 1|), mokre, z poświatą tylko w żyłach,
## pulsującą powoli i z przesunięciem wzdłuż x (jak brama z korzeni w hali, ale bez jednolitej emisji całej bryły).
const TISSUE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_col : source_color = vec3(0.085, 0.032, 0.03);
uniform vec3 vein_col : source_color = vec3(0.2, 0.045, 0.04);
uniform vec3 glow_col : source_color = vec3(0.55, 0.07, 0.04);
uniform float glow = 0.3;
varying vec3 wpos;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = n3(wpos * 6.5) * 0.7 + n3(wpos * 15.0 + 11.0) * 0.3;
	float v = smoothstep(0.86, 0.97, 1.0 - abs(n * 2.0 - 1.0));
	float mot = 0.8 + 0.4 * n3(wpos * 2.1 + 3.0);
	ALBEDO = mix(base_col * mot, vein_col, v);
	ROUGHNESS = mix(0.42, 0.22, v);
	SPECULAR = 0.55;
	float pulse = 0.65 + 0.35 * sin(TIME * 1.4 - wpos.x * 0.8);
	EMISSION = glow_col * v * glow * pulse;
}
"""

## Wstawka do `Level3D.ROCK_SHADER` w miejsce przypisania albedo: mech w plamach na wierzchach (n.y > 0,45), ciemniejsze spody (zacieki, cień ziemi).
## Porosty na licach z szumu wartości dawały kwadratowe plamy („moro”) — odrzucone.
const OUTDOOR_ROCK := """
	float up = smoothstep(0.45, 0.85, n.y);
	float mp = vnoise(wpos.xz * 1.1 + wpos.yy * 0.3) * 0.65 + vnoise(wpos.xz * 2.9 + 3.0) * 0.35;
	vec3 moss = mix(vec3(0.13, 0.14, 0.07), vec3(0.27, 0.28, 0.16), vnoise(wpos.xz * 3.1));
	col = mix(col, moss, up * smoothstep(0.38, 0.70, mp) * 0.8);
	col *= 1.0 - 0.3 * smoothstep(-0.2, -0.7, n.y);
	ALBEDO = col * COLOR.rgb;"""

static var parts: Array = []               ## [AABB, opis] — każdy element ostatniego `build` (test wolnego pasa i wierzchu)
static var _mats := {}
static var _tint := Color.WHITE            ## kolor wierzchołków następnych trójkątów (odcień bloku granitu; shader skały mnoży nim albedo)
static var _colored := {}                  ## SurfaceTool → true: siatki z kolorem wierzchołków (tylko skała; kora ma też wierzchołki `Front3D._cone`)

## Ciąg pomostu zaczynający się w (r, c0): {"r", "c0", "c1" (włącznie), "ch", "x0", "x1", "top" (y wierzchu pokładu)} albo {} bez takiego ciągu.
static func deck_at(rows: Array, r: int, c0: int) -> Dictionary:
	var ch := Level3D._ch(rows, c0, r)
	if not Level3D.is_platform_ch(ch) or Level3D._ch(rows, c0 - 1, r) == ch:
		return {}
	var c1 := c0
	while Level3D._ch(rows, c1 + 1, r) == ch:
		c1 += 1
	return {"r": r, "c0": c0, "c1": c1, "ch": ch, "x0": float(c0) * T, "x1": float(c1 + 1) * T, "top": -float(r) * T}

static func decks_of(rows: Array, entry: Dictionary) -> Array:
	var out: Array = []
	for d in entry.get("decks", []):
		var dd := deck_at(rows, int(d[0]), int(d[1]))
		if not dd.is_empty():
			out.append(dd)
	return out

## y wierzchu pierwszej bryły pod kolumną `c` poniżej wiersza `r` (z pomostami, gdy `decks`).
static func floor_y(rows: Array, c: int, r: int, decks := true) -> float:
	var g := r + 1
	while g < rows.size() and not Level3D.is_solid_ch(Level3D._ch(rows, c, g)) and not (decks and Level3D.is_platform_ch(Level3D._ch(rows, c, g))):
		g += 1
	return -float(g) * T

## Kafle pomostów z wpisów: Vector2i(c, r) → true (`Level3D.set_steps` — bez desek i nóg).
static func cells(rows: Array, steps: Array) -> Dictionary:
	var out := {}
	for e in steps:
		for d in decks_of(rows, e):
			for c in range(int(d["c0"]), int(d["c1"]) + 1):
				out[Vector2i(c, int(d["r"]))] = true
	return out

## Ciągi słupów `w` w kolumnie `c`: [[r0, r1 (wyłącznie)], …] (te same granice co `Level3D.post_runs`).
static func _post_runs_col(rows: Array, c: int) -> Array:
	var out: Array = []
	var r := 0
	while r < rows.size():
		if Level3D._ch(rows, c, r) != "w" and not (Level3D.is_post_cell(rows, c, r) and Level3D._ch(rows, c, r + 1) == "w"):
			r += 1
			continue
		var r1 := r
		while r1 < rows.size() and Level3D.is_post_cell(rows, c, r1):
			r1 += 1
		out.append([r, r1])
		r = r1
	return out

## Słupy, które znikają (wpis "posts"): Vector2i(c, r0 ciągu) → true dla ciągów w kolumnie między pomostem wpisu a podłożem.
static func hidden_posts(rows: Array, steps: Array) -> Dictionary:
	var out := {}
	for e in steps:
		var ds := decks_of(rows, e)
		for c in e.get("posts", []):
			for run in _post_runs_col(rows, int(c)):
				for d in ds:
					var g := -int(round(floor_y(rows, int(c), int(d["r"]), false) / T))
					if int(run[1]) > int(d["r"]) and int(run[0]) <= g:
						out[Vector2i(int(c), int(run[0]))] = true
	return out

## Sosny z konarami (rodzaj "boughs"): ciągi słupów `w` (≥ BOUGH_RUN kafli) w zasięgu BOUGH_REACH od pomostu wpisu → [{"c", "r0", "r1"}].
static func bough_trunks(rows: Array, entry: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for d in decks_of(rows, entry):
		for c in range(int(floor(float(d["c0"]) - BOUGH_REACH)), int(ceil(float(d["c1"]) + BOUGH_REACH)) + 1):
			for run in _post_runs_col(rows, c):
				if int(run[1]) - int(run[0]) >= BOUGH_RUN and int(run[0]) <= int(d["r"]) + 2 and not seen.has(Vector2i(c, int(run[0]))):
					seen[Vector2i(c, int(run[0]))] = true
					out.append({"c": c, "r0": int(run[0]), "r1": int(run[1])})
	return out

## Słupy rysowane jako sosny (`Level3D.set_steps`): Vector2i(c, r0 ciągu) → m, o ile podnieść koronę, żeby zaczynała się BOUGH_CROWN
## nad najwyższym pomostem wpisu (stara sosna z suchymi dolnymi konarami; korona przy pomoście zasłaniała kadr).
static func trunk_cells(rows: Array, steps: Array) -> Dictionary:
	var out := {}
	for e in steps:
		if String(e.get("kind", "")) == "boughs":
			var crown := crown_y(rows, e)
			for t in bough_trunks(rows, e):
				out[Vector2i(int(t["c"]), int(t["r0"]))] = maxf(0.0, crown + float(t["r0"]) * T)
	return out

## y, na którym zaczynają się korony sosen wpisu "boughs".
static func crown_y(rows: Array, entry: Dictionary) -> float:
	var top := -INF
	for d in decks_of(rows, entry):
		top = maxf(top, float(d["top"]))
	return top + BOUGH_CROWN

# --- materiały -------------------------------------------------------------------------------------------------------------

static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"bark", "root":
			var sm := StandardMaterial3D.new()
			if ResourceLoader.exists(BARK_TEX % "diff") and not "--noworldpbr" in OS.get_cmdline_user_args():
				sm.albedo_texture = load(BARK_TEX % "diff")
				var arm := load(BARK_TEX % "arm") as Texture2D
				sm.ao_enabled = true
				sm.ao_texture = arm
				sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				sm.roughness = 1.0
				sm.roughness_texture = arm
				sm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
				sm.normal_enabled = true
				sm.normal_texture = load(BARK_TEX % "nor_gl")
				sm.uv1_triplanar = true
				sm.uv1_world_triplanar = true
				sm.uv1_scale = Vector3.ONE / BARK_TILE
				sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			else:
				sm.roughness = 0.95
			sm.albedo_color = Color(0.62, 0.58, 0.54) if key == "bark" else Color(0.40, 0.34, 0.30)   # kora jak pnie lasu; korzenie ciemniejsze, ziemiste
			m = sm
		"cut":
			var cm := Level3D.make_pbr("plank", 0.8, Color(0.50, 0.40, 0.28), 0.9).duplicate() as StandardMaterial3D
			cm.albedo_color = Color(0.95, 0.82, 0.62)       # świeży przekrój piłą: jaśniejszy od kory
			m = cm
		"soil":
			m = Level3D.terrain_cut_material()
		"turf":
			m = Level3D.make_pbr("terrain", 0.30, Color(0.20, 0.17, 0.14), 0.97, 1.0, 1.0, false, "organic")
		"rock":
			m = Level3D.rock_material()
			if m is ShaderMaterial:                     # granit pod gołym niebem: mech na wierzchach, spody ciemniejsze
				var sm := (m as ShaderMaterial).duplicate() as ShaderMaterial
				var sh := Shader.new()
				sh.code = Level3D.ROCK_SHADER.replace("\tALBEDO = col * COLOR.rgb;", OUTDOOR_ROCK)
				sm.shader = sh
				m = sm
		"plank":
			m = Level3D.make_pbr("plank", 0.8, Color(0.34, 0.24, 0.14), 0.9, 1.0, 1.0, false, "organic")
		"rope":
			m = Level3D.make_mat(Color(0.40, 0.34, 0.22), 0.9)
		"paint":
			m = Level3D.make_mat(Color(0.42, 0.06, 0.04), 0.75)   # farba patrolu, wyblakła
		"metal":
			m = Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust")
		"steel":                                    # wsporniki i opaski ciepłociągu: stal ze rdzą
			var stm := Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.6, 1.0, 0.7, false, "rust").duplicate() as StandardMaterial3D
			stm.albedo_color = Color(0.62, 0.52, 0.44)
			m = stm
		"jacket":                                   # płaszcz izolacji z ocynkowanej blachy, zmatowiały
			var jm := Level3D.make_pbr("metal", 0.40, Color(0.55, 0.57, 0.58), 0.45, 1.0, 0.7, false, "rust").duplicate() as StandardMaterial3D
			jm.albedo_color = Color(1.0, 1.0, 1.0)
			jm.roughness = 0.55
			m = jm
		"wool":
			m = Level3D.make_mat(Color(0.62, 0.55, 0.33), 1.0)   # wata mineralna spod zdartego płaszcza
		"galv":                                     # ocynk: kraty, kratownice, poręcze stacji i anten
			var gm := Level3D.make_pbr("metal", 0.40, Color(0.28, 0.30, 0.34), 0.5, 1.0, 0.7, false, "rust").duplicate() as StandardMaterial3D
			gm.albedo_color = Color(0.82, 0.84, 0.86)
			m = gm
		"hazard":
			m = Level3D.make_mat(Color(0.72, 0.55, 0.10), 0.6)
		"hazard_dark":
			m = Level3D.make_mat(Color(0.05, 0.05, 0.05), 0.7)
		"mast_red":
			m = Level3D.make_mat(Color(0.50, 0.11, 0.07), 0.6)
		"mast_white":
			m = Level3D.make_mat(Color(0.70, 0.69, 0.65), 0.6)
		"porcelain":
			m = Level3D.make_mat(Color(0.74, 0.76, 0.72), 0.25, 0.06, 0.0)
		"transformer":
			m = Level3D.make_mat(Color(0.22, 0.26, 0.18), 0.6)
		"cabinet":
			m = Level3D.make_mat(Color(0.25, 0.30, 0.32), 0.6)
		"wire":
			m = Level3D.make_mat(Color(0.03, 0.03, 0.03), 0.5, 0.06, 0.0)
		"lamp":                                     # lampa przeszkodowa anteny: sama emisja, jak lampy masztu w tle
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(0.3, 0.02, 0.01)
			lm.emission_enabled = true
			lm.emission = Color(1.0, 0.10, 0.04)
			lm.emission_energy_multiplier = 2.0
			m = lm
		"concrete":
			m = Level3D.make_pbr("concrete", 0.33, Color(0.45, 0.45, 0.43), 0.95, 1.0, 1.0, false, "stone")
		"vein", "vein_dark":                        # tkanka Żyły: ciemna, mokra, grzbiety żył z szumu i słaba, pulsująca poświata (`TISSUE_SHADER`)
			var tm := ShaderMaterial.new()
			var tsh := Shader.new()
			tsh.code = TISSUE_SHADER
			tm.shader = tsh
			if key == "vein":
				tm.set_shader_parameter("base_col", Color(0.11, 0.04, 0.035))
			m = tm
	_mats[key] = m
	return m

# --- geometria ---------------------------------------------------------------------------------------------------------------

static func _st(sts: Dictionary, key: String) -> SurfaceTool:
	if not sts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
		if key == "rock":
			_colored[st] = true
	return sts[key]

static func _part(aabb: AABB, what: String) -> void:
	parts.append([aabb.abs(), what])

## Trójkąt widoczny od strony `out` (Godot: przód zgodnie z ruchem wskazówek zegara, czyli normalna z reguły prawej ręki do środka).
static func _tri(st: SurfaceTool, p: Array, n: Array, out: Vector3) -> void:
	var order := [0, 1, 2]
	if ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3)).dot(out) > 0.0:
		order = [0, 2, 1]
	for k in order:
		if _colored.has(st):
			st.set_color(_tint)
		st.set_normal(n[k])
		var v: Vector3 = p[k]
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, [a, b, c], [n, n, n], n)
	_tri(st, [a, c, d], [n, n, n], n)

## Prostopadłościan od rogu `a` do `b`, obrócony `basis` wokół środka.
static func _box(st: SurfaceTool, a: Vector3, b: Vector3, what: String, basis := Basis.IDENTITY) -> void:
	var c := (a + b) * 0.5
	var h := (b - a).abs() * 0.5
	var ax := [basis.x.normalized(), basis.y.normalized(), basis.z.normalized()]
	var corner := func(sx: float, sy: float, sz: float) -> Vector3: return c + ax[0] * h.x * sx + ax[1] * h.y * sy + ax[2] * h.z * sz
	for i in 3:
		for s: float in [-1.0, 1.0]:
			var n: Vector3 = ax[i] * s
			var q: Array = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var k := [0.0, 0.0, 0.0]
				k[i] = s
				k[(i + 1) % 3] = uv.x
				k[(i + 2) % 3] = uv.y
				q.append(corner.call(k[0], k[1], k[2]))
			_quad(st, q[0], q[1], q[2], q[3], n)
	var bb := AABB(c, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				bb = bb.expand(corner.call(sx, sy, sz))
	_part(bb, what)

## Płyta z zaokrąglonymi krawędziami wzdłuż x (przekrój w płaszczyźnie z–y: prostokąt z promieniem `rb`), od x0 do x1.
static func _slab(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, rb: float, what: String) -> void:
	rb = minf(rb, minf((y1 - y0), (z1 - z0)) * 0.45)
	var prof: Array = []                                    # [punkt (z, y), normalna (z, y)]
	var centers := [Vector2(z1 - rb, y1 - rb), Vector2(z0 + rb, y1 - rb), Vector2(z0 + rb, y0 + rb), Vector2(z1 - rb, y0 + rb)]
	for q in 4:
		for s in 4:
			var ang := PI * 0.5 * (float(q) + float(s) / 3.0)
			var nn := Vector2(cos(ang), sin(ang))
			prof.append([(centers[q] as Vector2) + nn * rb, nn])
	var cyz := Vector2((z0 + z1) * 0.5, (y0 + y1) * 0.5)
	for i in prof.size():
		var p0: Vector2 = prof[i][0]
		var p1: Vector2 = prof[(i + 1) % prof.size()][0]
		var n0: Vector2 = prof[i][1]
		var n1: Vector2 = prof[(i + 1) % prof.size()][1]
		var a := Vector3(x0, p0.y, p0.x)
		var b := Vector3(x0, p1.y, p1.x)
		var c := Vector3(x1, p1.y, p1.x)
		var d := Vector3(x1, p0.y, p0.x)
		var na := Vector3(0.0, n0.y, n0.x)
		var nb := Vector3(0.0, n1.y, n1.x)
		var out := Vector3(0.0, (p0.y + p1.y) * 0.5 - cyz.y, (p0.x + p1.x) * 0.5 - cyz.x)
		_tri(st, [a, b, c], [na, nb, nb], out)
		_tri(st, [a, c, d], [na, nb, na], out)
		for e in [[x0, -1.0], [x1, 1.0]]:                   # czoła płyty: wachlarz od środka przekroju
			var nx := Vector3(float(e[1]), 0.0, 0.0)
			_tri(st, [Vector3(float(e[0]), cyz.y, cyz.x), Vector3(float(e[0]), p0.y, p0.x), Vector3(float(e[0]), p1.y, p1.x)], [nx, nx, nx], nx)
	_part(AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0)), what)

## Graniastosłup: wielokąt w płaszczyźnie x–y (przeciwnie do ruchu wskazówek zegara) od z0 do z1.
static func _prism(st: SurfaceTool, poly: PackedVector2Array, z0: float, z1: float, what: String) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		for e in [[z1, 1.0], [z0, -1.0]]:
			var n := Vector3(0.0, 0.0, float(e[1]))
			var tri: Array = []
			for k in 3:
				tri.append(Vector3(poly[idx[i + k]].x, poly[idx[i + k]].y, float(e[0])))
			_tri(st, tri, [n, n, n], n)
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var e := (p1 - p0).normalized()
		var n := Vector3(e.y, -e.x, 0.0)                    # na zewnątrz wielokąta przeciwnie do ruchu wskazówek zegara
		_quad(st, Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1), n)
	var bb := AABB(Vector3(poly[0].x, poly[0].y, z0), Vector3.ZERO)
	for p in poly:
		bb = bb.expand(Vector3(p.x, p.y, z0)).expand(Vector3(p.x, p.y, z1))
	_part(bb, what)

## Stożek ścięty od `a` do `b` (promienie ra → rb) z nierówną korą (`Front3D._cone`).
static func _cone(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, what: String, seg := 10, rough := 0.03, ph := 0.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.005:
		return
	Front3D._cone(st, a, d, length, ra, rb, seg, maxi(1, int(ceil(length / 0.6))), Vector2(0.0, length / BARK_TILE), 1.0, rough, ph)
	var ax := d / length                                    # obwiednia: okręgi końców prostopadłe do osi (konar poziomy ma wierzch równo z osią + r)
	var ext := Vector3(sqrt(maxf(0.0, 1.0 - ax.x * ax.x)), sqrt(maxf(0.0, 1.0 - ax.y * ax.y)), sqrt(maxf(0.0, 1.0 - ax.z * ax.z))) * (1.0 + rough)
	var bb := AABB(a - ext * ra, ext * ra * 2.0).merge(AABB(b - ext * rb, ext * rb * 2.0))
	_part(bb, what)

## Krążek (przekrój kłody, talerz korzeniowy) w `c` o normalnej `n`.
static func _disc(st: SurfaceTool, c: Vector3, n: Vector3, r: float, seg := 14, wob := 0.0) -> void:
	var nn := n.normalized()
	var s := nn.cross(Vector3.UP)
	if s.length() < 0.1:
		s = nn.cross(Vector3.RIGHT)
	s = s.normalized()
	var u := nn.cross(s).normalized()
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var r0 := r * (1.0 + wob * sin(a0 * 3.0 + 1.3))
		var r1 := r * (1.0 + wob * sin(a1 * 3.0 + 1.3))
		_tri(st, [c, c + (s * cos(a0) + u * sin(a0)) * r0, c + (s * cos(a1) + u * sin(a1)) * r1], [nn, nn, nn], nn)

## Krzywa Catmulla-Roma przez punkty `pts` (`k` próbek na odcinek).
static func _crom(pts: Array, k: int) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for j in k:
			var t := float(j) / float(k)
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 1])
	return out

## Rura po krzywej (korzeń, lina): promień liniowo r0 → r1.
static func _tube(st: SurfaceTool, pts: Array, r0: float, r1: float, what: String, seg := 6) -> void:
	for i in pts.size() - 1:
		var f0 := float(i) / float(pts.size() - 1)
		var f1 := float(i + 1) / float(pts.size() - 1)
		_cone(st, pts[i], pts[i + 1], lerpf(r0, r1, f0), lerpf(r0, r1, f1), what, seg, 0.0)

## Blok granitu: prostopadłościan a–b z zaokrąglonymi krawędziami i narożnikami (promień `rb`), obrócony `basis` wokół środka, z nierównością
## wzdłuż normalnej (`bump` — część promienia). `flat_top`: wierzch zostaje płaski i nie wychodzi ponad b.y (po nim się chodzi).
static func _rbox(st: SurfaceTool, a: Vector3, b: Vector3, rb: float, what: String, basis := Basis.IDENTITY, bump := 0.0, flat_top := false, seed := 0.0) -> void:
	var c := (a + b) * 0.5
	var h := (b - a).abs() * 0.5
	rb = clampf(rb, 0.005, minf(h.x, minf(h.y, h.z)) * 0.95)
	var inner := h - Vector3.ONE * rb
	var at := func(q: Vector3) -> Array:                   # punkt siatki ściany sześcianu → [punkt, normalna] na bryle
		var k := q.clamp(-inner, inner)
		var dv := q - k
		var nrm := dv.normalized() if dv.length() > 0.0001 else Vector3.UP
		var v := k + nrm * rb
		if bump > 0.0 and not (flat_top and nrm.y > 0.999):
			var w := sin(v.x * 2.3 + seed) * sin(v.y * 1.9 + seed * 1.7) * sin(v.z * 2.9 + seed * 0.6) + 0.35 * sin(v.x * 6.1 - v.z * 4.7 + seed * 3.1)
			v += nrm * w * bump * rb
		if flat_top:
			v.y = minf(v.y, h.y)
		return [c + basis * v, (basis * nrm).normalized()]
	var axis_s := func(hh: float, ii: float) -> Array:      # próbki wzdłuż osi: strefa zaokrąglenia gęściej, środek ściany rzadziej
		var e := hh - ii
		return [-hh, -(ii + 0.62 * e), -(ii + 0.22 * e), -ii, -ii / 3.0, ii / 3.0, ii, ii + 0.22 * e, ii + 0.62 * e, hh]
	for i in 3:
		var j := (i + 1) % 3
		var k := (i + 2) % 3
		var sj: Array = axis_s.call(h[j], inner[j])
		var sk: Array = axis_s.call(h[k], inner[k])
		for s: float in [-1.0, 1.0]:
			var out := basis * (Vector3(1.0 if i == 0 else 0.0, 1.0 if i == 1 else 0.0, 1.0 if i == 2 else 0.0) * s)
			var grid: Array = []
			for u in sj:
				var row: Array = []
				for w in sk:
					var q := Vector3.ZERO
					q[i] = h[i] * s
					q[j] = u
					q[k] = w
					row.append(at.call(q))
				grid.append(row)
			for u in sj.size() - 1:
				for w in sk.size() - 1:
					var p := [grid[u][w], grid[u + 1][w], grid[u + 1][w + 1], grid[u][w + 1]]
					_tri(st, [p[0][0], p[1][0], p[2][0]], [p[0][1], p[1][1], p[2][1]], out)
					_tri(st, [p[0][0], p[2][0], p[3][0]], [p[0][1], p[2][1], p[3][1]], out)
	var bb := AABB(c, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				bb = bb.expand(c + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
	bb = bb.grow(bump * rb * 1.35)
	if flat_top:
		bb.size.y = minf(bb.end.y, c.y + h.y) - bb.position.y
	_part(bb, what)

## Kamień (granit) w pudle a–b: zaokrąglony blok, lekko przechylony, z nierównością.
static func _rock(sts: Dictionary, a: Vector3, b: Vector3, rng: RandomNumberGenerator, what: String, round_f := Vector2(0.28, 0.42)) -> void:
	var size := (b - a).abs()
	var rb := minf(size.x, minf(size.y, size.z)) * rng.randf_range(round_f.x, round_f.y)
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.06, 0.06), rng.randf_range(-0.04, 0.04)))
	_tint = _granite_tint(rng)
	_rbox(_st(sts, "rock"), a, b, rb, what, basis, 0.35, false, rng.randf() * 10.0)
	_tint = Color.WHITE

## Odcień bloku granitu: jaśniejszy lub ciemniejszy, raz cieplejszy (żelaziste zacieki), raz chłodniejszy.
static func _granite_tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(0.82, 1.12)
	var warm := rng.randf_range(-0.05, 0.07)
	return Color(v * (1.0 + warm), v, v * (1.0 - warm))

## Sosna z modelu lasu (`Level3D.TRUNK_MODELS`) o wysokości `h`, podstawa w `foot`; z `crown_y` wysokość tak, by korona zaczynała się na tej wysokości.
static func _pine(models: Dictionary, foot: Vector3, h: float, seed: int, crown_y := NAN) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pick: Array = Level3D.TRUNK_MODELS[rng.randi() % Level3D.TRUNK_MODELS.size()]
	var tk: String = pick[0]
	if Level3D.model_mesh(tk).is_empty():
		return
	if not is_nan(crown_y):
		h = (crown_y - foot.y) / float(pick[1])
	var sw := h / 100.0 * Level3D.TRUNK_W * rng.randf_range(0.9, 1.1)
	var basis := Basis().scaled(Vector3(1.0, 1.0, Level3D.TRUNK_DEPTH)) * Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sw, h / 100.0, sw))
	if not models.has(tk):
		models[tk] = []
	var v := rng.randf_range(0.85, 1.05)
	(models[tk] as Array).append([Transform3D(basis, foot + Vector3(0.0, -0.15, 0.0)), Color(v, v * 0.98, v * 0.95)])

# --- rodzaje -----------------------------------------------------------------------------------------------------------------

## Podmyta skarpa: bryła ziemi za pasem gry z płaskim wierzchem na wysokości pokładu, nawis darni na korzeniach do z ≈ +0,7,
## korzenie zwisają spod nawisu (w pasie gry nie niżej niż ROOT_CLEAR nad ścieżką) i po licu skarpy; na górze sosny.
static func _bank(sts: Dictionary, models: Dictionary, rows: Array, d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + int(d["c0"]) * 31 + int(d["r"])
	var x0: float = d["x0"]
	var x1: float = d["x1"]
	var top: float = d["top"]
	var yg := floor_y(rows, int((int(d["c0"]) + int(d["c1"])) / 2), int(d["r"]), false)
	var h := top - yg
	var z_face := -0.95
	var poly := PackedVector2Array([Vector2(x0 - 3.0, yg - 0.4), Vector2(x1 + 3.0, yg - 0.4), Vector2(x1 + 3.0, yg + 0.05), Vector2(x1 + 1.6, yg + h * 0.45),
		Vector2(x1 + 0.5, top - 0.4), Vector2(x1 - 0.3, top - 0.04), Vector2(x0 + 0.3, top - 0.04), Vector2(x0 - 0.5, top - 0.3),
		Vector2(x0 - 1.5, yg + h * 0.5), Vector2(x0 - 3.0, yg + 0.05)])
	_prism(_st(sts, "soil"), poly, -6.5, z_face, "bank")
	_box(_st(sts, "turf"), Vector3(x0 - 0.2, top - 0.16, -6.5), Vector3(x1 + 0.2, top, z_face + 0.02), "bank turf")
	var n := int(ceil((x1 - x0) / 0.55))
	for i in n:                                             # nawis: darń na wierzchu, pod nią warstwa ziemi przerośnięta korzeniami
		var a := x0 + float(i) * (x1 - x0) / float(n)
		var b := a + (x1 - x0) / float(n)
		var zf := rng.randf_range(0.62, 0.78)
		var th := rng.randf_range(0.28, 0.55)
		_box(_st(sts, "turf"), Vector3(a, top - 0.16, z_face - 0.05), Vector3(b, top, zf), "bank lip")
		_box(_st(sts, "soil"), Vector3(a + 0.03, top - 0.16 - th, z_face - 0.05), Vector3(b - 0.03, top - 0.16, zf - 0.15 - rng.randf() * 0.25), "bank lip soil")
	for i in 34:                                            # korzenie spod nawisu
		var x := rng.randf_range(x0 + 0.1, x1 - 0.1)
		var z := rng.randf_range(z_face + 0.05, 0.7)
		var y := top - rng.randf_range(0.45, 0.7)
		var fy := floor_y(rows, int(x / T), int(d["r"]))
		var lo := fy + (ROOT_CLEAR if absf(z) < STRIP + 0.2 else 1.2)
		var ye := maxf(lo, y - rng.randf_range(0.3, 2.6))
		if ye >= y - 0.1:
			continue
		var pts := _crom([Vector3(x, y, z), Vector3(x + rng.randf_range(-0.2, 0.2), (y + ye) * 0.5, z + rng.randf_range(-0.12, 0.12)),
			Vector3(x + rng.randf_range(-0.3, 0.3), ye, z + rng.randf_range(-0.12, 0.12))], 3)
		for p in pts.size():                                # krzywa nie schodzi poniżej końca (w pasie gry — poniżej ROOT_CLEAR)
			pts[p] = Vector3(pts[p].x, maxf(pts[p].y, ye), clampf(pts[p].z, z_face, 0.78))
		_tube(_st(sts, "root"), pts, rng.randf_range(0.02, 0.045), 0.006, "bank root")
	for i in 9:                                             # grube korzenie po licu skarpy do podłoża
		var x := rng.randf_range(x0 - 0.5, x1 + 0.5)
		var fy := floor_y(rows, int(x / T), int(d["r"]), false)
		_tube(_st(sts, "root"), _crom([Vector3(x, top - 0.45, z_face - 0.02), Vector3(x + rng.randf_range(-0.5, 0.5), (top + fy) * 0.5, z_face - 0.08 - rng.randf() * 0.25),
			Vector3(x + rng.randf_range(-0.8, 0.8), fy + 0.05, z_face - 0.4 - rng.randf())], 4), rng.randf_range(0.05, 0.09), 0.02, "bank face root")
	for i in 7:                                             # kamienie w licu
		var x := rng.randf_range(x0 - 1.0, x1 + 1.0)
		var y := yg + rng.randf_range(0.3, maxf(0.4, h - 1.2))
		_rock(sts, Vector3(x, y, z_face - 0.3), Vector3(x + rng.randf_range(0.3, 0.7), y + rng.randf_range(0.25, 0.5), z_face + 0.08), rng, "bank stone")
	_pine(models, Vector3((x0 + x1) * 0.5 + 0.8, top, -3.6), 15.0, int(d["c0"]) * 7 + 1)
	_pine(models, Vector3(x0 - 0.3, yg + h * 0.62, -4.8), 13.0, int(d["c0"]) * 7 + 2)

## Wykrot: dwupienny świerk wyrwany z talerzem korzeniowym (w głębi, z ≈ −3,5), pnie leżą w poprzek ścieżki na głazie za pasem gry,
## czubki odpiłowane przez patrol tuż przed przodem pokładu. Wierzch pni na wysokości pokładu, spód w pasie gry nad CLEAR.
static func _windfall(sts: Dictionary, models: Dictionary, rows: Array, d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + int(d["c0"]) * 13
	var x0: float = d["x0"]
	var x1: float = d["x1"]
	var top: float = d["top"]
	var xm := (x0 + x1) * 0.5
	var yg := floor_y(rows, int(xm / T), int(d["r"]), false)
	var fy := floor_y(rows, int(xm / T), int(d["r"]))
	var r := clampf((top - fy - CLEAR) * 0.5 / 1.12, 0.18, 0.34)       # pień na całej długości pasa gry nad CLEAR (zapas na korę i zbieżystość)
	var zb := -3.3
	var zs := -1.5
	var zf := 0.85
	var logs := [[x0 + 0.68 * (x1 - x0) / (2.0 * T), r, -1.0], [x1 - 0.66 * (x1 - x0) / (2.0 * T), r * 0.92, 1.0]]
	var ybmax := -INF
	for lg in logs:
		var x: float = lg[0]
		var rr: float = lg[1]
		var s: float = lg[2]
		var r_s := rr * 1.05
		var yb := top - rr * 1.15 + 0.1
		ybmax = maxf(ybmax, yb)
		_cone(_st(sts, "bark"), Vector3(x - 0.1 * s, yb, zb), Vector3(x, top - r_s, zs), rr * 1.15, r_s, "windfall log", 12)
		var prev := Vector3(x, top - r_s, zs)
		for k in range(1, 5):                               # od głazu do przekroju: wierzch równo z pokładem (oś niżej o promień)
			var f := float(k) / 4.0
			var rk := lerpf(r_s, rr * 0.95, f)
			var p := Vector3(x, top - rk, lerpf(zs, zf, f))
			_cone(_st(sts, "bark"), prev, p, lerpf(r_s, rr * 0.95, float(k - 1) / 4.0), rk, "windfall log", 12)
			prev = p
		_disc(_st(sts, "cut"), prev, Vector3.BACK, rr * 0.95)
		for i in 3:                                         # sęki i kikuty gałęzi w głębi
			var z := rng.randf_range(zb + 0.4, zs - 0.3)
			var y := lerpf(yb, top - r_s, (z - zb) / (zs - zb))
			var p0 := Vector3(x + s * rr * 0.8, y, z)
			_cone(_st(sts, "bark"), p0, p0 + Vector3(s * rng.randf_range(0.35, 0.7), rng.randf_range(0.1, 0.35), rng.randf_range(-0.2, 0.2)), 0.05, 0.02, "windfall stub", 6)
	var rp := clampf((top - yg) * 0.75, 1.3, 2.3)                  # talerz korzeniowy: spód w ziemi, pnie wychodzą z jego lica
	var pc := Vector3(xm, yg + rp - 0.45, zb - 0.35)
	_cone(_st(sts, "soil"), pc + Vector3(0.0, 0.0, -0.3), Vector3.BACK * 0.6 + pc + Vector3(0.0, 0.0, -0.3), rp * 0.92, rp, "windfall plate", 18, 0.1, 1.7)
	_disc(_st(sts, "soil"), pc + Vector3(0.0, 0.0, 0.3), Vector3.BACK, rp, 18, 0.06)
	for i in 16:
		var a := TAU * float(i) / 16.0 + rng.randf_range(-0.1, 0.1)
		var c := pc + Vector3(cos(a) * rp, sin(a) * rp, 0.25)
		if c.y < yg + 0.1:
			continue
		var e := c + Vector3(cos(a) * rng.randf_range(0.5, 1.2), sin(a) * rng.randf_range(0.4, 0.9), rng.randf_range(-0.3, 0.2))
		e.y = maxf(e.y, yg + 0.05)
		_tube(_st(sts, "root"), _crom([c, c.lerp(e, 0.5) + Vector3(0.0, 0.12, 0.08), e], 2), rng.randf_range(0.03, 0.06), 0.01, "windfall root")
	var y_rest := top - 2.0 * r * 1.05 * 1.03                      # głaz pod pniami za pasem gry
	_rock(sts, Vector3(x0 - 0.15, yg - 0.25, -2.25), Vector3(x1 + 0.15, y_rest, -STRIP - 0.55), rng, "windfall rock")

## Ostaniec granitowy (wietrzenie „materacowe”): płyty o zaokrąglonych krawędziach i różnej grubości z wierzchem na wysokości pokładu
## wystają nad ścieżką; pod nimi i za nimi masa bloków za pasem gry z przesuniętymi spoinami; za niższymi stopniami garb skały do wysokości
## następnego, więc ostaniec czyta się jako jedna bryła, a nie schody z kolumn; na szczycie i u stóp luźne głazy. Mech na wierzchach (`OUTDOOR_ROCK`).
## `cache`: na szczycie nisza ze skrytką `H` pod nawisem (za pasem gry), lina patrolu na haku po płytach w dół i czerwona strzałka na najniższej płycie.
static func _tor(sts: Dictionary, models: Dictionary, rows: Array, ds: Array, cache: bool) -> void:
	if ds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23 + int(ds[0]["c0"]) * 17
	var st := _st(sts, "rock")
	var sorted := ds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["top"]) < float(b["top"]))     # od najniższego
	var lo: Dictionary = sorted[0]
	var hi: Dictionary = sorted[sorted.size() - 1]
	var arrow := {}                                         # płyta pod strzałkę patrolu: najniższa, pierwsza z lewej
	for di in sorted.size():
		var d: Dictionary = sorted[di]
		var r := int(d["r"])
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var yg := floor_y(rows, int((int(d["c0"]) + int(d["c1"])) / 2), r, false)
		var width := x1 - x0
		var n := 1 if width < 3.0 else (2 if width < 4.8 else 3)
		var cuts: Array = [x0 + 0.01]
		for k in range(1, n):
			cuts.append(x0 + width * (float(k) / float(n) + rng.randf_range(-0.12, 0.12)))
		cuts.append(x1 - 0.01)
		var slab_low := top
		for k in n:                                         # płyty wierzchu
			var a: float = float(cuts[k]) + (0.025 if k > 0 else 0.0)
			var b: float = float(cuts[k + 1]) - (0.025 if k < n - 1 else 0.0)
			var low := k == 0 and di == 0 and cache
			var rb := rng.randf_range(0.15, 0.22)
			var bump := 0.06 if low else 0.3
			var grow := bump * rb * 1.35 + 0.08               # obwiednia z nierównością i skrętem
			var fy := -INF                                  # najwyższy poziom chodzenia pod płytą (bez kolumn zbocza, w których leży pomost)
			for c in range(int(floor((a - grow) / T)), int(floor((b + grow) / T)) + 1):
				if Level3D.is_solid_ch(Level3D._ch(rows, c, r)):
					continue
				fy = maxf(fy, floor_y(rows, c, r))
			var y0 := maxf(top - rng.randf_range(0.42, 0.74), fy + CLEAR + 0.03 + grow)
			var zb := -1.0 - rng.randf() * 0.3
			var zf := 0.7 + rng.randf() * 0.14
			var yaw := Basis.IDENTITY if low else Basis(Vector3.UP, rng.randf_range(-0.035, 0.035))
			_tint = _granite_tint(rng)
			_rbox(st, Vector3(a, y0, zb), Vector3(b, top, zf), rb, "tor slab", yaw, bump, true, rng.randf() * 10.0)
			_tint = Color.WHITE
			slab_low = minf(slab_low, y0)
			if low:
				arrow = {"x": a, "y0": y0, "top": top, "zf": zf}
		var y := yg - 0.25                                  # masa pod płytami za pasem gry: rzędy bloków, spoiny przesunięte
		while y < slab_low - 0.3:
			var hh := rng.randf_range(0.9, 1.8)
			if slab_low - 0.02 - (y + hh) < 0.5:
				hh = slab_low - 0.02 - y
			var xa := x0 - 0.45 - rng.randf() * 0.6
			while xa < x1 + 0.4:
				var wb := rng.randf_range(2.4, 4.6)
				if x1 + 0.5 - (xa + wb) < 1.4:
					wb = x1 + 0.5 - xa
				_rock(sts, Vector3(xa + 0.03, y, -2.6 - rng.randf() * 1.6), Vector3(xa + wb - 0.03, y + hh, -0.92 - rng.randf() * 0.55), rng, "tor mass",
					Vector2(0.4, 0.5))
				xa += wb
			y += hh * rng.randf_range(0.9, 0.97)
		if di + 1 < sorted.size():                          # garb za stopniem do wysokości następnego: jedna bryła zamiast schodów
			var up: Dictionary = sorted[di + 1]
			var yb := top - 0.6
			var yt: float = float(up["top"]) - rng.randf_range(0.15, 0.5)
			var xa2 := x0 + rng.randf_range(0.2, 0.8)
			var xb2: float = maxf(xa2 + 1.4, float(up["x0"]) + 0.6)
			while yb < yt - 0.3:
				var hh := minf(rng.randf_range(0.8, 1.6), yt - yb)
				_rock(sts, Vector3(xa2, yb, -4.6 - rng.randf() * 0.8), Vector3(xb2, yb + hh, -2.2 - rng.randf() * 0.5), rng, "tor mound", Vector2(0.4, 0.5))
				yb += hh * 0.92
				xa2 += rng.randf_range(0.2, 0.7)                    # garb zwęża się ku górze
	var ht: float = hi["top"]
	var hx0: float = hi["x0"]
	var hx1: float = hi["x1"]
	var xh := (hx0 + hx1) * 0.5
	for c in range(int(hi["c0"]), int(hi["c1"]) + 1):       # skrytka `H` nad szczytem
		if Level3D._ch(rows, c, int(hi["r"]) - 1) == "H":
			xh = (float(c) + 0.5) * T
	if cache:                                               # nisza: tylna ściana, boki, nawis; wnętrze otwarte ku kamerze
		_rock(sts, Vector3(xh - 1.3, ht - 0.1, -4.6), Vector3(xh + 1.3, ht + 2.5, -3.0), rng, "tor cache")
		_rock(sts, Vector3(xh - 2.6, ht - 0.1, -3.5), Vector3(xh - 0.85, ht + rng.randf_range(2.1, 2.6), -1.0), rng, "tor cache")
		_rock(sts, Vector3(xh + 0.85, ht - 0.1, -3.5), Vector3(xh + 2.5, ht + rng.randf_range(2.1, 2.6), -1.0), rng, "tor cache")
		_tint = _granite_tint(rng)
		_rbox(st, Vector3(xh - 2.3, ht + 2.25, -3.9), Vector3(xh + 2.6, ht + 2.95, -STRIP - 0.5), 0.25, "tor overhang",
			Basis(Vector3.BACK, rng.randf_range(-0.04, 0.04)), 0.35, false, rng.randf() * 10.0)
		_tint = Color.WHITE
	elif _free_above(rows, hi, 3):                          # luźne głazy na szczycie (bez mostu tuż nad nim)
		for k in 2:
			var xk := lerpf(hx0, hx1, 0.25 + 0.5 * float(k)) + rng.randf_range(-0.4, 0.4)
			var s := rng.randf_range(0.9, 1.5)
			_rock(sts, Vector3(xk - s * 0.6, ht - 0.15, -2.2 - s), Vector3(xk + s * 0.6, ht + s * 0.8, -1.4), rng, "tor top")
	for k in 3:                                             # głazy u stóp (osypane z ostańca), za pasem gry
		var left := k != 1
		var xk: float = (float(lo["x0"]) - rng.randf_range(0.4, 1.6)) if left else (hx1 + rng.randf_range(0.3, 1.4))
		var gy := floor_y(rows, int(xk / T), int(lo["r"]) if left else int(hi["r"]), false)
		var s := rng.randf_range(0.45, 1.0)
		_rock(sts, Vector3(xk - s * 0.6, gy - 0.2, -1.0 - s * 1.4 - rng.randf()), Vector3(xk + s * 0.6, gy + s * 0.75, -1.0 - rng.randf() * 0.4), rng, "tor boulder")
	if not cache:
		return
	var hook := Vector3(hx0 + 0.35, ht + 0.35, -1.0)
	_cone(_st(sts, "metal"), hook, hook + Vector3(0.0, 0.0, -0.3), 0.03, 0.03, "tor hook", 6, 0.0)
	var pts: Array = [hook + Vector3(0.0, -0.02, 0.0)]
	for i in range(sorted.size() - 2, -1, -1):
		pts.append(Vector3(float(sorted[i]["x1"]) - 0.4, float(sorted[i]["top"]) + 0.03, -1.0))
	var gy := floor_y(rows, int((float(lo["x0"]) - 0.8) / T), int(lo["r"]), false)
	pts.append(Vector3(float(lo["x0"]) + 0.2, (float(lo["top"]) + gy) * 0.5, -1.02))
	pts.append(Vector3(float(lo["x0"]) - 0.8, gy + 0.03, -1.2))
	_tube(_st(sts, "rope"), _crom(pts, 8), 0.022, 0.022, "tor rope", 5)
	if arrow.is_empty():
		return
	var ax: float = float(arrow["x"]) + 0.35                # strzałka patrolu na czole najniższej płyty (w prawo i w górę, ku linie)
	var ay: float = (float(arrow["y0"]) + float(arrow["top"])) * 0.5
	var az: float = float(arrow["zf"]) + 0.02
	var ab := Basis(Vector3.BACK, 0.5)
	_box(_st(sts, "paint"), Vector3(ax, ay - 0.035, az - 0.002), Vector3(ax + 0.5, ay + 0.035, az + 0.002), "tor arrow", ab)
	var tip := Vector3(ax + 0.25, ay, az) + ab * Vector3(0.25, 0.0, 0.0)
	for s in [1.0, -1.0]:
		var hb := Basis(Vector3.BACK, 0.5 + s * 2.4)
		var c := tip + hb * Vector3(0.11, 0.0, 0.0)
		_box(_st(sts, "paint"), c - Vector3(0.12, 0.03, 0.002), c + Vector3(0.12, 0.03, 0.002), "tor arrow", hb)
	_pine(models, Vector3(hx1 + 0.6, ht - 0.5, -3.4), 9.0, int(hi["c0"]) * 5 + 3)

## Nad pomostem `d` przez `n` wierszy nie ma bryły ani innego pomostu.
static func _free_above(rows: Array, d: Dictionary, n: int) -> bool:
	for r in range(int(d["r"]) - n, int(d["r"])):
		for c in range(int(d["c0"]) - 1, int(d["c1"]) + 2):
			var ch := Level3D._ch(rows, c, r)
			if Level3D.is_solid_ch(ch) or Level3D.is_platform_ch(ch):
				return false
	return true

## Ciepłociąg (Obiekt 86, wieczna zmarzlina — rury grzewcze nad ziemią): pod każdym pomostem wpisu jedna rura w płaszczu z blachy
## (⌀ HEAT_R × 2) na wspornikach Γ — słup za pasem gry, ramię nad głową w poprzek pasa; robotnicy położyli na rurze łaty i poprzeczne deski
## (wierzch na wysokości pokładu). Przy końcach pomostu rura skręca kolanem w głąb i schodzi pionem do magistrali biegnącej za placem
## na betonowych podporach — każdy pomost to U-pętla kompensacyjna nad drogą. Płaszcz z opaskami co ok. 1 m, gdzieniegdzie zdarty do waty.
static func _heat(sts: Dictionary, rows: Array, ds: Array) -> void:
	if ds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 + int(ds[0]["c0"]) * 19
	var sorted := ds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["top"]) > float(b["top"]))     # od najwyższego: słupy wyższych pomostów niosą też niższe ramiona
	var posts: Array = []                                   # [x, y wierzchu słupa]
	var runs: Array = []                                    # x odcinków rury w głąb (słup nie może przez nie przechodzić)
	for d: Dictionary in sorted:
		runs.append_array([float(d["x0"]) + 0.02, float(d["x1"]) - 0.02])
	var main_x := Vector2(INF, -INF)
	var main_y := -INF
	for d: Dictionary in sorted:
		var r := int(d["r"])
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var yb := top - 0.045                               # spód desek
		var yl := yb - 0.07                                 # spód łat
		var yc := yl - sqrt(HEAT_R * HEAT_R - 0.12 * 0.12)  # oś rury: łaty w z = ±0,12 leżą na płaszczu
		var arm_top := yc - HEAT_R
		var arm_bot := arm_top - 0.11
		var yg := floor_y(rows, int((int(d["c0"]) + int(d["c1"])) / 2), r, false)
		main_x = Vector2(minf(main_x.x, x0), maxf(main_x.y, x1))
		main_y = maxf(main_y, yg)
		var x := x0 + 0.02                                  # deski w poprzek, z przerwami
		while x < x1 - 0.05:
			var w := minf(rng.randf_range(0.17, 0.24), x1 - 0.02 - x)
			var bz := Vector2(-0.6 - rng.randf() * 0.06, 0.52 + rng.randf() * 0.08)
			_box(_st(sts, "plank"), Vector3(x, yb, bz.x), Vector3(x + w, top, bz.y), "heat board", Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)))
			x += w + rng.randf_range(0.015, 0.04)
		for zl in [-0.12, 0.12]:                            # łaty wzdłuż pomostu
			_box(_st(sts, "plank"), Vector3(x0 + 0.03, yl, zl - 0.04), Vector3(x1 - 0.03, yb, zl + 0.04), "heat batten")
		var xa := x0 + 0.5                                  # rura: prosto pod pomostem, kolana w głąb w jego obrysie
		var xe := x1 - 0.5
		var zb := -2.4
		var gaps: Array = []                                # zdarty płaszcz: [x0, x1]
		if xe - xa > 3.0:
			var g := rng.randf_range(xa + 0.8, xe - 1.2)
			gaps.append(Vector2(g, g + rng.randf_range(0.35, 0.6)))
		_pipe_run(sts, Vector3(xa, yc, 0.0), Vector3(xe, yc, 0.0), gaps)
		for e in [[xa, -1.0], [xe, 1.0]]:
			var xk: float = e[0]
			var s: float = e[1]
			var bend := _crom([Vector3(xk, yc, 0.0), Vector3(xk + s * 0.3, yc, -0.12), Vector3(xk + s * 0.48, yc, -0.5)], 6)
			_tube(_st(sts, "jacket"), bend, HEAT_R, HEAT_R, "heat elbow", 16)
			_pipe_run(sts, Vector3(xk + s * 0.48, yc, -0.5), Vector3(xk + s * 0.48, yc, zb + 0.5), [])
			var drop := _crom([Vector3(xk + s * 0.48, yc, zb + 0.5), Vector3(xk + s * 0.48, yc - 0.12, zb + 0.12), Vector3(xk + s * 0.48, yc - 0.5, zb)], 6)
			_tube(_st(sts, "jacket"), drop, HEAT_R, HEAT_R, "heat elbow", 16)
			_pipe_run(sts, Vector3(xk + s * 0.48, yc - 0.5, zb), Vector3(xk + s * 0.48, yg + HEAT_MAIN_Y, zb), [])
		var n := maxi(2, int(ceil((x1 - x0 - 1.4) / HEAT_SPAN)) + 1)   # wsporniki Γ
		for i in n:
			var xp := lerpf(x0 + 0.7, x1 - 0.7, float(i) / float(n - 1)) + rng.randf_range(-0.1, 0.1)
			for rx: float in runs:
				if absf(rx - xp) < 0.45:
					xp = rx + (0.45 if xp >= rx else -0.45)
			var shared := false
			for p in posts:
				if absf(float(p[0]) - xp) < 0.6:
					xp = float(p[0])
					shared = true
			var ok := false
			for dx: float in [0.0, 0.6, -0.6, 1.1, -1.1]:          # ramię nad głową: obok skrzyni czy rekwizytu pod pomostem
				var xt := xp + dx
				if shared and dx != 0.0 or xt < x0 + 0.3 or xt > x1 - 0.3:
					continue
				var fy := -INF
				for c in range(int(floor((xt - 0.1) / T)), int(floor((xt + 0.1) / T)) + 1):
					if not _cramped(rows, c, r):
						fy = maxf(fy, floor_y(rows, c, r))
				if arm_bot >= fy + CLEAR + 0.03:
					xp = xt
					ok = true
					break
			if not ok:
				continue
			var steel := _st(sts, "steel")
			_box(steel, Vector3(xp - 0.06, arm_bot, -1.24), Vector3(xp + 0.06, arm_top, HEAT_R + 0.05), "heat arm")
			_box(steel, Vector3(xp - 0.07, arm_top, -0.14), Vector3(xp + 0.07, arm_top + 0.05, 0.14), "heat saddle")
			var brace_a := Vector3(xp, arm_bot - 0.75, -1.16)
			_cone(steel, brace_a, Vector3(xp, arm_bot - 0.02, -0.58), 0.035, 0.035, "heat brace", 6, 0.0)
			if not shared:
				var ygp := floor_y(rows, int(xp / T), r, false)
				_box(steel, Vector3(xp - 0.07, ygp, -1.23), Vector3(xp + 0.07, arm_top, -1.09), "heat post")
				_box(_st(sts, "concrete"), Vector3(xp - 0.22, ygp - 0.05, -1.4), Vector3(xp + 0.22, ygp + 0.18, -0.92), "heat footing")
				posts.append([xp, arm_top])
	var ym := main_y + HEAT_MAIN_Y                           # magistrala za placem na betonowych podporach
	_pipe_run(sts, Vector3(main_x.x - 1.5, ym, -2.4), Vector3(main_x.y + 1.5, ym, -2.4), [])
	var xs := main_x.x - 1.0
	while xs < main_x.y + 1.0:
		var gy := floor_y(rows, int(xs / T), int(ds[0]["r"]), false)
		_box(_st(sts, "concrete"), Vector3(xs - 0.2, gy - 0.05, -2.75), Vector3(xs + 0.2, ym - HEAT_R + 0.02, -2.05), "heat sleeper")
		xs += rng.randf_range(3.6, 4.4)

## Odcinek rury w płaszczu od `a` do `b` z opaskami co ok. 1 m; `gaps` (Vector2 x0–x1, tylko odcinki wzdłuż x) — płaszcz zdarty, widać watę.
static func _pipe_run(sts: Dictionary, a: Vector3, b: Vector3, gaps: Array) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var segs: Array = [[0.0, 1.0]]
	for g: Vector2 in gaps:
		var f0 := (g.x - a.x) / d.x
		var f1 := (g.y - a.x) / d.x
		segs = [[0.0, f0], [f1, 1.0]]
		var wc := a + d * f0
		_cone(_st(sts, "wool"), wc, a + d * f1, HEAT_R * 0.93, HEAT_R * 0.9, "heat wool", 12, 0.12)
		for k in 3:                                         # strzępy płaszcza i waty na brzegach
			var t := f0 if k < 2 else f1
			var p := a + d * t
			_cone(_st(sts, "wool"), p, p + Vector3(0.0, -0.1 - 0.08 * float(k), 0.12 * float(k - 1)), 0.06, 0.02, "heat wool", 5, 0.2)
	for sg in segs:
		_cone(_st(sts, "jacket"), a + d * float(sg[0]), a + d * float(sg[1]), HEAT_R, HEAT_R, "heat pipe", 16, 0.0)
	var nb := int(floor(length / 1.0))
	for i in range(1, nb + 1):
		var f := float(i) / float(nb + 1)
		var inside := false
		for g: Vector2 in gaps:
			var x := a.x + d.x * f
			inside = inside or (x > g.x - 0.05 and x < g.y + 0.05)
		if inside:
			continue
		var p := a + d * f
		var u := d / length * 0.02
		_cone(_st(sts, "steel"), p - u, p + u, HEAT_R + 0.012, HEAT_R + 0.012, "heat band", 16, 0.0)

## Narośl Żyły (1.3, gniazdo): Żyła wylewa się oknem piętra i spływa po schodach pomostów do ziemi — kilka splecionych, guzowatych pasm
## za pasem gry (z ≤ −1), na dole rozchodzi się korzeniami po placu. Na każdym pomoście mata żył (płaski wierzch na wysokości pokładu, żyły
## zwisają z przedniej krawędzi), a pod nią co VEIN_STEP półłuki ze spływu: łukiem nad ścieżką do zwisu przed przednią krawędzią. Bez nóg
## przed płaszczyzną gry (zasłaniałyby wrogów co 1,3 m; materiał z wygaszaniem pierwszego planu wymaga tekstur i warstwy ścian przekroju).
static func _vein(sts: Dictionary, rows: Array, ds: Array) -> void:
	if ds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 53 + int(ds[0]["c0"]) * 23
	var sorted := ds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["top"]) > float(b["top"]))     # od najwyższego (przy oknie) w dół
	var hi: Dictionary = sorted[0]
	var lo: Dictionary = sorted[sorted.size() - 1]
	var hr := int(hi["r"])
	var dir := 1.0                                          # strona ściany budynku względem pomostów
	var c_wall := int(hi["c1"]) + 1
	if not _wall_at(rows, c_wall, hr):
		c_wall = int(hi["c0"]) - 1
		dir = -1.0
	var has_wall := _wall_at(rows, c_wall, hr)
	var xw := (float(c_wall) + (0.0 if dir > 0.0 else 1.0)) * T
	var yg := floor_y(rows, int((int(lo["c0"]) + int(lo["c1"])) / 2), int(lo["r"]), false)
	var far := float(lo["x0"]) if dir > 0.0 else float(lo["x1"])               # koniec najniższego pomostu z dala od ściany
	var flow: Array = []                                    # oś spływu: okno → wzdłuż tyłu każdej maty → przelew na niższy pomost → ziemia
	if has_wall:
		flow.append(Vector3(xw + dir * 0.35, float(hi["top"]) + 1.0, -1.0))
		flow.append(Vector3(xw - dir * 0.25, float(hi["top"]) + 0.15, -1.1))
	for d: Dictionary in sorted:
		var near := float(d["x1"]) if dir > 0.0 else float(d["x0"])           # koniec pomostu od strony ściany
		var away := float(d["x0"]) if dir > 0.0 else float(d["x1"])
		flow.append(Vector3(near - dir * 0.4, float(d["top"]) - 0.12, -1.15))
		flow.append(Vector3(lerpf(near, away, 0.5), float(d["top"]) - 0.2, -1.25))
		flow.append(Vector3(away + dir * 0.35, float(d["top"]) - 0.3, -1.3))
		flow.append(Vector3(away - dir * 0.15, float(d["top"]) - 0.75, -1.45))      # przelew przez koniec
	flow.append(Vector3(far - dir * 0.6, yg + 0.35, -1.6))
	flow.append(Vector3(far - dir * 1.3, yg + 0.12, -1.8))
	var tissue := _st(sts, "vein_dark")
	for k in 4:                                             # pasma spływu
		var pts: Array = []
		for p: Vector3 in flow:
			pts.append(p + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.12, 0.12), rng.randf_range(-0.2, 0.1)))
		var path := _crom(pts, 6)
		var r0 := rng.randf_range(0.11, 0.2)
		var tw := rng.randf() * TAU                         # pasma splatają się: przesunięcie po okręgu wokół osi spływu
		for p in path.size():
			var f := float(p) / float(path.size() - 1)
			path[p] = (path[p] as Vector3) + Vector3(0.0, cos(f * 22.0 + tw) * 0.16, sin(f * 22.0 + tw) * 0.2)
		var ph := rng.randf() * TAU
		for p in path.size() - 1:
			var a: Vector3 = path[p]
			var b: Vector3 = path[p + 1]
			a.z = minf(a.z, -0.8 - r0)
			b.z = minf(b.z, -0.8 - r0)
			var f0 := float(p) / float(path.size() - 1)
			var f1 := float(p + 1) / float(path.size() - 1)
			var ra := r0 * (0.75 + 0.3 * sin(f0 * 38.0 + ph)) * lerpf(0.8, 1.15, f0)   # guzy wzdłuż pasma, grubsze u dołu
			var rb := r0 * (0.75 + 0.3 * sin(f1 * 38.0 + ph)) * lerpf(0.8, 1.15, f1)
			_cone(tissue, a, b, ra, rb, "vein flow", 10, 0.1, float(k))
	var foot: Vector3 = flow[flow.size() - 1]
	for k in 5:                                             # korzenie rozchodzące się po placu, za pasem gry
		var e := foot + Vector3(rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-1.6, -0.2))
		e.y = floor_y(rows, int(e.x / T), int(lo["r"]), false) + 0.04
		var m := foot.lerp(e, 0.5) + Vector3(0.0, 0.08, 0.0)
		_tube(tissue, _crom([foot + Vector3(0.0, 0.1, 0.0), m, e], 4), rng.randf_range(0.08, 0.14), 0.02, "vein root", 7)
	for d: Dictionary in sorted:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		_rbox(_st(sts, "vein"), Vector3(x0 + 0.02, top - 0.16, -0.62), Vector3(x1 - 0.02, top, 0.62), 0.07, "vein mat", Basis.IDENTITY, 0.5, true, rng.randf() * 10.0)
		for k in 9:                                         # żyły na wierzchu: wzdłuż maty
			var z := lerpf(-0.5, 0.5, float(k) / 8.0) + rng.randf_range(-0.04, 0.04)
			var xa := rng.randf_range(x0, x0 + 0.6)
			var xb := rng.randf_range(x1 - 0.6, x1)
			var rv := rng.randf_range(0.025, 0.04)
			var pts: Array = []
			for j in 6:
				pts.append(Vector3(lerpf(xa, xb, float(j) / 5.0), top - rv + 0.012, z + rng.randf_range(-0.07, 0.07)))
			_tube(tissue, _crom(pts, 3), rv, rv * 0.7, "vein strand", 6)
		for k in rng.randi_range(4, 6):                     # zwisy z przedniej krawędzi
			var x := rng.randf_range(x0 + 0.2, x1 - 0.2)
			var dl := rng.randf_range(0.3, 0.9)
			_tube(tissue, _crom([Vector3(x, top - 0.05, 0.6), Vector3(x + 0.05, top - 0.12, 0.72), Vector3(x + rng.randf_range(-0.1, 0.1), top - 0.1 - dl, 0.78)], 3),
				rng.randf_range(0.02, 0.035), 0.006, "vein drip", 6)
		var n := maxi(2, int(round((x1 - x0) / VEIN_STEP)))
		for i in n:                                         # półłuki ze spływu pod matą
			var x := lerpf(x0 + 0.45, x1 - 0.45, (float(i) + 0.5) / float(n)) + rng.randf_range(-0.12, 0.12)
			var ya := top - 0.2
			var pts := [Vector3(x + rng.randf_range(-0.3, 0.3), top - 0.3, -1.3), Vector3(x, ya - 0.06, -0.9), Vector3(x, ya - 0.02, -0.5), Vector3(x, ya, 0.0),
				Vector3(x + rng.randf_range(-0.08, 0.08), ya - 0.03, 0.62), Vector3(x + rng.randf_range(-0.1, 0.1), ya - rng.randf_range(0.2, 0.4), 0.8)]
			var path := _crom(pts, 5)
			for p in path.size():                           # krzywa nie wychodzi ponad oś pod matą
				if (path[p] as Vector3).z > -1.2:
					path[p] = Vector3(path[p].x, minf(path[p].y, ya), path[p].z)
			var rr := rng.randf_range(0.07, 0.1)
			for p in path.size() - 1:
				var f0 := float(p) / float(path.size() - 1)
				var f1 := float(p + 1) / float(path.size() - 1)
				_cone(tissue, path[p], path[p + 1], lerpf(rr * 1.4, 0.03, f0), lerpf(rr * 1.4, 0.03, f1), "vein arch", 8, 0.12, float(i))

## Pod pomostem w wierszu `r` kolumny `c` stoi bryła z wierzchem tuż pod nim (skrzynia `M` o kafel niżej): ciasna wnęka, w której
## nikt nie stoi wyprostowany — nie liczy się jako poziom chodzenia (tak samo `tools/test_steps.gd`).
static func _cramped(rows: Array, c: int, r: int) -> bool:
	return Level3D.is_solid_ch(Level3D._ch(rows, c, r + 1))

## Kafel (c, r) albo wiersz nad nim to ściana budynku (lita albo z oknem `|`).
static func _wall_at(rows: Array, c: int, r: int) -> bool:
	for rr in [r, r - 1]:
		var ch := Level3D._ch(rows, c, rr)
		if Level3D.is_solid_ch(ch) or ch == "|":
			return true
	return false

## Konary sosen: sosny w miejscu słupów `w` (rysuje je `Level3D`, `trunk_cells`) i z "trunks"; konar wychodzi z pnia ukośnie ku kamerze
## i od pomostu biegnie wzdłuż niego w pasie gry, wierzch równo z pokładem. Przęsło mostu przechodzące przez pień — belka przybita do pnia.
static func _boughs(sts: Dictionary, models: Dictionary, rows: Array, e: Dictionary, step_cells: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	var ds := decks_of(rows, e)
	if ds.is_empty():
		return
	rng.seed = 31 + int(ds[0]["c0"]) * 11
	var trunks: Array = []                                  # x osi pnia
	for t in bough_trunks(rows, e):
		trunks.append((float(t["c"]) + 0.5) * T)
		for k in range(int(t["r0"]), int(t["r1"])):         # przęsło mostu przez pień: belka w poprzek i zastrzał za pasem gry
			var ch := Level3D._ch(rows, int(t["c"]), k)
			if Level3D.is_platform_ch(ch) and not step_cells.has(Vector2i(int(t["c"]), k)):
				var x := (float(t["c"]) + 0.5) * T
				var under := -float(k) * T - float(Level3D.DECK_H[ch]) * T + 0.01
				_box(_st(sts, "plank"), Vector3(x - 0.09, under - 0.2, Level3D.TRUNK_Z - 0.1), Vector3(x + 0.09, under, Level3D.deck_half(ch) - 0.05), "bough ledger")
				var a := Vector3(x, under - 1.3, Level3D.TRUNK_Z + 0.3)
				var b := Vector3(x, under - 0.2, -STRIP - 0.45)
				_cone(_st(sts, "plank"), a, b, 0.07, 0.07, "bough strut", 6, 0.0)
	for t in e.get("trunks", []):                           # dodatkowa sosna na podłożu (wiersz `t[1]`)
		var c := int(t[0])
		var rf := int(t[1])
		var foot := Vector3((float(c) + 0.5) * T, -float(rf) * T, Level3D.TRUNK_Z)
		_pine(models, foot, 17.0, c * 13 + rf, crown_y(rows, e))
		trunks.append(foot.x)
	for d in ds:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var mid := (x0 + x1) * 0.5
		var near: Array = trunks.filter(func(t): return t >= x0 - BOUGH_REACH * T and t <= x1 + BOUGH_REACH * T)
		if near.is_empty():
			push_warning("Step3D: pomost %d,%d bez sosny w zasięgu" % [int(d["r"]), int(d["c0"])])
			continue
		var inside: Array = near.filter(func(t): return t > x0 and t < x1)
		var left: Array = near.filter(func(t): return t <= mid)
		var right: Array = near.filter(func(t): return t > mid)
		if not inside.is_empty():
			_limb(sts, rng, inside[0], inside[0], x0, top, BOUGH_R.y)
			_limb(sts, rng, inside[0], inside[0], x1, top, BOUGH_R.y)
		elif not left.is_empty() and not right.is_empty() and left.max() >= x0 - 2.5 * T and right.min() <= x1 + 2.5 * T:
			_limb(sts, rng, left.max(), x0, mid + 0.4, top, 0.18)
			_limb(sts, rng, right.min(), x1, mid - 0.4, top, 0.18)
		else:
			near.sort_custom(func(a, b): return absf(a - mid) < absf(b - mid))
			var t: float = near[0]
			_limb(sts, rng, t, x1 if t > mid else x0, x0 if t > mid else x1, top, BOUGH_R.y)

## Konar z pnia w `t` (oś w głębi na TRUNK_Z): ukośnie ku pasowi gry do `xs` (koniec pomostu przy pniu), dalej wzdłuż pomostu do `xe`;
## promień BOUGH_R.x → `r_end`, oś na wysokości pokładu minus promień (płaski wierzch). Suche gałązki z tyłu, za pasem gry.
static func _limb(sts: Dictionary, rng: RandomNumberGenerator, t: float, xs: float, xe: float, top: float, r_end: float) -> void:
	var st := _st(sts, "bark")
	var dir := signf(xe - t) if absf(xe - t) > 0.01 else 1.0
	var zt := Level3D.TRUNK_Z
	var r0 := BOUGH_R.x
	var root_r := r0 * 1.25
	var z_run := -0.12
	var a := Vector3(t, top - root_r - 0.55, zt)
	var b := Vector3(lerpf(t, xs, 0.55) + dir * 0.2, top - r0 - 0.12, lerpf(zt, z_run, 0.6))
	var c := Vector3(xs, top - r0, z_run)
	var bend := _crom([a, b, c], 4)
	for i in bend.size() - 1:
		var f0 := float(i) / float(bend.size() - 1)
		var f1 := float(i + 1) / float(bend.size() - 1)
		_cone(st, bend[i], bend[i + 1], lerpf(root_r, r0, f0), lerpf(root_r, r0, f1), "bough limb root", 12, 0.02, t)
	var length := absf(xe - xs)
	var n := maxi(1, int(ceil(length / LIMB_STEP)))
	var prev := c
	var prev_r := r0
	for i in range(1, n + 1):
		var f := float(i) / float(n)
		var rr := lerpf(r0, r_end, f)
		var p := Vector3(xs + (xe - xs) * f, top - rr, z_run + 0.1 * f)
		_cone(st, prev, p, prev_r, rr, "bough limb", 10, 0.02, t + float(i))
		prev = p
		prev_r = rr
	_disc(_st(sts, "bark"), prev, Vector3(dir, 0.0, 0.0), prev_r)
	for i in 4:                                             # suche gałązki dolnych konarów (w tył i w górę, za pasem gry)
		var f := rng.randf_range(0.15, 0.95)
		var rr := lerpf(r0, r_end, f)
		var x := xs + (xe - xs) * f
		var p0 := Vector3(x, top - rr, -STRIP - 0.05)
		var p1 := Vector3(x + dir * rng.randf_range(0.3, 0.9), top + rng.randf_range(0.5, 1.3), -STRIP - rng.randf_range(0.5, 1.2))
		_cone(st, p0, p1, 0.035, 0.012, "bough twig", 5, 0.0)
		if rng.randf() < 0.6:
			var p2 := p1 + Vector3(dir * rng.randf_range(0.1, 0.4), rng.randf_range(0.2, 0.5), -rng.randf_range(0.1, 0.4))
			_cone(st, p1, p2, 0.012, 0.005, "bough twig", 4, 0.0)

# --- radiostacja 1.2 (S4): schody na dach, stacja słupowa, pole antenowe -------------------------------------------------------

## Podłoże pod kolumną `c` poniżej wiersza `r`: pierwsza bryła albo pokład leżący na czymś (właz studni w wierszu gruntu, podłoga) —
## pomost nad powietrzem (niższy stopień tych samych schodów) się nie liczy, słup idzie przez niego do ziemi.
static func _foot_y(rows: Array, c: int, r: int) -> float:
	var g := r + 1
	while g < rows.size():
		var ch := Level3D._ch(rows, c, g)
		if Level3D.is_solid_ch(ch) or (Level3D.is_platform_ch(ch) and Level3D._ch(rows, c, g + 1) != "."):
			break
		g += 1
	return -float(g) * T

## Pręt (walec) od `a` do `b`.
static func _rod(st: SurfaceTool, a: Vector3, b: Vector3, r: float, what: String) -> void:
	_cone(st, a, b, r, r, what, 6, 0.0)

## Belka prostokątna od `a` do `b` (oś w płaszczyźnie x–y), przekrój `h` (w pionie osi) × `w` (w głąb).
static func _beam_xy(st: SurfaceTool, a: Vector3, b: Vector3, h: float, w: float, what: String) -> void:
	var d := b - a
	var length := Vector2(d.x, d.y).length()
	var c := (a + b) * 0.5
	_box(st, c - Vector3(length * 0.5, h * 0.5, w * 0.5), c + Vector3(length * 0.5, h * 0.5, w * 0.5), what, Basis(Vector3.BACK, atan2(d.y, d.x)))

## Krata pomostu: rama i płaskowniki w poprzek co ok. 0,11 m, wierzch na `top`, od z0 do z1; przednia listwa w żółto-czarne pasy (krawędź do chwytu).
static func _grate(sts: Dictionary, x0: float, x1: float, top: float, z0: float, z1: float, what: String) -> void:
	var gal := _st(sts, "galv")
	for z: float in [z0, z1 - 0.06]:
		_box(gal, Vector3(x0, top - 0.06, z), Vector3(x1, top, z + 0.06), what + " frame")
	_box(gal, Vector3(x0, top - 0.06, z0), Vector3(x0 + 0.05, top, z1), what + " frame")
	_box(gal, Vector3(x1 - 0.05, top - 0.06, z0), Vector3(x1, top, z1), what + " frame")
	var n := maxi(2, int(round((x1 - x0) / 0.11)))
	for i in range(1, n):
		var x := lerpf(x0, x1, float(i) / float(n))
		_box(gal, Vector3(x - 0.012, top - 0.045, z0 + 0.06), Vector3(x + 0.012, top, z1 - 0.06), what + " bar")
	var zc := z0 + 0.35                                     # pręty wzdłuż co 0,35 m (krócej niż 0,4 m — któryś leży w osi pasa gry)
	while zc < z1 - 0.1:
		_box(gal, Vector3(x0, top - 0.035, zc - 0.01), Vector3(x1, top, zc + 0.01), what + " bar")
		zc += 0.35
	var m := maxi(2, int(round((x1 - x0) / 0.3)))
	for i in m:
		var xa := lerpf(x0, x1, float(i) / float(m))
		var xb := lerpf(x0, x1, float(i + 1) / float(m))
		_box(_st(sts, "hazard" if i % 2 == 0 else "hazard_dark"), Vector3(xa, top - 0.17, z1), Vector3(xb, top, z1 + 0.025), what + " edge")

## Poręcz z tyłu pomostu w głębi `z`: słupki co ok. 1,3 m, pochwyt na 1,05 m i przeciąg w połowie.
static func _rail(st: SurfaceTool, x0: float, x1: float, top: float, z: float, what: String, t := 0.03) -> void:
	var n := maxi(1, int(ceil((x1 - x0) / 1.3)))
	for i in n + 1:
		var x := lerpf(x0 + t, x1 - t, float(i) / float(n))
		_box(st, Vector3(x - t, top, z - t), Vector3(x + t, top + 1.05, z + t), what + " post")
	_box(st, Vector3(x0, top + 1.0, z - t * 1.2), Vector3(x1, top + 1.06, z + t * 1.2), what)
	_box(st, Vector3(x0, top + 0.5, z - t * 0.7), Vector3(x1, top + 0.54, z + t * 0.7), what)

## Maszt kratowy o przekroju kwadratu `a` (oś x, zc) od y0 do y1, przęsła co `step`; malowany w pasy co `band` m (0 — ocynk).
static func _lattice(sts: Dictionary, x: float, zc: float, y0: float, y1: float, a: float, step: float, band: float, what: String) -> void:
	var h := a * 0.5
	var cs := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	var k := maxf(1.0, a / 0.8)
	var n := maxi(1, int(round((y1 - y0) / step)))
	var s := (y1 - y0) / float(n)
	for i in n:
		var ya := y0 + s * float(i)
		var yb := ya + s
		var key := "galv" if band <= 0.0 else ("mast_white" if int(floor((ya - y0) / band)) % 2 == 1 else "mast_red")
		var st := _st(sts, key)
		for f in 4:
			var p: Vector2 = cs[f]
			var q: Vector2 = cs[(f + 1) % 4]
			_rod(st, Vector3(x + p.x, ya, zc + p.y), Vector3(x + p.x, yb, zc + p.y), 0.035 * k, what + " leg")
			var pa := p if i % 2 == 0 else q
			var pb := q if i % 2 == 0 else p
			_rod(st, Vector3(x + pa.x, ya, zc + pa.y), Vector3(x + pb.x, yb, zc + pb.y), 0.014 * k, what + " brace")
			_rod(st, Vector3(x + p.x, yb, zc + p.y), Vector3(x + q.x, yb, zc + q.y), 0.016 * k, what + " brace")

## Drabina z koszem na tylnej ścianie masztu (w `z`): pochwyty, szczeble co 0,3 m, obręcze kosza od 2,3 m co 0,9 m (w głąb) i pięć prętów.
static func _cage_ladder(sts: Dictionary, x: float, z: float, y0: float, y1: float) -> void:
	var gal := _st(sts, "galv")
	for o: float in [-0.22, 0.22]:
		_rod(gal, Vector3(x + o, y0, z), Vector3(x + o, y1, z), 0.022, "ladder rail")
	var y := y0 + 0.3
	while y < y1 - 0.05:
		_rod(gal, Vector3(x - 0.22, y, z), Vector3(x + 0.22, y, z), 0.012, "ladder rung")
		y += 0.3
	var hoops: Array = []
	y = y0 + 2.3
	while y < y1 - 0.2:
		hoops.append(y)
		var pts: Array = []
		for i in 9:
			var ang := PI * float(i) / 8.0
			pts.append(Vector3(x + cos(ang) * 0.36, y, z - sin(ang) * 0.36))
		for i in 8:
			_rod(gal, pts[i], pts[i + 1], 0.012, "ladder hoop")
		y += 0.9
	if hoops.size() > 1:
		for i in 5:
			var ang := PI * float(i) / 4.0
			var p := Vector3(x + cos(ang) * 0.36, 0.0, z - sin(ang) * 0.36)
			_rod(gal, Vector3(p.x, hoops[0], p.z), Vector3(p.x, hoops[hoops.size() - 1], p.z), 0.01, "ladder strap")

## Schody na dach (1.2, radiostacja): do ceglanego budynku dobito zewnętrzne schody z desek. Słupy za pasem gry (PORCH_Z: przedni i tylny
## rząd), spoczniki to pomosty wpisu — pokład z desek od tylnych słupów do przedniej krawędzi (jasna deska czołowa), legary wspornikowe
## nad ścieżką z zastrzałem za pasem; biegi w głębi na zmianę w dwóch pasach (PORCH_BANDS), pierwszy z ziemi. Poręcz tylko z tyłu.
static func _porch(sts: Dictionary, rows: Array, ds: Array) -> void:
	if ds.is_empty():
		return
	var sorted := ds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["top"]) < float(b["top"]))
	var plank := _st(sts, "plank")
	var zf := PORCH_Z.x
	var zb := PORCH_Z.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 61 + int(ds[0]["c0"]) * 7
	for d: Dictionary in sorted:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var r := int(d["r"])
		var n := int(round((x1 - x0) / 0.16))
		for i in n:                                         # deski w poprzek, od tylnej poręczy do przedniej krawędzi
			var a := lerpf(x0, x1, float(i) / float(n))
			var b := lerpf(x0, x1, float(i + 1) / float(n))
			_box(plank, Vector3(a + 0.008, top - 0.05, zb), Vector3(b - 0.008, top, 0.70 + rng.randf_range(-0.015, 0.01)), "porch board",
				Basis(Vector3.UP, rng.randf_range(-0.006, 0.006)))
		var xs: Array = []                                  # legary w głąb co ok. 1,15 m
		var xj := x0 + 0.15
		while xj < x1 - 0.2:
			xs.append(xj)
			xj += 1.15
		xs.append(x1 - 0.15)
		for x: float in xs:
			_box(plank, Vector3(x - 0.06, top - 0.26, zb), Vector3(x + 0.06, top - 0.05, 0.66), "porch joist")
		_box(plank, Vector3(x0, top - 0.38, zf - 0.07), Vector3(x1, top - 0.26, zf + 0.07), "porch header")
		_box(_st(sts, "cut"), Vector3(x0, top - 0.26, 0.66), Vector3(x1, top - 0.005, 0.73), "porch fascia")
		var np := maxi(1, int(round((x1 - x0) / 3.6)))
		for i in np + 1:                                    # słupy: przedni pod legarami, tylny przez poręcz; stopy z betonu
			var x := lerpf(x0 + 0.12, x1 - 0.12, float(i) / float(np))
			var yg := _foot_y(rows, int(floor(x / T)), r)
			_box(plank, Vector3(x - 0.07, yg, zf - 0.07), Vector3(x + 0.07, top - 0.26, zf + 0.07), "porch post")
			_box(plank, Vector3(x - 0.07, yg, zb), Vector3(x + 0.07, top + 1.05, zb + 0.14), "porch post")
			_box(_st(sts, "concrete"), Vector3(x - 0.17, yg - 0.05, zf - 0.17), Vector3(x + 0.17, yg + 0.12, zf + 0.17), "porch footing")
			_box(_st(sts, "concrete"), Vector3(x - 0.17, yg - 0.05, zb - 0.1), Vector3(x + 0.17, yg + 0.12, zb + 0.24), "porch footing")
			_cone(plank, Vector3(x, yg + 0.5, zf - 0.05), Vector3(x, top - 0.4, zb + 0.1), 0.04, 0.04, "porch brace", 6, 0.0)
			_cone(plank, Vector3(x, top - 1.0, zf), Vector3(x, top - 0.27, -STRIP - 0.06), 0.045, 0.045, "porch brace", 6, 0.0)
			_box(plank, Vector3(x - 0.05, top - 0.36, zb), Vector3(x + 0.05, top - 0.26, zf), "porch tie")
		_rail(plank, x0, x1, top, zb + 0.07, "porch rail", 0.035)
	var flight := func(xa: float, ya: float, xb: float, yb: float, band: Vector2) -> void:
		for z: float in [band.x, band.y]:
			_beam_xy(plank, Vector3(xa, ya - 0.13, z), Vector3(xb, yb - 0.13, z), 0.26, 0.06, "porch stringer")
		var k := maxi(2, int(round((yb - ya) / 0.2)))
		for i in range(1, k):
			var x := lerpf(xa, xb, float(i) / float(k))
			var y := lerpf(ya, yb, float(i) / float(k))
			_box(plank, Vector3(x - 0.15, y - 0.04, band.y), Vector3(x + 0.15, y, band.x), "porch tread")
		_beam_xy(plank, Vector3(xa, ya + 0.95, band.y), Vector3(xb, yb + 0.95, band.y), 0.05, 0.04, "porch handrail")
	var lo: Dictionary = sorted[0]
	var yl := _foot_y(rows, int(lo["c0"]), int(lo["r"]))
	var run := (float(lo["top"]) - yl) * 1.1
	flight.call(float(lo["x0"]) + 0.5 - run, yl, float(lo["x0"]) + 0.5, float(lo["top"]), PORCH_BANDS[1])
	for i in range(1, sorted.size()):
		var a: Dictionary = sorted[i - 1]
		var b: Dictionary = sorted[i]
		var xb := float(b["x0"]) + 0.5
		flight.call(xb - (float(b["top"]) - float(a["top"])) * 1.1, float(a["top"]), xb, float(b["top"]), PORCH_BANDS[(i + 1) % 2])

## Stacja słupowa (1.2, wieża nad halą): stacja brała prąd z linii, linia padła — stąd generatory. Pomosty to podesty obsługi na bramkach
## z żerdzi betonowych ustawionych w poprzek płaszczyzny gry (POLE_Z, obie za pasem); poprzecznica z ceownika wysunięta do przedniej krawędzi,
## zastrzał od przedniej żerdzi kończy się za pasem. Na najwyższym podeście w głębi dwa transformatory z izolatorami, na niższych szafki;
## żerdzie najwyższego podestu niosą martwą linię (trzy przewody nad wszystkim).
static func _pole(sts: Dictionary, rows: Array, ds: Array) -> void:
	if ds.is_empty():
		return
	var hi: Dictionary = ds[0]
	for d: Dictionary in ds:
		if float(d["top"]) > float(hi["top"]):
			hi = d
	var line_y := float(hi["top"]) + POLE_LINE
	var gal := _st(sts, "galv")
	var span := Vector2(INF, -INF)
	var sorted := ds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["top"]) > float(b["top"]))   # od najwyższego: niższy podest wisi na żerdziach wyższego
	var poles: Array = []                                   # x bramek już postawionych
	for d: Dictionary in sorted:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var r := int(d["r"])
		var is_hi := d == hi
		span = Vector2(minf(span.x, x0), maxf(span.y, x1))
		var n := maxi(1, int(round((x1 - x0) / POLE_SPAN)))
		for i in n + 1:
			var x := lerpf(x0 + 0.5, x1 - 0.5, float(i) / float(n))
			var shared := false
			for p: float in poles:
				if p > x0 + 0.2 and p < x1 - 0.2 and absf(p - x) < 1.8:
					x = p
					shared = true
			var yg := _foot_y(rows, int(floor(x / T)), r)
			var y_top := line_y if is_hi else top + 2.2
			if not shared:
				poles.append(x)
				for z: float in [POLE_Z.x, POLE_Z.y]:
					_cone(_st(sts, "concrete"), Vector3(x, yg - 0.2, z), Vector3(x, y_top, z), 0.17, 0.11, "pole", 10, 0.0)
					_box(_st(sts, "concrete"), Vector3(x - 0.3, yg - 0.05, z - 0.3), Vector3(x + 0.3, yg + 0.12, z + 0.3), "pole footing")
			_box(gal, Vector3(x - 0.08, top - 0.3, POLE_DECK_Z - 0.02), Vector3(x + 0.08, top - 0.06, 0.70), "pole crossbeam")
			_rod(gal, Vector3(x, top - 1.55, POLE_Z.x), Vector3(x, top - 0.32, -STRIP - 0.06), 0.04, "pole strut")
			_rod(gal, Vector3(x, top - 1.55, POLE_Z.y), Vector3(x, top - 0.32, POLE_Z.x - 0.1), 0.035, "pole strut")
			var yp := yg + 1.2
			while yp < top - 0.5 and not shared:                           # stopnie na przedniej żerdzi
				_rod(gal, Vector3(x - 0.25, yp, POLE_Z.x), Vector3(x + 0.25, yp, POLE_Z.x), 0.016, "pole step")
				yp += 0.45
			if is_hi:                                       # trawersa z izolatorami martwej linii
				_box(gal, Vector3(x - 0.07, line_y - 0.45, -3.7), Vector3(x + 0.07, line_y - 0.32, -0.55), "pole crossarm")
				for z: float in POLE_WIRES:
					_rod(_st(sts, "porcelain"), Vector3(x, line_y - 0.32, z), Vector3(x, line_y - 0.05, z), 0.06, "pole insulator")
		for z: float in [-0.56, 0.44, -2.1]:                # podłużnice pod kratą
			_box(gal, Vector3(x0, top - 0.2, z - 0.06), Vector3(x1, top - 0.06, z + 0.06), "pole stringer")
		_grate(sts, x0, x1, top, POLE_DECK_Z, 0.68, "pole deck")
		_rail(gal, x0, x1, top, POLE_DECK_Z + 0.03, "pole rail")
		if is_hi:
			var w := x1 - x0
			for f: float in [0.3, 0.7]:
				var xt := x0 + w * f
				var tank := _st(sts, "transformer")
				_box(tank, Vector3(xt - 0.8, top, -2.95), Vector3(xt + 0.8, top + 1.5, -1.8), "pole transformer")
				for k in 7:
					var fx := xt - 0.66 + float(k) * 0.22
					_box(tank, Vector3(fx - 0.02, top + 0.15, -1.8), Vector3(fx + 0.02, top + 1.3, -1.55), "pole fin")
				for k in 3:
					var bx := xt - 0.45 + 0.45 * float(k)
					_rod(_st(sts, "porcelain"), Vector3(bx, top + 1.5, -2.35), Vector3(bx, top + 2.1, -2.35), 0.06, "pole bushing")
					var px: float = poles[0]
					for p: float in poles:
						if absf(p - xt) < absf(px - xt):
							px = p
					_rod(_st(sts, "wire"), Vector3(bx, top + 2.1, -2.35), Vector3(px, line_y - 0.05, POLE_WIRES[k]), 0.012, "pole drop")
		else:
			_box(_st(sts, "cabinet"), Vector3(x0 + 0.35, top, POLE_DECK_Z + 0.15), Vector3(x0 + 1.05, top + 1.25, POLE_DECK_Z + 0.75), "pole cabinet")
	for z: float in POLE_WIRES:
		_rod(_st(sts, "wire"), Vector3(span.x - POLE_WIRE_OUT, line_y - 0.05, z), Vector3(span.y + POLE_WIRE_OUT, line_y - 0.05, z), 0.014, "pole wire")

## Pole antenowe przy maszcie (1.2, generator 4): niższe pomosty to spoczniki niskich masztów anten (kratownica ANT_A w z = ANT_Z, malowana
## w pasy, dipol na szczycie, drabina z koszem na tylnej ścianie); spocznik z kraty na wspornikach od podłużnicy przy maszcie, zastrzały za
## pasem, cięgno ze szczytu. Najwyższy pomost to pomost obsługi przy dużym maszcie (`Backdrop3D` MAST_Z): kratownica za pasem od nogi
## kratowej ("legs") do masztu i dalej, wsporniki kraty; generator stoi na nim jak dotąd.
static func _antenna(sts: Dictionary, rows: Array, e: Dictionary, ds: Array) -> void:
	if ds.is_empty():
		return
	var hi: Dictionary = ds[0]
	for d: Dictionary in ds:
		if float(d["top"]) > float(hi["top"]):
			hi = d
	var gal := _st(sts, "galv")
	for d: Dictionary in ds:
		var x0: float = d["x0"]
		var x1: float = d["x1"]
		var top: float = d["top"]
		var r := int(d["r"])
		if d == hi:
			continue
		var xc := x0 + 0.55
		var yg := _foot_y(rows, int(floor(xc / T)), r)
		var yt := top + 3.4
		_lattice(sts, xc, ANT_Z, yg, yt, ANT_A, 0.9, 3.0, "antenna mast")
		_box(_st(sts, "concrete"), Vector3(xc - 0.6, yg - 0.1, ANT_Z - 0.6), Vector3(xc + 0.6, yg + 0.2, ANT_Z + 0.6), "antenna footing")
		_rod(gal, Vector3(xc - 1.7, yt + 0.35, ANT_Z), Vector3(xc + 1.7, yt + 0.35, ANT_Z), 0.025, "antenna dipole")
		_rod(gal, Vector3(xc, yt, ANT_Z), Vector3(xc, yt + 0.9, ANT_Z), 0.03, "antenna top")
		for o: float in [-1.7, 1.7]:
			_rod(_st(sts, "porcelain"), Vector3(xc + o, yt + 0.28, ANT_Z), Vector3(xc + o, yt + 0.42, ANT_Z), 0.05, "antenna insulator")
		_box(_st(sts, "lamp"), Vector3(xc - 0.08, yt + 0.9, ANT_Z - 0.08), Vector3(xc + 0.08, yt + 1.06, ANT_Z + 0.08), "antenna lamp")
		_cage_ladder(sts, xc, ANT_Z - ANT_A * 0.5 - 0.1, yg + 0.15, top + 1.05)
		var zb := ANT_Z + ANT_A * 0.5 + 0.12                 # spocznik przed masztem: z tyłu do podłużnicy, kosz drabiny za nim
		_grate(sts, x0, x1, top, zb, 0.68, "antenna deck")
		for yy: float in [top - 0.3, top - 0.98]:
			_box(gal, Vector3(x0, yy, zb - 0.1), Vector3(x1, yy + 0.1, zb), "antenna stringer")
		var x := x0 + 0.12
		while x < x1:
			_box(gal, Vector3(x - 0.05, top - 0.2, zb - 0.1), Vector3(x + 0.05, top - 0.06, 0.66), "antenna bracket")
			_rod(gal, Vector3(x, top - 0.93, zb - 0.05), Vector3(x, top - 0.22, -STRIP - 0.06), 0.025, "antenna strut")
			_rod(gal, Vector3(x, top - 0.93, zb - 0.05), Vector3(x, top - 0.3, zb - 0.05), 0.02, "antenna strut")
			x += 1.3
		_rod(gal, Vector3(xc, top + 2.4, zb - 0.05), Vector3(x1 - 0.1, top - 0.3, zb - 0.05), 0.02, "antenna hanger")
		_rod(gal, Vector3(xc, top + 2.4, zb - 0.05), Vector3(x1 - 0.1, top - 0.93, zb - 0.05), 0.02, "antenna hanger")
		_rail(gal, x0, x1, top, zb + 0.03, "antenna rail")
	# pomost obsługi przy dużym maszcie
	var hx0: float = hi["x0"]
	var hx1: float = hi["x1"]
	var htop: float = hi["top"]
	var mast := Vector2(INF, -INF)                          # x masztu (para kolumn `w` od góry mapy) w obrysie pomostu
	for c in range(int(hi["c0"]), int(hi["c1"]) + 1):
		if Level3D._ch(rows, c, 1) == "w" and Level3D._ch(rows, c + 1, 1) == "w":
			mast = Vector2(float(c) * T + 0.25, float(c + 2) * T - 0.25)
			break
	var yt2 := htop - 0.22
	var yb2 := htop - 1.55
	var spans: Array = [[hx0, hx1]] if mast.x == INF else [[hx0, mast.x], [mast.y, hx1]]
	for sp in spans:
		var a: float = sp[0]
		var b: float = sp[1]
		if b - a < 0.3:
			continue
		var n := maxi(1, int(round((b - a) / 1.3)))
		var s := (b - a) / float(n)
		for z: float in GALLERY_Z:
			_rod(gal, Vector3(a, yt2, z), Vector3(b, yt2, z), 0.05, "gallery chord")
			_rod(gal, Vector3(a, yb2, z), Vector3(b, yb2, z), 0.05, "gallery chord")
			for k in n + 1:
				var xk := a + s * float(k)
				_rod(gal, Vector3(xk, yb2, z), Vector3(xk, yt2, z), 0.03, "gallery post")
				if k < n:
					_rod(gal, Vector3(xk, yt2 if k % 2 == 1 else yb2, z), Vector3(xk + s, yb2 if k % 2 == 1 else yt2, z), 0.025, "gallery diagonal")
		for k in n + 1:
			var xk := a + s * float(k)
			_rod(gal, Vector3(xk, yb2, GALLERY_Z.x), Vector3(xk, yb2, GALLERY_Z.y), 0.025, "gallery tie")
			_box(gal, Vector3(xk - 0.05, yt2 - 0.02, GALLERY_Z.y - 0.05), Vector3(xk + 0.05, htop - 0.06, 0.66), "gallery bracket")
			_rod(gal, Vector3(xk, yb2 + 0.1, GALLERY_Z.x), Vector3(xk, htop - 0.24, -STRIP - 0.06), 0.03, "gallery strut")
		for i in 3:                                         # wiązka kabli od masztu
			var zk := -1.5 - 0.1 * float(i)
			_rod(_st(sts, "wire"), Vector3(a, yb2 + 0.18 + 0.1 * float(i), zk), Vector3(b, yb2 + 0.18 + 0.1 * float(i), zk), 0.05, "gallery cable")
	for c in e.get("legs", []):                             # noga kratowa pod kratownicą
		var xl := (float(c) + 0.5) * T
		var yl := _foot_y(rows, int(c), int(hi["r"]))
		_lattice(sts, xl, (GALLERY_Z.x + GALLERY_Z.y) * 0.5, yl, yb2, 0.9, 1.2, 0.0, "gallery leg")
		_box(_st(sts, "concrete"), Vector3(xl - 0.8, yl - 0.1, -2.4), Vector3(xl + 0.8, yl + 0.25, -0.8), "gallery footing")
	for sp in spans:                                        # krata na całą głębokość kratownicy, przy maszcie (przód w −0,64) tylko przed nim
		if float(sp[1]) - float(sp[0]) > 0.05:
			_grate(sts, sp[0], sp[1], htop, GALLERY_Z.y - 0.05, 0.68, "gallery deck")
			_rail(gal, sp[0], sp[1], htop, GALLERY_Z.y - 0.02, "gallery rail")
	if mast.x != INF:
		_grate(sts, mast.x, mast.y, htop, -0.6, 0.68, "gallery deck")

## Buduje wszystkie wpisy `STEPS` mapy pod `parent`. Zwraca węzeł z bryłami (nazwa „Steps”); `parts` opisuje elementy dla testu.
static func build(parent: Node3D, rows: Array, steps: Array) -> Node3D:
	parts.clear()
	_colored.clear()
	var root := Node3D.new()
	root.name = "Steps"
	parent.add_child(root)
	if steps.is_empty():
		return root
	var sts := {}
	var models := {}
	var sc := cells(rows, steps)
	for e in steps:
		var kind := String(e.get("kind", ""))
		var ds := decks_of(rows, e)
		match kind:
			"bank":
				for d in ds:
					_bank(sts, models, rows, d)
			"windfall":
				for d in ds:
					_windfall(sts, models, rows, d)
			"tor":
				_tor(sts, models, rows, ds, bool(e.get("cache", false)))
			"boughs":
				_boughs(sts, models, rows, e, sc)
			"heat":
				_heat(sts, rows, ds)
			"vein":
				_vein(sts, rows, ds)
			"porch":
				_porch(sts, rows, ds)
			"pole":
				_pole(sts, rows, ds)
			"antenna":
				_antenna(sts, rows, e, ds)
			_:
				push_warning("Step3D: nieznany rodzaj „%s”" % kind)
	for key in sts:
		var st: SurfaceTool = sts[key]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = "Step_" + key
		mi.mesh = st.commit()
		mi.material_override = _mat(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	for mk in models:
		var mm := Level3D.model_mesh(mk)
		if mm.is_empty():
			continue
		Level3D._forest_chunks(root, mm[0], null, models[mk], true, mm[1])
	return root
