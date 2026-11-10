extends RefCounted
## Tabliczki kryjówki w świecie (HUB_LAYOUT_PLAN.md E4, `SIGNS` w danych mapy): wymiary i odstępy wspólne dla widoku 3D (view3d.gd
## `_sync_hub_signs`) i testu mieszczenia (`--uifittest`, tools/test_ui_fit.gd) — po angielsku i po polsku sąsiednie tabliczki na jednym
## pokładzie nie mogą na siebie nachodzić.

const FONT_SIZE := 64
const PIXEL := 0.0045                ## m na piksel czcionki Label3D (wysokość wersalików ok. 0,2 m)
const UP_M := 2.9                    ## wysokość środka tabliczki nad podłogą [m]: nad meblami stanowisk (ściana narzędzi ok. 2,5 m), pod belkami stropu
                                     ## w kadrze piwnicy (przy 3,55 m chowała się za podciągami)
const Z := -1.86                     ## głębia: tuż przed ścianą tylną
const PAD_M := 0.18                  ## margines płyty wokół tekstu
const GAP_M := 0.4                   ## najmniejszy odstęp między płytami sąsiednich tabliczek
const MAX_W := 3.6                   ## najszersza płyta [m] (pomieszczenia mają 6–14 kafli)
const ARROW_M := 0.42                ## bok strzałki przy pionie
const PX := 1.8 / 22.0               ## m na px świata (Level3D.PX)
const TILE := 16.0

## Środek tabliczki w osi x [m] dla kolumny mapy.
static func x_m(col: int) -> float:
	return (float(col) + 0.5) * TILE * PX

## Szerokość płyty [m] z tekstem `text` (już przetłumaczonym) i ewentualną strzałką.
static func plate_w(font: Font, text: String, arrow: bool) -> float:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x * PIXEL if font != null else float(text.length()) * 0.17
	return w + PAD_M * 2.0 + (ARROW_M + PAD_M if arrow else 0.0)

## Kłopoty z tabliczkami w bieżącym języku: za szeroka płyta albo nachodzenie na sąsiadkę na tym samym pokładzie. Pusta lista = w porządku.
static func problems(signs: Array, font: Font) -> Array:
	var out: Array = []
	var by_floor := {}
	for sg in signs:
		var txt := TranslationServer.translate(String(sg[2]))
		var w := plate_w(font, txt, String(sg[3]) != "")
		if w > MAX_W:
			out.append("„%s” ma %.2f m (najwyżej %.1f m)" % [txt, w, MAX_W])
		var fr := int(sg[1])
		if not by_floor.has(fr):
			by_floor[fr] = []
		(by_floor[fr] as Array).append([x_m(int(sg[0])) - w * 0.5, x_m(int(sg[0])) + w * 0.5, txt])
	for fr in by_floor:
		var row: Array = by_floor[fr]
		row.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for i in range(1, row.size()):
			if float(row[i][0]) - float(row[i - 1][1]) < GAP_M:
				out.append("„%s” i „%s” na pokładzie %d: odstęp %.2f m (najmniej %.1f m)" % [row[i - 1][2], row[i][2], fr,
					float(row[i][0]) - float(row[i - 1][1]), GAP_M])
	return out
