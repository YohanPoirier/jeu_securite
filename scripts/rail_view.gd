extends Control
## L'entrepôt vu de dessus, dessiné sur une grille de cases : pelouse et décor autour, murs, couloir
## (c'est le rail), petites salles pleines d'étagères, portes, robots et intrus.
## La nuit est tombée : tout est assombri, sauf ce qu'éclaire la lampe de poche du vigile (un faisceau
## qui couvre la case devant lui) et la pelouse autour des lampadaires.
## Pour l'instant c'est purement graphique : la logique du jeu reste celle du rail (world.gd).
##
## Déplacement « au tour par tour » : pendant un tick, l'élément glisse vers sa nouvelle case
## sur la première partie du tick (MOVE_FRACTION), puis marque une pause jusqu'au tick suivant.
## Un clic sur un robot émet robot_clicked(id) : l'interface ouvre alors son éditeur.

signal robot_clicked(id: String)
signal background_clicked  # clic dans l'entrepôt, hors de tout robot

var world = null
var alpha := 1.0  # avancement dans le tick courant, de 0 à 1
var hover := -1  # indice du robot survolé
var inset_top := 0.0  # hauteur de la barre du haut (l'entrepôt se centre entre les deux barres)
var inset_bottom := 0.0

const ROWS := 11
const RAIL_ROW := 5  # rangée du couloir
const MARGIN := 3  # colonnes avant la première case du rail : pelouse, pelouse, mur et porte
const MOVE_FRACTION := 0.55  # part du tick consacrée au glissement ; le reste est la pause

const C_GRASS := Color(0.20, 0.38, 0.22)
const C_FLOOR := Color(0.43, 0.44, 0.48)
const C_TILE := Color(0.37, 0.38, 0.42)
const C_CORRIDOR := Color(0.54, 0.55, 0.59)
const C_WALL := Color(0.55, 0.42, 0.36)
const C_MORTAR := Color(0.38, 0.28, 0.25)
const C_DOOR := Color(0.85, 0.65, 0.20)
const C_ROBOT := Color(0.25, 0.60, 0.95)
const CRATES := [Color(0.65, 0.48, 0.30), Color(0.50, 0.58, 0.64), Color(0.72, 0.60, 0.34), Color(0.40, 0.55, 0.47)]

var _brain_tex: Texture2D = null
var _gate_angle := [0.0, 0.0]  # angle d'ouverture affiché des deux portes (animé)
var _night: ColorRect = null  # calque d'obscurité (shader) posé sur l'entrepôt
var _hud: Control = null  # calque des noms et du cerveau, au-dessus de la nuit

const NIGHT_SHADER := """
shader_type canvas_item;
uniform vec4 skip_a;         // demi-case extérieure de la porte de gauche (traitée comme dehors)
uniform vec4 skip_b;         // idem, porte de droite
uniform vec4 box;            // zone intérieure de l'entrepôt : x, y, largeur, hauteur (pixels)
uniform float out_alpha = 0.30;
uniform float in_alpha = 0.55;
uniform float cell = 48.0;
uniform int count = 0;       // nombre de lampes de poche
uniform vec2 pos[8];         // position de la lampe (pixels)
uniform vec2 dir[8];         // direction du faisceau (vecteur unitaire)
uniform vec2 body[8];        // centre du corps du robot (petit halo)
uniform int lamp_count = 0;  // lampadaires
uniform vec2 lamp[32];
varying vec2 vpos;
void vertex() { vpos = VERTEX; }
void fragment() {
	vec2 p = vpos;
	bool inside = p.x >= box.x && p.x <= box.x + box.z && p.y >= box.y && p.y <= box.y + box.w;
	if (p.x >= skip_a.x && p.x <= skip_a.x + skip_a.z && p.y >= skip_a.y && p.y <= skip_a.y + skip_a.w) { inside = false; }
	if (p.x >= skip_b.x && p.x <= skip_b.x + skip_b.z && p.y >= skip_b.y && p.y <= skip_b.y + skip_b.w) { inside = false; }
	float a = inside ? in_alpha : out_alpha;
	float light = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= count) { break; }
		vec2 d = dir[i];
		vec2 q = p - pos[i];
		float along = dot(q, d);
		float across = abs(dot(q, vec2(-d.y, d.x)));
		float len = cell * 1.1;
		float t = clamp(along / len, 0.0, 1.0);
		float hw = mix(cell * 0.05, cell * 0.50, t);
		float cone = (1.0 - smoothstep(hw * 0.65, hw, across))
			* smoothstep(-cell * 0.03, cell * 0.04, along)
			* (1.0 - smoothstep(len * 0.80, len, along));
		float halo = 1.0 - smoothstep(cell * 0.10, cell * 0.30, length(p - body[i]));
		light = max(light, max(cone * 0.92, halo * 0.75));
	}
	for (int j = 0; j < 32; j++) {
		if (j >= lamp_count) { break; }
		float g = 1.0 - smoothstep(0.0, cell * 2.5, length(p - lamp[j]));
		light = max(light, g * g * 0.75);
	}
	vec3 night = vec3(0.02, 0.03, 0.08);
	vec3 warm = vec3(1.0, 0.90, 0.58);
	COLOR = vec4(mix(night, warm, light), mix(a, 0.10, light));
}
"""


func _ready() -> void:
	var sh := Shader.new()
	sh.code = NIGHT_SHADER
	_night = ColorRect.new()
	_night.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night.material = ShaderMaterial.new()
	_night.material.shader = sh
	add_child(_night)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	add_child(_hud)


