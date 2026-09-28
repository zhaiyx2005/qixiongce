extends RefCounted
class_name GameState

## 《七雄策》对局规则核心（纯逻辑，不依赖任何 UI / 场景）。
##
## 规则：
##   - 三局两胜 + 每人 2 座城池（输一局丢 1 座，平局双方各丢 1 座）
##   - 第一局抽 10 张可换 2 张；第二、三局各抽 2 张
##   - 第一局随机先手；之后上一局败者先手，平局随机
##   - 每回合打 1 张牌（单位 / 计策）或 Pass；双方 Pass（或无法行动）后比三行总战力
##   - 单位牌落三行（合法行由兵种推导）；计策牌不占行、打出即结算、结算后进弃牌堆
##   - 英杰战力固定不变，不受任何增减效果影响，但可被摧毁 / 收回 / 弃牌
##   - 局末场上单位进弃牌堆，手牌 / 牌库 / 弃牌堆跨局保留

signal changed
signal logged(text: String)
signal round_ended(summary: Dictionary)
signal match_ended(summary: Dictionary)

enum Phase { MULLIGAN, PLAY, ROUND_END, MATCH_END }

const GEMS_START := 2
const FIRST_ROUND_DRAW := 10
const LATER_ROUND_DRAW := 2
const MULLIGAN_LIMIT := 2
const MAX_ROUNDS := 3

const ROW_NAMES := {
	CardData.ROW_MELEE: "近战",
	CardData.ROW_RANGED: "远程",
	CardData.ROW_GARRISON: "守军",
}

var db: CardDB
var rng := RandomNumberGenerator.new()
## 本局随机种子。固定它即可复现整场对局（联机时由主机下发）。
## 0 表示「启动时随机化」。
var rng_seed: int = 0
var players: Array[PlayerState] = []

var phase: int = Phase.MULLIGAN
var round_number: int = 0
## 当前行动方在 players 中的下标（0 = 人类，1 = AI）
var active: int = 0
## 下一局先手
var next_starter: int = 0

var last_round_summary: Dictionary = {}
var match_summary: Dictionary = {}
## 本局换牌是否已完成
var mulligan_done: Array[bool] = [false, false]
## 本局换牌的处理顺序（先手方在前）。双方共用同一 rng，换牌内部要洗牌，
## 所以顺序必须是「先手方先换」，否则先手权与随机流顺序不一致会造成座位优势。
var mulligan_order: Array[int] = [0, 1]

## 效果执行器（4B 原子框架）
var runner: EffectRunner = null
var resolver: EffectResolver = null

## 本局内的战报（供 UI 与回归测试查看）
var battle_log: Array[String] = []

## 累计到当前局为止的「己方回合数」（老兵计数用，跨局重置）
var turn_counts: Array[int] = [0, 0]

## 已执行指令数（5E 乱序 / 重复包处理用）
var command_count: int = 0
## 最近一次被拒绝的原因（调试用）
var last_reject_reason: String = ""


## 该方累计回合数（当前局）。
func turn_count_of(player_index: int) -> int:
	if player_index < 0 or player_index >= turn_counts.size():
		return 0
	return turn_counts[player_index]


# ---------------- 指令入口（唯一对外操作接口） ----------------

## 执行一条指令。这是**对局唯一的对外操作入口**：
## 单机 UI、AI、联机客户端都走这里，保证规则校验只有一处口径。
##
## 返回 CommandResult（ok / 中文 reason / state_changed）。
func execute_command(cmd: Command) -> CommandResult:
	if cmd == null or not cmd.is_valid_type():
		return _reject("未知的指令类型。")

	command_count += 1

	match cmd.type:
		Command.CMD_MULLIGAN:
			return _exec_mulligan(cmd)
		Command.CMD_PLAY_CARD:
			return _exec_play_card(cmd)
		Command.CMD_PLAY_TACTIC:
			return _exec_play_tactic(cmd)
		Command.CMD_PASS:
			return _exec_pass(cmd)
		Command.CMD_ADVANCE_ROUND:
			return _exec_advance_round(cmd)
	return _reject("未知的指令类型。")


