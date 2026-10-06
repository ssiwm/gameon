extends RefCounted
## Własności powierzchni (1.7.8): jedno miejsce, z którego czytają ruch (player.gd, enemy.gd), kroki
## (audio_director.gd) i hałas biegu. Nazwa powierzchni pochodzi z kafla pod stopami (level.surface_at).
##
## Pola:
##   speed   mnożnik maks. prędkości chodu            jump   mnożnik prędkości wybicia
##   accel   mnożnik przyspieszania na ziemi          decel  mnożnik hamowania bez wejścia
##   turn    mnożnik zawracania (zmiana kierunku)     noise  mnożnik hałasu biegu (stealth!)
##   step    próbka kroku (5 wariantów)               db, pitch  korekta głośności i wysokości
##   layer   dodatkowa warstwa dźwięku kroku: "water" / "squelch" / "ring" / ""
## accel/decel/turn bliskie 0 = ślizg (olej, lód): postać „płynie" w kierunku ruchu i trudno ją zatrzymać.
## „ice" i „snow" czekają na biom zimowy — kafle mają grafikę, ale nie ma ich jeszcze na mapie.

const DEFAULT := "dirt"

const TABLE := {
	"dirt": {"speed": 1.0, "accel": 1.0, "decel": 1.0, "turn": 1.0, "jump": 1.0, "noise": 1.0,
		"step": "step_dirt", "db": -2.0, "pitch": 1.0, "layer": ""},
	"concrete": {"speed": 1.0, "accel": 1.0, "decel": 1.0, "turn": 1.0, "jump": 1.0, "noise": 1.1,
		"step": "step_concrete", "db": 1.5, "pitch": 1.0, "layer": ""},
	"metal": {"speed": 1.0, "accel": 1.0, "decel": 1.0, "turn": 1.0, "jump": 1.0, "noise": 1.35,
		"step": "step_metal", "db": 4.0, "pitch": 1.0, "layer": "ring"},
	# płycizna / bagno: grząsko — wolniej, ospały rozruch, niższy skok; chlupot głośny
	"water": {"speed": 0.72, "accel": 0.55, "decel": 0.75, "turn": 0.6, "jump": 0.85, "noise": 1.3,
		"step": "step_water", "db": 2.0, "pitch": 0.95, "layer": "water"},
	# błoto z bagna: jeszcze wolniej i ciężej, ale tłumi hałas
	"mud": {"speed": 0.58, "accel": 0.42, "decel": 0.55, "turn": 0.5, "jump": 0.8, "noise": 0.6,
		"step": "step_water", "db": 0.0, "pitch": 0.62, "layer": "squelch"},
	# plama oleju: ślizg (prawie bez przyczepności), lekko wolniej
	"oil": {"speed": 0.9, "accel": 0.14, "decel": 0.06, "turn": 0.12, "jump": 1.0, "noise": 0.8,
		"step": "step_water", "db": -3.0, "pitch": 1.3, "layer": ""},
	# biom zimowy (zapas): lód ślizga, śnieg grzęźnie i tłumi kroki
	"ice": {"speed": 1.05, "accel": 0.16, "decel": 0.05, "turn": 0.10, "jump": 1.0, "noise": 1.0,
		"step": "step_concrete", "db": 0.0, "pitch": 1.45, "layer": ""},
	"snow": {"speed": 0.82, "accel": 0.7, "decel": 0.8, "turn": 0.8, "jump": 0.92, "noise": 0.55,
		"step": "step_dirt", "db": -4.0, "pitch": 0.8, "layer": ""},
}

static func of(surface: String) -> Dictionary:
	return TABLE.get(surface, TABLE[DEFAULT])
