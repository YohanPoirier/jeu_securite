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
const BOTTOM_H := 64
const SPEEDS := [["Lent (×½)", 3], ["Normal (×1)", 6], ["Rapide (×2)", 12], ["Très rapide (×4)", 24]]
const GREEN := Color(0.16, 0.50, 0.28)
const ATTACK_TIP := "Attaque à lancer : une nouvelle, ou une ancienne à rejouer pour déboguer"
const ERROR_LINE := Color(0.9, 0.25, 0.25, 0.30)
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
var warn_icon: Texture2D
var replay_btn: Button
var replay_bubble: PopupPanel
var replay_title: Label
var replay_text: Label
var out_badge_label: Label

var view
var menu_btn: Button
var modal: Control
var modal_box: VBoxContainer
var modal_kind := ""  # "" (fermé), scenario, menu, aide, principal
var unlock_all := false
var help_tab := "interface"
var result_info: Dictionary = {}
var title_label: Label
var btn_run: Button
var btn_stop: Button
var speed_btn: Button
var speed_menu: PopupMenu
var attack_menu: PopupMenu
var attack_btn: Button
var out_btn: Button
var out_panel: PanelContainer
var editor_panel: PanelContainer
var toolbox: VBoxContainer  # boîte à outils : rappel des fonctions utilisables (repliable)
var toolbox_btn: Button
var tex_tb_open: Texture2D
var tex_tb_closed: Texture2D
const TOOLBOX_BG := Color(0.13, 0.15, 0.20)
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
	view.inset_top = TOP_H  # l'entrepôt se centre entre les deux barres
	view.inset_bottom = BOTTOM_H
	view.robot_clicked.connect(_open_editor)
	view.background_clicked.connect(_close_editor)
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
func _apply_colors(btn: BaseButton, color: Color, border := false) -> void:
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
		if border:
			sb.border_color = Color(0.32, 0.36, 0.45)
			sb.set_border_width_all(1)
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

	# ligne des commandes
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bv.add_child(bh)
	# Lancer + petite flèche pour choisir l'attaque (nouvelle ou ancienne)
	var run_box := HBoxContainer.new()
	run_box.add_theme_constant_override("separation", 8)
	bh.add_child(run_box)
	btn_run = _styled_button("▶  Lancer", GREEN)
	btn_run.pressed.connect(_on_run)
	run_box.add_child(btn_run)
	attack_btn = Button.new()
	attack_btn.custom_minimum_size = Vector2(210, 46)
	attack_btn.add_theme_font_size_override("font_size", 16)
	attack_btn.tooltip_text = ATTACK_TIP
	_apply_colors(attack_btn, Color(0.17, 0.19, 0.24), true)
	# petit bouton d'avertissement, posé sur le bouton d'attaque (il a la priorité sur le clic)
	replay_btn = Button.new()
	replay_btn.flat = true
	replay_btn.icon = _warning_icon()
	replay_btn.tooltip_text = "Cliquer pour en savoir plus"
	replay_btn.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	replay_btn.offset_left = 6
	replay_btn.offset_right = 40
	replay_btn.offset_top = 4
	replay_btn.offset_bottom = -4
	replay_btn.visible = false
	replay_btn.pressed.connect(_show_replay_bubble)
	attack_btn.add_child(replay_btn)
	_build_replay_bubble()
	attack_menu = _make_popup()
	attack_menu.id_pressed.connect(_on_attack_chosen)
	attack_btn.pressed.connect(func(): _popup_above(attack_btn, attack_menu))
	run_box.add_child(attack_btn)
	btn_stop = _styled_button("■  Arrêter", Color(0.45, 0.20, 0.20))
	btn_stop.custom_minimum_size = Vector2(120, 46)
	btn_stop.pressed.connect(_on_stop)
	bh.add_child(btn_stop)
	# vitesse : petit bouton de couleur à icône de compteur ; les choix n'apparaissent qu'au clic,
	# et la simulation est en pause tant qu'on n'a pas choisi
	speed_btn = Button.new()
	speed_btn.icon = _gauge_icon()
	speed_btn.expand_icon = false
	speed_btn.custom_minimum_size = Vector2(46, 46)
	speed_btn.tooltip_text = "Vitesse de la simulation"
	_apply_colors(speed_btn, Color(0.20, 0.38, 0.62))
	speed_menu = _make_popup()
	for i in SPEEDS.size():
		speed_menu.add_radio_check_item(SPEEDS[i][0], i)
		speed_menu.set_item_checked(i, SPEEDS[i][1] == tps)
	speed_menu.id_pressed.connect(_on_speed_chosen)
	speed_menu.about_to_popup.connect(func(): sim_paused = true)
	speed_menu.popup_hide.connect(func(): sim_paused = false)
	speed_btn.pressed.connect(func(): _popup_above(speed_btn, speed_menu))
	bh.add_child(speed_btn)
	_rebuild_attack_menu()


