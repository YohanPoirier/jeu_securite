extends Control
## Interface épurée : l'entrepôt en plein écran et des zones opaques par-dessus.
##   - en haut : une barre fine (bouton Menu, nom du niveau, bouton « Sorties ») ;
##   - au centre, par-dessus : un message à fermer (scénario au début du niveau) ou le menu
##     (recommencer, aide, retour au menu principal) ;
##   - en bas : lancement du code (Lancer + choix de l'attaque, Arrêter, vitesse) et résultat ;
##   - à gauche, collé au bord : l'éditeur du robot sur lequel on a cliqué (un éditeur par robot) ;
##   - à droite, collé au bord : les sorties (print, erreurs), toujours avec le nom du robot.

const Interp = preload("res://scripts/interpreter.gd")
const World = preload("res://scripts/world.gd")
const RailView = preload("res://scripts/rail_view.gd")

const SAVE_PATH := "user://progression.cfg"
const TOP_H := 40
const BOTTOM_H := 102
const SPEEDS := [["Lent  (×½)", 3], ["Normal  (×1)", 6], ["Rapide  (×2)", 12], ["Très rapide  (×4)", 24]]
const GREEN := Color(0.16, 0.50, 0.28)
const REPLAY_COLOR := Color(1.0, 0.82, 0.45)
const EDITOR_W := 520
const OUT_W := 360
const MODAL_W := 440
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
var sim_paused := false  # vrai tant que le choix de vitesse est ouvert
var attacks: Dictionary = {}  # id du niveau -> liste des attaques déjà jouées (n° 1, 2, 3...)
var attack_choice := -1  # -1 : nouvelle attaque ; k : rejouer l'attaque n° k+1
var run_replay := false
var out_count := 0  # sorties non lues (pastille rouge), plafonnée à 50
var out_badge: PanelContainer
var out_badge_label: Label

var view
var menu_btn: Button
var modal: Control
var modal_box: VBoxContainer
var modal_kind := ""  # "" (fermé), scenario, menu, aide, principal
var unlock_all := false
var help_tab := "interface"
var title_label: Label
var btn_run: Button
var btn_stop: Button
var speed_btn: MenuButton
var attack_btn: MenuButton
var out_btn: Button
var out_panel: PanelContainer
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
	_build_output_panel()
	_build_bottom_bar()
	_build_menu()
	_build_modal()


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
	menu_btn.text = "☰ Menu"
	menu_btn.pressed.connect(func(): _show_modal("menu"))
	th.add_child(menu_btn)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	th.add_child(title_label)
	th.add_child(_spacer())
	out_btn = Button.new()
	out_btn.text = "▤ Sorties"
	out_btn.tooltip_text = "Affiche ou masque les sorties des programmes (print et erreurs)"
	out_btn.pressed.connect(func(): _set_out(not out_panel.visible))
	th.add_child(out_btn)
	# pastille rouge façon notification : nombre de sorties non lues
	out_badge = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.85, 0.15, 0.15)
	bsb.set_corner_radius_all(9)
	bsb.content_margin_left = 5
	bsb.content_margin_right = 5
	bsb.content_margin_top = 0
	bsb.content_margin_bottom = 0
	out_badge.add_theme_stylebox_override("panel", bsb)
	out_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	out_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	out_badge.offset_top = -2
	out_badge.offset_right = 8
	out_badge.visible = false
	out_badge_label = Label.new()
	out_badge_label.add_theme_font_size_override("font_size", 12)
	out_badge.add_child(out_badge_label)
	out_btn.add_child(out_badge)


