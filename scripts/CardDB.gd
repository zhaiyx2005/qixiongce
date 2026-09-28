extends RefCounted
class_name CardDB

## 《七雄策》卡牌数据库（数据层）
##
## 职责：
##   1. 从 data/ 目录加载七国卡牌数据（qin/qi/chu/yan/han/zhao/wei_cards.json）
##   2. 提供按 id / 阵营 / 分类查询
##   3. 加载时校验字段与数量，错误写入 load_errors
##
## 明确不做：抽牌、出牌、比战力、AI、UI —— 这些属于 GameState 等模块。

## 阵营 -> 数据文件路径（七雄）
const FACTION_DATA_FILES := {
	CardData.FACTION_QIN: "res://data/qin_cards.json",
	CardData.FACTION_QI: "res://data/qi_cards.json",
	CardData.FACTION_CHU: "res://data/chu_cards.json",
	CardData.FACTION_YAN: "res://data/yan_cards.json",
	CardData.FACTION_HAN: "res://data/han_cards.json",
	CardData.FACTION_ZHAO: "res://data/zhao_cards.json",
	CardData.FACTION_WEI: "res://data/wei_cards.json",
}

## 每阵营应有的卡牌数量（30 普通单位 + 4 英杰 + 8 计策 + 3 领袖 = 45）
const NORMAL_UNITS_PER_FACTION := 30
const HEROES_PER_FACTION := 4
const TACTICS_PER_FACTION := 8
const LEADERS_PER_FACTION := 3
const UNITS_PER_FACTION := NORMAL_UNITS_PER_FACTION + HEROES_PER_FACTION  # 34
const CARDS_PER_FACTION := UNITS_PER_FACTION + TACTICS_PER_FACTION + LEADERS_PER_FACTION  # 45

## 所有条目必须包含的字段
const REQUIRED_FIELDS := [
	"id", "name", "faction", "card_type", "row", "power", "unit_type",
	"is_leader", "description", "ability_id", "faction_ability_id",
]

## faction -> Array[CardData]，保持 JSON 中的原始顺序
var _cards_by_faction: Dictionary = {}
## id -> CardData
var _cards_by_id: Dictionary = {}
## 加载过程中收集到的错误信息（空数组表示数据完全合法）
var load_errors: PackedStringArray = PackedStringArray()


func _init() -> void:
	load_all()


## 加载全部阵营数据。可重复调用（会先清空再重新载入）。
func load_all() -> void:
	_cards_by_faction.clear()
	_cards_by_id.clear()
	load_errors = PackedStringArray()
	for faction in FACTION_DATA_FILES.keys():
		_load_faction_file(faction, FACTION_DATA_FILES[faction])


## 按 id 查询单张卡牌，不存在时返回 null。
func get_card_by_id(card_id: String) -> CardData:
	return _cards_by_id.get(card_id, null)


## 该 id 是否存在于卡库中。
func has_card(card_id: String) -> bool:
	return _cards_by_id.has(card_id)


## 按阵营获取全部卡牌（返回副本，外部修改不会污染卡库）。
## 传入未知阵营时返回空数组并记录错误。
func get_cards_by_faction(faction: String) -> Array[CardData]:
	var result: Array[CardData] = []
	if not _cards_by_faction.has(faction):
		load_errors.append("未知阵营：%s" % faction)
		return result
	result.assign(_cards_by_faction[faction])
	return result


## 全部已加载的卡牌（跨阵营，返回副本）。
func get_all_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for faction in _cards_by_faction.keys():
		result.append_array(_cards_by_faction[faction])
	return result


