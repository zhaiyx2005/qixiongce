extends Control
class_name MatchScreen

## 对局界面（第三阶段：昆特牌式四角布局）
##   顶部带：对方领袖 + 手牌数 + 总战力 + 城池 ........ 对方牌库 / 弃牌堆
##   中央：三行战场（每行左侧圆形行战力）
##   底部带：己方领袖 + 手牌数 + 总战力 + 城池 ........ 己方牌库 / 弃牌堆
##   最下方：手牌区 + 操作按钮区
## 逻辑全部来自 GameState，本文件只负责显示与交互。

signal exit_to_menu

## 城墙装饰条高度。
## 【为什么是 7 而不是 14】1280×800 窗口下，对局界面各段最小高度实测合计
## 780 + 间距 18 + 上下边距 16 = 814，比 800 高出 14px —— 手牌带底边会落到
## y=806，最下面 6px 被窗口裁掉（真实渲染验证过，不是理论推算）。
## 城墙只是装饰，从 14 收到 7（两个半场各省 7px）正好补平这 14px，
## 同时不动信息带/战场行/手牌区的尺寸，视觉损失最小。
const WALL_HEIGHT := 7
const HAND_AREA_WIDTH := 800
const AI_THINK_TIME := 0.7
## 上半场（对手）暗红/暖褐，下半场（己方）暗蓝/冷褐，对比度压低不影响读牌
const FIELD_TOP_COLOR := Color("31201b")
const FIELD_BOTTOM_COLOR := Color("1b2230")
const ROW_TINT := Color(1, 1, 1, 0.045)
const WALL_MARK := "__wall__"

var db: CardDB
var state: GameState = null
var human_faction: String = CardData.FACTION_QIN
## 对局随机种子（0 = 随机）。固定它即可复现整场对局。
var match_seed: int = 0
## 是否联机对局（5C）。联机时：本地玩家由 NetworkManager.local_player 决定，
## 远程玩家只显示不可操作，且不启用 AI。
var net_mode: bool = false
## 本方玩家下标（单机恒为 0；联机时主机 0 / 客户端 1）
var my_index: int = 0
## 远端玩家下标
var opp_index: int = 1

var _row_views: Array = [{}, {}]
var _hand_box: HBoxContainer
var _leader_slots: Array = []
var _hand_labels: Array = []
var _power_labels: Array = []
var _city_labels: Array = []
var _deck_labels: Array = []
var _discard_labels: Array = []
var _hint_label: Label
var _pass_button: Button
var _use_tactic_button: Button
## 当前选中的计策（单击手牌中的计策卡设置）
var _selected_tactic: CardData = null

var _mulligan_screen: Control
var _mulligan_box: HBoxContainer
var _mulligan_hint: Label
var _mulligan_button: Button
var _selected: Array[CardData] = []

var _round_popup: Control
var _round_box: VBoxContainer
var _match_popup: Control
var _match_box: VBoxContainer
var _info_popup: Control
var _info_box: VBoxContainer

# ---------------- 结算弹窗去重（联机客户端专用） ----------------
# 客户端不走 GameState 的结算代码，round_ended / match_ended 在客户端不会发射，
# 所以由 _on_state_received() 按「本局编号」补弹窗。这两个变量记录已经弹过的局号，
# 避免同一结算被重发的状态包反复弹出来。
## 已经为哪个局号弹过小局结算（-1 = 还没弹过）
var _round_popup_shown_for: int = -1
## 终局弹窗是否已弹过
var _match_popup_shown: bool = false

var _ai_timer: Timer
var _last_message := ""
## 音效去重：已经播过「本局开始」的局号（-1 = 还没播过）。
## 单机 / 主机在 advance_round 后刷新，客户端靠权威状态包刷新 ——
## 统一在 _refresh() 里比对局号，三种模式都能各播一次。
var _sfx_last_round: int = -1
## 音效去重：上一次看到的「对手场上单位数」。
## 联机客户端的对手（主机）出牌不经过本机 _dispatch()，只能靠数量变化补一个落牌音；
## 单机 / 主机不走这条 —— AI 与玩家一样走 _dispatch()，再补一次就是双声。
var _sfx_last_opp_units: int = -1
## 音效去重：上一次看到的「双方场上单位总数」。
## 总数减少 = 有单位离场（摧毁 / 收回手牌），补一个崩解音。
var _sfx_last_total_units: int = -1
var _leader_built := false
## 联机模式：双方阵营由联机流程决定（主机先选），这里显式传入座位 → 阵营的映射
var net_faction_by_seat: Array = []
## 联机提示的一条状态行（显示「你的回合 / 等待对手」与联机身份）
var _net_status_label: Label
## 联机模式下「重开」无意义（会与远端状态分叉），这里存引用以便禁用
var _restart_button: Button
## 联机模式下「主菜单」要先断开再返回，避免残留 peer
var _menu_button: Button
## 联机客户端等主机权威状态时的遮罩（见 _show_waiting_veil）
var _wait_veil: Control = null


func setup(p_db: CardDB, p_faction: String, p_seed: int = 0) -> void:
	db = p_db
	human_faction = p_faction
	match_seed = p_seed


## 联机模式初始化（5C）。由 Main 在联机流程里调用，必须在加入场景树前设置好。
## p_my_index / p_opp_index 来自 NetworkManager（主机 0 / 客户端 1）。
## p_my_faction / p_opp_faction 由联机阵营选择决定（主机先选，客户端取另一阵营）。
func setup_network(p_db: CardDB, p_my_faction: String, p_my_index: int, p_opp_index: int,
		p_opp_faction: String = "", p_seed: int = 0) -> void:
	db = p_db
	human_faction = p_my_faction
	match_seed = p_seed
	net_mode = true
	my_index = p_my_index
	opp_index = p_opp_index

	var opp_faction := p_opp_faction
	# 兜底：调用方没给对手阵营时，取七国里第一个不是自己的。
	# 正常流程下 Main 一定会传入权威值（联机时由主机指派），这里只为防漏。
	if opp_faction.is_empty():
		for f in CardData.FACTIONS:
			if f != p_my_faction:
				opp_faction = f
				break
	# 座位 → 阵营：主机固定座位 0，客户端固定座位 1
	net_faction_by_seat = ["", ""]
	net_faction_by_seat[my_index] = p_my_faction
	net_faction_by_seat[opp_index] = opp_faction


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if db == null:
		db = CardDB.new()
	_build()
	_start_match()
	if net_mode:
		_connect_network_signals()


## 联机信号接线（5C）。主机收客户端指令并裁决、客户端收权威状态并覆盖本地。
func _connect_network_signals() -> void:
	var nm := _net()
	if nm == null:
		push_warning("[MatchScreen] 联机模式但找不到 NetworkManager，将退化为单机。")
		net_mode = false
		return
	if not nm.command_received.is_connected(_on_net_command):
		nm.command_received.connect(_on_net_command)
	if not nm.state_received.is_connected(_on_state_received):
		nm.state_received.connect(_on_state_received)
	if not nm.disconnected.is_connected(_on_net_disconnected):
		nm.disconnected.connect(_on_net_disconnected)
	if not nm.rejected.is_connected(_on_net_rejected):
		nm.rejected.connect(_on_net_rejected)
	if not nm.state_request_received.is_connected(_on_net_state_requested):
		nm.state_request_received.connect(_on_net_state_requested)

	# 客户端：界面已就绪，主动向主机要一次权威状态。
	# 主机的首次广播可能在本界面构造完成之前就发出去了（那一帧会丢），
	# 这里补一次请求即可自愈，避免客户端停在「正在同步对局……」。
	if nm.is_client():
		nm.request_state()