## Donne à un bouton un fond plein de couleur, à angles arrondis.
func _apply_colors(btn: BaseButton, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		if state == "hover":
			sb.bg_color = color.lightened(0.15)
		elif state == "pressed" or state == "hover_pressed":
			sb.bg_color = color.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = color.darkened(0.5)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.flat = false  # les MenuButton sont plats par défaut


## Bouton plein, de couleur, plus visible que les boutons par défaut.
func _styled_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 46)
	btn.add_theme_font_size_override("font_size", 18)
	_apply_colors(btn, color)
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
	tick_label = _label("")
	tick_label.modulate = Color(1, 1, 1, 0.6)
	info.add_child(tick_label)

	# ligne des commandes
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bv.add_child(bh)
	# Lancer + petite flèche pour choisir l'attaque (nouvelle ou ancienne)
	var run_box := HBoxContainer.new()
	run_box.add_theme_constant_override("separation", 2)
	bh.add_child(run_box)
	btn_run = _styled_button("▶  Lancer", GREEN)
	btn_run.pressed.connect(_on_run)
	run_box.add_child(btn_run)
	attack_btn = MenuButton.new()
	attack_btn.text = "▲"
	attack_btn.custom_minimum_size = Vector2(34, 46)
	attack_btn.add_theme_font_size_override("font_size", 14)
	attack_btn.tooltip_text = "Choisir l'attaque : une nouvelle, ou une ancienne à rejouer pour déboguer"
	_apply_colors(attack_btn, GREEN.darkened(0.15))
	attack_btn.get_popup().id_pressed.connect(_on_attack_chosen)
	run_box.add_child(attack_btn)
	btn_stop = _styled_button("■  Arrêter", Color(0.45, 0.20, 0.20))
	btn_stop.custom_minimum_size = Vector2(120, 46)
	btn_stop.pressed.connect(_on_stop)
	bh.add_child(btn_stop)
	# vitesse : petit bouton de couleur à icône de compteur ; les choix n'apparaissent qu'au clic,
	# et la simulation est en pause tant qu'on n'a pas choisi
	speed_btn = MenuButton.new()
	speed_btn.icon = _gauge_icon()
	speed_btn.expand_icon = false
	speed_btn.custom_minimum_size = Vector2(46, 46)
	speed_btn.tooltip_text = "Vitesse de la simulation"
	_apply_colors(speed_btn, Color(0.20, 0.38, 0.62))
	var pm := speed_btn.get_popup()
	for i in SPEEDS.size():
		pm.add_radio_check_item(SPEEDS[i][0], i)
		pm.set_item_checked(i, SPEEDS[i][1] == tps)
	pm.id_pressed.connect(_on_speed_chosen)
	pm.about_to_popup.connect(func(): sim_paused = true)
	pm.popup_hide.connect(func(): sim_paused = false)
	bh.add_child(speed_btn)
	_rebuild_attack_menu()


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


# ---------- attaques ----------

func _new_attack_id() -> int:
	return randi() % 100000


## Attaques déjà jouées sur le niveau courant (numérotées 1, 2, 3... dans l'ordre).
func _level_attacks() -> Array:
	var id: String = levels[cur].id
	if not attacks.has(id):
		attacks[id] = []
	return attacks[id]


func _rebuild_attack_menu() -> void:
	var pm := attack_btn.get_popup()
	pm.clear()
	pm.add_radio_check_item("Nouvelle attaque", 0)
	var n := _level_attacks().size() if not levels.is_empty() else 0
	if n > 0:
		pm.add_separator("Anciennes attaques")
	for k in n:
		pm.add_radio_check_item("Attaque %d" % (k + 1), k + 1)
	for i in pm.item_count:
		if not pm.is_item_separator(i):
			pm.set_item_checked(i, pm.get_item_id(i) == attack_choice + 1)


func _replay_msg(n: int) -> String:
	return "↻ Rejeu de l'attaque %d — simple essai pour déboguer : cette partie ne valide pas le niveau." % n


func _on_attack_chosen(id: int) -> void:
	attack_choice = id - 1
	_rebuild_attack_menu()
	if attack_choice >= 0:
		_set_status(_replay_msg(id), REPLAY_COLOR)
	else:
		_set_status("", Color.WHITE)


func _build_editor_panel() -> void:
	# collé au bord gauche, entre la barre du haut et celle du bas
	editor_panel = _panel()
	editor_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	editor_panel.offset_left = 0
	editor_panel.offset_right = EDITOR_W
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


