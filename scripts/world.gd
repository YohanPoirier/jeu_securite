extends RefCounted
## Le monde d'un niveau : un rail (le couloir) dans un entrepôt, un ou plusieurs robots, des voleurs.
## Un voleur arrive de l'extérieur par l'une des deux portes (aux extrémités du couloir), la force,
## entre, va vers l'objet le plus proche (sur une étagère, dans une salle), le prend, puis essaie
## de ressortir par la porte la plus proche. Simulation par ticks, déterministe pour une graine.
##
## Coordonnées d'un voleur : x = numéro de case du couloir (les portes sont en -1 et length),
## ry = décalage vertical (0 = couloir, ±1 = seuil de salle, ±2 = sol de la salle, ±3 = étagère).
##
## Ordre d'un tick : 1) chaque robot exécute son programme (dans l'ordre de la liste)
##                   2) les voleurs avancent  3) interceptions.
## Un voleur est arrêté s'il est dans le couloir avec un robot sur sa case, ou s'ils se sont croisés.
## Un voleur qui ressort avec un objet fait perdre la partie.

const VM = preload("res://scripts/vm.gd")
const PyOps = preload("res://scripts/pyops.gd")

const API_ARITY := {
	"avancer": 0, "reculer": 0, "attendre": 1,
	"fin_de_rail": 0, "debut_de_rail": 0, "position": 0, "longueur": 0,
	"vu": 0, "assommer": 0,
}

const API_DOC := {
	"avancer": "avancer() : avance d'une case vers la droite (1 tick)",
	"reculer": "reculer() : recule d'une case vers la gauche (1 tick)",
	"attendre": "attendre(n) : ne fait rien pendant n ticks",
	"fin_de_rail": "fin_de_rail() : True si le robot est tout à droite (instantané)",
	"debut_de_rail": "debut_de_rail() : True si le robot est tout à gauche (instantané)",
	"position": "position() : numéro de la case du robot, 0 = tout à gauche (instantané)",
	"longueur": "longueur() : nombre de cases du rail (instantané)",
	"vu": "vu() : True si un voleur est sur ta case ou sur la case devant toi (instantané)",
	"assommer": "assommer() : assomme le voleur sur ta case ou sur la case devant toi (1 tick)",
}

var level: Dictionary
var length := 6
var robots: Array = []
var intruders: Array = []
var tick_n := 0
var status := "en_cours"  # en_cours | victoire | defaite
var events: Array = []  # robots tombés en panne (HS) pendant un tick : {id, nom, line, msg}
var message := ""
var seed_used := 0
var rng := RandomNumberGenerator.new()
var taken: Dictionary = {}  # étagères déjà vidées : Vector2i(colonne, ±3) -> true
var gates: Array = [{"state": "ferme"}, {"state": "ferme"}]  # porte gauche, porte droite (ferme | force | entrouverte | ouverte)
var _reserved: Dictionary = {}
const START_OUT := 4  # les voleurs partent à cette distance en dehors de l'écran


## codes : {id du robot -> code compilé}. Un robot sans code reste immobile ; un code `null`
## (programme qui ne compile pas) met le robot hors service (HS) dès le départ.
func _init(p_level: Dictionary, codes: Dictionary, p_seed: int) -> void:
	level = p_level
	seed_used = p_seed
	rng.seed = p_seed
	var l = level.get("longueur", 6)
	if l is Array:
		length = rng.randi_range(int(l[0]), int(l[1]))
	else:
		length = int(l)
	var cfg: Dictionary = level.get("intrus", {})
	var n := int(cfg.get("nombre", 1))
	var ap: Array = cfg.get("apparition", [2, 6])
	var gap := int(cfg.get("ecart", 0))
	var periode := int(cfg.get("periode", 3))
	var forcer := int(cfg.get("forcer", 4))
	for i in n:
		var spawn := rng.randi_range(int(ap[0]), int(ap[1])) + i * gap
		var side := 1 if rng.randi_range(0, 1) == 1 else -1  # côté par lequel il arrive
		var x0 := -START_OUT if side == 1 else length - 1 + START_OUT
		intruders.append({
			"spawn": spawn, "side": side, "dir": side, "periode": periode, "t0": 0, "forcer": forcer,
			"x": x0, "ry": 0, "px": x0, "py": 0, "pos": x0, "prev": x0,
			"state": "attente", "phase": "arrivee", "path": [], "loot": false, "target": Vector2i.ZERO,
			"force_left": 0, "face": side, "escaped": false,
		})
	var specs: Array = level.get("robots", [{"id": "robot", "nom": "Robot", "depart": 0}])
	for spec in specs:
		var start := clampi(int(spec.get("depart", 0)), 0, length - 1)
		var code = codes.get(spec.id, [])
		var rb := {"id": spec.id, "nom": spec.get("nom", spec.id), "pos": start, "prev": start, "vm": null, "hs": code == null, "facing": 1, "stun": false}
		var vm := VM.new(code if code != null else [], self, level.get("builtins", []))
		vm.robot_ref = rb
		vm.budget = int(level.get("reflexion", 200))
		rb.vm = vm
		robots.append(rb)


