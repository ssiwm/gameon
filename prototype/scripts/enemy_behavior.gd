extends RefCounted
## Zachowanie rodzaju wroga (ENEMY_PLAN.md F2c/F3.1c): wszystko, co jest specyficzne dla jednego rodzaju (Wołek: szarża i rzuty, Podsłuchacz: krzyk i pole ochronne,
## Ćma: lot do światła, Mimik: demaskacja…), mieszka w podklasie tej klasy, a `enemy.gd` tylko wywołuje haki w stałych miejscach swojego tiku. Nowy rodzaj z własną
## mechaniką = nowa podklasa + wpis `"behavior"` w `enemy_defs.gd`, bez dopisywania kolejnych `if kind ==` w rdzeniu.
##
## Zasady: stan, który widzą klienci (`_sp`, `winding`, `_ai`, `_facing`, `_windup`), zostaje w `enemy.gd` (replikuje go `_sync`); stan prywatny zachowania
## (liczniki, cooldowny) żyje tu. Funkcje RPC (`_scream_fx`, `_crash_fx`, `_mimic_call`…) zostają w `enemy.gd` — RPC wymaga węzła w scenie. Wszystkie haki
## mają bezpieczne domyślne działanie „nic się nie dzieje", więc rodzaj bez zachowania (pusty `behavior`) działa jak zwykły wróg.

const BEHAVIORS := {
	"listener": "res://scripts/enemy_listener.gd",
	"bruiser": "res://scripts/enemy_bruiser.gd",
}

## Węzeł wroga (`enemy.gd`) — bez typu, bo `enemy.gd` ładuje tę klasę (cykl preload).
var e

func _init(enemy = null) -> void:
	e = enemy

## Tworzy zachowanie wg nazwy z `enemy_defs.gd` (`"behavior"`); nieznana albo pusta nazwa = zachowanie bazowe (bez haków).
static func create(behavior_name: String, enemy):
	if BEHAVIORS.has(behavior_name):
		return (load(BEHAVIORS[behavior_name]) as GDScript).new(enemy)
	return (load("res://scripts/enemy_behavior.gd") as GDScript).new(enemy)

## Restart misji: zerowanie stanu prywatnego.
func reset() -> void:
	pass

## Czy żywy, aktywny wróg jest realnym zagrożeniem dla botów (np. Podsłuchacz dopiero po krzyku).
func threat_ok() -> bool:
	return true

## Stan AI, który przejmuje całą resztę (np. Podsłuchacz); -1 = liczy rdzeń.
func derive_pre() -> int:
	return -1

## Stan AI zwykłego pościgu zastąpiony zachowaniem (np. szarża Ślepca); -1 = liczy rdzeń.
func derive_mid() -> int:
	return -1

## Pełne przejęcie tiku po wspólnym wstępie (Podsłuchacz, Ćma); true = rdzeń kończy tik.
func tick_special(_delta: float) -> bool:
	return false

## Mnożnik obrażeń (pole ochronne Podsłuchacza); 1 = bez zmian.
func damage_mult() -> float:
	return 1.0

## Punkt, w który wróg patrzy, gdy stoi; (INF, INF) = zostaje kierunek z ruchu.
func look_at_point() -> Vector2:
	return Vector2(INF, INF)

## Czy mocne ogłuszenie może przerwać zapowiedź ciosu.
func can_interrupt_windup() -> bool:
	return true

## Trafienie (po obrażeniach, nie śmiertelne): zachowanie może zareagować (Podsłuchacz zaczyna krzyk). `silent` = ciche trafienie (maczeta w plecy).
func on_hit(_silent: bool) -> void:
	pass

## Zachowanie dopisuje klucze do `view_info` (stan pola, rozżarzone oczy…).
func view_extra(_d: Dictionary) -> void:
	pass

## Animacja prezentacji: zachowanie może ją zmienić (np. krzyk w polu ochronnym trzyma pozę zapowiedzi).
func anim(a: String, _moving: bool) -> String:
	return a

## Czy kierunek patrzenia modelu 3D pochodzi z serwera (stoi i patrzy na cel), a nie z przesunięcia pozycji.
func server_facing() -> bool:
	return false

## Faza specjalna rodzaju w tiku aktywnego wroga (po percepcji, przed zwykłym łańcuchem decyzji — szarża i rzuty Wołka); true = przejęła ruch w tej klatce.
func tick_phase(_delta: float, _target: Node2D) -> bool:
	return false

## Po ruchu klatki, w której zadziałała `tick_phase` (szarża Wołka rozbija skrzynie i uderza gracza).
func after_phase_move() -> void:
	pass
