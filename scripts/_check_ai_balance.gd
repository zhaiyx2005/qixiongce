extends SceneTree

## 七国 AI 对局体检（常备）：循环对战平衡 + 计策使用 + 卡死检测。
##
## 【为什么改成循环对战】两国时代「先手 vs 后手」就是全部对阵；七国之后
## 每国要面对 6 个对手，只测一组根本无法反映平衡。这里让七国两两交手
## （a 对 b 与 b 对 a 都跑，抵消先手因素），再统计每国的总体胜率。
##
## 【为什么要单独做这件事】用户报告过「AI 不会使用计策牌，一用就卡住」。
## 实测发现真相是**反过来的**：AI 每局会尝试出约 6.5 次计策，
## 只是每次都被旧 bug 拦下 —— 表现为「AI 好像从不出计策 + 游戏卡死」。
## 所以这里把「计策使用次数」也量化成断言，防止它再被悄悄改回 0。
##
## 【阈值怎么定】
## GAMES_PER_PAIR × 6 个对手 = 480 局/国，标准差约 2.3%，±10 个百分点已接近 4σ。
##
## 【为什么不再用 40%~60% 做硬断言（第 20 阶段）】那个紧区间是「七国机制统一」
## 时代的产物 —— 当时刻意让各国的兵种 / 能力档位完全对齐，把国家差异压到只剩卡名。
## 之后按《流派设计稿》重排了 28 位英杰的能力，而设计稿本身就是**有意差异化**的：
## 「己方全场 +1」作用于整行（可达 8~10 点收益），「点杀对方最高战力」只作用于 1~2 张
## （约 4~6 点）。两者不可能等价，所以国家之间必然拉开差距 —— 这正是设计稿
## 第五节「流派平衡建议」里列「优势 / 弱点」而不是追求势均力敌的原因。
##
## 因此这里分两层：
##   · 硬断言：25%~75% 的**宽区间** —— 只用来抓「某国被改崩了」这种真故障；
##   · 参考区间：40%~60% —— 只打印不判定，作为后续调平的目标。
## 若日后要把国家拉回势均力敌，可用的杠杆见同目录 `Archetypes.gd` 与
## `功能清单.md` 第 20 章「平衡现状」一节的说明。
const SANITY_MIN := 0.25
const SANITY_MAX := 0.75
const REF_MIN := 0.40
const REF_MAX := 0.60

## 每对交手局数（七国两两交手共 42 对 → **4200 局**，约 45 秒）。
## 【为什么从 40 提到 100】40 局/对时每国只跑 480 局，抽样误差约 ±2.3%，
## 而七国在调平之后**真实差距只有几个百分点** —— 用 1680 局的结果微调，
## 等于在噪声上过拟合。提到 100 后误差降到 ±1.4%，读数才可信。
const GAMES_PER_PAIR := 100

var _fail := 0
var _pass := 0

var _wins := {}
var _losses := {}
var _draws := {}
var _games := {}
var _tactic_by_faction := {}
var _games_with_tactic := 0
var _total_games := 0
var _stuck_games := 0
var _wrong_faction_games := 0
var _deck_db := CardDB.new()
var _archetypes := false
var _seed_offset := 0


