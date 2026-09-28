extends SceneTree

## 规则层回归套件（常备）。
##
## 覆盖两组：
##   H. AI 使用计策牌：必须分派到 play_tactic。
##      【曾经的 bug】`MatchScreen._on_ai_timeout()` 无条件用 `play_card` 打 AI 选中的牌，
##      AI 一旦选中计策牌就会被 GameState 以「不是单位牌」拒绝 → 状态无变化 →
##      `changed` 不发射 → `_schedule_ai()` 不再启动定时器 → **AI 永久停手、整局卡死**。
##   I. 摧毁效果免疫英杰（白起 / 秦昭襄王）。
##      【曾经的 bug】`apply_power_change` 早就挡住了英杰的战力增减，但「摧毁」
##      是把卡从场上移除、根本不走战力那条路，所以英杰照样被白起除掉。
##
## 【设计原则】所有断言用 Side-effect（手牌 / 弃牌堆 / 场上归属）验证，
## 不依赖任何私有实现细节。

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _run() -> void:
	_watchdog()
	print("\n===== 规则层回归套件 =====")
	await _test_ai_tactic()
	_test_destroy_immune_hero()
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------- H. AI 使用计策牌 ----------------

func _test_ai_tactic() -> void:
	print("\n[H] AI 使用计策牌（曾经一用就卡死）")
	var db = load("res://scripts/CardDB.gd").new()
	var ms = load("res://scripts/MatchScreen.gd").new()
	ms.setup(db, CardData.FACTION_QIN, 20250920)
	root.add_child(ms)
	ms.name = "RULE_AI_MS"
	await process_frame
	await create_timer(0.2).timeout

	if ms.state == null:
		_ok(false, "MatchScreen 状态未建立")
		return
	var gs: GameState = ms.state

	# 推进到出牌阶段
	gs.execute_command(Command.mulligan(0, []))
	gs.execute_command(Command.mulligan(1, []))
	await process_frame
	_ok(gs.phase == GameState.Phase.PLAY, "已进入出牌阶段（phase=%d）" % gs.phase)

	# 把 AI（座位 1）手牌里的单位牌全部移走，只留计策
	var ai: PlayerState = gs.players[1]
	for c in ai.hand.duplicate():
		if c.card_type != CardData.TYPE_TACTIC:
			ai.hand.erase(c)
	# 万一手上没有计策，就从牌库补一张
	if ai.tactic_cards_in_hand().is_empty():
		for i in range(ai.deck.size()):
			if ai.deck[i].card_type == CardData.TYPE_TACTIC:
				ai.hand.append(ai.deck[i])
				ai.deck.remove_at(i)
				break
	_ok(not ai.tactic_cards_in_hand().is_empty(), "AI 手上有计策牌")
	_ok(ai.playable_cards().is_empty(),
		"AI 手上没有可出的单位牌（choose_card 会走计策分支）")

	# AI 的决策应落在一张计策上
	var picked: CardData = AIOpponent.choose_card(gs, 1)
	_ok(picked != null and picked.card_type == CardData.TYPE_TACTIC,
		"★ AI 选中了计策牌「%s」" % (picked.name if picked != null else "无"))

	# 设为 AI 回合并触发一次 AI 行动（停掉自动定时器，避免干扰断言）
	if ms._ai_timer != null:
		ms._ai_timer.stop()
	gs.active = 1
	var tactics_before := ai.tactic_cards_in_hand().size()
	var discard_before := ai.discard.size()
	var cmd_before := gs.command_count

	ms._on_ai_timeout()
	await process_frame

	_ok(gs.command_count > cmd_before,
		"★ AI 出计策后指令计数推进（%d → %d，不卡死）" % [cmd_before, gs.command_count])
	var hand_shrank := ai.tactic_cards_in_hand().size() < tactics_before
	var discard_grew := ai.discard.size() > discard_before
	_ok(hand_shrank or discard_grew,
		"★ AI 真的把计策打出去了（手牌 %d→%d，弃牌堆 %d→%d）" % [
			tactics_before, ai.tactic_cards_in_hand().size(),
			discard_before, ai.discard.size()])

	# 对照：AI 有单位可出时依旧走 play_card（不能被这次改动带偏）
	var unit: CardData = null
	for c in ai.deck:
		if c.card_type == CardData.TYPE_UNIT:
			unit = c
			break
	if unit != null:
		ai.deck.erase(unit)
		ai.hand.append(unit)
		var picked2: CardData = AIOpponent.choose_card(gs, 1)
		_ok(picked2 != null and picked2.card_type == CardData.TYPE_UNIT,
			"对照：AI 有单位牌时优先出单位（选中「%s」）" % (picked2.name if picked2 != null else "无"))

	ms.queue_free()
	await process_frame


