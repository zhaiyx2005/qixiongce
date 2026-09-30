extends RefCounted
class_name FactionEffects

const FACTION_ROLES := {
	"qin": "军功成长 · 精确压制", "qi": "步弩协同 · 三路调度",
	"chu": "多路展开 · 纵深施压", "yan": "边塞固守 · 袭击后阵",
	"han": "劲弩集结 · 铁冶增援", "zhao": "骑兵策应 · 将相协力",
	"wei": "武卒结阵 · 精兵选练",
}
const FACTION_TIPS := {
	"qin": "军功爵强化步卒，带动军功进爵；分散强化优于单卡堆叠。",
	"qi": "步卒与弓弩手在守军行协同；尊王攘夷奖励三路布阵。",
	"chu": "至少两行展开以启动纵深；单行堆兵会失去特色收益。",
	"yan": "戍守部队适合守军行；下齐七十城专门压制对手远程阵线。",
	"han": "劲弩列阵最多 +3；配合宜阳铁冶，避免无限堆叠。",
	"zhao": "将骑兵分置近战与远程；保留步卒以配合将相和。",
	"wei": "让步卒彼此紧邻；武卒选练同时补给，避免骑兵割裂方阵。",
}

## 七国特色：有限目标、稳定选序；不使用展示层随机数，不额外创造手牌资源。
const UNITS := {
	"qin_merit": {"timing": "dynamic", "name": "军功进爵", "text": "有正永久增益时战力 +2；否则有相邻单位时 +1。两者不叠加。"},
	"qi_combined": {"timing": "dynamic", "name": "技击协同", "text": "同行同时有步卒与弓弩手时战力 +2；否则有其他步卒时 +1。两者不叠加。"},
	"chu_depth": {"timing": "dynamic", "name": "荆楚纵深", "text": "己方至少两行有单位时，本卡战力 +2。"},
	"yan_frontier": {"timing": "dynamic", "name": "北疆戍守", "text": "位于守军行时战力 +2；位于近战行时 +1。"},
	"han_crossbow": {"timing": "dynamic", "name": "劲弩列阵", "text": "同行每名弓弩手（含本卡）使本卡战力 +1，最多 +3。"},
	"zhao_mobile": {"timing": "dynamic", "name": "骑射策应", "text": "另一行有己方骑兵时战力 +2；否则同行有其他骑兵时 +1。"},
	"wei_drill": {"timing": "dynamic", "name": "武卒方阵", "text": "每名左右紧邻的步卒使本卡战力 +1，最多 +2。"},
}
const TACTICS := {
	"tac_yuanjiao": {"timing": "on_play", "name": "远交近攻", "text": "对方战力最高的一个非英杰单位 -3；同战力按行与站位取首个。"},
	"tac_jungong": {"timing": "on_play", "name": "军功爵", "text": "己方战力最低的至多 3 名步卒各 +2。"},
	"tac_qi_weiwei": {"timing": "on_play", "name": "围魏救赵", "text": "对方最强行中战力最高的至多 2 个非英杰单位各 -2。"},
	"tac_qi_zunwang": {"timing": "on_play", "name": "尊王攘夷", "text": "己方每行战力最低的一个非英杰单位 +2，鼓励分兵三路。"},
	"tac_chu_wending": {"timing": "on_play", "name": "问鼎中原", "text": "对方最强行中战力最高的至多 3 个非英杰单位各 -1；己方至少两行有单位时改为 -2。"},
	"tac_chu_bilu": {"timing": "on_play", "name": "筚路蓝缕", "text": "己方每行战力最低的至多 2 个非英杰单位各 +1。"},
	"tac_chu_baiyue": {"timing": "on_play", "name": "百越归附", "text": "己方单位数不少于对方时，每行战力最低的一个非英杰单位 +1。"},
	"tac_yan_xiaqi": {"timing": "on_play", "name": "下齐七十城", "text": "对方远程行战力最高的至多 2 个非英杰单位各 -2。"},
	"tac_yan_kuhan": {"timing": "on_play", "name": "苦寒之地", "text": "己方守军行战力最低的至多 3 个非英杰单位各 +2。"},
	"tac_han_jinnu": {"timing": "on_play", "name": "劲弩之师", "text": "对方近战行战力最高的至多 2 个非英杰单位各 -2。"},
	"tac_han_yiyang": {"timing": "on_play", "name": "宜阳铁冶", "text": "己方战力最低的至多 3 名弓弩手各 +2。"},
	"tac_yuyu": {"timing": "on_play", "name": "阏与之战", "text": "对方最强行中战力最高的至多 2 个非英杰单位各 -2。"},
	"tac_jiangxiang": {"timing": "on_play", "name": "将相和", "text": "己方战力最低的一名步卒与一名骑兵各 +3。"},
	"tac_wei_wuzuzhi": {"timing": "on_play", "name": "武卒之制", "text": "己方战力最低的至多 2 名步卒各 +2。"},
	"tac_wei_wuzu": {"timing": "on_play", "name": "武卒选练", "text": "己方战力最低的至多 3 名步卒各 +1，然后抽 1 张。"},
	"tac_wei_wuqilianbing": {"timing": "on_play", "name": "吴起练兵", "text": "己方场上单位数不少于对方时，战力最低的至多 3 名步卒各 +2。"},
}

static func definition(id: String) -> Dictionary:
	return UNITS.get(id, TACTICS.get(id, {}))