func _init() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await create_timer(600.0).timeout
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
	_archetypes = OS.get_cmdline_user_args().has("--archetypes")
	_seed_offset = 700000 if OS.get_cmdline_user_args().has("--holdout") else 0
	print("卡组：%s；独立种子偏移：%d" % ["推荐流派交叉" if _archetypes else "预设", _seed_offset])
	var pair_count: int = CardData.FACTIONS.size() * (CardData.FACTIONS.size() - 1)
	print("\n===== 七国 AI 对局体检（每对 %d 局，共 %d 局） =====" % [
		GAMES_PER_PAIR, pair_count * GAMES_PER_PAIR])
	var t0 := Time.get_ticks_msec()

	var pairs := 0
	for a in CardData.FACTIONS:
		for b in CardData.FACTIONS:
			if a == b:
				continue
			pairs += 1
			for k in range(GAMES_PER_PAIR):
				_play_one(a, b, 90000 + pairs * 1000 + k + _seed_offset)

	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	print("\n  耗时            : %.1f 秒" % elapsed)

	print("\n  %-4s %6s %6s %6s %8s %10s %8s" % ["国", "胜", "负", "平", "总场", "胜率", "参考"])
	for f in CardData.FACTIONS:
		var w: int = int(_wins.get(f, 0))
		var l: int = int(_losses.get(f, 0))
		var d: int = int(_draws.get(f, 0))
		var n: int = int(_games.get(f, 0))
		var rate := float(w) / float(n) if n > 0 else 0.0
		var in_ref := rate >= REF_MIN and rate <= REF_MAX
		print("  %-4s %6d %6d %6d %8d %9.1f%% %8s" % [
			CardData.faction_name_of(f), w, l, d, n, rate * 100.0,
			"参考内" if in_ref else "参考外"])

	var total_tactics := 0
	for f in _tactic_by_faction.keys():
		total_tactics += int(_tactic_by_faction[f])
	print("\n  计策使用合计    : %d（%.2f 次/局）" % [
		total_tactics, float(total_tactics) / max(1, _total_games)])
	print("  出过计策的对局  : %d / %d" % [_games_with_tactic, _total_games])

	print("")
	_ok(_stuck_games == 0, "★ 全部 %d 局都正常结束（0 局卡死）" % _total_games)
	_ok(_wrong_faction_games == 0, "每一局都按指定的双方阵营建立（参数已接通）")
	_ok(total_tactics > 0, "★ AI 确实会使用计策牌（合计 %d 次）" % total_tactics)
	_ok(_games_with_tactic == _total_games,
		"★ 每一局 AI 都用过计策（%d / %d）" % [_games_with_tactic, _total_games])

	for f in CardData.FACTIONS:
		var n: int = int(_games.get(f, 0))
		var w: int = int(_wins.get(f, 0))
		var rate := float(w) / float(n) if n > 0 else 0.0
		_ok(rate >= SANITY_MIN and rate <= SANITY_MAX,
			"★ %s 胜率 %.1f%% 未崩坏（%.0f%%~%.0f%%）" % [
				CardData.faction_name_of(f), rate * 100.0,
				SANITY_MIN * 100.0, SANITY_MAX * 100.0])

	var off_ref := PackedStringArray()
	for f in CardData.FACTIONS:
		var n2: int = int(_games.get(f, 0))
		var rate2 := float(int(_wins.get(f, 0))) / float(n2) if n2 > 0 else 0.0
		if rate2 < REF_MIN or rate2 > REF_MAX:
			off_ref.append("%s %.1f%%" % [CardData.faction_name_of(f), rate2 * 100.0])
	print("\n  [参考] 落在 %.0f%%~%.0f%% 之外的国家：%s" % [
		REF_MIN * 100.0, REF_MAX * 100.0,
		"、".join(off_ref) if not off_ref.is_empty() else "无"])
	print("  [说明] 逐国胜率受《流派设计稿》的英杰能力差异影响，此处只报告不判定；")
	print("         根因与可行的调平杠杆见 功能清单.md 第 20 章。")

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _play_one(a: String, b: String, seed_v: int) -> void:
	var gs: GameState = load("res://scripts/GameState.gd").new()
	# 显式指定双方阵营（p_ai_faction = b），保证跑的就是 a vs b 这一组对阵
	var deck_a: DeckList = null
	var deck_b: DeckList = null
	if _archetypes:
		deck_a = Archetypes.build(a, seed_v % 2, _deck_db)
		deck_b = Archetypes.build(b, (seed_v / 2) % 2, _deck_db)
	gs.start_match(a, deck_a, deck_b, seed_v, b)

	if gs.players[0].faction != a or gs.players[1].faction != b:
		_wrong_faction_games += 1

	var used := [0, 0]
	var guard := 0
	while gs.phase != GameState.Phase.MATCH_END and guard < 6000:
		guard += 1
		match gs.phase:
			GameState.Phase.MULLIGAN:
				for i in gs.mulligan_order:
					if gs.mulligan_done[i]:
						continue
					var ids: Array[String] = []
					for c in AIOpponent.choose_mulligan(gs, i):
						ids.append(c.id)
					gs.execute_command(Command.mulligan(i, ids))
			GameState.Phase.PLAY:
				var p: int = gs.active
				var card: CardData = AIOpponent.choose_card(gs, p)
				if card == null:
					gs.execute_command(Command.pass_turn(p))
				elif card.card_type == CardData.TYPE_TACTIC:
					# 走与 MatchScreen._on_ai_timeout 完全相同的分派逻辑
					if gs.execute_command(Command.play_tactic(p, card.id)).ok:
						used[p] += 1
					else:
						gs.execute_command(Command.pass_turn(p))
				else:
					if not gs.execute_command(Command.play_card(p, card.id, AIOpponent.choose_row(gs, p, card), -1)).ok:
						gs.execute_command(Command.pass_turn(p))
			GameState.Phase.ROUND_END:
				gs.execute_command(Command.advance_round())
			_:
				break

	if guard >= 6000:
		_stuck_games += 1

	var summary: Dictionary = gs.match_summary
	var winner: int = int(summary.get("winner", -1))

	_bump(_games, a)
	_bump(_games, b)
	_total_games += 1
	if winner == 0:
		_bump(_wins, a)
		_bump(_losses, b)
	elif winner == 1:
		_bump(_wins, b)
		_bump(_losses, a)
	else:
		_bump(_draws, a)
		_bump(_draws, b)

	for i in range(2):
		var f: String = gs.players[i].faction
		_tactic_by_faction[f] = int(_tactic_by_faction.get(f, 0)) + int(used[i])
	if int(used[0]) + int(used[1]) > 0:
		_games_with_tactic += 1


func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1
