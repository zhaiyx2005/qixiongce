extends RefCounted
class_name DeckList

## 卡组数据层（UI 后置）：记录 “卡牌 id -> 张数”，支持增删改查、构筑校验、存读 JSON。
## 一套合法卡组 = ≥22 张单位卡 + 1 张领袖 + 特殊卡 ≤10（Demo 为 0），同名卡最多 3 张。

var faction: String = ""
var deck_name: String = ""

var _order: Array[String] = []
var _counts: Dictionary = {}


func _init(p_faction: String = "", p_name: String = "") -> void:
	faction = p_faction
	deck_name = p_name


# ---------------- 编辑 ----------------

func add_card(card_id: String, count: int = 1) -> void:
	if count <= 0:
		return
	if not _counts.has(card_id):
		_order.append(card_id)
	_counts[card_id] = count_of(card_id) + count


func set_card_count(card_id: String, count: int) -> void:
	if count <= 0:
		remove_card(card_id)
		return
	if not _counts.has(card_id):
		_order.append(card_id)
	_counts[card_id] = count


func remove_card(card_id: String) -> void:
	if _counts.has(card_id):
		_counts.erase(card_id)
		_order.erase(card_id)


func clear() -> void:
	_order.clear()
	_counts.clear()


func count_of(card_id: String) -> int:
	return int(_counts.get(card_id, 0))


## 卡组总张数（含领袖）
func size() -> int:
	var total := 0
	for card_id in _order:
		total += count_of(card_id)
	return total


func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_order)
	return out


## [{ "id": ..., "count": ... }, ...]
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for card_id in _order:
		out.append({"id": card_id, "count": count_of(card_id)})
	return out


func clone() -> DeckList:
	var copy := DeckList.new(faction, deck_name)
	for card_id in _order:
		copy.set_card_count(card_id, count_of(card_id))
	return copy


# ---------------- 展开为卡牌实例 ----------------

## 展开成对局用的卡牌实例数组。
##
## 每张牌都生成**独立的 CardData 实例**（copy），而不是共用 CardDB 里的原型。
## 原因见 CardData.duplicate_card() 的注释：对局状态以 CardData 对象为 key，
## 共用实例会让 owner_of() 判错归属，使伤害类效果打到自己身上。
func build_cards(db: CardDB) -> Array[CardData]:
	var out: Array[CardData] = []
	for card_id in _order:
		var card := db.get_card_by_id(card_id)
		if card == null:
			push_warning("卡组中存在未知卡牌 id：%s" % card_id)
			continue
		for _i in range(count_of(card_id)):
			out.append(card.duplicate_card())
	return out


# ---------------- 序列化 ----------------

func to_dict() -> Dictionary:
	return {
		"faction": faction,
		"name": deck_name,
		"cards": entries(),
	}


static func from_dict(data: Dictionary) -> DeckList:
	var deck := DeckList.new(str(data.get("faction", "")), str(data.get("name", "")))
	var cards: Variant = data.get("cards", [])
	if cards is Array:
		for entry in cards:
			if entry is Dictionary:
				deck.add_card(str(entry.get("id", "")), int(entry.get("count", 1)))
	return deck


## 存到磁盘（建议用 user://decks/xxx.json）
func save_to_file(path: String) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()
	return OK


## 读盘；失败返回 null
static func load_from_file(path: String) -> DeckList:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary):
		return null
	return from_dict(parsed)


# ---------------- 预设卡组 ----------------

## 自定义卡组固定存放位置：user://decks/qin.json / zhao.json
const DECK_DIR := "user://decks"

## 单位卡展示排序：行固定顺序（近战 → 远程 → 守军）
const ROW_ORDER := {
	CardData.ROW_MELEE: 0,
	CardData.ROW_RANGED: 1,
	CardData.ROW_GARRISON: 2,
}


## 统一的单位卡排序（牌库编辑卡池、已选清单共用）：
## 1) 行：近战 → 远程 → 守军　2) 战力降序　3) id 升序（稳定、可复现）
## 不修改传入数组，返回排好序的新数组。
static func sort_units(cards: Array[CardData]) -> Array[CardData]:
	var out: Array[CardData] = []
	out.assign(cards)
	out.sort_custom(func(a: CardData, b: CardData) -> bool:
		var ra: int = ROW_ORDER.get(a.row, 9)
		var rb: int = ROW_ORDER.get(b.row, 9)
		if ra != rb:
			return ra < rb
		if a.power != b.power:
			return a.power > b.power
		return a.id < b.id)
	return out


static func path_for(faction: String) -> String:
	return "%s/%s.json" % [DECK_DIR, faction]


