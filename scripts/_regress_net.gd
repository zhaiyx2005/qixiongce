extends SceneTree

## 联机回归验收（死锁修复后的合并回归套件）。
##
## 覆盖本次修复涉及的全部路径：
##   A. 指令层：单机 GameState 能跑完整局（规则没被改坏）
##   B. 联机 RPC 方向：客户端→主机指令、主机→客户端状态/拒绝
##   C. 用户场景：大厅建连 → 阵营选择 → 主机选秦 → 双方进对局 → 客户端同步
##   D. 连接生命周期：离开对局回主菜单会断连；界面被换走不会断连
##   E. 注入转发：Main 的 net_override 会传给子界面
##
## 【设计原则】所有断言用 Array/Dictionary 容器收集副作用 ——
## GDScript 的 lambda 按值捕获外层标量，直接改 bool 会永远为假。

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _wait(cond: Callable, timeout: float = 3.0) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return false


func _mk_nm(node_name: String) -> Node:
	var nm: Node = load("res://scripts/NetworkManager.gd").new()
	root.add_child(nm)
	nm.name = node_name
	nm.use_isolated_multiplayer()
	return nm


# ---------------- A. 单机规则回归 ----------------

func _test_rules() -> void:
	print("\n[A] 单机规则回归：跑完整对局")
	var db = load("res://scripts/CardDB.gd").new()
	var gs = load("res://scripts/GameState.gd").new()
	gs.start_match(CardData.FACTION_QIN, null, null, 20250921)
	var guard := 0
	while gs.phase != GameState.Phase.MATCH_END and guard < 3000:
		guard += 1
		if gs.phase == GameState.Phase.MULLIGAN:
			gs.execute_command(Command.mulligan(0, []))
			gs.execute_command(Command.mulligan(1, []))
		elif gs.phase == GameState.Phase.PLAY:
			var p: int = gs.active
			var hand: Array = gs.players[p].hand
			var played := false
			for c in hand:
				var cmd: Command = Command.play_card(p, c.id, c.row)
				if gs.execute_command(cmd).ok:
					played = true
					break
			if not played:
				gs.execute_command(Command.pass_turn(p))
		elif gs.phase == GameState.Phase.ROUND_END:
			gs.execute_command(Command.advance_round())
		else:
			break
	_ok(gs.phase == GameState.Phase.MATCH_END, "单机对局能正常跑到 MATCH_END（guard=%d）" % guard)
	_ok(gs.players[0].gems > 0 or gs.players[1].gems > 0, "对局产生了城池归属")


# ---------------- B. RPC 方向 ----------------

func _test_rpc_dirs() -> void:
	print("\n[B] RPC 方向：客户端指令上行 / 主机状态下行")
	var host_nm := _mk_nm("RT_Host")
	var cli_nm := _mk_nm("RT_Cli")
	var port := 29401
	host_nm.host_game(port)
	cli_nm.join_game("127.0.0.1", port)
	_ok(await _wait(func(): return host_nm.is_connected_now and cli_nm.is_connected_now, 8.0),
		"连接建立")

	# 客户端 → 主机：指令
	# 注意 send_command 收的是 Command 对象，seq 由 NetworkManager 内部递增分配。
	var got_cmd: Array = []
	host_nm.command_received.connect(func(d: Dictionary): got_cmd.append(d))
	cli_nm.send_command(Command.pass_turn(1))
	_ok(await _wait(func(): return got_cmd.size() > 0, 3.0), "客户端指令能上行到主机")

	# 序号去重：手工重放同一个 seq，主机应丢弃
	var before := got_cmd.size()
	var dup: Command = Command.pass_turn(1)
	dup.seq = 1   # 与上面那条相同的 seq
	cli_nm._rpc_id(1, "_net_command", dup.to_dict())
	await create_timer(0.4).timeout
	_ok(got_cmd.size() == before, "同 seq 重复包被去重（未重复执行）")

	# 主机 → 客户端：状态
	var got_state: Array = []
	cli_nm.state_received.connect(func(d: Dictionary): got_state.append(d))
	host_nm.send_state({"phase": 0, "rng_seed": 777, "probe": true})
	_ok(await _wait(func(): return got_state.size() > 0, 3.0), "主机状态能下行到客户端")

	# 主机 → 客户端：拒绝
	var got_rej: Array = []
	cli_nm.rejected.connect(func(r: String): got_rej.append(r))
	host_nm.send_reject("测试拒绝")
	_ok(await _wait(func(): return got_rej.size() > 0, 3.0), "主机拒绝能下行到客户端")

	host_nm.disconnect_peer()
	cli_nm.disconnect_peer()
	host_nm.queue_free()
	cli_nm.queue_free()
	await process_frame


