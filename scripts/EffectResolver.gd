extends RefCounted
class_name EffectResolver

## 《七雄策》能力效果的原子操作框架。
##
## 设计原则：
##   1. 所有能力效果 = 一组原子操作的组合，能力本身不含循环 / 条件分支的复制品。
##   2. 原子操作只通过 GameState 提供的接口改动状态，保证「动态战力」口径唯一。
##   3. 每个原子操作都返回受影响卡牌数组，便于战报文案与断言。

var _state_ref: WeakRef
var state: GameState:
	get:
		return _state_ref.get_ref() as GameState
	set(value):
		_state_ref = weakref(value)


func _init(p_state: GameState) -> void:
	state = p_state


# ---------------- 单卡 ----------------

func change_power(card: CardData, delta: int, reason: String = "") -> bool:
	return state.apply_power_change(card, delta, reason)


func buff_card(card: CardData, delta: int, reason: String = "") -> bool:
	if delta <= 0:
		return false
	return state.apply_power_change(card, delta, reason)


func damage_card(card: CardData, delta: int, reason: String = "") -> bool:
	if delta <= 0:
		return false
	return state.apply_power_change(card, -delta, reason)


# ---------------- 批量：行 / 全场 ----------------

func change_row(owner: PlayerState, row: String, delta: int, reason: String = "") -> Array[CardData]:
	var affected: Array[CardData] = []
	for card in owner.row_cards(row):
		if state.apply_power_change(card, delta, reason):
			affected.append(card)
	return affected


func buff_row(owner: PlayerState, row: String, delta: int, reason: String = "") -> Array[CardData]:
	if delta <= 0:
		return []
	return change_row(owner, row, delta, reason)


func damage_row(owner: PlayerState, row: String, delta: int, reason: String = "") -> Array[CardData]:
	if delta <= 0:
		return []
	return change_row(owner, row, -delta, reason)


## 某方场上所有单位改战力（跨三行）。
func change_all(owner: PlayerState, delta: int, reason: String = "") -> Array[CardData]:
	var affected: Array[CardData] = []
	for row in CardData.ROWS:
		affected.append_array(change_row(owner, row, delta, reason))
	return affected


func buff_all(owner: PlayerState, delta: int, reason: String = "") -> Array[CardData]:
	if delta <= 0:
		return []
	return change_all(owner, delta, reason)


func damage_all(owner: PlayerState, delta: int, reason: String = "") -> Array[CardData]:
	if delta <= 0:
		return []
	return change_all(owner, delta, reason)


# ---------------- 挑选目标 ----------------

## 某方场上所有单位（三行拼接）。
func all_units(owner: PlayerState) -> Array[CardData]:
	var out: Array[CardData] = []
	for row in CardData.ROWS:
		out.append_array(owner.row_cards(row))
	return out


## 某方场上战力最高 / 最低的所有单位（并列全选）。空场返回空数组。
func pick_extreme(owner: PlayerState, want_highest: bool) -> Array[CardData]:
	var units := all_units(owner)
	if units.is_empty():
		return []
	var best := owner.effective_power(units[0])
	for card in units:
		var p := owner.effective_power(card)
		if (want_highest and p > best) or (not want_highest and p < best):
			best = p
	var out: Array[CardData] = []
	for card in units:
		if owner.effective_power(card) == best:
			out.append(card)
	return out


func pick_highest(owner: PlayerState) -> Array[CardData]:
	return pick_extreme(owner, true)


func pick_lowest(owner: PlayerState) -> Array[CardData]:
	return pick_extreme(owner, false)


## 卡片当前所在的行（不在场上返回空串）。
func row_of(owner: PlayerState, card: CardData) -> String:
	return owner.row_of(card)


## 某行 / 某方的总战力（动态）。
func row_power(owner: PlayerState, row: String) -> int:
	return owner.row_power(row)


func total_power(owner: PlayerState) -> int:
	return owner.total_power()


## 某方场上单位总数。
func unit_count(owner: PlayerState) -> int:
	return all_units(owner).size()


## 某方场上某兵种数量。
func count_unit_type(owner: PlayerState, unit_type: String) -> int:
	var n := 0
	for card in all_units(owner):
		if card.unit_type == unit_type:
			n += 1
	return n


## 某行某兵种数量。
func count_unit_type_in_row(owner: PlayerState, row: String, unit_type: String) -> int:
	var n := 0
	for card in owner.row_cards(row):
		if card.unit_type == unit_type:
			n += 1
	return n


## 某方战力最高的行名（并列取行顺序靠前者：近战 → 远程 → 守军）。空场返回空串。
func strongest_row(owner: PlayerState) -> String:
	var best_row := ""
	var best := -1
	for row in CardData.ROWS:
		if owner.row_cards(row).is_empty():
			continue
		var p := owner.row_power(row)
		if p > best:
			best = p
			best_row = row
	return best_row


# ---------------- 结构性操作 ----------------

## 从牌库召唤单位到指定行。filter 为 Callable(card)->bool，null 表示任意单位卡。
func summon_from_deck(owner: PlayerState, row: String, filter: Variant = null) -> CardData:
	var picked: CardData = null
	var picked_idx := -1
	for i in range(owner.deck.size()):
		var card: CardData = owner.deck[i]
		if card.card_type != CardData.TYPE_UNIT:
			continue
		if not card.can_place_in(row):
			continue
		if filter != null and not (filter as Callable).call(card):
			continue
		if picked == null or card.power > picked.power:
			picked = card
			picked_idx = i
	if picked == null:
		return null
	owner.deck.remove_at(picked_idx)
	owner.place_unit(picked, row)
	return picked


