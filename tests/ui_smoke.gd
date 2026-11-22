extends SceneTree
## Test de fumée de l'interface :  godot --headless --path . -s tests/ui_smoke.gd

func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var fails := 0
	for i in main.levels.size():
		main.unlock_all.button_pressed = true
		main._select_level(i)
		await process_frame
		if not main.menu_panel.visible:
			print("ÉCHEC : le menu avec le scénario devrait se dérouler au début du niveau")
			fails += 1
		main._set_menu(false)
		# clic sur un robot -> son éditeur s'ouvre
		var rid: String = main.levels[i].robots[0].id
		main._open_editor(rid)
		if not main.editor_panel.visible or main.open_robot != rid:
			print("ÉCHEC : l'éditeur ne s'ouvre pas")
			fails += 1
		main.editors[rid].text = main.levels[i].solutions[rid]
		main.debug_check.button_pressed = true
		main.attack_edit.text = "7"
		main._on_run()
		var guard := 0
		while main.running and guard < 2000:
			main._process(0.1)
			guard += 1
		await process_frame
		var st: String = main.world.status
		print("niveau %d : %s (%s)" % [i + 1, st, main.world.message])
		if st != "victoire":
			fails += 1
	# mode débogage : la même attaque est rejouée à l'identique
	main._select_level(1)
	main._set_menu(false)
	main.debug_check.button_pressed = true
	main.editors["garde"].text = main.levels[1].solutions["garde"]
	main.attack_edit.text = "123"
	var traces: Array = []
	for r in 2:
		main._on_run()
		var w1 = main.world
		var g := 0
		while main.running and g < 2000:
			main._process(0.1)
			g += 1
		traces.append([w1.length, w1.tick_n, w1.status, w1.intruders.map(func(it): return it.dir)])
	print("rejeu identique : ", traces[0] == traces[1], " ", traces[0])
	if traces[0] != traces[1]:
		fails += 1
	# vrai clic de souris sur le robot dans l'entrepôt
	main._select_level(0)
	main._set_menu(false)
	main._close_editor()
	await process_frame
	var lay: Dictionary = main.view._layout()
	var pos: Vector2 = main.view._robot_center(lay, main.world.robots[0])
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	main.view._gui_input(ev)
	print("clic sur le robot -> éditeur ouvert : ", main.editor_panel.visible)
	if not main.editor_panel.visible:
		fails += 1
	# erreur de syntaxe : l'éditeur du robot fautif s'ouvre et la ligne est signalée
	main._select_level(0)
	main._set_menu(false)
	main._close_editor()
	main.editors["garde"].text = "if True:\n    avancer()\n"
	main._on_run()
	print("éditeur ouvert après erreur : ", main.editor_panel.visible)
	print("console : ", main.console.get_parsed_text().strip_edges().split("\n")[-1])
	if not main.editor_panel.visible:
		fails += 1
	quit(fails)