func _reject(reason: String) -> CommandResult:
	last_reject_reason = reason
	return CommandResult.fail(reason)


## 校验玩家下标，返回中文错误或空串。
func _check_player_index(player_index: int) -> String:
	if player_index < 0 or player_index >= players.size():
		return "玩家编号无效。"
	return ""


# ---------------- 指令实现 ----------------

func _exec_mulligan(cmd: Command) -> CommandResult:
	var bad := _check_player_index(cmd.player)
	if not bad.is_empty():
		return _reject(bad)
	if phase != Phase.MULLIGAN:
		return _reject("现在不是换牌阶段。")
	if mulligan_done[cmd.player]:
		return _reject("已经换过牌了。")
	if cmd.card_ids.size() > MULLIGAN_LIMIT:
		return _reject("最多只能换 %d 张牌。" % MULLIGAN_LIMIT)

	# 【为什么要按「已匹配下标」逐个消费】指令里传的是**卡牌 id 字符串**，
	# 而同一张卡（同名同数据）可以有多个独立实例，它们的 id 完全相同。
	# 若用 `_find_in_hand()`（恒返回第一个匹配）来解析，想换掉两张同名卡时
	# 两次都会解析到**同一个实例** → 被判「同一张牌不能换两次」而整条指令失败。
	# 正确做法：按 id 逐个挑「还没被本次占用过」的下一个实例。
	var cards: Array[CardData] = []
	var used_index: Array[int] = []
	var hand: Array = players[cmd.player].hand
	for card_id in cmd.card_ids:
		var found := -1
		for i in range(hand.size()):
			if used_index.has(i):
				continue
			var c: CardData = hand[i]
			if c.id == card_id:
				found = i
				break
		if found < 0:
			return _reject("「%s」不在你的手牌中。" % card_id)
		used_index.append(found)
		cards.append(hand[found])

	if not _do_mulligan(cmd.player, cards):
		return _reject("换牌失败。")
	return CommandResult.success(true)


func _exec_play_card(cmd: Command) -> CommandResult:
	var bad := _check_player_index(cmd.player)
	if not bad.is_empty():
		return _reject(bad)
	if phase != Phase.PLAY:
		return _reject("现在不是出牌阶段。")
	if cmd.player != active:
		return _reject("现在不是你的回合。")
	if players[cmd.player].passed:
		return _reject("你已经 Pass，本局不能继续出牌。")

	var card := _find_in_hand(cmd.player, cmd.card_id)
	if card == null:
		return _reject("「%s」不在你的手牌中。" % cmd.card_id)
	if card.card_type != CardData.TYPE_UNIT:
		return _reject("「%s」不是单位牌。" % card.name)

	var row := cmd.row
	if row.is_empty():
		row = card.row
	if not CardData.ROWS.has(row):
		return _reject("行「%s」不存在。" % row)
	if not card.can_place_in(row):
		return _reject("「%s」不能放在%s行。" % [card.name, row_name(row)])

	if not _do_play_card(cmd.player, card, cmd.insert_index, row):
		return _reject("出牌失败。")
	return CommandResult.success(true)


func _exec_play_tactic(cmd: Command) -> CommandResult:
	var bad := _check_player_index(cmd.player)
	if not bad.is_empty():
		return _reject(bad)
	if phase != Phase.PLAY:
		return _reject("现在不是出牌阶段。")
	if cmd.player != active:
		return _reject("现在不是你的回合。")
	if players[cmd.player].passed:
		return _reject("你已经 Pass，本局不能继续出牌。")

	var card := _find_in_hand(cmd.player, cmd.card_id)
	if card == null:
		return _reject("「%s」不在你的手牌中。" % cmd.card_id)
	if card.card_type != CardData.TYPE_TACTIC:
		return _reject("「%s」不是计策牌。" % card.name)

	if not _do_play_tactic(cmd.player, card):
		return _reject("计策结算失败。")
	return CommandResult.success(true)