## 从牌库取一张符合条件的牌加入手牌。
func fetch_to_hand(owner: PlayerState, filter: Variant = null) -> CardData:
	for i in range(owner.deck.size()):
		var card: CardData = owner.deck[i]
		if filter != null and not (filter as Callable).call(card):
			continue
		owner.deck.remove_at(i)
		owner.hand.append(card)
		return card
	return null


## 摧毁对方牌库中随机一张符合条件的牌（进弃牌堆）。
##
## 【英杰免疫】牌库里的英杰同样不可摧毁（秦昭襄王 / leader_qinzhaoxiang
## 传进来的 filter 只判了 `card_type == unit`，英杰的 card_type 也是 unit，
## 所以过滤必须在这里内置，不能依赖调用方）。
func destroy_from_deck(owner: PlayerState, filter: Variant = null) -> CardData:
	var candidates: Array[int] = []
	for i in range(owner.deck.size()):
		var card: CardData = owner.deck[i]
		if card.is_hero():
			continue   # 英杰免疫一切摧毁效果
		if filter != null and not (filter as Callable).call(card):
			continue
		candidates.append(i)
	if candidates.is_empty():
		return null
	var pick: int = candidates[state.rng.randi_range(0, candidates.size() - 1)]
	var card: CardData = owner.deck[pick]
	owner.deck.remove_at(pick)
	owner.discard.append(card)
	return card


func draw_cards(owner: PlayerState, count: int) -> Array[CardData]:
	return owner.draw(count)


## 弃掉手牌中指定卡（进弃牌堆）。
func discard_from_hand(owner: PlayerState, card: CardData) -> bool:
	var idx := owner.hand.find(card)
	if idx < 0:
		return false
	owner.hand.remove_at(idx)
	owner.discard.append(card)
	return true


## 收回己方场上最低战力单位到手上。
func return_lowest_to_hand(owner: PlayerState) -> CardData:
	var picks := pick_lowest(owner)
	if picks.is_empty():
		return null
	var card: CardData = picks[0]
	var row := owner.row_of(card)
	if row.is_empty():
		return null
	owner.remove_from_row(card, row)
	owner.hand.append(card)
	state.mark_returned(card)
	return card


func return_card_to_hand(owner: PlayerState, card: CardData) -> bool:
	var row := owner.row_of(card)
	if row.is_empty():
		return false
	owner.remove_from_row(card, row)
	owner.hand.append(card)
	state.mark_returned(card)
	return true


## 摧毁场上单卡（进弃牌堆）。
##
## 【英杰免疫 —— 最后一道防线】这是所有「场上摧毁」的公共出口，
## 必须在这里挡住英杰，而不是指望每个调用方自己过滤。
## 历史上白起就是因为绕过了这层检查，把对方的英杰一起除掉了。
func destroy_card(owner: PlayerState, card: CardData) -> bool:
	if card == null or card.is_hero():
		return false   # 英杰免疫一切摧毁效果
	var row := owner.row_of(card)
	if row.is_empty():
		return false
	owner.remove_from_row(card, row)
	owner.discard.append(card)
	state.clear_card_state(card)
	return true


## 摧毁某方场上战力最高的所有单位（并列全毁）。
##
## 【英杰免疫】只在「可摧毁单位」（非英杰）里挑最高。
## 若直接用 pick_highest()，对方场上战力最高的若是英杰就会被一起摧毁 ——
## 这是白起（hero_baiqi）实测出的 bug。英杰按设计免疫一切摧毁效果，
## 所以这里要挑的是「非英杰里战力最高的」，而不是「全场最高」。
func destroy_highest(owner: PlayerState) -> Array[CardData]:
	var picks := pick_extreme_destroyable(owner, true)
	var done: Array[CardData] = []
	for card in picks:
		if destroy_card(owner, card):
			done.append(card)
	return done


# ---------------- 可摧毁单位（英杰除外） ----------------

## 某方场上**可被摧毁**的单位：排除英杰。
##
## 【为什么需要单独一个口径】英杰免疫一切摧毁效果（`apply_power_change`
## 早就挡住了战力增减，但摧毁是把卡从场上移除、根本不走战力那条路，
## 所以必须在这里显式挡）。所有摧毁类原子操作都要经过这里，
## 不要在调用方各自过滤 —— 那样漏一处就是一个 bug。
func destroyable_units(owner: PlayerState) -> Array[CardData]:
	var out: Array[CardData] = []
	for card in all_units(owner):
		if card.is_hero():
			continue
		out.append(card)
	return out


## 在「可摧毁单位」里挑战力最高 / 最低（并列全选）。无可摧毁单位时返回空数组。
func pick_extreme_destroyable(owner: PlayerState, want_highest: bool) -> Array[CardData]:
	var units := destroyable_units(owner)
	if units.is_empty():
		return []
	var best := owner.effective_power(units[0])
	for card in units:
		var p := owner.effective_power(card)
		if (want_highest and p > best) or (not want_highest and p < best):
			best = p
	var out: Array[CardData] = []
	for card in units:
		if owner.effective_power(card) == best:
			out.append(card)
	return out


## 清除某行所有减益（把负永久增益归零，保留正增益）。
func clear_debuffs_in_row(owner: PlayerState, row: String, _reason: String = "") -> Array[CardData]:
	var affected: Array[CardData] = []
	for card in owner.row_cards(row):
		if state.clear_card_debuff(card):
			affected.append(card)
	return affected