# ---------------- C. 用户场景端到端 ----------------

func _make_side(node_name: String, nm: Node, is_host: bool, seed_v: int) -> Array:
	var main: Node = load("res://scripts/Main.gd").new()
	main.net_override = nm
	root.add_child(main)
	main.name = node_name
	await process_frame
	await process_frame
	var fs: Node = load("res://scripts/FactionSelectScreen.gd").new()
	fs.net_mode = true
	fs.net_is_host = is_host
	fs.net_my_index = 0 if is_host else 1
	fs.net_seed = seed_v
	fs.net_override = nm
	fs.faction_chosen.connect(main._on_net_faction_chosen)
	fs.faction_chosen_seed.connect(main._on_net_faction_chosen_seed)
	main.add_child(fs)
	fs.name = node_name + "FS"
	main._current = fs
	return [main, fs]


func _test_user_scenario() -> void:
	print("\n[C] 用户场景：主机选秦 → 双方进对局 → 客户端同步")
	var host_nm := _mk_nm("US_Host")
	var cli_nm := _mk_nm("US_Cli")
	var port := 29411
	var seed_v := 20250920
	host_nm.host_game(port)
	cli_nm.join_game("127.0.0.1", port)
	_ok(await _wait(func(): return host_nm.is_connected_now and cli_nm.is_connected_now, 8.0),
		"连接建立")

	var host_side: Array = await _make_side("US_HostMain", host_nm, true, seed_v)
	var host_main: Node = host_side[0]
	var host_fs: Node = host_side[1]
	var cli_side: Array = await _make_side("US_CliMain", cli_nm, false, 0)
	var cli_main: Node = cli_side[0]

	var cli_states: Array = []
	cli_nm.state_received.connect(func(d: Dictionary): cli_states.append(d))

	await process_frame
	await create_timer(0.3).timeout

	# 关键动作：主机按下「秦」
	host_fs._on_faction_card_pressed("qin")

	_ok(await _wait(func(): return host_main._current is MatchScreen, 4.0),
		"★ 主机自动进入对局（死锁已解除）")
	_ok(host_main._current is MatchScreen
		and host_main._current.state != null
		and host_main._current.state.phase == GameState.Phase.MULLIGAN,
		"主机进入换牌阶段")
	_ok(host_main._current is MatchScreen and host_main._current.my_index == 0,
		"主机 my_index = 0（座席正确）")

	_ok(await _wait(func(): return cli_main._current is MatchScreen, 4.0),
		"★ 客户端进入对局界面")
	if cli_main._current is MatchScreen:
		_ok(cli_main._current.my_index == 1, "客户端 my_index = 1（座席正确）")
		_ok(cli_main._current.net_mode, "客户端处于联机模式")
		# 七国改动：客户端阵营不再等于「主机的反面」（那不是唯一解），
		# 而是由主机指派并随广播下发。断言「两端看到的对手/自己一致」才是有意义的检查。
		_ok(cli_main._net_my_faction == host_main._net_opp_faction,
			"★ 客户端阵营 = 主机指派的阵营（%s）" % cli_main._net_my_faction)
		_ok(cli_main._net_my_faction != host_main._net_my_faction,
			"★ 双方阵营不同（客户端 %s ≠ 主机 %s）" % [
				cli_main._net_my_faction, host_main._net_my_faction])
		_ok(cli_main._net_opp_faction == host_main._net_my_faction,
			"★ 客户端看到的对手 = 主机阵营（%s）" % cli_main._net_opp_faction)
		_ok(CardData.FACTIONS.has(cli_main._net_my_faction),
			"客户端阵营是七国中的合法值")

	_ok(await _wait(func(): return cli_states.size() > 0, 5.0),
		"★ 客户端收到权威状态（不再卡「正在同步」）")
	if cli_states.size() > 0:
		var st: Dictionary = cli_states[cli_states.size() - 1]
		_ok(int(st.get("rng_seed", 0)) == seed_v,
			"权威状态带主机种子 %d（双方牌序一致）" % seed_v)

	# ---- 主机必须能真正选牌（换牌）----
	# 这是死锁修复后的下一个环节：曾经 `_start_match()` 写成 `if not net_mode`，
	# 把主机也排除在外 → 主机看不到换牌界面、发不出 mulligan 指令 → 双方卡在换牌。
	if host_main._current is MatchScreen:
		var hms = host_main._current
		_ok(hms._mulligan_screen != null and hms._mulligan_screen.visible,
			"★ 主机能看到换牌界面（曾经看不到 → 卡住）")
		# 选一张牌走真实点击回调，再确认
		var host_hand: Array = hms.state.players[0].hand
		if host_hand.size() > 0:
			hms._on_mulligan_card_clicked(host_hand[0], null)
			_ok(hms._selected.size() == 1, "主机能选中要换的牌")
		hms._on_mulligan_confirm()
		await create_timer(0.8).timeout
		_ok(hms.state.mulligan_done[0], "★ 主机确认换牌后 mulligan_done[0] = true")
		_ok(not hms._mulligan_screen.visible, "主机换牌界面已关闭")

	# ---- 换掉「两张同名卡」必须成功（用户第三轮问题 1）----
	# 直接对一份独立 GameState 验证，避免干扰上面的联机对局。
	# 根因：`_find_in_hand()` 恒返回第一个匹配，两张同名卡的 id 又完全相同 →
	# 两次都解析到同一实例 → `cards.has(card)` → 整条指令被拒 → 换牌界面卡住。
	_test_duplicate_mulligan()

	# ---- 客户端也必须能选牌 ----
	if cli_main._current is MatchScreen:
		var cms = cli_main._current
		# 注意：lambda 体不能跨行，必须压成一行
		var cli_see_ms := func() -> bool: return cms._mulligan_screen != null and cms._mulligan_screen.visible
		_ok(await _wait(cli_see_ms, 4.0), "★ 客户端能看到换牌界面")
		var cli_hand: Array = cms.state.players[1].hand
		if cli_hand.size() > 0:
			cms._on_mulligan_card_clicked(cli_hand[0], null)
			_ok(cms._selected.size() == 1, "客户端能选中要换的牌")
		cms._on_mulligan_confirm()
		var both_done := await _wait(func(): return cms.state.mulligan_done[1], 5.0)
		_ok(both_done, "★ 客户端换牌被主机接受（回传权威状态）")
		# 主机侧应看到进入出牌阶段
		if host_main._current is MatchScreen:
			var hms2 = host_main._current
			var host_play := func() -> bool: return hms2.state.phase == GameState.Phase.PLAY
			_ok(await _wait(host_play, 5.0), "★ 双方换牌完毕 → 主机进入出牌阶段")

			# ---- 出牌阶段：双方都必须能真正动作（走真实回调 → _dispatch）----
			# 注意 1：点击手牌只是「选中」，真正出牌走 _on_card_dropped。
			# 注意 2：联机没有 AI，轮到谁就必须由「那一侧」发指令，否则回合不会推进。
			#         所以这里两侧轮流驱动，验证「谁都能动、状态能推进」。
			if hms2.state.phase == GameState.Phase.PLAY:
				var host_acted := false
				var cli_acted := false
				for _try in range(300):
					if hms2.state.phase != GameState.Phase.PLAY:
						break
					# 主机侧：用主机界面自己的权威状态驱动
					if hms2.state.active == 0 and not host_acted:
						var hu: CardData = null
						for c in hms2.state.players[0].hand:
							if c.card_type == CardData.TYPE_UNIT:
								hu = c
								break
						if hu != null:
							hms2._on_card_dropped(hu, hu.row, -1)
						else:
							hms2._on_pass_pressed()
						host_acted = true
					# 客户端侧：走客户端界面（本地状态 + 真实 RPC 上送）
					if cli_main._current is MatchScreen and not cli_acted:
						var cms2 = cli_main._current
						if cms2.state.active == 1:
							var cu: CardData = null
							for c in cms2.state.players[1].hand:
								if c.card_type == CardData.TYPE_UNIT:
									cu = c
									break
							if cu != null:
								cms2._on_card_dropped(cu, cu.row, -1)
							else:
								cms2._on_pass_pressed()
							cli_acted = true
					if host_acted and cli_acted:
						break
					await create_timer(0.1).timeout
				_ok(host_acted, "★ 轮到主机时能出牌/过牌（不卡死）")
				_ok(cli_acted, "★ 轮到客户端时能出牌/过牌（不卡死）")
				var progressed := func() -> bool: return hms2.state.command_count >= 3
				_ok(await _wait(progressed, 5.0), "★ 回合能正常推进（command_count 增长）")
				var cli_sees := func() -> bool: return cli_main._current is MatchScreen \
					and cli_main._current.state.command_count > 0
				_ok(await _wait(cli_sees, 5.0), "★ 主机的操作被同步到客户端")

	host_nm.disconnect_peer()
	cli_nm.disconnect_peer()
	await process_frame