## 主机侧：客户端请求重发权威状态。
func _on_net_state_requested() -> void:
	var nm := _net()
	if nm == null or not nm.is_host() or state == null:
		return
	nm.send_state(state.serialize())


## 主机侧：收到来自客户端的指令，交给 NetworkManager 裁决并广播。
## 注意主机自己的指令在 _dispatch 里已经执行过了，这里只处理**来自客户端**的。
##
## 协议实现在 NetworkManager.adjudicate()，与回归测试走的是同一条代码路径。
func _on_net_command(data: Dictionary) -> void:
	if state == null or not net_mode:
		return
	var nm := _net()
	if nm == null or not nm.is_host():
		return
	if str(data.get("type", "")) == "":
		return
	var cmd := Command.from_dict(data)
	# 只接受远端座位的指令，防止伪造本方操作
	if cmd.player != opp_index:
		nm.send_reject("不能操作对手的牌。")
		return
	var result: CommandResult = nm.adjudicate(data, state)
	if result.ok:
		_refresh()
	else:
		_last_message = "对手操作无效：" + result.reason
		if _hint_label != null:
			_hint_label.text = _last_message


## 客户端侧：收到主机广播的权威状态，覆盖本地并刷新界面。
func _on_state_received(data: Dictionary) -> void:
	if state == null:
		return
	# 【先记下旧的阶段与结算快照】用来判断这一包是否「跨过了」某个结算节点。
	# 客户端不走 GameState 的结算代码（那是主机的事），所以 round_ended /
	# match_ended 这两个信号在客户端**永远不会发射**。若不在这里补一次，
	# 小局结算与终局弹窗就只在主机出现（客户端什么都看不到）。
	var prev_phase := state.phase
	var prev_round := int(state.last_round_summary.get("round", -1))
	var prev_rounds_won := _round_popup_shown_for

	state.apply_state(data, db)
	# 【关键】权威状态会重建整副牌（apply_state 里所有 CardData 都是新实例），
	# 领袖卡对象也随之换新。必须让领袖面板重建，否则会一直显示开局时
	# 用本地占位状态建出来的领袖（联机客户端表现为显示成对手的阵营）。
	_leader_built = false
	# 换牌界面里的卡同样是旧实例，需按新状态重建；
	# 但本方**已经确认过换牌**时就不要再弹回来了。
	var i_still_need_mulligan := state.phase == GameState.Phase.MULLIGAN \
		and not state.mulligan_done[my_index]
	if _mulligan_screen != null and _mulligan_screen.visible and i_still_need_mulligan:
		_open_mulligan()
	_refresh()
	# 权威状态已到，揭开等待遮罩
	_hide_waiting_veil()
	# 换牌阶段：主机可能先/后完成换牌，客户端在此同步开/关换牌界面
	if i_still_need_mulligan:
		if not _mulligan_screen.visible:
			_open_mulligan()
	elif _mulligan_screen.visible:
		_mulligan_screen.visible = false
		_selected.clear()

	# 【补齐结算弹窗】按「本局编号」去重，确保每个结算只弹一次。
	# 判据用 last_round_summary["round"]（每局唯一且随状态同步），
	# 比看 phase 更稳 —— 因为同一序号的状态包可能被重发多次。
	if state.phase == GameState.Phase.MATCH_END:
		if not _match_popup_shown and not state.match_summary.is_empty():
			_match_popup_shown = true
			_on_match_ended(state.match_summary)
	else:
		var cur_round := int(state.last_round_summary.get("round", -1))
		if cur_round >= 0 and cur_round != prev_rounds_won \
			and not state.last_round_summary.is_empty():
			_round_popup_shown_for = cur_round
			_on_round_ended(state.last_round_summary)
	# 进入新的出牌局时应把「终局弹窗」标记复位，供重开/下一局使用
	if state.phase == GameState.Phase.MULLIGAN or state.phase == GameState.Phase.PLAY:
		_match_popup_shown = false


## 客户端侧：主机判定指令非法。
func _on_net_rejected(reason: String) -> void:
	_last_message = "操作无效：" + reason
	if _hint_label != null:
		_hint_label.text = _last_message


## 任一侧：对手断开 -> 立即结束对局并提示。
func _on_net_disconnected() -> void:
	if state == null:
		return
	if _ai_timer != null:
		_ai_timer.stop()
	_last_message = "对手已断开，对局结束。"
	if _hint_label != null:
		_hint_label.text = _last_message
	_show_net_disconnect_popup()


