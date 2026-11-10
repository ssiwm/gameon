extends Node2D
## Rekwizyt kryjówki wstawiany z HUB_PROPS w danych mapy (ATMOSPHERE / „Stacja Dead Air”, etap 3): generator, rury, skrzynie, zamknięte drzwi D-7, okno z prognozą pogody.
## Sam węzeł niesie rodzaj, parametry i stan kosmetyczny (stukanie zza D-7, buczenie generatora); bryły, światła i okno buduje view3d.gd z grupy „hub_props”.
## Wszystko lokalne i bez wpływu na rozgrywkę (każdy peer losuje własne stukanie), więc nic nie idzie siecią.

const KNOCK_MIN := 30.0               ## odstęp między stukaniami zza drzwi D-7 [s]
const KNOCK_MAX := 80.0
const KNOCKS := ["amb_thud_1", "amb_thud_2"]

## Meble kryjówki stawiane ręcznie z HUB_PROPS (HUB_LAYOUT_PLAN.md E5, zamiast losowania): parametry [przesunięcie x w px od środka kolumny,
## głębia z w m (brak = przy ścianie), odbicie w poziomie]. „bunk” to prycza piętrowa (dwie prycze i stalowe słupki), „stove” — piecyk
## z beczki z rurą do stropu i migoczącym żarem; reszta to modele z art/items3d/ o tej samej nazwie.
const FURNITURE := ["bunk", "stove", "table", "chair", "stool", "shelf", "shelf_b", "locker"]

var kind := ""                        ## "generator", "compressor", "pipes", "crate", "mil_crate", "scrap_pile", "barrel", "d7", "window",
                                      ## "hatch", "cables" i meble z FURNITURE
var args: Array = []                  ## parametry rodzaju: pipes / cables [ostatnia kolumna], window [szerokość w kaflach], meble jak wyżej, reszta []
var knock_flash := 0.0                ## d7: 1 w chwili stuknięcia, zanika do 0 (view3d rozjaśnia czerwony pas pod drzwiami)

var _knock_t := 0.0

## Żar piecyka w kwaterach (mnożnik jasności): powolne falowanie z drobnym migotaniem.
static func stove_light(t: float) -> float:
	return 0.8 + 0.12 * sin(t * 2.3) * sin(t * 0.7 + 1.3) + 0.08 * sin(t * 13.0) * sin(t * 7.1)

## Lampa przy generatorze (mnożnik jasności): buczy i lekko pulsuje, a w burzy co jakiś czas siada (widok 3D gasi nią światło generatora).
static func generator_light(t: float, storm: bool) -> float:
	if storm and sin(t * 1.7) * sin(t * 0.6 + 1.0) > 0.78:
		return 0.15
	return 0.85 + 0.15 * sin(t * 9.0) * sin(t * 3.3)

func _ready() -> void:
	add_to_group("hub_props")
	z_index = 0
	_knock_t = randf_range(KNOCK_MIN * 0.4, KNOCK_MAX * 0.6)
	if kind == "generator":
		Audio.start_loop_at("generator_loop", self, Audio.BUS_WORLD, -17.0, true, _hum_id())      # buczenie maszynowni: słyszalne dopiero blisko

func _exit_tree() -> void:
	if kind == "generator":
		Audio.stop_loop(_hum_id())

func _hum_id() -> String:
	return "hubgen_%d" % get_instance_id()

func _process(delta: float) -> void:
	if kind != "d7":
		return
	knock_flash = maxf(0.0, knock_flash - delta * 2.2)
	_knock_t -= delta
	if _knock_t <= 0.0:
		_knock_t = randf_range(KNOCK_MIN, KNOCK_MAX)
		knock_flash = 1.0
		Audio.play_at(KNOCKS[randi() % KNOCKS.size()], global_position + Vector2(0.0, -24.0), Audio.BUS_WORLD, -4.0, randf_range(0.8, 0.95))
