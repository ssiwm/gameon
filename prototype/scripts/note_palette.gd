extends RefCounted
## Palety notatek (MESSAGES_PLAN.md §4): trzy materiały zależne od źródła informacji i ciemna paleta po zmroku (gra toczy się w nocy, jasny papier
## świeciłby jak ekran). Luminancja tła notatki <= 0,3, tekst >= 4,5:1, duże pismo >= 3:1 — pilnuje tego tools/test_note_contrast.gd.
## Osobny plik bez zależności od autoloadów, żeby test mógł go ładować w trybie `-s`. Dostęp z kodu gry: UiTheme.Note / UiTheme.note_palette().

enum Note { DOSSIER, PRINTOUT, SCRAWL }   ## akta sztabu (maszynopis), wydruk z radia (matrycowy, odwrócony), kartka odręczna

const PALETTES := [
	{"bg": Color("9a8660"), "bg2": Color("92805b"), "ink": Color("15100a"), "dim": Color("1a1209"), "accent": Color("650f09"), "edge": Color("5a4a30"), "deco": Color("6d5c3c")},
	{"bg": Color("101c14"), "bg2": Color("0c150f"), "ink": Color("9be6ac"), "dim": Color("62a073"), "accent": Color("9be6ac"), "edge": Color("2f4434"), "deco": Color("050806")},
	{"bg": Color("958d77"), "bg2": Color("857d68"), "ink": Color("0d0b09"), "dim": Color("17120d"), "accent": Color("621610"), "edge": Color("4d4636"), "deco": Color("96905f")},
]

static func palette(mat: int) -> Dictionary:
	return PALETTES[clampi(mat, 0, PALETTES.size() - 1)]