func _exec_pass(cmd: Command) -> CommandResult:
	var bad := _check_player_index(cmd.player)
	if not bad.is_empty():
		return _reject(bad)
	if phase != Phase.PLAY:
		return _reject("现在不是出牌阶段。")
	if cmd.player != active:
		return _reject("现在不是你的回合。")
	if players[cmd.player].passed:
		return _reject("你已经 Pass 了。")

	if not _do_pass_turn(cmd.player):
		return _reject("Pass 失败。")
	return CommandResult.success(true)


func _exec_advance_round(cmd: Command) -> CommandResult:
	if phase != Phase.ROUND_END:
		return _reject("现在不是结算阶段。")
	_do_advance_after_round()
	return CommandResult.success(true)


## 在手牌里按 id 找卡（找不到返回 null）。
## 注意：同名牌可能有多个独立实例，这里返回第一个匹配。
func _find_in_hand(player_index: int, card_id: String) -> CardData:
	if player_index < 0 or player_index >= players.size():
		return null
	for card in players[player_index].hand:
		if card.id == card_id:
			return card
	return null


## 按 id 从任一方的手牌里找卡（联机时给「本地玩家」找牌用）。
func find_in_any_hand(card_id: String) -> CardData:
	for i in range(players.size()):
		var card := _find_in_hand(i, card_id)
		if card != null:
			return card
	return null


## 按 id 在指定玩家的所有区域里找卡（序列化反查用）。
func find_card_anywhere(player_index: int, card_id: String) -> CardData:
	if player_index < 0 or player_index >= players.size():
		return null
	for area in ["hand", "board", "deck", "discard", "leader"]:
		var card := find_card_by_id(player_index, card_id, area)
		if card != null:
			return card
	return null


## 在牌库 / 弃牌堆 / 战场里按 id 找卡（序列化反查用）。
func find_card_by_id(player_index: int, card_id: String, area: String = "hand") -> CardData:
	if player_index < 0 or player_index >= players.size():
		return null
	var p := players[player_index]
	match area:
		"hand":
			return _find_in_hand(player_index, card_id)
		"deck":
			for card in p.deck:
				if card.id == card_id:
					return card
		"discard":
			for card in p.discard:
				if card.id == card_id:
					return card
		"board":
			for row in CardData.ROWS:
				for card in p.row_cards(row):
					if card.id == card_id:
						return card
		"leader":
			if p.leader != null and p.leader.id == card_id:
				return p.leader
	return null


# ---------------- 开局 ----------------

