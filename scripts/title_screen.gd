extends Control
## Écran d'accueil : un entrepôt vu de dessus dont les caisses écrivent le nom du jeu,
## des voleurs qui rôdent autour, et les boutons Nouvelle partie / Charger / Choisir un niveau / Quitter.

signal new_game
signal load_game
signal choose_level
signal quit_game

const TITLE := "SÉCURITÉ"
const N_THIEVES := 14

const C_GRASS := Color(0.16, 0.31, 0.19)
const C_FLOOR := Color(0.27, 0.28, 0.32)
const C_TILE := Color(0.23, 0.24, 0.28)
const C_WALL := Color(0.50, 0.38, 0.33)
const C_MORTAR := Color(0.34, 0.25, 0.22)
const LETTER := Color(0.90, 0.62, 0.24)  # caisses qui forment le nom : une seule teinte, bien lisible
const CRATES := [Color(0.72, 0.52, 0.30), Color(0.52, 0.62, 0.70), Color(0.80, 0.66, 0.36), Color(0.44, 0.60, 0.50)]

## Police 5×7 (les É ont leur accent sur deux rangées au-dessus).
const GLYPHS := {
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
}

var buttons: VBoxContainer
var load_btn: Button
var _thieves: Array = []
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in N_THIEVES:
		_thieves.append({
			"s": rng.randf(),  # position sur le tour (0..1)
			"lane": rng.randf_range(0.7, 2.2),  # distance au mur, en cases
			"v": rng.randf_range(0.03, 0.06) * (1 if rng.randf() < 0.6 else -1),  # tours par seconde de marche
			"ph": rng.randf() * TAU,  # rythme des arrêts (ils rôdent, s'arrêtent, repartent)
			"f": rng.randf_range(0.25, 0.55),
		})
	# boutons, au centre en bas
	var holder := CenterContainer.new()
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.56
	holder.anchor_bottom = 1.0
	holder.offset_left = 0
	holder.offset_right = 0
	holder.offset_top = 0
	holder.offset_bottom = 0
	add_child(holder)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.13, 0.86)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	buttons = VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	panel.add_child(buttons)
	_button("Nouvelle partie", func(): new_game.emit())
	load_btn = _button("Charger la partie", func(): load_game.emit())
	_button("Choisir un niveau", func(): choose_level.emit())
	if not OS.has_feature("web"):  # dans un navigateur, on ne quitte pas : on ferme l'onglet
		_button("Quitter", func(): quit_game.emit())


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(260, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	buttons.add_child(b)
	return b


## Bouton « Charger » grisé s'il n'y a pas de partie enregistrée.
func refresh(has_save: bool) -> void:
	load_btn.disabled = not has_save


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


# ---------- géométrie ----------

func _glyph(ch: String) -> Array:
	return GLYPHS["E" if ch == "É" else ch]


## Taille du texte en cases (largeur, hauteur avec l'accent).
func _text_cols() -> int:
	var w := 0
	for ch in TITLE:
		w += _glyph(ch)[0].length() + 1
	return w - 1


## Case et rectangle intérieur de l'entrepôt : il occupe le haut de l'écran, au-dessus des boutons.
func _layout() -> Dictionary:
	var cols := _text_cols() + 4  # deux cases de marge de chaque côté du texte
	var rows := 13  # étagère, allée, accent (2), lettres (7), allée, étagère
	var avail := Vector2(size.x * 0.90, size.y * 0.44)
	var c := floorf(minf(avail.x / float(cols + 2), avail.y / float(rows + 2)))
	var inner := Vector2(cols, rows) * c
	var pos := Vector2((size.x - inner.x) / 2.0, size.y * 0.09 + c)
	return {"c": c, "inner": Rect2(pos, inner), "cols": cols, "rows": rows}


# ---------- dessin ----------

func _draw() -> void:
	var lay := _layout()
	var c: float = lay.c
	var inner: Rect2 = lay.inner
	draw_rect(Rect2(Vector2.ZERO, size), C_GRASS)
	_draw_grass(c)
	# voleurs derrière l'entrepôt (au-dessus de lui à l'écran), puis l'entrepôt, puis ceux devant
	var pos: Array = []
	for th in _thieves:
		pos.append(_thief_pos(th, inner, c))
	for i in _thieves.size():
		if pos[i].p.y < inner.get_center().y:
			_draw_thief(pos[i].p, c * 2.4, pos[i].face, pos[i].moving)
	_draw_warehouse(inner, c, lay)
	for i in _thieves.size():
		if pos[i].p.y >= inner.get_center().y:
			_draw_thief(pos[i].p, c * 2.4, pos[i].face, pos[i].moving)


func _hash(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663)) % 1000003