## Liste déroulante au style du jeu (fond sombre, survol bleu, pastilles de choix).
func _make_popup() -> PopupMenu:
	var pm := PopupMenu.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.13, 0.17)
	bg.border_color = Color(0.32, 0.36, 0.45)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(6)
	bg.shadow_color = Color(0, 0, 0, 0.5)
	bg.shadow_size = 6
	pm.add_theme_stylebox_override("panel", bg)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.22, 0.38, 0.62)
	hover.set_corner_radius_all(5)
	pm.add_theme_stylebox_override("hover", hover)
	pm.add_theme_font_size_override("font_size", 17)
	pm.add_theme_constant_override("v_separation", 12)
	pm.add_theme_constant_override("h_separation", 12)
	pm.add_theme_constant_override("item_start_padding", 10)
	pm.add_theme_constant_override("item_end_padding", 14)
	pm.add_theme_color_override("font_separator_color", Color(0.6, 0.65, 0.75))
	pm.add_theme_icon_override("radio_checked", _dot_icon(true))
	pm.add_theme_icon_override("radio_unchecked", _dot_icon(false))
	pm.min_size = Vector2i(190, 0)
	pm.max_size = Vector2i(420, 380)
	add_child(pm)
	return pm


func _dot_icon(checked: bool) -> Texture2D:
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
<circle cx="9" cy="9" r="7" fill="none" stroke="#8a93a6" stroke-width="1.8"/>%s</svg>""" % ("<circle cx=\"9\" cy=\"9\" r=\"3.8\" fill=\"#6fd08c\"/>" if checked else "")
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


## Ouvre une liste juste au-dessus d'un bouton (les boutons sont en bas de l'écran).
func _popup_above(btn: Control, pm: PopupMenu) -> void:
	pm.reset_size()
	var sz := Vector2i(pm.get_contents_minimum_size())
	sz.x = maxi(sz.x, int(btn.size.x))
	sz.y = mini(sz.y, pm.max_size.y)
	var top_left := Vector2i(btn.get_screen_transform() * Vector2.ZERO)
	pm.popup(Rect2i(Vector2i(top_left.x, top_left.y - sz.y - 8), sz))


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
	for i in SPEEDS.size():
		speed_menu.set_item_checked(i, i == id)
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
	var pm := attack_menu
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
	var replay := attack_choice >= 0
	attack_btn.text = ("Attaque %d  ▾" % (attack_choice + 1)) if replay else "Nouvelle attaque  ▾"
	replay_btn.visible = replay  # avertissement orange en rejeu
	attack_btn.tooltip_text = _replay_msg(attack_choice + 1) if replay else ATTACK_TIP


func _replay_msg(n: int) -> String:
	return "Rejeu de l'attaque %d : simple essai pour déboguer, cette partie ne valide pas le niveau." % n


func _on_attack_chosen(id: int) -> void:
	attack_choice = id - 1
	_rebuild_attack_menu()


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
	tex_tb_closed = _svg_icon("""<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24">
<path d="M8.5 8V6a1.5 1.5 0 0 1 1.5-1.5h4A1.5 1.5 0 0 1 15.5 6v2" fill="none" stroke="#b8c4d8" stroke-width="2"/>
<rect x="3" y="8" width="18" height="12" rx="2" fill="#b8c4d8"/>
<rect x="3" y="12.2" width="18" height="1.6" fill="#1a1d27"/>
<rect x="10.5" y="11" width="3" height="4" rx="0.8" fill="#f5a524"/></svg>""")
	tex_tb_open = _svg_icon("""<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24">