func _show_net_disconnect_popup() -> void:
	if _match_popup == null:
		return
	for child in _match_box.get_children():
		_match_box.remove_child(child)
		child.queue_free()

	var title := UiKit.make_label("对手已断开", 30, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(title)

	var desc := UiKit.make_label("连接中断，本局结束。", 18, UiKit.COL_TEXT_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(desc)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_match_box.add_child(row)

	var menu := UiKit.make_button("返回主菜单", UiKit.COL_GOLD, 16, Vector2(170, 46))
	menu.pressed.connect(_on_menu_pressed)
	row.add_child(menu)
	_match_popup.visible = true


# ================================================================
#  开局
# ================================================================

func _start_match() -> void:
	state = GameState.new()
	state.changed.connect(_refresh)
	state.logged.connect(_on_logged)
	state.round_ended.connect(_on_round_ended)
	state.match_ended.connect(_on_match_ended)
	_selected_tactic = null
	# 结算弹窗去重标记复位（重开/新对局时）
	_round_popup_shown_for = -1
	_match_popup_shown = false
	# 音效去重标记一并复位，否则重开一局不会响「新一局开始」
	_sfx_last_round = -1
	_sfx_last_total_units = -1
	_sfx_last_opp_units = -1

	if net_mode:
		_setup_network_match()
	else:
		var human_deck := DeckList.load_for_faction(human_faction, db)
		state.start_match(human_faction, human_deck, null, match_seed)

	_refresh()
	# 换牌界面谁来开？
	#   单机       → 本机直接开
	#   联机主机   → 本机直接开（主机是权威方，它的本地状态就是权威状态）
	#   联机客户端 → **不开**，等主机广播权威状态后再开（见 _on_state_received）
	# 【曾经写错的坑】这里原本是 `if not net_mode`，把**主机也一起排除**了 ——
	# 主机永远看不到换牌界面，也就永远发不出 mulligan 指令，双方各自卡在换牌阶段。
	if state.phase == GameState.Phase.MULLIGAN and not _is_net_client():
		_open_mulligan()
	# 联机客户端：本地这份状态只是「占位」（种子/卡组构造顺序可能与主机不同），
	# 在权威状态到达之前必须盖住界面，否则玩家会看到一份错误的对局
	# （典型表现：左下角显示的是对手阵营的领袖）。
	if net_mode and _is_net_client():
		_show_waiting_veil()


## 联机开局：双方必须用**完全相同的种子与卡组构造顺序**，否则卡牌实例对不上。
## 主机先按种子开好局，然后把完整状态广播给客户端；客户端 bootstrap 后 apply_state。
## 座位 0 恒为主机、座位 1 恒为客户端 —— 双方阵营由 net_faction_by_seat 决定。
func _setup_network_match() -> void:
	var deck0_faction := ""
	var deck1_faction := ""
	if net_faction_by_seat.size() >= 2:
		deck0_faction = str(net_faction_by_seat[0])
		deck1_faction = str(net_faction_by_seat[1])
	# 兜底：任一座位阵营缺失时，从七国里补两个不同的阵营。
	# 正常流程下 Main 会把主机指派的双方阵营都填好，这里只为防漏。
	if deck0_faction.is_empty():
		deck0_faction = CardData.FACTIONS[0]
	if deck1_faction.is_empty():
		for f in CardData.FACTIONS:
			if f != deck0_faction:
				deck1_faction = f
				break
	# 【必须把 deck1_faction 传给 start_match】否则 GameState 会给座位 1
	# 随机一个阵营，而它的牌库却是 deck1（主机指派的阵营）—— 玩家阵营与牌面对不上。
	state.start_match(deck0_faction, DeckList.load_for_faction(deck0_faction, db),
		DeckList.load_for_faction(deck1_faction, db), match_seed, deck1_faction)


## 本机是不是联机里的客户端（客户端要等主机发权威状态才能显示对局）。
func _is_net_client() -> bool:
	var nm := _net()
	return nm != null and nm.is_client()


## 客户端等主机初始状态时的遮罩。
## 【为什么需要】客户端本地也会 start_match 出一份状态，但它的种子/卡组顺序
## 未必与主机一致，直接显示会看到错乱的战场与错误的领袖。盖住它，
## 等 _on_state_received 拿到权威状态后再揭开。
func _show_waiting_veil() -> void:
	if _wait_veil != null:
		_wait_veil.visible = true
		return
	_wait_veil = Control.new()
	_wait_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wait_veil.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wait_veil.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := UiKit.make_label("正在同步对局……", 30, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := UiKit.make_label("等待主机下发初始状态。", 15, UiKit.COL_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	# 绘制层级 = add_child 顺序：
	#   对局界面 < 等待遮罩 < 换牌/结算/终局弹窗
	# 遮罩要盖住错乱的对局界面，但不能盖住随后的换牌弹窗，所以插在弹窗之前。
	add_child(_wait_veil)
	if _mulligan_screen != null:
		move_child(_mulligan_screen, get_child_count() - 1)
	if _round_popup != null:
		move_child(_round_popup, get_child_count() - 1)
	if _match_popup != null:
		move_child(_match_popup, get_child_count() - 1)
	if _info_popup != null:
		move_child(_info_popup, get_child_count() - 1)


func _hide_waiting_veil() -> void:
	if _wait_veil != null:
		_wait_veil.visible = false


# ================================================================
#  构建界面
# ================================================================

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	# 【座位按「我的视角」排列，不能硬编码 0/1】
	# 单机时 my_index == 0，正好是「己方在下」；但联机客户端固定是玩家 1，
	# 若这里写死 `_build_band(1)` 在上，客户端就会看到「自己的信息带跑到上面、
	# 对手的信息带跑到下面」——即用户反馈的「客户端的场景在下面/上面颠倒」。
	# 正确做法：上方恒定是 opp_index，下方恒定是 my_index。
	col.add_child(_build_band(opp_index))
	col.add_child(_build_board())
	col.add_child(_build_band(my_index))
	col.add_child(_build_hand_band())

	_ai_timer = Timer.new()
	_ai_timer.one_shot = true
	_ai_timer.timeout.connect(_on_ai_timeout)
	add_child(_ai_timer)

	_mulligan_screen = _build_mulligan_overlay()
	_round_popup = _build_round_popup()
	_match_popup = _build_match_popup()
	_info_popup = _build_info_popup()
	# 加入顺序 = 绘制层级：浮层必须在对局界面之后
	for node in [_mulligan_screen, _round_popup, _match_popup, _info_popup]:
		node.visible = false
		add_child(node)


## 一片“角落信息带”：领袖 + 手牌数 + 总战力 + 城池 ........ 牌库 + 弃牌堆
func _build_band(player_index: int) -> Control:
	# 先建对手那片再建己方那片，所以必须按下标写入而不是 append
	if _leader_slots.size() < 2:
		_leader_slots.resize(2)
		_hand_labels.resize(2)
		_power_labels.resize(2)
		_city_labels.resize(2)
		_deck_labels.resize(2)
		_discard_labels.resize(2)

	var panel := UiKit.make_panel(UiKit.COL_PANEL_SOFT)
	panel.custom_minimum_size = Vector2(0, 72)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(UiKit.make_margin(row, 4))

	# 左：领袖卡
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(66, 66)
	slot.add_theme_stylebox_override("panel",
		UiKit.panel_style(Color("1e1a16"), UiKit.COL_GOLD.darkened(0.6), 4))
	row.add_child(slot)
	_leader_slots[player_index] = slot

	# 左：名字 + 手牌数
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_box)

	var p_faction := _seat_faction(player_index)
	var who_text := "你 · %s" % UiKit.faction_name(p_faction)
	if player_index != my_index:
		who_text = "对手 · %s" % UiKit.faction_name(p_faction)
	name_box.add_child(UiKit.make_label(who_text, 15, UiKit.faction_color(p_faction)))

	var hand_row := UiKit.make_icon_label(UiKit.ICON_HAND, "0", 20, UiKit.COL_TEXT, 20)
	name_box.add_child(hand_row)
	_hand_labels[player_index] = hand_row.get_child(1)

	# 左：总战力
	var power_box := VBoxContainer.new()
	power_box.add_theme_constant_override("separation", 0)
	power_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(power_box)
	power_box.add_child(UiKit.make_label("总战力", 11, UiKit.COL_TEXT_DIM))
	var power_value := UiKit.make_label("0", 32, UiKit.COL_GOLD)
	power_box.add_child(power_value)
	_power_labels[player_index] = power_value

	# 左：城池
	var city_row := UiKit.make_icon_label(UiKit.ICON_CITY, "◆◆", 20, UiKit.COL_GOLD, 22)
	city_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(city_row)
	_city_labels[player_index] = city_row.get_child(1)

	# 中：留白；对手那片放行动提示
	row.add_child(UiKit.h_spring())
	if player_index == opp_index:
		var mid_box := VBoxContainer.new()
		mid_box.add_theme_constant_override("separation", 2)
		mid_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mid_box)

		_hint_label = UiKit.make_label("", 13, UiKit.COL_TEXT_DIM)
		_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_label.custom_minimum_size = Vector2(380, 0)
		mid_box.add_child(_hint_label)

		# 联机专有：一行「你的回合 / 等待对手」提示，与上方战报错开显示
		_net_status_label = UiKit.make_label("", 12, UiKit.COL_TEXT_DIM)
		_net_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_status_label.visible = net_mode
		mid_box.add_child(_net_status_label)

		row.add_child(UiKit.h_spring())

	# 右：牌库 / 弃牌堆
	var deck_row := UiKit.make_icon_label(UiKit.ICON_DECK, "0", 20, UiKit.COL_TEXT, 22)
	deck_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(deck_row)
	_deck_labels[player_index] = deck_row.get_child(1)

	var discard_row := UiKit.make_icon_label(UiKit.ICON_DISCARD, "0", 20, UiKit.COL_TEXT_DIM, 22)
	discard_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(discard_row)
	_discard_labels[player_index] = discard_row.get_child(1)

	return panel


## 某个座位当前的阵营。单机时己方 = human_faction、对手 = 另一阵营；
## 联机时必须读GameState，因为双方阵营由联机流程决定（主机先选）。
func _seat_faction(player_index: int) -> String:
	if net_mode and net_faction_by_seat.size() > player_index:
		var f: String = str(net_faction_by_seat[player_index])
		if not f.is_empty():
			return f
	if state != null and state.players.size() > player_index:
		var sf: String = state.players[player_index].faction
		if not sf.is_empty():
			return sf
	if player_index == my_index:
		return human_faction
	# 最后的兜底（对局尚未建立时）：取七国里第一个不是自己的阵营。
	# 【不要写死「秦的对面是赵」】七国之下对面有 6 种可能。
	for f in CardData.FACTIONS:
		if f != human_faction:
			return f
	return human_faction


func _build_board() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 上：对手半场（暗红/暖褐）　中：中央界限　下：己方半场（暗蓝/冷褐）
	# 【同样不能硬编码】上面恒为 opp_index、下面恒为 my_index，
	# 保证不论本机是主机(0)还是客户端(1)，自己的半场永远在屏幕下方。
	col.add_child(_build_half(opp_index))
	col.add_child(_build_boundary())
	col.add_child(_build_half(my_index))
	return col


## 一个半场：带底色的面板，内部按“守军→城墙→远程→近战”或“近战→远程→城墙→守军”排列
func _build_half(player_index: int) -> Control:
	# 底色与行序都按「是不是我方」判断，而不是「是不是座位 0」
	var is_mine := player_index == my_index
	var bg := FIELD_BOTTOM_COLOR if is_mine else FIELD_TOP_COLOR
	var panel := UiKit.make_panel(bg, Color(1, 1, 1, 0.05), 6)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(UiKit.make_margin(box, 4))

	# 对手半场：守军离中央最近（贴着自己一侧的下缘）→ 从下往上递增
	var order: Array = [CardData.ROW_GARRISON, WALL_MARK, CardData.ROW_RANGED, CardData.ROW_MELEE]
	if is_mine:
		# 我方半场：近战在最上（最贴近中央），守军在最下（贴近手牌）
		order = [CardData.ROW_MELEE, CardData.ROW_RANGED, WALL_MARK, CardData.ROW_GARRISON]
	for item in order:
		if item == WALL_MARK:
			box.add_child(_build_wall())
		else:
			box.add_child(_add_row(item, player_index))
	return panel


## 中央界限：4px 金色横线 + 中间小字
func _build_boundary() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_boundary_line())
	var label := UiKit.make_label("阵 前", 11, UiKit.COL_GOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	row.add_child(_boundary_line())
	return row


func _boundary_line() -> Control:
	var line := ColorRect.new()
	line.color = UiKit.COL_GOLD
	line.custom_minimum_size = Vector2(0, 4)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _add_row(row: String, player_index: int) -> RowView:
	var view := RowView.new()
	view.setup(row, ROW_TINT)
	# 只有己方的行接受拖放；行下标必须用 my_index，联机时己方可能是 players[1]
	view.accepts_drop = player_index == my_index
	# 己方行接受计策牌拖放（拖到任意位置即释放，不占行）
	view.accepts_tactic = player_index == my_index
	view.info_requested.connect(_on_card_info_requested)
	if player_index == my_index:
		view.card_dropped.connect(_on_card_dropped)
	_row_views[player_index][row] = view
	return view


func _build_wall() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, WALL_HEIGHT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base := ColorRect.new()
	base.color = Color("2a231d")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)

	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_TILE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://assets/wall.svg"):
		texture_rect.texture = load("res://assets/wall.svg")
	if texture_rect.texture == null:
		texture_rect.visible = false
	holder.add_child(texture_rect)
	return holder


func _build_hand_band() -> Control:
	var panel := UiKit.make_panel(UiKit.COL_PANEL)
	panel.custom_minimum_size = Vector2(0, 128)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.make_margin(row, 4))

	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 8)
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hand_box)

	# 操作按钮区（手牌右侧）
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(170, 0)
	buttons.add_theme_constant_override("separation", 5)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(buttons)

	_pass_button = UiKit.make_button("Pass", UiKit.COL_LOSE, 17, Vector2(170, 42))
	_pass_button.pressed.connect(_on_pass_pressed)
	buttons.add_child(_pass_button)

	# 计策专用：单击手牌中的计策选中它，再点这里结算（计策不占行，无法拖放）
	_use_tactic_button = UiKit.make_button("使用计策", Color("8a6ea8"), 15, Vector2(170, 38))
	_use_tactic_button.disabled = true
	_use_tactic_button.pressed.connect(_on_use_tactic_pressed)
	buttons.add_child(_use_tactic_button)

	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 5)
	buttons.add_child(sub_row)

	_restart_button = UiKit.make_button("重开", UiKit.COL_TEXT_DIM, 14, Vector2(82, 36))
	_restart_button.pressed.connect(_on_restart)
	# 联机下"重开"会让双方状态分叉（只有本地重开、远端不知情），直接禁用
	_restart_button.disabled = net_mode
	if net_mode:
		_restart_button.tooltip_text = "联机对局不支持重开。"
	sub_row.add_child(_restart_button)

	_menu_button = UiKit.make_button("主菜单", UiKit.COL_TEXT_DIM, 14, Vector2(82, 36))
	_menu_button.pressed.connect(_on_menu_pressed)
	sub_row.add_child(_menu_button)

	return panel


