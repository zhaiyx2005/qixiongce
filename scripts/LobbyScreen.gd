extends Control
class_name LobbyScreen

## 联机大厅（5D）：创建房间 / 加入房间 / 连接状态 / 返回主菜单。
##
## 本界面只负责「建立连接」这一件事，不碰对局规则，也不碰阵营选择。
## 连接建立后发出 `link_ready`，由 Main 接管后续流程（阵营选择 → 换牌 → 对局）。

signal back
## 连接建立完毕，可以进入阵营选择
signal link_ready

const DEFAULT_IP := "127.0.0.1"

## 端口输入框允许的端口范围
const PORT_MIN := 1024
const PORT_MAX := 65535

var _ip_edit: LineEdit
var _port_edit: LineEdit
var _status_label: Label
var _host_btn: Button
var _join_btn: Button
var _cancel_btn: Button
## 是否正在等待连接（等待期间禁用按钮、显示取消）
var _connecting: bool = false
## 连接失败/断开原因（供外部读取）
var _last_error: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect_net_signals()
	_set_status("填好端口后点「创建房间」，或填好主机 IP 与端口后点「加入游戏」。",
		UiKit.COL_TEXT_DIM)


func _exit_tree() -> void:
	# 【只解绑信号，绝不在这里断开连接】
	#
	# 曾经这里调用了 disconnect_peer()，以为「离开大厅 = 玩家放弃联机」。
	# 实际上 `link_ready` → `Main._show_net_faction_select()` 会**立刻**把大厅
	# 从场景树里换掉，`_exit_tree()` 紧接着执行 —— 此时连接是好的、双方正要去
	# 选阵营，却被这里一刀砍断，于是双方都停在「等待对手」：
	#   主机：已发出阵营广播，但 peer 已关闭，报「等待对手回应」
	#   客户端：永远收不到广播，报「等待主机反应」
	# 这是「双方同时卡在等待」的真正根因。
	#
	# 正确的断开时机：
	#   1. 玩家点「返回主菜单」（`_on_back_pressed`，且尚未连上）
	#   2. 玩家点「取消连接」（`_on_cancel_pressed`）
	#   3. 对局结束 `Main._show_menu()` → `_reset_net_state()`（补充兜底）
	_connect_net_signals(true)


func setup_error(err: String) -> void:
	_last_error = err


# ---------------- 构建界面 ----------------

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
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := UiKit.make_label("联 机 对 战", 46, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var desc := UiKit.make_label("局域网 P2P 对战 · 主机为规则裁判 · 双方各占一方阵营", 14, UiKit.COL_TEXT_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(desc)

	box.add_child(UiKit.spacer(12))

	# ---- 连接参数：IP 与端口在同一行 ----
	# 【为什么合并成一行】原先做成「创建房间」和「加入房间」两个面板，各自一行输入：
	#   创建房间：端口 [__]                    创建房间
	#   加入房间：主机 IP [__]  端口(无输入框)  加入房间
	# 两个问题：① 端口输入框只建了一个（在创建房间那行），加入房间那行的「端口」
	# 只是个**没有输入框的孤立标签**；② 两块面板重复表达了同一组连接参数。
	# 改成「参数行 + 按钮行」两行，参数只输入一次，两个按钮并排在下。
	var param_panel := UiKit.make_panel()
	box.add_child(param_panel)
	var param_row := HBoxContainer.new()
	param_row.add_theme_constant_override("separation", 12)
	param_row.alignment = BoxContainer.ALIGNMENT_CENTER
	param_panel.add_child(UiKit.make_margin(param_row, 14))

	var ip_caption := UiKit.make_label("主机 IP", 15, UiKit.COL_TEXT_DIM)
	ip_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	param_row.add_child(ip_caption)

	_ip_edit = _make_line_edit(DEFAULT_IP, 200)
	param_row.add_child(_ip_edit)

	var port_caption := UiKit.make_label("端口", 15, UiKit.COL_TEXT_DIM)
	port_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	param_row.add_child(port_caption)

	_port_edit = _make_line_edit("%d" % NetworkManager.DEFAULT_PORT, 120)
	param_row.add_child(_port_edit)

	# ---- 两个动作按钮并排 ----
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 16)
	box.add_child(action_row)

	_host_btn = UiKit.make_button("创建房间", UiKit.COL_WIN, 18, Vector2(190, 48))
	_host_btn.pressed.connect(_on_host_pressed)
	action_row.add_child(_host_btn)

	_join_btn = UiKit.make_button("加入游戏", UiKit.COL_GOLD, 18, Vector2(190, 48))
	_join_btn.pressed.connect(_on_join_pressed)
	action_row.add_child(_join_btn)

	# ---- 状态 ----
	box.add_child(UiKit.spacer(6))

	_status_label = UiKit.make_label("", 15, UiKit.COL_TEXT_DIM)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size = Vector2(460, 0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)

	box.add_child(UiKit.spacer(6))

	# ---- 取消 / 返回 ----
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)

	_cancel_btn = UiKit.make_button("取消连接", UiKit.COL_LOSE, 16, Vector2(160, 44))
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	bottom.add_child(_cancel_btn)

	var back_button := UiKit.make_button("返回主菜单", UiKit.COL_TEXT_DIM, 16, Vector2(180, 44))
	back_button.pressed.connect(_on_back_pressed)
	bottom.add_child(back_button)