# ---------- API fournie aux programmes ----------

func has_api(name: String) -> bool:
	return API_ARITY.has(name)


func call_api(name: String, args: Array, rb: Dictionary):
	if args.size() != API_ARITY[name]:
		return PyOps.err("TypeError : %s() attend %d argument(s), pas %d." % [name, API_ARITY[name], args.size()])
	match name:
		"avancer":
			rb.facing = 1  # le robot regarde (et éclaire) du côté où il va
			if rb.pos < length - 1:
				rb.pos += 1
			return {"value": null, "cost": 1}
		"reculer":
			rb.facing = -1
			if rb.pos > 0:
				rb.pos -= 1
			return {"value": null, "cost": 1}
		"attendre":
			if typeof(args[0]) != TYPE_INT or args[0] < 0:
				return PyOps.err("ValueError : attendre(n) attend un nombre entier positif ou nul.")
			return {"value": null, "cost": args[0]}
		"fin_de_rail":
			return {"value": rb.pos == length - 1, "cost": 0}
		"debut_de_rail":
			return {"value": rb.pos == 0, "cost": 0}
		"position":
			return {"value": rb.pos, "cost": 0}
		"longueur":
			return {"value": length, "cost": 0}
		"vu":
			return {"value": _sees_thief(rb), "cost": 0}
		"assommer":
			rb.stun = true  # résolu à la fin du tick, sur la situation du début du tick
			return {"value": null, "cost": 1}
	return PyOps.err("Fonction inconnue : %s" % name)


# ---------- simulation ----------

## Les salles (identiques à l'affichage) : colonne de départ (case du couloir) et largeur.
func rooms() -> Array:
	var n := maxi(1, (length + 1) / 3)
	var free := length - (n - 1)
	var base := free / n
	var extra := free % n
	var out: Array = []
	var c := 0
	for i in n:
		var w := base + (1 if i < extra else 0)
		out.append({"c0": c, "w": w})
		c += w + 1
	return out


func _room_of(col: int) -> Dictionary:
	for r in rooms():
		if col >= r.c0 and col < r.c0 + r.w:
			return r
	return rooms()[0]


## Chemin (liste de cases (x, ry)) du couloir en `x` jusqu'au sol devant l'étagère `item`.
func _path_to(x: int, item: Vector2i) -> Array:
	var room := _room_of(item.x)
	var sgn := 1 if item.y > 0 else -1
	var out: Array = []
	var cx := x
	while cx != room.c0:
		cx += 1 if room.c0 > cx else -1
		out.append(Vector2i(cx, 0))
	out.append(Vector2i(room.c0, sgn))
	out.append(Vector2i(room.c0, sgn * 2))
	var fx: int = room.c0
	while fx != item.x:
		fx += 1 if item.x > fx else -1
		out.append(Vector2i(fx, sgn * 2))
	return out


## L'objet disponible le plus proche (en nombre de pas) d'une porte.
func _nearest_item(x: int) -> Vector2i:
	var best := Vector2i(-99, -99)
	var best_len := 1 << 30
	var ties := 0
	for room in rooms():
		for j in room.w:
			for sgn in [-1, 1]:
				var item := Vector2i(room.c0 + j, 3 * sgn)
				if taken.has(item) or _reserved.has(item):
					continue
				var d := _path_to(x, item).size()
				if d < best_len:
					best_len = d
					best = item
					ties = 1
				elif d == best_len:
					ties += 1
					if rng.randi_range(1, ties) == 1:  # départage au hasard (déterministe : graine)
						best = item
	return best