## Géométrie de la grille, commune au dessin et aux clics.
## Le rail occupe les colonnes k, k+1, ... ; les portes sont dans les murs, de part et d'autre.
func _layout() -> Dictionary:
	var l: int = world.length if world != null else 6
	var cols := l + 2 * MARGIN
	var avail_h := size.y - inset_top - inset_bottom
	var cell: float = minf(size.x / float(cols), avail_h / float(ROWS))
	return {
		"l": l, "cols": cols, "cell": cell,
		"x0": (size.x - cell * cols) / 2.0,
		"y0": inset_top + (avail_h - cell * ROWS) / 2.0,
		"k": MARGIN,
	}


func _cell_rect(lay: Dictionary, col: int, row: int) -> Rect2:
	return Rect2(lay.x0 + col * lay.cell, lay.y0 + row * lay.cell, lay.cell, lay.cell)


## Position fluide (en cases) entre l'ancienne et la nouvelle case : glisse puis pause.
func _smooth(prev: int, pos: int) -> float:
	var u := clampf(alpha / MOVE_FRACTION, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)  # départ et arrivée en douceur
	return lerpf(float(prev), float(pos), u)


## Temps affiché, en ticks (continu) : l'état du tick courant est atteint à alpha = 1.
func _t_now() -> float:
	return float(world.tick_n - 1) + alpha


## Position affichée (en cases) d'un voleur : il marche en continu vers sa prochaine case pendant
## toute la durée de son pas, au lieu de sauter d'une case à l'autre.
func _thief_visual(it: Dictionary) -> Vector2:
	if it.state != "actif":
		return Vector2(it.x, it.ry)
	var t := _t_now()
	var per := float(it.periode)
	if t >= float(it.ws):
		var k := clampf((t - float(it.ws)) / per, 0.0, 1.0) if it.wt != it.wf else 0.0
		return Vector2(it.wf).lerp(Vector2(it.wt), k)
	var k2 := clampf((t - float(it.pws)) / per, 0.0, 1.0) if it.pwt != it.pwf else 1.0
	return Vector2(it.pwf).lerp(Vector2(it.pwt), k2)


func _smooth_t() -> float:
	var u := clampf(alpha / MOVE_FRACTION, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _robot_center(lay: Dictionary, rb: Dictionary) -> Vector2:
	var col: float = lay.k + _smooth(rb.prev, rb.pos)
	return Vector2(lay.x0 + (col + 0.5) * lay.cell, lay.y0 + (RAIL_ROW + 0.5) * lay.cell)


## Plusieurs personnages sur une même case : on les range côte à côte, en plus petit.
## Retourne {clé -> {"off": décalage en cases, "sc": échelle}} ; clés « r<id> » (robots) et « t<n> » (intrus).
func _slots() -> Dictionary:
	var by_cell: Dictionary = {}
	if world == null:
		return by_cell
	for rb in world.robots:
		var key: int = rb.pos
		by_cell[key] = by_cell.get(key, []) + ["r" + str(rb.id)]
	for j in world.intruders.size():
		if world.intruders[j].state != "attente":
			var key2: int = world.intruders[j].x + world.intruders[j].ry * 1000
			by_cell[key2] = by_cell.get(key2, []) + ["t" + str(j)]
	var out: Dictionary = {}
	for key in by_cell:
		var ids: Array = by_cell[key]
		# le vigile se range du côté éclairé (devant lui) : les intrus restent derrière, dans l'ombre
		var guards: Array = ids.filter(func(k): return k.begins_with("r"))
		var others: Array = ids.filter(func(k): return not k.begins_with("r"))
		var f := 1
		for rb in world.robots:
			if "r" + str(rb.id) == guards[0] if guards.size() > 0 else false:
				f = rb.facing
		ids = others + guards if f >= 0 else guards + others
		var n := ids.size()
		for idx in n:
			var off := Vector2.ZERO
			var sc := 1.0
			if n == 2:
				off = Vector2(-0.22 + 0.44 * idx, 0.0)
				sc = 0.82
			elif n == 3:
				off = Vector2(-0.30 + 0.30 * idx, 0.07 if idx != 1 else -0.08)
				sc = 0.72
			elif n > 3:
				var cols := ceili(n / 2.0)
				off = Vector2((idx % cols - (cols - 1) / 2.0) * 0.30, ((idx / cols) - 0.5) * 0.34)
				sc = 0.60
			out[ids[idx]] = {"off": off, "sc": sc}
	return out


func _slot(slots: Dictionary, key: String) -> Dictionary:
	return slots.get(key, {"off": Vector2.ZERO, "sc": 1.0})


func _robot_pos(lay: Dictionary, rb: Dictionary, slots: Dictionary) -> Vector2:
	return _robot_center(lay, rb) + _slot(slots, "r" + str(rb.id)).off * lay.cell


func _robot_rect(lay: Dictionary, rb: Dictionary, slots := {}) -> Rect2:
	var sl: Dictionary = _slot(slots, "r" + str(rb.id))
	var s: float = lay.cell * 0.7 * sl.sc
	return Rect2(_robot_pos(lay, rb, slots) - Vector2(s, s) / 2.0, Vector2(s, s))


func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	var lay := _layout()
	var slots := _slots()
	if event is InputEventMouseMotion:
		var h := -1
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i], slots).grow(6.0).has_point(event.position):
				h = i
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i], slots).grow(6.0).has_point(event.position):
				robot_clicked.emit(world.robots[i].id)
				return
		background_clicked.emit()


# ---------- petits outils de dessin ----------