func _draw_grass(c: float) -> void:
	var step := c * 2.0
	var nx := ceili(size.x / step)
	var ny := ceili(size.y / step)
	for j in ny:
		for i in nx:
			var h := _hash(i, j)
			if h % 7 == 0:
				var p := Vector2(i * step + (h % 11) * step / 11.0, j * step + (h % 13) * step / 13.0)
				draw_line(p, p + Vector2(-2, -5), C_GRASS.lightened(0.15), 1.5)
				draw_line(p + Vector2(3, 0), p + Vector2(4, -6), C_GRASS.lightened(0.10), 1.5)
			elif h % 23 == 1:
				var q := Vector2(i * step + step / 2.0, j * step + step / 2.0)
				draw_circle(q, step * 0.30, Color(0.10, 0.24, 0.13))
				draw_circle(q + Vector2(-step * 0.08, -step * 0.08), step * 0.14, Color(0.15, 0.32, 0.18))


func _draw_warehouse(inner: Rect2, c: float, lay: Dictionary) -> void:
	var wall := c * 1.0
	var outer := inner.grow(wall)
	# ombre portée
	draw_rect(Rect2(outer.position + Vector2(c * 0.4, c * 0.5), outer.size), Color(0, 0, 0, 0.30))
	# murs de briques
	draw_rect(outer, C_WALL)
	var rows := int(outer.size.y / (c * 0.5))
	for r in rows:
		var y := outer.position.y + r * c * 0.5
		draw_line(Vector2(outer.position.x, y), Vector2(outer.end.x, y), C_MORTAR, 1.0)
		var off := c * (0.5 if r % 2 == 0 else 0.0)
		var x := outer.position.x + off
		while x < outer.end.x:
			draw_line(Vector2(x, y), Vector2(x, y + c * 0.5), C_MORTAR, 1.0)
			x += c
	draw_rect(outer, C_MORTAR.darkened(0.3), false, 2.0)
	# sol carrelé
	draw_rect(inner, C_FLOOR)
	var cols: int = lay.cols
	var nrows: int = lay.rows
	for i in cols + 1:
		draw_line(inner.position + Vector2(i * c, 0), inner.position + Vector2(i * c, inner.size.y), C_TILE, 1.0)
	for j in nrows + 1:
		draw_line(inner.position + Vector2(0, j * c), inner.position + Vector2(inner.size.x, j * c), C_TILE, 1.0)
	# étagères le long des murs du haut et du bas
	for i in range(1, cols - 1):
		for yy in [inner.position.y, inner.end.y - c]:
			var rc := Rect2(inner.position.x + i * c, yy, c, c)
			draw_rect(rc.grow(-1.0), Color(0.18, 0.19, 0.22))
			var h := _hash(i, int(yy))
			_crate(Rect2(rc.position + Vector2(c * 0.12, c * 0.18), Vector2(c * 0.76, c * 0.64)), CRATES[h % CRATES.size()])
	# portes dorées à gauche et à droite
	for x in [outer.position.x, inner.end.x]:
		draw_rect(Rect2(x + wall * 0.35, inner.get_center().y - c, wall * 0.3, c * 2.0), Color(0.80, 0.62, 0.22))
	# le nom du jeu en caisses
	var tx := inner.position.x + 2.0 * c
	var ty := inner.position.y + 2.0 * c  # rangée 0 de l'accent ; les lettres commencent 2 rangées plus bas
	var col_i := 0
	for ch in TITLE:
		var g: Array = _glyph(ch)
		var w: int = g[0].length()
		if ch == "É":
			_crate(Rect2(tx + (col_i + 3) * c, ty, c, c).grow(-1.0), LETTER)
			_crate(Rect2(tx + (col_i + 2) * c, ty + c, c, c).grow(-1.0), LETTER)
		for r in g.size():
			for k in w:
				if g[r][k] == "#":
					var h := _hash(col_i + k, r)
					_crate(Rect2(tx + (col_i + k) * c, ty + (r + 2) * c, c, c).grow(-1.0), LETTER.lightened(0.06 * float(h % 3)))
		col_i += w + 1


