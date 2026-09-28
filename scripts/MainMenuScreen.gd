extends Control
class_name MainMenuScreen

## 主菜单：开始游戏 / 联机对战 / 整理牌库 / 游戏设置 / 退出游戏

signal start_game
signal open_lobby
signal open_decks
signal open_settings
signal quit_game

const BUTTON_SIZE := Vector2(280, 56)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


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

	var title := UiKit.make_label("七 雄 策", 64, UiKit.COL_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := UiKit.make_label("战国卡牌对战 · Demo · 三局两胜", 16, UiKit.COL_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(UiKit.spacer(24))

	_add_button(box, "开始游戏", UiKit.COL_GOLD, 22, func(): start_game.emit())
	_add_button(box, "联机对战", UiKit.COL_WIN, 20, func(): open_lobby.emit())
	_add_button(box, "整理牌库", UiKit.COL_TEXT_DIM, 20, func(): open_decks.emit())
	_add_button(box, "游戏设置", UiKit.COL_TEXT_DIM, 20, func(): open_settings.emit())
	_add_button(box, "退出游戏", UiKit.COL_LOSE, 20, func(): quit_game.emit())

	box.add_child(UiKit.spacer(20))

	var hint := UiKit.make_label("开始游戏 → 选择秦 / 赵 → 换牌 → 对局　|　联机对战 → 创建 / 加入房间", 13, Color(1, 1, 1, 0.28))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _add_button(parent: Control, text: String, accent: Color, font_size: int, action: Callable) -> void:
	var button := UiKit.make_button(text, accent, font_size, BUTTON_SIZE)
	button.pressed.connect(action)
	parent.add_child(button)