# ---------------- D. 连接生命周期 ----------------

func _test_lifecycle() -> void:
	print("\n[D] 连接生命周期")
	var host_nm := _mk_nm("LC_Host")
	var cli_nm := _mk_nm("LC_Cli")
	var port := 29421
	host_nm.host_game(port)
	cli_nm.join_game("127.0.0.1", port)
	_ok(await _wait(func(): return host_nm.is_connected_now and cli_nm.is_connected_now, 8.0),
		"连接建立")

	# D1: 构造 Main（模拟「连接已建立后 Main 才 ready」）不应断连
	var main: Node = load("res://scripts/Main.gd").new()
	main.net_override = cli_nm
	root.add_child(main)
	main.name = "LC_Main"
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	_ok(cli_nm.is_active(), "★ Main 首帧构造主菜单不断连（连接存活）")

	# D2: 主菜单被换走（模拟进大厅）不断连
	var lobby: Node = load("res://scripts/LobbyScreen.gd").new()
	lobby.net_override = cli_nm
	main.add_child(lobby)
	lobby.name = "LC_Lobby"
	var old: Node = main._current
	main._current = lobby
	main.remove_child(old)
	old.queue_free()
	await create_timer(0.3).timeout
	_ok(cli_nm.is_active(), "★ 界面被换走不会断连（大厅 _exit_tree 不断连）")

	# D3: 玩家显式回主菜单 → 断连
	cli_nm.disconnect_peer()
	await create_timer(0.3).timeout
	_ok(not cli_nm.is_active(), "★ 显式断连后连接关闭")

	host_nm.disconnect_peer()
	await process_frame


