extends Control
## Interface épurée : l'entrepôt en plein écran et trois zones opaques par-dessus.
##   - en haut : une barre fine (nom du niveau) et un menu déroulant (niveau, scénario, graine) ;
##     il se déroule tout seul au début d'un niveau pour montrer le scénario ;
##   - en bas : lancement du code (Lancer, Arrêter, vitesse) et résultat ;
##   - à droite, collé au bord : l'éditeur du robot sur lequel on a cliqué (un éditeur par robot),
##     avec la console en dessous.

const Interp = preload("res://scripts/interpreter.gd")
const World = preload("res://scripts/world.gd")
const RailView = preload("res://scripts/rail_view.gd")

const SAVE_PATH := "user://progression.cfg"
const TOP_H := 40
const BOTTOM_H := 102
const SPEEDS := [["Lent  (×½)", 3], ["Normal  (×1)", 6], ["Rapide  (×2)", 12], ["Très rapide  (×4)", 24]]
const EDITOR_W := 520
const MENU_W := 640
const PANEL_BG := Color(0.09, 0.10, 0.13)
const BORDER := Color(0.20, 0.22, 0.27)

var levels: Array = []
var unlocked := 1
var cur := 0
var codes: Dictionary = {}  # "niveau/robot" -> texte du programme
var world = null
var running := false
var timer := 0.0
var editors: Dictionary = {}  # id du robot -> CodeEdit
var marks: Dictionary = {}  # id du robot -> ligne surlignée
var open_robot := ""
var tps := 6  # ticks par seconde
var debug_mode := false
var last_attack := -1

var view
var menu_btn: Button
var title_label: Label
var menu_panel: PanelContainer
var menu_text: RichTextLabel
var level_select: OptionButton
var unlock_all: CheckBox
var btn_run: Button
var btn_stop: Button
var debug_check: CheckButton
var speed_btn: MenuButton
var attack_box: HBoxContainer
var attack_edit: LineEdit
var attack_label: Label
var tick_label: Label
var status_label: Label
var editor_panel: PanelContainer
var editor_title: Label
var editor_holder: VBoxContainer
var console: RichTextLabel


func _ready() -> void:
	_load_levels()
	_load_progress()
	_build_ui()
	_select_level(mini(unlocked - 1, levels.size() - 1))


# ---------- données ----------

func _load_levels() -> void:
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://levels/index.json"))
	for id in index:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s.json" % id))
		if d is Dictionary:
			levels.append(d)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		unlocked = clampi(int(cfg.get_value("progression", "debloques", 1)), 1, maxi(1, levels.size()))
		if cfg.has_section("codes"):
			for k in cfg.get_section_keys("codes"):
				codes[k] = cfg.get_value("codes", k)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progression", "debloques", unlocked)
	for k in codes:
		cfg.set_value("codes", k, codes[k])
	cfg.save(SAVE_PATH)


func _key(robot_id: String) -> String:
	return "%s/%s" % [levels[cur].id, robot_id]


# ---------- construction de l'interface ----------

## Panneau opaque, à angles droits, avec un filet de séparation.
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _build_ui() -> void:
	# fond : l'entrepôt, plein écran
	view = RailView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.robot_clicked.connect(_open_editor)
	add_child(view)

	_build_editor_panel()
	_build_bottom_bar()
	_build_menu()
	_refresh_level_items()


