extends RefCounted
class_name Command

## 指令数据结构（5A 指令化改造）。
##
## 对局的所有外部操作一律表达为指令，再由 GameState.execute_command() 校验并执行。
## 这样做的好处：
##   1. 单机与联机走**同一条代码路径**，联机只是把指令多送一趟网络。
##   2. 指令可序列化（to_dict / from_dict），便于网络传输与录像回放。
##   3. 校验集中在 execute_command 里，非法指令返回中文原因而不是静默失败。
##
## 指令内只携带**可序列化的数据**（卡牌 id、行 id、下标），不携带 CardData 对象，
## 因为对象引用无法跨网络传输。接收方用 card_id 在自己这边的状态里查实例。

# ---------------- 指令类型 ----------------

const CMD_MULLIGAN := "mulligan"           # 换牌：player, card_ids
const CMD_PLAY_CARD := "play_card"         # 打出单位牌：player, card_id, row, insert_index
const CMD_PLAY_TACTIC := "play_tactic"     # 打出计策牌：player, card_id
const CMD_PASS := "pass"                   # Pass：player
const CMD_ADVANCE_ROUND := "advance_round" # 局末继续：无参

const TYPES := [
	CMD_MULLIGAN, CMD_PLAY_CARD, CMD_PLAY_TACTIC, CMD_PASS, CMD_ADVANCE_ROUND,
]

# ---------------- 字段 ----------------

var type: String = ""
var player: int = -1
var card_id: String = ""
## 换牌用：要换掉的卡牌 id 列表
var card_ids: Array[String] = []
## 打单位牌用
var row: String = ""
var insert_index: int = -1
## 指令序号（5E 乱序/重复包处理用；0 表示未编号，单机模式不校验）
var seq: int = 0


func _init(p_type: String = "") -> void:
	type = p_type


# ---------------- 静态构造 ----------------

static func mulligan(p_player: int, p_card_ids: Array[String]) -> Command:
	var cmd := Command.new(CMD_MULLIGAN)
	cmd.player = p_player
	cmd.card_ids.assign(p_card_ids)
	return cmd


static func play_card(p_player: int, p_card_id: String, p_row: String, p_insert_index: int = -1) -> Command:
	var cmd := Command.new(CMD_PLAY_CARD)
	cmd.player = p_player
	cmd.card_id = p_card_id
	cmd.row = p_row
	cmd.insert_index = p_insert_index
	return cmd


static func play_tactic(p_player: int, p_card_id: String) -> Command:
	var cmd := Command.new(CMD_PLAY_TACTIC)
	cmd.player = p_player
	cmd.card_id = p_card_id
	return cmd


## 注意：方法名不能叫 pass —— `pass` 是 GDScript 保留字。
static func pass_turn(p_player: int) -> Command:
	var cmd := Command.new(CMD_PASS)
	cmd.player = p_player
	return cmd


static func advance_round() -> Command:
	return Command.new(CMD_ADVANCE_ROUND)


# ---------------- 序列化 ----------------

func to_dict() -> Dictionary:
	return {
		"type": type,
		"player": player,
		"card_id": card_id,
		"card_ids": _ids_to_array(),
		"row": row,
		"insert_index": insert_index,
		"seq": seq,
	}


static func from_dict(data: Dictionary) -> Command:
	var cmd := Command.new(str(data.get("type", "")))
	cmd.player = int(data.get("player", -1))
	cmd.card_id = str(data.get("card_id", ""))
	cmd.card_ids.clear()
	var ids: Variant = data.get("card_ids", [])
	if ids is Array:
		for one in ids:
			cmd.card_ids.append(str(one))
	cmd.row = str(data.get("row", ""))
	cmd.insert_index = int(data.get("insert_index", -1))
	cmd.seq = int(data.get("seq", 0))
	return cmd


func _ids_to_array() -> Array:
	var out: Array = []
	for one in card_ids:
		out.append(one)
	return out


## 人类可读的描述（战报 / 调试用）。
func describe() -> String:
	match type:
		CMD_MULLIGAN:
			return "换牌 %d 张" % card_ids.size()
		CMD_PLAY_CARD:
			return "打出 %s 到 %s" % [card_id, row]
		CMD_PLAY_TACTIC:
			return "使用计策 %s" % card_id
		CMD_PASS:
			return "Pass"
		CMD_ADVANCE_ROUND:
			return "继续"
	return "未知指令"


func is_valid_type() -> bool:
	return TYPES.has(type)


## 带上序号的副本（发送前调用）。
func with_seq(p_seq: int) -> Command:
	seq = p_seq
	return self


func duplicate_command() -> Command:
	return Command.from_dict(to_dict())
