extends Control
## L'entrepôt, en plein écran, entièrement dessiné sur une grille de cases :
## sol, étagères (3 cases chacune), rail, portes, robots et intrus.
## Pour l'instant c'est purement graphique : la logique du jeu reste celle du rail (world.gd).
##
## Déplacement « au tour par tour » : pendant un tick, l'élément glisse vers sa nouvelle case
## sur la première partie du tick (MOVE_FRACTION), puis marque une pause jusqu'au tick suivant.
## Un clic sur un robot émet robot_clicked(id) : l'interface ouvre alors son éditeur.

signal robot_clicked(id: String)

var world = null
var alpha := 1.0  # avancement dans le tick courant, de 0 à 1
var hover := -1  # indice du robot survolé

const ROWS := 9
const RAIL_ROW := 4
const MOVE_FRACTION := 0.55  # part du tick consacrée au glissement ; le reste est la pause
const SHELF_ROWS := [1, 2, 6, 7]  # rangées de cases occupées par des étagères
const SHELF_LEN := 3  # une étagère occupe 3 cases

const C_FLOOR := Color(0.15, 0.16, 0.18)
const C_TILE := Color(0.19, 0.20, 0.23)
const C_RAIL := Color(0.10, 0.11, 0.13)
const C_CELL := Color(0.23, 0.25, 0.30)
const C_DOOR := Color(0.85, 0.65, 0.20)
const C_ROBOT := Color(0.25, 0.60, 0.95)
const C_INTRUDER := Color(0.92, 0.25, 0.25)
const C_CAUGHT := Color(0.35, 0.80, 0.45)
const CRATES := [Color(0.55, 0.40, 0.25), Color(0.45, 0.50, 0.55), Color(0.60, 0.50, 0.30), Color(0.35, 0.45, 0.40)]


## Géométrie de la grille, commune au dessin et aux clics.
## cols : 16 si le rail a un nombre pair de cases, 17 sinon (rail centré).
## k : colonne de la première case du rail.
func _layout() -> Dictionary:
	var l: int = world.length if world != null else 6
	var cols := 16 if l % 2 == 0 else 17
	var cell: float = minf(size.x / float(cols), size.y / float(ROWS))
	return {
		"l": l, "cols": cols, "cell": cell,
		"x0": (size.x - cell * cols) / 2.0, "y0": (size.y - cell * ROWS) / 2.0,
		"k": (cols - l) / 2,
	}


func _cell_rect(lay: Dictionary, col: int, row: int) -> Rect2:
	return Rect2(lay.x0 + col * lay.cell, lay.y0 + row * lay.cell, lay.cell, lay.cell)


## Position fluide (en cases) entre l'ancienne et la nouvelle case : glisse puis pause.
func _smooth(prev: int, pos: int) -> float:
	var u := clampf(alpha / MOVE_FRACTION, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)  # départ et arrivée en douceur
	return lerpf(float(prev), float(pos), u)


func _robot_center(lay: Dictionary, rb: Dictionary) -> Vector2:
	var col: float = lay.k + _smooth(rb.prev, rb.pos)
	return Vector2(lay.x0 + (col + 0.5) * lay.cell, lay.y0 + (RAIL_ROW + 0.5) * lay.cell)


func _robot_rect(lay: Dictionary, rb: Dictionary) -> Rect2:
	var s: float = lay.cell * 0.7
	return Rect2(_robot_center(lay, rb) - Vector2(s, s) / 2.0, Vector2(s, s))


