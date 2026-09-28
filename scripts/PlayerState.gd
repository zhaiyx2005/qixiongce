extends RefCounted
class_name PlayerState

## 单方玩家的状态容器：手牌 / 牌库 / 弃牌堆 / 三行战场 / 宝石 / Pass 标记。
## 只负责“装数据 + 最小存取动作”，规则判定在 GameState 里。

## 卡牌实例状态：key 为 CardData 实例，返回一个 Dictionary。
## 由于同一张 CardData 是共享数据对象，场上同一时刻最多一份；
## 需要「按场次存活状态」区分的能力（老兵计数、曾进场标记、永久增益）
## 一律存在这里，避免污染 CardData 资源。
##
## 每次开局（clear_board）会清掉大部分状态；跨局保留的只有：
##   - permanents（永久增益）
##   - returned_before（曾进场标记，蔺相如 / 完璧归赵用）

var faction: String = CardData.FACTION_QIN
var display_name: String = ""
var is_human: bool = true

## 领袖卡单独存放，不进入抽牌堆
var leader: CardData = null
## 抽牌堆
var deck: Array[CardData] = []
## 手牌（跨局保留）
var hand: Array[CardData] = []
## 弃牌堆（局末场上单位进这里）
var discard: Array[CardData] = []
## 战场：row -> Array[CardData]
var board: Dictionary = {}

## 卡牌 -> 永久增益（本局内跨行/换行不丢，局末清空）
var permanents: Dictionary = {}
## 卡牌 -> 本局是否曾进场（跨局保留）
var returned_before: Dictionary = {}
## 卡牌 -> 本局在场上度过的己方回合数（老兵用，离场清零）
var turns_on_board: Dictionary = {}
## 卡牌 -> 老兵是否已触发（每张卡只触发一次）
var veteran_done: Dictionary = {}
## 本局行光环：row -> 每张进场单位自动获得的永久战力（秦惠文王 / 赵惠文王）
var row_aura: Dictionary = {}

var gems: int = 2
var passed: bool = false
var rounds_won: int = 0


func _init(p_faction: String = CardData.FACTION_QIN, p_is_human: bool = true) -> void:
	faction = p_faction
	is_human = p_is_human
	# 战报里显示的部队名，如「秦军」。七国通用写法，别再写成 if/else 两分支。
	display_name = "%s军" % CardData.faction_name_of(faction)
	clear_board()


# ---------------- 战场 ----------------

func clear_board() -> void:
	board = {}
	for row in CardData.ROWS:
		var empty: Array[CardData] = []
		board[row] = empty
	permanents.clear()
	turns_on_board.clear()
	veteran_done.clear()


func row_cards(row: String) -> Array[CardData]:
	var empty: Array[CardData] = []
	var value: Variant = board.get(row, empty)
	if value is Array:
		return value
	return empty


## 单卡动态战力 = 卡面战力 + 本局永久增益 + 动态能力加成。
## 英杰战力固定不变，直接返回卡面值。
func effective_power(card: CardData) -> int:
	if card == null:
		return 0
	if card.is_hero():
		return card.power
	var row := row_of(card)
	return card.power + int(permanents.get(card, 0)) + Abilities.dynamic_bonus(null, self, card, row)


## 卡片当前所在行（不在场上返回空串）。
func row_of(card: CardData) -> String:
	for row in CardData.ROWS:
		if row_cards(row).has(card):
			return row
	return ""


## 该卡是否在本方场上（已打出）。
func board_has(card: CardData) -> bool:
	if card == null:
		return false
	for row in CardData.ROWS:
		if row_cards(row).has(card):
			return true
	return false


func row_power(row: String) -> int:
	var total := 0
	for card in row_cards(row):
		total += effective_power(card)
	return total


func total_power() -> int:
	var total := 0
	for row in CardData.ROWS:
		total += row_power(row)
	return total


# ---------------- 卡牌状态 ----------------

func permanent_of(card: CardData) -> int:
	return int(permanents.get(card, 0))


func add_permanent(card: CardData, delta: int) -> void:
	permanents[card] = permanent_of(card) + delta


func turns_of(card: CardData) -> int:
	return int(turns_on_board.get(card, 0))


func bump_turn_count(card: CardData) -> int:
	var n := turns_of(card) + 1
	turns_on_board[card] = n
	return n


## 卡牌离场时清掉「场上计数」（老兵重新进场要从 0 重新计数）。
func clear_on_board_state(card: CardData) -> void:
	turns_on_board.erase(card)


## 把卡放到指定行（不经过手牌校验，供召唤/回收等内部使用）。
func place_unit(card: CardData, row: String) -> bool:
	if card == null or not CardData.ROWS.has(row):
		return false
	var cards := row_cards(row)
	cards.append(card)
	board[row] = cards
	return true


## 从指定行移除（不移入任何区域，由调用方决定去处）。
func remove_from_row(card: CardData, row: String) -> bool:
	if not CardData.ROWS.has(row):
		return false
	var cards := row_cards(row)
	var idx := cards.find(card)
	if idx < 0:
		return false
	cards.remove_at(idx)
	board[row] = cards
	clear_on_board_state(card)
	return true