## 「主菜单」：联机下必须先断开连接，否则会带着半死连接回到菜单。
func _on_menu_pressed() -> void:
	if net_mode:
		var nm := _net()
		if nm != null:
			nm.disconnect_peer()
	exit_to_menu.emit()


# ================================================================
#  刷新
# ================================================================

func _refresh() -> void:
	if state == null or state.players.size() < 2:
		return
	for i in range(2):
		var p := state.players[i]
		for row in CardData.ROWS:
			var view: RowView = _row_views[i][row]
			var cards := p.row_cards(row)
			var powers: Array = []
			for card in cards:
				powers.append(p.effective_power(card))
			view.refresh(cards, p.row_power(row), powers)
	_refresh_corner_info()
	_refresh_leaders()
	_rebuild_hand()
	_refresh_use_tactic_button()
	_sfx_track_state()
	_schedule_ai()


## 从状态变化里补三种「事件音」—— 都是无法在 `_dispatch()` 收口的那几类。
##
## 1) **新一局开始**：局号变大 → 鼓 + 短锣。放在这里而不是 advance_round 的处理里，
##    是因为三种模式拿到新一局的路径不同（单机 / 主机靠本地指令，客户端靠权威状态包），
##    比对 `round_number` 是唯一对三者都成立的判据。
## 2) **单位离场**：场上单位总数减少 → 崩解音。换局那一下必须跳过 ——
##    那是清场，不是摧毁，响了会误导。
## 3) **对手落牌（仅联机客户端）**：对手的动作不经过本机 `_dispatch()`，
##    只能用「对手场上单位数增加」推断。单机 / 主机**不能**启用这条 ——
##    AI 和玩家一样走 `_dispatch()`，再补一次就成了双声。
func _sfx_track_state() -> void:
	if state == null or state.players.size() < 2:
		return

	var round_now := state.round_number
	var new_round := _sfx_last_round >= 0 and round_now > _sfx_last_round
	if new_round:
		UiKit.sfx("round_start")

	var total := 0
	for i in range(2):
		for row in CardData.ROWS:
			total += state.players[i].row_cards(row).size()
	var opp_units := 0
	for row in CardData.ROWS:
		opp_units += state.players[opp_index].row_cards(row).size()

	if not new_round and _sfx_last_total_units >= 0 and total < _sfx_last_total_units:
		UiKit.sfx("destroy", 0.05, 0.95)
	if _is_net_client() and _sfx_last_opp_units >= 0 and opp_units > _sfx_last_opp_units:
		UiKit.sfx("card_place", 0.03, 0.9)

	_sfx_last_round = round_now
	_sfx_last_total_units = total
	_sfx_last_opp_units = opp_units


