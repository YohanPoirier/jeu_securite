extends Control
## L'entrepôt, en plein écran : sol, étagères, rail, portes, robots et intrus.
## Les positions sont interpolées entre deux ticks (alpha de 0 à 1).
## Un clic sur un robot émet robot_clicked(id) : l'interface ouvre alors son éditeur.

signal robot_clicked(id: String)

var world = null
var alpha := 1.0
var hover := -1  # indice du robot survolé

const C_FLOOR := Color(0.15, 0.16, 0.18)
const C_TILE := Color(0.19, 0.20, 0.23)
const C_RAIL := Color(0.10, 0.11, 0.13)
const C_CELL := Color(0.23, 0.25, 0.30)
const C_DOOR := Color(0.85, 0.65, 0.20)
const C_ROBOT := Color(0.25, 0.60, 0.95)
const C_INTRUDER := Color(0.92, 0.25, 0.25)
const C_CAUGHT := Color(0.35, 0.80, 0.45)
const CRATES := [Color(0.55, 0.40, 0.25), Color(0.45, 0.50, 0.55), Color(0.60, 0.50, 0.30), Color(0.35, 0.45, 0.40)]


## Géométrie commune au dessin et aux clics : {cell, x0, y}
func _layout() -> Dictionary:
	var l: int = world.length if world != null else 6
	var gate := 46.0
	var cell: float = minf((size.x - 2.0 * (gate + 30.0)) / float(l), 110.0)
	return {"l": l, "cell": cell, "x0": (size.x - cell * l) / 2.0, "y": size.y * 0.5, "gate": gate}


func _robot_center(lay: Dictionary, rb: Dictionary) -> Vector2:
	var rp: float = lerpf(float(rb.prev), float(rb.pos), alpha)
	return Vector2(lay.x0 + (rp + 0.5) * lay.cell, lay.y)


func _robot_rect(lay: Dictionary, rb: Dictionary) -> Rect2:
	var s: float = lay.cell * 0.6
	var c := _robot_center(lay, rb)
	return Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s))


func _gui_input(event: InputEvent) -> void:
	if world == null:
		return
	var lay := _layout()
	if event is InputEventMouseMotion:
		var h := -1
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i]).grow(8.0).has_point(event.position):
				h = i
		if h != hover:
			hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in world.robots.size():
			if _robot_rect(lay, world.robots[i]).grow(8.0).has_point(event.position):
				robot_clicked.emit(world.robots[i].id)
				return


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var lay := _layout()
	var l: int = lay.l
	var cell: float = lay.cell
	var x0: float = lay.x0
	var y: float = lay.y
	# sol carrelé
	draw_rect(Rect2(Vector2.ZERO, size), C_FLOOR)
	var t := 64.0
	var gx := 0.0
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), C_TILE, 1.0)
		gx += t
	var gy := 0.0
	while gy < size.y:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), C_TILE, 1.0)
		gy += t
	_draw_shelves(y - cell * 0.9, -1)
	_draw_shelves(y + cell * 0.9, 1)
	# rail
	draw_rect(Rect2(x0 - 8.0, y - cell / 2.0 - 8.0, cell * l + 16.0, cell + 16.0), C_RAIL)
	for i in l:
		var r := Rect2(x0 + i * cell + 2.0, y - cell / 2.0 + 2.0, cell - 4.0, cell - 4.0)
		draw_rect(r, C_CELL)
		draw_string(font, Vector2(r.position.x + 5.0, r.position.y + r.size.y - 5.0), str(i),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.35))
	# portes (dans le mur, aux deux extrémités)
	for side in [0, 1]:
		var gxr: float = x0 - lay.gate - 8.0 if side == 0 else x0 + cell * l + 8.0
		var gr := Rect2(gxr, y - cell / 2.0, lay.gate, cell)
		draw_rect(gr, C_DOOR.darkened(0.45))
		var k := 0.0
		while k < cell:
			draw_rect(Rect2(gr.position.x, gr.position.y + k, lay.gate, 10.0), C_DOOR.darkened(0.15) if int(k / 10.0) % 2 == 0 else C_DOOR.darkened(0.6))
			k += 10.0
		draw_string(font, Vector2(gr.position.x, gr.position.y - 8.0), "porte", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DOOR)
	if world == null:
		return
	# intrus
	for it in world.intruders:
		if it.state == "attente":
			continue
		var p: float = float(it.pos)
		if it.state == "actif":
			p = lerpf(float(it.prev), float(it.pos), alpha)
		var c := Vector2(x0 + (p + 0.5) * cell, y)
		if it.state == "arrete":
			draw_circle(c, cell * 0.22, C_CAUGHT)
			draw_string(font, c + Vector2(-5, 6), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
		else:
			draw_circle(c, cell * 0.22, C_INTRUDER)
			draw_string(font, c + Vector2(-4, 6), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	# robots
	for i in world.robots.size():
		var rb: Dictionary = world.robots[i]
		var rr := _robot_rect(lay, rb)
		draw_rect(rr, C_ROBOT)
		draw_rect(rr, Color.WHITE if i == hover else Color(1, 1, 1, 0.6), false, 3.0 if i == hover else 2.0)
		var c2 := rr.get_center()
		draw_circle(c2 + Vector2(-rr.size.x * 0.18, -rr.size.y * 0.1), rr.size.x * 0.09, Color.WHITE)
		draw_circle(c2 + Vector2(rr.size.x * 0.18, -rr.size.y * 0.1), rr.size.x * 0.09, Color.WHITE)
		draw_line(c2 + Vector2(0, -rr.size.y * 0.5), c2 + Vector2(0, -rr.size.y * 0.8), Color.WHITE, 2.0)
		draw_string(font, Vector2(rr.position.x - 10.0, rr.end.y + 18.0), String(rb.nom),
			HORIZONTAL_ALIGNMENT_CENTER, rr.size.x + 20.0, 14, Color(1, 1, 1, 0.9))
		if i == hover:
			draw_string(font, Vector2(rr.position.x - 40.0, rr.position.y - 22.0), "clic : programmer",
				HORIZONTAL_ALIGNMENT_CENTER, rr.size.x + 80.0, 13, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(14, size.y - 200), "tick %d" % world.tick_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))


## Rangées d'étagères avec des caisses, au-dessus (dir = -1) ou au-dessous (dir = 1) du rail.
func _draw_shelves(edge_y: float, dir: int) -> void:
	var sh := 46.0
	var row := 0
	var yy := edge_y
	while row < 3:
		var top: float = yy - sh if dir < 0 else yy
		if top < -sh or top > size.y:
			break
		var xx := 30.0
		var i := 0
		while xx < size.x - 70.0:
			var w := 110.0
			draw_rect(Rect2(xx, top, w, sh), Color(0.12, 0.13, 0.15))
			for j in 3:
				var col: Color = CRATES[(i * 7 + j * 3 + row * 5) % CRATES.size()]
				draw_rect(Rect2(xx + 6.0 + j * 34.0, top + 6.0, 30.0, sh - 12.0), col)
			xx += w + 40.0
			i += 1
		yy += dir * (sh + 26.0)
		row += 1