func _crate(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(maxi(1, int(r.size.x * 0.12)))
	sb.border_color = col.darkened(0.35)
	sb.set_border_width_all(1)
	draw_style_box(sb, r)
	draw_rect(Rect2(r.position.x + 2.0, r.position.y + 2.0, r.size.x - 4.0, maxf(1.5, r.size.y * 0.14)), col.lightened(0.22))
	draw_line(Vector2(r.get_center().x, r.position.y + 2.0), Vector2(r.get_center().x, r.end.y - 2.0), col.darkened(0.25), 1.0)


## Position d'un voleur : il fait le tour de l'entrepôt sur sa propre allée, en s'arrêtant de temps en temps.
func _thief_pos(th: Dictionary, inner: Rect2, c: float) -> Dictionary:
	# avancement : vitesse modulée (arrêts quand le sinus est négatif)
	var go := maxf(0.0, sin(_t * th.f + th.ph))
	var s: float = fposmod(th.s + th.v * _integral(th), 1.0)
	var ring := inner.grow(c * (1.0 + th.lane))
	var per := 2.0 * (ring.size.x + ring.size.y)
	var d := s * per
	var p: Vector2
	var dir: Vector2
	if d < ring.size.x:
		p = ring.position + Vector2(d, 0); dir = Vector2.RIGHT
	elif d < ring.size.x + ring.size.y:
		p = Vector2(ring.end.x, ring.position.y + d - ring.size.x); dir = Vector2.DOWN
	elif d < 2.0 * ring.size.x + ring.size.y:
		p = Vector2(ring.end.x - (d - ring.size.x - ring.size.y), ring.end.y); dir = Vector2.LEFT
	else:
		p = Vector2(ring.position.x, ring.end.y - (d - 2.0 * ring.size.x - ring.size.y)); dir = Vector2.UP
	if th.v < 0:
		dir = -dir
	var face := 1 if dir.x > 0 else (-1 if dir.x < 0 else (1 if int(th.ph * 10) % 2 == 0 else -1))
	return {"p": p, "face": face, "moving": go > 0.05}


## Distance parcourue (en temps « actif ») : intégrale de max(0, sin(f t + φ)), calculée en forme close.
func _integral(th: Dictionary) -> float:
	var f: float = th.f
	var ph: float = th.ph
	# primitive de max(0, sin) sur une période 2π : 2 par période, plus la partie de la période en cours
	var a := _t * f + ph
	var full := floorf(a / TAU)
	var rem := a - full * TAU
	var part := (1.0 - cos(minf(rem, PI)))
	var a0 := ph
	var full0 := floorf(a0 / TAU)
	var rem0 := a0 - full0 * TAU
	var part0 := (1.0 - cos(minf(rem0, PI)))
	return ((full * 2.0 + part) - (full0 * 2.0 + part0)) / f


func _rr(r: Rect2, color: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(maxi(1, int(radius)))
	draw_style_box(sb, r)


## Le voleur du jeu (pull rayé, masque, bonnet, sac), dessiné à la position donnée.
func _draw_thief(c: Vector2, u: float, face: int, moving: bool) -> void:
	var f := float(face)
	var b := -absf(sin(_t * PI * 2.2)) * u * 0.05 if moving else 0.0
	draw_set_transform(c + Vector2(0, u * 0.34), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, u * 0.26, Color(0, 0, 0, 0.35))
	draw_set_transform(c, 0.0, Vector2(f, 1.0))
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