func _refresh_corner_info() -> void:
	# 【必须按「座位下标」写入】信息带是 _build_band(my_index) / _build_band(opp_index)
	# 建立的，两侧的标签数组下标就是**座位号**。若这里硬编码 [0]=己方、[1]=对手，
	# 联机客户端（my_index == 1）就会把双方数据写反 —— 上面显示自己的数字、
	# 下面显示对手的数字，与用户反馈的「客户端场景不对」是同一个根因。
	var me := state.players[my_index]
	var opp := state.players[opp_index]

	_hand_labels[my_index].text = "%d" % me.hand_size()
	_hand_labels[opp_index].text = "%d" % opp.hand_size()
	_hand_labels[my_index].add_theme_color_override("font_color", UiKit.COL_TEXT)
	_hand_labels[opp_index].add_theme_color_override("font_color", UiKit.COL_TEXT)

	var mp := me.total_power()
	var op := opp.total_power()
	_power_labels[my_index].text = str(mp)
	_power_labels[opp_index].text = str(op)
	_power_labels[my_index].add_theme_color_override("font_color",
		UiKit.COL_WIN if mp > op else (UiKit.COL_LOSE if mp < op else UiKit.COL_GOLD))
	_power_labels[opp_index].add_theme_color_override("font_color",
		UiKit.COL_WIN if op > mp else (UiKit.COL_LOSE if op < mp else UiKit.COL_TEXT))

	# 城池（原宝石）：◆◆ / ◆◇，失去 2 座即失败
	_city_labels[my_index].text = me.gems_text()
	_city_labels[opp_index].text = opp.gems_text()
	_city_labels[my_index].add_theme_color_override("font_color",
		UiKit.COL_LOSE if me.gems <= 1 else UiKit.COL_GOLD)
	_city_labels[opp_index].add_theme_color_override("font_color",
		UiKit.COL_LOSE if opp.gems <= 1 else UiKit.COL_GOLD)

	_deck_labels[my_index].text = str(me.deck_size())
	_deck_labels[opp_index].text = str(opp.deck_size())
	_discard_labels[my_index].text = str(me.discard_size())
	_discard_labels[opp_index].text = str(opp.discard_size())

	_hint_label.text = "%s　·　%s" % [state.turn_text(), _last_message]
	_hint_label.add_theme_color_override("font_color",
		UiKit.COL_GOLD if state.active == my_index else UiKit.COL_TEXT_DIM)
	_pass_button.disabled = not state.can_act(my_index)
	if net_mode:
		var nm := _net()
		var side := "主机" if (nm != null and nm.is_host()) else "客户端"
		var turn_text := "你的回合" if state.active == my_index else "等待对手行动"
		_net_status_label.text = "联机 · %s · 你是玩家 %d　|　%s" % [side, my_index, turn_text]
		_net_status_label.add_theme_color_override("font_color",
			UiKit.COL_GOLD if state.active == my_index else UiKit.COL_TEXT_DIM)


func _refresh_leaders() -> void:
	if _leader_built:
		return
	for i in range(2):
		var slot: PanelContainer = _leader_slots[i]
		for child in slot.get_children():
			slot.remove_child(child)
			child.queue_free()
		var leader: CardData = state.players[i].leader
		if leader == null:
			var empty := UiKit.make_label("无\n领袖", 12, UiKit.COL_TEXT_DIM)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(empty)
			continue
		var view := CardView.new()
		view.setup(leader, CardView.Style.BOARD)
		view.set_interaction(false, false, true)
		view.card_right_clicked.connect(_on_card_right_clicked)
		slot.add_child(view)
	_leader_built = true


func _rebuild_hand() -> void:
	for child in _hand_box.get_children():
		_hand_box.remove_child(child)
		child.queue_free()

	var cards := state.players[my_index].hand.duplicate()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		var ra := _hand_sort_key(a)
		var rb := _hand_sort_key(b)
		if ra != rb:
			return ra < rb
		if a.card_type == CardData.TYPE_TACTIC:
			return a.id < b.id
		return a.power > b.power)

	# 手牌多时自动重叠，保证不溢出
	var count := cards.size()
	var separation := 8
	if count > 1:
		var card_width: float = CardView.SIZES[CardView.Style.HAND].x
		separation = int(clamp(floor((HAND_AREA_WIDTH - count * card_width) / float(count - 1)), -40.0, 8.0))
	_hand_box.add_theme_constant_override("separation", separation)

	var can_drag := state.can_act(my_index)
	for card in cards:
		var view := CardView.new()
		view.setup(card, CardView.Style.HAND)
		view.set_interaction(true, can_drag, true)
		view.set_playable(can_drag)
		view.card_clicked.connect(_on_hand_card_clicked)
		view.card_right_clicked.connect(_on_card_right_clicked)
		view.drag_began.connect(_on_drag_began)
		_hand_box.add_child(view)

	for row in CardData.ROWS:
		var row_view: RowView = _row_views[my_index][row]
		row_view.set_drag_hint(can_drag)