<path d="M5 9 L3 3.5 H21 L19 9" fill="none" stroke="#b8c4d8" stroke-width="2" stroke-linejoin="round"/>
<rect x="3" y="10" width="18" height="10" rx="2" fill="#b8c4d8"/>
<rect x="3" y="13.6" width="18" height="1.4" fill="#1a1d27"/>
<rect x="10.5" y="12.6" width="3" height="3.6" rx="0.8" fill="#f5a524"/></svg>""")
	toolbox_btn = _icon_button(tex_tb_closed,
		"Boîte à outils : rappel des fonctions du niveau (un clic sur l'une d'elles l'insère)")
	toolbox_btn.toggle_mode = true
	var sb_on := StyleBoxFlat.new()
	sb_on.bg_color = TOOLBOX_BG
	sb_on.corner_radius_top_left = 6
	sb_on.corner_radius_top_right = 6
	sb_on.set_content_margin_all(4)
	toolbox_btn.add_theme_stylebox_override("pressed", sb_on)
	toolbox_btn.add_theme_stylebox_override("hover_pressed", sb_on)
	toolbox_btn.toggled.connect(func(on):
		toolbox.visible = on
		toolbox_btn.icon = tex_tb_open if on else tex_tb_closed)
	eh.add_child(toolbox_btn)
	var b_reset := _icon_button(_svg_icon("""<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24">