## Rectangle à coins arrondis (avec contour facultatif).
func _rr(r: Rect2, color: Color, radius: float, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(maxi(1, int(radius)))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
		if color.a == 0.0:
			sb.draw_center = false
	draw_style_box(sb, r)


## Nombre pseudo-aléatoire fixe pour une case : le décor ne change jamais d'une partie à l'autre.
func _hash(c: int, r: int) -> int:
	return absi((c * 73856093) ^ (r * 19349663) ^ 83492791) % 1000003


func _inside(lay: Dictionary, c: int, r: int) -> bool:
	return c >= 2 and c <= lay.k + lay.l and r >= 1 and r <= ROWS - 2


## Salles : de part et d'autre du couloir, séparées par un mur d'une colonne.
func _rooms(l: int) -> Array:
	var out: Array = []
	for r in world.rooms():
		out.append({"c0": MARGIN + r.c0, "w": r.w})
	return out


# ---------- dessin ----------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var lay := _layout()
	var lamps: Array = []
	draw_rect(Rect2(Vector2.ZERO, size), C_GRASS)
	_draw_outside(lay, lamps)
	_draw_warehouse(lay, font)
	var slots := _slots()
	if world != null:
		for j in world.intruders.size():
			if world.intruders[j].state != "attente":
				_draw_thief(lay, world.intruders[j], _slot(slots, "t" + str(j)))
		for i in world.robots.size():
			_draw_robot(lay, world.robots[i], i == hover, _slot(slots, "r" + str(world.robots[i].id)))
	_update_night(lay, lamps, slots)
	_hud.queue_redraw()


## Noms, « clic : programmer » et cerveau : par-dessus la nuit, pour rester lisibles.
## Quatre petits coins autour d'une case.
## `only` : les coins à tracer (0 haut-gauche, 1 haut-droit, 2 bas-gauche, 3 bas-droit).
func _marker(rc: Rect2, col: Color, only := [0, 1, 2, 3]) -> void:
	var r := rc.grow(-3.0)
	var l := rc.size.x * 0.22
	var idx := -1
	for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)], [r.end, Vector2(-1, 0), Vector2(0, -1)]]:
		idx += 1
		if not only.has(idx):
			continue
		_hud.draw_line(corner[0], corner[0] + corner[1] * l, col, 2.0)
		_hud.draw_line(corner[0], corner[0] + corner[2] * l, col, 2.0)


func _draw_hud() -> void:
	if world == null:
		return
	var font := ThemeDB.fallback_font
	var lay := _layout()
	var cell: float = lay.cell
	var slots := _slots()
	# marqueurs de case discrets (coins) : voleurs en rouge, robots en bleu (+ la case devant, plus pâle)
	for it in world.intruders:
		if it.state == "actif":
			var only: Array = [0, 1, 2, 3]
			for rb2 in world.robots:
				if not rb2.hs and rb2.pos == it.x and it.ry == 0:
					only = [0, 3]  # case partagée avec un robot : voleur sur l'autre diagonale
			_marker(_cell_rect(lay, lay.k + it.x, RAIL_ROW + it.ry), Color(1.0, 0.40, 0.32, 0.65 if only.size() < 4 else 0.50), only)
	for rb in world.robots:
		if not rb.hs:
			var shared := false
			for it2 in world.intruders:
				if it2.state == "actif" and it2.ry == 0 and it2.x == rb.pos:
					shared = true
			# case partagée avec un voleur : coins alternés (robot sur la diagonale haut-droit / bas-gauche)
			_marker(_cell_rect(lay, lay.k + rb.pos, RAIL_ROW), Color(0.45, 0.85, 1.0, 0.65 if shared else 0.50), [1, 2] if shared else [0, 1, 2, 3])
	for i in world.robots.size():
		var rb: Dictionary = world.robots[i]
		var sl: Dictionary = _slot(slots, "r" + str(rb.id))
		var c: Vector2 = _robot_pos(lay, rb, slots)
		var broken: bool = rb.hs
		if rb.vm.thinking and not broken:
			_hud.draw_texture_rect(_brain(), Rect2(c + Vector2(cell * 0.10, -cell * (0.55 + 0.4 * sl.sc)), Vector2(cell * 0.7, cell * 0.7) * sl.sc), false)
		_hud.draw_string(font, Vector2(c.x - cell, c.y + cell * (0.40 + 0.22 * sl.sc)), String(rb.nom) + (" (HS)" if broken else ""),
			HORIZONTAL_ALIGNMENT_CENTER, cell * 2.0, 13, Color(1.0, 0.55, 0.55) if broken else Color(1, 1, 1, 0.95))
		if i == hover:
			_hud.draw_string(font, Vector2(c.x - cell * 1.5, c.y - cell * 0.62), "clic : programmer",
				HORIZONTAL_ALIGNMENT_CENTER, cell * 3.0, 13, Color(1, 1, 1, 0.95))


## Pelouse, arbres, buissons et lampadaires autour de l'entrepôt (décor fixe, tiré de la position).
func _draw_outside(lay: Dictionary, lamps: Array) -> void:
	var cell: float = lay.cell
	var c_min: int = floori(-lay.x0 / cell) - 1
	var c_max: int = ceili((size.x - lay.x0) / cell) + 1
	for r in range(-1, ROWS + 1):
		for c in range(c_min, c_max + 1):
			if _inside(lay, c, r):
				continue
			var rc := _cell_rect(lay, c, r)
			var h := _hash(c, r)
			var ctr := rc.get_center()
			if (r == 0 or r == ROWS - 1) and posmod(c, 5) == 0:
				_draw_lamp(ctr, cell)
				lamps.append(ctr + Vector2(0, -cell * 0.42))
			elif h % 6 == 0:
				_draw_tree(ctr, cell, h)
			elif h % 6 == 1:
				_draw_bush(ctr, cell, h)
			elif h % 3 == 0:
				for j in 3:
					var p := rc.position + Vector2(cell * (0.2 + 0.3 * j), cell * (0.35 + 0.2 * ((h >> j) % 3)))
					draw_line(p, p + Vector2(-2, -5), C_GRASS.lightened(0.18), 1.5)
					draw_line(p, p + Vector2(2, -6), C_GRASS.lightened(0.12), 1.5)