## 手牌排序键：近战 0 → 远程 1 → 守军 2 → 计策 3。
func _hand_sort_key(card: CardData) -> int:
	if card.card_type == CardData.TYPE_TACTIC:
		return 3
	var rank := {CardData.ROW_MELEE: 0, CardData.ROW_RANGED: 1, CardData.ROW_GARRISON: 2}
	return int(rank.get(card.row, 2))


# ================================================================
#  指令派发（单机 = 本地执行；联机 = 发给主机）
# ================================================================

## 所有操作一律经这里变成指令。
## 单机：直接本地执行。
## 联机（5C）：
##   - 主机：本地执行（主机就是权威），执行成功后广播新状态给客户端。
##   - 客户端：只把指令发给主机，**不本地执行**（避免与主机状态漂移），
##     等主机广播权威状态后再刷新界面。
func _dispatch(cmd: Command) -> CommandResult:
	if state == null:
		return CommandResult.fail("对局尚未开始。")

	var nm := _net()
	if net_mode and nm != null and nm.is_client():
		# 【为什么要在这里也播音】客户端不本地跑规则，成败要等主机回传（没有 ack），
		# 但玩家的操作反馈必须**立刻**有 —— 先乐观地响，被拒时 _on_command_result 再补 error。
		_sfx_for_command(cmd)
		nm.send_command(cmd)
		# 客户端不本地跑规则：返回一个「已提交」的结果，实际成败由主机回传
		return CommandResult.success(true)

	var result := state.execute_command(cmd)
	if not result.ok and not result.reason.is_empty():
		_last_message = "操作无效：" + result.reason
		if _hint_label != null:
			_hint_label.text = _last_message

	if result.ok:
		_sfx_for_command(cmd)
	else:
		UiKit.sfx("error")

	# 主机执行成功 -> 广播权威状态
	if net_mode and nm != null and nm.is_host() and result.ok:
		nm.send_state(state.serialize())
	return result


## 按指令类型播放操作音。
##
## 【为什么放在指令层而不是各个交互入口】出牌有「拖放 / 点选 / AI 代打」多条入口，
## 逐个挂必然漏；`_dispatch()` 是所有操作的唯一收口，挂这里一次覆盖全部。
## 对手的牌用更沉的音高（0.9），一听就知道不是自己出的。
func _sfx_for_command(cmd: Command) -> void:
	var by_me := cmd.player == my_index
	match cmd.type:
		Command.CMD_PLAY_CARD:
			if by_me:
				UiKit.sfx("card_place", 0.05)
			else:
				UiKit.sfx("card_place", 0.03, 0.9)
		Command.CMD_PLAY_TACTIC:
			if by_me:
				UiKit.sfx("tactic")
			else:
				UiKit.sfx("tactic", 0.0, 0.92)
		Command.CMD_MULLIGAN:
			UiKit.sfx("card_draw")
		_:
			pass


## 主机专用（5D）：开局后把权威初始状态推给客户端。
## 客户端在联机开局时用的是同一个种子，但因缺少「主机选了什么阵营/卡组构造顺序」，
## 必须靠这条初始状态完全对齐；客户端收到后 apply_state 覆盖。
func push_initial_state() -> void:
	if not net_mode or state == null:
		return
	var nm := _net()
	if nm == null or not nm.is_host():
		return
	nm.send_state(state.serialize())


## 取 NetworkManager 单例（Autoload）。取不到返回 null，便于单机/测试环境。
## 测试用：注入一个独立的 NetworkManager 实例（同进程双实例隔离需要）。
## 为 null 时从场景树取 Autoload "NetworkManager"。
var net_override: Node = null


func _net() -> Node:
	if net_override != null:
		return net_override
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("NetworkManager")


# ================================================================
#  出牌交互
# ================================================================

func _on_hand_card_clicked(card: CardData, _view: CardView) -> void:
	if state == null or state.phase == GameState.Phase.MULLIGAN:
		return
	if not state.can_act(my_index):
		return
	if card.card_type == CardData.TYPE_TACTIC:
		_selected_tactic = card
		_hint_label.text = "已选中计策「%s」，点右侧「使用计策」结算（不占行）。" % card.name
		_refresh_use_tactic_button()
		return
	_selected_tactic = null
	_refresh_use_tactic_button()
	var rows_text := _legal_rows_text(card)
	_hint_label.text = "按住「%s」拖到%s出牌。" % [card.name, rows_text]


## 刷新「使用计策」按钮的可用状态。
func _refresh_use_tactic_button() -> void:
	if _use_tactic_button == null:
		return
	var ok := state != null and state.can_act(my_index) and _selected_tactic != null \
		and state.players[my_index].hand.has(_selected_tactic)
	_use_tactic_button.disabled = not ok
	_use_tactic_button.text = "使用计策" if _selected_tactic == null \
		else "使用「%s」" % _selected_tactic.name


func _on_use_tactic_pressed() -> void:
	if state == null or _selected_tactic == null:
		return
	if not state.can_act(my_index):
		_hint_label.text = "现在不是你的行动回合。"
		return
	var card := _selected_tactic
	_selected_tactic = null
	_dispatch(Command.play_tactic(my_index, card.id))
	_refresh_use_tactic_button()


## 该卡可落行的中文描述（如「近战 / 守军」）。
func _legal_rows_text(card: CardData) -> String:
	var names: PackedStringArray = PackedStringArray()
	for row in card.legal_rows():
		names.append(CardView.row_display_name(row))
	if names.is_empty():
		return "任意行"
	return " / ".join(names) + "行"


func _on_drag_began(_card: CardData, _view: CardView) -> void:
	if state == null:
		return
	var can_drag := state.can_act(my_index)
	for row in CardData.ROWS:
		var row_view: RowView = _row_views[my_index][row]
		row_view.set_drag_hint(can_drag)


## 计策牌拖到场上任意一行即释放（5C：不占行、不需要选目标行）。
## 统一由这里拦下，转成 play_tactic 指令。
func _on_tactic_dropped(card: CardData) -> void:
	if state == null or card == null:
		return
	if not state.can_act(my_index):
		_hint_label.text = "现在不是你的行动回合。"
		return
	_selected_tactic = null
	_refresh_use_tactic_button()
	_dispatch(Command.play_tactic(my_index, card.id))
	for row in CardData.ROWS:
		var row_view: RowView = _row_views[my_index][row]
		row_view.reset_drop_state()


func _on_card_dropped(card: CardData, row_id: String, index: int = -1) -> void:
	if state == null or card == null:
		return
	# 计策牌走「拖到任意位置即释放」的路径，忽略落点行
	if card.card_type == CardData.TYPE_TACTIC:
		_on_tactic_dropped(card)
		return
	var row_name := CardView.row_display_name(row_id)
	if not card.can_place_in(row_id):
		_hint_label.text = "「%s」只能落在%s，不能放到%s行。" % [
			card.name, _legal_rows_text(card), row_name]
		return
	if not state.can_act(my_index):
		_hint_label.text = "现在不是你的行动回合。"
		return
	_dispatch(Command.play_card(my_index, card.id, row_id, index))
	for row in CardData.ROWS:
		var row_view: RowView = _row_views[my_index][row]
		row_view.set_drag_hint(false)
		row_view.reset_drop_state()


