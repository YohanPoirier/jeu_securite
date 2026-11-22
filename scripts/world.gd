extends RefCounted
## Le monde d'un niveau : un rail dans un entrepôt, un ou plusieurs robots, des intrus qui
## apparaissent au milieu et filent vers l'une des deux portes (aux extrémités).
## Simulation par ticks, déterministe pour une graine donnée.
##
## Ordre d'un tick : 1) chaque robot exécute son programme (dans l'ordre de la liste)
##                   2) les intrus avancent  3) interceptions.
## Un intrus est arrêté si un robot est sur sa case, ou s'ils se sont croisés pendant le tick.

const VM = preload("res://scripts/vm.gd")
const PyOps = preload("res://scripts/pyops.gd")

const API_ARITY := {
	"avancer": 0, "reculer": 0, "attendre": 1,
	"fin_de_rail": 0, "debut_de_rail": 0, "position": 0, "longueur": 0,
}

const API_DOC := {
	"avancer": "avancer() : avance d'une case vers la droite (1 tick)",
	"reculer": "reculer() : recule d'une case vers la gauche (1 tick)",
	"attendre": "attendre(n) : ne fait rien pendant n ticks",
	"fin_de_rail": "fin_de_rail() : True si le robot est tout à droite (instantané)",
	"debut_de_rail": "debut_de_rail() : True si le robot est tout à gauche (instantané)",
	"position": "position() : numéro de la case du robot, 0 = tout à gauche (instantané)",
	"longueur": "longueur() : nombre de cases du rail (instantané)",
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
var duree_max := 150


## codes : {id du robot -> code compilé}. Un robot sans code reste immobile ; un code `null`
## (programme qui ne compile pas) met le robot hors service (HS) dès le départ.
func _init(p_level: Dictionary, codes: Dictionary, p_seed: int) -> void:
	level = p_level
	seed_used = p_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var l = level.get("longueur", 6)
	if l is Array:
		length = rng.randi_range(int(l[0]), int(l[1]))
	else:
		length = int(l)
	duree_max = int(level.get("duree_max", 150))
	var cfg: Dictionary = level.get("intrus", {})
	var n := int(cfg.get("nombre", 1))
	var ap: Array = cfg.get("apparition", [2, 6])
	var gap := int(cfg.get("ecart", 0))
	var periode := int(cfg.get("periode", 3))
	var centre := length / 2
	for i in n:
		var spawn := rng.randi_range(int(ap[0]), int(ap[1])) + i * gap
		var d := 1 if rng.randi_range(0, 1) == 1 else -1
		intruders.append({
			"spawn": spawn, "dir": d, "periode": periode, "t0": 0,
			"pos": centre, "prev": centre, "state": "attente",
		})
	var specs: Array = level.get("robots", [{"id": "robot", "nom": "Robot", "depart": 0}])
	for spec in specs:
		var start := clampi(int(spec.get("depart", 0)), 0, length - 1)
		var code = codes.get(spec.id, [])
		var rb := {"id": spec.id, "nom": spec.get("nom", spec.id), "pos": start, "prev": start, "vm": null, "hs": code == null}
		var vm := VM.new(code if code != null else [], self, level.get("builtins", []))
		vm.robot_ref = rb
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
			if rb.pos < length - 1:
				rb.pos += 1
			return {"value": null, "cost": 1}
		"reculer":
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
	return PyOps.err("Fonction inconnue : %s" % name)


# ---------- simulation ----------

func _caught(it: Dictionary) -> bool:
	for rb in robots:
		if rb.hs:
			continue  # un robot HS n'arrête personne
		if rb.pos == it.pos or (rb.prev == it.pos and rb.pos == it.prev):
			return true
	return false


func tick() -> void:
	if status != "en_cours":
		return
	tick_n += 1
	for rb in robots:
		rb.prev = rb.pos
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
		it.prev = it.pos
		if it.state == "attente" and tick_n >= it.spawn:
			it.state = "actif"
			it.t0 = tick_n
			it.prev = it.pos
		elif it.state == "actif" and (tick_n - it.t0) % it.periode == 0:
			it.pos += it.dir
		if it.state == "actif":
			if _caught(it):
				it.state = "arrete"
			elif it.pos <= 0 or it.pos >= length - 1:
				it.state = "intrusion"
				status = "defaite"
				message = "Un intrus a atteint une porte."
				return
		if it.state != "arrete":
			all_caught = false
	if all_caught:
		status = "victoire"
		message = "Tous les intrus ont été arrêtés."
	elif tick_n >= duree_max:
		status = "defaite"
		message = "Temps écoulé : tous les intrus n'ont pas été arrêtés."