<path d="M20 12a8 8 0 1 1-2.6-5.9" fill="none" stroke="#b8c4d8" stroke-width="2.2" stroke-linecap="round"/>
<path d="M20.5 3.5v5h-5" fill="none" stroke="#b8c4d8" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>"""),
		"Remettre le code de départ")
	b_reset.pressed.connect(_on_reset_code)
	eh.add_child(b_reset)
	var b_close := Button.new()
	b_close.text = "✕"
	b_close.flat = true
	b_close.pressed.connect(_close_editor)
	eh.add_child(b_close)
	toolbox = VBoxContainer.new()
	toolbox.visible = false
	ev.add_child(toolbox)
	editor_holder = VBoxContainer.new()
	editor_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ev.add_child(editor_holder)


func _toggle_toolbox() -> void:
	toolbox_btn.button_pressed = not toolbox_btn.button_pressed


func _svg_icon(svg: String) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


func _icon_button(tex: Texture2D, tip: String) -> Button:
	var b := Button.new()
	b.icon = tex
	b.flat = true
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	return b


## Boîte à outils : les fonctions (et notions de syntaxe) disponibles dans le niveau en cours.
## Un clic sur une fonction l'insère dans l'éditeur à la position du curseur.
func _refresh_toolbox() -> void:
	for c in toolbox.get_children():
		toolbox.remove_child(c)
		c.queue_free()
	var lv: Dictionary = levels[cur]
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = TOOLBOX_BG
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", sb)
	var link := Control.new()  # languette reliant le panneau à l'icône de la boîte à outils
	link.custom_minimum_size = Vector2(0, 6)
	link.draw.connect(func():
		var x: float = toolbox_btn.global_position.x + toolbox_btn.size.x / 2.0 - link.global_position.x
		var w: float = toolbox_btn.size.x
		link.draw_rect(Rect2(x - w / 2.0, 0, w, 6), TOOLBOX_BG))
	toolbox.add_theme_constant_override("separation", 0)
	toolbox.add_child(link)
	toolbox.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var items: Array = []  # [code à insérer, nom affiché, description]
	for f in lv.get("api", []):
		var doc: String = World.API_DOC[f]
		var parts := doc.split(" : ", true, 1)
		var args := "1" if World.API_ARITY[f] == 1 else ""
		items.append([f + "(" + args + ")", String(parts[0]), String(parts[1]) if parts.size() > 1 else ""])
	for it in items:
		var row := HBoxContainer.new()
		var btn := Button.new()
		btn.text = it[1]
		btn.flat = true
		btn.custom_minimum_size.x = 150
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.95, 1.0))
		btn.pressed.connect(_insert_snippet.bind(it[0]))
		row.add_child(btn)
		var d := Label.new()
		d.text = it[2]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", Color(0.78, 0.80, 0.86))
		row.add_child(d)
		col.add_child(row)


func _insert_snippet(code: String) -> void:
	if open_robot == "" or running or not editors.has(open_robot):
		return
	var ed: TextEdit = editors[open_robot]
	ed.insert_text_at_caret(code)
	ed.grab_focus()


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


## Grosse bulle d'explication qui s'ouvre au clic sur l'avertissement orange.
func _build_replay_bubble() -> void:
	replay_bubble = PopupPanel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17)
	sb.border_color = Color(0.96, 0.65, 0.14)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	replay_bubble.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	replay_bubble.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var ic := TextureRect.new()
	ic.texture = _warning_icon()
	ic.custom_minimum_size = Vector2(22, 22)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(ic)
	replay_title = _label("")
	replay_title.add_theme_font_size_override("font_size", 19)
	head.add_child(replay_title)
	replay_text = _label("Cette partie sert uniquement à déboguer : le niveau ne sera pas validé, même si ton robot gagne.\n\nPour jouer une attaque pour de vrai, choisis « Nouvelle attaque ».")
	replay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	replay_text.custom_minimum_size = Vector2(360, 0)
	replay_text.add_theme_font_size_override("font_size", 16)
	v.add_child(replay_text)
	add_child(replay_bubble)


func _show_replay_bubble() -> void:
	replay_title.text = "Rejeu de l'attaque %d" % (attack_choice + 1)
	replay_bubble.reset_size()
	var top_left := Vector2i(replay_btn.get_screen_transform() * Vector2.ZERO)
	replay_bubble.popup(Rect2i(Vector2i(top_left.x, top_left.y - 220), Vector2i(400, 10)))
	await get_tree().process_frame
	replay_bubble.position = Vector2i(top_left.x, top_left.y - replay_bubble.size.y - 14)


func _warning_icon() -> Texture2D:
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24">
<path d="M12 3 L22 20.5 H2 Z" fill="#f5a524" stroke="#f5a524" stroke-width="2" stroke-linejoin="round"/>
<rect x="11" y="9" width="2" height="6.5" rx="1" fill="#1a1a1a"/><circle cx="12" cy="17.6" r="1.2" fill="#1a1a1a"/></svg>"""
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


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
		"reset_code":
			_modal_title("Remettre le code de départ ?", false)
			var warn := _label("Le programme de %s sera remplacé par le code de départ du niveau. Cette action est définitive." % _robot_name(open_robot))
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.custom_minimum_size = Vector2(380, 0)
			modal_box.add_child(warn)
			modal_box.add_child(_modal_button("Remettre le code de départ", _do_reset_code))
			modal_box.add_child(_modal_button("Annuler", _close_modal))
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
		"resultat":
			var rt := _label(String(result_info.title))
			rt.add_theme_font_size_override("font_size", 28)
			rt.add_theme_color_override("font_color", result_info.color)
			rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rt.custom_minimum_size = Vector2(0, 60)
			rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			modal_box.add_child(rt)
			if result_info.title == "Échec":  # la cause de la défaite, pas pour une victoire
				var body := _label(String(result_info.text))
				body.add_theme_font_size_override("font_size", 17)
				body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				body.custom_minimum_size = Vector2(MODAL_W - 20, 0)
				modal_box.add_child(body)
			if result_info.next:
				modal_box.add_child(_modal_button("Niveau suivant", func(): _select_level(cur + 1)))
			modal_box.add_child(_modal_button("Fermer", _close_modal))
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
			t += "[b]L'entrepôt[/b]\nTon robot circule dans le couloir. Des voleurs forcent une porte, volent un objet dans une salle puis essaient de ressortir avec : il doit les arrêter avant qu'ils ne sortent.\n\n"
			t += "[b]Programmer un robot[/b]\nClique sur un robot : son éditeur s'ouvre à gauche. Chaque robot a son propre programme. la petite boîte à outils déplie un rappel des fonctions du robot (un clic sur l'une d'elles l'insère dans ton code), ↻ remet le code de départ (après confirmation), ✕ ferme l'éditeur.\n\n"
			t += "[b]Lancer[/b]\n▶ Lancer démarre l'attaque. La petite flèche ▲ permet de choisir une nouvelle attaque, ou de rejouer une ancienne (Attaque 1, 2, 3…) pour déboguer : un rejeu ne valide pas le niveau. ■ Arrêter interrompt la simulation.\n\n"
			t += "[b]Vitesse[/b]\nLe bouton compteur règle la vitesse. La simulation est en pause tant qu'on n'a pas choisi.\n\n"
			t += "[b]Réflexion[/b]\nSi le programme calcule trop longtemps avant d'agir, le robot perd son tour : un petit cerveau s'affiche au-dessus de lui.\n\n"
			t += "[b]Sorties[/b]\nLa fenêtre de droite affiche les print et les erreurs, toujours avec le nom du robot concerné.\n\n"
			t += "[b]Menu[/b]\nRecommencer le niveau, ouvrir cette aide, retourner au menu principal."
		"python":
			t += "[b]Un programme[/b]\nUn programme est une suite d'instructions, une par ligne, exécutées dans l'ordre. Appeler une fonction s'écrit avec des parenthèses :\n[code]avancer()[/code]\nUn # commence un commentaire, ignoré par l'ordinateur. L'indentation (4 espaces) compte : elle indique ce qui appartient à un bloc.\n\n"
			if "boucle_while" in syn:
				t += "[b]Répéter : while[/b]\n[code]while True:\n    avancer()[/code]\nTrue signifie « vrai, toujours » : le bloc indenté se répète sans fin.\n\n"
			if "conditions" in syn:
				var cond := "regarder() == \"mur\""
				t += "[b]Décider : if / elif / else[/b]\n[code]if %s:\n    avancer()\nelse:\n    tourner(ouest)[/code]\nOn compare avec ==, !=, <, <=, >, >= et on combine avec and, or, not. elif signifie « sinon si ».\n\n" % cond
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
	world = World.new(lv, {}, 0)
	view.world = world
	view.alpha = 1.0
	view.queue_redraw()
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
	_refresh_toolbox()
	editor_panel.visible = true