func _draw_tree(ctr: Vector2, cell: float, h: int) -> void:
	var s := 0.8 + 0.25 * float(h % 3) / 2.0
	draw_set_transform(ctr + Vector2(0, cell * 0.30), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, cell * 0.36 * s, Color(0, 0, 0, 0.30))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_rr(Rect2(ctr + Vector2(-cell * 0.06, -cell * 0.02), Vector2(cell * 0.12, cell * 0.34)), Color(0.36, 0.25, 0.16), 2)
	var g := Color(0.12, 0.30, 0.16)
	draw_circle(ctr + Vector2(-cell * 0.16, -cell * 0.08) * s, cell * 0.26 * s, g)
	draw_circle(ctr + Vector2(cell * 0.16, -cell * 0.08) * s, cell * 0.26 * s, g.darkened(0.05))
	draw_circle(ctr + Vector2(0, -cell * 0.24) * s, cell * 0.28 * s, g.lightened(0.10))
	draw_circle(ctr + Vector2(-cell * 0.06, -cell * 0.30) * s, cell * 0.10 * s, g.lightened(0.25))


func _draw_bush(ctr: Vector2, cell: float, h: int) -> void:
	var g := Color(0.16, 0.34, 0.19)
	draw_circle(ctr + Vector2(-cell * 0.14, cell * 0.08), cell * 0.20, g)
	draw_circle(ctr + Vector2(cell * 0.14, cell * 0.08), cell * 0.19, g.darkened(0.06))
	draw_circle(ctr + Vector2(0, -cell * 0.04), cell * 0.22, g.lightened(0.08))
	if h % 4 == 0:  # quelques fleurs
		draw_circle(ctr + Vector2(cell * 0.06, -cell * 0.08), 2.5, Color(0.95, 0.85, 0.40))


func _draw_lamp(ctr: Vector2, cell: float) -> void:
	_rr(Rect2(ctr + Vector2(-cell * 0.14, cell * 0.30), Vector2(cell * 0.28, cell * 0.08)), Color(0.20, 0.20, 0.24), 2)
	draw_rect(Rect2(ctr + Vector2(-cell * 0.03, -cell * 0.38), Vector2(cell * 0.06, cell * 0.72)), Color(0.28, 0.28, 0.32))
	_rr(Rect2(ctr + Vector2(-cell * 0.13, -cell * 0.50), Vector2(cell * 0.26, cell * 0.14)), Color(0.22, 0.22, 0.26), 3)
	draw_circle(ctr + Vector2(0, -cell * 0.42), cell * 0.075, Color(1.0, 0.93, 0.60))


## L'entrepôt : sol, couloir, salles, étagères pleines de marchandises, murs et portes.
func _draw_warehouse(lay: Dictionary, font: Font) -> void:
	var l: int = lay.l
	var k: int = lay.k
	var cell: float = lay.cell
	var right: int = k + l  # colonne du mur de droite
	var rooms := _rooms(l)
	var door_cols: Array = []
	var sep_cols: Array = []
	for i in rooms.size():
		door_cols.append(rooms[i].c0)
		if i < rooms.size() - 1:
			sep_cols.append(rooms[i].c0 + rooms[i].w)
	# sol de tout l'intérieur
	for r in range(2, ROWS - 2):
		for c in range(k, right):
			var rc := _cell_rect(lay, c, r)
			draw_rect(rc, C_FLOOR)
			draw_rect(rc, C_TILE, false, 1.0)
	# étagères au fond de chaque salle (rangée du haut et du bas)
	for room in rooms:
		for j in room.w:
			var rel: int = room.c0 + j - k
			_draw_shelf(_cell_rect(lay, room.c0 + j, 2), room.c0 + j, 2, world != null and world.taken.has(Vector2i(rel, -3)))
			_draw_shelf(_cell_rect(lay, room.c0 + j, ROWS - 3), room.c0 + j, ROWS - 3, world != null and world.taken.has(Vector2i(rel, 3)))
	var walls: Dictionary = {}
	# murs : pourtour, cloisons du couloir (avec une ouverture par salle) et séparations de salles
	for c in range(2, right + 1):
		_add_wall(walls, c, 1)
		_add_wall(walls, c, ROWS - 2)
	for r in range(1, ROWS - 1):
		if r != RAIL_ROW:
			_add_wall(walls, 2, r)
			_add_wall(walls, right, r)
	for c in range(k, right):
		for r in [RAIL_ROW - 1, RAIL_ROW + 1]:
			if door_cols.has(c):
				_draw_doorway(_cell_rect(lay, c, r))
			else:
				_add_wall(walls, c, r)
	for c in sep_cols:
		for r in [2, 3, ROWS - 4, ROWS - 3]:
			_add_wall(walls, c, r)
	_draw_walls(lay, walls)
	# portes aux extrémités du couloir
	for gc in [k - 1, right]:
		_draw_gate(_cell_rect(lay, gc, RAIL_ROW), gc == k - 1, font, 0 if gc == k - 1 else 1)


