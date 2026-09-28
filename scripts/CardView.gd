extends Control
class_name CardView

## 单张卡牌控件（纯代码构建）。
## 支持：点击 / 右键 / 悬停放大 / 拖拽出牌 / 角标（数量或计数）。
## 三种尺寸：BOARD（战场行内）、HAND（手牌与领袖）、EDITOR（牌库编辑）。

signal card_clicked(card: CardData, view: CardView)
signal card_right_clicked(card: CardData, view: CardView)
signal drag_began(card: CardData, view: CardView)

enum Style { BOARD, HAND, EDITOR }

const SIZES := {
	Style.BOARD: Vector2(62, 60),
	Style.HAND: Vector2(88, 118),
	Style.EDITOR: Vector2(84, 112),
}
const NAME_FONT := { Style.BOARD: 10, Style.HAND: 15, Style.EDITOR: 13 }
const POWER_FONT := { Style.BOARD: 17, Style.HAND: 26, Style.EDITOR: 22 }
const ROW_FONT := { Style.BOARD: 8, Style.HAND: 10, Style.EDITOR: 10 }
const MARGINS := { Style.BOARD: 3, Style.HAND: 7, Style.EDITOR: 6 }
const HOVER_SCALE := 1.15

const COL_TEXT := Color("efe6d6")
const COL_DIM := Color("b3a894")
const COL_GOLD := Color("d8b26c")
const COL_SELECT := Color("f0c877")
## 卡面底色（七国）。都是在深色系里取该国主题色的暗化版，
## 保证卡上的浅色文字（COL_TEXT）与金色标题始终可读。
const FACTION_BG := {
	CardData.FACTION_QIN: Color("5e2a26"),    # 秦
	CardData.FACTION_QI: Color("3d2b52"),     # 齐
	CardData.FACTION_CHU: Color("5c2422"),    # 楚
	CardData.FACTION_YAN: Color("1f3b3a"),    # 燕
	CardData.FACTION_HAN: Color("45423a"),    # 韩
	CardData.FACTION_ZHAO: Color("233d56"),   # 赵
	CardData.FACTION_WEI: Color("37401f"),    # 魏
}
const ROW_BORDER := {
	CardData.ROW_MELEE: Color("a5563f"),
	CardData.ROW_RANGED: Color("6d8f5a"),
	CardData.ROW_GARRISON: Color("5b7590"),
}
## 未知阵营时的兜底底色。
const SHARED_BG := Color("3a332b")

var data: CardData = null
var style: int = Style.BOARD

var clickable := false
var draggable := false
var hoverable := true
var selected := false
var playable := true
## 场上卡牌显示实时战力（含增益）；为 -1 时用卡面战力
var live_power := -1

var _panel: PanelContainer
var _style_box: StyleBoxFlat
var _name_label: Label
var _row_label: Label
var _power_label: Label
var _badge: Label
var _hovering := false


static func row_display_name(row: String) -> String:
	match row:
		CardData.ROW_MELEE:
			return "近战"
		CardData.ROW_RANGED:
			return "远程"
		CardData.ROW_GARRISON:
			return "守军"
	return ""


## 卡牌类型 / 兵种的简短标签（显示在行名位置）。
static func category_display_name(card: CardData) -> String:
	match card.category():
		CardData.CATEGORY_LEADER:
			return "领袖"
		CardData.CATEGORY_TACTIC:
			return "计策"
		CardData.UNIT_HERO:
			return "英杰"
		CardData.UNIT_INFANTRY:
			return "步卒"
		CardData.UNIT_ARCHER:
			return "弓弩"
		CardData.UNIT_CAVALRY:
			return "骑兵"
	return ""


