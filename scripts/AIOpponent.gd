extends RefCounted
class_name AIOpponent

## 简单 AI（4F 升级版 · 保守）
##
## 改动相对上一版（第三阶段）只有两点，且都保持「双方完全对称」：
##   1. 战力评估统一走 `effective_power` / 行光环，而不是裸 `card.power`
##   2. 支持计策牌：**只在没有可出的单位牌时才出计策**，
##      避免打乱原有的出牌节奏（曾因激进的计策评估导致先后手胜负严重失衡）
##
## 玩家【未 Pass】时：
##   1. 没有可出的牌 -> Pass
##   2. 总战力落后 且 手牌数 <= KEEP_CARD_HAND -> Pass（留牌）
##   3. 否则出手中战力最高的合法单位牌
##
## 玩家【已 Pass】时按战力差决定：
##   1. 领先 >= LEAD_THRESHOLD -> Pass（收手留牌）
##   2. 平手或小幅领先 -> 出最小合法牌
##   3. 落后 -> 出「能反超的最小合法牌」；反超不了 -> Pass 保留手牌
##
## 换牌策略：优先换掉战力最低的单位牌（计策保留）。

## 领先多少战力就收手（可调参：若 AI 过于保守可降到 5 或 0）
const LEAD_THRESHOLD := 10
## 落后且手牌数不超过此值时 Pass 留牌
const KEEP_CARD_HAND := 2


static func choose_card(state: GameState, player_index: int) -> CardData:
	var me := state.players[player_index]
	var opp := state.players[1 - player_index]

	var playable := me.playable_cards()
	# 没有单位可出：只能出计策（计策打出即结算，总能出）
	if playable.is_empty():
		return _first_tactic(me)

	if not opp.passed:
		if me.total_power() < opp.total_power() and me.hand.size() <= KEEP_CARD_HAND:
			return null
		return _strongest(state, player_index, playable)

	var diff := me.total_power() - opp.total_power()
	if diff >= LEAD_THRESHOLD:
		return null
	if diff >= 0:
		return _weakest(state, player_index, playable)
	# 落后：出能反超的最小牌，反超不了就 Pass 保牌
	var catch_up := _smallest_to_overtake(state, player_index, playable, -diff)
	if catch_up != null:
		return catch_up
	return null


# ---------------- 单位评估 ----------------

## 手上单位牌的预期战力 = 卡面战力 + 落场行光环。
## 已在场上的卡走 effective_power（含永久增益与动态能力）。
static func _effective(state: GameState, pi: int, card: CardData) -> int:
	if card == null:
		return 0
	var owner := state.players[pi]
	if owner.board_has(card):
		return owner.effective_power(card)
	return card.power + int(owner.row_aura.get(card.row, 0))


static func _strongest(state: GameState, pi: int, units: Array) -> CardData:
	var best: CardData = null
	var best_v := -99999
	for card in units:
		var v := _effective(state, pi, card)
		if v > best_v:
			best_v = v
			best = card
	return best


static func _weakest(state: GameState, pi: int, units: Array) -> CardData:
	var best: CardData = null
	var best_v := 99999
	for card in units:
		var v := _effective(state, pi, card)
		if v < best_v:
			best_v = v
			best = card
	return best


## 满足「我方总战力 + power > 对手总战力」的最小单位；不存在返回 null
static func _smallest_to_overtake(state: GameState, pi: int, units: Array, deficit: int) -> CardData:
	var best: CardData = null
	var best_v := 99999
	for card in units:
		var v := _effective(state, pi, card)
		if v <= deficit:
			continue
		if v < best_v:
			best_v = v
			best = card
	return best


## 没有单位可出时，取第一张计策（顺序稳定，双方对称）。
static func _first_tactic(me: PlayerState) -> CardData:
	var tactics := me.tactic_cards_in_hand()
	if tactics.is_empty():
		return null
	return tactics[0]


# ---------------- 换牌 ----------------

## 换牌策略：换掉战力最低的 2 张单位牌（与玩家对称）。
static func choose_mulligan(state: GameState, player_index: int) -> Array[CardData]:
	var me := state.players[player_index]
	var sorted := me.unit_cards_in_hand()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.power != b.power:
			return a.power < b.power
		return a.id < b.id)
	var out: Array[CardData] = []
	for i in range(min(GameState.MULLIGAN_LIMIT, sorted.size())):
		out.append(sorted[i])
	return out