## Style des murs : true = traits fins (la case reste non marchable, mais le mur est dessiné étroit),
## false = cases de mur pleines (ancien style).
const THIN_WALLS := false
const WALL_T := 0.34  # épaisseur d'un mur fin, en fraction de case


func _add_wall(walls: Dictionary, c: int, r: int) -> void:
	walls[Vector2i(c, r)] = true


func _draw_walls(lay: Dictionary, walls: Dictionary) -> void:
	for key in walls:
		var rc := _cell_rect(lay, key.x, key.y)
		if not THIN_WALLS:
			_draw_wall(rc)
			continue
		var cell: float = lay.cell
		var t := cell * WALL_T
		var ctr := rc.get_center()
		# la case de mur est du sol, sauf en bordure de l'entrepôt (pelouse dehors)
		var outer: bool = key.y == 1 or key.y == ROWS - 2 or key.x == 2 or key.x == lay.k + lay.l
		# en bordure, le mur se colle au bord intérieur de sa case (côté entrepôt)
		if key.y == 1:
			ctr.y = rc.end.y - t / 2.0
		elif key.y == ROWS - 2:
			ctr.y = rc.position.y + t / 2.0
		if key.x == 2:
			ctr.x = rc.end.x - t / 2.0
		elif key.x == lay.k + lay.l:
			ctr.x = rc.position.x + t / 2.0
		if not outer:
			draw_rect(rc, C_FLOOR)
			draw_rect(rc, C_TILE, false, 1.0)
		var parts: Array = [Rect2(ctr - Vector2(t, t) / 2.0, Vector2(t, t))]
		if walls.has(key + Vector2i(1, 0)):
			parts.append(Rect2(ctr.x, ctr.y - t / 2.0, rc.end.x - ctr.x, t))
		if walls.has(key + Vector2i(-1, 0)):
			parts.append(Rect2(rc.position.x, ctr.y - t / 2.0, ctr.x - rc.position.x, t))
		if walls.has(key + Vector2i(0, 1)):
			parts.append(Rect2(ctr.x - t / 2.0, ctr.y, t, rc.end.y - ctr.y))
		if walls.has(key + Vector2i(0, -1)):
			parts.append(Rect2(ctr.x - t / 2.0, rc.position.y, t, ctr.y - rc.position.y))
		for pr in parts:
			draw_rect(pr, C_WALL)
		for pr in parts:  # arête claire en haut
			draw_rect(Rect2(pr.position, Vector2(pr.size.x, minf(3.0, pr.size.y * 0.25))), C_WALL.lightened(0.22))
		if parts.size() == 1:  # pilier isolé : contour
			draw_rect(parts[0], C_MORTAR.darkened(0.2), false, 1.0)


func _draw_wall(rc: Rect2) -> void:
	draw_rect(rc, C_WALL)
	var th := rc.size.y / 3.0
	for i in 3:
		var y := rc.position.y + th * i
		if i > 0:
			draw_line(Vector2(rc.position.x, y), Vector2(rc.end.x, y), C_MORTAR, 1.0)
		var x := rc.position.x + rc.size.x * (0.5 if i % 2 == 0 else 0.0)
		if i % 2 == 0:
			draw_line(Vector2(x, y), Vector2(x, y + th), C_MORTAR, 1.0)
	draw_rect(Rect2(rc.position, Vector2(rc.size.x, rc.size.y * 0.10)), C_WALL.lightened(0.20))
	draw_rect(rc, C_MORTAR.darkened(0.2), false, 1.0)


