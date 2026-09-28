extends Control
class_name DeckEditorScreen

## 整理牌库：选阵营 → 按分类卡池构筑 → 存到 user://decks/<faction>.json
##
## 构筑规格（29 张）：
##   普通单位 20 · 英杰 2 · 计策 6 · 领袖 1
##   同名普通 / 计策 ≤ 3；英杰同名 ≤ 1
##
## 卡池按分类分区显示，每组独立计数与上限提示。

signal back

const GRID_COLUMNS := 10

## 分区定义：key -> { title, hint, need }
const SECTIONS := [
	{"key": CardData.CATEGORY_LEADER, "title": "领袖", "need": 1},
	{"key": CardData.UNIT_HERO, "title": "英杰", "need": 2},
	{"key": CardData.UNIT_INFANTRY, "title": "步卒", "need": -1},
	{"key": CardData.UNIT_ARCHER, "title": "弓弩手", "need": -1},
	{"key": CardData.UNIT_CAVALRY, "title": "骑兵", "need": -1},
	{"key": CardData.CATEGORY_TACTIC, "title": "计策", "need": 6},
]

## 步卒 / 弓弩手 / 骑兵 三组合计 20 张
const NORMAL_TOTAL := DeckRules.NORMAL_UNITS

var _db: CardDB
var _faction: String = CardData.FACTION_QIN
var _counts: Dictionary = {}
var _leader_id: String = ""

var _sections_box: VBoxContainer
var _cards_by_id: Dictionary = {}      # id -> CardView
var _section_heads: Dictionary = {}    # section key -> Label（计数）
var _title_label: Label
var _normal_label: Label
var _hero_label: Label
var _tactic_label: Label
var _leader_label: Label
var _deck_list_label: RichTextLabel
var _message_label: Label


func setup(db: CardDB) -> void:
	_db = db


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _db == null:
		_db = CardDB.new()
	_load_state()
	_build()
	_rebuild_pool()
	_refresh_all()


# ---------------- 状态 ----------------

func _load_state() -> void:
	var deck := DeckList.load_for_faction(_faction, _db)
	if deck == null:
		deck = DeckList.preset_for(_faction, _db)
	_apply_deck(deck)


func _apply_deck(deck: DeckList) -> void:
	_counts.clear()
	_leader_id = ""
	for entry in deck.entries():
		var card := _db.get_card_by_id(entry["id"])
		if card == null:
			continue
		if card.card_type == CardData.TYPE_LEADER:
			_leader_id = card.id
		else:
			_counts[card.id] = int(entry["count"])
	if _leader_id.is_empty():
		var leaders := _db.get_leader_cards(_faction)
		if not leaders.is_empty():
			_leader_id = leaders[0].id


func _counts_by_category() -> Dictionary:
	var out := {"normal": 0, "hero": 0, "tactic": 0, "leader": 0}
	for id in _counts.keys():
		var card := _db.get_card_by_id(id)
		if card == null:
			continue
		var n := int(_counts[id])
		if card.is_hero():
			out["hero"] += n
		elif card.card_type == CardData.TYPE_TACTIC:
			out["tactic"] += n
		else:
			out["normal"] += n
	if not _leader_id.is_empty():
		out["leader"] = 1
	return out


func _build_deck() -> DeckList:
	var deck := DeckList.new(_faction, "%s 自定义卡组" % UiKit.faction_name(_faction))
	for id in _counts.keys():
		deck.set_card_count(id, int(_counts[id]))
	if not _leader_id.is_empty():
		deck.set_card_count(_leader_id, 1)
	return deck


## 该分类当前是否已达上限（用于左键添加前的拦截）。
func _category_at_limit(card: CardData) -> bool:
	var c := _counts_by_category()
	match card.category():
		CardData.CATEGORY_LEADER:
			return c["leader"] >= DeckRules.LEADERS
		CardData.UNIT_HERO:
			return c["hero"] >= DeckRules.HEROES
		CardData.CATEGORY_TACTIC:
			return c["tactic"] >= DeckRules.TACTICS
		_:
			return c["normal"] >= NORMAL_TOTAL


