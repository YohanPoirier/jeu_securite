extends RefCounted
## Analyse syntaxique : jetons -> arbre syntaxique NEUTRE (dictionnaires).
## L'arbre ne dépend pas de Python : un autre langage pourra produire le même arbre.
##
## Instructions : expr, assign, augassign, if, while, for, break, continue, pass
## Expressions  : num, str, const, name, call, binop, unop, cmp, boolop

const UNSUPPORTED := ["def", "return", "import", "from", "class", "lambda", "try", "except",
	"finally", "with", "as", "global", "nonlocal", "del", "assert", "raise", "yield", "is",
	"in", "async", "await"]
const RESERVED := ["if", "elif", "else", "while", "for", "pass", "break", "continue",
	"and", "or", "not"]
const AUGOPS := ["+=", "-=", "*=", "/=", "//=", "%=", "**="]
const CMPOPS := ["==", "!=", "<", ">", "<=", ">="]

var toks: Array = []
var p := 0
var err: Dictionary = {}
var loop_depth := 0


func parse(tokens: Array) -> Dictionary:
	toks = tokens
	p = 0
	err = {}
	loop_depth = 0
	var body: Array = []
	while not _at("EOF") and err.is_empty():
		var s = _statement()
		if s != null:
			body.append(s)
	if not err.is_empty():
		return {"ok": false, "line": err.line, "msg": err.msg}
	return {"ok": true, "ast": body}


# ---------- utilitaires ----------

func _peek() -> Dictionary:
	return toks[p]


func _at(t: String, v = null) -> bool:
	var tk: Dictionary = toks[p]
	return tk.t == t and (v == null or tk.v == v)


func _next() -> Dictionary:
	var tk: Dictionary = toks[p]
	if tk.t != "EOF":
		p += 1
	return tk


func _fail(msg: String, line: int) -> void:
	if err.is_empty():
		err = {"line": line, "msg": msg}
	p = toks.size() - 1


func _desc(tk: Dictionary) -> String:
	match tk.t:
		"NEWLINE":
			return "la fin de la ligne"
		"INDENT", "DEDENT":
			return "un changement d'indentation"
		"EOF":
			return "la fin du programme"
		"STR":
			return "un texte"
	return "« %s »" % str(tk.v)


func _fail_unexpected() -> void:
	var tk := _peek()
	_fail("Syntaxe incorrecte près de %s." % _desc(tk), tk.line)


func _is_kw(v: String) -> bool:
	return UNSUPPORTED.has(v) or RESERVED.has(v)


func _kw_error(tk: Dictionary) -> void:
	if UNSUPPORTED.has(tk.v):
		_fail("« %s » n'est pas disponible dans ce jeu pour l'instant." % tk.v, tk.line)
	else:
		_fail("Le mot « %s » est réservé ; il ne peut pas être utilisé ici." % tk.v, tk.line)


func _expect_op(v: String, msg: String) -> bool:
	if _at("OP", v):
		_next()
		return true
	_fail(msg, _peek().line)
	return false


# ---------- instructions ----------

func _statement():
	var t := _peek()
	if t.t == "NAME":
		match t.v:
			"if":
				return _if_stmt()
			"while":
				return _while_stmt()
			"for":
				return _for_stmt()
			"elif", "else":
				_fail("« %s » sans « if » correspondant." % t.v, t.line)
				return null
	if t.t == "INDENT":
		_fail("Indentation inattendue (rien ne la justifie à cet endroit).", t.line)
		return null
	if t.t == "NEWLINE":
		_next()
		return null
	var s = _simple()
	if s == null:
		return null
	if not _at("NEWLINE"):
		_fail_unexpected()
		return null
	_next()
	return s


