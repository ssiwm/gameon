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
	"moth": "res://scripts/enemy_moth.gd",
	"mimic": "res://scripts/enemy_mimic.gd",
	"ambusher": "res://scripts/enemy_ambusher.gd",
	"pack": "res://scripts/enemy_pack.gd",
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

## Wróg właśnie się obudził (po `active = true`): odczepienie od sufitu (Skoczek), demaskacja (Mimik).
func on_wake() -> void:
	pass

## Tik uśpionego wroga (po sprawdzeniu budzenia): fałszywe wołanie Mimika.
func tick_asleep(_delta: float) -> void:
	pass

## Tik wiszącego (uśpionego) wroga: zasadzka Skoczka.
func tick_hanging() -> void:
	pass

## Po zwykłym ruchu (`move_and_slide`) w klatce aktywnego wroga: lądowanie Skoczka.
func after_slide() -> void:
	pass

## Czy bez śladu i celu wróg wraca do domu (Skoczek po zasadzce czatuje tam, gdzie wylądował).
func returns_home() -> bool:
	return true

## Wysokość głosu krzyku demaskacji (Mimik niżej niż Podsłuchacz).
func scream_pitch() -> float:
	return 1.0

## Czy uśpiony wróg wygląda jak zwykły stojący (Mimik: bez przygaszenia „uśpionego").
func disguised() -> bool:
	return false

## Dodatkowe rysowanie w nakładce (etykieta Mimika).
func draw_overlay(_ov: Node2D) -> void:
	pass

## Wstęp tiku serwera (liczniki zachowania: cooldowny watahy, rzutu na dźwięk).
func tick_prelude(_delta: float) -> void:
	pass

## Tik aktywnego wroga po percepcji (np. strach watahy przed Stalkerem).
func tick_awake(_delta: float) -> void:
	pass

## Czy wróg stoi w miejscu w zapowiedzi zachowania (obok reakcji „zauważył"): zapowiedź rzutu Ślepca.
func holds_still() -> bool:
	return false

## Ruch narzucony przez zachowanie w łańcuchu decyzji (po zapowiedziach, przed pościgiem): rzut Ślepca, odskok Trzoska po ciosie; true = ustawił `velocity`.
func drive(_delta: float, _target: Node2D, _speed: float) -> bool:
	return false

## Stan AI w pościgu za widocznym celem (Trzosek po ciosie: RETREAT).
func chase_state() -> int:
	return e.Ai.CHASE

## Czy w pościgu wróg czeka na wolne miejsce przy celu (wataha); true = ustawił `velocity`.
func chase_hold(_target: Node2D, _d: Vector2, _speed: float) -> bool:
	return false

## Wróg właśnie zauważył gracza (wataha daje znać kolegom).
func on_sighting(_pos: Vector2) -> void:
	pass

## Cios (zapowiedź skończona, po ustawieniu cooldownu): Trzosek odskakuje.
func after_attack() -> void:
	pass

## Wróg się zapalił.
func on_ignite() -> void:
	pass

## Wróg zginął (po śmierci): morale watahy.
func on_death() -> void:
	pass

## Wróg dostał obrażenia (też nieśmiertelne trafienie): przerywa zapowiedź rzutu Ślepca.
func on_damaged() -> void:
	pass

## Wróg usłyszał hałas (po ustaleniu śladu `lead`, `dist` = słyszalna odległość po trasie, `amount` = głośność): szarża Ślepca.
func on_heard_noise(_lead: Vector2, _dist: float, _amount: float) -> void:
	pass