## human_deck / ai_deck 传 null 则使用该阵营预设卡组。
## p_seed 传非 0 值则使用固定种子（可复现对局）；传 0 表示随机化。
## 开局。
##   p_ai_faction：显式指定对手阵营。
##     - 联机：由主机指派后传入（**必须传**，否则玩家阵营会和它的牌库对不上）
##     - 测试：指定对阵双方
##     - 单机：留空 → 从其余六国随机（随机源由 p_seed 派生，可复现）
func start_match(human_faction: String, human_deck: DeckList = null, ai_deck: DeckList = null,
		p_seed: int = 0, p_ai_faction: String = "") -> void:
	db = CardDB.new()
	_set_seed(p_seed)
	if not db.load_errors.is_empty():
		for err in db.load_errors:
			push_warning("[CardDB] " + err)

	# 对手阵营：七国之下「另一个阵营」不再唯一。
	#
	# 【为什么用独立派生的随机源】若直接借用对局主 rng，这一步会推进随机序列，
	# 于是「同一个种子」在本改动前后会发出完全不同的牌 —— 所有既有的
	# 种子复现（回归测试、平衡基线、玩家分享的种子）都会作废。
	# 用一个由 p_seed 派生的独立 RNG：既可复现，又完全不动牌序。
	var base_faction := human_faction
	if base_faction.is_empty():
		base_faction = CardData.FACTION_QIN
	var ai_faction := p_ai_faction
	if ai_faction.is_empty() or ai_faction == base_faction:
		var picker := RandomNumberGenerator.new()
		picker.seed = p_seed ^ 0x5F3A71C9
		ai_faction = CardData.random_other_faction(picker, base_faction)

	players.clear()
	players.append(PlayerState.new(human_faction, true))
	players.append(PlayerState.new(ai_faction, false))
	for p in players:
		p.gems = GEMS_START
		p.rounds_won = 0

	var decks: Array = [human_deck, ai_deck]
	for i in range(players.size()):
		var p := players[i]
		var deck: DeckList = decks[i]
		if deck == null:
			deck = DeckList.preset_for(p.faction, db)
		p.setup_deck(deck.build_cards(db))
		p.shuffle_deck(rng)

	round_number = 0
	last_round_summary = {}
	match_summary = {}
	mulligan_done = [false, false]
	mulligan_order = [0, 1]
	battle_log.clear()
	command_count = 0
	last_reject_reason = ""

	runner = EffectRunner.new(self)
	resolver = EffectResolver.new(self)

	logged.emit("对局开始：你使用「%s」，%s 使用「%s」。" % [
		_faction_name(players[0].faction), players[1].display_name, _faction_name(players[1].faction)
	])

	# 领袖「整场开局」能力：先手方先结算（先手拥有先手权，能力顺序对结果影响很小）
	for i in range(players.size()):
		var msg := runner.run_leader_match_start(i)
		if not msg.is_empty():
			logged.emit(msg)

	_begin_round(rng.randi_range(0, 1))


## 设置随机种子。传 0 则随机化（并把实际种子记下来，便于复现）。
func _set_seed(p_seed: int) -> void:
	if p_seed == 0:
		rng.randomize()
		rng_seed = rng.seed
	else:
		rng_seed = p_seed
		rng.seed = p_seed


func _begin_round(first_player: int) -> void:
	round_number += 1
	for p in players:
		p.passed = false
		p.clear_board()
		p.returned_before.clear()   # 曾进场标记每局重置
		p.row_aura.clear()

	# 领袖「每局开始」光环先就位，再抽牌（抽到手里的牌也带光环，进场上时结算）
	for i in range(players.size()):
		runner.setup_round_auras(i)

	var draw_count := LATER_ROUND_DRAW
	if round_number == 1:
		draw_count = FIRST_ROUND_DRAW
	for p in players:
		p.draw(draw_count)

	active = first_player
	next_starter = first_player
	mulligan_done = [false, false]
	turn_counts = [0, 0]
	phase = Phase.MULLIGAN if round_number == 1 else Phase.PLAY
	# 换牌顺序：先手方先换。
	# 【为什么必须这样】双方共用同一个 rng，而 `_do_mulligan` 内部会 `shuffle_deck(rng)`
	# 消耗随机数。若换牌顺序固定按座位 0→1（而先手方是随机的），座位 0 就总能拿到
	# 换牌洗牌的第一段随机流，形成与阵营无关的座位优势（实测镜像对局座位 0 胜率 ~70%）。
	mulligan_order = [first_player, 1 - first_player]

	# 每局开始领袖效果
	for i in range(players.size()):
		var msg := runner.run_leader_round_start(i)
		if not msg.is_empty():
			logged.emit(msg)

	if round_number == 1:
		logged.emit("第 1 局：双方各抽 %d 张，可换 %d 张，随机先手为 %s。" % [
			FIRST_ROUND_DRAW, MULLIGAN_LIMIT, players[active].display_name
		])
	else:
		logged.emit("第 %d 局开始：双方各抽 %d 张，%s 先手。" % [
			round_number, LATER_ROUND_DRAW, players[active].display_name
		])

	changed.emit()
	if phase == Phase.PLAY:
		_resolve_unable_to_act()


