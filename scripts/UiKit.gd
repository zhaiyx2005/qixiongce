extends RefCounted
class_name UiKit

## 共享 UI 工具：主题、配色、面板/标签/按钮/图标构建。
## 所有界面模块（主菜单、牌库编辑、对局）都从这里取素材，保证风格统一。

# ---------------- 配色 ----------------
const COL_BG := Color("10171c")
const COL_PANEL := Color("1b252b")
const COL_PANEL_SOFT := Color("243038")
const COL_PANEL_HI := Color("303d43")
const COL_BORDER := Color("526067")
const COL_TEXT := Color("e9e0d1")
const COL_TEXT_DIM := Color("9a9080")
const COL_GOLD := Color("d8b26c")
const COL_SELECT := Color("f0c877")
const COL_LOSE := Color("c9603f")
const COL_WIN := Color("7fa86a")
const COL_DROP_OK := Color("9ec97a")
const COL_DROP_NO := Color("d05a45")

const FACTION_NAMES := {
	CardData.FACTION_QIN: "秦",
	CardData.FACTION_QI: "齐",
	CardData.FACTION_CHU: "楚",
	CardData.FACTION_YAN: "燕",
	CardData.FACTION_HAN: "韩",
	CardData.FACTION_ZHAO: "赵",
	CardData.FACTION_WEI: "魏",
}
## 七国主题色。选色原则：① 亮度接近，避免某个国在深色底上"跳出来"；
## ② 相邻国家色相拉开，七张阵营卡并在时仍能一眼分清（尤其秦的橙 vs 楚的朱红）。
const FACTION_COLORS := {
	CardData.FACTION_QIN: Color("c8794f"),    # 秦 · 橙褐
	CardData.FACTION_QI: Color("8e6bbf"),     # 齐 · 紫
	CardData.FACTION_CHU: Color("c2554f"),    # 楚 · 朱红
	CardData.FACTION_YAN: Color("4f8f8a"),    # 燕 · 青碧
	CardData.FACTION_HAN: Color("b0a98f"),    # 韩 · 素白
	CardData.FACTION_ZHAO: Color("6f93bd"),   # 赵 · 靛蓝
	CardData.FACTION_WEI: Color("8fa35c"),    # 魏 · 橄榄
}

# ---------------- 图标 ----------------
const ICON_POWER := "res://assets/icon_power.svg"
const ICON_GEM := "res://assets/icon_gem.svg"
const ICON_CITY := "res://assets/icon_city.svg"
const ICON_HAND := "res://assets/icon_hand.svg"
const ICON_DECK := "res://assets/icon_deck.svg"
const ICON_DISCARD := "res://assets/icon_discard.svg"
const ICON_LEADER := "res://assets/icon_leader.svg"


static func faction_name(faction: String) -> String:
	return FACTION_NAMES.get(faction, faction)


static func faction_color(faction: String) -> Color:
	return FACTION_COLORS.get(faction, COL_TEXT)


# ---------------- 主题 ----------------

## 注册系统中文字体（Godot 默认字体没有中文字形）
static func apply_theme(root: Control) -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei",
		"Noto Sans CJK SC", "sans-serif",
	])
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 14
	root.theme = th


# ---------------- 基础控件 ----------------

static func panel_style(bg: Color, border_color := COL_BORDER, radius := 6, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style


static func make_panel(bg := COL_PANEL, border_color := COL_BORDER, radius := 6) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style(bg, border_color, radius))
	return panel


static func make_margin(node: Control, margin: int) -> MarginContainer:
	var box := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		box.add_theme_constant_override("margin_" + side, margin)
	box.add_child(node)
	return box


static func make_label(text: String, size: int, color := COL_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func style_button(button: Button, accent: Color, font_size := 16) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COL_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.48, 1))
	button.add_theme_stylebox_override("normal", panel_style(COL_PANEL_SOFT, accent.darkened(0.35), 8))
	button.add_theme_stylebox_override("hover", panel_style(COL_PANEL_HI, accent, 8, 2))
	button.add_theme_stylebox_override("pressed", panel_style(Color("241f1a"), accent))
	button.add_theme_stylebox_override("disabled", panel_style(Color("262220"), Color(1, 1, 1, 0.05)))
	button.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), COL_SELECT, 8, 2))


static func make_button(text: String, accent: Color, font_size := 16, min_size := Vector2(180, 44)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	style_button(button, accent, font_size)
	# 【为什么在这里统一挂】按钮的点击音分散在几十个调用点，逐个手写必然漏；
	# 全部按钮都由本工厂创建，集中挂载是唯一可靠的位置。
	# 加一点随机音高，连点同一个按钮时不会听起来像复读机。
	button.pressed.connect(func() -> void: sfx("click", 0.06))
	return button


static func spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func h_spring() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


# ---------------- 音效 ----------------

## 播放音效的便捷入口：任意脚本直接 `UiKit.sfx("click")`。
##
## 【为什么放在 UiKit 而不是 AudioManager】AudioManager 是 Autoload **实例**，
## 通过单例名调用它的静态方法在 Godot 里语义含糊；而 UiKit 已经是全局静态工具类，
## 各界面本来就引用它，在这里转发一次最省事，也让调用点只有一种写法。
##
## 找不到 AudioManager（例如没有 Autoload 的裸测试）时**静默跳过** ——
## 音效是装饰，任何情况下都不该影响游戏流程。
static func sfx(name: String, pitch_variation: float = 0.0, base_pitch: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var am: Node = tree.root.get_node_or_null("AudioManager")
	if am != null:
		am.call("play_sfx", name, pitch_variation, base_pitch)


## 图标贴图（带缓存；缺失返回 null）
static func icon_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func make_icon(path: String, px := 18, tint := Color(1, 1, 1, 1)) -> Control:
	var tex := icon_texture(path)
	if tex == null:
		var fallback := ColorRect.new()
		fallback.color = tint
		fallback.custom_minimum_size = Vector2(px, px)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return fallback
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(px, px)
	rect.modulate = tint
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## 图标 + 文字 一行
static func make_icon_label(icon_path: String, text: String, size: int, color := COL_TEXT, icon_px := 18) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(make_icon(icon_path, icon_px))
	var label := make_label(text, size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row