static func occupied_rows(owner: PlayerState) -> int:
	var count := 0
	for row in CardData.ROWS:
		if not owner.row_cards(row).is_empty():
			count += 1
	return count

static func dynamic_bonus(owner: PlayerState, card: CardData, row: String) -> int:
	if row.is_empty():
		return 0
	var cards := owner.row_cards(row)
	match card.ability_id:
		"qin_merit":
			return 2 if owner.permanent_of(card) > 0 else (1 if cards.size() > 1 else 0)
		"qi_combined":
			var infantry := false
			var archer := false
			for c in cards:
				infantry = infantry or c.unit_type == CardData.UNIT_INFANTRY
				archer = archer or c.unit_type == CardData.UNIT_ARCHER
			if infantry and archer:
				return 2
			for c in cards:
				if c != card and c.unit_type == CardData.UNIT_INFANTRY:
					return 1
			return 0
		"chu_depth":
			return 2 if occupied_rows(owner) >= 2 else 0
		"yan_frontier":
			return 2 if row == CardData.ROW_GARRISON else 1
		"han_crossbow":
			var count := 0
			for c in cards:
				if c.unit_type == CardData.UNIT_ARCHER:
					count += 1
			return mini(count, 3)
		"zhao_mobile":
			for other in CardData.ROWS:
				if other != row:
					for c in owner.row_cards(other):
						if c.unit_type == CardData.UNIT_CAVALRY:
							return 2
			for c in cards:
				if c != card and c.unit_type == CardData.UNIT_CAVALRY:
					return 1
		"wei_drill":
			var index := cards.find(card)
			var count := 0
			for neighbor in [index - 1, index + 1]:
				if neighbor >= 0 and neighbor < cards.size() and cards[neighbor].unit_type == CardData.UNIT_INFANTRY:
					count += 1
			return count
	return 0

## 每次先冻结目标再施加效果，避免数值变化影响下一目标；稳定处理同分。
static func select_units(owner: PlayerState, row: String, kind: String, limit: int, highest: bool) -> Array[CardData]:
	var candidates: Array[CardData] = []
	for r in CardData.ROWS:
		if not row.is_empty() and row != r:
			continue
		for c in owner.row_cards(r):
			if not c.is_hero() and (kind.is_empty() or c.unit_type == kind):
				candidates.append(c)
	var result: Array[CardData] = []
	while not candidates.is_empty() and result.size() < limit:
		var best := candidates[0]
		for c in candidates:
			if (highest and owner.effective_power(c) > owner.effective_power(best)) or (not highest and owner.effective_power(c) < owner.effective_power(best)):
				best = c
		result.append(best)
		candidates.erase(best)
	return result

static func run_tactic(state: GameState, pi: int, id: String) -> String:
	var owner := state.players[pi]
	var foe := state.players[1 - pi]
	var res := EffectResolver.new(state)
	var targets: Array[CardData] = []
	var delta := 2
	match id:
		"tac_yuanjiao":
			targets = select_units(foe, "", "", 1, true)
			delta = -3
		"tac_qi_weiwei", "tac_yuyu", "tac_chu_wending":
			targets = select_units(foe, res.strongest_row(foe), "", 3 if id == "tac_chu_wending" else 2, true)
			delta = -1 if id == "tac_chu_wending" and occupied_rows(owner) < 2 else -2
		"tac_yan_xiaqi", "tac_han_jinnu":
			targets = select_units(foe, CardData.ROW_RANGED if id == "tac_yan_xiaqi" else CardData.ROW_MELEE, "", 2, true)
			delta = -2
		"tac_wei_wuqilianbing":
			if res.unit_count(owner) >= res.unit_count(foe):
				targets = select_units(owner, "", CardData.UNIT_INFANTRY, 3, false)
		"tac_jungong", "tac_wei_wuzuzhi", "tac_wei_wuzu":
			targets = select_units(owner, "", CardData.UNIT_INFANTRY, 2 if id == "tac_wei_wuzuzhi" else 3, false)
			delta = 1 if id == "tac_wei_wuzu" else 2
		"tac_qi_zunwang", "tac_chu_bilu":
			for row in CardData.ROWS:
				targets.append_array(select_units(owner, row, "", 2 if id == "tac_chu_bilu" else 1, false))
			delta = 1 if id == "tac_chu_bilu" else 2
		"tac_chu_baiyue":
			if res.unit_count(owner) >= res.unit_count(foe):
				for row in CardData.ROWS:
					targets.append_array(select_units(owner, row, "", 1, false))
			delta = 1
		"tac_yan_kuhan":
			targets = select_units(owner, CardData.ROW_GARRISON, "", 3, false)
		"tac_han_yiyang":
			targets = select_units(owner, "", CardData.UNIT_ARCHER, 3, false)
		"tac_jiangxiang":
			for kind in [CardData.UNIT_INFANTRY, CardData.UNIT_CAVALRY]:
				targets.append_array(select_units(owner, "", kind, 1, false))
			delta = 3
	var affected := 0
	for c in targets:
		if state.apply_power_change(c, delta, str(TACTICS[id].name)):
			affected += 1
	var message := "%s：%d 个单位各 %+d" % [TACTICS[id].name, affected, delta]
	if id == "tac_wei_wuzu":
		message += "；抽 %d 张" % owner.draw(1).size()
	return message