## 把卡放到它归属的默认行；不在手牌或非法则失败。
## index 为行内插入位置（仅影响显示顺序，不影响战力结算）；-1 表示追加到行尾。
func play_to_board(card: CardData, index: int = -1, row: String = "") -> bool:
	if not is_playable(card):
		return false
	var target_row := row
	if target_row.is_empty():
		target_row = card.row
	if not card.can_place_in(target_row):
		return false
	var idx := hand.find(card)
	if idx < 0:
		return false
	hand.remove_at(idx)
	var cards := row_cards(target_row)
	if index < 0 or index > cards.size():
		cards.append(card)
	else:
		cards.insert(index, card)
	board[target_row] = cards
	return true



## 场上所有单位进弃牌堆，战场清空。
func clear_board_to_discard() -> void:
	for row in CardData.ROWS:
		for card in row_cards(row):
			discard.append(card)
	clear_board()


# ---------------- 手牌 / 牌库 ----------------

## 该卡当前是否可以打出：单位卡（含英杰）可打；计策卡打出即结算，由 GameState 判定。
func is_playable(card: CardData) -> bool:
	if card == null:
		return false
	if card.card_type == CardData.TYPE_TACTIC:
		return true
	return card.card_type == CardData.TYPE_UNIT and not card.legal_rows().is_empty()


## 手牌里所有可打的单位卡。
func playable_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for card in hand:
		if card.card_type == CardData.TYPE_UNIT:
			out.append(card)
	return out


## 手牌里所有单位卡（含英杰）。
func unit_cards_in_hand() -> Array[CardData]:
	return playable_cards()


## 手牌里所有计策卡。
func tactic_cards_in_hand() -> Array[CardData]:
	var out: Array[CardData] = []
	for card in hand:
		if card.card_type == CardData.TYPE_TACTIC:
			out.append(card)
	return out


## 手牌里所有可打出的牌（单位 + 计策）。
func playable_any() -> Array[CardData]:
	var out: Array[CardData] = []
	for card in hand:
		if is_playable(card):
			out.append(card)
	return out


func hand_size() -> int:
	return hand.size()


func deck_size() -> int:
	return deck.size()


func discard_size() -> int:
	return discard.size()


# ---------------- 卡组 / 抽牌 ----------------

## 用构筑好的卡牌列表初始化：领袖单独拿出，其余进抽牌堆。
func setup_deck(cards: Array[CardData]) -> void:
	deck.clear()
	hand.clear()
	discard.clear()
	leader = null
	permanents.clear()
	returned_before.clear()
	turns_on_board.clear()
	veteran_done.clear()
	clear_board()
	for card in cards:
		if card.card_type == CardData.TYPE_LEADER or card.is_leader:
			if leader == null:
				leader = card
			# 多出的领袖不入抽牌堆（正常卡组只有 1 张）
		else:
			deck.append(card)


func shuffle_deck(rng: RandomNumberGenerator) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: CardData = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp


