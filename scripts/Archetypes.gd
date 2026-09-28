extends RefCounted
class_name Archetypes

## 「系统推荐流派」数据层（UI 后置）。
##
## 数据来源：`res://data/archetypes.json`，结构为
##   { 阵营: [ { id, name, pace, role, leader, heroes[], tactics[], units{名 -> 张数}, tip }, ... ] }
##
## 本类是流派数据的**唯一读取与构造入口**：把卡名解析成卡牌 id、拼出一套合法 DeckList。
##
## 【为什么用卡名而不是 id】设计稿是按「卡名 + 张数」写的（如 锐士×3），
## 用卡名维护最直观；但卡组必须存 id（`DeckList` 的 key 就是 id），
## 所以这里做一次「阵营内卡名 → id」的解析。解析失败时**不静默跳过**，
## 而是把缺的卡名写进 load_errors 并返回 null —— 改名漏了一处就会被测试抓到。
##
## 【为什么本国自己的计策要排在通用计策前面】见 `CardDB.get_tactic_cards_by_faction`，
## 那是为了不动既有预设卡组；这里不分先后，只按名字查表。

const DATA_PATH := "res://data/archetypes.json"

## 每个流派恰好 29 张（20 普通 + 2 英杰 + 6 计策 + 1 领袖）
const DECK_SIZE := DeckRules.TOTAL

static var _data: Dictionary = {}                       # faction -> Array[Dictionary]
static var _loaded := false
static var _errors: PackedStringArray = PackedStringArray()


# ---------------- 载入 ----------------

static func load_errors() -> PackedStringArray:
	_ensure_loaded()
	return _errors


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_errors = PackedStringArray()
	_data = {}

	if not FileAccess.file_exists(DATA_PATH):
		_errors.append("流派数据文件不存在：%s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("流派数据不是合法的 JSON 对象：%s" % DATA_PATH)
		return

	for key in parsed.keys():
		var faction := str(key)
		if not CardData.FACTIONS.has(faction):
			_errors.append("流派数据里出现未知阵营：%s" % faction)
			continue
		var list: Variant = parsed[key]
		if typeof(list) != TYPE_ARRAY:
			_errors.append("阵营 %s 的流派分组不是数组。" % faction)
			continue
		var items: Array[Dictionary] = []
		for entry in list:
			if typeof(entry) != TYPE_DICTIONARY:
				_errors.append("阵营 %s 存在非对象的流派条目。" % faction)
				continue
			items.append(entry)
		_data[faction] = items


## 强制重新读盘（测试用；运行时数据不会变）。
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


# ---------------- 查询 ----------------

static func list_for(faction: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	var items: Variant = _data.get(faction, [])
	if items is Array:
		out.assign(items)
	return out


static func count_for(faction: String) -> int:
	return list_for(faction).size()


## 该阵营全部流派的名称（UI 列表用）。
static func titles_for(faction: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item in list_for(faction):
		out.append(title_of(item))
	return out


static func title_of(item: Dictionary) -> String:
	return str(item.get("name", "未命名流派"))


## 「中速 · 歼灭」这类一行定位，UI 标题旁展示。
static func pace_line(item: Dictionary) -> String:
	var pace := str(item.get("pace", ""))
	var role := str(item.get("role", ""))
	if pace.is_empty():
		return role
	if role.is_empty():
		return pace
	return "%s · %s" % [pace, role]


## 流派摘要（弹窗正文）：领袖 / 英杰 / 战术要点。
static func summary(item: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("领袖：%s" % str(item.get("leader", "—")))
	lines.append("英杰：%s" % "、".join(hero_names(item)))
	var tip := str(item.get("tip", ""))
	if not tip.is_empty():
		lines.append(tip)
	return "\n".join(lines)


static func hero_names(item: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n in item.get("heroes", []):
		out.append(str(n))
	return out


## 卡牌张数合计（校验用；正常应等于 29）。
static func deck_size_of(item: Dictionary) -> int:
	var total := 1                                     # 领袖
	total += hero_names(item).size()
	total += int(item.get("tactics", []).size())
	var units: Variant = item.get("units", {})
	if typeof(units) == TYPE_DICTIONARY:
		for n in units.keys():
			total += int(units[n])
	return total


# ---------------- 构造 ----------------

## 按阵营内序号构造卡组；越界或卡名解析失败返回 null。
static func build(faction: String, index: int, db: CardDB) -> DeckList:
	var items := list_for(faction)
	if index < 0 or index >= items.size():
		return null
	return _build_one(faction, items[index], db)


static func build_by_id(faction: String, archetype_id: String, db: CardDB) -> DeckList:
	for item in list_for(faction):
		if str(item.get("id", "")) == archetype_id:
			return _build_one(faction, item, db)
	return null


static func _build_one(faction: String, item: Dictionary, db: CardDB) -> DeckList:
	var title := title_of(item)
	var deck := DeckList.new(faction, "%s · %s" % [CardData.faction_name_of(faction), title])
	var index := _name_index(faction, db)
	var missing: PackedStringArray = PackedStringArray()

	_put(deck, index, "leader", str(item.get("leader", "")), 1, missing)
	for n in item.get("heroes", []):
		_put(deck, index, "hero", str(n), 1, missing)
	for n in item.get("tactics", []):
		_put(deck, index, "tactic", str(n), 1, missing)
	var units: Variant = item.get("units", {})
	if typeof(units) == TYPE_DICTIONARY:
		for n in units.keys():
			_put(deck, index, "unit", str(n), int(units[n]), missing)

	if not missing.is_empty():
		_errors.append("%s·%s 引用了不存在的卡名：%s" % [faction, title, ", ".join(missing)])
		return null
	return deck


## 阵营内的卡名索引：{ kind -> { 卡名 -> CardData } }。
## 计策走 `get_tactic_cards_by_faction`，因此通用计策也在表里。
static func _name_index(faction: String, db: CardDB) -> Dictionary:
	var index := {"leader": {}, "hero": {}, "unit": {}, "tactic": {}}
	for card in db.get_cards_by_faction(faction):
		if card.is_hero():
			index["hero"][card.name] = card
		elif card.card_type == CardData.TYPE_LEADER:
			index["leader"][card.name] = card
		elif card.card_type == CardData.TYPE_UNIT:
			index["unit"][card.name] = card
	for card in db.get_tactic_cards_by_faction(faction):
		index["tactic"][card.name] = card
	return index


static func _put(deck: DeckList, index: Dictionary, kind: String, card_name: String,
		count: int, missing: PackedStringArray) -> void:
	if card_name.is_empty() or count <= 0:
		return
	var bucket: Dictionary = index.get(kind, {})
	if not bucket.has(card_name):
		if not missing.has(card_name):
			missing.append(card_name)
		return
	var card: CardData = bucket[card_name]
	deck.set_card_count(card.id, deck.count_of(card.id) + count)