## 卡牌完整说明（悬停提示 / 卡牌信息弹窗用）。
static func describe(card: CardData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("【%s】%s" % [category_display_name(card), card.name])
	if card.card_type == CardData.TYPE_UNIT:
		var rows: PackedStringArray = PackedStringArray()
		for row in card.legal_rows():
			rows.append(row_display_name(row))
		parts.append("战力 %d　可落：%s" % [card.power, " / ".join(rows)])
	var ability_name := Abilities.ability_name(card.ability_id)
	var ability_text := Abilities.ability_text(card.ability_id)
	if not ability_name.is_empty():
		parts.append("%s：%s" % [ability_name, ability_text])
	return "\n".join(parts)


func setup(card: CardData, p_style: int = Style.BOARD) -> void:
	data = card
	style = p_style
	custom_minimum_size = SIZES[style]
	tooltip_text = describe(card)
	_build()
	_apply_style()


## 更新实时战力显示（场上卡牌用）。
func set_live_power(value: int) -> void:
	live_power = value
	if _power_label != null and data != null and data.card_type == CardData.TYPE_UNIT:
		_power_label.text = str(value)
		var diff := value - data.power
		if data.is_hero():
			_power_label.add_theme_color_override("font_color", COL_GOLD)
		elif diff > 0:
			_power_label.add_theme_color_override("font_color", UiKit.COL_DROP_OK)
		elif diff < 0:
			_power_label.add_theme_color_override("font_color", UiKit.COL_DROP_NO)
		else:
			_power_label.add_theme_color_override("font_color", COL_GOLD)


## 设置交互能力（点击 / 拖拽 / 悬停放大）
func set_interaction(can_click: bool, can_drag: bool, can_hover: bool) -> void:
	clickable = can_click
	draggable = can_drag
	hoverable = can_hover
	mouse_filter = Control.MOUSE_FILTER_STOP if (clickable or draggable or can_hover) else Control.MOUSE_FILTER_IGNORE
	_apply_style()


func set_playable(value: bool) -> void:
	playable = value
	_apply_style()


func set_selected(value: bool) -> void:
	selected = value
	_apply_style()


## 角标：显示数量（如牌库编辑的 “×2”），传空串隐藏
func set_badge(text: String) -> void:
	if _badge == null:
		return
	_badge.text = text
	_badge.visible = not text.is_empty()


func reset_hover() -> void:
	_hovering = false
	_apply_hover()


# ---------------- 构建 ----------------

func _build() -> void:
	var margin_px: int = MARGINS[style]

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_box = UiKit.panel_style(FACTION_BG.get(data.faction, SHARED_BG), Color("000000"), 5)
	_panel.add_theme_stylebox_override("panel", _style_box)
	add_child(_panel)

	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, margin_px)
	_panel.add_child(inner)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(box)

	_name_label = UiKit.make_label(data.name, NAME_FONT[style], COL_TEXT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 2)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(footer)

	_row_label = UiKit.make_label(_footer_left_text(), ROW_FONT[style], _footer_left_color())
	_row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_row_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_row_label)

	_power_label = UiKit.make_label(str(data.power), POWER_FONT[style], COL_GOLD)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_power_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_power_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_power_label)

	# 领袖 / 计策不参与战力结算，卡面上不显示战力数字
	if data.card_type != CardData.TYPE_UNIT:
		_power_label.visible = false

	_badge = UiKit.make_label("", 13, Color.WHITE)
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.custom_minimum_size = Vector2(26, 20)
	_badge.add_theme_stylebox_override("normal", UiKit.panel_style(COL_SELECT, Color("2a2118"), 10))
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_top = 0.0
	_badge.anchor_bottom = 0.0
	_badge.offset_left = -30.0
	_badge.offset_right = -4.0
	_badge.offset_top = 2.0
	_badge.offset_bottom = 22.0
	_badge.visible = false
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _apply_style() -> void:
	var bg: Color = FACTION_BG.get(data.faction, SHARED_BG)
	var border: Color = _border_color()
	var width := 2
	if selected:
		border = COL_SELECT
		width = 3
		bg = bg.lightened(0.12)
	elif clickable or draggable:
		border = border.lightened(0.35)
		width = 3
	if _hovering:
		border = border.lightened(0.45)
		width = 3
	_style_box.bg_color = bg
	_style_box.border_color = border
	_style_box.set_border_width_all(width)
	_style_box.set_corner_radius_all(5)

	if clickable or draggable:
		modulate = Color(1, 1, 1, 1) if playable else Color(0.6, 0.58, 0.56, 1)
	else:
		modulate = Color(1, 1, 1, 1)


## 卡面底部左侧文字：单位显示默认行名，英杰显示「英杰」，计策显示「计策」。
func _footer_left_text() -> String:
	match data.category():
		CardData.CATEGORY_LEADER:
			return "领袖"
		CardData.CATEGORY_TACTIC:
			return "计策"
		CardData.UNIT_HERO:
			return "英杰"
	return row_display_name(data.row)


func _footer_left_color() -> Color:
	match data.category():
		CardData.CATEGORY_LEADER:
			return COL_GOLD
		CardData.CATEGORY_TACTIC:
			return Color("c9a0dc")
		CardData.UNIT_HERO:
			return COL_SELECT
	return ROW_BORDER.get(data.row, COL_DIM)


## 边框颜色：由卡牌可落的行推导（多行时取第一行的颜色）。
func _border_color() -> Color:
	var rows := data.legal_rows()
	if rows.is_empty():
		if data.card_type == CardData.TYPE_TACTIC:
			return Color("8a6ea8")
		return COL_GOLD if data.is_leader else COL_DIM
	if data.is_hero():
		return COL_SELECT
	return ROW_BORDER.get(rows[0], COL_DIM)


# ---------------- 悬停 ----------------

func _on_mouse_entered() -> void:
	if not hoverable:
		return
	_hovering = true
	_apply_hover()
	_apply_style()


func _on_mouse_exited() -> void:
	if not hoverable:
		return
	_hovering = false
	_apply_hover()
	_apply_style()


func _apply_hover() -> void:
	if _hovering:
		pivot_offset = Vector2(custom_minimum_size.x * 0.5, custom_minimum_size.y)
		scale = Vector2(HOVER_SCALE, HOVER_SCALE)
		z_index = 20
		_style_box.shadow_color = Color(0, 0, 0, 0.55)
		_style_box.shadow_size = 6
		_style_box.shadow_offset = Vector2(0, -3)
	else:
		scale = Vector2.ONE
		z_index = 0
		_style_box.shadow_color = Color(0, 0, 0, 0.35)
		_style_box.shadow_size = 2
		_style_box.shadow_offset = Vector2(0, 1)


# ---------------- 交互 ----------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and clickable:
		card_clicked.emit(data, self)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		card_right_clicked.emit(data, self)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := CardView.new()
	preview.setup(data, style)
	preview.set_interaction(false, false, false)
	preview.modulate = Color(1, 1, 1, 0.9)
	var holder := Control.new()
	preview.position = -SIZES[style] * 0.5
	holder.add_child(preview)
	set_drag_preview(holder)
	drag_began.emit(data, self)
	return {"card": data, "source": self}