## Fenêtre des sorties, collée au bord droit : print, erreurs et remarques, avec le nom du robot.
func _build_output_panel() -> void:
	out_panel = _panel()
	out_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	out_panel.offset_left = -OUT_W
	out_panel.offset_right = 0
	out_panel.offset_top = TOP_H
	out_panel.offset_bottom = -BOTTOM_H
	out_panel.visible = false
	add_child(out_panel)
	var ov := VBoxContainer.new()
	out_panel.add_child(ov)
	var oh := HBoxContainer.new()
	ov.add_child(oh)
	var t := _label("Sorties")
	t.add_theme_font_size_override("font_size", 16)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(t)
	var b_clear := Button.new()
	b_clear.text = "Effacer"
	b_clear.flat = true
	b_clear.pressed.connect(func(): console.clear())
	oh.add_child(b_clear)
	var b_close := Button.new()
	b_close.text = "✕"
	b_close.flat = true
	b_close.pressed.connect(func(): _set_out(false))
	oh.add_child(b_close)
	console = RichTextLabel.new()
	console.bbcode_enabled = true
	console.scroll_following = true
	console.selection_enabled = true
	console.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ov.add_child(console)


func _set_out(show: bool) -> void:
	out_panel.visible = show
	if show:
		_reset_out_count()


func _reset_out_count() -> void:
	out_count = 0
	if out_badge != null:
		out_badge.visible = false


func _count_out() -> void:
	out_count = mini(out_count + 1, 50)
	out_badge_label.text = "50+" if out_count >= 50 else str(out_count)
	out_badge.visible = true


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


func _is_unlocked(i: int) -> bool:
	return unlock_all or i < unlocked


# ---------- fenêtre centrale (scénario, menu, aide, menu principal) ----------

func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP  # bloque les clics sur le jeu derrière
	modal.visible = false
	add_child(modal)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)
	var panel := _panel()
	panel.get_theme_stylebox("panel").set_content_margin_all(22)
	panel.custom_minimum_size = Vector2(MODAL_W, 0)
	center.add_child(panel)
	modal_box = VBoxContainer.new()
	modal_box.add_theme_constant_override("separation", 12)
	panel.add_child(modal_box)


func _modal_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	return b


func _modal_title(text: String, closable: bool) -> void:
	var row := HBoxContainer.new()
	modal_box.add_child(row)
	var t := _label(text)
	t.add_theme_font_size_override("font_size", 20)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	if closable:
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.pressed.connect(_close_modal)
		row.add_child(x)


func _show_modal(kind: String) -> void:
	modal_kind = kind
	for c in modal_box.get_children():
		modal_box.remove_child(c)
		c.queue_free()
	match kind:
		"scenario":
			var l := _label("scénario")
			l.add_theme_font_size_override("font_size", 20)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(0, 80)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			modal_box.add_child(l)
			modal_box.add_child(_modal_button("Fermer", _close_modal))
		"menu":
			_modal_title("Menu", true)
			modal_box.add_child(_modal_button("Recommencer le niveau", _restart_level))
			modal_box.add_child(_modal_button("Aide", func(): _show_modal("aide")))
			modal_box.add_child(_modal_button("Retour au menu principal", func(): _show_modal("principal")))
		"aide":
			_modal_title("Aide", true)
			var tabs := HBoxContainer.new()
			tabs.add_theme_constant_override("separation", 8)
			modal_box.add_child(tabs)
			for tb in [["interface", "L'interface"], ["python", "Python"], ["robot", "Le robot"]]:
				var b := _modal_button(tb[1], func(): help_tab = tb[0]; _show_modal("aide"))
				b.toggle_mode = true
				b.button_pressed = (help_tab == tb[0])
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				tabs.add_child(b)
			var sc := ScrollContainer.new()
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			sc.custom_minimum_size = Vector2(620, 360)
			modal_box.add_child(sc)
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true
			rt.fit_content = true
			rt.scroll_active = false
			rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var mono := SystemFont.new()
			mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
			rt.add_theme_font_override("mono_font", mono)
			rt.add_theme_color_override("default_color", Color(0.88, 0.9, 0.95))
			rt.text = _help_text(help_tab)
			sc.add_child(rt)
			modal_box.add_child(_modal_button("Retour", func(): _show_modal("menu")))
		"principal":
			var t := _label("Garde Robot")
			t.add_theme_font_size_override("font_size", 26)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			modal_box.add_child(t)
			for i in levels.size():
				var b := _modal_button("%d. %s" % [i + 1, levels[i].titre], func(): _select_level(i))
				b.disabled = not _is_unlocked(i)
				modal_box.add_child(b)
			var cb := CheckBox.new()
			cb.text = "Tout débloquer"
			cb.button_pressed = unlock_all
			cb.toggled.connect(func(on): unlock_all = on; _show_modal("principal"))
			modal_box.add_child(cb)
	modal.visible = true


