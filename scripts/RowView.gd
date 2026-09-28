extends PanelContainer
class_name RowView

## 一条战场行：左侧圆形行战力 + 行名，右侧横向排列已打出的单位卡。
## 同时是拖拽落点（行匹配亮绿、不匹配亮红），场上卡牌支持右键查看。

signal card_dropped(card: CardData, row_id: String, index: int)
signal info_requested(card: CardData)

enum DropState { NONE, VALID, INVALID }

const COL_PANEL := Color("221d19")
const COL_BADGE_BG := Color("2b231b")
const ROW_TITLES := {
	CardData.ROW_MELEE: "近战",
	CardData.ROW_RANGED: "远程",
	CardData.ROW_GARRISON: "守军",
}

var row_id: String = ""
## 对手的行设为 false：仍然能右键看牌，但不接受拖放
var accepts_drop := true
## 由对局界面注入：判断“现在这张牌能不能落到本行”
var drop_filter: Callable = Callable()
## 是否接受**计策牌**拖放（5C：计策拖到场上任意位置即可释放，不需要选目标行）
var accepts_tactic := false

var _power_label: Label
var _cards_box: HBoxContainer
var _empty_hint: Label
var _insert_marker: ColorRect
var _style_box: StyleBoxFlat
var _drop_state: int = DropState.NONE
var _has_cards := false
var _drag_hint_active := false
var _base_bg: Color = COL_PANEL
var _pending_index := 0


func setup(p_row_id: String, bg: Color = COL_PANEL) -> void:
	row_id = p_row_id
	_base_bg = bg
	custom_minimum_size = Vector2(0, 66)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_style_box = UiKit.panel_style(_base_bg, Color(1, 1, 1, 0.06), 4)
	add_theme_stylebox_override("panel", _style_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	# 左侧：圆形战力数字 + 行名
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(66, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 1)
	hbox.add_child(left)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel",
		UiKit.panel_style(COL_BADGE_BG, UiKit.COL_GOLD.darkened(0.35), 19, 2))
	left.add_child(badge)

	_power_label = UiKit.make_label("0", 18, UiKit.COL_GOLD)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(_power_label)

	var title := UiKit.make_label(ROW_TITLES.get(row_id, row_id), 12, Color(1, 1, 1, 0.42))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(title)

	# 右侧：卡牌区域
	var cards_holder := Control.new()
	cards_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cards_holder)

	_cards_box = HBoxContainer.new()
	_cards_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_box.add_theme_constant_override("separation", 5)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_holder.add_child(_cards_box)

	# 拖拽时的插入指示线（金色，略高于卡牌）
	_insert_marker = ColorRect.new()
	_insert_marker.color = UiKit.COL_SELECT
	_insert_marker.custom_minimum_size = Vector2(3, 0)
	_insert_marker.size = Vector2(3, 40)
	_insert_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insert_marker.visible = false
	cards_holder.add_child(_insert_marker)

	_empty_hint = UiKit.make_label("", 13, Color(1, 1, 1, 0.13))
	_empty_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_holder.add_child(_empty_hint)

	mouse_filter = Control.MOUSE_FILTER_STOP


## cards 为显示顺序；powers 为与之对应的实时战力（可省，省略则显示卡面战力）。
func refresh(cards: Array[CardData], power: int, powers: Array = []) -> void:
	_power_label.text = str(power)
	_power_label.add_theme_color_override("font_color",
		UiKit.COL_GOLD if power > 0 else Color(1, 1, 1, 0.3))
	for child in _cards_box.get_children():
		_cards_box.remove_child(child)
		child.queue_free()
	for i in range(cards.size()):
		var card := cards[i]
		var view := CardView.new()
		view.setup(card, CardView.Style.BOARD)
		view.set_interaction(false, false, true)
		view.card_right_clicked.connect(_on_board_card_right_clicked)
		if i < powers.size():
			view.set_live_power(int(powers[i]))
		else:
			view.set_live_power(int(view.data.power))
		_cards_box.add_child(view)
	_has_cards = not cards.is_empty()
	_update_hint()
	reset_drop_state()


func _on_board_card_right_clicked(card: CardData, _view: CardView) -> void:
	info_requested.emit(card)


func reset_drop_state() -> void:
	_drop_state = DropState.NONE
	if _insert_marker != null:
		_insert_marker.visible = false
	_apply_drop_style()


# ---------------- 拖拽落点 ----------------

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not accepts_drop:
		return false
	if not (data is Dictionary) or not data.has("card"):
		return false
	var card: CardData = data["card"]
	if card == null:
		return false

	# 计策牌：不占行，拖到场上任意一行都算「释放」。此时落点不排序，
	# 统一给 -1，由 MatchScreen 走 play_tactic 指令。
	if card.card_type == CardData.TYPE_TACTIC:
		if not accepts_tactic:
			return false
		var tactic_ok := true
		if drop_filter.is_valid():
			tactic_ok = bool(drop_filter.call(card))
		_drop_state = DropState.VALID if tactic_ok else DropState.INVALID
		_apply_drop_style()
		_pending_index = -1
		_insert_marker.visible = false
		return tactic_ok

	# 合法行由兵种推导（card.can_place_in），不再直接比较 card.row
	var ok := card.can_place_in(row_id)
	if ok and drop_filter.is_valid():
		ok = bool(drop_filter.call(card))
	_drop_state = DropState.VALID if ok else DropState.INVALID
	_apply_drop_style()
	if ok:
		_pending_index = _insert_index_at(at_position)
		_show_insert_marker(_pending_index)
	else:
		_insert_marker.visible = false
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var index := _pending_index
	reset_drop_state()
	if data is Dictionary and data.has("card"):
		card_dropped.emit(data["card"], row_id, index)


## 插入索引：以每张卡牌的水平中心为界
func _insert_index_at(local_position: Vector2) -> int:
	var global_x := global_position.x + local_position.x
	var count := _cards_box.get_child_count()
	for i in range(count):
		var card: Control = _cards_box.get_child(i)
		if global_x < card.global_position.x + card.size.x * 0.5:
			return i
	return count


func _show_insert_marker(index: int) -> void:
	var count := _cards_box.get_child_count()
	var x := 0.0
	if count > 0:
		if index >= count:
			var last: Control = _cards_box.get_child(count - 1)
			x = last.position.x + last.size.x + 3.0
		else:
			var card: Control = _cards_box.get_child(index)
			x = card.position.x - 3.0
	_insert_marker.size = Vector2(3, maxf(_cards_box.size.y + 8.0, 24.0))
	_insert_marker.position = Vector2(maxf(x, 0.0), -4.0)
	_insert_marker.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
		reset_drop_state()


func _apply_drop_style() -> void:
	match _drop_state:
		DropState.VALID:
			_style_box.border_color = UiKit.COL_DROP_OK
			_style_box.set_border_width_all(3)
			_style_box.bg_color = Color("2c3524")
		DropState.INVALID:
			_style_box.border_color = UiKit.COL_DROP_NO
			_style_box.set_border_width_all(3)
			_style_box.bg_color = Color("35221d")
		_:
			_style_box.border_color = Color(1, 1, 1, 0.06)
			_style_box.set_border_width_all(1)
			_style_box.bg_color = _base_bg


func set_drag_hint(active: bool) -> void:
	_drag_hint_active = active
	_update_hint()


func _update_hint() -> void:
	if _has_cards:
		_empty_hint.text = ""
		return
	_empty_hint.text = "← 拖拽到此行" if _drag_hint_active else ""
	_empty_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.3 if _drag_hint_active else 0.13))