# ---------------- 换牌 ----------------

## 换牌：最多 MULLIGAN_LIMIT 张放回牌库，洗牌后抽等量。
## 【私有】外部一律通过 execute_command(Command.mulligan(...)) 调用。
func _do_mulligan(player_index: int, cards: Array[CardData]) -> bool:
	if phase != Phase.MULLIGAN:
		return false
	if player_index < 0 or player_index >= players.size():
		return false
	if mulligan_done[player_index]:
		return false
	if cards.size() > MULLIGAN_LIMIT:
		push_warning("换牌数量超过上限")
		return false

	var p := players[player_index]
	p.return_cards_to_deck(cards)
	p.shuffle_deck(rng)
	p.draw(cards.size())
	mulligan_done[player_index] = true

	if cards.is_empty():
		logged.emit("%s 不换牌。" % p.display_name)
	else:
		var names: PackedStringArray = PackedStringArray()
		for c in cards:
			names.append(c.name)
		logged.emit("%s 换掉 %d 张：%s" % [p.display_name, cards.size(), ", ".join(names)])

	_check_mulligan_finished()
	changed.emit()
	return true


func _check_mulligan_finished() -> void:
	if phase != Phase.MULLIGAN:
		return
	if not (mulligan_done[0] and mulligan_done[1]):
		return
	phase = Phase.PLAY
	logged.emit("换牌完成，%s 先手。" % players[active].display_name)
	_resolve_unable_to_act()


# ---------------- 行动 ----------------

## 单位牌：需要 target_row 在合法行内（空串时用卡面默认行）。
## 【私有】外部一律通过 execute_command(Command.play_card(...)) 调用。
func _do_play_card(player_index: int, card: CardData, index: int = -1, target_row: String = "") -> bool:
	if not _can_take_action(player_index):
		return false
	if card == null:
		return false
	if card.card_type == CardData.TYPE_TACTIC:
		return _do_play_tactic(player_index, card)
	if card.card_type != CardData.TYPE_UNIT:
		return false

	var p := players[player_index]
	var row := target_row
	if row.is_empty():
		row = card.row
	if not card.can_place_in(row):
		return false

	# 打出前的本行战力快照（奋勇 / 践踏 / 赵奢 需要）
	var pre_row := p.row_power(row)
	var pre_other := players[1 - player_index].row_power(row)

	if not p.play_to_board(card, index, row):
		return false

	# 行光环（秦惠文王 / 赵惠文王）
	var aura := int(p.row_aura.get(row, 0))
	if aura != 0:
		apply_power_change(card, aura, "行光环")

	# 蔺相如 / 完璧归赵 收回后再打出的永久 +1
	var returned_bonus := runner.apply_returned_bonus(player_index, card)

	logged.emit("%s 打出「%s」（%s %d），总战力 %d。" % [
		p.display_name, card.name, ROW_NAMES.get(row, row), p.effective_power(card), p.total_power()
	])
	if returned_bonus:
		logged.emit("「%s」再上场：永久 +1。" % card.name)

	var msg := runner.run_unit_on_play(player_index, card, row, pre_row, pre_other)
	if not msg.is_empty():
		logged.emit(msg)

	changed.emit()
	_advance_turn()
	return true


## 计策牌：不占行，打出即结算，结算后进弃牌堆。
## 【私有】外部一律通过 execute_command(Command.play_tactic(...)) 调用。
func _do_play_tactic(player_index: int, card: CardData) -> bool:
	if not _can_take_action(player_index):
		return false
	if card == null or card.card_type != CardData.TYPE_TACTIC:
		return false
	var p := players[player_index]
	if not p.hand.has(card):
		return false

	p.hand.erase(card)
	logged.emit("%s 使用计策「%s」。" % [p.display_name, card.name])
	var msg := runner.run_tactic(player_index, card)
	if not msg.is_empty():
		logged.emit("　" + msg)
	p.discard.append(card)

	changed.emit()
	_advance_turn()
	return true