## Porte de l'entrepôt : fine plaque dorée au milieu de la case, herbe côté extérieur, poignées
## des deux côtés et petit tapis d'accueil devant.
func _draw_gate(rc: Rect2, left_side: bool, font: Font, gate_i := 0) -> void:
	var sgn := -1.0 if left_side else 1.0  # direction de l'extérieur
	var cx := rc.get_center().x
	var out_rc := Rect2(rc.position.x if left_side else cx, rc.position.y, rc.size.x / 2.0, rc.size.y)
	var in_rc := Rect2(cx if left_side else rc.position.x, rc.position.y, rc.size.x / 2.0, rc.size.y)
	draw_rect(in_rc, C_FLOOR)
	draw_rect(in_rc, C_TILE, false, 1.0)
	draw_rect(out_rc, C_GRASS)
	# tapis d'accueil, sur l'herbe, juste devant la porte
	var w := rc.size.x * 0.20
	var cell := rc.size.x
	var mat_x := cx - w / 2.0 - cell * 0.95 if left_side else cx + w / 2.0
	var mat := Rect2(mat_x, rc.get_center().y - cell * 0.30, cell * 0.95, cell * 0.60)
	draw_rect(mat, Color(0.55, 0.20, 0.18))
	draw_rect(mat.grow(-3.0), Color(0.40, 0.14, 0.14), false, 1.5)
	draw_string(font, Vector2(mat.position.x, mat.get_center().y + 3.5), "WELCOME", HORIZONTAL_ALIGNMENT_CENTER, mat.size.x, 8, Color(0.95, 0.85, 0.65))
	# plaque : pivote autour de sa charnière et s'ouvre vers l'extérieur. Charnière en haut pour la
	# porte de gauche, en bas pour celle de droite ; la poignée est du côté opposé (bout libre).
	var state := "ferme"
	if world != null:
		state = String(world.gates[gate_i].state)
	var forced: bool = world != null and world.gates[gate_i].forced
	var gx: float = -1.0 if gate_i == 0 else float(world.length) if world != null else 0.0
	var target := deg_to_rad(26.0) if forced else 0.0  # déverrouillée : se referme, mais reste entrouverte
	var near := false
	if world != null:
		for it in world.intruders:
			if it.state == "actif":
				var vp := _thief_visual(it)
				if absf(vp.x - gx) < 0.75 and absf(vp.y) < 0.5:
					near = true  # un voleur est à la porte : elle s'ouvre en grand devant lui
	var wobble := 0.0
	if near:
		target = deg_to_rad(88.0)
	elif state == "force":
		wobble = deg_to_rad(5.0) * sin(Time.get_ticks_msec() / 60.0) + deg_to_rad(5.0)  # elle résiste, secouée
	var speed := 0.35 if target > _gate_angle[gate_i] else 0.06  # ouverture vive, fermeture lente
	_gate_angle[gate_i] = move_toward(_gate_angle[gate_i], target, speed)
	var shown: float = _gate_angle[gate_i] + wobble
	var hinge_top := left_side
	var hinge := Vector2(cx, rc.position.y if hinge_top else rc.end.y)
	draw_set_transform(hinge, shown, Vector2.ONE)
	var slab := Rect2(-w / 2.0, 0.0 if hinge_top else -rc.size.y, w, rc.size.y)
	draw_rect(slab, C_DOOR)
	draw_rect(Rect2(slab.position, Vector2(slab.size.x * 0.4, slab.size.y)), C_DOOR.lightened(0.25))
	draw_rect(slab, C_DOOR.darkened(0.55), false, 2.0)
	var hy := (rc.size.y * 0.78 if hinge_top else -rc.size.y * 0.78) - 4.0
	draw_rect(Rect2(slab.position.x - 3.0, hy, 3.0, 8.0), Color(0.30, 0.22, 0.10))
	draw_rect(Rect2(slab.end.x, hy, 3.0, 8.0), Color(0.30, 0.22, 0.10))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _gate_angle[gate_i] != target or state == "force":
		queue_redraw()  # on continue d'animer jusqu'à la position voulue


func _draw_doorway(rc: Rect2) -> void:
	draw_rect(rc, C_FLOOR)
	draw_rect(rc, C_TILE, false, 1.0)
	draw_rect(Rect2(rc.position, Vector2(rc.size.x * 0.12, rc.size.y)), C_WALL.darkened(0.25))
	draw_rect(Rect2(rc.position + Vector2(rc.size.x * 0.88, 0), Vector2(rc.size.x * 0.12, rc.size.y)), C_WALL.darkened(0.25))


## Une étagère (une case) : montants, deux niveaux, caisses et tonneaux.
func _draw_shelf(rc: Rect2, c: int, r: int, stolen := false) -> void:
	draw_rect(rc.grow(-1.0), Color(0.20, 0.21, 0.24))
	var half := rc.size.y / 2.0
	for lvl in 2:
		var y0 := rc.position.y + lvl * half
		draw_rect(Rect2(rc.position.x + 2.0, y0 + half - 4.0, rc.size.x - 4.0, 3.0), Color(0.50, 0.38, 0.26))
		if stolen and lvl == 1:  # un objet a été volé : l'étage du bas est vide
			continue
		var h := _hash(c * 7 + lvl, r * 3)
		var col: Color = CRATES[h % CRATES.size()]
		if h % 5 == 0:  # tonneau
			draw_circle(Vector2(rc.get_center().x, y0 + half * 0.52), half * 0.36, Color(0.35, 0.45, 0.60))
			draw_arc(Vector2(rc.get_center().x, y0 + half * 0.52), half * 0.36, 0.0, TAU, 20, Color(0.20, 0.28, 0.40), 2.0)
		else:
			var bw := rc.size.x * (0.34 if h % 2 == 0 else 0.42)
			_rr(Rect2(rc.position.x + 4.0, y0 + 4.0, bw, half - 9.0), col, 2)
			_rr(Rect2(rc.position.x + 4.0, y0 + 4.0, bw, 3.0), col.lightened(0.25), 1)
			var col2: Color = CRATES[(h / 3) % CRATES.size()]
			_rr(Rect2(rc.position.x + 8.0 + bw, y0 + 7.0, rc.size.x - bw - 13.0, half - 12.0), col2, 2)


# ---------- personnages ----------

## Léger rebond quand l'élément est en train de glisser vers sa case.
func _bob(prev: int, pos: int, cell: float) -> float:
	if prev == pos:
		return 0.0
	var u := clampf(alpha / MOVE_FRACTION, 0.0, 1.0)
	if u >= 1.0:
		return 0.0
	return -absf(sin(u * PI * 2.0)) * cell * 0.04


