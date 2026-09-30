extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://preview/" + file + ".png")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.apply_theme(host)
	root.add_child(host)
	var menu := MainMenuScreen.new()
	host.add_child(menu)
	await capture("polish-menu")
	menu.queue_free()
	await process_frame
	var factions := FactionSelectScreen.new()
	factions.setup(CardDB.new())
	host.add_child(factions)
	await capture("polish-factions")
	factions.queue_free()
	await process_frame
	var match_view := MatchScreen.new()
	match_view.setup(CardDB.new(), "qin", 20260929)
	host.add_child(match_view)
	await process_frame
	match_view._mulligan_screen.visible = false
	match_view._ai_timer.stop()
	match_view.state.phase = GameState.Phase.PLAY
	match_view.state.active = 0
	match_view.state.players[1].faction = "zhao"
	match_view.state.players[0].clear_board()
	match_view.state.players[1].clear_board()
	for i in range(2):
		var faction := "qin" if i == 0 else "zhao"
		for n in [1, 3, 4, 5, 16, 17, 24]:
			var card := match_view.db.get_card_by_id("%s_%03d" % [faction, n]).duplicate_card()
			match_view.state.players[i].place_unit(card, card.row)
	match_view._refresh()
	await create_timer(0.1).timeout
	var p := match_view.state.players[0]
	for card in p.row_cards("melee"):
		match_view.state.apply_power_change(card, 2)
	for card in match_view.state.players[1].row_cards("melee"):
		match_view.state.apply_power_change(card, -2)
	match_view._refresh()
	await create_timer(0.4).timeout
	await capture("polish-match")
	quit()