func _close_editor() -> void:
	open_robot = ""
	editor_panel.visible = false


func _on_reset_code() -> void:
	if open_robot != "" and not running:
		_show_modal("reset_code")


func _do_reset_code() -> void:
	if open_robot != "" and editors.has(open_robot):
		editors[open_robot].text = levels[cur].code_initial
	_close_modal()


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
			# le jeu ne s'arrête pas : ce robot est simplement hors service (HS)
			_log("[color=tomato]%s — ligne %d : %s[/color]" % [_robot_name(id), res.line, _esc(res.msg)])
			_mark_line(id, res.line, ERROR_LINE)
			compiled[id] = null
		else:
			compiled[id] = res.code
	var list := _level_attacks()
	var attack: int
	var number: int
	run_replay = attack_choice >= 0 and attack_choice < list.size()
	if run_replay:
		attack = list[attack_choice]  # même numéro = exactement la même attaque
		number = attack_choice + 1
	else:
		attack = _new_attack_id()
		list.append(attack)
		number = list.size()
		_rebuild_attack_menu()
	world = World.new(lv, compiled, attack)
	view.world = world
	view.alpha = 1.0
	_set_running(true)
	timer = 0.0
	view.queue_redraw()


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
			if not rb.hs:
				_mark_line(rb.id, rb.vm.last_line)
	view.alpha = clampf(timer / interval, 0.0, 1.0) if running else 1.0
	view.queue_redraw()


## Échappe les crochets pour que le texte ne soit pas pris pour du BBCode.
func _esc(t: String) -> String:
	return t.replace("[", "[lb]")


func _drain_prints() -> void:
	for e in world.events:
		_log("[color=tomato]%s — ligne %d : %s[/color]" % [e.nom, e.line, _esc(str(e.msg))])
		_mark_line(e.id, e.line, ERROR_LINE)
	world.events.clear()
	for rb in world.robots:
		var vm = rb.vm
		for line in vm.printed:
			_log("[color=#9fd0ff]%s ›[/color] %s" % [rb.nom, _esc(str(line))])
		vm.printed.clear()


func _finish() -> void:
	_set_running(false)
	view.alpha = 1.0
	view.queue_redraw()
	var broken: Array = []
	for rb in world.robots:
		if rb.hs:
			broken.append(rb.nom)
	var info := {"text": world.message, "replay": run_replay, "next": false, "hs": ", ".join(broken)}
	if world.status == "victoire":
		info["title"] = "Victoire !"
		info["color"] = Color.LIGHT_GREEN
		if not run_replay:
			if cur + 1 == unlocked and unlocked < levels.size():
				unlocked += 1
				info["unlocked"] = unlocked
			info["next"] = cur + 1 < levels.size()
			_save_progress()
	else:
		info["title"] = "Échec"
		info["color"] = Color.ORANGE
	result_info = info
	_show_modal("resultat")


## Ajoute une ligne aux sorties. La fenêtre ne s'ouvre jamais toute seule : si elle est fermée,
## la pastille rouge du bouton « Sorties » compte les nouvelles lignes (erreurs comprises).
func _log(bb: String) -> void:
	console.append_text(bb + "\n")
	if not out_panel.visible:
		_count_out()


# ---------- surlignage de la ligne courante ----------

func _clear_marks() -> void:
	for id in marks:
		var e: CodeEdit = editors.get(id)
		if e != null and marks[id] >= 0 and marks[id] < e.get_line_count():
			e.set_line_background_color(marks[id], Color(0, 0, 0, 0))
	marks.clear()


func _mark_line(id: String, line_1based: int, color := Color(0.3, 0.5, 0.9, 0.25)) -> void:
	var e: CodeEdit = editors.get(id)
	if e == null:
		return
	if marks.has(id) and marks[id] >= 0 and marks[id] < e.get_line_count():
		e.set_line_background_color(marks[id], Color(0, 0, 0, 0))
	var i := line_1based - 1
	if i >= 0 and i < e.get_line_count():
		e.set_line_background_color(i, color)
		marks[id] = i
