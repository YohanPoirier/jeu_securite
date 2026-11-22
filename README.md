# Garde Robot — prototype

Jeu de programmation en Python (sous-ensemble) : tu programmes un robot garde sur un rail pour arrêter des intrus.
Les fonctionnalités du langage se débloquent niveau par niveau.

## Ouvrir et jouer
1. Godot 4.x → *Importer* → choisir `project.godot` → *Ouvrir*.
2. F5 (ou ▶ en haut à droite) pour lancer.

## Publier en ligne (web)
1. *Éditeur → Gérer les modèles d'exportation…* → *Télécharger et installer* (une seule fois).
2. *Projet → Exporter…* → préréglage **Web** (déjà configuré) → *Exporter le projet* dans `build/web/index.html`.
3. Zipper le contenu de `build/web/` et le déposer sur itch.io (type « HTML », cocher « This file will be played in the browser »).
   Export sans threads (par défaut) : pas d'en-têtes spéciaux à configurer.
   Le moteur de rendu « Compatibility » est déjà choisi (obligatoire pour le web).

## Tests (sans fenêtre)
    godot --headless --path . -s tests/run_tests.gd     # interpréteur vs CPython, déblocage, niveaux
    godot --headless --path . -s tests/ui_smoke.gd      # l'interface se construit et les 4 niveaux se jouent
    python3 tools/gen_tests.py                          # régénère les sorties de référence avec CPython

## Organisation
- `scripts/lexer.gd`, `parser.gd` : texte → arbre syntaxique neutre (dictionnaires)
- `scripts/gating.gd` : règles de déblocage, définies sur les types de nœuds de l'arbre
- `scripts/compiler.gd`, `vm.gd`, `pyops.gd` : exécution tick par tick, sémantique de Python
- `scripts/world.gd` : monde du niveau, API des robots, simulation déterministe (graine)
- `levels/*.json` : les niveaux sont des données (règles, API autorisée, solution de référence)
- `scripts/main.gd`, `rail_view.gd` : interface

## Limites connues
- Entiers sur 64 bits (pas d'entiers illimités comme Python).
- Affichage des flottants approché (pas toujours identique à `repr` de Python).
- Pas encore de fonctions (`def`), listes, dictionnaires, modules.