## 读取某阵营的自定义卡组；不存在或非法时返回 null（调用方回退到预设）。
static func load_for_faction(faction: String, db: CardDB) -> DeckList:
	var deck := load_from_file(path_for(faction))
	if deck == null:
		return null
	deck.faction = faction
	if not DeckRules.validate(deck, db).is_empty():
		return null
	return deck


## 预设卡组：严格按新构筑规格凑出 29 张。
##   普通单位 20（按行比例取，最长余数法，同名不超 3）
##   + 英杰 2（取卡池前 2 张）
##   + 计策 6（取卡池前 6 张，同名不超 3）
##   + 领袖 1
##
## 行内取牌排序：**先按战力降序，同战力再按能力档位**，最后 id 升序。
## 档位只做同战力破平，避免出现「同战力时两阵营运气性拿到不同强度能力」
## 造成的隐性优势（曾出现 102 : 100 导致秦胜率 61%）。
const ABILITY_VALUE_TIER := {
	"qin_merit": 3, "qi_combined": 3, "chu_depth": 3, "yan_frontier": 3,
	"han_crossbow": 3, "zhao_mobile": 3, "wei_drill": 3,
	"inf_comrade": 3, "inf_formation": 3, "arc_formation": 3, "cav_ironride": 3,
	"inf_deathwish": 2, "inf_veteran": 2,
	"inf_valor": 1, "arc_volley": 1, "arc_precise": 1, "arc_cover": 1,
	"cav_raid": 1, "cav_trample": 1, "cav_charge": 1, "inf_summon": 1,
}


static func ability_tier(card: CardData) -> int:
	if card == null:
		return 0
	return int(ABILITY_VALUE_TIER.get(card.ability_id, 0))


static func preset_for(faction: String, db: CardDB) -> DeckList:
	var deck := DeckList.new(faction, "%s 预设卡组" % CardData.faction_name_of(faction))

	# ---- 普通单位 20 张：按行比例分配名额 ----
	var pool := db.get_normal_unit_cards_by_faction(faction)
	var need: int = DeckRules.NORMAL_UNITS
	var total := maxi(pool.size(), 1)
	var accumulated := 0.0
	var taken := 0
	var name_used: Dictionary = {}
	for row in CardData.ROWS:
		var row_cards: Array[CardData] = []
		for card in pool:
			if card.row == row:
				row_cards.append(card)
		row_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
			if a.power != b.power:
				return a.power > b.power
			var ta := ability_tier(a)
			var tb := ability_tier(b)
			if ta != tb:
				return ta > tb
			return a.id < b.id)
		accumulated += float(need) * float(row_cards.size()) / float(total)
		var want := int(round(accumulated)) - taken
		taken += want
		var placed := 0
		for card in row_cards:
			if placed >= want:
				break
			var used := int(name_used.get(card.name, 0))
			if used >= DeckRules.MAX_COPIES_PER_NAME:
				continue
			var copies := mini(DeckRules.MAX_COPIES_PER_NAME - used, want - placed)
			deck.set_card_count(card.id, copies)
			name_used[card.name] = used + copies
			placed += copies
	if deck.size() < need:
		_trim_or_fill_normals(deck, pool, need, name_used)

	# ---- 英杰 2 张 ----
	var heroes := db.get_hero_cards_by_faction(faction)
	for i in range(mini(DeckRules.HEROES, heroes.size())):
		deck.set_card_count(heroes[i].id, 1)

	# ---- 计策 6 张 ----
	var tactics := db.get_tactic_cards_by_faction(faction)
	var t_used: Dictionary = {}
	var t_count := 0
	for card in tactics:
		if t_count >= DeckRules.TACTICS:
			break
		var used := int(t_used.get(card.name, 0))
		if used >= DeckRules.MAX_COPIES_PER_NAME:
			continue
		# 预设展示六种不同计策，避免三份抽二牌主导国家强度。
		var copies := 1
		deck.set_card_count(card.id, copies)
		t_used[card.name] = used + copies
		t_count += copies

	# ---- 领袖 1 张 ----
	var leaders := db.get_leader_cards(faction)
	if not leaders.is_empty():
		deck.set_card_count(leaders[0].id, 1)

	return deck


## 按行比例取不满 20 张时的兜底：从整个普通单位池里按战力降序补足。
static func _trim_or_fill_normals(deck: DeckList, pool: Array[CardData], need: int,
		name_used: Dictionary) -> void:
	var sorted := sort_units(pool)
	for card in sorted:
		if deck.size() >= need:
			break
		var used := int(name_used.get(card.name, 0))
		if used >= DeckRules.MAX_COPIES_PER_NAME:
			continue
		var room := DeckRules.MAX_COPIES_PER_NAME - used
		var missing := need - deck.size()
		var copies := mini(room, missing)
		deck.set_card_count(card.id, deck.count_of(card.id) + copies)
		name_used[card.name] = used + copies