## Chemin retour : de la case (x, ry) jusqu'à la porte la plus proche (case -1 ou length).
func _path_out(x: int, ry: int, prefer: int) -> Array:  # prefer = côté d'entrée (-1 gauche, +1 droite)
	var out: Array = []
	var sgn := 0 if ry == 0 else (1 if ry > 0 else -1)
	var room := _room_of(x)
	var cx := x
	var cy := ry
	if cy != 0:
		# on remonte le sol jusqu'au seuil, puis au couloir
		while cx != room.c0:
			cx += 1 if room.c0 > cx else -1
			out.append(Vector2i(cx, cy))
		while cy != 0:
			cy -= sgn
			out.append(Vector2i(cx, cy))
	# il ressort par l'autre porte que celle qu'il a forcée (qui est encore entrouverte)
	var gate := length if prefer == 1 else -1
	while cx != gate:
		cx += 1 if gate > cx else -1
		out.append(Vector2i(cx, 0))
	return out


func _gate_index(it: Dictionary) -> int:
	return 0 if it.side == 1 else 1


## Les cases que surveille un robot : la sienne et celle devant lui.
func _watched(rb: Dictionary) -> Array:
	return [rb.pos, rb.pos + rb.facing]


func _sees_thief(rb: Dictionary) -> bool:
	var cells := _watched(rb)
	for it in intruders:
		if it.state == "actif" and it.ry == 0 and cells.has(it.x):
			return true
	return false


func _move_to(it: Dictionary, c: Vector2i) -> void:
	if c.x != it.x:
		it.face = 1 if c.x > it.x else -1
	it.x = c.x
	it.ry = c.y
	it.pos = it.x


func _step_thief(it: Dictionary) -> void:
	match it.phase:
		"arrivee":
			_move_to(it, Vector2i(it.x + it.side, 0))
			if (it.side == 1 and it.x == -1) or (it.side == -1 and it.x == length):
				it.phase = "force"
				it.force_left = it.forcer
				gates[_gate_index(it)].state = "force"
		"entree":
			_move_to(it, Vector2i(it.x + it.side, 0))
			gates[_gate_index(it)].state = "entrouverte"  # la porte se referme, mais pas tout à fait
			var item := _nearest_item(it.x)
			it.target = item
			_reserved[item] = true
			it.path = _path_to(it.x, item)
			it.phase = "va"
		"va":
			if it.path.is_empty():
				taken[it.target] = true
				it.loot = true
				it.path = _path_out(it.x, it.ry, it.side)
				it.phase = "fuite"
			else:
				_move_to(it, it.path.pop_front())
		"fuite":
			if it.path.is_empty():
				return
			_move_to(it, it.path.pop_front())
			if it.x == -1 or it.x == length:
				gates[0 if it.x == -1 else 1].state = "ouverte"
				it.escaped = true  # jugé après les coups de matraque du même tick


func tick() -> void:
	if status != "en_cours":
		return
	tick_n += 1
	for rb in robots:
		rb.prev = rb.pos
		rb.stun = false
	for rb in robots:
		if rb.hs:
			continue
		var vm = rb.vm
		vm.step()
		if not vm.error.is_empty():
			# une erreur ne stoppe pas la partie : ce robot-là est simplement hors service
			rb.hs = true
			events.append({"id": rb.id, "nom": rb.nom, "line": vm.error.line, "msg": vm.error.msg})
	var all_caught := true
	for it in intruders:
		it.px = it.x
		it.py = it.ry
		it.prev = it.x
		if it.state == "attente" and tick_n >= it.spawn:
			it.state = "actif"
			it.t0 = tick_n
		elif it.state == "actif":
			if it.phase == "force":
				it.force_left -= 1
				if it.force_left <= 0:
					it.phase = "entree"
			elif (tick_n - it.t0) % it.periode == 0:
				_step_thief(it)
	# les coups de matraque : sur les cases surveillées au DÉBUT du tick (le voleur qui vient de bouger est touché quand même)
	for rb in robots:
		if rb.hs or not rb.stun:
			continue
		var cells := [rb.prev, rb.prev + rb.facing]
		for it in intruders:
			if it.state == "actif" and it.py == 0 and cells.has(it.px):
				it.state = "arrete"
	for it in intruders:
		if it.state != "arrete":
			if it.escaped:
				status = "defaite"
				message = "Un voleur s'est enfui avec un objet."
				return
			all_caught = false
	if all_caught:
		status = "victoire"
		message = "Tous les intrus ont été arrêtés."