func _on_pass_pressed() -> void:
	if state != null:
		_dispatch(Command.pass_turn(my_index))


func _on_card_info_requested(card: CardData) -> void:
	_show_card_info(card)


# ================================================================
#  换牌
# ================================================================

func _build_mulligan_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.74)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := UiKit.make_label("换 牌 阶 段", 32, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var desc := UiKit.make_label("第 1 局 · 选择最多 2 张放回牌库并重抽等量（不选即直接开始）", 14, UiKit.COL_TEXT_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)

	_mulligan_box = HBoxContainer.new()
	_mulligan_box.add_theme_constant_override("separation", 6)
	_mulligan_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_mulligan_box)

	_mulligan_hint = UiKit.make_label("", 15, UiKit.COL_TEXT)
	_mulligan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_mulligan_hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_mulligan_button = UiKit.make_button("确认换牌", UiKit.COL_GOLD, 18, Vector2(200, 48))
	_mulligan_button.pressed.connect(_on_mulligan_confirm)
	row.add_child(_mulligan_button)
	return root


func _open_mulligan() -> void:
	_selected.clear()
	for child in _mulligan_box.get_children():
		_mulligan_box.remove_child(child)
		child.queue_free()
	var row_rank := {CardData.ROW_MELEE: 0, CardData.ROW_RANGED: 1, CardData.ROW_GARRISON: 2}
	var cards := state.players[my_index].hand.duplicate()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if row_rank.get(a.row, 3) != row_rank.get(b.row, 3):
			return row_rank.get(a.row, 3) < row_rank.get(b.row, 3)
		return a.power > b.power)
	for card in cards:
		var view := CardView.new()
		view.setup(card, CardView.Style.HAND)
		view.set_interaction(true, false, true)
		view.card_clicked.connect(_on_mulligan_card_clicked)
		view.card_right_clicked.connect(_on_card_right_clicked)
		_mulligan_box.add_child(view)
	_update_mulligan_hint()
	_mulligan_screen.visible = true


## 点击换牌界面里的一张牌，切换其选中状态。
## `view` 允许为 null（测试直接调此函数时不必造控件）——
## 选中态以 `_selected` 数组为准，控件高亮只是表现层。
func _on_mulligan_card_clicked(card: CardData, view: CardView) -> void:
	if _selected.has(card):
		_selected.erase(card)
		if view != null:
			view.set_selected(false)
	elif _selected.size() < GameState.MULLIGAN_LIMIT:
		_selected.append(card)
		if view != null:
			view.set_selected(true)
	_update_mulligan_hint()


func _update_mulligan_hint() -> void:
	var names: PackedStringArray = PackedStringArray()
	for card in _selected:
		names.append(card.name)
	var suffix := ""
	if not names.is_empty():
		suffix = "　→　" + ", ".join(names)
	_mulligan_hint.text = "已选 %d / %d%s" % [_selected.size(), GameState.MULLIGAN_LIMIT, suffix]


func _on_mulligan_confirm() -> void:
	if state == null or state.phase != GameState.Phase.MULLIGAN:
		return
	var ids: Array[String] = []
	for card in _selected:
		ids.append(card.id)
	# 【关键】先派发、**看结果**再决定要不要关界面。
	# 曾经这里无条件 `visible = false`，一旦指令被拒（例如两张同名卡只解析到同一实例），
	# 界面已经关掉、换牌又没生效，玩家既看不到错误也点不了确认 → 永久卡死在换牌阶段。
	var result: CommandResult = _dispatch(Command.mulligan(my_index, ids))
	if not result.ok:
		# 保持界面打开，把原因显示在换牌提示里，玩家可以改选后重试
		_mulligan_hint.text = "换牌失败：%s" % result.reason
		return
	_selected.clear()
	_mulligan_screen.visible = false

	# 联机：对手是真人，只关掉自己的换牌界面，等对手确认后主机会广播进入出牌阶段
	if net_mode:
		_refresh()
		return

	# 单机：按 mulligan_order 让 AI 依次换牌（先手方先换）。
	# 双方共用同一 rng，顺序错了会造成座位优势。
	if state.phase == GameState.Phase.MULLIGAN:
		for i in state.mulligan_order:
			if i == my_index or state.mulligan_done[i]:
				continue
			var ai_ids: Array[String] = []
			for card in AIOpponent.choose_mulligan(state, i):
				ai_ids.append(card.id)
			_dispatch(Command.mulligan(i, ai_ids))
	_refresh()


# ================================================================
#  弹窗
# ================================================================

func _build_popup_frame(width: int) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.62)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := UiKit.make_panel(UiKit.COL_PANEL, UiKit.COL_GOLD.darkened(0.4))
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(UiKit.make_margin(box, 20))
	root.set_meta("box", box)
	return root


func _build_round_popup() -> Control:
	var root := _build_popup_frame(500)
	_round_box = root.get_meta("box")
	return root


func _build_match_popup() -> Control:
	var root := _build_popup_frame(500)
	_match_box = root.get_meta("box")
	return root


func _build_info_popup() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var veil := Button.new()
	veil.flat = true
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.pressed.connect(_close_info_popup)
	root.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := UiKit.make_panel(UiKit.COL_PANEL, UiKit.COL_GOLD.darkened(0.4))
	panel.custom_minimum_size = Vector2(430, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.make_margin(_info_box, 20))
	return root


