extends Control
class_name SettingsScreen

## 游戏设置。
##
## 当前版本可配置：**音量**（主音量 / 背景音乐 / 音效），改动即时生效并写盘。
##
## 联机模式下下列选项**不能各自设置**（否则会与远端状态分叉），因此以禁用态列出：
##   - AI 难度（联机对手是真人，AI 不参战）
##   - 动画速度（会改变指令节奏，联机下需双方一致）
##
## 【音量为什么联机下也能调】音量只影响本方听感，不参与权威状态，
## 双方各调各的不会造成不同步，因此始终可用。

signal back

## 联机模式下进入本界面（由 Main 传入）
var net_mode: bool = false

## 联机不支持的设置项：(名称, 说明)
const NET_UNSUPPORTED := [
	["AI 难度", "联机对战的对手是真人，AI 不参战。"],
	["动画速度", "联机时节奏由主机权威状态决定，需双方一致。"],
]

## 要做成滑块的音量项：(总线名, 显示名, 说明)
const VOLUME_ROWS := [
	[AudioManager.BUS_MASTER, "主音量", "所有声音的总音量"],
	[AudioManager.BUS_MUSIC, "背景音乐", "主菜单与对局音乐"],
	[AudioManager.BUS_SFX, "音效", "按钮、出牌、战力变化、计策、结算等反馈音"],
]

## 滑块 -> 百分比文字，便于回读
var _value_labels: Dictionary = {}
var _sliders: Dictionary = {}
## 上一次播放试听音的时间戳（毫秒），用于节流
var _last_preview_ms := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _audio() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKit.make_panel(UiKit.COL_PANEL, UiKit.COL_GOLD.darkened(0.45))
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(UiKit.make_margin(box, 28))

	var title := UiKit.make_label("游 戏 设 置", 30, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# ---------------- 音量 ----------------
	var vol_title := UiKit.make_label("音量", 20, UiKit.COL_TEXT)
	box.add_child(vol_title)

	box.add_child(HSeparator.new())

	var am := _audio()
	if am == null:
		var warn := UiKit.make_label("音频模块不可用，音量设置暂不可调。", 14, UiKit.COL_LOSE)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(warn)
	else:
		for item in VOLUME_ROWS:
			_add_volume_row(box, am, str(item[0]), str(item[1]), str(item[2]))

	box.add_child(UiKit.spacer(4))

	# ---------------- 其他 ----------------
	var other_title := UiKit.make_label("其他", 20, UiKit.COL_TEXT)
	box.add_child(other_title)

	box.add_child(HSeparator.new())

	var note := UiKit.make_label(
		"动画速度与 AI 难度将在后续版本加入。", 13, UiKit.COL_TEXT_DIM)
	box.add_child(note)

	if net_mode:
		box.add_child(UiKit.spacer(6))
		box.add_child(HSeparator.new())

		var net_title := UiKit.make_label("联机对局中不可用", 17, UiKit.COL_LOSE)
		net_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(net_title)

		var net_desc := UiKit.make_label(
			"联机对局由主机权威状态驱动，以下选项无法各自设置：", 13, UiKit.COL_TEXT_DIM)
		net_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(net_desc)

		for item in NET_UNSUPPORTED:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			box.add_child(row)

			var name_label := UiKit.make_label(str(item[0]), 15, UiKit.COL_TEXT_DIM)
			name_label.custom_minimum_size = Vector2(110, 0)
			row.add_child(name_label)

			var state_label := UiKit.make_label("已禁用 —— %s" % str(item[1]), 13,
				Color(0.72, 0.45, 0.38))
			state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			state_label.custom_minimum_size = Vector2(360, 0)
			row.add_child(state_label)

	box.add_child(UiKit.spacer(6))

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(button_row)
	var back_button := UiKit.make_button("返回", UiKit.COL_TEXT_DIM, 18, Vector2(180, 46))
	back_button.pressed.connect(func(): back.emit())
	button_row.add_child(back_button)


## 一行音量控制：名称 + 滑块 + 百分比。
func _add_volume_row(box: VBoxContainer, am: Node, bus_name: String, label_text: String, hint: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var name_label := UiKit.make_label(label_text, 16, UiKit.COL_TEXT)
	name_label.custom_minimum_size = Vector2(90, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = am.get_volume(bus_name)
	slider.custom_minimum_size = Vector2(320, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	row.add_child(slider)

	var pct := UiKit.make_label("", 15, UiKit.COL_GOLD)
	pct.custom_minimum_size = Vector2(52, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)

	slider.value_changed.connect(func(v: float): _on_volume_changed(am, bus_name, v))
	_sliders[bus_name] = slider
	_value_labels[bus_name] = pct
	_update_pct(bus_name, slider.value)

	var hint_label := UiKit.make_label(hint, 12, UiKit.COL_TEXT_DIM)
	box.add_child(hint_label)


func _on_volume_changed(am: Node, bus_name: String, value: float) -> void:
	am.set_volume(bus_name, value)
	_update_pct(bus_name, value)
	# 调「音效」或「主音量」时立刻试听一声 ——
	# 否则玩家只能退出设置、进对局才知道自己调得合不合适。
	# 「背景音乐」不放试听音：那会与正在播的 BGM 混在一起，反而听不清楚。
	if bus_name == AudioManager.BUS_SFX or bus_name == AudioManager.BUS_MASTER:
		_preview_click(value)


## 拖动滑块时的试听音（带节流）。
## HSlider 拖动会连续发 value_changed，不节流会变成一串爆豆。
func _preview_click(value: float) -> void:
	if value <= 0.001:
		return                      # 已经拉到静音了，播了也听不见
	var now := Time.get_ticks_msec()
	if now - _last_preview_ms < 220:
		return
	_last_preview_ms = now
	UiKit.sfx("click", 0.05)


func _update_pct(bus_name: String, value: float) -> void:
	if not _value_labels.has(bus_name):
		return
	var label: Label = _value_labels[bus_name]
	label.text = "%d%%" % int(roundf(value * 100.0))
	# 静音时用暗色提示
	label.add_theme_color_override("font_color",
		UiKit.COL_TEXT_DIM if value <= 0.001 else UiKit.COL_GOLD)


## 给 HSlider 套上本作配色。
func _style_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override("slider",
		UiKit.panel_style(Color("1d1915"), UiKit.COL_BORDER, 3))
	slider.add_theme_stylebox_override("grabber_area",
		UiKit.panel_style(UiKit.COL_GOLD.darkened(0.35), UiKit.COL_GOLD.darkened(0.35), 3))
	slider.add_theme_stylebox_override("grabber_area_highlight",
		UiKit.panel_style(UiKit.COL_GOLD, UiKit.COL_GOLD, 3))