func _build_menu() -> void:
	# barre fine du haut : bouton de menu + nom du niveau
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, TOP_H)
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 12)
	top.add_child(th)
	menu_btn = Button.new()
	menu_btn.pressed.connect(func(): _set_menu(not menu_panel.visible))
	th.add_child(menu_btn)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	th.add_child(title_label)

	# menu déroulant, sous la barre, à gauche
	menu_panel = _panel()
	menu_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu_panel.offset_top = TOP_H
	menu_panel.custom_minimum_size = Vector2(MENU_W, 0)
	menu_panel.visible = false
	add_child(menu_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	menu_panel.add_child(mv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	mv.add_child(row)
	row.add_child(_label("Niveau :"))
	level_select = OptionButton.new()
	level_select.custom_minimum_size = Vector2(300, 0)
	level_select.item_selected.connect(func(i): _select_level(i))
	row.add_child(level_select)
	menu_text = RichTextLabel.new()
	menu_text.bbcode_enabled = true
	menu_text.fit_content = true
	menu_text.scroll_active = false
	mv.add_child(menu_text)
	unlock_all = CheckBox.new()
	unlock_all.text = "Tout débloquer"
	unlock_all.toggled.connect(func(_b): _refresh_level_items())
	mv.add_child(unlock_all)


## Bouton plein, de couleur, plus visible que les boutons par défaut.
func _styled_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 46)
	btn.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		if state == "hover":
			sb.bg_color = color.lightened(0.15)
		elif state == "pressed":
			sb.bg_color = color.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = color.darkened(0.5)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, sb)
	return btn


func _build_bottom_bar() -> void:
	var bottom := _panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.custom_minimum_size = Vector2(0, BOTTOM_H)
	add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)

	# ligne du haut : résultat de l'essai, numéro de l'attaque, tick
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 14)
	bv.add_child(info)
	status_label = _label("")
	status_label.add_theme_font_size_override("font_size", 16)
	info.add_child(status_label)
	info.add_child(_spacer())
	attack_label = _label("")
	attack_label.modulate = Color(1, 1, 1, 0.6)
	info.add_child(attack_label)
	debug_check = CheckButton.new()
	debug_check.text = "Mode débogage"
	debug_check.tooltip_text = "Rejoue toujours la même attaque, pour tester ton programme."
	debug_check.toggled.connect(_on_debug_toggled)
	info.add_child(debug_check)
	tick_label = _label("")
	tick_label.modulate = Color(1, 1, 1, 0.6)
	info.add_child(tick_label)

	# ligne des commandes
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bv.add_child(bh)
	btn_run = _styled_button("▶  Lancer", Color(0.16, 0.50, 0.28))
	btn_run.pressed.connect(_on_run)
	bh.add_child(btn_run)
	btn_stop = _styled_button("■  Arrêter", Color(0.45, 0.20, 0.20))
	btn_stop.custom_minimum_size = Vector2(120, 46)
	btn_stop.pressed.connect(_on_stop)
	bh.add_child(btn_stop)
	bh.add_child(VSeparator.new())
	# vitesse : un seul petit bouton à icône de compteur ; les choix n'apparaissent qu'au clic
	speed_btn = MenuButton.new()
	speed_btn.icon = _gauge_icon()
	speed_btn.expand_icon = false
	speed_btn.custom_minimum_size = Vector2(46, 46)
	speed_btn.tooltip_text = "Vitesse de la simulation"
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.17, 0.19, 0.24) if state != "hover" else Color(0.24, 0.27, 0.34)
		box.border_color = BORDER
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		speed_btn.add_theme_stylebox_override(state, box)
	var pm := speed_btn.get_popup()
	for i in SPEEDS.size():
		pm.add_radio_check_item(SPEEDS[i][0], i)
		pm.set_item_checked(i, SPEEDS[i][1] == tps)
	pm.id_pressed.connect(_on_speed_chosen)
	bh.add_child(speed_btn)
	bh.add_child(_spacer())

	# mode débogage : rejouer la même attaque
	attack_box = HBoxContainer.new()
	attack_box.add_theme_constant_override("separation", 8)
	attack_box.visible = false
	bh.add_child(attack_box)
	attack_box.add_child(_label("Attaque n°"))
	attack_edit = LineEdit.new()
	attack_edit.custom_minimum_size = Vector2(90, 0)
	attack_edit.placeholder_text = "?"
	attack_edit.tooltip_text = "Chaque numéro correspond à une attaque précise : le même numéro rejoue exactement la même attaque."
	attack_box.add_child(attack_edit)
	var b_new := Button.new()
	b_new.text = "Autre attaque"
	b_new.custom_minimum_size = Vector2(0, 40)
	b_new.pressed.connect(func(): attack_edit.text = str(_new_attack_id()))
	attack_box.add_child(b_new)


