extends RefCounted
## Opérations avec la sémantique de Python (et pas celle de GDScript) :
## division entière et modulo « vers le bas », bool = entier, valeurs vraies/fausses, etc.
## En cas d'erreur, les fonctions renvoient un PyError au lieu de lever une exception.

class PyError:
	var msg: String

	func _init(m: String = "") -> void:
		msg = m


static func err(m: String) -> PyError:
	return PyError.new(m)


static func type_name(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "NoneType"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "str"
	return "objet"


static func is_num(v) -> bool:
	var t := typeof(v)
	return t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL


static func num(v):
	if typeof(v) == TYPE_BOOL:
		return 1 if v else 0
	return v


static func truthy(v) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT:
			return v != 0
		TYPE_FLOAT:
			return v != 0.0
		TYPE_STRING:
			return v != ""
	return true


static func py_str(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "None"
		TYPE_BOOL:
			return "True" if v else "False"
		TYPE_FLOAT:
			return _float_str(v)
	return str(v)


static func _float_str(v: float) -> String:
	if is_nan(v):
		return "nan"
	if is_inf(v):
		return "inf" if v > 0 else "-inf"
	if v == floor(v) and absf(v) < 1e15:
		return "%d.0" % int(v)
	return str(v)


@warning_ignore("integer_division")
static func _floordiv_int(a: int, b: int) -> int:
	var q: int = a / b
	if (a % b != 0) and ((a < 0) != (b < 0)):
		q -= 1
	return q


static func _mod_int(a: int, b: int) -> int:
	var r: int = a % b
	if r != 0 and ((r < 0) != (b < 0)):
		r += b
	return r


static func _pow_int(a: int, e: int) -> int:
	var r := 1
	var base := a
	var k := e
	while k > 0:
		if k & 1:
			r *= base
		k >>= 1
		if k > 0:
			base *= base
	return r


static func binop(op: String, a, b):
	if op == "+" and typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
		return a + b
	if op == "*":
		if typeof(a) == TYPE_STRING and (typeof(b) == TYPE_INT or typeof(b) == TYPE_BOOL):
			return a.repeat(maxi(0, num(b)))
		if typeof(b) == TYPE_STRING and (typeof(a) == TYPE_INT or typeof(a) == TYPE_BOOL):
			return b.repeat(maxi(0, num(a)))
	if not (is_num(a) and is_num(b)):
		return err("TypeError : l'opération « %s » est impossible entre %s et %s." % [op, type_name(a), type_name(b)])
	var x = num(a)
	var y = num(b)
	var both_int: bool = typeof(x) == TYPE_INT and typeof(y) == TYPE_INT
	match op:
		"+":
			return x + y
		"-":
			return x - y
		"*":
			return x * y
		"/":
			if y == 0:
				return err("ZeroDivisionError : division par zéro.")
			return float(x) / float(y)
		"//":
			if y == 0:
				return err("ZeroDivisionError : division par zéro.")
			if both_int:
				return _floordiv_int(x, y)
			return floor(float(x) / float(y))
		"%":
			if y == 0:
				return err("ZeroDivisionError : modulo par zéro.")
			if both_int:
				return _mod_int(x, y)
			return float(x) - float(y) * floor(float(x) / float(y))
		"**":
			if both_int and y >= 0:
				return _pow_int(x, y)
			if x == 0 and y < 0:
				return err("ZeroDivisionError : 0 ne peut pas être mis à une puissance négative.")
			return pow(float(x), float(y))
	return err("Opération inconnue : %s" % op)


static func unop(op: String, a):
	if op == "not":
		return not truthy(a)
	if not is_num(a):
		return err("TypeError : le signe « %s » est impossible devant un %s." % [op, type_name(a)])
	if op == "-":
		return -num(a)
	return num(a)


static func cmp(op: String, a, b):
	var na := is_num(a)
	var nb := is_num(b)
	if op == "==" or op == "!=":
		var eq := false
		if na and nb:
			eq = num(a) == num(b)
		elif typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
			eq = a == b
		elif typeof(a) == TYPE_NIL and typeof(b) == TYPE_NIL:
			eq = true
		return eq if op == "==" else not eq
	var x
	var y
	if na and nb:
		x = num(a)
		y = num(b)
	elif typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
		x = a
		y = b
	else:
		return err("TypeError : « %s » est impossible entre %s et %s." % [op, type_name(a), type_name(b)])
	match op:
		"<":
			return x < y
		"<=":
			return x <= y
		">":
			return x > y
		">=":
			return x >= y
	return err("Comparaison inconnue : %s" % op)
