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
		main.editor.text = main.levels[i].solution
		main.seed_edit.text = "7"
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
	# erreur de syntaxe affichée
	main._select_level(0)
	main.editor.text = "if True:\n    avancer()\n"
	main._on_run()
	print("console après erreur : ", main.console.get_parsed_text().strip_edges().split("\n")[-1])
	quit(fails)
