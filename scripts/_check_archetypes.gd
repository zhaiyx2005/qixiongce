extends SceneTree

## 「系统推荐流派」数据层与合法性的常备回归（第 20 阶段新增）。
##
## 覆盖：
##   A 流派数据可载入（七国 × 2 套，0 错误）
##   B 14 套全部能构造出 29 张合法卡组（DeckRules.validate 通过）
##   C 每套三行都有可落单位（不是瘸腿流派）
##   D 计策全部是本国专属（不存在通用计策）
##   E 每张卡的 ability_id 都有定义，且 能力名 == 卡名（防止改名后描述表不同步）
##
## 【为什么值得单独立一个】流派数据是「卡名 → id」的软引用：
## 任何一次卡池改名都可能只改一半，静默地让某个流派少一张卡。
## 这个套件就是那道防线。

const GOLDEN_SIZE := 29
const GOLDEN_NORMAL := 20
const GOLDEN_HERO := 2
const GOLDEN_TACTIC := 6
const GOLDEN_LEADER := 1
## 每国专属计策数（与 CardDB.TACTICS_PER_FACTION 一致）
const TACTICS_PER_FACTION := 8
## 每个阵营应有的推荐流派数
const ARCHETYPES_PER_FACTION := 2

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


func _run() -> void:
	_watchdog()
	print("\n===== 推荐流派数据与合法性检查 =====")

	var db := CardDB.new()
	Archetypes.reload()
	var arch_errors := Archetypes.load_errors()

	# ---------------- A 数据载入 ----------------
	print("\n[A] 流派数据载入")
	_ok(arch_errors.is_empty(), "流派数据无载入错误（%s）" % (
		"无" if arch_errors.is_empty() else "；".join(arch_errors)))
	var total := 0
	for faction in CardData.FACTIONS:
		var n := Archetypes.count_for(faction)
		total += n
		_ok(n == ARCHETYPES_PER_FACTION,
			"%s 有 %d 套推荐流派（期望 %d）" % [CardData.faction_name_of(faction), n, ARCHETYPES_PER_FACTION])
	_ok(total == 14, "推荐流派合计 14 套（实际 %d）" % total)

	# ---------------- B/C 每套卡组 ----------------
	print("\n[B] 14 套流派均可构造且构筑合法")
	for faction in CardData.FACTIONS:
		var fname := CardData.faction_name_of(faction)
		for i in range(Archetypes.count_for(faction)):
			var item := Archetypes.list_for(faction)[i]
			var title := Archetypes.title_of(item)
			var tag := "%s·%s" % [fname, title]

			_ok(Archetypes.deck_size_of(item) == GOLDEN_SIZE,
				"%s 卡名表合计 %d 张（期望 %d）" % [tag, Archetypes.deck_size_of(item), GOLDEN_SIZE])

			var deck := Archetypes.build(faction, i, db)
			if deck == null:
				_ok(false, "%s 构造失败：%s" % [tag, "；".join(Archetypes.load_errors())])
				continue

			var errs := DeckRules.validate(deck, db)
			_ok(errs.is_empty(), "%s 构筑校验通过（%s）" % [tag,
				"无错误" if errs.is_empty() else "；".join(errs)])

			var counts := DeckRules.count_by_category(deck, db)
			_ok(int(counts["total"]) == GOLDEN_SIZE
				and int(counts["normal"]) == GOLDEN_NORMAL
				and int(counts["hero"]) == GOLDEN_HERO
				and int(counts["tactic"]) == GOLDEN_TACTIC
				and int(counts["leader"]) == GOLDEN_LEADER,
				"%s 分类计数 20/2/6/1（实际 %d/%d/%d/%d）" % [tag,
					int(counts["normal"]), int(counts["hero"]),
					int(counts["tactic"]), int(counts["leader"])])

			# C 三行都不瘸腿
			var cards := deck.build_cards(db)
			var can_melee := 0
			var can_ranged := 0
			var can_garrison := 0
			for card in cards:
				if card.card_type != CardData.TYPE_UNIT:
					continue
				if card.can_place_in(CardData.ROW_MELEE):
					can_melee += 1
				if card.can_place_in(CardData.ROW_RANGED):
					can_ranged += 1
				if card.can_place_in(CardData.ROW_GARRISON):
					can_garrison += 1
			_ok(can_melee >= 6 and can_ranged >= 5 and can_garrison >= 4,
				"%s 三行都填得满（可落 近战%d/远程%d/守军%d）" % [tag, can_melee, can_ranged, can_garrison])

	# ---------------- D 计策必须全部是本国专属 ----------------
	# 【设计决定】不存在「通用计策」：七国各有自己专属的 8 张计策。
	# 这里三道防线：① 计策池里没有外来卡；② 14 套流派用到的计策全属本国；
	# ③ 把一张外阵营计策塞进卡组时 `DeckRules.validate()` 必须仍然拒绝（防回归）。
	print("\n[D] 计策阵营纯净性")
	var foreign_in_pool := 0
	for faction in CardData.FACTIONS:
		var pool := db.get_tactic_cards_by_faction(faction)
		_ok(pool.size() == TACTICS_PER_FACTION,
			"%s 专属计策 %d 张（期望 %d）" % [
				CardData.faction_name_of(faction), pool.size(), TACTICS_PER_FACTION])
		for card in pool:
			if card.faction != faction:
				foreign_in_pool += 1
	_ok(foreign_in_pool == 0, "★ 没有任何阵营的计策池混入外来计策（%d）" % foreign_in_pool)

	var foreign_in_deck := 0
	for faction in CardData.FACTIONS:
		for i in range(Archetypes.count_for(faction)):
			var deck := Archetypes.build(faction, i, db)
			if deck == null:
				continue
			for entry in deck.entries():
				var card := db.get_card_by_id(entry["id"])
				if card != null and card.card_type == CardData.TYPE_TACTIC and card.faction != faction:
					foreign_in_deck += 1
	_ok(foreign_in_deck == 0, "★ 14 套流派用到的计策全部属于本国（外来 %d）" % foreign_in_deck)

	# 反向断言：跨阵营计策必须仍被构筑校验拒绝
	var probe := DeckList.new(CardData.FACTION_QI, "跨阵营探针")
	probe.set_card_count("qin_tactic_01", 1)
	var probe_errors := DeckRules.validate(probe, db)
	var rejected := false
	for e in probe_errors:
		if str(e).find("不属于") >= 0:
			rejected = true
	_ok(rejected, "★ 跨阵营计策仍被 DeckRules 拒绝（回归保护）")

	# ---------------- E 卡名 / 能力一致性 ----------------
	print("\n[E] 能力定义与卡名一致")
	var missing_def: PackedStringArray = PackedStringArray()
	var name_mismatch: PackedStringArray = PackedStringArray()
	for card in db.get_all_cards():
		if card.ability_id.is_empty():
			continue
		var d := Abilities.def(card.ability_id)
		if d.is_empty():
			missing_def.append("%s(%s)" % [card.name, card.ability_id])
			continue
		# 单位能力（同袍/结阵…）与卡名无关，只校验「一人一卡」的英杰 / 领袖 / 计策
		if card.is_hero() or card.card_type == CardData.TYPE_LEADER \
				or card.card_type == CardData.TYPE_TACTIC:
			if Abilities.ability_name(card.ability_id) != card.name:
				name_mismatch.append("%s ≠ %s" % [
					card.name, Abilities.ability_name(card.ability_id)])
	_ok(missing_def.is_empty(), "所有 ability_id 均有定义（%s）" % (
		"缺 " + ", ".join(missing_def) if not missing_def.is_empty() else "无缺失"))
	_ok(name_mismatch.is_empty(), "英杰/领袖/计策的能力名与卡名一致（%s）" % (
		"不一致：" + ", ".join(name_mismatch) if not name_mismatch.is_empty() else "全部一致"))

	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
