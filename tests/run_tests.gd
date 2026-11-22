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
	# boucle infinie sans action
	var res := Interp.compile("while True:\n    pass\n", ALL_SYNTAX, [], ALL_BUILTINS)
	var vm := VM.new(res.code, null, ALL_BUILTINS)
	vm.step()
	ok(not vm.error.is_empty() and vm.error.msg.contains("boucle infinie"), "erreur/boucle_infinie")


# ---------- 3. déblocage progressif ----------

func gate(src: String, syntaxe: Array) -> String:
	var res := Interp.compile(src, syntaxe, ["avancer"], ["print", "range"])
	return "" if res.ok else "Ligne %d : %s" % [res.line, res.msg]


func test_gating() -> void:
	ok(gate("while True:\n    avancer()\n", ["boucle_while"]) == "", "gating/while_ok")
	ok(gate("avancer()\n", []) == "", "gating/appel_ok")
	var m := gate("while True:\n    avancer()\n", [])
	ok(m.begins_with("Ligne 1") and m.contains("while") and m.contains("niveau 1"), "gating/while_refuse", m)
	m = gate("if True:\n    avancer()\n", ["boucle_while"])
	ok(m.begins_with("Ligne 1") and m.contains("if") and m.contains("niveau 2"), "gating/if_refuse", m)
	m = gate("x = 3\n", ["boucle_while", "conditions"])
	ok(m.begins_with("Ligne 1") and m.contains("niveau 3"), "gating/variable_refusee", m)
	m = gate("while not True:\n    avancer()\n", ["boucle_while"])
	ok(m.contains("not") and m.contains("niveau 2"), "gating/not_refuse", m)
	m = gate("while True:\n    avancer()\n    avancer() + 1\n", ["boucle_while"])
	ok(m.begins_with("Ligne 3") and m.contains("niveau 3"), "gating/calcul_refuse", m)
	m = gate("for i in range(3):\n    avancer()\n", ["boucle_while", "conditions", "variables", "arithmetique"])
	ok(m.begins_with("Ligne 1") and m.contains("niveau 4"), "gating/for_refuse", m)
	m = gate("for i in range(3):\n    avancer()\n", ["boucle_for", "variables"])
	ok(m == "", "gating/for_ok", m)
	m = gate("reculer()\n", [])
	ok(m.contains("reculer") and m.contains("n'existe pas"), "gating/api_refusee", m)


# ---------- 4. niveaux : la solution de référence doit gagner ----------

func load_level(id: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://levels/%s.json" % id)
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


func play(level: Dictionary, code: String, seed_value: int) -> World:
	var res := Interp.compile(code, level.get("syntaxe", []), level.get("api", []), level.get("builtins", []))
	if not res.ok:
		print("   (compilation) Ligne %d : %s" % [res.line, res.msg])
		return null
	var w := World.new(level, res.code, seed_value)
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
		var wins := 0
		var first_loss := ""
		for s in range(1, 61):
			var w := play(lv, lv.solution, s)
			if w == null:
				ok(false, "niveau/%s/solution compile" % id)
				break
			if w.status == "victoire":
				wins += 1
			elif first_loss == "":
				first_loss = "graine %d : %s %s" % [s, w.status, w.message]
		ok(wins == 60, "niveau/%s/solution gagne sur 60 graines" % id, "(%d/60) %s" % [wins, first_loss])
		# un robot qui ne fait rien ne doit PAS gagner à tous les coups
		var idle_wins := 0
		for s in range(1, 61):
			var w := play(lv, "while True:\n    pass\n", s) if false else null
			var res := Interp.compile("x = 0\n", ALL_SYNTAX, [], ALL_BUILTINS)
			var w2 := World.new(lv, res.code, s)
			var g := 0
			while w2.status == "en_cours" and g < 1000:
				w2.tick()
				g += 1
			if w2.status == "victoire":
				idle_wins += 1
		ok(idle_wins < 60, "niveau/%s/ne rien faire ne suffit pas" % id, "(%d/60 victoires sans rien faire)" % idle_wins)
		print("niveau %s : solution %d/60, robot inactif %d/60" % [id, wins, idle_wins])
