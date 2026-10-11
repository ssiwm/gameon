extends Node2D
## Stojak na broń w kryjówce (dekoracja za przedmiotem „g"): drewniana deska z JEDNĄ kołyską, w której leży broń, i tabliczką.
## Stopy w (0, 0); broń (pickup.gd ze static_display) ma dolną krawędź 6 px nad podłogą (sprite ma jeszcze ~3 px przezroczystego marginesu, więc półka jest wyżej).

const Sprites := preload("res://scripts/sprites.gd")
const ItemsHd := preload("res://scripts/items_hd.gd")

## Wysokość półki (górna krawędź kołyski) nad podłogą w wersji HD — broń na stojaku (pickup.gd) kładzie się na niej.
const SHELF_Y_HD := -9.8

var _hd := false

func _ready() -> void:
	z_index = 0
	if Sprites.newitem and ItemsHd.has("rack"):
		_hd = true
		ItemsHd.make("rack", self)