## 抽牌，牌库空了就停。返回实际抽到的牌。
func draw(count: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	for _i in range(count):
		if deck.is_empty():
			break
		var card: CardData = deck.pop_back()
		hand.append(card)
		drawn.append(card)
	return drawn


## 换牌：把这些牌放回牌库（调用方负责洗牌与补抽）。
func return_cards_to_deck(cards: Array[CardData]) -> void:
	for card in cards:
		var idx := hand.find(card)
		if idx >= 0:
			hand.remove_at(idx)
		deck.append(card)


# ---------------- 状态查询 ----------------

func is_out_of_gems() -> bool:
	return gems <= 0


func gems_text() -> String:
	var text := ""
	for i in range(2):
		text += "◆" if i < gems else "◇"
	return text


# ---------------- 序列化（联机状态同步用） ----------------
#
# 状态一律以 CardData **对象**为 key，而对象无法跨网络传输，
# 因此序列化时把 key 换成卡牌在玩家区域里的**位置标识**：
#   hand:0 / deck:3 / discard:5 / board:melee:1 / leader
# 反序列化时按同样的位置标识回填，保证永久增益等状态精确还原。
#
# 【前提】每张牌 id 在同一区域内可能重复（同名卡有多份实例），
# 所以必须用「区域 + 下标」而不是卡牌 id 来定位。

func serialize() -> Dictionary:
	# ⚠️ 顺序敏感：以对象为 key 的字典必须先算槽位，再生成各区域的 id 数组。
	#    slot_of() 按 hand → board → deck → discard → leader 的顺序查第一个命中的区域，
	#    而 hand / board / deck 的内容可能重复（换牌后同一张牌既在手牌又在牌库，
	#    牌库只按 id 序列化、下标无法唯一还原）。
	#    若先取 id 数组、后算槽位，手牌里的牌就可能被判到别的区域而丢状态。
	var perm_slots := _dict_to_slots(permanents)
	var returned_slots := _dict_to_slots(returned_before)
	var turns_slots := _dict_to_slots(turns_on_board)
	var veteran_slots := _dict_to_slots(veteran_done)
	return {
		"faction": faction,
		"display_name": display_name,
		"is_human": is_human,
		"leader": leader.id if leader != null else "",
		"deck": _cards_to_ids(deck),
		"hand": _cards_to_ids(hand),
		"discard": _cards_to_ids(discard),
		"board": _board_to_ids(),
		"permanents": perm_slots,
		"returned_before": returned_slots,
		"turns_on_board": turns_slots,
		"veteran_done": veteran_slots,
		"row_aura": _string_keyed_dict(row_aura),
		"gems": gems,
		"passed": passed,
		"rounds_won": rounds_won,
	}


## 用序列化数据还原本方状态。db 用于把卡牌 id 还原成 CardData 实例
## （**必须新实例化**，不能共用 CardDB 原型 —— 见 CardData.duplicate_card 注释）。
func deserialize(data: Dictionary, db: CardDB) -> void:
	faction = str(data.get("faction", faction))
	display_name = str(data.get("display_name", display_name))
	is_human = bool(data.get("is_human", is_human))

	deck = _ids_to_cards(data.get("deck", []), db)
	hand = _ids_to_cards(data.get("hand", []), db)
	discard = _ids_to_cards(data.get("discard", []), db)

	board = {}
	for row in CardData.ROWS:
		var ids: Variant = data.get("board", {}).get(row, [])
		var cards: Array[CardData] = []
		for raw in ids:
			var card := _make_card(str(raw), db)
			if card != null:
				cards.append(card)
		board[row] = cards

	var leader_id := str(data.get("leader", ""))
	leader = _make_card(leader_id, db) if not leader_id.is_empty() else null

	permanents = _slots_to_dict(data.get("permanents", {}))
	returned_before = _slots_to_dict(data.get("returned_before", {}))
	turns_on_board = _slots_to_dict(data.get("turns_on_board", {}))
	veteran_done = _slots_to_dict(data.get("veteran_done", {}))
	row_aura = _string_keyed_dict_in(data.get("row_aura", {}))

	gems = int(data.get("gems", gems))
	passed = bool(data.get("passed", passed))
	rounds_won = int(data.get("rounds_won", rounds_won))


## 卡牌所在「槽位」标识；不在这方区域返回空串。
## 顺序固定：hand → board(按行序) → deck → discard → leader。
func slot_of(card: CardData) -> String:
	var idx := hand.find(card)
	if idx >= 0:
		return "hand:%d" % idx
	for row in CardData.ROWS:
		var cards := row_cards(row)
		var ri := cards.find(card)
		if ri >= 0:
			return "board:%s:%d" % [row, ri]
	idx = deck.find(card)
	if idx >= 0:
		return "deck:%d" % idx
	idx = discard.find(card)
	if idx >= 0:
		return "discard:%d" % idx
	if leader != null and leader == card:
		return "leader"
	return ""


## 按槽位标识取卡（反序列化后重建字典用）。
func card_at_slot(slot: String) -> CardData:
	if slot.is_empty():
		return null
	var parts := slot.split(":")
	if parts[0] == "leader":
		return leader
	if parts.size() < 2:
		return null
	var idx := int(parts[1])
	match parts[0]:
		"hand":
			return hand[idx] if idx >= 0 and idx < hand.size() else null
		"deck":
			return deck[idx] if idx >= 0 and idx < deck.size() else null
		"discard":
			return discard[idx] if idx >= 0 and idx < discard.size() else null
		"board":
			if parts.size() < 3:
				return null
			var row := parts[1]
			var cards := row_cards(row)
			var ri := int(parts[2])
			return cards[ri] if ri >= 0 and ri < cards.size() else null
	return null


func _cards_to_ids(cards: Array[CardData]) -> Array:
	var out: Array = []
	for card in cards:
		out.append(card.id)
	return out


func _board_to_ids() -> Dictionary:
	var out: Dictionary = {}
	for row in CardData.ROWS:
		out[row] = _cards_to_ids(row_cards(row))
	return out


## 把「CardData -> int/bool」字典转成「槽位 -> 值」。
func _dict_to_slots(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for card in source.keys():
		var slot := slot_of(card)
		if slot.is_empty():
			continue   # 不在任何区域（例如已离场的计数残留），丢弃
		out[slot] = source[card]
	return out


func _slots_to_dict(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for slot in raw.keys():
		var card := card_at_slot(str(slot))
		if card != null:
			out[card] = raw[slot]
	return out


func _string_keyed_dict(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in source.keys():
		out[str(k)] = source[k]
	return out


func _string_keyed_dict_in(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		out[str(k)] = raw[k]
	return out


func _ids_to_cards(ids: Variant, db: CardDB) -> Array[CardData]:
	var out: Array[CardData] = []
	if not (ids is Array):
		return out
	for raw in ids:
		var card := _make_card(str(raw), db)
		if card != null:
			out.append(card)
	return out


func _make_card(card_id: String, db: CardDB) -> CardData:
	if card_id.is_empty() or db == null:
		return null
	var proto := db.get_card_by_id(card_id)
	if proto == null:
		push_warning("[PlayerState] 反序列化遇到未知卡牌 id：%s" % card_id)
		return null
	return proto.duplicate_card()
