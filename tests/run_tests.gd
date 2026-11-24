extends SceneTree
## Lancer :  godot --headless --path . -s tests/run_tests.gd
## (code de sortie 0 si tout passe, 1 sinon)

const Interp = preload("res://scripts/interpreter.gd")
const VM = preload("res://scripts/vm.gd")
const World = preload("res://scripts/world.gd")

const ALL_SYNTAX := ["boucle_while", "conditions", "variables", "arithmetique", "boucle_for"]
const ALL_BUILTINS := ["print", "range", "abs", "min", "max", "int", "str"]

var fails := 0
var passed := 0


func _init() -> void:
	test_cases()
	test_errors()
	test_gating()
	test_levels()
	test_hs()
	test_reflexion()
	test_tuto()
	test_noms_inconnus()
	print("")
	print("=== %d tests réussis, %d échecs ===" % [passed, fails])
	quit(1 if fails > 0 else 0)


func ok(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		fails += 1
		print("ÉCHEC : %s %s" % [name, detail])


# ---------- 1. comparaison avec CPython ----------

func run_program(src: String) -> Dictionary:
	var res := Interp.compile(src, ALL_SYNTAX, [], ALL_BUILTINS)
	if not res.ok:
		return {"error": "Ligne %d : %s" % [res.line, res.msg], "out": []}
	var vm := VM.new(res.code, null, ALL_BUILTINS)
	vm.budget = 100000000
	var guard := 0
	while not vm.done and vm.error.is_empty() and guard < 100:
		vm.step()
		guard += 1
	if not vm.error.is_empty():
		return {"error": "Ligne %d : %s" % [vm.error.line, vm.error.msg], "out": vm.printed}
	return {"error": "", "out": vm.printed}


func test_cases() -> void:
	var dir := DirAccess.open("res://tests/cases")
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".py"):
			names.append(f.trim_suffix(".py"))
	names.sort()
	for name in names:
		var src := FileAccess.get_file_as_string("res://tests/cases/%s.py" % name)
		var expected := FileAccess.get_file_as_string("res://tests/cases/%s.out" % name)
		var r := run_program(src)
		var got_text := ""
		for line in r.out:
			got_text += str(line) + "\n"
		if r.error != "":
			ok(false, "CPython/" + name, "erreur : " + r.error + " (après %d lignes de sortie)" % r.out.size())
			continue
		if got_text == expected:
			ok(true, "CPython/" + name)
		else:
			var gl := got_text.split("\n")
			var el := expected.split("\n")
			var bad := 0
			while bad < mini(gl.size(), el.size()) and gl[bad] == el[bad]:
				bad += 1
			var g := gl[bad] if bad < gl.size() else "(rien)"
			var e := el[bad] if bad < el.size() else "(rien)"
			ok(false, "CPython/" + name, "ligne de sortie %d : obtenu « %s », attendu « %s »" % [bad + 1, g, e])
	print("%d programmes comparés à CPython" % names.size())


# ---------- 2. erreurs d'exécution et de syntaxe ----------

func expect_error(name: String, src: String, line: int, fragment: String) -> void:
	var r := run_program(src)
	var msg: String = r.error
	ok(msg.begins_with("Ligne %d" % line) and msg.contains(fragment), "erreur/" + name,
		"obtenu « %s », attendu ligne %d contenant « %s »" % [msg, line, fragment])


func test_errors() -> void:
	expect_error("div0", "x = 1\ny = 0\nprint(x // y)\n", 3, "ZeroDivisionError")
	expect_error("div0_float", "print(1 / 0)\n", 1, "ZeroDivisionError")
	expect_error("mod0", "print(5 % 0)\n", 1, "ZeroDivisionError")
	expect_error("nom_inconnu", "a = 1\nprint(b)\n", 2, "NameError")
	expect_error("type", "print(\"a\" + 1)\n", 1, "TypeError")
	expect_error("comparaison_types", "print(\"a\" < 1)\n", 1, "TypeError")
	expect_error("def", "x = 1\ndef f():\n    pass\n", 2, "pas disponible")
	expect_error("parenthese", "print((1 + 2)\n", 1, "parenthèse")
	expect_error("deux_points", "if 1\n    pass\n", 1, "«")
	expect_error("indentation", "if 1:\npass\n", 2, "bloc indenté")
	expect_error("indentation_incoherente", "if 1:\n        x = 1\n    y = 2\n", 3, "indentation")
	expect_error("tabulation", "if 1:\n\tx = 1\n", 2, "espaces")
	expect_error("break_hors_boucle", "break\n", 1, "boucle")
	expect_error("for_pas_range", "for i in 5:\n    pass\n", 1, "range")
	expect_error("range0", "for i in range(0, 5, 0):\n    pass\n", 1, "ValueError")
	expect_error("affectation_invalide", "3 = x\n", 1, "affecter")
	expect_error("caractere", "x = 3 $ 4\n", 1, "Caractère")
	expect_error("texte_non_termine", "print(\"abc)\n", 1, "Texte non terminé")
	# boucle sans action : pas une erreur, le robot perd son tour (thinking), sans aucun message
	var res := Interp.compile("while True:\n    pass\n", ALL_SYNTAX, [], ALL_BUILTINS)
	var vm := VM.new(res.code, null, ALL_BUILTINS)
	vm.step()
	vm.step()
	ok(vm.error.is_empty() and vm.thinking, "boucle sans action = le robot perd son tour (cerveau), pas une erreur")