func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	var lay := _layout()
	if event is InputEventMouseMotion:
		var h := -1
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i]).grow(6.0).has_point(event.position):
				h = i
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i]).grow(6.0).has_point(event.position):
				robot_clicked.emit(world.robots[i].id)
				return


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var lay := _layout()
	var l: int = lay.l
	var cols: int = lay.cols
	var cell: float = lay.cell
	var k: int = lay.k
	# sol carrelé : une dalle par case de la grille (le sol déborde de la grille jusqu'aux bords)
	draw_rect(Rect2(Vector2.ZERO, size), C_FLOOR)
	var gx: float = fmod(lay.x0, cell) - cell
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), C_TILE, 1.0)
		gx += cell
	var gy: float = fmod(lay.y0, cell) - cell
	while gy < size.y:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), C_TILE, 1.0)
		gy += cell
	_draw_shelves(lay)
	# rail : une case par case de la grille
	var rail_bg: Rect2 = _cell_rect(lay, k, RAIL_ROW)
	draw_rect(Rect2(rail_bg.position - Vector2(4, 4), Vector2(cell * l + 8.0, cell + 8.0)), C_RAIL)
	for i in l:
		var r := _cell_rect(lay, k + i, RAIL_ROW).grow(-2.0)
		draw_rect(r, C_CELL)
		draw_string(font, Vector2(r.position.x + 4.0, r.end.y - 4.0), str(i),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.35))
	# portes : une case à chaque extrémité du rail
	for gc in [k - 1, k + l]:
		var gr := _cell_rect(lay, gc, RAIL_ROW).grow(-2.0)
		draw_rect(gr, C_DOOR.darkened(0.5))
		var s := 0.0
		while s < gr.size.y:
			if int(s / 9.0) % 2 == 0:
				draw_rect(Rect2(gr.position.x, gr.position.y + s, gr.size.x, minf(9.0, gr.size.y - s)), C_DOOR.darkened(0.1))
			s += 9.0
		draw_string(font, Vector2(gr.position.x - 4.0, gr.position.y - 6.0), "porte",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DOOR)
	if world == null:
		return
	# intrus
	for it in world.intruders:
		if it.state == "attente":
			continue
		var p: float = float(it.pos)
		if it.state == "actif":
			p = _smooth(it.prev, it.pos)
		var c := Vector2(lay.x0 + (k + p + 0.5) * cell, lay.y0 + (RAIL_ROW + 0.5) * cell)
		if it.state == "arrete":
			draw_circle(c, cell * 0.26, C_CAUGHT)
			draw_string(font, c + Vector2(-5, 6), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
		else:
			draw_circle(c, cell * 0.26, C_INTRUDER)
			draw_string(font, c + Vector2(-4, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# robots
	for i in world.robots.size():
		var rb: Dictionary = world.robots[i]
		var rr := _robot_rect(lay, rb)
		var broken: bool = rb.hs
		draw_rect(rr, Color(0.28, 0.30, 0.34) if broken else C_ROBOT)
		var edge := Color(0.9, 0.3, 0.3) if broken else (Color.WHITE if i == hover else Color(1, 1, 1, 0.6))
		draw_rect(rr, edge, false, 3.0 if i == hover else 2.0)
		var c2 := rr.get_center()
		var ex := rr.size.x * 0.18
		var ey := -rr.size.y * 0.1
		var er := rr.size.x * 0.09
		if broken:
			for sx in [-1.0, 1.0]:
				var ec: Vector2 = c2 + Vector2(sx * ex, ey)
				draw_line(ec + Vector2(-er, -er), ec + Vector2(er, er), Color(0.9, 0.3, 0.3), 2.5)
				draw_line(ec + Vector2(-er, er), ec + Vector2(er, -er), Color(0.9, 0.3, 0.3), 2.5)
			draw_line(c2 + Vector2(0, -rr.size.y * 0.5), c2 + Vector2(rr.size.x * 0.12, -rr.size.y * 0.68), Color(0.7, 0.7, 0.7), 2.0)
		else:
			draw_circle(c2 + Vector2(-ex, ey), er, Color.WHITE)
			draw_circle(c2 + Vector2(ex, ey), er, Color.WHITE)
			draw_line(c2 + Vector2(0, -rr.size.y * 0.5), c2 + Vector2(0, -rr.size.y * 0.8), Color.WHITE, 2.0)
		if rb.vm.thinking and not broken:
			draw_texture_rect(_brain(), Rect2(rr.end.x - 14.0, rr.position.y - 36.0, 40, 40), false)
		draw_string(font, Vector2(rr.position.x - 10.0, rr.end.y + 16.0), String(rb.nom) + (" (HS)" if broken else ""),
			HORIZONTAL_ALIGNMENT_CENTER, rr.size.x + 20.0, 13, Color(1.0, 0.55, 0.55) if broken else Color(1, 1, 1, 0.9))
		if i == hover:
			draw_string(font, Vector2(rr.position.x - 40.0, rr.position.y - 20.0), "clic : programmer",
				HORIZONTAL_ALIGNMENT_CENTER, rr.size.x + 80.0, 13, Color(1, 1, 1, 0.9))


var _brain_tex: Texture2D = null


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


## Étagères : unités de 3 cases de long, 1 case de large, alignées sur la grille.
func _draw_shelves(lay: Dictionary) -> void:
	var cols: int = lay.cols
	var usable := cols - 2
	var n := (usable + 1) / (SHELF_LEN + 1)
	var used := n * (SHELF_LEN + 1) - 1
	var start := 1 + (usable - used) / 2
	for row in SHELF_ROWS:
		for u in n:
			var c0: int = start + u * (SHELF_LEN + 1)
			for j in SHELF_LEN:
				var r := _cell_rect(lay, c0 + j, row)
				draw_rect(r.grow(-1.0), Color(0.12, 0.13, 0.15))
				var col: Color = CRATES[(u * 7 + j * 3 + row * 5) % CRATES.size()]
				draw_rect(r.grow(-6.0), col)
				draw_rect(Rect2(r.position.x + 6.0, r.position.y + 6.0, r.size.x - 12.0, 4.0), col.lightened(0.2))
