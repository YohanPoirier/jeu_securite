extends RefCounted
## Analyse lexicale : texte -> liste de jetons (avec INDENT / DEDENT comme en Python).
## Jeton = {"t": type, "v": valeur, "line": numéro de ligne}
## Types : NUM, STR, NAME, OP, NEWLINE, INDENT, DEDENT, EOF

const OPS3 := ["//=", "**="]
const OPS2 := ["**", "//", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%="]
const OPS1 := "+-*/%<>=(),:"


static func _tok(t: String, v, line: int) -> Dictionary:
	return {"t": t, "v": v, "line": line}


static func _err(line: int, msg: String) -> Dictionary:
	return {"ok": false, "line": line, "msg": msg}


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_alpha(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c.unicode_at(0) > 127


static func tokenize(src: String) -> Dictionary:
	var tokens: Array = []
	var indents: Array = [0]
	var depth := 0
	var open_lines: Array = []
	var lines := src.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var ln := 0
	for raw in lines:
		ln += 1
		var line: String = raw
		var n := line.length()
		var i := 0
		if depth == 0:
			var col := 0
			while i < n and line[i] == " ":
				col += 1
				i += 1
			if i < n and line[i] == "\t":
				return _err(ln, "Utilise des espaces pour indenter (pas de tabulation).")
			if i >= n or line[i] == "#":
				continue
			if col > indents[-1]:
				indents.append(col)
				tokens.append(_tok("INDENT", null, ln))
			else:
				while col < indents[-1]:
					indents.pop_back()
					tokens.append(_tok("DEDENT", null, ln))
				if col != indents[-1]:
					return _err(ln, "IndentationError : l'indentation ne correspond à aucun bloc précédent.")
		while i < n:
			var c := line[i]
			if c == " ":
				i += 1
				continue
			if c == "\t":
				return _err(ln, "Utilise des espaces pour indenter (pas de tabulation).")
			if c == "#":
				break
			if _is_digit(c):
				var j := i
				while j < n and _is_digit(line[j]):
					j += 1
				var is_float := false
				if j + 1 < n and line[j] == "." and _is_digit(line[j + 1]):
					is_float = true
					j += 1
					while j < n and _is_digit(line[j]):
						j += 1
				if j < n and _is_alpha(line[j]):
					return _err(ln, "Nombre mal écrit près de « %s »." % line.substr(i, j - i + 1))
				var txt := line.substr(i, j - i)
				if is_float:
					tokens.append(_tok("NUM", txt.to_float(), ln))
				else:
					tokens.append(_tok("NUM", txt.to_int(), ln))
				i = j
				continue
			if _is_alpha(c):
				var j := i
				while j < n and (_is_alpha(line[j]) or _is_digit(line[j])):
					j += 1
				tokens.append(_tok("NAME", line.substr(i, j - i), ln))
				i = j
				continue
			if c == "\"" or c == "'":
				var j := i + 1
				var s := ""
				var closed := false
				while j < n:
					var d := line[j]
					if d == "\\" and j + 1 < n:
						var e := line[j + 1]
						match e:
							"n":
								s += "\n"
							"t":
								s += "\t"
							"\\":
								s += "\\"
							"'":
								s += "'"
							"\"":
								s += "\""
							_:
								s += "\\" + e
						j += 2
						continue
					if d == c:
						closed = true
						j += 1
						break
					s += d
					j += 1
				if not closed:
					return _err(ln, "Texte non terminé : il manque le guillemet fermant.")
				tokens.append(_tok("STR", s, ln))
				i = j
				continue
			var three := line.substr(i, 3)
			if OPS3.has(three):
				tokens.append(_tok("OP", three, ln))
				i += 3
				continue
			var two := line.substr(i, 2)
			if OPS2.has(two):
				tokens.append(_tok("OP", two, ln))
				i += 2
				continue
			if OPS1.contains(c):
				if c == "(":
					depth += 1
					open_lines.append(ln)
				elif c == ")":
					depth -= 1
					if depth >= 0:
						open_lines.pop_back()
					if depth < 0:
						return _err(ln, "Parenthèse fermante « ) » sans parenthèse ouvrante.")
				tokens.append(_tok("OP", c, ln))
				i += 1
				continue
			return _err(ln, "Caractère inattendu : « %s »." % c)
		if depth == 0:
			tokens.append(_tok("NEWLINE", null, ln))
	if depth > 0:
		return _err(open_lines[-1], "Il manque une parenthèse fermante « ) » (celle ouverte ici).")
	while indents.size() > 1:
		indents.pop_back()
		tokens.append(_tok("DEDENT", null, ln))
	tokens.append(_tok("EOF", null, ln))
	return {"ok": true, "tokens": tokens}