# ---------- 3. déblocage progressif ----------

func gate(src: String, syntaxe: Array) -> String:
	var res := Interp.compile(src, syntaxe, ["avancer"], ["print", "range"])
	return "" if res.ok else "Ligne %d : %s" % [res.line, res.msg]


func test_gating() -> void:
	ok(gate("while True:\n    avancer()\n", ["boucle_while"]) == "", "gating/while_ok")
	ok(gate("avancer()\n", []) == "", "gating/appel_ok")
	var m := gate("while True:\n    avancer()\n", [])
	ok(m.begins_with("Ligne 1") and m.contains("while") and m.contains("plus loin"), "gating/while_refuse", m)
	m = gate("if True:\n    avancer()\n", ["boucle_while"])
	ok(m.begins_with("Ligne 1") and m.contains("if") and m.contains("plus loin"), "gating/if_refuse", m)
	m = gate("x = 3\n", ["boucle_while", "conditions"])
	ok(m.begins_with("Ligne 1") and m.contains("plus loin"), "gating/variable_refusee", m)
	m = gate("while not True:\n    avancer()\n", ["boucle_while"])
	ok(m.contains("not") and m.contains("plus loin"), "gating/not_refuse", m)
	m = gate("while True:\n    avancer()\n    avancer() + 1\n", ["boucle_while"])
	ok(m.begins_with("Ligne 3") and m.contains("plus loin"), "gating/calcul_refuse", m)
	m = gate("for i in range(3):\n    avancer()\n", ["boucle_while", "conditions", "variables", "arithmetique"])
	ok(m.begins_with("Ligne 1") and m.contains("plus loin"), "gating/for_refuse", m)
	m = gate("for i in range(3):\n    avancer()\n", ["boucle_for", "variables"])
	ok(m == "", "gating/for_ok", m)
	m = gate("reculer()\n", [])
	ok(m == "", "gating/fonction inconnue : pas d'erreur avant l'exécution", m)


# ---------- 4. niveaux : la solution de référence doit gagner ----------

