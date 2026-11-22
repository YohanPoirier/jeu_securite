extends RefCounted
## Façade : texte du joueur -> code exécutable, en appliquant les règles du niveau.
##   texte -> lexer -> parser (arbre neutre) -> gating (règles du niveau) -> compilateur

const Lexer = preload("res://scripts/lexer.gd")
const Parser = preload("res://scripts/parser.gd")
const Gating = preload("res://scripts/gating.gd")
const Compiler = preload("res://scripts/compiler.gd")


## Retourne {"ok": true, "code": [...]} ou {"ok": false, "line": n, "msg": "..."}
static func compile(src: String, syntaxe: Array, api: Array, builtins: Array) -> Dictionary:
	var lx := Lexer.tokenize(src)
	if not lx.ok:
		return lx
	var ps := Parser.new()
	var pr := ps.parse(lx.tokens)
	if not pr.ok:
		return pr
	var g := Gating.new()
	var errs := g.check(pr.ast, syntaxe, api, builtins)
	if errs.size() > 0:
		return {"ok": false, "line": errs[0].line, "msg": errs[0].msg}
	var cp := Compiler.new()
	return {"ok": true, "code": cp.compile(pr.ast)}