# ---------------- 构建 ----------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 10)
	margin.add_child(split)

	# 左侧：分类卡池
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)

	left.add_child(_build_header())
	left.add_child(_build_counters())
	left.add_child(_build_pool_scroll())
	left.add_child(_build_footer())

	# 右侧：牌库概览
	split.add_child(_build_side_panel())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	_title_label = UiKit.make_label("整理牌库", 24, UiKit.COL_GOLD)
	row.add_child(_title_label)
	row.add_child(UiKit.make_label("左键添加 / 右键移除", 12, UiKit.COL_TEXT_DIM))
	row.add_child(UiKit.h_spring())

	# 七国按钮：顺序固定走 CardData.FACTIONS，位置不会乱跳。
	for faction in CardData.FACTIONS:
		row.add_child(_make_faction_button(faction))
	return row


func _make_faction_button(faction: String) -> Button:
	var button := UiKit.make_button(UiKit.faction_name(faction), UiKit.faction_color(faction), 16, Vector2(64, 36))
	button.pressed.connect(func(): _switch_faction(faction))
	return button


## 四组计数：普通单位 20 / 英杰 2 / 计策 6 / 领袖 1
func _build_counters() -> Control:
	var panel := UiKit.make_panel(UiKit.COL_PANEL)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(UiKit.make_margin(row, 8))

	_normal_label = UiKit.make_label("", 17, UiKit.COL_TEXT)
	_hero_label = UiKit.make_label("", 17, UiKit.COL_TEXT)
	_tactic_label = UiKit.make_label("", 17, UiKit.COL_TEXT)
	_leader_label = UiKit.make_label("", 17, UiKit.COL_TEXT)
	for node in [_normal_label, _hero_label, _tactic_label, _leader_label]:
		row.add_child(node)
	row.add_child(UiKit.h_spring())
	return panel


func _build_pool_scroll() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 4)
	_sections_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections_box)
	return scroll


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var save_button := UiKit.make_button("保存卡组", UiKit.COL_GOLD, 18, Vector2(160, 44))
	save_button.pressed.connect(_on_save)
	row.add_child(save_button)

	var reset_button := UiKit.make_button("恢复预设", UiKit.COL_TEXT_DIM, 16, Vector2(130, 44))
	reset_button.pressed.connect(_on_reset)
	row.add_child(reset_button)

	# 系统推荐流派：按**当前所选国家**列出设计稿给它的两套流派。
	# 国家在标题栏切换，按钮跟着变，所以「每个国家都有一个自己的入口」。
	var arch_button := UiKit.make_button("推荐流派", UiKit.COL_WIN, 16, Vector2(130, 44))
	arch_button.pressed.connect(_open_archetypes)
	row.add_child(arch_button)

	var back_button := UiKit.make_button("返回主菜单", UiKit.COL_TEXT_DIM, 16, Vector2(140, 44))
	back_button.pressed.connect(func(): back.emit())
	row.add_child(back_button)

	_message_label = UiKit.make_label("", 13, UiKit.COL_TEXT_DIM)
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_message_label)
	return row


# ---------------- 系统推荐流派 ----------------

const ARCHETYPE_OVERLAY := "ArchetypeOverlay"


## 打开「推荐流派」浮层。
##
## 【浮层必须在最后 add_child】项目约定：绘制层级 = add_child 顺序。
## 本界面的卡池是 `_build()` 里挂上去的，所以浮层只能用「之后再加」的方式压住它，
## 不能用 move_child 去调（会被后面的重建逻辑打乱）。
## 关闭时整棵 queue_free，不留残留节点 —— 用名字查找而不是成员变量，
## 这样重建之后也不会拿到悬空引用。
func _open_archetypes() -> void:
	_close_archetypes()
	var items := Archetypes.list_for(_faction)
	if items.is_empty():
		_set_message("暂未为「%s」配置推荐流派。" % UiKit.faction_name(_faction), true)
		return

	var overlay := Control.new()
	overlay.name = ARCHETYPE_OVERLAY
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := UiKit.make_panel(UiKit.COL_PANEL)
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.make_margin(box, 16))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.make_label(
		"「%s」系统推荐流派" % UiKit.faction_name(_faction), 22, UiKit.COL_GOLD))
	head.add_child(UiKit.h_spring())
	var close_button := UiKit.make_button("关闭", UiKit.COL_TEXT_DIM, 14, Vector2(90, 34))
	close_button.pressed.connect(_close_archetypes)
	head.add_child(close_button)
	box.add_child(head)

	for i in range(items.size()):
		box.add_child(_build_archetype_row(items[i], i))

	box.add_child(UiKit.make_label(
		"载入后只是填进编辑器；点「保存卡组」才会写入并对局生效。",
		12, UiKit.COL_TEXT_DIM))