## 【私有】外部一律通过 execute_command(Command.pass_turn(...)) 调用。
func _do_pass_turn(player_index: int) -> bool:
	if not _can_take_action(player_index):
		return false
	players[player_index].passed = true
	logged.emit("%s Pass（总战力 %d）。" % [players[player_index].display_name, players[player_index].total_power()])
	changed.emit()
	_advance_turn()
	return true


func can_act(player_index: int) -> bool:
	if phase != Phase.PLAY:
		return false
	if player_index != active:
		return false
	if players[player_index].passed:
		return false
	return not players[player_index].playable_any().is_empty()


func _can_take_action(player_index: int) -> bool:
	if phase != Phase.PLAY:
		return false
	if player_index != active:
		return false
	return not players[player_index].passed


## 一次行动结束后推进回合。
func _advance_turn() -> void:
	_continue_turn(true)


## 开局 / 换牌结束后检查先手方能否行动（不切换回合）。
func _resolve_unable_to_act() -> void:
	# 先手方回合开始（计数触发）
	turn_counts[active] += 1
	runner.run_counting_start_of_turn(active)
	_continue_turn(false)


## 回合推进：双方都 Pass 则结算本局；一方已 Pass 时另一方连续行动；
## 当前方无法行动则自动 Pass。
## rotate = true 表示先把行动权交给对方（一次行动之后）；
## rotate = false 表示停留在当前方身上做一次可行动性检查（局开始时）。
func _continue_turn(rotate: bool) -> void:
	while true:
		if players[0].passed and players[1].passed:
			_end_round()
			return
		if rotate:
			var other := 1 - active
			if not players[other].passed:
				active = other
				# 新行动方的回合开始（计数触发：老兵）
				turn_counts[active] += 1
				runner.run_counting_start_of_turn(active)
		rotate = true
		if not players[active].playable_any().is_empty():
			break
		players[active].passed = true
		logged.emit("%s 已无牌可出，自动 Pass。" % players[active].display_name)

	changed.emit()
	_check_round_end()


func _check_round_end() -> void:
	if phase != Phase.PLAY:
		return
	if players[0].passed and players[1].passed:
		_end_round()


# ---------------- 战力改动入口（唯一口径） ----------------

## 所有战力改动的唯一入口。
##   - 英杰：直接忽略（战力固定不变）
##   - 死志（immune_debuff）：忽略负 delta
##   - 卡不在任一方场上：忽略
## 返回是否真的生效。
func apply_power_change(card: CardData, delta: int, _reason: String = "") -> bool:
	if card == null or delta == 0:
		return false
	if card.is_hero():
		return false   # 英杰免疫一切战力增减
	var owner := owner_of(card)
	if owner == null:
		return false
	if delta < 0 and card.ability_id == "inf_deathwish":
		return false   # 死志：免疫战力减少
	owner.add_permanent(card, delta)
	return true


## 该卡当前在哪一方场上（不在场上返回 null）。
func owner_of(card: CardData) -> PlayerState:
	if card == null:
		return null
	for p in players:
		if p.board_has(card):
			return p
	return null


## 把卡恢复至卡面基础战力（清掉永久增益）。英杰无法被改动，返回 false。
func reset_to_base(card: CardData) -> bool:
	if card == null or card.is_hero():
		return false
	var owner := owner_of(card)
	if owner == null:
		return false
	if owner.permanent_of(card) == 0:
		return false
	owner.permanents.erase(card)
	return true


## 清除该卡所有负向永久增益（保留正向）。返回是否发生改动。
func clear_card_debuff(card: CardData) -> bool:
	if card == null or card.is_hero():
		return false
	var owner := owner_of(card)
	if owner == null:
		return false
	if owner.permanent_of(card) >= 0:
		return false
	owner.permanents.erase(card)
	return true


