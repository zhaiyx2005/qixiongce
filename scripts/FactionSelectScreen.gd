extends Control
class_name FactionSelectScreen

## 阵营选择：战国七雄（秦 / 齐 / 楚 / 燕 / 韩 / 赵 / 魏）。
##
## 单机：选定后由电脑使用**其余六国之一**（随机，但由对局种子派生 → 可复现），
##       `faction_chosen` 直接开始对局。
##
## 联机（5D）：
##   - 主机先选，选完把「主机阵营 + 指派给客户端的阵营 + 种子」一起广播；
##   - 客户端**不能选**，只等主机广播；
##   - 双方都确认后再一起进入换牌。
##
## 【为什么联机要让主机指派对手阵营】两国时代「客户端 = 主机的反面」是唯一解；
## 七国之下同一件事有 6 种可能，客户端无法自行推导，必须由主机明确指定。
## 这里用 `net_mode` + `net_is_host` 两个开关表达三种状态，不做状态机。

signal faction_chosen(faction: String)
## 联机客户端专有：先从广播里把种子带出来，再发 faction_chosen 起局。
## 【为什么带三个参数】七国下客户端必须同时知道「自己用哪国」和「对手是哪国」，
## 只有阵营名才能推出对手（否则客户端只能看到自己那一半信息）。
signal faction_chosen_seed(faction: String, opp_faction: String, seed_value: int)
signal back

## 各国一句话特色（显示在阵营卡上）。四个字以内，保证 168px 宽的卡放得下。
const FACTION_TAGLINES := {
	CardData.FACTION_QIN: "强弩压阵",
	CardData.FACTION_QI: "技击富庶",
	CardData.FACTION_CHU: "带甲百万",
	CardData.FACTION_YAN: "苦寒坚守",
	CardData.FACTION_HAN: "劲弩之利",
	CardData.FACTION_ZHAO: "胡服骑射",
	CardData.FACTION_WEI: "武卒之勇",
}

## 七张阵营卡的尺寸与间距：7 × 168 + 6 × 12 = 1248，正好放进 1280 宽的窗口。
const CARD_SIZE := Vector2(168, 150)
const CARD_GAP := 12

## 联机模式（由 Main 在进入前设置）
var net_mode: bool = false
## 本方是否为联机主机（主机可选，客户端只读等待）
var net_is_host: bool = true
## 本方玩家下标（主机 0 / 客户端 1）
var net_my_index: int = 0
## 本局随机种子（联机时由主机决定并广播，保证双方牌序一致）
var net_seed: int = 0

var _title: Label
var _desc: Label
var _status: Label
var _cards: Array = []
var _back_button: Button
## 已选阵营（空串表示未选）
var _picked: String = ""
## 对手/远端阵营（联机时由主机指派或广播填入）
var _opp_picked: String = ""
## 卡牌库：用来读各国领袖名（唯一数据来源，避免在 UI 里硬编码君主名）
var db: CardDB = null


func setup(p_db: CardDB) -> void:
	db = p_db


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if net_mode:
		_connect_net_signals()
	_build()
	_refresh_ui()


