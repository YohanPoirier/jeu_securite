extends RefCounted
## Déblocage progressif : parcourt l'arbre et refuse ce que le niveau n'autorise pas.
## Les fonctionnalités sont définies sur les TYPES DE NOEUDS de l'arbre, pas sur du texte.

## fonctionnalité -> {niveau où elle arrive, description}
const FEATURES := {
	"boucle_while": {"niveau": 1, "nom": "la boucle while"},
	"conditions": {"niveau": 2, "nom": "les conditions (if, comparaisons, and/or/not)"},
	"variables": {"niveau": 3, "nom": "les variables"},
	"arithmetique": {"niveau": 3, "nom": "les calculs (+ - * / // % **)"},
	"boucle_for": {"niveau": 4, "nom": "la boucle for"},
}

var syntaxe: Array = []
var api: Array = []
var builtins: Array = []
var errs: Array = []


## Retourne une liste d'erreurs {"line", "msg"} (vide si tout est autorisé).
func check(ast: Array, p_syntaxe: Array, p_api: Array, p_builtins: Array) -> Array:
	syntaxe = p_syntaxe
	api = p_api
	builtins = p_builtins
	errs = []
	_block(ast)
	errs.sort_custom(func(a, b): return a.line < b.line)
	return errs


func _need(feature: String, label: String, line: int) -> void:
	if syntaxe.has(feature):
		return
	var info: Dictionary = FEATURES[feature]
	errs.append({"line": line, "msg": "%s n'est pas encore disponible ici. Tu débloqueras plus loin : %s." % [
		label, info.nom]})


func _block(stmts: Array) -> void:
	for s in stmts:
		_stmt(s)


func _stmt(s: Dictionary) -> void:
	match s.k:
		"expr":
			_expr(s.value)
		"assign":
			_need("variables", "L'affectation « %s = ... »" % s.name, s.line)
			_expr(s.value)
		"augassign":
			_need("variables", "L'affectation « %s %s= ... »" % [s.name, s.op], s.line)
			_need("arithmetique", "Le calcul « %s »" % s.op, s.line)
			_expr(s.value)
		"if":
			_need("conditions", "« if »", s.line)
			_expr(s.test)
			_block(s.body)
			_block(s.orelse)
		"while":
			_need("boucle_while", "« while »", s.line)
			_expr(s.test)
			_block(s.body)
		"for":
			_need("boucle_for", "« for »", s.line)
			if not builtins.has("range"):
				errs.append({"line": s.line, "msg": "range(...) n'est pas disponible à ce niveau."})
			for a in s.args:
				_expr(a)
			_block(s.body)
		"break", "continue":
			pass
		"pass":
			pass


func _expr(e: Dictionary) -> void:
	match e.k:
		"num", "str", "const":
			pass
		"name":
			_need("variables", "La variable « %s »" % e.id, e.line)
		"call":
			if not api.has(e.name) and not builtins.has(e.name):
				errs.append({"line": e.line, "msg": "La fonction « %s » n'existe pas (ou n'est pas disponible à ce niveau)." % e.name})
			for a in e.args:
				_expr(a)
		"binop":
			_need("arithmetique", "Le calcul « %s »" % e.op, e.line)
			_expr(e.l)
			_expr(e.r)
		"unop":
			if e.op == "not":
				_need("conditions", "« not »", e.line)
			else:
				_need("arithmetique", "Le signe « %s »" % e.op, e.line)
			_expr(e.operand)
		"cmp":
			_need("conditions", "La comparaison « %s »" % e.ops[0], e.line)
			_expr(e.left)
			for r in e.rights:
				_expr(r)
		"boolop":
			_need("conditions", "« %s »" % e.op, e.line)
			for v in e.values:
				_expr(v)
