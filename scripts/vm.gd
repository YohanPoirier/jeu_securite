extends RefCounted
## Machine virtuelle d'UN robot. step() est appelée une fois par tick.
##  - Les capteurs (coût 0) s'exécutent instantanément et le programme continue dans le même tick.
##  - Une action de coût c occupe le robot pendant c ticks.
##  - Si le programme exécute trop d'instructions sans agir : erreur « boucle infinie ? ».

const Comp = preload("res://scripts/compiler.gd")
const PyOps = preload("res://scripts/pyops.gd")

var code: Array
var pc := 0
var stack: Array = []
var vars: Dictionary = {}
var wait := 0
var done := false
var error: Dictionary = {}
var host = null
var builtins: Array = []
var printed: Array = []
var budget := 2000
var last_line := 0
var robot_ref = null  # le robot (dictionnaire du monde) qui exécute cette VM


func _init(p_code: Array, p_host, p_builtins: Array) -> void:
	code = p_code
	host = p_host
	builtins = p_builtins


func _fail(msg: String) -> void:
	error = {"line": last_line, "msg": msg}


func step() -> void:
	if done or not error.is_empty():
		return
	if wait > 0:
		wait -= 1
		return
	var n := 0
	while n < budget:
		if pc >= code.size():
			done = true
			return
		n += 1
		var ins: Array = code[pc]
		pc += 1
		last_line = ins[3]
		var op: int = ins[0]
		if op == Comp.PUSH:
			stack.push_back(ins[1])
		elif op == Comp.LOAD:
			if not vars.has(ins[1]):
				_fail("NameError : la variable « %s » n'est pas définie (elle doit avoir reçu une valeur avant d'être utilisée)." % ins[1])
				return
			stack.push_back(vars[ins[1]])
		elif op == Comp.STORE:
			vars[ins[1]] = stack.pop_back()
		elif op == Comp.BINOP:
			var b = stack.pop_back()
			var a = stack.pop_back()
			var r = PyOps.binop(ins[1], a, b)
			if r is PyOps.PyError:
				_fail(r.msg)
				return
			stack.push_back(r)
		elif op == Comp.UNOP:
			var a1 = stack.pop_back()
			var r1 = PyOps.unop(ins[1], a1)
			if r1 is PyOps.PyError:
				_fail(r1.msg)
				return
			stack.push_back(r1)
		elif op == Comp.CMP or op == Comp.CMPK:
			var b2 = stack.pop_back()
			var a2 = stack.pop_back()
			var r2 = PyOps.cmp(ins[1], a2, b2)
			if r2 is PyOps.PyError:
				_fail(r2.msg)
				return
			if op == Comp.CMPK:
				stack.push_back(b2)
			stack.push_back(r2)
		elif op == Comp.JMP:
			pc = ins[1]
		elif op == Comp.JF:
			if not PyOps.truthy(stack.pop_back()):
				pc = ins[1]
		elif op == Comp.JFK:
			if not PyOps.truthy(stack.back()):
				pc = ins[1]
			else:
				stack.pop_back()
		elif op == Comp.JTK:
			if PyOps.truthy(stack.back()):
				pc = ins[1]
			else:
				stack.pop_back()
		elif op == Comp.CHAINJF:
			var r3 = stack.pop_back()
			if not PyOps.truthy(r3):
				stack.pop_back()
				stack.push_back(r3)
				pc = ins[1]
		elif op == Comp.POP:
			stack.pop_back()
		elif op == Comp.MKRANGE:
			var args: Array = []
			for i in ins[1]:
				args.push_front(stack.pop_back())
			var it = _make_range(args)
			if it == null:
				return
			stack.push_back(it)
		elif op == Comp.FORRANGE:
			var it2: Dictionary = stack.back()
			if (it2.step > 0 and it2.cur >= it2.stop) or (it2.step < 0 and it2.cur <= it2.stop):
				stack.pop_back()
				pc = ins[2]
			else:
				vars[ins[1]] = it2.cur
				it2.cur += it2.step
		elif op == Comp.CALL:
			var args2: Array = []
			for i in ins[2]:
				args2.push_front(stack.pop_back())
			var res = _call(ins[1], args2)
			if res == null:
				return
			stack.push_back(res.value)
			if res.cost > 0:
				wait = res.cost - 1
				return
	_fail("Ton programme a exécuté plus de %d instructions d'affilée sans que le robot n'agisse : boucle infinie ?" % budget)


func _make_range(args: Array):
	for a in args:
		if typeof(a) != TYPE_INT and typeof(a) != TYPE_BOOL:
			_fail("TypeError : range(...) n'accepte que des nombres entiers.")
			return null
	var vals: Array = []
	for a in args:
		vals.append(PyOps.num(a))
	var start := 0
	var stop := 0
	var step := 1
	if vals.size() == 1:
		stop = vals[0]
	elif vals.size() == 2:
		start = vals[0]
		stop = vals[1]
	else:
		start = vals[0]
		stop = vals[1]
		step = vals[2]
	if step == 0:
		_fail("ValueError : le pas de range(...) ne peut pas être 0.")
		return null
	return {"cur": start, "stop": stop, "step": step}


## Retourne {"value", "cost"} ou null en cas d'erreur (l'erreur est alors enregistrée).
func _call(name: String, args: Array):
	if builtins.has(name):
		var v = _builtin(name, args)
		if v is PyOps.PyError:
			_fail(v.msg)
			return null
		return {"value": v, "cost": 0}
	if host != null and host.has_api(name):
		var r = host.call_api(name, args, robot_ref)
		if r is PyOps.PyError:
			_fail(r.msg)
			return null
		return r
	_fail("NameError : la fonction « %s » n'existe pas." % name)
	return null


func _builtin(name: String, args: Array):
	match name:
		"print":
			var parts: Array = []
			for a in args:
				parts.append(PyOps.py_str(a))
			printed.append(" ".join(parts))
			return null
		"abs":
			if args.size() != 1 or not PyOps.is_num(args[0]):
				return PyOps.err("TypeError : abs(x) attend un seul nombre.")
			return absi(PyOps.num(args[0])) if typeof(PyOps.num(args[0])) == TYPE_INT else absf(args[0])
		"min", "max":
			if args.size() < 2:
				return PyOps.err("TypeError : %s(a, b, ...) attend au moins deux valeurs." % name)
			var best = args[0]
			for a in args:
				if not PyOps.is_num(a):
					return PyOps.err("TypeError : %s(...) n'accepte ici que des nombres." % name)
			for a in args:
				if (name == "min" and PyOps.num(a) < PyOps.num(best)) or (name == "max" and PyOps.num(a) > PyOps.num(best)):
					best = a
			return best
		"int":
			if args.size() != 1:
				return PyOps.err("TypeError : int(x) attend un seul argument.")
			var a0 = args[0]
			if typeof(a0) == TYPE_STRING:
				var s: String = a0.strip_edges()
				if s.is_valid_int():
					return s.to_int()
				return PyOps.err("ValueError : « %s » n'est pas un entier valide." % a0)
			if not PyOps.is_num(a0):
				return PyOps.err("TypeError : int(x) impossible pour un %s." % PyOps.type_name(a0))
			return int(PyOps.num(a0))
		"str":
			if args.size() != 1:
				return PyOps.err("TypeError : str(x) attend un seul argument.")
			return PyOps.py_str(args[0])
	return PyOps.err("La fonction « %s » n'existe pas." % name)