## 按分类筛选某阵营的卡牌。category 取值见 CardData.CATEGORIES。
func get_cards_by_category(faction: String, category: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in get_cards_by_faction(faction):
		if card.category() == category:
			result.append(card)
	return result


## 按阵营获取全部单位卡（含英杰，不含领袖与计策）。
func get_unit_cards_by_faction(faction: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in get_cards_by_faction(faction):
		if card.card_type == CardData.TYPE_UNIT:
			result.append(card)
	return result


## 按阵营获取普通单位卡（不含英杰）。
func get_normal_unit_cards_by_faction(faction: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in get_cards_by_faction(faction):
		if card.card_type == CardData.TYPE_UNIT and not card.is_hero():
			result.append(card)
	return result


## 按阵营获取英杰卡。
func get_hero_cards_by_faction(faction: String) -> Array[CardData]:
	return get_cards_by_category(faction, CardData.UNIT_HERO)


## 按阵营获取计策卡（**只有本国自己的**）。
##
## 【设计决定：不存在通用计策】曾经把 9 张计策做成七国通用（`is_shared`），
## 但那样会让各国计策同质化 —— 现在**每个国家都有自己专属的 8 张计策**，
## 强国与弱国的差别靠计策强度而非共享池来体现。
func get_tactic_cards_by_faction(faction: String) -> Array[CardData]:
	return get_cards_by_category(faction, CardData.CATEGORY_TACTIC)


## 按阵营获取领袖卡（无则返回 null）。
func get_leader_card(faction: String) -> CardData:
	for card in get_cards_by_faction(faction):
		if card.is_leader or card.card_type == CardData.TYPE_LEADER:
			return card
	return null


## 按阵营获取全部领袖卡（供牌库编辑 3 选 1）。
func get_leader_cards(faction: String) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in get_cards_by_faction(faction):
		if card.is_leader or card.card_type == CardData.TYPE_LEADER:
			result.append(card)
	return result


# ---------------- 内部实现 ----------------

func _load_faction_file(faction: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		load_errors.append("数据文件不存在：%s" % path)
		return

	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		load_errors.append("数据文件为空或读取失败：%s" % path)
		return

	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or typeof(parsed) != TYPE_ARRAY:
		load_errors.append("数据文件不是合法的 JSON 数组：%s" % path)
		return

	var list: Array[CardData] = []
	for entry in parsed:
		var card := _build_card(entry, faction, path)
		if card == null:
			continue
		if _cards_by_id.has(card.id):
			load_errors.append("id 重复：%s（%s）" % [card.id, path])
			continue
		_cards_by_id[card.id] = card
		list.append(card)

	_cards_by_faction[faction] = list
	_check_faction_count(faction, list, path)


func _build_card(entry: Variant, expected_faction: String, path: String) -> CardData:
	if typeof(entry) != TYPE_DICTIONARY:
		load_errors.append("条目不是 JSON 对象（%s）" % path)
		return null

	for field in REQUIRED_FIELDS:
		if not entry.has(field):
			load_errors.append("条目缺少字段 %s（%s）：%s" % [field, path, entry])
			return null

	if str(entry["faction"]) != expected_faction:
		load_errors.append("阵营字段与文件名不符（%s）：%s" % [path, entry["id"]])
		return null

	var card := CardData.new()
	card.id = str(entry["id"])
	card.name = str(entry["name"])
	card.faction = str(entry["faction"])
	card.card_type = str(entry["card_type"])
	card.unit_type = str(entry["unit_type"])
	card.row = str(entry["row"])
	card.power = int(entry["power"])
	card.is_leader = bool(entry["is_leader"])
	card.description = str(entry["description"])
	card.ability_id = str(entry["ability_id"])
	card.faction_ability_id = str(entry["faction_ability_id"])
	_validate_card(card, path)
	return card


func _validate_card(card: CardData, path: String) -> void:
	match card.card_type:
		CardData.TYPE_UNIT:
			if not CardData.UNIT_TYPES.has(card.unit_type):
				load_errors.append("单位卡兵种非法（%s）：%s -> '%s'" % [path, card.id, card.unit_type])
			if not CardData.ROWS.has(card.row):
				load_errors.append("单位卡行字段非法（%s）：%s -> '%s'" % [path, card.id, card.row])
			elif not card.can_place_in(card.row):
				load_errors.append("单位卡默认行不在兵种合法行内（%s）：%s(%s) -> '%s'"
					% [path, card.id, card.unit_type, card.row])
			if card.is_leader:
				load_errors.append("单位卡不应标记为领袖（%s）：%s" % [path, card.id])
			if card.power <= 0:
				load_errors.append("单位卡战力应为正数（%s）：%s -> %d" % [path, card.id, card.power])
		CardData.TYPE_LEADER:
			if card.row != "":
				load_errors.append("领袖卡行字段应为空（%s）：%s" % [path, card.id])
			if card.power != 0:
				load_errors.append("领袖卡战力应为 0（%s）：%s" % [path, card.id])
			if not card.is_leader:
				load_errors.append("领袖卡 is_leader 应为 true（%s）：%s" % [path, card.id])
			if card.unit_type != "":
				load_errors.append("领袖卡兵种字段应为空（%s）：%s" % [path, card.id])
		CardData.TYPE_TACTIC:
			if card.row != "":
				load_errors.append("计策卡行字段应为空（%s）：%s" % [path, card.id])
			if card.power != 0:
				load_errors.append("计策卡战力应为 0（%s）：%s" % [path, card.id])
			if card.unit_type != "":
				load_errors.append("计策卡兵种字段应为空（%s）：%s" % [path, card.id])
			if card.is_leader:
				load_errors.append("计策卡不应标记为领袖（%s）：%s" % [path, card.id])
		_:
			load_errors.append("未知卡牌类型（%s）：%s -> '%s'" % [path, card.id, card.card_type])


func _check_faction_count(faction: String, list: Array[CardData], path: String) -> void:
	var normal_units := 0
	var heroes := 0
	var tactics := 0
	var leaders := 0
	for card in list:
		match card.card_type:
			CardData.TYPE_UNIT:
				if card.is_hero():
					heroes += 1
				else:
					normal_units += 1
			CardData.TYPE_LEADER:
				leaders += 1
			CardData.TYPE_TACTIC:
				tactics += 1

	_expect(faction, "卡牌总数", list.size(), CARDS_PER_FACTION, path)
	_expect(faction, "普通单位卡", normal_units, NORMAL_UNITS_PER_FACTION, path)
	_expect(faction, "英杰卡", heroes, HEROES_PER_FACTION, path)
	_expect(faction, "计策卡", tactics, TACTICS_PER_FACTION, path)
	_expect(faction, "领袖卡", leaders, LEADERS_PER_FACTION, path)


func _expect(faction: String, label: String, actual: int, expected: int, path: String) -> void:
	if actual != expected:
		load_errors.append("%s %s应为 %d 张，实际 %d（%s）" % [faction, label, expected, actual, path])