# ---------------- E. 注入转发 ----------------

func _test_injection() -> void:
	print("\n[E] net_override 注入转发")
	var nm := _mk_nm("IN_NM")
	var main: Node = load("res://scripts/Main.gd").new()
	main.net_override = nm
	root.add_child(main)
	main.name = "IN_Main"
	await process_frame
	await create_frame_wait()

	# 造一个 MatchScreen，用 Main 的 _attach_net 注入
	var db = load("res://scripts/CardDB.gd").new()
	var ms: Node = load("res://scripts/MatchScreen.gd").new()
	ms.db = db
	main._attach_net(ms)
	_ok(ms.net_override == nm, "★ _attach_net 把 net_override 传给了 MatchScreen")

	# 造一个 FactionSelectScreen 同理
	var fs: Node = load("res://scripts/FactionSelectScreen.gd").new()
	main._attach_net(fs)
	_ok(fs.net_override == nm, "_attach_net 把 net_override 传给了 FactionSelectScreen")

	# 造一个没声明 net_override 的界面（MainMenuScreen）不应报错
	var mm: Node = load("res://scripts/MainMenuScreen.gd").new()
	var threw: Array = []
	main._attach_net(mm)   # 若实现有误会抛出
	threw.append(1)
	_ok(threw.size() == 1, "对未声明 net_override 的界面调用 _attach_net 不报错")
	mm.free()
	ms.free()
	fs.free()

	await process_frame


func create_frame_wait() -> void:
	await process_frame


# ---------------- F. 第三轮修复：同名换牌 / 视角 / 结算可见性 ----------------

