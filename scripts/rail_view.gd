extends Control
## Dessin du rail, du robot et des intrus. Les positions sont interpolées entre deux ticks
## (alpha va de 0 à 1) pour un mouvement fluide.

var world = null
var level_len := 6
var alpha := 1.0

const C_BG := Color(0.09, 0.10, 0.13)
const C_CELL := Color(0.20, 0.23, 0.29)
const C_DOOR := Color(0.85, 0.65, 0.20)
const C_ROBOT := Color(0.25, 0.60, 0.95)
const C_INTRUDER := Color(0.92, 0.25, 0.25)
const C_CAUGHT := Color(0.35, 0.80, 0.45)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var l: int = world.length if world != null else level_len
	var margin := 24.0
	var cell: float = minf((size.x - 2.0 * margin) / float(l), 90.0)
	var x0: float = (size.x - cell * l) / 2.0
	var y: float = size.y / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for i in l:
		var r := Rect2(x0 + i * cell + 2.0, y - cell / 2.0 + 2.0, cell - 4.0, cell - 4.0)
		var col := C_DOOR if (i == 0 or i == l - 1) else C_CELL
		draw_rect(r, col.darkened(0.35) if col == C_DOOR else col)
		draw_string(font, Vector2(r.position.x + 4.0, r.position.y + r.size.y - 4.0), str(i),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))
	draw_string(font, Vector2(x0, y - cell / 2.0 - 8.0), "porte", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DOOR)
	draw_string(font, Vector2(x0 + cell * (l - 1), y - cell / 2.0 - 8.0), "porte", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DOOR)
	if world == null:
		return
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
	var rp: float = lerpf(float(world.robot.prev), float(world.robot.pos), alpha)
	var rc := Vector2(x0 + (rp + 0.5) * cell, y)
	var s: float = cell * 0.6
	draw_rect(Rect2(rc - Vector2(s, s) / 2.0, Vector2(s, s)), C_ROBOT)
	draw_rect(Rect2(rc - Vector2(s, s) / 2.0, Vector2(s, s)), Color.WHITE, false, 2.0)
	draw_string(font, Vector2(10, size.y - 10), "tick %d" % world.tick_n, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