func _close_modal() -> void:
	modal_kind = ""
	modal.visible = false


func _restart_level() -> void:
	_stop()
	console.clear()
	_reset_out_count()
	out_panel.visible = false
	attack_choice = -1
	_rebuild_attack_menu()
	attack_label.text = ""
	status_label.text = ""
	tick_label.text = ""
	world = World.new(levels[cur], {}, 0)
	view.world = world
	view.alpha = 1.0
	view.queue_redraw()
	_close_modal()


func _help_text(tab: String) -> String:
	var lv: Dictionary = levels[cur]
	var syn: Array = lv.get("syntaxe", [])
	var api: Array = lv.get("api", [])
	var t := ""
	match tab:
		"interface":
			t += "[b]L'entrepôt[/b]\nTon robot circule sur un rail. Des intrus entrent dans l'entrepôt : il doit les arrêter avant qu'ils n'atteignent une porte.\n\n"
			t += "[b]Programmer un robot[/b]\nClique sur un robot : son éditeur s'ouvre à gauche. Chaque robot a son propre programme. ↺ remet le code de départ, ✕ ferme l'éditeur.\n\n"
			t += "[b]Lancer[/b]\n▶ Lancer démarre l'attaque. La petite flèche ▲ permet de choisir une nouvelle attaque, ou de rejouer une ancienne (Attaque 1, 2, 3…) pour déboguer : un rejeu ne valide pas le niveau. ■ Arrêter interrompt la simulation.\n\n"
			t += "[b]Vitesse[/b]\nLe bouton compteur règle la vitesse. La simulation est en pause tant qu'on n'a pas choisi.\n\n"
			t += "[b]Sorties[/b]\nLa fenêtre de droite affiche les print et les erreurs, toujours avec le nom du robot concerné.\n\n"
			t += "[b]Menu[/b]\nRecommencer le niveau, ouvrir cette aide, retourner au menu principal."
		"python":
			t += "[b]Un programme[/b]\nUn programme est une suite d'instructions, une par ligne, exécutées dans l'ordre. Appeler une fonction s'écrit avec des parenthèses :\n[code]avancer()[/code]\nUn # commence un commentaire, ignoré par l'ordinateur. L'indentation (4 espaces) compte : elle indique ce qui appartient à un bloc.\n\n"
			if "boucle_while" in syn:
				t += "[b]Répéter : while[/b]\n[code]while True:\n    avancer()[/code]\nTrue signifie « vrai, toujours » : le bloc indenté se répète sans fin.\n\n"
			if "conditions" in syn:
				var cond := "fin_de_rail()" if api.has("fin_de_rail") else "position() < longueur() - 1"
				t += "[b]Décider : if / elif / else[/b]\n[code]if %s:\n    avancer()\nelse:\n    reculer()[/code]\nOn compare avec ==, !=, <, <=, >, >= et on combine avec and, or, not. elif signifie « sinon si ».\n\n" % cond
			if "variables" in syn:
				t += "[b]Variables[/b]\n[code]n = 3\nwhile n > 0:\n    avancer()\n    n = n - 1[/code]\nUne variable garde une valeur ; on peut la modifier.\n\n"
			if "arithmetique" in syn:
				t += "[b]Calculs[/b]\n[code]+  -  *  //  %[/code]\n// est la division entière (7 // 2 vaut 3) et % le reste (7 % 2 vaut 1).\n\n"
			if "boucle_for" in syn:
				t += "[b]Répéter n fois : for[/b]\n[code]for i in range(3):\n    avancer()[/code]\n\n"
			t += "[color=gray]D'autres notions se débloquent au fil des niveaux.[/color]"
		"robot":
			t += "[b]Fonctions du robot (ce niveau)[/b]\n"
			for f in api:
				t += "• " + World.API_DOC[f] + "\n"
			for b in lv.get("builtins", []):
				if b == "print":
					t += "• print(...) : affiche dans la fenêtre des sorties\n"
				elif b == "range":
					t += "• range(n) : à utiliser avec for\n"
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
	_reset_out_count()
	out_panel.visible = false
	attack_choice = -1
	_rebuild_attack_menu()
	attack_label.text = ""
	status_label.text = ""
	world = World.new(lv, {}, 0)
	view.world = world
	view.alpha = 1.0
	view.queue_redraw()
	tick_label.text = ""
	_show_modal("scenario")  # le scénario s'affiche au début du niveau


