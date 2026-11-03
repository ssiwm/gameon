extends RefCounted
## Maska uszkodzeń zniszczalnego elementu (DESTRUCTION_PLAN.md D0): obraz RG8 na przedniej ścianie modelu — R: 0 = całe, 1 = najgłębsza
## wyrwa; G: dziura na wylot (D2, deski — `stamp_hole`), w nakładce czarna szpara z poszarpanym brzegiem.
## Plamy przychodzą z serwera (`breakable.gd`: u, v, promień, stopień), więc każdy peer odciska te same i maska wygląda u wszystkich tak samo.
## Odcisk to miękkie koło z maksimum zależnym od stopnia (`PEAK`); nowe wartości łączą się ze starymi przez max, więc kolejność
## plam nie zmienia wyniku. Widok 3D (`view3d.gd`) czyta maskę w nakładce `OVERLAY_SHADER` (materiał `material_overlay` modelu).

const TEXEL_M := 0.025                     ## m na teksel (2,5 cm — jak w spike'u S1)
const PEAK := [0.55, 0.8, 1.0]             ## maksimum odcisku wg stopnia 0–2: odprysk, wyszczerbienie, wyrwa
const EDGE := 0.375                        ## szerokość miękkiego brzegu (ułamek promienia)

## Nakładka uszkodzeń na przednią ścianę (+z) bryły wyśrodkowanej w zerze. Mnoży gotowy obraz (`blend_mul`, bez cieniowania), więc tekstura
## i światło pod spodem zostają: brzeg plamy lekko rozjaśniony i zabarwiony świeżym przełomem (`fresh` — mnożnik ~1), środek przyciemniony
## do `deep`. Szum na siatce ~2,5 cm szarpie brzeg (wykruszone cegły zamiast koła). Ściany boczne i tylna bez zmian. Dziura (kanał G)
## to prawie czarna szpara: za deskami jest ciemny korytarz, a nakładka mnoży obraz, więc przezroczystości nie potrzeba.
const OVERLAY_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, fog_disabled;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec2 half_size;
uniform vec3 fresh = vec3(1.6, 1.35, 1.2);
uniform vec3 deep = vec3(0.3, 0.24, 0.22);
uniform vec2 offset;                       // część bryły (deska, pręt): jej położenie w układzie bryły, żeby czytać tę samą maskę
varying vec3 lp;
varying float front;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void vertex() {
	lp = VERTEX + vec3(offset, 0.0);
	front = NORMAL.z;
}
void fragment() {
	if (front < 0.5) {
		discard;
	}
	vec2 uv = vec2((lp.x + half_size.x) / (2.0 * half_size.x), 1.0 - (lp.y + half_size.y) / (2.0 * half_size.y));
	vec2 mk = texture(mask, uv).rg;
	vec2 cell = floor(lp.xy / 0.025);
	float n = hash(cell) * 0.6 + hash(floor(lp.xy / 0.07)) * 0.4;
	float k = mk.r * (0.7 + 0.6 * n);
	vec3 f = mix(vec3(1.0), fresh, smoothstep(0.1, 0.3, k) * (1.0 - smoothstep(0.55, 0.8, k)));
	f = mix(f, deep * (0.55 + 0.9 * hash(cell + 7.0)), smoothstep(0.5, 0.9, k));
	float hole = mk.g * (0.75 + 0.5 * n);                   // dziura na wylot: drzazgi szarpią brzeg
	f = mix(f, vec3(0.02, 0.018, 0.016), smoothstep(0.45, 0.6, hole));
	ALBEDO = f;
}
"""

## Pusta maska dla przedniej ściany `w_m` × `h_m` metrów.
static func create(w_m: float, h_m: float) -> Image:
	var img := Image.create(maxi(2, ceili(w_m / TEXEL_M)), maxi(2, ceili(h_m / TEXEL_M)), false, Image.FORMAT_RG8)
	img.fill(Color(0, 0, 0))
	return img

## Odcisk plamy: `u`, `v` — środek w ułamkach ściany (v = 0 u góry), `r_m` — promień w metrach, `deg` — stopień 0–2.
static func stamp(img: Image, u: float, v: float, r_m: float, deg: int, w_m: float, h_m: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cu := u * w
	var cv := v * h
	var ru := maxf(r_m / w_m * w, 0.75)
	var rv := maxf(r_m / h_m * h, 0.75)
	var peak: float = PEAK[clampi(deg, 0, 2)]
	for j in range(maxi(0, floori(cv - rv)), mini(h, ceili(cv + rv) + 1)):
		for i in range(maxi(0, floori(cu - ru)), mini(w, ceili(cu + ru) + 1)):
			var d := Vector2((i + 0.5 - cu) / ru, (j + 0.5 - cv) / rv).length()
			if d >= 1.0:
				continue
			var val := peak * clampf((1.0 - d) / EDGE, 0.0, 1.0)
			var px := img.get_pixel(i, j)
			if val > px.r:
				img.set_pixel(i, j, Color(val, px.g, 0))

## Dziura na wylot (kanał G): jak `stamp`, pełna wartość w środku, miękki brzeg; łączy się z poprzednimi przez max.
static func stamp_hole(img: Image, u: float, v: float, r_m: float, w_m: float, h_m: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cu := u * w
	var cv := v * h
	var ru := maxf(r_m / w_m * w, 0.75)
	var rv := maxf(r_m / h_m * h, 0.75)
	for j in range(maxi(0, floori(cv - rv)), mini(h, ceili(cv + rv) + 1)):
		for i in range(maxi(0, floori(cu - ru)), mini(w, ceili(cu + ru) + 1)):
			var d := Vector2((i + 0.5 - cu) / ru, (j + 0.5 - cv) / rv).length()
			if d >= 1.0:
				continue
			var val := clampf((1.0 - d) / EDGE, 0.0, 1.0)
			var px := img.get_pixel(i, j)
			if val > px.g:
				img.set_pixel(i, j, Color(px.r, val, 0))