func _build_archetype_row(item: Dictionary, index: int) -> Control:
	var card_panel := UiKit.make_panel(Color(1, 1, 1, 0.05))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card_panel.add_child(UiKit.make_margin(box, 10))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiKit.make_label(Archetypes.title_of(item), 18, UiKit.COL_TEXT))
	head.add_child(UiKit.make_label(Archetypes.pace_line(item), 13, UiKit.COL_GOLD))
	head.add_child(UiKit.h_spring())
	var load_button := UiKit.make_button("载入这套", UiKit.COL_WIN, 15, Vector2(120, 36))
	load_button.pressed.connect(func(): _load_archetype(index))
	head.add_child(load_button)
	box.add_child(head)

	var body := UiKit.make_label(Archetypes.summary(item), 13, UiKit.COL_TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	box.add_child(body)
	return card_panel


## 载入某套流派到编辑器（不落盘，由玩家再点保存）。
func _load_archetype(index: int) -> void:
	var items := Archetypes.list_for(_faction)
	if index < 0 or index >= items.size():
		return
	var item: Dictionary = items[index]
	var deck := Archetypes.build(_faction, index, _db)
	if deck == null:
		UiKit.sfx("error")
		_set_message("载入失败：%s" % "；".join(Archetypes.load_errors()), true)
		return
	var errors := DeckRules.validate(deck, _db)
	if not errors.is_empty():
		UiKit.sfx("error")
		_set_message("「%s」不合法，已拒绝载入：%s" % [
			Archetypes.title_of(item), "；".join(errors)], true)
		return
	_apply_deck(deck)
	_refresh_all()
	_close_archetypes()
	UiKit.sfx("card_draw")
	_set_message("已载入「%s」，点「保存卡组」后对局生效。" % Archetypes.title_of(item), false)


func _close_archetypes() -> void:
	var overlay := get_node_or_null(ARCHETYPE_OVERLAY)
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()


func _build_side_panel() -> Control:
	var panel := UiKit.make_panel(UiKit.COL_PANEL)
	panel.custom_minimum_size = Vector2(280, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(UiKit.make_margin(box, 12))

	box.add_child(UiKit.make_label("当前牌库", 18, UiKit.COL_GOLD))

	_deck_list_label = RichTextLabel.new()
	_deck_list_label.scroll_active = true
	_deck_list_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deck_list_label.add_theme_font_size_override("normal_font_size", 12)
	_deck_list_label.add_theme_color_override("default_color", UiKit.COL_TEXT_DIM)
	box.add_child(_deck_list_label)

	var rules := UiKit.make_label(
		"规则：\n普通单位 20 · 英杰 2\n计策 6 · 领袖 1 = 29 张\n同名卡 ≤ 3（英杰 ≤ 1）\n保存后对局将优先生效",
		12, Color(1, 1, 1, 0.35))
	box.add_child(rules)
	return panel


# ---------------- 交互 ----------------

func _switch_faction(faction: String) -> void:
	if faction == _faction:
		return
	_faction = faction
	_load_state()
	_rebuild_pool()
	_refresh_all()


func _rebuild_pool() -> void:
	for child in _sections_box.get_children():
		_sections_box.remove_child(child)
		child.queue_free()
	_cards_by_id.clear()
	_section_heads.clear()

	for section in SECTIONS:
		var key: String = section["key"]
		var cards := _cards_for_section(key)
		if cards.is_empty():
			continue

		# 分区标题
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UiKit.make_label(str(section["title"]), 16, UiKit.COL_GOLD))
		var info := UiKit.make_label(_section_hint(key), 12, UiKit.COL_TEXT_DIM)
		head.add_child(info)
		head.add_child(UiKit.h_spring())
		var counter := UiKit.make_label("", 15, UiKit.COL_TEXT)
		head.add_child(counter)
		_section_heads[key] = counter
		_sections_box.add_child(head)

		var grid := GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		_sections_box.add_child(grid)

		for card in cards:
			var view := CardView.new()
			view.setup(card, CardView.Style.EDITOR)
			view.set_interaction(true, false, true)
			view.card_clicked.connect(_on_card_clicked)
			view.card_right_clicked.connect(_on_card_right_clicked)
			grid.add_child(view)
			_cards_by_id[card.id] = view

		_sections_box.add_child(UiKit.spacer(6))


func _cards_for_section(key: String) -> Array[CardData]:
	if key == CardData.CATEGORY_LEADER:
		return _db.get_leader_cards(_faction)
	if key == CardData.CATEGORY_TACTIC:
		return _db.get_tactic_cards_by_faction(_faction)
	if key == CardData.UNIT_HERO:
		return _db.get_hero_cards_by_faction(_faction)
	return _db.get_cards_by_category(_faction, key)


func _section_hint(key: String) -> String:
	match key:
		CardData.CATEGORY_LEADER:
			return "3 选 1"
		CardData.UNIT_HERO:
			return "每张只能 1 份"
		CardData.CATEGORY_TACTIC:
			return "打出即结算，不占行"
		_:
			return "近战 / 远程 / 守军（按兵种）"


func _on_card_clicked(card: CardData, _view: CardView) -> void:
	# 领袖是单选
	if card.card_type == CardData.TYPE_LEADER:
		_leader_id = card.id
		_set_message("领袖设为「%s」。" % card.name, false)
		_refresh_all()
		return

	var current := int(_counts.get(card.id, 0))
	var max_copies := DeckRules.MAX_COPIES_PER_HERO if card.is_hero() else DeckRules.MAX_COPIES_PER_NAME
	if current >= max_copies:
		if card.is_hero():
			_set_message("英杰「%s」只能携带 1 张。" % card.name, true)
		else:
			_set_message("「%s」已达同名上限 %d 张。" % [card.name, max_copies], true)
		return
	if _category_at_limit(card):
		_set_message("%s 已达上限（%s），先右键移除再加。" % [
			_category_label(card.category()), _category_quota_text(card.category())], true)
		return
	_counts[card.id] = current + 1
	_set_message("加入「%s」。" % card.name, false)
	_refresh_all()


func _on_card_right_clicked(card: CardData, _view: CardView) -> void:
	if card.card_type == CardData.TYPE_LEADER:
		_set_message("领袖不可移除，换选其他领袖即可。", true)
		return
	var current := int(_counts.get(card.id, 0))
	if current <= 0:
		_set_message("「%s」不在牌库中。" % card.name, true)
		return
	if current == 1:
		_counts.erase(card.id)
	else:
		_counts[card.id] = current - 1
	_set_message("移除「%s」。" % card.name, false)
	_refresh_all()


func _category_label(category: String) -> String:
	match category:
		CardData.CATEGORY_LEADER:
			return "领袖"
		CardData.UNIT_HERO:
			return "英杰"
		CardData.CATEGORY_TACTIC:
			return "计策"
		CardData.UNIT_INFANTRY:
			return "步卒"
		CardData.UNIT_ARCHER:
			return "弓弩手"
		CardData.UNIT_CAVALRY:
			return "骑兵"
	return category


func _category_quota_text(category: String) -> String:
	match category:
		CardData.CATEGORY_LEADER:
			return "%d 张" % DeckRules.LEADERS
		CardData.UNIT_HERO:
			return "%d 张" % DeckRules.HEROES
		CardData.CATEGORY_TACTIC:
			return "%d 张" % DeckRules.TACTICS
	return "普通单位合计 %d 张" % NORMAL_TOTAL


func _on_reset() -> void:
	UiKit.sfx("card_draw")
	_apply_deck(DeckList.preset_for(_faction, _db))
	_set_message("已恢复为预设卡组（未保存）。", false)
	_refresh_all()


func _on_save() -> void:
	var deck := _build_deck()
	var errors := DeckRules.validate(deck, _db)
	if not errors.is_empty():
		UiKit.sfx("error")
		_set_message("无法保存：" + "；".join(errors), true)
		return
	var path := DeckList.path_for(_faction)
	var err := deck.save_to_file(path)
	if err != OK:
		UiKit.sfx("error")
		_set_message("保存失败，错误码 %d。" % err, true)
		return
	UiKit.sfx("card_place")
	_set_message("已保存到 %s（%d 张）。" % [path, deck.size()], false)


# ---------------- 刷新 ----------------

func _refresh_all() -> void:
	var c := _counts_by_category()
	_title_label.text = "整理牌库 · %s" % UiKit.faction_name(_faction)

	_normal_label.text = "普通单位 %d / %d" % [int(c["normal"]), NORMAL_TOTAL]
	_hero_label.text = "英杰 %d / %d" % [int(c["hero"]), DeckRules.HEROES]
	_tactic_label.text = "计策 %d / %d" % [int(c["tactic"]), DeckRules.TACTICS]
	_leader_label.text = "领袖 %d / %d" % [int(c["leader"]), DeckRules.LEADERS]

	_normal_label.add_theme_color_override("font_color",
		UiKit.COL_WIN if int(c["normal"]) == NORMAL_TOTAL else UiKit.COL_GOLD)
	_hero_label.add_theme_color_override("font_color",
		UiKit.COL_WIN if int(c["hero"]) == DeckRules.HEROES else UiKit.COL_GOLD)
	_tactic_label.add_theme_color_override("font_color",
		UiKit.COL_WIN if int(c["tactic"]) == DeckRules.TACTICS else UiKit.COL_GOLD)
	_leader_label.add_theme_color_override("font_color",
		UiKit.COL_WIN if int(c["leader"]) == DeckRules.LEADERS else UiKit.COL_GOLD)

	# 分区计数
	for section in SECTIONS:
		var key: String = section["key"]
		if not _section_heads.has(key):
			continue
		var label: Label = _section_heads[key]
		label.text = _section_count_text(key, c)

	# 卡面标记
	for id in _cards_by_id.keys():
		var view: CardView = _cards_by_id[id]
		var card := _db.get_card_by_id(id)
		if card == null:
			continue
		if card.card_type == CardData.TYPE_LEADER:
			var chosen: bool = id == _leader_id
			view.set_selected(chosen)
			view.set_badge("已选" if chosen else "")
		else:
			var count := int(_counts.get(id, 0))
			view.set_selected(count > 0)
			view.set_badge("×%d" % count if count > 1 else ("1" if count == 1 else ""))

	_deck_list_label.text = _compose_deck_text()


func _section_count_text(key: String, c: Dictionary) -> String:
	match key:
		CardData.CATEGORY_LEADER:
			return "%d / %d" % [int(c["leader"]), DeckRules.LEADERS]
		CardData.UNIT_HERO:
			return "%d / %d" % [int(c["hero"]), DeckRules.HEROES]
		CardData.CATEGORY_TACTIC:
			return "%d / %d" % [int(c["tactic"]), DeckRules.TACTICS]
		CardData.UNIT_INFANTRY:
			return "步卒合计"
		CardData.UNIT_ARCHER:
			return "弓弩手合计"
		CardData.UNIT_CAVALRY:
			return "骑兵合计"
	return ""


func _compose_deck_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var total := 0

	lines.append("【领袖】")
	var leader := _db.get_card_by_id(_leader_id)
	if leader != null:
		lines.append("　%s" % leader.name)
		total += 1
	else:
		lines.append("　（未选择）")

	for spec in [
		{"key": CardData.UNIT_HERO, "title": "英杰"},
		{"key": CardData.UNIT_INFANTRY, "title": "步卒"},
		{"key": CardData.UNIT_ARCHER, "title": "弓弩手"},
		{"key": CardData.UNIT_CAVALRY, "title": "骑兵"},
		{"key": CardData.CATEGORY_TACTIC, "title": "计策"},
	]:
		var key: String = spec["key"]
		var picked: Array[CardData] = []
		for id in _counts.keys():
			var card := _db.get_card_by_id(id)
			if card != null and card.category() == key:
				picked.append(card)
		if picked.is_empty():
			continue
		lines.append("【%s】" % spec["title"])
		for card in DeckList.sort_units(picked):
			var n := int(_counts[card.id])
			total += n
			lines.append("　%s ×%d" % [card.name, n])

	lines.append("")
	lines.append("合计 %d / %d 张" % [total, DeckRules.TOTAL])
	return "\n".join(lines)


func _set_message(text: String, is_error: bool) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", UiKit.COL_LOSE if is_error else UiKit.COL_WIN)