func _simple():
	var t := _peek()
	if t.t == "NAME":
		match t.v:
			"pass":
				_next()
				return {"k": "pass", "line": t.line}
			"break", "continue":
				if loop_depth == 0:
					_fail("« %s » en dehors d'une boucle." % t.v, t.line)
					return null
				_next()
				return {"k": t.v, "line": t.line}
	var e = _expr()
	if e == null:
		return null
	if _at("OP", "="):
		if e.k != "name":
			_fail("On ne peut affecter qu'à une variable : nom = valeur.", t.line)
			return null
		_next()
		var v = _expr()
		if v == null:
			return null
		return {"k": "assign", "name": e.id, "value": v, "line": t.line}
	var tk := _peek()
	if tk.t == "OP" and AUGOPS.has(tk.v):
		if e.k != "name":
			_fail("On ne peut modifier qu'une variable (par exemple : x += 1).", t.line)
			return null
		_next()
		var v2 = _expr()
		if v2 == null:
			return null
		return {"k": "augassign", "name": e.id, "op": String(tk.v).substr(0, String(tk.v).length() - 1),
			"value": v2, "line": t.line}
	return {"k": "expr", "value": e, "line": t.line}


func _colon() -> bool:
	return _expect_op(":", "Il manque « : » à la fin de la ligne.")


func _block() -> Array:
	var body: Array = []
	if _at("NEWLINE"):
		_next()
		if not _at("INDENT"):
			_fail("Il manque un bloc indenté après « : » (la ligne suivante doit être décalée).", _peek().line)
			return body
		_next()
		while not _at("DEDENT") and not _at("EOF") and err.is_empty():
			var s = _statement()
			if s != null:
				body.append(s)
		if _at("DEDENT"):
			_next()
		return body
	var s2 = _simple()
	if s2 == null:
		return body
	if not _at("NEWLINE"):
		_fail_unexpected()
		return body
	_next()
	body.append(s2)
	return body


func _if_stmt():
	var line: int = _next().line  # « if » ou « elif »
	var test = _expr()
	if test == null or not _colon():
		return null
	var body := _block()
	var orelse: Array = []
	if _at("NAME", "elif"):
		var sub = _if_stmt()
		if sub == null:
			return null
		orelse = [sub]
	elif _at("NAME", "else"):
		_next()
		if not _colon():
			return null
		orelse = _block()
	return {"k": "if", "test": test, "body": body, "orelse": orelse, "line": line}


func _while_stmt():
	var line: int = _next().line
	var test = _expr()
	if test == null or not _colon():
		return null
	loop_depth += 1
	var body := _block()
	loop_depth -= 1
	return {"k": "while", "test": test, "body": body, "line": line}


func _for_stmt():
	var line: int = _next().line
	var v := _peek()
	if v.t != "NAME" or _is_kw(v.v):
		_fail("Après « for », il faut un nom de variable (par exemple : for i in range(5):).", v.line)
		return null
	_next()
	if not _at("NAME", "in"):
		_fail("Il manque « in » après la variable du « for ».", _peek().line)
		return null
	_next()
	if not _at("NAME", "range"):
		_fail("Pour l'instant, « for » fonctionne uniquement avec range(...), par exemple : for i in range(5):", _peek().line)
		return null
	_next()
	if not _expect_op("(", "Il manque « ( » après range."):
		return null
	var args: Array = []
	if not _at("OP", ")"):
		while true:
			var a = _expr()
			if a == null:
				return null
			args.append(a)
			if _at("OP", ","):
				_next()
				continue
			break
	if not _expect_op(")", "Il manque « ) » pour fermer range(...)."):
		return null
	if args.size() < 1 or args.size() > 3:
		_fail("range(...) prend entre 1 et 3 arguments.", line)
		return null
	if not _colon():
		return null
	loop_depth += 1
	var body := _block()
	loop_depth -= 1
	return {"k": "for", "var": v.v, "args": args, "body": body, "line": line}


# ---------- expressions ----------

func _expr():
	return _or()