## Le vigile : robot à casquette, visière lumineuse et lampe de poche tenue du côté où il regarde.
func _draw_robot(lay: Dictionary, rb: Dictionary, hovered: bool, slot := {"off": Vector2.ZERO, "sc": 1.0}) -> void:
	var u: float = lay.cell * 1.12 * slot.sc  # les personnages dépassent un peu de leur case
	var c: Vector2 = _robot_center(lay, rb) + slot.off * lay.cell
	var f: float = float(rb.facing)
	var broken: bool = rb.hs
	var b := _bob(rb.prev, rb.pos, u)
	var body_col := Color(0.38, 0.40, 0.44) if broken else C_ROBOT
	var head_col := Color(0.46, 0.48, 0.52) if broken else C_ROBOT.lightened(0.18)
	draw_set_transform(c + Vector2(0, u * 0.36), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, u * 0.30, Color(0, 0, 0, 0.35))
	draw_set_transform(c, 0.0, Vector2(f, 1.0))  # on dessine vers la droite ; f retourne le dessin
	# chenilles
	_rr(Rect2(-u * 0.27, u * 0.20 + b, u * 0.54, u * 0.16), Color(0.16, 0.17, 0.20), u * 0.07)
	for wx in [-0.18, 0.0, 0.18]:
		draw_circle(Vector2(u * wx, u * 0.28 + b), u * 0.04, Color(0.42, 0.44, 0.50))
	# bras du fond, corps, insigne
	_rr(Rect2(-u * 0.28, u * 0.01 + b, u * 0.07, u * 0.18), body_col.darkened(0.25), u * 0.03)
	_rr(Rect2(-u * 0.20, -u * 0.02 + b, u * 0.40, u * 0.26), body_col, u * 0.06)
	_rr(Rect2(-u * 0.18, -u * 0.015 + b, u * 0.36, u * 0.045), body_col.lightened(0.3), u * 0.02)
	draw_rect(Rect2(-u * 0.20, u * 0.17 + b, u * 0.40, u * 0.03), body_col.darkened(0.35))
	draw_circle(Vector2(0, u * 0.09 + b), u * 0.05, Color(0.95, 0.80, 0.25))
	# bras avant + lampe de poche
	_rr(Rect2(u * 0.19, u * 0.01 + b, u * 0.07, u * 0.15), body_col.darkened(0.12), u * 0.03)
	_rr(Rect2(u * 0.24, u * 0.04 + b, u * 0.17, u * 0.08), Color(0.18, 0.19, 0.22), u * 0.03)
	var lens := Color(0.30, 0.30, 0.30) if broken else Color(1.0, 0.95, 0.65)
	draw_rect(Rect2(u * 0.39, u * 0.035 + b, u * 0.03, u * 0.09), lens)
	# tête, visière et yeux
	_rr(Rect2(-u * 0.16, -u * 0.29 + b, u * 0.32, u * 0.26), head_col, u * 0.08)
	_rr(Rect2(-u * 0.10, -u * 0.25 + b, u * 0.25, u * 0.14), Color(0.07, 0.09, 0.15), u * 0.05)
	if broken:
		for ex in [0.0, 0.09]:
			var ec := Vector2(u * (ex + 0.02), -u * 0.18 + b)
			var d := u * 0.03
			draw_line(ec + Vector2(-d, -d), ec + Vector2(d, d), Color(0.95, 0.3, 0.3), 2.0)
			draw_line(ec + Vector2(-d, d), ec + Vector2(d, -d), Color(0.95, 0.3, 0.3), 2.0)
	else:
		draw_circle(Vector2(u * 0.02, -u * 0.18 + b), u * 0.03, Color(0.45, 0.92, 1.0))
		draw_circle(Vector2(u * 0.11, -u * 0.18 + b), u * 0.03, Color(0.45, 0.92, 1.0))
	# casquette de vigile
	_rr(Rect2(-u * 0.15, -u * 0.37 + b, u * 0.30, u * 0.10), Color(0.12, 0.16, 0.32), u * 0.04)
	_rr(Rect2(u * 0.05, -u * 0.30 + b, u * 0.19, u * 0.035), Color(0.09, 0.12, 0.25), u * 0.015)
	draw_circle(Vector2(0, -u * 0.33 + b), u * 0.025, Color(0.95, 0.80, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if broken:  # un peu de fumée
		for j in 3:
			draw_circle(c + Vector2(-u * 0.04 + j * u * 0.05, -u * 0.45 - j * u * 0.09), u * (0.04 + 0.01 * j), Color(0.7, 0.7, 0.7, 0.55 - 0.15 * j))
	_rr(Rect2(c - Vector2(u * 0.36, u * 0.44), Vector2(u * 0.72, u * 0.84)),
		Color(0, 0, 0, 0), u * 0.08, Color(0.95, 0.35, 0.35) if broken else Color(1, 1, 1, 0.85 if hovered else 0.0), 2 if (hovered or broken) else 0)


## L'intrus : voleur à pull rayé et masque ; assommé, il est allongé avec des étoiles.
func _draw_thief(lay: Dictionary, it: Dictionary, slot := {"off": Vector2.ZERO, "sc": 1.0}) -> void:
	var u: float = lay.cell * 1.12 * slot.sc
	var cell: float = lay.cell
	var vp := _thief_visual(it)
	var c: Vector2 = Vector2(lay.x0 + (lay.k + vp.x + 0.5) * cell, lay.y0 + (RAIL_ROW + vp.y + 0.5) * cell) + slot.off * cell
	var f: float = float(it.face)
	var moving: bool = it.state == "actif" and it.wt != Vector2i(it.x, it.ry) or (it.state == "actif" and it.pwt != it.pwf and _t_now() < float(it.ws))
	var b := -absf(sin(_t_now() * PI * 0.7)) * u * 0.04 if moving else 0.0
	var down: bool = it.state == "arrete"
	draw_set_transform(c + Vector2(0, u * 0.34), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, u * 0.26, Color(0, 0, 0, 0.35))
	if down:
		draw_set_transform(c + Vector2(0, u * 0.12), PI / 2.0 * f, Vector2.ONE)
	else:
		draw_set_transform(c, 0.0, Vector2(f, 1.0))
	# jambes, pull rayé, sac, tête, masque, bonnet
	_rr(Rect2(-u * 0.12, u * 0.18 + b, u * 0.09, u * 0.16), Color(0.15, 0.15, 0.2), u * 0.03)
	_rr(Rect2(u * 0.03, u * 0.18 + b, u * 0.09, u * 0.16), Color(0.15, 0.15, 0.2), u * 0.03)
	_rr(Rect2(-u * 0.20, -u * 0.04 + b, u * 0.14, u * 0.2), Color(0.55, 0.42, 0.25), u * 0.05)
	_rr(Rect2(-u * 0.15, -u * 0.04 + b, u * 0.30, u * 0.24), Color(0.93, 0.93, 0.95), u * 0.05)
	for sy in [0.0, 0.08, 0.16]:
		draw_rect(Rect2(-u * 0.15, u * (0.01 + sy) + b, u * 0.30, u * 0.035), Color(0.12, 0.12, 0.16))
	draw_circle(Vector2(0, -u * 0.14 + b), u * 0.13, Color(0.93, 0.78, 0.62))
	draw_rect(Rect2(-u * 0.13, -u * 0.17 + b, u * 0.26, u * 0.07), Color(0.08, 0.08, 0.1))
	draw_circle(Vector2(u * 0.04, -u * 0.135 + b), u * 0.015, Color.WHITE)
	draw_circle(Vector2(u * 0.09, -u * 0.135 + b), u * 0.015, Color.WHITE)
	draw_arc(Vector2(0, -u * 0.17 + b), u * 0.13, PI, TAU, 12, Color(0.25, 0.25, 0.30), u * 0.06)
	if it.loot:  # le butin : une caisse tenue devant lui
		_rr(Rect2(u * 0.10, u * 0.02 + b, u * 0.20, u * 0.17), Color(0.80, 0.60, 0.25), u * 0.02)
		draw_rect(Rect2(u * 0.10, u * 0.08 + b, u * 0.20, u * 0.025), Color(0.55, 0.38, 0.15))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if down:
		var t := Time.get_ticks_msec() / 400.0
		for j in 3:
			var a := t + j * TAU / 3.0
			draw_circle(c + Vector2(cos(a) * u * 0.22, -u * 0.12 + sin(a) * u * 0.06), u * 0.035, Color(1.0, 0.90, 0.30))


## La nuit : le calque d'obscurité (shader) reçoit la zone de l'entrepôt, les lampes de poche
## des vigiles (un faisceau sur la case devant eux) et les lampadaires.
func _update_night(lay: Dictionary, lamps: Array, slots: Dictionary) -> void:
	var cell: float = lay.cell
	var mat: ShaderMaterial = _night.material
	var box := Rect2(_cell_rect(lay, 2, 1).position, Vector2(cell * (lay.l + 2), cell * (ROWS - 2)))
	mat.set_shader_parameter("box", Vector4(box.position.x, box.position.y, box.size.x, box.size.y))
	mat.set_shader_parameter("cell", cell)
	var ga := _cell_rect(lay, lay.k - 1, RAIL_ROW)
	var gb := _cell_rect(lay, lay.k + lay.l, RAIL_ROW)
	mat.set_shader_parameter("skip_a", Vector4(ga.position.x, ga.position.y, ga.size.x / 2.0, ga.size.y))
	mat.set_shader_parameter("skip_b", Vector4(gb.get_center().x, gb.position.y, gb.size.x / 2.0, gb.size.y))
	var pos := PackedVector2Array()
	var dirs := PackedVector2Array()
	var bodies := PackedVector2Array()
	if world != null:
		for rb in world.robots:
			if rb.hs or pos.size() >= 8:
				continue
			var c: Vector2 = _robot_pos(lay, rb, slots)
			var f := float(rb.facing)
			pos.append(c + Vector2(f * cell * 0.42 * _slot(slots, "r" + str(rb.id)).sc, cell * 0.08))
			dirs.append(Vector2(f, 0.0))
			bodies.append(c)
	var n := pos.size()
	while pos.size() < 8:
		pos.append(Vector2.ZERO)
		dirs.append(Vector2.RIGHT)
		bodies.append(Vector2.ZERO)
	mat.set_shader_parameter("count", n)
	mat.set_shader_parameter("pos", pos)
	mat.set_shader_parameter("dir", dirs)
	mat.set_shader_parameter("body", bodies)
	var lp := PackedVector2Array()
	for l in lamps:
		if lp.size() < 32:
			lp.append(l)
	var ln := lp.size()
	while lp.size() < 32:
		lp.append(Vector2.ZERO)
	mat.set_shader_parameter("lamp_count", ln)
	mat.set_shader_parameter("lamp", lp)


## Petit cerveau (dessiné en SVG) : affiché quand la réflexion prend le pas sur une action.
func _brain() -> Texture2D:
	if _brain_tex == null:
		var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 24 24">
<g fill="#f4a6c0" stroke="#7a2f4f" stroke-width="1.3">
<circle cx="8" cy="9" r="5"/><circle cx="16" cy="9" r="5"/><circle cx="7.5" cy="15" r="4.6"/><circle cx="16.5" cy="15" r="4.6"/><circle cx="12" cy="13" r="5"/></g>
<g fill="none" stroke="#7a2f4f" stroke-width="1.3" stroke-linecap="round">
<path d="M12 5 V19"/><path d="M6 8 Q8 10 6 12"/><path d="M18 8 Q16 10 18 12"/><path d="M8.5 15 Q10 14 9.5 17"/><path d="M15.5 15 Q14 14 14.5 17"/></g></svg>"""
		var img := Image.new()
		img.load_svg_from_string(svg)
		_brain_tex = ImageTexture.create_from_image(img)
	return _brain_tex