func _exit_tree() -> void:
	if net_mode:
		_connect_net_signals(true)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	_title = UiKit.make_label("选 择 你 的 阵 营", 40, UiKit.COL_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_desc = UiKit.make_label("", 14, UiKit.COL_TEXT_DIM)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.custom_minimum_size = Vector2(760, 0)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc)

	box.add_child(UiKit.spacer(10))

	# 七国并立：单行排开。国家顺序固定走 CardData.FACTIONS，避免每次进界面位置乱跳。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", CARD_GAP)
	box.add_child(row)

	_cards = []
	for faction in CardData.FACTIONS:
		var btn := _make_faction_card(faction)
		row.add_child(btn)
		_cards.append([faction, btn])

	box.add_child(UiKit.spacer(8))

	_status = UiKit.make_label("", 15, UiKit.COL_TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(760, 0)
	box.add_child(_status)

	box.add_child(UiKit.spacer(6))

	_back_button = UiKit.make_button("返回主菜单", UiKit.COL_TEXT_DIM, 16, Vector2(200, 44))
	_back_button.pressed.connect(_on_back_pressed)
	box.add_child(_back_button)


## 一张阵营卡：国名（大字） + 该国首位领袖 + 一句话特色。
func _make_faction_card(faction: String) -> Button:
	var accent := UiKit.faction_color(faction)
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	UiKit.style_button(button, accent, 22)
	button.pressed.connect(func(): _on_faction_card_pressed(faction))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var name_label := UiKit.make_label(UiKit.faction_name(faction), 40, accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var leader := UiKit.make_icon_label(UiKit.ICON_LEADER, _leader_name(faction), 13, UiKit.COL_TEXT, 16)
	leader.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(leader)

	var tag := UiKit.make_label(str(FACTION_TAGLINES.get(faction, "")), 12, UiKit.COL_TEXT_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)

	return button


## 该阵营首位领袖的名字（用于阵营卡上的小字）。
## 【为什么从 db 读】阵营卡上原本硬编码「秦孝公」「赵武灵王」，七国扩展后
## 就成了 7 处重复且容易和数据文件脱节。统一从卡表取 leader_01。
func _leader_name(faction: String) -> String:
	if db != null:
		var leaders := db.get_leader_cards(faction)
		if not leaders.is_empty():
			return leaders[0].name
	return UiKit.faction_name(faction)


# ---------------- 交互 ----------------

func _on_faction_card_pressed(faction: String) -> void:
	if net_mode and not net_is_host:
		_status.text = "等待主机选择阵营……"
		_status.add_theme_color_override("font_color", UiKit.COL_TEXT_DIM)
		return
	if net_mode and not _picked.is_empty():
		# 主机已选，不允许改（客户端已按此结成对局）
		UiKit.sfx("error")
		_status.text = "阵营已确定，无法更改。"
		_status.add_theme_color_override("font_color", UiKit.COL_LOSE)
		return

	UiKit.sfx("card_place", 0.04)
	_picked = faction

	if not net_mode:
		_refresh_ui()
		faction_chosen.emit(faction)
		return

	# ---- 联机主机 ----
	# 【顺序极重要】必须先广播、再让本机开局，理由是：
	#   广播这条 RPC 在 send_faction_choice() 内立即完成投递；
	#   随后 Main 走 _start_net_match()，它会立刻把初始权威状态推给客户端。
	#   客户端收到阵营后也会开局并主动 request_state()，形成兜底。
	#
	# 对手阵营由主机指派：从其余 6 国里随机取一个，随机源由 net_seed 派生
	# （同一种子必然指派同一对手，便于复现与排查）。
	var picker := RandomNumberGenerator.new()
	picker.seed = net_seed ^ 0x2C9E4B17
	_opp_picked = CardData.random_other_faction(picker, faction)

	var nm := _net()
	if nm != null and nm.is_host():
		nm.send_faction_choice(faction, _opp_picked, net_seed)

	_refresh_ui()
	# 【死锁修复】主机**不等任何 ack**，广播完就自己开局。
	# 曾经这里只广播、不发射 faction_chosen，于是 Main 永远不会调 _start_net_match，
	# 主机停在「等待对手确认」；而客户端收到广播后已经进了对局界面等状态 ——
	# 双方互等，形成死锁。协议上不存在 ack，主机是权威方，自己决定开局即可。
	faction_chosen_seed.emit(faction, _opp_picked, net_seed)
	faction_chosen.emit(faction)


func _on_back_pressed() -> void:
	if net_mode:
		var nm := _net()
		if nm != null:
			nm.disconnect_peer()
	back.emit()


func _refresh_ui() -> void:
	if not net_mode:
		_title.text = "选 择 你 的 阵 营"
		_desc.text = "七雄并立，各有兵种与计策之长。选定后由电脑使用其余六国之一。" \
			+ "每方从 30 张单位卡池中构筑 29 张（20 张普通单位 + 2 张英杰 + 6 张计策）+ 1 张领袖。"
		_status.text = ""
		_back_button.text = "返回主菜单"
		for pair in _cards:
			pair[1].disabled = false
		return

	# ---- 联机 ----
	_back_button.text = "断开并返回"
	if net_is_host:
		_title.text = "选 择 你 的 阵 营"
		_desc.text = "你是主机，先选阵营；系统会从其余六国中为你指派一个对手阵营，" \
			+ "双方随即进入换牌阶段。"
		if _picked.is_empty():
			_status.text = "请选择你的阵营。"
		else:
			_status.text = "你使用「%s」，对手为「%s」，正在进行对局……" % [
				UiKit.faction_name(_picked), UiKit.faction_name(_opp_picked)]
		_status.add_theme_color_override("font_color", UiKit.COL_GOLD)
	else:
		_title.text = "等 待 主 机 选 择"
		_desc.text = "你是客户端，阵营由主机指派；主机选定后你会自动获得自己的阵营。"
		if not _picked.is_empty():
			_status.text = "你的阵营是「%s」，对手为「%s」。即将进入换牌阶段……" % [
				UiKit.faction_name(_picked), UiKit.faction_name(_opp_picked)]
			_status.add_theme_color_override("font_color", UiKit.COL_GOLD)

	# 主机已选 / 客户端不可选 -> 禁用全部阵营按钮
	for pair in _cards:
		var clickable := net_is_host and _picked.is_empty()
		pair[1].disabled = not clickable


# ---------------- 网络 ----------------

func _connect_net_signals(unbind := false) -> void:
	var nm := _net()
	if nm == null:
		return
	var pairs := [
		[nm.faction_choice_received, _on_remote_faction_choice],
		[nm.disconnected, _on_net_disconnected],
	]
	for pair in pairs:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if unbind:
			if sig.is_connected(cb):
				sig.disconnect(cb)
		else:
			if not sig.is_connected(cb):
				sig.connect(cb)


## 客户端：收到主机下发的「双方阵营 + 种子」-> 直接用主机指派的阵营开局。
func _on_remote_faction_choice(host_faction: String, client_faction: String,
		seed_value: int) -> void:
	_opp_picked = host_faction
	_picked = client_faction
	net_seed = seed_value
	_refresh_ui()
	# 顺序敏感：先发种子，再发起局信号（Main 在起局时会用到 _net_seed）
	faction_chosen_seed.emit(client_faction, host_faction, seed_value)
	faction_chosen.emit(client_faction)


func _on_net_disconnected() -> void:
	_status.text = "与主机的连接已断开。"
	_status.add_theme_color_override("font_color", UiKit.COL_LOSE)
	for pair in _cards:
		pair[1].disabled = true
	_back_button.disabled = false


## 联机时使用的 NetworkManager。默认从场景树取 Autoload；
## 测试可以在 add_child 之前注入一个独立实例（同进程双实例隔离用）。
var net_override: Node = null


func _net() -> Node:
	if net_override != null:
		return net_override
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("NetworkManager")