## 卡离场 / 进弃牌堆时清掉场上计数（永久增益保留到本局结束）。
func clear_card_state(card: CardData) -> void:
	for p in players:
		p.clear_on_board_state(card)


## 标记该卡「曾被收回手牌」（蔺相如 / 完璧归赵用）。
func mark_returned(card: CardData) -> void:
	for p in players:
		if p.hand.has(card):
			p.returned_before[card] = false
			return


## 单卡动态战力（含永久增益 + 动态能力）。不在场上返回其卡面基准值。
func effective_power(card: CardData, owner: PlayerState = null) -> int:
	if card == null:
		return 0
	if owner != null and owner.board_has(card):
		return owner.effective_power(card)
	var p := owner_of(card)
	if p != null:
		return p.effective_power(card)
	return card.power


func row_name(row: String) -> String:
	return ROW_NAMES.get(row, row)


# ---------------- 序列化（联机全量状态同步用） ----------------

## 把整场对局的可见状态打包成可传输的 Dictionary。
## 不含 db / runner / resolver（接收方自己重建）。
func serialize() -> Dictionary:
	var player_data: Array = []
	for p in players:
		player_data.append(p.serialize())

	return {
		"rng_seed": rng_seed,
		"phase": phase,
		"round_number": round_number,
		"active": active,
		"next_starter": next_starter,
		"mulligan_done": mulligan_done.duplicate(),
		"mulligan_order": mulligan_order.duplicate(),
		"turn_counts": turn_counts.duplicate(),
		"command_count": command_count,
		"players": player_data,
		"last_round_summary": last_round_summary.duplicate(true),
		"match_summary": match_summary.duplicate(true),
		"battle_log": battle_log.duplicate(),
	}


## 用序列化数据还原对局状态。
## 【注意】接收方必须用**与主机相同的种子与卡组**开局，否则卡牌实例对不上。
## 标准流程：先 start_match(faction, deck_a, deck_b, seed)，再 apply_state(...)。
func apply_state(data: Dictionary, db: CardDB) -> void:
	phase = int(data.get("phase", phase))
	round_number = int(data.get("round_number", round_number))
	active = int(data.get("active", active))
	next_starter = int(data.get("next_starter", next_starter))
	command_count = int(data.get("command_count", command_count))

	rng_seed = int(data.get("rng_seed", rng_seed))

	# 注意：不能直接赋值 [bool, bool] 字面量数组（会得到无类型的 Array），
	# 必须逐元素写入已声明类型的数组。
	var md: Variant = data.get("mulligan_done", [])
	if md is Array and md.size() >= mulligan_done.size():
		for i in range(mulligan_done.size()):
			mulligan_done[i] = bool(md[i])

	var mo: Variant = data.get("mulligan_order", [])
	if mo is Array and mo.size() >= mulligan_order.size():
		for i in range(mulligan_order.size()):
			mulligan_order[i] = int(mo[i])

	var tc: Variant = data.get("turn_counts", [])
	if tc is Array and tc.size() >= turn_counts.size():
		for i in range(turn_counts.size()):
			turn_counts[i] = int(tc[i])

	var pdata: Variant = data.get("players", [])
	if pdata is Array:
		for i in range(mini(players.size(), pdata.size())):
			players[i].deserialize(pdata[i], db)

	var lrs: Variant = data.get("last_round_summary", {})
	last_round_summary = lrs if lrs is Dictionary else {}

	var ms: Variant = data.get("match_summary", {})
	match_summary = ms if ms is Dictionary else {}

	var bl: Variant = data.get("battle_log", [])
	if bl is Array:
		battle_log.clear()
		for line in bl:
			battle_log.append(str(line))

	changed.emit()


# ---------------- 结算 ----------------

