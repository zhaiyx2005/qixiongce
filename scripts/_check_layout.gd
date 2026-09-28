extends SceneTree

## 对局界面布局预算与视角检查（第三轮修复的防回归）。
##
## 覆盖三件事：
##   1. 视角：不论本机是主机(0) 还是客户端(1)，自己的半场永远在屏幕下方；
##      信息带上=对手、下=本方；上下半场底色不同。
##   2. 行序方向：我方近战贴近中央、守军贴近手牌；对手镜像。
##   3. 高度预算：内容最小高度 ≤ 784（= 800 - 上下边距 16），
##      并在真实 1280×800 容器里验证手牌带不会被窗口裁掉。
##
## 【历史教训】曾经只断言「内容最小高度 ≤ 784」而没在真实 800 高度里渲染，
## 结果漏掉了「内容 798 + 边距 16 = 814 > 800，手牌带底边落到 y=806 被裁 6px」。
## 所以这里两件事都要测：最小高度本身，以及真实窗口里的落点。
##
## 【注意】headless 下达不到 1280×800 视口，所以用一个显式的 1280×800 容器模拟窗口。

const WIN_W := 1280
const WIN_H := 800
const BUDGET_H := 784.0

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(60.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _mk_nm(tag: String) -> Node:
	var nm: Node = load("res://scripts/NetworkManager.gd").new()
	root.add_child(nm)
	nm.name = "LAY_NM_" + tag
	return nm


func _run() -> void:
	_watchdog()
	print("\n===== 对局界面布局预算与视角检查 =====")

	await _check_lobby_layout()
	await _check_faction_select_layout()
	await _check_deck_editor_layout()

	for is_client in [false, true]:
		var side := "客户端(座位1)" if is_client else "主机(座位0)"
		var nm := _mk_nm("c" if is_client else "h")

		# 用 1280×800 容器模拟真实窗口
		var win := Control.new()
		win.size = Vector2(WIN_W, WIN_H)
		root.add_child(win)
		win.name = "LAY_WIN_" + ("c" if is_client else "h")
		await process_frame
		await process_frame

		var ms = load("res://scripts/MatchScreen.gd").new()
		ms.setup_network(load("res://scripts/CardDB.gd").new(),
			CardData.FACTION_ZHAO if is_client else CardData.FACTION_QIN,
			1 if is_client else 0, 0 if is_client else 1,
			CardData.FACTION_QIN if is_client else CardData.FACTION_ZHAO, 20250920)
		ms.net_override = nm
		win.add_child(ms)
		ms.name = "LAY_MS_" + ("c" if is_client else "h")
		ms.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		await process_frame

		var vbox: VBoxContainer = _find_vbox(ms)
		if vbox == null:
			_ok(false, "%s 找不到内容 VBox" % side)
			continue

		# ---- 1. 高度预算 ----
		var min_h: float = vbox.get_combined_minimum_size().y
		print("      [诊断] %s 内容最小高度 = %.1f px（预算 ≤ %.0f）" % [side, min_h, BUDGET_H])
		_ok(min_h > 0.0, "%s 界面已产生实际尺寸（不是 0）" % side)
		_ok(min_h <= BUDGET_H, "%s 内容最小高度在预算内（%.1f ≤ %.0f）" % [side, min_h, BUDGET_H])

		# ---- 2. 真实窗口里不溢出 ----
		var bottom := vbox.global_position.y + vbox.size.y
		print("      [诊断] %s VBox 底边 y = %.1f（窗口高 %d）" % [side, bottom, WIN_H])
		_ok(bottom <= WIN_H + 0.5, "%s 内容底边未超出窗口（%.1f ≤ %d）" % [side, bottom, WIN_H])
		var hand_band: Control = vbox.get_child(vbox.get_child_count() - 1)
		_ok(hand_band.global_position.y + hand_band.size.y <= WIN_H + 0.5,
			"%s 手牌带完整可见（不被裁）" % side)
		_ok(hand_band.size.y >= 128.0 - 0.5,
			"%s 手牌带高度未被压缩（%.1f ≥ 128）" % [side, hand_band.size.y])

		# ---- 3. 视角：上恒为对手、下恒为本方 ----
		var top_owner := _band_owner(ms, true)
		var bottom_owner := _band_owner(ms, false)
		var expect_top: int = 0 if is_client else 1
		var expect_bottom: int = 1 if is_client else 0
		_ok(top_owner == expect_top and bottom_owner == expect_bottom,
			"★ %s 视角正确：上=对手(%d) 下=本方(%d)" % [side, top_owner, bottom_owner])

		# ---- 4. 上下半场底色：必须分别是对手色/本方色，且两者可分辨 ----
		var c_top := _half_bg_color(ms, true)
		var c_bottom := _half_bg_color(ms, false)
		_ok(c_top.is_equal_approx(ms.FIELD_TOP_COLOR),
			"%s 上方半场底色 = 对手色" % side)
		_ok(c_bottom.is_equal_approx(ms.FIELD_BOTTOM_COLOR),
			"%s 下方半场底色 = 本方色" % side)
		_ok(not c_top.is_equal_approx(c_bottom), "%s 上下半场底色不同（视觉可分辨）" % side)

		# ---- 5. 行序方向 ----
		_ok(_row_is_above(ms, ms.my_index, CardData.ROW_MELEE, CardData.ROW_GARRISON),
			"%s 我方近战行在守军行之上（朝向中央）" % side)
		_ok(_row_is_above(ms, ms.opp_index, CardData.ROW_GARRISON, CardData.ROW_MELEE),
			"%s 对手守军行在近战行之上（朝向对方边缘）" % side)

		# ---- 6. 只有本方行接受拖放 ----
		var mine_accept := 0
		var opp_accept := 0
		for row in CardData.ROWS:
			if ms._row_views[ms.my_index][row].accepts_drop:
				mine_accept += 1
			if ms._row_views[ms.opp_index][row].accepts_drop:
				opp_accept += 1
		_ok(mine_accept == CardData.ROWS.size() and opp_accept == 0,
			"%s 只有本方行接受拖放" % side)

		nm.queue_free()
		win.queue_free()
		await process_frame

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## 联机大厅布局：主机 IP 与端口必须同一行，两个动作按钮在其下一行。
##
## 【为什么用坐标比而不是数控件层级】层级只能证明「谁是谁的父节点」，
## 证明不了「渲染出来在同一行」。这里直接比较各控件的 global_position：
## 必须在布局跑完之后读，否则全是 0，断言会假通过。
func _check_lobby_layout() -> void:
	print("\n[L] 联机大厅布局：IP 与端口同行，按钮在下一行")
	var nm := _mk_nm("lobby")
	var lb = load("res://scripts/LobbyScreen.gd").new()
	lb.net_override = nm
	root.add_child(lb)
	lb.name = "LAY_Lobby"
	await process_frame
	await process_frame
	await process_frame

	if lb._ip_edit == null or lb._port_edit == null \
			or lb._host_btn == null or lb._join_btn == null:
		_ok(false, "大厅控件未建好")
		return

	var ip_y: float = lb._ip_edit.global_position.y
	var port_y: float = lb._port_edit.global_position.y
	var ip_x: float = lb._ip_edit.global_position.x
	var port_x: float = lb._port_edit.global_position.x
	var host_y: float = lb._host_btn.global_position.y
	var join_y: float = lb._join_btn.global_position.y

	print("      [诊断] IP(y=%.1f x=%.1f) 端口(y=%.1f x=%.1f) 创建(y=%.1f) 加入(y=%.1f)" % [
		ip_y, ip_x, port_y, port_x, host_y, join_y])

	_ok(absf(ip_y - port_y) < 2.0,
		"★ 主机 IP 与端口在同一行（y 差 %.1f）" % absf(ip_y - port_y))
	_ok(port_x > ip_x + 20.0, "★ 端口输入框在 IP 输入框右侧")
	_ok(host_y > port_y + 10.0, "★ 「创建房间」在参数行下面（差 %.1f）" % (host_y - port_y))
	_ok(join_y > port_y + 10.0, "★ 「加入游戏」在参数行下面（差 %.1f）" % (join_y - port_y))
	_ok(absf(host_y - join_y) < 2.0, "★ 两个按钮在同一行")
	_ok(lb._join_btn.global_position.x > lb._host_btn.global_position.x + 20.0,
		"★ 「加入游戏」在「创建房间」右侧")

	nm.queue_free()
	lb.queue_free()
	await process_frame


## 七国阵营选择界面：七张卡必须并排放在一行里，且整体不超出 1280×800。
##
## 【为什么要断言】七国扩展把那行从 2 张卡变成了 7 张。宽度是硬约束：
## 一旦某张卡变宽或间距变大，第七张就会被挤出窗口右边，玩家根本点不到。
func _check_faction_select_layout() -> void:
	print("\n[M] 阵营选择：七张卡并排且不溢出")
	var nm := _mk_nm("faction")
	var fs = load("res://scripts/FactionSelectScreen.gd").new()
	fs.setup(load("res://scripts/CardDB.gd").new())
	fs.net_override = nm
	root.add_child(fs)
	fs.name = "LAY_FactionSelect"
	await process_frame
	await process_frame
	await process_frame

	_ok(fs._cards.size() == 7, "阵营卡数量 = 7（实际 %d）" % fs._cards.size())

	var min_x := 1e9
	var max_right := -1e9
	var rows_seen := {}
	for pair in fs._cards:
		var btn: Button = pair[1]
		min_x = minf(min_x, btn.global_position.x)
		max_right = maxf(max_right, btn.global_position.x + btn.size.x)
		rows_seen[snappedf(btn.global_position.y, 1.0)] = true
	print("      [诊断] 卡片左边界 x=%.1f 右边界 x=%.1f（窗口宽 %d）" % [min_x, max_right, WIN_W])

	_ok(rows_seen.size() == 1, "★ 七张卡在同一行（y 值种类 = %d）" % rows_seen.size())
	_ok(min_x >= -0.5, "★ 最左的卡没有超出窗口左边（x=%.1f）" % min_x)
	_ok(max_right <= float(WIN_W) + 0.5, "★ 最右的卡没有超出窗口右边（右边距 %.1f）" % max_right)

	var h: float = fs.get_combined_minimum_size().y
	if fs.get_child_count() > 1:
		# 取 CenterContainer 里 VBox 的实际高度更有意义
		for ch in fs.get_children():
			if ch is CenterContainer and ch.get_child_count() > 0:
				h = ch.get_child(0).get_combined_minimum_size().y
	print("      [诊断] 阵营选择内容高度 = %.1f px（预算 ≤ %.0f）" % [h, BUDGET_H])
	_ok(h <= BUDGET_H, "★ 阵营选择高度在预算内（%.1f ≤ %.0f）" % [h, BUDGET_H])
	_ok(fs._cards.size() == CardData.FACTIONS.size(), "覆盖了全部七国")

	nm.queue_free()
	fs.queue_free()
	await process_frame


## [N] 牌库编辑器：推荐流派入口 + 浮层压在最上层 + 载入后计数正确。
##
## 【为什么用 1280×800 的外层容器】headless 视口是 1280×1280，
## 「铺满屏幕」的浮层会拿到 1280×1280，直接断言就会假通过 / 假失败。
## 套一层真实尺寸的 Control 才有意义（与对局界面的做法一致）。
func _check_deck_editor_layout() -> void:
	print("\n[N] 牌库编辑器：推荐流派入口与浮层")
	var db: CardDB = load("res://scripts/CardDB.gd").new()

	var win := Control.new()
	win.size = Vector2(WIN_W, WIN_H)
	root.add_child(win)
	win.name = "LAY_DeckWin"
	await process_frame

	var de = load("res://scripts/DeckEditorScreen.gd").new()
	de.setup(db)
	win.add_child(de)
	de.name = "LAY_DeckEditor"
	de.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	await process_frame

	_ok(de.get_node_or_null(DeckEditorScreen.ARCHETYPE_OVERLAY) == null,
		"初始没有残留的流派浮层")

	de._open_archetypes()
	await process_frame
	await process_frame

	var overlay: Node = de.get_node_or_null(DeckEditorScreen.ARCHETYPE_OVERLAY)
	_ok(overlay != null, "★「推荐流派」能打开浮层")

	if overlay != null:
		# 绘制层级 = add_child 顺序：浮层必须压在所有内容之上
		_ok(de.get_child(de.get_child_count() - 1) == overlay,
			"★ 浮层是最后一个子节点（压在最上层，不会被卡池盖住）")

		var rect := (overlay as Control).get_global_rect()
		_ok(rect.size.x <= float(WIN_W) + 0.5 and rect.size.y <= float(WIN_H) + 0.5,
			"浮层未超出窗口（%.0f×%.0f ≤ %d×%d）" % [rect.size.x, rect.size.y, WIN_W, WIN_H])

		var expect := Archetypes.count_for(de._faction)
		var found := _count_load_buttons(overlay)
		_ok(found == expect, "★ %s 的浮层列出 %d 套流派（期望 %d）" % [
			UiKit.faction_name(de._faction), found, expect])

		var panel := _find_archetype_panel(overlay)
		if panel == null:
			_ok(false, "浮层内找不到流派面板")
		else:
			print("      [诊断] 流派面板 %.0f×%.0f（窗口 %d×%d）" % [
				panel.size.x, panel.size.y, WIN_W, WIN_H])
			_ok(panel.size.y <= float(WIN_H) and panel.global_position.y >= -0.5,
				"流派面板高度在窗口内（%.0f ≤ %d）" % [panel.size.y, WIN_H])

	# 载入第一套流派
	de._load_archetype(0)
	await process_frame
	await process_frame

	var counts: Dictionary = de._counts_by_category()
	_ok(int(counts["normal"]) == 20 and int(counts["hero"]) == 2
			and int(counts["tactic"]) == 6 and int(counts["leader"]) == 1,
		"★ 载入后计数 = 20/2/6/1（实际 %d/%d/%d/%d）" % [
			int(counts["normal"]), int(counts["hero"]),
			int(counts["tactic"]), int(counts["leader"])])
	_ok(DeckRules.validate(de._build_deck(), db).is_empty(), "载入后的卡组构筑合法")
	_ok(de.get_node_or_null(DeckEditorScreen.ARCHETYPE_OVERLAY) == null,
		"载入后浮层自动关闭")

	win.queue_free()
	await process_frame


func _count_load_buttons(node: Node) -> int:
	var n := 0
	if node is Button and (node as Button).text == "载入这套":
		n += 1
	for child in node.get_children():
		n += _count_load_buttons(child)
	return n


func _find_archetype_panel(node: Node) -> PanelContainer:
	if node is PanelContainer and (node as PanelContainer).custom_minimum_size.x >= 600.0:
		return node
	for child in node.get_children():
		var found := _find_archetype_panel(child)
		if found != null:
			return found
	return null


func _find_vbox(ms) -> VBoxContainer:
	for child in ms.get_children():
		if child is MarginContainer:
			for sub in child.get_children():
				if sub is VBoxContainer:
					return sub
	return null


## 在信息带里反推这条带属于哪个座位。
## 路径：_leader_slots[i] → HBox → Margin → VBox(col)，看 col 的下标。
## 顺序固定为 [band_opp][board][band_me][hand]，所以：
##   上带 = col 的第 0 个；下带 = 倒数第 2 个。
func _band_owner(ms, top_side: bool) -> int:
	for i in range(2):
		var slot = ms._leader_slots[i]
		if slot == null:
			continue
		var node: Node = slot.get_parent()
		if node == null:
			continue
		node = node.get_parent()
		if node == null:
			continue
		node = node.get_parent()
		if node == null:
			continue
		var idx: int = node.get_index()
		if top_side and idx == 0:
			return i
		if not top_side and idx == node.get_parent().get_child_count() - 2:
			return i
	return -1


## 某个半场的底色：沿该座位任一行的父链上溯到带 StyleBoxFlat 的 PanelContainer。
func _half_bg_color(ms, top_side: bool) -> Color:
	var seat: int = ms.opp_index if top_side else ms.my_index
	var any_row: RowView = null
	for r in CardData.ROWS:
		if ms._row_views[seat].has(r):
			any_row = ms._row_views[seat][r]
			break
	if any_row == null:
		return Color(-1, -1, -1, -1)
	var node: Node = any_row.get_parent()
	while node != null:
		if node is PanelContainer:
			var sb: StyleBox = node.get_theme_stylebox("panel")
			if sb is StyleBoxFlat:
				return sb.bg_color
		node = node.get_parent()
	return Color(-1, -1, -1, -1)


## 同一座位内，row_a 是否排在 row_b 之上（比较全局 y）。
## 必须在布局完成后调用，否则所有控件 y 都是 0。
func _row_is_above(ms, seat: int, row_a: String, row_b: String) -> bool:
	if not ms._row_views[seat].has(row_a) or not ms._row_views[seat].has(row_b):
		return false
	var a: RowView = ms._row_views[seat][row_a]
	var b: RowView = ms._row_views[seat][row_b]
	return a.global_position.y < b.global_position.y
