extends RefCounted
## Compilation : arbre -> liste plate d'instructions [op, a, b, ligne].
## Une liste plate permet à chaque robot de s'arrêter après n'importe quelle instruction
## (nécessaire pour exécuter plusieurs robots « en parallèle », tick par tick).

enum { PUSH, LOAD, STORE, BINOP, UNOP, CMP, CMPK, JMP, JF, JFK, JTK, CHAINJF, CALL, POP, MKRANGE, FORRANGE }

var code: Array = []
var loops: Array = []


func compile(ast: Array) -> Array:
	code = []
	loops = []
	_block(ast)
	return code


func _emit(op: int, a = null, b = null, line: int = 0) -> int:
	code.append([op, a, b, line])
	return code.size() - 1


func _block(stmts: Array) -> void:
	for s in stmts:
		_stmt(s)


func _stmt(s: Dictionary) -> void:
	match s.k:
		"expr":
			_expr(s.value)
			_emit(POP, null, null, s.line)
		"pass":
			pass
		"assign":
			_expr(s.value)
			_emit(STORE, s.name, null, s.line)
		"augassign":
			_emit(LOAD, s.name, null, s.line)
			_expr(s.value)
			_emit(BINOP, s.op, null, s.line)
			_emit(STORE, s.name, null, s.line)
		"if":
			_expr(s.test)
			var jf := _emit(JF, -1, null, s.line)
			_block(s.body)
			if s.orelse.size() > 0:
				var jend := _emit(JMP, -1, null, s.line)
				code[jf][1] = code.size()
				_block(s.orelse)
				code[jend][1] = code.size()
			else:
				code[jf][1] = code.size()
		"while":
			var start := code.size()
			_expr(s.test)
			var jf2 := _emit(JF, -1, null, s.line)
			var ctx := {"cont": start, "breaks": []}
			loops.append(ctx)
			_block(s.body)
			loops.pop_back()
			_emit(JMP, start, null, s.line)
			var end := code.size()
			code[jf2][1] = end
			for b in ctx.breaks:
				code[b][1] = end
		"for":
			for a in s.args:
				_expr(a)
			_emit(MKRANGE, s.args.size(), null, s.line)
			var start2 := code.size()
			var fr := _emit(FORRANGE, s.var, -1, s.line)
			var ctx2 := {"cont": start2, "breaks": []}
			loops.append(ctx2)
			_block(s.body)
			loops.pop_back()
			_emit(JMP, start2, null, s.line)
			var brk := code.size()
			_emit(POP, null, null, s.line)  # un « break » retire l'itérateur de la pile
			code[fr][2] = code.size()
			for b2 in ctx2.breaks:
				code[b2][1] = brk
		"break":
			loops[-1].breaks.append(_emit(JMP, -1, null, s.line))
		"continue":
			_emit(JMP, loops[-1].cont, null, s.line)


func _expr(e: Dictionary) -> void:
	match e.k:
		"num", "str", "const":
			_emit(PUSH, e.v, null, e.line)
		"name":
			_emit(LOAD, e.id, null, e.line)
		"call":
			for a in e.args:
				_expr(a)
			_emit(CALL, e.name, e.args.size(), e.line)
		"binop":
			_expr(e.l)
			_expr(e.r)
			_emit(BINOP, e.op, null, e.line)
		"unop":
			_expr(e.operand)
			_emit(UNOP, e.op, null, e.line)
		"cmp":
			_expr(e.left)
			var jumps: Array = []
			for i in e.ops.size():
				_expr(e.rights[i])
				if i < e.ops.size() - 1:
					_emit(CMPK, e.ops[i], null, e.line)
					jumps.append(_emit(CHAINJF, -1, null, e.line))
				else:
					_emit(CMP, e.ops[i], null, e.line)
			for j in jumps:
				code[j][1] = code.size()
		"boolop":
			var jl: Array = []
			for i in e.values.size():
				_expr(e.values[i])
				if i < e.values.size() - 1:
					jl.append(_emit(JFK if e.op == "and" else JTK, -1, null, e.line))
			for j2 in jl:
				code[j2][1] = code.size()
