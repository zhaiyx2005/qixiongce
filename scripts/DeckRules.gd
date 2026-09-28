extends RefCounted
class_name DeckRules

## 卡组构筑规则（数据层，牌库编辑界面直接复用）。
##
## 规格：每套 29 张
##   - 普通单位牌 20 张（同名最多 3 张）
##   - 英杰牌      2 张（每张只能 1 份）
##   - 计策牌      6 张（同名最多 3 张）
##   - 领袖牌      1 张
## 其中单位牌合计 22 张 = 20 普通 + 2 英杰。

const NORMAL_UNITS := 20
const HEROES := 2
const TACTICS := 6
const LEADERS := 1
const TOTAL := NORMAL_UNITS + HEROES + TACTICS + LEADERS  # 29
const UNITS := NORMAL_UNITS + HEROES                      # 22

const MAX_COPIES_PER_NAME := 3   # 普通单位 / 计策：同名上限 3
const MAX_COPIES_PER_HERO := 1   # 英杰：同名上限 1


## 统计卡组中各分类的张数。
## 返回 {"normal": int, "hero": int, "tactic": int, "leader": int, "total": int}
static func count_by_category(deck: DeckList, db: CardDB) -> Dictionary:
	var counts := {"normal": 0, "hero": 0, "tactic": 0, "leader": 0, "total": 0}
	if deck == null:
		return counts
	for entry in deck.entries():
		var card := db.get_card_by_id(entry["id"])
		if card == null:
			continue
		var count: int = int(entry["count"])
		counts["total"] += count
		if card.card_type == CardData.TYPE_LEADER:
			counts["leader"] += count
		elif card.card_type == CardData.TYPE_TACTIC:
			counts["tactic"] += count
		elif card.is_hero():
			counts["hero"] += count
		else:
			counts["normal"] += count
	return counts


## 校验卡组，返回错误信息列表；空列表 = 合法。
static func validate(deck: DeckList, db: CardDB) -> Array[String]:
	var errors: Array[String] = []
	if deck == null:
		errors.append("卡组为空。")
		return errors

	var counts := {"normal": 0, "hero": 0, "tactic": 0, "leader": 0, "total": 0}
	var by_name: Dictionary = {}
	var by_category_name: Dictionary = {}

	for entry in deck.entries():
		var card_id: String = entry["id"]
		var count: int = entry["count"]
		var card := db.get_card_by_id(card_id)
		if card == null:
			errors.append("未知卡牌 id：%s" % card_id)
			continue
		if card.faction != deck.faction and not deck.faction.is_empty():
			errors.append("「%s」不属于 %s 阵营。" % [card.name, deck.faction])
		if count <= 0:
			errors.append("「%s」的张数非法：%d" % [card.name, count])

		counts["total"] += count
		var category := card.category()
		if category == CardData.CATEGORY_LEADER:
			counts["leader"] += count
		elif category == CardData.CATEGORY_TACTIC:
			counts["tactic"] += count
		elif category == CardData.UNIT_HERO:
			counts["hero"] += count
		else:
			counts["normal"] += count

		by_name[card.name] = int(by_name.get(card.name, 0)) + count
		var key := "%s|%s" % [category, card.name]
		by_category_name[key] = int(by_category_name.get(key, 0)) + count

	if deck.size() <= 0:
		errors.append("卡组不能为空。")
		return errors

	if counts["normal"] != NORMAL_UNITS:
		errors.append("普通单位牌必须正好 %d 张，当前 %d 张。" % [NORMAL_UNITS, counts["normal"]])
	if counts["hero"] != HEROES:
		errors.append("英杰牌必须正好 %d 张，当前 %d 张。" % [HEROES, counts["hero"]])
	if counts["tactic"] != TACTICS:
		errors.append("计策牌必须正好 %d 张，当前 %d 张。" % [TACTICS, counts["tactic"]])
	if counts["leader"] != LEADERS:
		errors.append("领袖牌必须为 %d 张，当前 %d 张。" % [LEADERS, counts["leader"]])
	if counts["total"] != TOTAL:
		errors.append("卡组总数应为 %d 张，当前 %d 张。" % [TOTAL, counts["total"]])

	for card_name in by_name.keys():
		if int(by_name[card_name]) > MAX_COPIES_PER_NAME:
			errors.append("「%s」超过同名上限：%d / %d" % [card_name, int(by_name[card_name]), MAX_COPIES_PER_NAME])

	# 英杰每张只能 1 份
	for key in by_category_name.keys():
		var parts: PackedStringArray = str(key).split("|")
		if parts.size() == 2 and parts[0] == CardData.UNIT_HERO:
			var hero_count := int(by_category_name[key])
			if hero_count > MAX_COPIES_PER_HERO:
				errors.append("英杰「%s」只能携带 %d 张，当前 %d 张。"
					% [parts[1], MAX_COPIES_PER_HERO, hero_count])

	return errors


static func is_valid(deck: DeckList, db: CardDB) -> bool:
	return validate(deck, db).is_empty()


## 卡组摘要，供卡组编辑 UI 显示
static func describe(deck: DeckList, db: CardDB) -> Dictionary:
	var counts := count_by_category(deck, db)
	counts["faction"] = deck.faction
	counts["units"] = int(counts["normal"]) + int(counts["hero"])
	counts["specials"] = counts["tactic"]
	counts["leaders"] = counts["leader"]
	counts["valid"] = validate(deck, db).is_empty()
	return counts