func _end_round() -> void:
	if phase != Phase.PLAY:
		return
	phase = Phase.ROUND_END

	var a := players[0]
	var b := players[1]
	var power_a := a.total_power()
	var power_b := b.total_power()
	# 三行明细必须在清场之前快照，否则结算弹窗会显示 0
	var row_power_snapshot := [
		[a.row_power(CardData.ROW_MELEE), a.row_power(CardData.ROW_RANGED), a.row_power(CardData.ROW_GARRISON)],
		[b.row_power(CardData.ROW_MELEE), b.row_power(CardData.ROW_RANGED), b.row_power(CardData.ROW_GARRISON)],
	]

	# winner: 0 / 1 / -1（平局）
	var winner := -1
	if power_a > power_b:
		winner = 0
	elif power_b > power_a:
		winner = 1

	var result_text := ""
	if winner == -1:
		a.gems -= 1
		b.gems -= 1
		result_text = "平局，双方各失 1 座城池。"
	else:
		var loser := 1 - winner
		players[loser].gems -= 1
		players[winner].rounds_won += 1
		result_text = "%s 赢下本局，%s 失 1 座城池。" % [players[winner].display_name, players[loser].display_name]

	# 下一局先手：败者先手；平局随机
	if winner == -1:
		next_starter = rng.randi_range(0, 1)
	else:
		next_starter = 1 - winner

	# 场上单位进弃牌堆
	for p in players:
		p.clear_board_to_discard()

	last_round_summary = {
		"round": round_number,
		"power": [power_a, power_b],
		"row_power": row_power_snapshot,
		"winner": winner,
		"gems": [a.gems, b.gems],
		"rounds_won": [a.rounds_won, b.rounds_won],
		"next_starter": next_starter,
		"text": result_text,
		"match_over": is_match_over(),
	}

	logged.emit("第 %d 局结束：%s %d : %d %s。%s" % [
		round_number, players[0].display_name, power_a, power_b, players[1].display_name, result_text
	])
	round_ended.emit(last_round_summary)
	changed.emit()


func is_match_over() -> bool:
	if players.size() < 2:
		return true
	if players[0].is_out_of_gems() or players[1].is_out_of_gems():
		return true
	return round_number >= MAX_ROUNDS


## 局末弹窗点“继续”后调用：要么开下一局，要么结束整场。
## 【私有】外部一律通过 execute_command(Command.advance_round()) 调用。
func _do_advance_after_round() -> void:
	if phase != Phase.ROUND_END:
		return
	if is_match_over():
		_finish_match()
	else:
		_begin_round(next_starter)


func _finish_match() -> void:
	phase = Phase.MATCH_END
	var a := players[0]
	var b := players[1]
	var winner := -1
	if a.gems > b.gems:
		winner = 0
	elif b.gems > a.gems:
		winner = 1
	elif a.rounds_won > b.rounds_won:
		winner = 0
	elif b.rounds_won > a.rounds_won:
		winner = 1

	var text := "平局，双方城池同时耗尽。" if winner == -1 else "%s 获得最终胜利！" % players[winner].display_name
	match_summary = {
		"winner": winner,
		"gems": [a.gems, b.gems],
		"rounds_won": [a.rounds_won, b.rounds_won],
		"text": text,
	}
	logged.emit("对局结束：" + text)
	match_ended.emit(match_summary)
	changed.emit()


# ---------------- 查询辅助 ----------------

func faction_name(player_index: int) -> String:
	return _faction_name(players[player_index].faction)


func _faction_name(faction: String) -> String:
	return CardData.faction_name_of(faction)


func turn_text() -> String:
	if phase == Phase.MULLIGAN:
		return "换牌阶段"
	if phase == Phase.ROUND_END:
		return "本局结算"
	if phase == Phase.MATCH_END:
		return "对局结束"
	var who := "你的回合" if players[active].is_human else "%s 的回合" % players[active].display_name
	return "第 %d 局 · %s" % [round_number, who]


func status_text() -> String:
	if phase == Phase.PLAY:
		var p := players[active]
		if players[1 - active].passed:
			return "%s 已 Pass，你可以继续出牌。" % players[1 - active].display_name
		return "%s 行动中。" % p.display_name
	return ""