# ---------- éditeurs ----------

func _robot_name(id: String) -> String:
	for spec in levels[cur].get("robots", []):
		if spec.id == id:
			return spec.get("nom", id)
	return id


func _open_editor(id: String) -> void:
	if not editors.has(id):
		return
	_close_modal()
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
	_close_modal()
	_save_editors()
	_save_progress()
	_clear_marks()
	console.clear()
	_reset_out_count()
	var compiled := {}
	for id in editors:
		var res := Interp.compile(editors[id].text, lv.get("syntaxe", []), lv.get("api", []), lv.get("builtins", []))
		if not res.ok:
			_log("[color=tomato]%s — ligne %d : %s[/color]" % [_robot_name(id), res.line, _esc(res.msg)], true)
			_set_status("Erreur dans le programme de %s" % _robot_name(id), Color.TOMATO)
			_open_editor(id)
			_mark_line(id, res.line)
			return
		compiled[id] = res.code
	var list := _level_attacks()
	var attack: int
	var number: int
	run_replay = attack_choice >= 0 and attack_choice < list.size()
	if run_replay:
		attack = list[attack_choice]  # même numéro = exactement la même attaque
		number = attack_choice + 1
		_set_status(_replay_msg(number), REPLAY_COLOR)
	else:
		attack = _new_attack_id()
		list.append(attack)
		number = list.size()
		_rebuild_attack_menu()
		_set_status("", Color.WHITE)
	attack_label.text = "Attaque %d%s" % [number, " (rejeu)" if run_replay else ""]
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
	attack_btn.disabled = r
	for id in editors:
		editors[id].editable = not r


func _on_stop() -> void:
	_stop()


func _stop() -> void:
	_set_running(false)
	_clear_marks()


func _process(delta: float) -> void:
	if not running or world == null or sim_paused or modal_kind != "":
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


## Échappe les crochets pour que le texte ne soit pas pris pour du BBCode.
func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _drain_prints() -> void:
	for rb in world.robots:
		var vm = rb.vm
		for line in vm.printed:
			_log("[color=#9fd0ff]%s ›[/color] %s" % [rb.nom, _esc(str(line))])
		vm.printed.clear()
		for n in vm.notices:
			_log("[color=gray]%s : %s[/color]" % [rb.nom, _esc(str(n))])
		vm.notices.clear()


func _finish() -> void:
	_set_running(false)
	view.alpha = 1.0
	view.queue_redraw()
	var note := " (rejeu : niveau non validé)" if run_replay else ""
	match world.status:
		"victoire":
			if run_replay:
				_set_status("Victoire" + note, REPLAY_COLOR)
			else:
				var msg := "Victoire !"
				if cur + 1 == unlocked and unlocked < levels.size():
					unlocked += 1
					msg += " Niveau %d débloqué." % unlocked
				_set_status(msg, Color.LIGHT_GREEN)
				_save_progress()
		"defaite":
			_set_status("Échec : %s%s" % [world.message, note], Color.ORANGE)
		"erreur":
			_set_status("Erreur dans un programme (voir les sorties)", Color.TOMATO)
			_log("[color=tomato]%s[/color]" % _esc(world.message), true)
			for rb in world.robots:
				if not rb.vm.error.is_empty():
					_open_editor(rb.id)
					_mark_line(rb.id, rb.vm.error.line)


## Ajoute une ligne aux sorties. Une erreur ouvre la fenêtre ; sinon, si elle est fermée,
## seule la pastille rouge du bouton « Sorties » compte les nouvelles lignes.
func _log(bb: String, force := false) -> void:
	console.append_text(bb + "\n")
	if force:
		_set_out(true)
	elif not out_panel.visible:
		_count_out()


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