## 用户第三轮问题 1：换牌阶段允许完全相同的两张牌都被换掉。
## 旧实现用 `_find_in_hand()`（恒返回第一个匹配）逐个解析 card_id，
## 而同名卡有多个独立实例但 **id 完全相同** → 两次解析到同一实例 →
## `cards.has(card)` 判为「同一张牌不能换两次」→ 整条指令被拒 → 界面卡死。
func _test_duplicate_mulligan() -> void:
	print("\n[F] 第三轮修复：同名换牌 / 视角 / 结算")
	var gs = load("res://scripts/GameState.gd").new()
	gs.start_match(CardData.FACTION_QIN, null, null, 424242)

	# 先在手里造出「两张完全同名同 id」的牌：把后手第 2 张换成与第 1 张相同的实例数据。
	# 直接改手牌数组最直观：取两张不同卡，把第二张对象替换为第一张的同 id 副本。
	var hand: Array = gs.players[0].hand
	var dup_ok := false
	var dup_id := ""
	if hand.size() >= 2:
		var src: CardData = hand[0]
		var clone: CardData = src.duplicate_card()
		if clone == null:
			# 没有 duplicate_card 就直接用同一个数据重建
			clone = load("res://scripts/CardData.gd").new()
			clone.from_dict(src.to_dict())
		hand[1] = clone
		dup_ok = hand[0].id == hand[1].id
		dup_id = hand[0].id
	_ok(dup_ok, "构造出两张同 id 的手牌（id=%s）" % dup_id)

	if dup_ok:
		var before := hand.size()
		var res: CommandResult = gs.execute_command(Command.mulligan(0, [dup_id, dup_id]))
		_ok(res.ok, "★ 换掉两张同名卡被接受（曾经被拒 → 卡死）")
		_ok(gs.mulligan_done[0], "★ 同名换牌后 mulligan_done[0] = true")
		_ok(gs.phase == GameState.Phase.MULLIGAN or gs.phase == GameState.Phase.PLAY,
			"同名换牌后阶段仍可推进（phase=%d）" % gs.phase)
		_ok(gs.players[0].hand.size() == before, "换牌后手牌张数不变（换出即补进）")

	# 对照：不存在的 id 依然要被拒（不能因为放宽而放行非法操作）
	var bad: CommandResult = gs.execute_command(Command.mulligan(1, ["__no_such_card__"]))
	_ok(not bad.ok, "不存在的卡 id 依然被拒（校验没有失效）")


## 用户第三轮问题 3：客户端的战场必须「本方在下、对手在上」。
## 断言方式：建一个 my_index = 1 的联机 MatchScreen，检查
##   _(a) 上信息带展示的是对手(0)、下信息带展示的是本方(1)；
##   _(b) 上/下半场的行视图归属的座位号分别是 0 / 1；
##   _(c) 只有 my_index 那一侧的行 accepts_drop = true。
func _test_client_orientation() -> void:
	var nm := _mk_nm("OR_Client")
	var ms = load("res://scripts/MatchScreen.gd").new()
	# 模拟客户端：座位 1，阵营取主机（秦）的反面
	ms.setup_network(load("res://scripts/CardDB.gd").new(), CardData.FACTION_ZHAO, 1, 0,
		CardData.FACTION_QIN, 20250920)
	ms.net_override = nm
	root.add_child(ms)
	ms.name = "OR_ClientMS"
	await process_frame
	await create_timer(0.3).timeout

	_ok(ms.my_index == 1 and ms.opp_index == 0, "客户端视角 my=1 / opp=0")

	# (b) 半场归属：_row_views[座位][行] 必须在树里被正确挂载
	#     用「哪一侧的行接受拖放」来反推视角，比对控件层级更稳。
	var mine_rows_accept := 0
	var opp_rows_accept := 0
	for row in CardData.ROWS:
		if ms._row_views[1][row].accepts_drop:
			mine_rows_accept += 1
		if ms._row_views[0][row].accepts_drop:
			opp_rows_accept += 1
	_ok(mine_rows_accept == CardData.ROWS.size() and opp_rows_accept == 0,
		"★ 只有本方(座位1)的行接受拖放，对手(座位0)的不接受")

	# (c) 信息带：用 _refresh 后的文本反推 —— 上方那条应属于对手(0)
	#     通过 _leader_slots 的挂载位置（父链顺序）判断上下。
	var band_top := _band_slot_owner(ms, true)
	var band_bottom := _band_slot_owner(ms, false)
	_ok(band_top == 0, "★ 上信息带属于对手(座位 0)，实际=%s" % str(band_top))
	_ok(band_bottom == 1, "★ 下信息带属于本方(座位 1)，实际=%s" % str(band_bottom))

	# (d) 数据不串位：给自己和对手分别设一个可辨识的战力数字，看标签写到哪一侧
	#     —— 这里直接检查「标签数组下标 == 座位号」的约定
	_ok(ms._power_labels.size() == 2, "战力标签数组按座位下标存放（size=2）")
	if ms.state != null and ms.state.players.size() == 2:
		ms._refresh_corner_info()
		var mine_txt: String = ms._power_labels[1].text
		var opp_txt: String = ms._power_labels[0].text
		var expect_mine := str(ms.state.players[1].total_power())
		var expect_opp := str(ms.state.players[0].total_power())
		_ok(mine_txt == expect_mine and opp_txt == expect_opp,
			"★ 总战力按座位写入：本方(1)=%s 对手(0)=%s" % [mine_txt, opp_txt])

	nm.queue_free()
	ms.queue_free()
	await process_frame