func _show_card_info(card: CardData) -> void:
	if card == null:
		return
	_clear_box(_info_box)

	var title := UiKit.make_label(card.name, 30, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_box.add_child(title)

	var kind := CardView.category_display_name(card)
	var subtitle_text := "%s · %s" % [UiKit.faction_name(card.faction), kind]
	if card.card_type == CardData.TYPE_UNIT:
		var rows: PackedStringArray = PackedStringArray()
		for row in card.legal_rows():
			rows.append(CardView.row_display_name(row))
		subtitle_text += " · 战力 %d · 可落 %s" % [card.power, " / ".join(rows)]
	var subtitle := UiKit.make_label(subtitle_text, 15, UiKit.COL_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_box.add_child(subtitle)

	# 场上卡牌显示实时战力（含增益）
	var live := _live_power_of(card)
	if live >= 0 and card.card_type == CardData.TYPE_UNIT and live != card.power:
		var diff := live - card.power
		var live_text := "当前战力 %d（卡面 %d，%+d）" % [live, card.power, diff]
		var live_label := UiKit.make_label(live_text, 15,
			UiKit.COL_DROP_OK if diff > 0 else UiKit.COL_DROP_NO)
		live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_info_box.add_child(live_label)

	_info_box.add_child(HSeparator.new())
	_info_box.add_child(UiKit.make_label("效果说明", 15, UiKit.COL_TEXT))

	var ability_name := Abilities.ability_name(card.ability_id)
	var ability_text := Abilities.ability_text(card.ability_id)
	var desc := ""
	if not ability_name.is_empty():
		desc = "「%s」%s" % [ability_name, ability_text]
	elif card.description.strip_edges() != "":
		desc = card.description
	if desc.strip_edges() == "":
		desc = "无特殊效果"
	var desc_label := UiKit.make_label(desc, 16, UiKit.COL_TEXT)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(380, 0)
	_info_box.add_child(desc_label)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_info_box.add_child(close_row)
	var close_button := UiKit.make_button("关闭", UiKit.COL_TEXT_DIM, 16, Vector2(140, 42))
	close_button.pressed.connect(_close_info_popup)
	close_row.add_child(close_button)

	_info_popup.visible = true


## 该卡在当前对局中的实时战力；不在场上返回 -1。
func _live_power_of(card: CardData) -> int:
	if state == null or state.players.size() < 2:
		return -1
	for p in state.players:
		if p.board_has(card):
			return p.effective_power(card)
	return -1


func _close_info_popup() -> void:
	if _info_popup != null:
		_info_popup.visible = false


func _on_card_right_clicked(card: CardData, _view: CardView) -> void:
	_show_card_info(card)


func _on_logged(text: String) -> void:
	_last_message = text
	if _hint_label != null:
		_hint_label.text = "%s　·　%s" % [state.turn_text(), text]


func _on_round_ended(summary: Dictionary) -> void:
	# 一声收束鼓：弹出结算之前先给出「这一局完了」的听觉信号
	UiKit.sfx("round_end")
	_clear_box(_round_box)
	var winner: int = summary["winner"]
	var power: Array = summary["power"]

	var title := UiKit.make_label("第 %d 局结束" % int(summary["round"]), 26, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_box.add_child(title)

	var score_color := UiKit.COL_TEXT
	if winner == my_index:
		score_color = UiKit.COL_WIN
	elif winner == opp_index:
		score_color = UiKit.COL_LOSE
	# 比分按「本方 : 对手」重排，联机时己方可能是 players[1]
	var mine_power: int = int(power[my_index])
	var opp_power: int = int(power[opp_index])
	var score := UiKit.make_label("你 %d : %d 对手" % [mine_power, opp_power], 34, score_color)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_box.add_child(score)

	var row_power: Array = summary["row_power"]
	var detail := UiKit.make_label(
		"你 —— 近战 %d · 远程 %d · 守军 %d\n对手 —— 近战 %d · 远程 %d · 守军 %d" % [
			int(row_power[my_index][0]), int(row_power[my_index][1]), int(row_power[my_index][2]),
			int(row_power[opp_index][0]), int(row_power[opp_index][1]), int(row_power[opp_index][2]),
		], 13, UiKit.COL_TEXT_DIM)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_box.add_child(detail)

	var result := UiKit.make_label(str(summary["text"]), 15, UiKit.COL_TEXT)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_box.add_child(result)

	var gems: Array = summary["gems"]
	_round_box.add_child(UiKit.make_icon_label(UiKit.ICON_CITY,
		"你 %d 座　·　对手 %d 座" % [int(gems[my_index]), int(gems[opp_index])], 16, UiKit.COL_GOLD))

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_round_box.add_child(button_row)
	var next_button := UiKit.make_button("继续", UiKit.COL_GOLD, 18, Vector2(180, 46))
	next_button.pressed.connect(_on_round_popup_continue)
	button_row.add_child(next_button)
	_round_popup.visible = true


func _on_round_popup_continue() -> void:
	_round_popup.visible = false
	if state == null:
		return
	_dispatch(Command.advance_round())
	_refresh()


func _on_match_ended(summary: Dictionary) -> void:
	_clear_box(_match_box)
	var winner: int = summary["winner"]
	# 胜负音：胜用上行三音编钟、负用下行三音，平局用回合收束鼓
	if winner == my_index:
		UiKit.sfx("win")
	elif winner == opp_index:
		UiKit.sfx("lose")
	else:
		UiKit.sfx("round_end")

	var headline := "平局"
	var color := UiKit.COL_TEXT
	if winner == my_index:
		headline = "你 获 胜"
		color = UiKit.COL_WIN
	elif winner == opp_index:
		headline = "对手获胜"
		color = UiKit.COL_LOSE

	var title := UiKit.make_label("对 局 结 束", 24, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(title)

	var verdict := UiKit.make_label(headline, 38, color)
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(verdict)

	var rounds_won: Array = summary["rounds_won"]
	var detail := UiKit.make_label("胜局　你 %d : %d 对手" % [
		int(rounds_won[my_index]), int(rounds_won[opp_index])], 15, UiKit.COL_TEXT_DIM)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_box.add_child(detail)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_match_box.add_child(row)

	# 联机无法「再来一局」（远端不会跟着重开），只留返回
	if not net_mode:
		var again := UiKit.make_button("再来一局", UiKit.COL_GOLD, 18, Vector2(170, 46))
		again.pressed.connect(_on_restart)
		row.add_child(again)

	var menu := UiKit.make_button("返回主菜单", UiKit.COL_TEXT_DIM, 16, Vector2(170, 46))
	menu.pressed.connect(_on_menu_pressed)
	row.add_child(menu)
	_match_popup.visible = true


# ================================================================
#  AI 与重开
# ================================================================

## 联机模式下不存在 AI：双方都是真人，由网络指令驱动。
## 单机模式下对手固定是 players[opp_index]（恒为 1）。
func _schedule_ai() -> void:
	if net_mode:
		return
	if state == null or _ai_timer == null:
		return
	if state.phase != GameState.Phase.PLAY or state.active != opp_index:
		return
	if not _ai_timer.is_stopped():
		return
	_ai_timer.start(AI_THINK_TIME)


func _on_ai_timeout() -> void:
	if net_mode:
		return
	if state == null or state.phase != GameState.Phase.PLAY or state.active != opp_index:
		return
	var card := AIOpponent.choose_card(state, opp_index)
	var result: CommandResult
	if card == null:
		result = _dispatch(Command.pass_turn(opp_index))
	elif card.card_type == CardData.TYPE_TACTIC:
		# 【计策必须走 play_tactic】计策牌不占行、打出即结算，和单位牌是两条指令。
		# 曾经这里无条件用 play_card，AI 一拿到计策就被 GameState 以
		# 「「X」不是单位牌。」拒绝 → 状态无变化 → changed 不发射 →
		# _schedule_ai() 不再启动定时器 → AI 永久停手，整局卡死。
		result = _dispatch(Command.play_tactic(opp_index, card.id))
	else:
		result = _dispatch(Command.play_card(opp_index, card.id, card.row, -1))
	# 【兜底】万一指令仍被拒（AI 选到了落点非法的牌、或手牌已变），
	# 必须让 AI 改判 Pass，否则回合永不推进 —— 表现同样是整局卡死。
	if not result.ok:
		_dispatch(Command.pass_turn(opp_index))


func _on_restart() -> void:
	if _ai_timer != null:
		_ai_timer.stop()
	_round_popup.visible = false
	_match_popup.visible = false
	_mulligan_screen.visible = false
	_info_popup.visible = false
	_last_message = ""
	_leader_built = false
	_start_match()


func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


