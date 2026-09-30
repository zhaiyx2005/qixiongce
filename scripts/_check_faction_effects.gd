extends SceneTree

var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[%s] %s" % ["OK" if ok else "FAIL", message])

func unit(kind: String = "infantry", ability: String = "") -> CardData:
	var card := CardData.new()
	card.id = "qin_001"
	card.name = "测试单位"
	card.faction = "qin"
	card.power = 5
	card.unit_type = kind
	card.ability_id = ability
	card.row = "melee"
	return card

func fixture() -> GameState:
	var state := GameState.new()
	state.players = [PlayerState.new("qin"), PlayerState.new("han")]
	for p in state.players:
		for row in CardData.ROWS:
			for i in range(3):
				p.place_unit(unit("archer" if row == "ranged" else "infantry"), row)
		var hero := unit("hero")
		hero.power = 50
		p.place_unit(hero, "garrison")
		p.place_unit(unit("cavalry"), "melee")
		p.deck.append(unit())
	return state

func run() -> void:
	var db := CardDB.new()
	for f in CardData.FACTIONS:
		var count := 0
		for card in db.get_cards_by_faction(f):
			check(not Abilities.def(card.ability_id).is_empty(), "%s 能力已注册" % card.name)
			if FactionEffects.UNITS.has(card.ability_id):
				count += 1
		check(count > 0, "%s 有特色兵种" % f)
	var expected := {"tac_yuanjiao": -3, "tac_jungong": 6, "tac_qi_weiwei": -4,
		"tac_qi_zunwang": 6, "tac_chu_wending": -6, "tac_chu_bilu": 6, "tac_chu_baiyue": 3,
		"tac_yan_xiaqi": -4, "tac_yan_kuhan": 6, "tac_han_jinnu": -4,
		"tac_han_yiyang": 6, "tac_yuyu": -4, "tac_jiangxiang": 6,
		"tac_wei_wuzuzhi": 4, "tac_wei_wuzu": 3, "tac_wei_wuqilianbing": 6}
	for id in expected:
		var state := fixture()
		var pi := 1 if int(expected[id]) < 0 else 0
		var before := state.players[pi].total_power()
		FactionEffects.run_tactic(state, 0, id)
		check(state.players[pi].total_power() - before == expected[id], "%s 限定目标与数值正确" % id)
		check(state.players[pi].row_cards("garrison")[3].power == 50, "英杰基础值不变")
		check(state.players[pi].effective_power(state.players[pi].row_cards("garrison")[3]) == 50, "英杰免疫")
		if id == "tac_wei_wuzu":
			check(state.players[0].hand.size() == 1 and state.players[0].deck.is_empty(), "选练只抽一张真实牌库卡")
		state.players[0].clear_board()
		state.players[1].clear_board()
		FactionEffects.run_tactic(state, 0, id)
		check(state.players[0].total_power() == 0 and state.players[1].total_power() == 0, "空场安全")
	for id in FactionEffects.UNITS:
		var p := PlayerState.new()
		var kind := "archer" if id == "han_crossbow" else ("cavalry" if id == "zhao_mobile" else "infantry")
		var c := unit(kind, id)
		p.place_unit(c, "garrison" if id == "yan_frontier" else "melee")
		var alone := p.effective_power(c)
		check(alone == (7 if id == "yan_frontier" else (6 if id == "han_crossbow" else 5)), "%s 单卡条件" % id)
		p.place_unit(unit(), p.row_of(c))
		p.place_unit(unit("archer"), p.row_of(c))
		p.place_unit(unit("cavalry"), "ranged")
		p.add_permanent(c, 1 if id == "qin_merit" else 0)
		var value := p.effective_power(c)
		check(value == (8 if id == "qin_merit" else (6 if id == "wei_drill" else 7)), "%s 联动条件" % id)
		p.clear_board()
		check(p.permanents.is_empty(), "换局清空增益")
	# 死志不能被新伤害绕过；并列最高只按上限取目标。
	var state := fixture()
	var protected := state.players[1].row_cards("melee")[0]
	protected.ability_id = "inf_deathwish"
	protected.power = 40
	FactionEffects.run_tactic(state, 0, "tac_yuanjiao")
	check(state.players[1].effective_power(protected) == 40, "军略伤害遵守死志免疫")
	await check_feedback(db)
	print("TOTAL %d / FAIL %d" % [checks, failures])
	quit(1 if failures else 0)

func check_feedback(db: CardDB) -> void:
	var p := PlayerState.new("qin")
	var c := db.get_card_by_id("qin_001").duplicate_card()
	var duplicate := c.duplicate_card()
	p.setup_deck([c, duplicate])
	p.deck.clear()
	p.place_unit(c, "melee")
	p.place_unit(duplicate, "melee")
	check(c.instance_key != duplicate.instance_key, "同名副本有独立身份")
	var row := RowView.new()
	row.setup("melee")
	root.add_child(row)
	row.refresh(p.row_cards("melee"), 10, [5, 5])
	await process_frame
	var view: CardView = row._cards_box.get_child(0)
	var base_children := view.get_child_count()
	row.refresh(p.row_cards("melee"), 12, [7, 5])
	check(row._cards_box.get_child(0) == view, "刷新保留卡牌控件")
	check(view.get_child_count() == base_children + 1, "增益飘字产生")
	var fresh := PlayerState.new("qin")
	fresh.deserialize(p.serialize(), db)
	row.refresh(fresh.row_cards("melee"), 11, [6, 5])
	check(row._cards_box.get_child(0) == view, "联机快照保留同一动画控件")
	check(view.data == fresh.row_cards("melee")[0], "快照更新右键详情引用")
	check(view.get_child_count() == base_children + 2, "连续减益与增益分别保留")
	row.refresh(fresh.row_cards("melee"), 11, [6, 5])
	check(view.get_child_count() == base_children + 2, "相同数值不重复产生飘字")
	await create_timer(0.5).timeout
	check(view._panel.position.is_equal_approx(Vector2.ZERO), "震动结束复位")
	check(view.get_child_count() == base_children + 2, "飘字停留可读")
	await create_timer(1.9).timeout
	check(view.get_child_count() == base_children, "飘字到时回收")
	row.queue_free()
	await process_frame
