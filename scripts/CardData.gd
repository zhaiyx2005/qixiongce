extends Resource
class_name CardData

## 《七雄策》卡牌数据定义（数据层，不含任何游戏逻辑）
##
## 四类卡：
##   - unit   单位卡（含英杰）：有阵营、兵种、战力、合法行
##   - leader 领袖卡：有阵营、无行、无战力，开局能力
##   - tactic 计策卡：不占行、无战力、打出即结算
##
## ability_id 表示该卡自带的能力（共 46 个），本阶段只做数据落库，
## 效果实现在 4C / 4D / 4E。

# ---------------- 常量：阵营 ----------------
## 战国七雄。每个阵营都有独立的 45 张卡表（见 data/*_cards.json）。
const FACTION_QIN := "qin"     # 秦
const FACTION_QI := "qi"       # 齐
const FACTION_CHU := "chu"     # 楚
const FACTION_YAN := "yan"     # 燕
const FACTION_HAN := "han"     # 韩
const FACTION_ZHAO := "zhao"   # 赵
const FACTION_WEI := "wei"     # 魏

## 稳定的展示顺序（选择界面 / 牌库编辑按钮组都按它排）。
## 【为什么单独定一个顺序】字典与常量声明顺序在某些场合不保证稳定，
## 界面上国家按钮的排列必须每次都一样，否则玩家会觉得"按钮乱跳"。
const FACTIONS := [
	FACTION_QIN, FACTION_QI, FACTION_CHU, FACTION_YAN, FACTION_HAN, FACTION_ZHAO, FACTION_WEI,
]

## 阵营 -> 单字国名（UI 与战报通用）
const FACTION_NAMES := {
	FACTION_QIN: "秦", FACTION_QI: "齐", FACTION_CHU: "楚", FACTION_YAN: "燕",
	FACTION_HAN: "韩", FACTION_ZHAO: "赵", FACTION_WEI: "魏",
}


## 该阵营的单字国名；未知阵营回退为原名。
static func faction_name_of(faction: String) -> String:
	return str(FACTION_NAMES.get(faction, faction))


## 从除 exclude 之外的阵营里随机取一个。
## 【为什么要这个】单机时 AI 用「除玩家之外」的阵营；联机时客户端用「除主机之外」的阵营。
## 七国之下"另一个阵营"不再唯一，必须显式随机（并让调用方把种子随广播下发）。
static func random_other_faction(rng: RandomNumberGenerator, exclude: String) -> String:
	var pool: Array[String] = []
	for f in FACTIONS:
		if f != exclude:
			pool.append(f)
	if pool.is_empty():
		return FACTION_QIN
	return pool[rng.randi_range(0, pool.size() - 1)]


# ---------------- 常量：卡牌类型 ----------------
const TYPE_UNIT := "unit"
const TYPE_LEADER := "leader"
const TYPE_TACTIC := "tactic"
const TYPES := [TYPE_UNIT, TYPE_LEADER, TYPE_TACTIC]

# ---------------- 常量：行 ----------------
const ROW_MELEE := "melee"        # 近战行
const ROW_RANGED := "ranged"      # 远程行
const ROW_GARRISON := "garrison"  # 守军行
const ROWS := [ROW_MELEE, ROW_RANGED, ROW_GARRISON]

# ---------------- 常量：兵种 ----------------
const UNIT_HERO := "hero"          # 英杰
const UNIT_INFANTRY := "infantry"  # 步卒
const UNIT_ARCHER := "archer"      # 弓弩手
const UNIT_CAVALRY := "cavalry"    # 骑兵
const UNIT_TYPES := [UNIT_HERO, UNIT_INFANTRY, UNIT_ARCHER, UNIT_CAVALRY]

## 兵种 -> 合法行。row 字段仅作展示提示，合法行一律由此表推导。
const UNIT_TYPE_ROWS := {
	UNIT_HERO: [ROW_MELEE, ROW_RANGED, ROW_GARRISON],
	UNIT_INFANTRY: [ROW_MELEE, ROW_GARRISON],
	UNIT_ARCHER: [ROW_RANGED, ROW_GARRISON],
	UNIT_CAVALRY: [ROW_MELEE, ROW_RANGED],
}

## category() 的取值
const CATEGORY_LEADER := "leader"
const CATEGORY_TACTIC := "tactic"
const CATEGORIES := [
	CATEGORY_LEADER, CATEGORY_TACTIC,
	UNIT_HERO, UNIT_INFANTRY, UNIT_ARCHER, UNIT_CAVALRY,
]

# ---------------- 字段 ----------------
@export var id: String = ""                    # 唯一标识
@export var name: String = ""                  # 卡牌名称
@export var faction: String = ""               # 阵营：qin / zhao
@export var card_type: String = TYPE_UNIT      # 类型：unit / leader / tactic
@export var unit_type: String = ""             # 兵种：hero / infantry / archer / cavalry（非单位卡为空）
@export var row: String = ""                   # 默认行：melee / ranged / garrison（领袖、计策为空）
@export var power: int = 0                     # 基础战力
@export var is_leader: bool = false            # 是否领袖
@export var description: String = ""           # 描述
@export var ability_id: String = ""            # 能力标识
@export var faction_ability_id: String = ""    # 阵营能力占位


## 是否英杰牌（战力固定，不受任何增减效果影响）。
func is_hero() -> bool:
	return card_type == TYPE_UNIT and unit_type == UNIT_HERO


## 是否计策牌。
func is_tactic() -> bool:
	return card_type == TYPE_TACTIC


## 是否单位牌（含英杰）。
func is_unit() -> bool:
	return card_type == TYPE_UNIT


## 该卡的可落行列表。非单位卡返回空数组。
func legal_rows() -> Array[String]:
	var result: Array[String] = []
	if card_type != TYPE_UNIT:
		return result
	var rows: Variant = UNIT_TYPE_ROWS.get(unit_type, null)
	if rows == null:
		return result
	result.assign(rows)
	return result


## 该卡能否落在指定行。
func can_place_in(row_id: String) -> bool:
	return legal_rows().has(row_id)


## 卡牌分类：leader / hero / infantry / archer / cavalry / tactic。
## 未知组合返回空串。
func category() -> String:
	if card_type == TYPE_LEADER:
		return CATEGORY_LEADER
	if card_type == TYPE_TACTIC:
		return CATEGORY_TACTIC
	if card_type == TYPE_UNIT:
		return unit_type
	return ""


## 复制一份独立的卡牌实例（同 id、同数值，但是不同的对象）。
##
## 【为什么必须复制】对局状态（永久增益 permanents、场上回合数、曾收回标记等）
## 一律以「CardData 对象」为 key 存在 PlayerState 里。如果双方牌库共用同一个
## CardData 实例（例如镜像对局、或两边都带了同一张卡），
## GameState.owner_of() 只能返回 players 里第一个“拥有”它的玩家，
## 导致「修正战力时打错人」——实测会让伤害类计策反过来打到自己。
## 因此每套卡组构筑时必须为每张牌生成独立实例。
func duplicate_card() -> CardData:
	var copy := CardData.new()
	copy.id = id
	copy.name = name
	copy.faction = faction
	copy.card_type = card_type
	copy.unit_type = unit_type
	copy.row = row
	copy.power = power
	copy.is_leader = is_leader
	copy.description = description
	copy.ability_id = ability_id
	copy.faction_ability_id = faction_ability_id
	return copy
