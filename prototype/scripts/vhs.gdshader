shader_type canvas_item;
// Filtr VHS/CRT dla świata gry (pod HUD-em). Subtelny: ziarno, linie,
// aberracja chromatyczna przy krawędziach, winieta, lekka korekcja barw
// (zielononiebieskie cienie, bursztynowe światła) i rzadkie zakłócenie taśmy.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;
uniform float aberration = 1.6;     // px przy krawędzi
uniform float grain = 0.045;
uniform float scanline = 0.07;
uniform float vignette = 0.32;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	// zakłócenie taśmy: wąski pas przesuwający się w dół co kilka sekund
	float band_y = fract(TIME * 0.07);
	float band = smoothstep(0.012, 0.0, abs(uv.y - band_y));
	uv.x += band * 0.004 * sin(TIME * 40.0) * strength;

	vec2 dir = (uv - 0.5) * 2.0;
	float edge = dot(dir, dir);
	vec2 off = dir * aberration * px * edge * strength;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// korekcja: lekka desaturacja + chłodne cienie, ciepłe światła
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), 0.12 * strength);
	col += vec3(-0.004, 0.006, 0.012) * (1.0 - l) * strength;
	col *= mix(vec3(1.0), vec3(1.04, 1.0, 0.94), smoothstep(0.25, 0.8, l) * strength);

	// linie (co druga linia ekranu) i ziarno
	float line = mod(floor(FRAGCOORD.y), 2.0);
	col *= 1.0 - scanline * line * strength;
	float n = rand(uv * vec2(1920.0, 1080.0) + vec2(TIME * 13.0, TIME * 7.0)) - 0.5;
	col += n * grain * strength;
	col += band * 0.03 * strength;

	// winieta
	col *= 1.0 - vignette * smoothstep(0.35, 1.35, edge) * strength;
	COLOR = vec4(col, 1.0);
}
