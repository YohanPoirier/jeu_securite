extends Control
## Interface : éditeur de code, rail animé, console, choix du niveau, progression sauvegardée.

const Interp = preload("res://scripts/interpreter.gd")
const World = preload("res://scripts/world.gd")
const Gating = preload("res://scripts/gating.gd")
const RailView = preload("res://scripts/rail_view.gd")

const SAVE_PATH := "user://progression.cfg"

var levels: Array = []
var unlocked := 1
var cur := 0
var codes: Dictionary = {}
var world = null
var running := false
var timer := 0.0
var marked_line := -1

var level_select: OptionButton
var title_label: Label
var statement: RichTextLabel
var editor: CodeEdit
var view: Control
var console: RichTextLabel
var btn_run: Button
var btn_stop: Button
var speed_slider: HSlider
var speed_label: Label
var seed_edit: LineEdit
var unlock_all: CheckBox


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


# ---------- construction de l'interface ----------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	top.add_child(_label("Niveau :"))
	level_select = OptionButton.new()
	level_select.custom_minimum_size = Vector2(300, 0)
	level_select.item_selected.connect(_on_level_selected)
	top.add_child(level_select)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_label("Graine :"))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "aléatoire"
	seed_edit.custom_minimum_size = Vector2(110, 0)
	top.add_child(seed_edit)
	speed_label = _label("")
	top.add_child(speed_label)
	speed_slider = HSlider.new()
	speed_slider.min_value = 1
	speed_slider.max_value = 40
	speed_slider.step = 1
	speed_slider.value = 6
	speed_slider.custom_minimum_size = Vector2(140, 0)
	speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_slider.value_changed.connect(func(_v): _update_speed_label())
	top.add_child(speed_slider)
	unlock_all = CheckBox.new()
	unlock_all.text = "Tout débloquer"
	unlock_all.toggled.connect(func(_b): _refresh_level_items())
	top.add_child(unlock_all)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 80
	root.add_child(split)

	# --- colonne gauche : énoncé + éditeur ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	left.add_child(title_label)
	statement = RichTextLabel.new()
	statement.bbcode_enabled = true
	statement.fit_content = true
	statement.scroll_active = false
	left.add_child(statement)
	editor = CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.gutters_draw_line_numbers = true
	editor.indent_use_spaces = true
	editor.indent_size = 4
	editor.indent_automatic = true
	editor.auto_brace_completion_enabled = true
	editor.highlight_current_line = true
	editor.add_theme_font_size_override("font_size", 16)
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
	editor.syntax_highlighter = hl
	left.add_child(editor)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	btn_run = Button.new()
	btn_run.text = "▶ Lancer"
	btn_run.pressed.connect(_on_run)
	buttons.add_child(btn_run)
	btn_stop = Button.new()
	btn_stop.text = "■ Arrêter"
	btn_stop.pressed.connect(_on_stop)
	buttons.add_child(btn_stop)
	var btn_reset := Button.new()
	btn_reset.text = "↺ Code de départ"
	btn_reset.pressed.connect(_on_reset_code)
	buttons.add_child(btn_reset)

	# --- colonne droite : rail + console ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(480, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	view = RailView.new()
	view.custom_minimum_size = Vector2(0, 240)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(view)
	console = RichTextLabel.new()
	console.bbcode_enabled = true
	console.scroll_following = true
	console.custom_minimum_size = Vector2(0, 170)
	right.add_child(console)

	_update_speed_label()
	_refresh_level_items()


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _update_speed_label() -> void:
	speed_label.text = "Vitesse : %d ticks/s" % int(speed_slider.value)


func _refresh_level_items() -> void:
	var keep := cur
	level_select.clear()
	for i in levels.size():
		level_select.add_item("%d. %s" % [i + 1, levels[i].titre])
		level_select.set_item_disabled(i, i >= unlocked and not unlock_all.button_pressed)
	level_select.select(keep)


# ---------- niveaux ----------

func _on_level_selected(idx: int) -> void:
	_select_level(idx)