func load_level(id: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://levels/%s.json" % id)
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func compile_all(level: Dictionary, sources: Dictionary) -> Dictionary:
	var compiled := {}
	for id in sources:
		var res := Interp.compile(sources[id], level.get("syntaxe", []), level.get("api", []), level.get("builtins", []))
		if not res.ok:
			print("   (compilation %s) Ligne %d : %s" % [id, res.line, res.msg])
			return {}
		compiled[id] = res.code
	return compiled


func play(level: Dictionary, compiled: Dictionary, seed_value: int) -> World:
	var w := World.new(level, compiled, seed_value)
	var guard := 0
	while w.status == "en_cours" and guard < 1000:
		w.tick()
		guard += 1
	return w


func test_levels() -> void:
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://levels/index.json"))
	for id in index:
		var lv := load_level(id)
		ok(not lv.is_empty(), "niveau/" + id + "/lisible")
		if lv.is_empty():
			continue
		var compiled := compile_all(lv, lv.solutions)
		ok(not compiled.is_empty(), "niveau/%s/solutions compilent" % id)
		if compiled.is_empty():
			continue
		for spec in lv.robots:
			ok(lv.solutions.has(spec.id), "niveau/%s/solution du robot %s" % [id, spec.id])
		var wins := 0
		var first_loss := ""
		for s in range(1, 61):
			var w := play(lv, compiled, s)
			if w.status == "victoire":
				wins += 1
			elif first_loss == "":
				first_loss = "graine %d : %s %s" % [s, w.status, w.message]
		ok(wins == 60, "niveau/%s/solution gagne sur 60 graines" % id, "(%d/60) %s" % [wins, first_loss])
		# le code de départ ne doit jamais produire d'erreur : la partie se termine par victoire ou défaite
		var start_code := {}
		for spec in lv.robots:
			start_code[spec.id] = lv.code_initial
		var start_compiled := compile_all(lv, start_code)
		ok(not start_compiled.is_empty(), "niveau/%s/code de départ compile" % id)
		var start_bad := ""
		for s in range(1, 41):
			var w0 := play(lv, start_compiled, s)
			if w0.status != "victoire" and w0.status != "defaite":
				start_bad = "graine %d : %s %s" % [s, w0.status, w0.message]
				break
		ok(start_bad == "", "niveau/%s/code de départ finit par victoire ou défaite" % id, start_bad)
		# des robots qui ne font rien ne doivent PAS gagner à tous les coups
		var idle := {}
		for spec in lv.robots:
			idle[spec.id] = []
		var idle_wins := 0
		for s in range(1, 61):
			if play(lv, idle, s).status == "victoire":
				idle_wins += 1
		ok(idle_wins < 60, "niveau/%s/ne rien faire ne suffit pas" % id, "(%d/60 victoires sans rien faire)" % idle_wins)
		print("niveau %s : solution %d/60, robots inactifs %d/60" % [id, wins, idle_wins])


## Une erreur ne stoppe pas le jeu : le robot est hors service (HS) et n'arrête plus personne.
func test_hs() -> void:
	var lv := load_level("niveau_03")
	# programme qui ne compile pas : code null = HS dès le départ, la partie se joue quand même
	var w := play(lv, {"garde": null}, 5)
	ok(w.robots[0].hs and w.status == "defaite", "hs/code null : robot HS, la partie va à son terme", w.status)
	var wins := 0
	for s in range(1, 41):
		if play(lv, {"garde": null}, s).status == "victoire":
			wins += 1
	ok(wins == 0, "hs/un robot HS n'arrête aucun intrus", "(%d victoires)" % wins)
	# erreur d'exécution : le robot tombe en panne, la partie continue
	var res := Interp.compile("avancer()\nattendre(-1)\n", lv.syntaxe, lv.api, lv.builtins)
	ok(res.ok, "hs/programme à erreur d'exécution compile")
	var w2 := World.new(lv, {"garde": res.code}, 5)
	var guard := 0
	while w2.status == "en_cours" and guard < 1000:
		w2.tick()
		guard += 1
	ok(w2.robots[0].hs and w2.events.size() == 1 and w2.status != "en_cours" and w2.tick_n > 2,
		"hs/erreur d'exécution : robot HS, un événement, la partie continue", "%s tick %d" % [w2.status, w2.tick_n])


## La réflexion est gratuite si elle est légère ; trop longue, elle compte comme une action.
func test_reflexion() -> void:
	var lv1 := load_level("niveau_01")
	var lv3 := load_level("niveau_03")
	# une boucle infinie sans action ne bloque rien, dès le premier niveau (et avec variables ensuite)
	for case in [[lv1, "while True:\n    pass\n"], [lv3, "i = 0\nwhile True:\n    i = i + 1\n"]]:
		var res := Interp.compile(case[1], case[0].syntaxe, case[0].api, case[0].builtins)
		ok(res.ok, "reflexion/compile : " + case[1].substr(0, 12), str(res))
		if not res.ok:
			continue
		var w := World.new(case[0], {"garde": res.code}, 3)
		var seen := false
		var guard := 0
		while w.status == "en_cours" and guard < 1000:
			w.tick()
			seen = seen or w.robots[0].vm.thinking
			guard += 1
		ok(w.status != "en_cours" and w.events.is_empty() and seen, "reflexion/boucle sans action ne bloque pas (cerveau affiché)", w.status)
	# réflexion légère : jamais de cerveau
	var sol := compile_all(lv1, lv1.solutions)
	var w1 := World.new(lv1, sol, 3)
	var never := true
	var g := 0
	while w1.status == "en_cours" and g < 1000:
		w1.tick()
		never = never and not w1.robots[0].vm.thinking
		g += 1
	ok(never, "reflexion/réflexion légère = gratuite, jamais de cerveau")
	# réflexion lourde : le robot avance moins vite qu'un robot qui agit directement
	var light := Interp.compile("while True:\n    avancer()\n", lv3.syntaxe, lv3.api, lv3.builtins)
	var heavy := Interp.compile("while True:\n    i = 0\n    while i < 150:\n        i = i + 1\n    avancer()\n", lv3.syntaxe, lv3.api, lv3.builtins)
	var wl := World.new(lv3, {"garde": light.code}, 3)
	var wh := World.new(lv3, {"garde": heavy.code}, 3)
	for t in 3:
		wl.tick()
		wh.tick()
	ok(wh.robots[0].pos < wl.robots[0].pos, "reflexion/réflexion lourde = moins d'actions", "léger %d, lourd %d" % [wl.robots[0].pos, wh.robots[0].pos])


## Tuto : mémoire en caractères, assommer dans le vide, alternance voleur / pas de voleur.
func test_tuto() -> void:
	var I = Interp
	ok(I.chars_used("avancer()\n") == 9, "tuto/chars simple", str(I.chars_used("avancer()\n")))
	ok(I.chars_used("# commentaire\n\nassommer()  # fin\n") == 10, "tuto/chars commentaires et lignes vides ignorés", str(I.chars_used("# commentaire\n\nassommer()  # fin\n")))
	ok(I.chars_used("x = \"#a\"\n") == 8, "tuto/chars # dans une chaîne compte", str(I.chars_used("x = \"#a\"\n")))
	# tuto 3 : la solution « à la main » tient dans la mémoire
	var t3 := load_level("tuto_3")
	ok(I.chars_used(t3.solutions.garde) <= int(t3.memoire), "tuto/3 solution dans la mémoire", str(I.chars_used(t3.solutions.garde)))
	# tuto 4 : 14 fois avancer() ne tient pas, la boucle for tient
	var t4 := load_level("tuto_4")
	var by_hand := "avancer()\n".repeat(14) + "assommer()\n"
	ok(I.chars_used(by_hand) > int(t4.memoire), "tuto/4 à la main dépasse la mémoire", str(I.chars_used(by_hand)))
	ok(I.chars_used(t4.solutions.garde) <= int(t4.memoire), "tuto/4 la boucle for tient", str(I.chars_used(t4.solutions.garde)))
	var rej := I.compile(by_hand, t4.syntaxe, t4.api, t4.builtins)
	ok(rej.ok, "tuto/4 syntaxe à la main acceptée par le jeu (la limite est celle de la mémoire)")
	# tuto 5 : les attaques impaires ont un voleur, les paires aucun
	var t5 := load_level("tuto_5")
	var naive := compile_all(t5, {"garde": "assommer()\n"})
	var empty := compile_all(t5, {"garde": "# rien\n"})
	var odd := t5.duplicate()
	odd["numero"] = 1
	var even := t5.duplicate()
	even["numero"] = 2
	ok(play(odd, naive, 1).status == "victoire", "tuto/5 voleur présent : assommer seul suffit")
	ok(play(even, naive, 1).status == "defaite", "tuto/5 assommer à vide : panne, défaite")
	ok(play(odd, empty, 1).status == "defaite", "tuto/5 ne rien faire ne bat pas le voleur")
	ok(play(even, empty, 1).status == "victoire", "tuto/5 sans voleur, ne rien faire suffit (mais il faut valider les deux cas)")
	var good := compile_all(t5, t5.solutions)
	ok(play(odd, good, 1).status == "victoire" and play(even, good, 1).status == "victoire", "tuto/5 le if gagne dans les deux cas")
	# assommer dans le vide met le robot hors service
	var lv := load_level("niveau_01")
	var res := compile_all(lv, {"garde": "assommer()\n"})
	var w := World.new(lv, res, 3)
	w.tick()
	ok(w.robots[0].hs and w.events.size() == 1 and String(w.events[0].msg).contains("personne"), "tuto/assommer dans le vide : robot HS", str(w.events))


## Une fonction inconnue ou pas encore disponible n'échoue qu'à l'exécution de sa ligne.
func test_noms_inconnus() -> void:
	var lv := load_level("tuto_2")
	var typo := compile_all(lv, {"garde": "avancer()\nassomer()\n"})
	ok(not typo.is_empty(), "noms/la faute de frappe compile")
	var w := World.new(lv, typo, 1)
	w.tick()
	ok(not w.robots[0].hs, "noms/pas d'erreur avant d'atteindre la ligne fautive")
	w.tick()
	ok(w.robots[0].hs and w.events.size() == 1 and w.events[0].line == 2 and String(w.events[0].msg).contains("assomer"),
		"noms/erreur à la ligne fautive, au moment de l'exécution", str(w.events))
	# une fonction d'un autre niveau (regarder n'est pas encore disponible au tuto 2)
	var lv2 := load_level("tuto_2")
	var early := compile_all(lv2, {"garde": "regarder()\n"})
	var w2 := World.new(lv2, early, 1)
	w2.tick()
	ok(w2.robots[0].hs and String(w2.events[0].msg).contains("pas disponible"), "noms/fonction pas encore disponible : erreur à l'exécution", str(w2.events))
