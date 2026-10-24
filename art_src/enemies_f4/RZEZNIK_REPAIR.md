# Źródło naprawy Rzeźnika

`rzeznik_rig.glb` to odzyskany pełny rig używany wcześniej w tym projekcie:
117 515 trójkątów, ciało i osobny tasak, tekstury z dotychczasowego generatora
TRELLIS/ComfyUI. Nie jest nową generacją ani nowym zakupem. Plik przechowywany
w Git LFS umożliwia odtworzenie naprawy bez lokalnego katalogu ComfyUI.

Generator `prototype/tools/prep_enemy3d.py --only=wolek,rzeznik` scala
geometryczne szwy przed uproszczeniem. Rzeźnik ma dodatkowo wagi liczone
po powierzchni (`enemy_mesh_repair.skin_by_surface_distance`), a tasak
jednoznacznie należy do `mixamorig:RightHand`. Szkielet i tekstury pozostają
z tego źródła; nie klasyfikujemy wysp UV jako niezależnych części anatomii.

Źródło nadal ma lokalne nieprawidłowości topologii wygenerowanej siatki.
Test `test_enemy_surface.gd` kontroluje budżet otwartych krawędzi po wirtualnym
scaleniu UV i rozchodzenie się szwów podczas rzeczywistego skinningu.