func _select_level(idx: int) -> void:
	if levels.is_empty():
		return
	if cur < levels.size() and editor.text != "":
		codes[levels[cur].id] = editor.text
	cur = idx
	_stop()
	var lv: Dictionary = levels[cur]
	level_select.select(cur)
	title_label.text = "Niveau %d — %s" % [cur + 1, lv.titre]
	statement.text = _statement_text(lv)
	editor.text = codes.get(lv.id, lv.code_initial)
	_clear_mark()
	console.clear()
	_log("[color=gray]Écris ton programme, puis clique sur « Lancer ». La graine est affichée pour pouvoir rejouer le même scénario.[/color]")
	world = null
	view.world = null
	var l = lv.longueur
	view.level_len = int(l[0]) if l is Array else int(l)
	view.queue_redraw()


func _statement_text(lv: Dictionary) -> String:
	var t := String(lv.enonce) + "\n\n[b]Fonctions du robot[/b]\n"
	for f in lv.api:
		t += "• " + World.API_DOC[f] + "\n"
	for b in lv.get("builtins", []):
		if b == "print":
			t += "• print(...) : affiche dans la console\n"
		elif b == "range":
			t += "• range(n) : à utiliser avec for\n"
	return t


# ---------- exécution ----------

func _on_run() -> void:
	var lv: Dictionary = levels[cur]
	codes[lv.id] = editor.text
	_save_progress()
	_clear_mark()
	var res := Interp.compile(editor.text, lv.get("syntaxe", []), lv.get("api", []), lv.get("builtins", []))
	if not res.ok:
		_log("[color=tomato]Ligne %d : %s[/color]" % [res.line, res.msg])
		_mark_line(res.line)
		return
	var s := 0
	var txt := seed_edit.text.strip_edges()
	if txt.is_valid_int():
		s = txt.to_int()
	else:
		s = randi() % 1000000
	console.clear()
	_log("[color=gray]Lancement — graine %d[/color]" % s)
	world = World.new(lv, res.code, s)
	view.world = world
	view.alpha = 1.0
	running = true
	timer = 0.0
	view.queue_redraw()


func _on_stop() -> void:
	_stop()
	_log("[color=gray]Arrêté.[/color]")


func _stop() -> void:
	running = false
	_clear_mark()


func _on_reset_code() -> void:
	editor.text = levels[cur].code_initial


func _process(delta: float) -> void:
	if not running or world == null:
		return
	var interval := 1.0 / speed_slider.value
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
		_mark_line(world.robot.vm.last_line)
	view.alpha = clampf(timer / interval, 0.0, 1.0) if running else 1.0
	view.queue_redraw()


func _drain_prints() -> void:
	var vm = world.robot.vm
	for line in vm.printed:
		_log("[color=#9fd0ff]> %s[/color]" % str(line).replace("[", "[lb]"))
	vm.printed.clear()


func _finish() -> void:
	running = false
	view.alpha = 1.0
	view.queue_redraw()
	match world.status:
		"victoire":
			_log("[color=lightgreen][b]Victoire ![/b] %s[/color]" % world.message)
			if cur + 1 == unlocked and unlocked < levels.size():
				unlocked += 1
				_log("[color=lightgreen]Niveau %d débloqué.[/color]" % unlocked)
				_refresh_level_items()
			_save_progress()
		"defaite":
			_log("[color=orange]Échec : %s[/color] [color=gray](graine %d)[/color]" % [world.message, world.seed_used])
		"erreur":
			_log("[color=tomato]%s[/color]" % world.message)
			_mark_line(world.robot.vm.error.line)


func _log(bb: String) -> void:
	console.append_text(bb + "\n")


# ---------- surlignage de la ligne courante ----------

func _clear_mark() -> void:
	if marked_line >= 0 and marked_line < editor.get_line_count():
		editor.set_line_background_color(marked_line, Color(0, 0, 0, 0))
	marked_line = -1


func _mark_line(line_1based: int) -> void:
	_clear_mark()
	var i := line_1based - 1
	if i >= 0 and i < editor.get_line_count():
		editor.set_line_background_color(i, Color(0.3, 0.5, 0.9, 0.25))
		marked_line = i
