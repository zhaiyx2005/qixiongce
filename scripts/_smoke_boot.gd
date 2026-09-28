extends SceneTree

## 启动冒烟：真实加载 Main.tscn，跑若干帧，确认没有脚本错误、界面构建成功。
## 覆盖 UI 高度断言（布局回归）。

var _fail := 0
var _pass := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	print("[看门狗] 超时")
	quit(1)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] " + what)
	else:
		_fail += 1
		print("  [FAIL] " + what)


func _run() -> void:
	_watchdog()
	print("\n===== 启动冒烟 =====")

	var scene: PackedScene = load("res://scenes/Main.tscn")
	_ok(scene != null, "Main.tscn 能加载")
	if scene == null:
		quit(1)
		return

	var inst: Node = scene.instantiate()
	_ok(inst != null, "Main.tscn 能实例化")
	root.add_child(inst)
	await process_frame
	await process_frame
	await create_timer(0.4).timeout

	_ok(inst._current != null, "主菜单已构建（_current 非空）")
	_ok(inst._current is MainMenuScreen, "首屏是主菜单")
	var all: Array = inst.db.get_all_cards() if inst.db != null else []
	_ok(all.size() > 0, "卡牌库已加载（%d 张）" % all.size())
	# 七国 × 45 张 = 315
	_ok(all.size() == 315, "卡牌总数 = 315（七国各 45）")
	_ok(inst.db.load_errors.is_empty(),
		"卡牌库校验无错误（%d 条）" % inst.db.load_errors.size())
	for f in CardData.FACTIONS:
		var cards: Array = inst.db.get_cards_by_faction(f)
		_ok(cards.size() == 45, "%s 阵营 45 张" % CardData.faction_name_of(f))

	# 主菜单高度预算（1280×800 减上下边距 16 → 784）
	if inst._current is Control:
		var h: float = inst._current.get_combined_minimum_size().y
		print("      [诊断] 主菜单最小高度 = %.1f px（预算 ≤ 784）" % h)
		_ok(h <= 784.0, "主菜单高度在预算内")

	# 音频单例在位
	var am := root.get_node_or_null("AudioManager")
	_ok(am != null, "AudioManager Autoload 在位")

	# NetworkManager 单例在位
	var nm := root.get_node_or_null("NetworkManager")
	_ok(nm != null, "NetworkManager Autoload 在位")
	_ok(nm.is_active() == false, "启动时没有残留联机连接")

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