# ---------------- I. 摧毁免疫英杰 ----------------

func _test_destroy_immune_hero() -> void:
	print("\n[I] 摧毁效果免疫英杰（白起 / 秦昭襄王）")
	var db = load("res://scripts/CardDB.gd").new()
	var gs: GameState = load("res://scripts/GameState.gd").new()
	gs.start_match(CardData.FACTION_QIN, null, null, 777)
	var res = load("res://scripts/EffectResolver.gd").new(gs)

	var foe: PlayerState = gs.players[1]
	var hero: CardData = db.get_hero_cards_by_faction(CardData.FACTION_QIN)[0].duplicate_card()
	var normal: CardData = db.get_normal_unit_cards_by_faction(
		CardData.FACTION_QIN)[0].duplicate_card()
	normal.power = 1

	_ok(hero.is_hero() and hero.card_type == CardData.TYPE_UNIT,
		"英杰卡 is_hero() = true（且 card_type 仍是 unit）")
	_ok(not normal.is_hero(), "普通单位 is_hero() = false")

	foe.place_unit(hero, hero.row)
	foe.place_unit(normal, normal.row)
	_ok(foe.effective_power(hero) > foe.effective_power(normal),
		"英杰战力(%d) > 普通单位(%d)，确保「最高」会先撞上英杰" % [
			foe.effective_power(hero), foe.effective_power(normal)])

	# 1) 单卡摧毁：直接被挡
	_ok(not res.destroy_card(foe, hero), "★ destroy_card 对英杰返回 false")
	_ok(foe.board_has(hero), "★ 英杰仍在场上")

	# 2) 白起：destroy_highest 应跳过英杰、改打普通单位
	var killed: Array = res.destroy_highest(foe)
	_ok(foe.board_has(hero), "★ 白起 destroy_highest 没有摧毁英杰")
	_ok(killed.size() == 1 and killed[0] == normal,
		"★ 被摧毁的是普通单位（本次摧毁 %d 张）" % killed.size())
	_ok(not foe.board_has(normal), "普通单位确实已离场")

	# 3) 场上只剩英杰：什么都不该摧毁
	foe.clear_board()
	foe.place_unit(hero, hero.row)
	var killed2: Array = res.destroy_highest(foe)
	_ok(killed2.is_empty() and foe.board_has(hero),
		"★ 场上只剩英杰时，摧毁最高不产生任何摧毁")

	# 4) 秦昭襄王：摧毁牌库 —— 牌库只剩英杰时必须拿不到目标
	var me: PlayerState = gs.players[0]
	var hero2: CardData = db.get_hero_cards_by_faction(CardData.FACTION_ZHAO)[0].duplicate_card()
	me.deck.clear()
	me.deck.append(hero2)
	var unit_filter := func(c: CardData) -> bool: return c.card_type == CardData.TYPE_UNIT
	var got = res.destroy_from_deck(me, unit_filter)
	_ok(got == null and me.deck.size() == 1,
		"★ 牌库只剩英杰时，摧毁牌库返回 null 且英杰留存")

	# 5) 牌库「英杰 + 5 张普通单位」，反复摧毁 5 次 —— 剩余的必须只有英杰
	me.deck.clear()
	me.deck.append(hero2)
	var zhao_normals: Array = db.get_normal_unit_cards_by_faction(CardData.FACTION_ZHAO)
	for i in range(5):
		me.deck.append(zhao_normals[i].duplicate_card())
	for _i in range(5):
		res.destroy_from_deck(me, unit_filter)
	_ok(me.deck.size() == 1 and me.deck[0].is_hero(),
		"★ 反复摧毁牌库 5 次后只剩英杰（实剩 %d 张）" % me.deck.size())

	# 6) 对照：普通单位仍可被正常摧毁（证明校验没有被放宽成「谁都摧毁不了」）
	foe.place_unit(normal, normal.row)
	_ok(res.destroy_card(foe, normal), "对照：普通单位可以被正常摧毁")
	_ok(not foe.board_has(normal), "对照：普通单位已离场")

	# 7) 对照：英杰依然免疫战力增减（原有保护没被改坏）
	_ok(not gs.apply_power_change(hero, -3, "测试"), "对照：英杰仍免疫战力增减")