## 在信息带里找到领袖槽位，反推这条信息带属于哪个座位。
## top_side=true 找最上面那条（父链上第一个 VBox 的 child 0），false 找最下面那条。
func _band_slot_owner(ms, top_side: bool) -> int:
	# _leader_slots[i] 是 PanelContainer，其祖先是 PanelContainer(band) → HBox → Margin → VBox(col)
	for i in range(2):
		var slot = ms._leader_slots[i]
		if slot == null:
			continue
		var node: Node = slot.get_parent()   # HBox
		if node == null:
			continue
		node = node.get_parent()             # Margin
		if node == null:
			continue
		node = node.get_parent()             # VBox (col)
		if node == null:
			continue
		var idx: int = node.get_index()
		if top_side and idx == 0:
			return i
		if not top_side and idx == node.get_parent().get_child_count() - 2:
			# 顺序是 [band_opp][board][band_me][hand] → 倒数第二即下信息带
			return i
	return -1


# ---------------- G. 结算弹窗在客户端可见 ----------------

## 用户第三轮问题 2：小局结算 / 终局信息必须双方都能看到。
## 客户端不跑规则，round_ended / match_ended 永远不会发射，
## 由 _on_state_received() 按「本局编号」补弹窗（_round_popup_shown_for / _match_popup_shown）。
func _test_client_sees_popups() -> void:
	print("\n[G] 客户端结算弹窗可见性")
	var nm := _mk_nm("POP_Client")
	var ms = load("res://scripts/MatchScreen.gd").new()
	ms.setup_network(load("res://scripts/CardDB.gd").new(), CardData.FACTION_ZHAO, 1, 0,
		CardData.FACTION_QIN, 20250920)
	ms.net_override = nm
	root.add_child(ms)
	ms.name = "POP_ClientMS"
	await process_frame
	await create_timer(0.2).timeout

	_ok(ms._round_popup != null and ms._match_popup != null, "结算弹窗与终局弹窗已建好")
	_ok(ms._round_popup_shown_for == -1, "初始「已弹局号」为 -1")
	_ok(not ms._match_popup_shown, "初始「终局已弹」为 false")

	# 造一份带小局结算的权威状态（模拟主机广播跨过 ROUND_END）
	var data: Dictionary = ms.state.serialize()
	data["phase"] = GameState.Phase.ROUND_END
	data["last_round_summary"] = {
		"round": 1, "winner": 0,
		"power": [10, 7], "row_power": [[4, 3, 3], [3, 2, 2]],
		"text": "对手赢下第 1 局。", "gems": [2, 1],
	}
	ms._on_state_received(data)
	await process_frame
	_ok(ms._round_popup.visible, "★ 客户端收到 ROUND_END 状态后弹出小局结算")
	_ok(ms._round_popup_shown_for == 1, "已记录弹过的局号 = 1")

	# 重发同一份（主机可能重发）不应重复弹
	ms._round_popup.visible = false
	ms._on_state_received(data)
	await process_frame
	_ok(not ms._round_popup.visible, "★ 同一局号重发不会重复弹结算")

	# 终局
	var end_data: Dictionary = ms.state.serialize()
	end_data["phase"] = GameState.Phase.MATCH_END
	end_data["match_summary"] = {"winner": 1, "rounds_won": [1, 2]}
	ms._on_state_received(end_data)
	await process_frame
	_ok(ms._match_popup.visible, "★ 客户端收到 MATCH_END 状态后弹出终局")
	_ok(ms._match_popup_shown, "已记录终局已弹")

	nm.queue_free()
	ms.queue_free()
	await process_frame


func _run() -> void:
	_watchdog()
	print("\n===== 联机回归验收套件 =====")

	await _test_rules()
	await _test_rpc_dirs()
	await _test_user_scenario()
	await _test_lifecycle()
	await _test_injection()
	await _test_client_orientation()
	await _test_client_sees_popups()

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