func _or():
	var first = _and()
	if first == null:
		return null
	if _at("NAME", "or"):
		var line: int = _peek().line
		var vals: Array = [first]
		while _at("NAME", "or"):
			_next()
			var r = _and()
			if r == null:
				return null
			vals.append(r)
		return {"k": "boolop", "op": "or", "values": vals, "line": line}
	return first


func _and():
	var first = _not()
	if first == null:
		return null
	if _at("NAME", "and"):
		var line: int = _peek().line
		var vals: Array = [first]
		while _at("NAME", "and"):
			_next()
			var r = _not()
			if r == null:
				return null
			vals.append(r)
		return {"k": "boolop", "op": "and", "values": vals, "line": line}
	return first


func _not():
	if _at("NAME", "not"):
		var line: int = _next().line
		var operand = _not()
		if operand == null:
			return null
		return {"k": "unop", "op": "not", "operand": operand, "line": line}
	return _comparison()


func _comparison():
	var left = _arith()
	if left == null:
		return null
	var ops: Array = []
	var rights: Array = []
	var line: int = _peek().line
	while _peek().t == "OP" and CMPOPS.has(_peek().v):
		ops.append(_next().v)
		var r = _arith()
		if r == null:
			return null
		rights.append(r)
	if ops.is_empty():
		return left
	return {"k": "cmp", "left": left, "ops": ops, "rights": rights, "line": line}


func _arith():
	var left = _term()
	if left == null:
		return null
	while _at("OP", "+") or _at("OP", "-"):
		var op: Dictionary = _next()
		var r = _term()
		if r == null:
			return null
		left = {"k": "binop", "op": op.v, "l": left, "r": r, "line": op.line}
	return left


func _term():
	var left = _unary()
	if left == null:
		return null
	while _at("OP", "*") or _at("OP", "/") or _at("OP", "//") or _at("OP", "%"):
		var op: Dictionary = _next()
		var r = _unary()
		if r == null:
			return null
		left = {"k": "binop", "op": op.v, "l": left, "r": r, "line": op.line}
	return left


func _unary():
	if _at("OP", "-") or _at("OP", "+"):
		var op: Dictionary = _next()
		var operand = _unary()
		if operand == null:
			return null
		return {"k": "unop", "op": op.v, "operand": operand, "line": op.line}
	return _power()


func _power():
	var base = _atom()
	if base == null:
		return null
	if _at("OP", "**"):
		var op: Dictionary = _next()
		var e = _unary()
		if e == null:
			return null
		return {"k": "binop", "op": "**", "l": base, "r": e, "line": op.line}
	return base


func _atom():
	var t := _peek()
	match t.t:
		"NUM":
			_next()
			return {"k": "num", "v": t.v, "line": t.line}
		"STR":
			_next()
			return {"k": "str", "v": t.v, "line": t.line}
		"NAME":
			if _is_kw(t.v):
				_kw_error(t)
				return null
			_next()
			if t.v == "True":
				return {"k": "const", "v": true, "line": t.line}
			if t.v == "False":
				return {"k": "const", "v": false, "line": t.line}
			if t.v == "None":
				return {"k": "const", "v": null, "line": t.line}
			if _at("OP", "("):
				_next()
				var args: Array = []
				if not _at("OP", ")"):
					while true:
						var a = _expr()
						if a == null:
							return null
						args.append(a)
						if _at("OP", ","):
							_next()
							if _at("OP", ")"):
								break
							continue
						break
				if not _expect_op(")", "Il manque « ) » pour fermer l'appel de %s." % t.v):
					return null
				return {"k": "call", "name": t.v, "args": args, "line": t.line}
			return {"k": "name", "id": t.v, "line": t.line}
		"OP":
			if t.v == "(":
				_next()
				var e = _expr()
				if e == null:
					return null
				if not _expect_op(")", "Il manque une parenthèse fermante « ) »."):
					return null
				return e
	_fail("Expression attendue, mais on trouve %s." % _desc(t), t.line)
	return null