## Petite icône de compteur (cadran et aiguille), dessinée en SVG.
func _gauge_icon() -> Texture2D:
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24">
<path d="M3.5 18 A9 9 0 1 1 20.5 18" fill="none" stroke="white" stroke-width="2.2" stroke-linecap="round"/>
<line x1="12" y1="14.5" x2="16.8" y2="8.2" stroke="white" stroke-width="2.2" stroke-linecap="round"/>
<circle cx="12" cy="14.5" r="1.9" fill="white"/></svg>"""
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


func _on_speed_chosen(id: int) -> void:
	tps = SPEEDS[id][1]
	var pm := speed_btn.get_popup()
	for i in SPEEDS.size():
		pm.set_item_checked(i, i == id)
	speed_btn.tooltip_text = "Vitesse : %s" % String(SPEEDS[id][0]).replace("  ", " ")


func _new_attack_id() -> int:
	return randi() % 100000


func _on_debug_toggled(on: bool) -> void:
	debug_mode = on
	attack_box.visible = on
	attack_label.visible = not on
	if on and last_attack >= 0:
		attack_edit.text = str(last_attack)  # on rejoue l'attaque qu'on vient de voir


func _build_editor_panel() -> void:
	# collé au bord droit, entre la barre du haut et celle du bas
	editor_panel = _panel()
	editor_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	editor_panel.offset_left = -EDITOR_W
	editor_panel.offset_right = 0
	editor_panel.offset_top = TOP_H
	editor_panel.offset_bottom = -BOTTOM_H
	editor_panel.visible = false
	add_child(editor_panel)
	var ev := VBoxContainer.new()
	editor_panel.add_child(ev)
	var eh := HBoxContainer.new()
	ev.add_child(eh)
	editor_title = Label.new()
	editor_title.add_theme_font_size_override("font_size", 16)
	editor_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eh.add_child(editor_title)
	var b_reset := Button.new()
	b_reset.text = "↺ Code de départ"
	b_reset.flat = true
	b_reset.pressed.connect(_on_reset_code)
	eh.add_child(b_reset)
	var b_close := Button.new()
	b_close.text = "✕"
	b_close.flat = true
	b_close.pressed.connect(_close_editor)
	eh.add_child(b_close)
	editor_holder = VBoxContainer.new()
	editor_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ev.add_child(editor_holder)
	console = RichTextLabel.new()
	console.bbcode_enabled = true
	console.scroll_following = true
	console.custom_minimum_size = Vector2(0, 90)
	ev.add_child(console)


func _make_editor() -> CodeEdit:
	var e := CodeEdit.new()
	e.size_flags_vertical = Control.SIZE_EXPAND_FILL
	e.gutters_draw_line_numbers = true
	e.indent_use_spaces = true
	e.indent_size = 4
	e.indent_automatic = true
	e.auto_brace_completion_enabled = true
	e.highlight_current_line = true
	e.add_theme_font_size_override("font_size", 16)
	var hl := CodeHighlighter.new()
	hl.number_color = Color(0.95, 0.75, 0.4)
	hl.symbol_color = Color(0.8, 0.8, 0.85)
	hl.function_color = Color(0.45, 0.75, 1.0)
	hl.member_variable_color = Color(0.9, 0.9, 0.9)
	for kw in ["while", "if", "elif", "else", "for", "in", "and", "or", "not", "pass", "break", "continue", "True", "False", "None"]:
		hl.add_keyword_color(kw, Color(0.95, 0.5, 0.6))
	hl.add_color_region("#", "", Color(0.5, 0.55, 0.6), true)
	hl.add_color_region("\"", "\"", Color(0.6, 0.85, 0.5))
	hl.add_color_region("'", "'", Color(0.6, 0.85, 0.5))
	e.syntax_highlighter = hl
	e.visible = false
	return e


func _refresh_level_items() -> void:
	level_select.clear()
	for i in levels.size():
		level_select.add_item("%d. %s" % [i + 1, levels[i].titre])
		level_select.set_item_disabled(i, i >= unlocked and not unlock_all.button_pressed)
	level_select.select(cur)


# ---------- menu déroulant ----------

func _set_menu(show: bool) -> void:
	menu_panel.visible = show
	menu_btn.text = "▲ Menu" if show else "☰ Menu"
	if show:
		menu_text.text = _statement_text(levels[cur])


func _statement_text(lv: Dictionary) -> String:
	var t := String(lv.enonce) + "\n\n[b]Fonctions du robot[/b]\n"
	for f in lv.api:
		t += "• " + World.API_DOC[f] + "\n"
	for b in lv.get("builtins", []):
		if b == "print":
			t += "• print(...) : affiche dans la console\n"
		elif b == "range":
			t += "• range(n) : à utiliser avec for\n"
	t += "\n[color=gray]Clique sur un robot pour écrire son programme.[/color]"
	return t


# ---------- niveaux ----------

func _save_editors() -> void:
	if cur < levels.size():
		for id in editors:
			codes[_key(id)] = editors[id].text


func _select_level(idx: int) -> void:
	if levels.is_empty():
		return
	_save_editors()
	_stop()
	cur = idx
	var lv: Dictionary = levels[cur]
	level_select.select(cur)
	title_label.text = "Niveau %d — %s" % [cur + 1, lv.titre]
	# un éditeur par robot
	for id in editors:
		editors[id].queue_free()
	editors.clear()
	marks.clear()
	open_robot = ""
	editor_panel.visible = false
	for spec in lv.get("robots", [{"id": "robot", "nom": "Robot"}]):
		var e := _make_editor()
		e.text = codes.get(_key(spec.id), lv.code_initial)
		editor_holder.add_child(e)
		editors[spec.id] = e
	console.clear()
	status_label.text = ""
	world = World.new(lv, {}, 0)
	view.world = world
	view.alpha = 1.0
	view.queue_redraw()
	tick_label.text = ""
	_set_menu(true)  # le scénario s'affiche au début du niveau


# ---------- éditeurs ----------

func _robot_name(id: String) -> String:
	for spec in levels[cur].get("robots", []):
		if spec.id == id:
			return spec.get("nom", id)
	return id


func _open_editor(id: String) -> void:
	if not editors.has(id):
		return
	_set_menu(false)
	open_robot = id
	for k in editors:
		editors[k].visible = (k == id)
		editors[k].editable = not running
	editor_title.text = "Programme — %s" % _robot_name(id)
	editor_panel.visible = true


func _close_editor() -> void:
	open_robot = ""
	editor_panel.visible = false


func _on_reset_code() -> void:
	if open_robot != "" and not running:
		editors[open_robot].text = levels[cur].code_initial


# ---------- exécution ----------

func _on_run() -> void:
	var lv: Dictionary = levels[cur]
	_set_menu(false)
	_save_editors()
	_save_progress()
	_clear_marks()
	var compiled := {}
	for id in editors:
		var res := Interp.compile(editors[id].text, lv.get("syntaxe", []), lv.get("api", []), lv.get("builtins", []))
		if not res.ok:
			console.clear()
			_log("[color=tomato]%s — ligne %d : %s[/color]" % [_robot_name(id), res.line, res.msg])
			_set_status("Erreur dans le programme de %s" % _robot_name(id), Color.TOMATO)
			_open_editor(id)
			_mark_line(id, res.line)
			return
		compiled[id] = res.code
	var attack: int
	if debug_mode and attack_edit.text.strip_edges().is_valid_int():
		attack = attack_edit.text.strip_edges().to_int()  # même numéro = même attaque
	else:
		attack = _new_attack_id()
	last_attack = attack
	attack_edit.text = str(attack)
	attack_label.text = "Attaque n° %d" % attack
	console.clear()
	_log("[color=gray]Attaque n° %d[/color]" % attack)
	_set_status("", Color.WHITE)
	world = World.new(lv, compiled, attack)
	view.world = world
	view.alpha = 1.0
	_set_running(true)
	timer = 0.0
	view.queue_redraw()


func _set_status(t: String, c: Color) -> void:
	status_label.text = t
	status_label.modulate = c


func _set_running(r: bool) -> void:
	running = r
	for id in editors:
		editors[id].editable = not r


func _on_stop() -> void:
	if running:
		_log("[color=gray]Arrêté.[/color]")
	_stop()


func _stop() -> void:
	_set_running(false)
	_clear_marks()


func _process(delta: float) -> void:
	if not running or world == null:
		return
	var interval := 1.0 / float(tps)
	timer += delta
	var guard := 0
	while timer >= interval and running and guard < 60:
		timer -= interval
		guard += 1
		world.tick()
		_drain_prints()
		if world.status != "en_cours":
			_finish()
			break
		for rb in world.robots:
			_mark_line(rb.id, rb.vm.last_line)
	tick_label.text = "Tick %d" % world.tick_n
	view.alpha = clampf(timer / interval, 0.0, 1.0) if running else 1.0
	view.queue_redraw()


func _drain_prints() -> void:
	for rb in world.robots:
		var vm = rb.vm
		for line in vm.printed:
			_log("[color=#9fd0ff]%s > %s[/color]" % [rb.nom, str(line).replace("[", "[lb]")])
		vm.printed.clear()
		for n in vm.notices:
			_log("[color=gray]%s : %s[/color]" % [rb.nom, n])
		vm.notices.clear()


func _finish() -> void:
	_set_running(false)
	view.alpha = 1.0
	view.queue_redraw()
	match world.status:
		"victoire":
			var msg := "Victoire !"
			if cur + 1 == unlocked and unlocked < levels.size():
				unlocked += 1
				msg += " Niveau %d débloqué." % unlocked
				_refresh_level_items()
			_set_status(msg, Color.LIGHT_GREEN)
			_log("[color=lightgreen]%s[/color]" % world.message)
			_save_progress()
		"defaite":
			_set_status("Échec : %s" % world.message, Color.ORANGE)
			_log("[color=orange]%s[/color] [color=gray](attaque n° %d)[/color]" % [world.message, world.seed_used])
		"erreur":
			_set_status("Erreur dans un programme (voir la console)", Color.TOMATO)
			_log("[color=tomato]%s[/color]" % world.message)
			for rb in world.robots:
				if not rb.vm.error.is_empty():
					_open_editor(rb.id)
					_mark_line(rb.id, rb.vm.error.line)


func _log(bb: String) -> void:
	console.append_text(bb + "\n")


# ---------- surlignage de la ligne courante ----------

func _clear_marks() -> void:
	for id in marks:
		var e: CodeEdit = editors.get(id)
		if e != null and marks[id] >= 0 and marks[id] < e.get_line_count():
			e.set_line_background_color(marks[id], Color(0, 0, 0, 0))
	marks.clear()


func _mark_line(id: String, line_1based: int) -> void:
	var e: CodeEdit = editors.get(id)
	if e == null:
		return
	if marks.has(id) and marks[id] >= 0 and marks[id] < e.get_line_count():
		e.set_line_background_color(marks[id], Color(0, 0, 0, 0))
	var i := line_1based - 1
	if i >= 0 and i < e.get_line_count():
		e.set_line_background_color(i, Color(0.3, 0.5, 0.9, 0.25))
		marks[id] = i