func _make_line_edit(text: String, width: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.custom_minimum_size = Vector2(width, 36)
	edit.add_theme_font_size_override("font_size", 16)
	edit.add_theme_color_override("font_color", UiKit.COL_TEXT)
	edit.add_theme_color_override("caret_color", UiKit.COL_GOLD)
	edit.add_theme_color_override("font_placeholder_color", UiKit.COL_TEXT_DIM)
	edit.add_theme_stylebox_override("normal", UiKit.panel_style(Color("1d1915"), UiKit.COL_BORDER))
	edit.add_theme_stylebox_override("focus", UiKit.panel_style(Color("1d1915"), UiKit.COL_GOLD))
	return edit


# ---------------- 交互 ----------------

func _on_host_pressed() -> void:
	var port := _read_port()
	if port < 0:
		return

	var nm := _net()
	if nm == null:
		_set_status("网络模块不可用。", UiKit.COL_LOSE)
		return

	if nm.host_game(port):
		_set_connecting(true)
		_set_status("房间已创建，端口 %d。正在等待对手加入……" % port, UiKit.COL_GOLD)


func _on_join_pressed() -> void:
	var port := _read_port()
	if port < 0:
		return

	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_set_status("请填写主机 IP。", UiKit.COL_LOSE)
		return

	var nm := _net()
	if nm == null:
		_set_status("网络模块不可用。", UiKit.COL_LOSE)
		return

	if nm.join_game(ip, port):
		_set_connecting(true)
		_set_status("正在连接 %s:%d ……" % [ip, port], UiKit.COL_GOLD)


func _on_cancel_pressed() -> void:
	var nm := _net()
	if nm != null:
		nm.disconnect_peer()
	_set_connecting(false)
	_set_status("已取消。可重新创建或加入房间。", UiKit.COL_TEXT_DIM)


func _on_back_pressed() -> void:
	# 返回主菜单前断开，避免带着一个半连接状态回到菜单。
	# 【只在「还没连上」时断】已经连上还按返回，说明玩家想退出联机，
	# 但此时更可能是误触；真退出请用「取消连接」。这里保守处理：
	# 连上了就不悄悄断开，交给 Main._show_menu() 统一清理。
	var nm := _net()
	if nm != null and not nm.is_connected_now:
		nm.disconnect_peer()
	back.emit()


## 读取并校验端口输入。非法时返回 -1 并给出中文提示。
func _read_port() -> int:
	var raw := _port_edit.text.strip_edges()
	if not raw.is_valid_int():
		_set_status("端口必须是数字。", UiKit.COL_LOSE)
		return -1
	var port := raw.to_int()
	if port < PORT_MIN or port > PORT_MAX:
		_set_status("端口需在 %d ~ %d 之间。" % [PORT_MIN, PORT_MAX], UiKit.COL_LOSE)
		return -1
	return port


func _set_connecting(on: bool) -> void:
	_connecting = on
	_host_btn.disabled = on
	_join_btn.disabled = on
	_cancel_btn.visible = on
	# 连接过程中两个输入框都锁住 —— 参数已经用出去了，改动只会让人困惑。
	# （原先两个分支各自只禁一个，且禁的不是同一个，语义混乱。）
	_ip_edit.editable = not on
	_port_edit.editable = not on


func _set_status(text: String, color: Color) -> void:
	if _status_label != null:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", color)


# ---------------- 网络信号 ----------------

func _connect_net_signals(unbind := false) -> void:
	var nm := _net()
	if nm == null:
		return
	var pairs := [
		[nm.connected, _on_net_connected],
		[nm.connection_failed, _on_net_connection_failed],
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


func _on_net_connected() -> void:
	var nm := _net()
	var side := "主机" if (nm != null and nm.is_host()) else "客户端"
	_set_connecting(false)
	UiKit.sfx("round_start")
	_set_status("已连接（%s）。进入阵营选择。" % side, UiKit.COL_WIN)
	link_ready.emit()


func _on_net_connection_failed(reason: String) -> void:
	UiKit.sfx("error")
	_set_connecting(false)
	_set_status(reason, UiKit.COL_LOSE)


func _on_net_disconnected() -> void:
	_set_connecting(false)
	_set_status("连接已断开。", UiKit.COL_LOSE)


## 联机时使用的 NetworkManager。默认从场景树取 Autoload；
## 测试/多实例场景可在 add_child 之前注入一个独立实例。
var net_override: Node = null


func _net() -> Node:
	if net_override != null:
		return net_override
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("NetworkManager")
