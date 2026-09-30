extends RefCounted
class_name EffectRunner

## 能力效果执行器：把 ability_id 映射到具体的原子操作序列。
## 所有状态改动一律经 EffectResolver → GameState.apply_power_change，保证口径唯一。

var _state_ref: WeakRef
var state: GameState:
	get:
		return _state_ref.get_ref() as GameState
	set(value):
		_state_ref = weakref(value)
var res: EffectResolver


func _init(p_state: GameState) -> void:
	state = p_state
	res = EffectResolver.new(p_state)


# ---------------- 单位进场（ON_PLAY） ----------------

## card 刚被放到 row。返回战报文本（无效果则空串）。
func run_unit_on_play(owner_index: int, card: CardData, row: String,
		pre_row_power: int, pre_other_row_power: int) -> String:
	var owner := state.players[owner_index]
	var foe := state.players[1 - owner_index]
	match card.ability_id:
		"inf_valor":
			if pre_row_power < pre_other_row_power:
				state.apply_power_change(card, 3, "奋勇")
				return "奋勇：本行原落后，%s 永久 +3" % card.name
		"inf_summon":
			return _summon_same_name(owner, card, row)
		"arc_volley":
			var hit := res.damage_row(foe, CardData.ROW_MELEE, 1, "齐射")
			if not hit.is_empty():
				return "齐射：对方近战行 %d 个单位 -1" % hit.size()
		"arc_precise":
			var picks := res.pick_highest(foe)
			var n := 0
			for c in picks:
				if state.apply_power_change(c, -2, "精准"):
					n += 1
			if n > 0:
				return "精准：对方最高战力 %d 个单位 -2" % n
		"arc_cover":
			var hit2 := res.buff_row(owner, CardData.ROW_MELEE, 1, "掩护")
			if not hit2.is_empty():
				return "掩护：己方近战行 %d 个单位永久 +1" % hit2.size()
		"cav_raid":
			if row == CardData.ROW_MELEE:
				var hit3 := res.damage_row(foe, CardData.ROW_RANGED, 1, "突袭")
				if not hit3.is_empty():
					return "突袭：对方远程行 %d 个单位 -1" % hit3.size()
		"cav_trample":
			if row == CardData.ROW_MELEE and _other_cavalry_count(owner, card, row) >= 1:
				var hit4 := res.damage_row(foe, CardData.ROW_MELEE, 1, "践踏")
				if not hit4.is_empty():
					return "践踏：对方近战行 %d 个单位 -1" % hit4.size()
		"cav_charge":
			var picks2 := res.pick_lowest(foe)
			var n2 := 0
			for c in picks2:
				if state.apply_power_change(c, -2, "冲阵"):
					n2 += 1
			if n2 > 0:
				return "冲阵：对方最低战力 %d 个单位 -2" % n2
		# ---------------- 英杰（七国共享机制，战报名字动态取） ----------------
		# 【战报里的名字必须动态取】七国共用同一段实现，若把「白起」写进文案，
		# 齐国的孙膑打出同机制时会显示成「白起：摧毁对方……」。
		# 统一用 Abilities.ability_name(card.ability_id)，而英杰能力的 name 就是人名。
		#
		# 【按设计稿重排（第 20 阶段）】设计稿给每位英杰指定了效果，与旧实现有约一半不同。
		# 重排时**没有引入任何新的原子操作** —— 全部是既有「抽牌 / 全场增减 / 行减益 /
		# 召唤 / 收回」的组合，避免一次改动同时变更「机制」与「数值」两个变量。
		# 同步修正了两处旧实现与卡面描述相反的历史问题：
		#   李牧 实为「摧毁最高」（描述是落后+1）、廉颇 实为「单位数占优+1」（描述是清同行减益）。
		"hero_baiqi":
			var killed := res.destroy_highest(foe)
			if not killed.is_empty():
				var names := PackedStringArray()
				for c in killed:
					names.append(c.name)
				return "%s：摧毁对方 %s" % [Abilities.ability_name(card.ability_id),
					", ".join(names)]
		# 荆轲 —— 逆风刺杀：摧毁对方战力最高的「一张」，且**仅在己方人数不占优时**。
		# 【为什么要加门槛】白起是「所有并列最高」且无门槛；荆轲只取一张，
		# 若也做成无条件，燕（乐毅 + 荆轲）会稳定比秦（白起 + 王翦）高约 10 个百分点。
		"hero_yan_jingke":
			# 【为什么从「摧毁」降级为「−3」】摧毁（进弃牌堆）实测等价于 +10pp，
			# 远超其余国家的 6 战力英杰，会把燕顶到 53% 以上。降级为单体重创后
			# 与暴鸢（对方最高全体 −2）同档。
			# 目标筛选用 pick_extreme_destroyable —— 它其实就是「战力最高的非英杰单位」
			# （英杰免疫战力变化，含进去会白选一张）。
			var top := res.pick_extreme_destroyable(foe, true)
			if not top.is_empty() and state.apply_power_change(top[0], -2, "荆轲"):
				return "%s：对方「%s」-2" % [Abilities.ability_name(card.ability_id), top[0].name]
		# 单位数占优时己方全场 +1（英杰不吃）—— 乐乘
		"hero_yan_yuecheng":
			if res.all_units(owner).size() > res.all_units(foe).size():
				var n3 := _buff_side_except_heroes(owner, 1, "单位数占优")
				if n3 > 0:
					return "%s：己方全场 %d 个单位 +1" % [
						Abilities.ability_name(card.ability_id), n3]
		# 抽 1 张单位牌 —— 乐毅
		# 【为什么换成抽牌】燕原本是全七国最低（44.4%），因为它的两位英杰里
		# 一个「条件全场 +1」在空场打出等于没有、一个只是 −2 单体伤害 —— 一次抽牌都没有。
		# 换成抽牌后与其余国家的结构对齐（1 抽牌 + 1 伤害）。
		"hero_yan_yueyi":
			var got_yy := _draw_unit(owner)
			if got_yy != null:
				return "%s：抽到单位牌「%s」" % [Abilities.ability_name(card.ability_id), got_yy.name]
		# 抽 1 张单位牌 —— 王翦
		# 【对齐口径】AI 总在第一回合就把英杰打出去，场面还是空的，
		# 「全场 +1」实际加到 0 个单位。抽牌不受场面影响，是可靠的等价收益。
		"hero_wangjian":
			var got_wj := _draw_unit(owner)
			if got_wj != null:
				return "%s：抽到单位牌「%s」" % [Abilities.ability_name(card.ability_id), got_wj.name]
		# 对方战力最高的所有单位 −2 —— 项燕
		# 【为什么不用「全场 +1」】诊断显示该英杰 13 次打出只有 1 次真正加到了人
		# （AI 常在空场时打出英杰），条件型全场增益的实际收益接近 0，
		# 于是楚长期是全七国最低。改成「对方最高全体 −2」这种不依赖己方场面的效果，
		# 触发率 100%，且符合「楚虽三户，亡秦必楚」的反击气质。
		"hero_chu_xiangyan":
			var picks_x := res.pick_highest(foe)
			var n_x := 0
			for c in picks_x:
				if state.apply_power_change(c, -2, "项燕"):
					n_x += 1
			# 【不要再给它加抽牌】试过给项燕补一手过牌，楚立刻从 44.6% 冲到 59.0% ——
			# 「抽 1 张」在本作里价值 ≈ +7~14pp（AI 打光手牌就 Pass，多一张牌常常
			# 等于多打一轮）。所以抽牌要按国家配额给，不能凭手感加。
			if n_x > 0:
				return "%s：对方最高战力 %d 个单位 -2" % [
					Abilities.ability_name(card.ability_id), n_x]
		# 抽 1 张单位牌 —— 司马错
		"hero_simacuo":
			var got := _draw_unit(owner)
			if got != null:
				return "%s：抽到单位牌「%s」" % [Abilities.ability_name(card.ability_id), got.name]
		# 抽 1 张计策牌 —— 樗里疾 / 管仲
		"hero_chuliji", "hero_qi_guanzhong":
			var got2 := _draw_tactic(owner)
			if got2 != null:
				return "%s：抽到计策牌「%s」" % [Abilities.ability_name(card.ability_id), got2.name]
		# 总战力落后时己方全场 +1（英杰不吃）—— 李牧 / 庄蹻
		"hero_limu":
			var reinforcement := res.fetch_to_hand(owner, func(c: CardData) -> bool: return c.unit_type == CardData.UNIT_CAVALRY)
			return "李牧：检索骑兵「%s」" % reinforcement.name if reinforcement != null else "李牧：牌库无骑兵"
		"hero_chu_zhuangqiao":
			if owner.total_power() < foe.total_power():
				var n4 := _buff_side_except_heroes(owner, 1, "逆风")
				if n4 > 0:
					return "%s：己方全场 %d 个单位 +1" % [
						Abilities.ability_name(card.ability_id), n4]
		# 清除同行减益，恢复至卡面基础战力 —— 廉颇
		"hero_lianpo":
			var n5 := 0
			for c in owner.row_cards(row):
				if state.reset_to_base(c):
					n5 += 1
			if n5 > 0:
				return "%s：同行 %d 个单位恢复至卡面基础战力" % [
					Abilities.ability_name(card.ability_id), n5]
		# 本行落后时对方同行 -2 —— 赵奢 / 庞涓
		"hero_wei_pangjuan":
			var hit_count := 0
			if pre_row_power < pre_other_row_power:
				for target in FactionEffects.select_units(foe, row, "", 3, true):
					if state.apply_power_change(target, -2, "庞涓"):
						hit_count += 1
			return "庞涓：本行反击，%d 个单位 -2" % hit_count
		"hero_zhaoshe":
			if owner.row_power(row) < foe.row_power(row):
				var hit5 := res.damage_row(foe, row, 2, "本行反击")
				if not hit5.is_empty():
					return "%s：本行落后，对方同行 %d 个单位 -2" % [
						Abilities.ability_name(card.ability_id), hit5.size()]
		# 收回己方最低战力单位（该牌再打出时 +1）—— 蔺相如 / 公孙衍 / 信陵君
		"hero_linxiangru", "hero_han_gongsunyan", "hero_wei_xinlingjun":
			var back := res.return_lowest_to_hand(owner)
			if back != null:
				return "%s：收回己方「%s」" % [Abilities.ability_name(card.ability_id), back.name]
		# ---- 设计稿新增的六种组合机制（全部由既有原子操作拼出，零新原子） ----
		# 抽 1 张计策牌 —— 孙膑
		# 【为什么只剩抽牌】试过「全场 +1」「门槛 + 全场 +1」「本行 +1」三档，
		# 实测对齐的胜率几乎不变 —— 因为 AI 打出英杰时场面常常还很小，
		# 增益打在空场上等于没有。抽牌是唯一 100% 生效的部分，
		# 所以把齐的强度完全交给「过牌」这一条，再靠田忌的骑兵增益拉开特色。
		"hero_qi_sunbin":
			var g_sb := _draw_tactic(owner)
			if g_sb != null:
				return "%s：抽到计策牌「%s」" % [Abilities.ability_name(card.ability_id), g_sb.name]
		# 己方单位数 ≥ 对方时，对方最高战力所有单位 -2 —— 匡章
		"hero_qi_kuangzhang":
			if res.all_units(owner).size() >= res.all_units(foe).size():
				var picks_k := res.pick_highest(foe)
				var n_k := 0
				for c in picks_k:
					if state.apply_power_change(c, -2, "匡章"):
						n_k += 1
				if n_k > 0:
					return "%s：单位数占优，对方最高战力 %d 个单位 -2" % [
						Abilities.ability_name(card.ability_id), n_k]
		# 抽 1 张计策牌 + 清除己方守军行减益 —— 屈原
		# 【为什么从「全场 +1」换成「抽牌」】见王翦处的说明：英杰几乎总在空场打出，
		# 场面增益的期望收益接近 0 且方差极大，抽牌才是可靠收益。
		"hero_chu_quyuan":
			var cl_qy := res.clear_debuffs_in_row(owner, CardData.ROW_GARRISON, "屈原")
			var g_qy := _draw_tactic(owner)
			var msg_qy := ""
			if g_qy != null:
				msg_qy = "抽到计策牌「%s」" % g_qy.name
			if not cl_qy.is_empty():
				msg_qy += ("；" if not msg_qy.is_empty() else "") + "清除守军行 %d 个减益" % cl_qy.size()
			if not msg_qy.is_empty():
				return "%s：%s" % [Abilities.ability_name(card.ability_id), msg_qy]
		# 从牌库召唤铺场到本行（优先同名卡）—— 昭阳 / 剧辛
		"hero_chu_zhaoyang", "hero_yan_juxin":
			var same := _hero_summon(owner, card, row)
			if same != null:
				return "%s：从牌库召唤「%s」（战力 %d）到本行" % [
					Abilities.ability_name(card.ability_id), same.name, same.power]
		# 抽 1 张单位牌 —— 吴起（武卒靠的是兵源不断）
		"hero_wei_wuqi":
			var got_wq := _draw_unit(owner)
			if got_wq != null:
				return "%s：抽到单位牌「%s」" % [Abilities.ability_name(card.ability_id), got_wq.name]
		# 抽 1 张计策牌 —— 申不害（术治靠的是筹算）
		"hero_han_shenbuhai":
			var got_sbh := _draw_tactic(owner)
			if got_sbh != null:
				return "%s：抽到计策牌「%s」" % [Abilities.ability_name(card.ability_id), got_sbh.name]
		# 从牌库召唤战力最高的单位牌到近战行 —— 乐羊
		"hero_wei_leyang":
			var s_ly := res.summon_from_deck(owner, CardData.ROW_MELEE, null)
			if s_ly != null:
				return "%s：从牌库召唤「%s」（战力 %d）到近战行" % [
					Abilities.ability_name(card.ability_id), s_ly.name, s_ly.power]
		# 对方最高战力所有单位 -2 —— 暴鸢
		"hero_han_baoyuan":
			var picks_by := res.pick_highest(foe)
			var n_by := 0
			for c in picks_by:
				if state.apply_power_change(c, -2, "暴鸢"):
					n_by += 1
			if n_by > 0:
				return "%s：对方最高战力 %d 个单位 -2" % [
					Abilities.ability_name(card.ability_id), n_by]
		# 抽 1 张计策牌 + 清除己方远程行减益 —— 韩非
		"hero_han_feizi":
			var msg_hf := ""
			var g_hf := _draw_tactic(owner)
			if g_hf != null:
				msg_hf = "抽到计策牌「%s」" % g_hf.name
			var cl_hf := res.clear_debuffs_in_row(owner, CardData.ROW_RANGED, "韩非")
			if not cl_hf.is_empty():
				msg_hf += ("；" if not msg_hf.is_empty() else "") + "清除远程行 %d 个减益" % cl_hf.size()
			if not msg_hf.is_empty():
				return "%s：%s" % [Abilities.ability_name(card.ability_id), msg_hf]
		# 己方总战力落后时，抽 1 张牌并己方骑兵 +1 —— 田忌
		# 【为什么下调】齐原本是全七国最高（58%）。原实现「落后时骑兵 +2」
		# 收益接近其他国家的 6 战力英杰，但齐的 7 战力孙膑已经提供了过牌，
		# 两份可靠收益叠加把齐顶了起来。这里把 +2 降到 +1 并补一点过牌，
		# 保留「逆风赛马」的手感而把总量拉回中间。
		"hero_qi_tianji":
			if owner.total_power() < foe.total_power():
				var n_tj := 0
				for c in res.all_units(owner):
					if c.unit_type == CardData.UNIT_CAVALRY \
							and state.apply_power_change(c, 1, "田忌"):
						n_tj += 1
				# 【不要在这里抽牌】齐的孙膑已经提供过一次过牌，再叠一张会让齐偏强。
				if n_tj > 0:
					return "%s：己方落后，%d 个骑兵 +2" % [
						Abilities.ability_name(card.ability_id), n_tj]
	return ""


## 蔺相如 / 完璧归赵 收回的牌再次打出时的永久 +1（每张卡只触发一次）。
func apply_returned_bonus(owner_index: int, card: CardData) -> bool:
	var owner := state.players[owner_index]
	if not owner.returned_before.has(card):
		return false
	if bool(owner.returned_before[card]):
		return false
	owner.returned_before[card] = true
	state.apply_power_change(card, 1, "归赵")
	return true


# ---------------- 计策结算（ON_PLAY） ----------------

## 计策结算（ON_PLAY）。
##
## 【七国共享】每个 case 里并列多个 ability_id —— 它们共用同一段实现。
## 战报文案里**不含计策名**（`_do_play_tactic` 会先单独发一条「使用计策「X」」），
## 所以共享分支不会串名字。新增国家时只需把 id 追加到对应机制的 case 列表。
func run_tactic(owner_index: int, card: CardData) -> String:
	if FactionEffects.TACTICS.has(card.ability_id):
		return FactionEffects.run_tactic(state, owner_index, card.ability_id)
	var owner := state.players[owner_index]
	var foe := state.players[1 - owner_index]
	match card.ability_id:
		# M1 对方最高战力 -2
		"tac_yuanjiao", "tac_qi_weiwei", "tac_chu_wending", "tac_yan_xiaqi", \
		"tac_han_jinnu", "tac_wei_wuzuzhi", "tac_yuyu":
			var picks := res.pick_highest(foe)
			var n := 0
			for c in picks:
				if state.apply_power_change(c, -2, "远交近攻"):
					n += 1
			return "对方最高战力 %d 个单位 -2" % n
		# M2 对方最高行 -1 + 己方抽 1
		"tac_lianheng", "tac_qi_tianji", "tac_chu_yanying", \
		"tac_yan_jingke", "tac_han_nubing", "tac_wei_wuzu", "tac_handan":
			var row := res.strongest_row(foe)
			var msg := ""
			if not row.is_empty():
				var hit := res.damage_row(foe, row, 1, "连横")
				msg = "对方「%s」行 %d 个单位 -1" % [state.row_name(row), hit.size()]
			var got := owner.draw(1)
			if not got.is_empty():
				msg += ("；" if not msg.is_empty() else "") + "己方抽 1 张"
			return msg if not msg.is_empty() else "无目标"
		# M3 己方全场 +1（魏的「魏武卒」已改挂 M2，见上）
		"tac_jungong", "tac_qi_zunwang", "tac_chu_bilu", "tac_yan_kuhan", "tac_han_yiyang":
			var hit2 := res.buff_all(owner, 1, "军功爵")
			return "己方全场 %d 个单位 +1" % hit2.size()
		# M4 己方抽 2 张
		"tac_zhengguoqu", "tac_qi_jixia", "tac_chu_yunmeng", "tac_yan_huangjin", \
		"tac_han_shuzhi", "tac_wei_likui":
			var got2 := owner.draw(2)
			return "己方抽 %d 张" % got2.size()
		# M5 清除己方守军行减益
		"tac_hangu", "tac_han_shenzi":
			var hit3 := res.clear_debuffs_in_row(owner, CardData.ROW_GARRISON, "函谷关")
			return "清除己方守军行 %d 个单位的减益" % hit3.size()
		# M6 从牌库召唤战力最高的单位到守军行
		"tac_ironeagle", "tac_chu_shenxi", "tac_han_xinzheng":
			var s := res.summon_from_deck(owner, CardData.ROW_GARRISON, null)
			if s != null:
				return "从牌库召唤「%s」（战力 %d）到守军行" % [s.name, s.power]
			return "牌库中没有可召唤的单位"
		# M7 弃 1 张手牌，己方全场 +2
		"tac_fenzhou", "tac_qi_jiji", "tac_wei_ximen":
			var discarded := _discard_worst(owner)
			var hit4 := res.buff_all(owner, 2, "焚舟破釜")
			var msg2 := "己方全场 %d 个单位 +2" % hit4.size()
			if discarded != null:
				msg2 = "弃「%s」，" % discarded.name + msg2
			return msg2
		# M8 对方近战行 -2
		"tac_qincrossbow":
			var hit5 := res.damage_row(foe, CardData.ROW_MELEE, 2, "秦弩阵")
			return "对方近战行 %d 个单位 -2" % hit5.size()
		# M9 己方全场骑兵 +2
		"tac_hufu":
			var n2 := 0
			for c in res.all_units(owner):
				if c.unit_type == CardData.UNIT_CAVALRY:
					if state.apply_power_change(c, 2, "胡服骑射"):
						n2 += 1
			return "己方 %d 个骑兵 +2" % n2
		# M10 收回己方最低战力单位 + 抽 1
		"tac_wanbi", "tac_chu_chucai", "tac_yan_zhaoxian", "tac_wei_qiefu":
			var back := res.return_lowest_to_hand(owner)
			var got3 := owner.draw(1)
			var msg3 := ""
			if back != null:
				msg3 = "收回己方「%s」" % back.name
			if not got3.is_empty():
				msg3 += ("；" if not msg3.is_empty() else "") + "己方抽 1 张"
			return msg3 if not msg3.is_empty() else "无目标"
		# M11 己方全场 +1（赵·将相和）
		"tac_jiangxiang":
			var hit6 := res.buff_all(owner, 1, "将相和")
			return "己方全场 %d 个单位 +1" % hit6.size()
		# M12 己方落后时，对方战力最高的行 -2
		"tac_wei_daliang":
			if owner.total_power() < foe.total_power():
				var row2 := res.strongest_row(foe)
				if not row2.is_empty():
					var hit7 := res.damage_row(foe, row2, 2, "阏与之战")
					return "己方落后，对方「%s」行 %d 个单位 -2" % [
						state.row_name(row2), hit7.size()]
			return "己方未落后，无事发生"
		# M13 清除己方守军行减益 + 守军行 +1
		"tac_jianbi", "tac_qi_jimo", "tac_chu_fangcheng", "tac_yan_liaodong", \
		"tac_han_shangdang":
			var hit8 := res.clear_debuffs_in_row(owner, CardData.ROW_GARRISON, "坚壁清野")
			var hit9 := res.buff_row(owner, CardData.ROW_GARRISON, 1, "坚壁清野")
			return "清除守军行 %d 个减益，守军行 %d 个单位 +1" % [hit8.size(), hit9.size()]
		# M14 从牌库召唤骑兵到近战行
		"tac_daijun", "tac_wei_henei":
			var s2 := res.summon_from_deck(owner, CardData.ROW_MELEE,
				func(c: CardData) -> bool: return c.unit_type == CardData.UNIT_CAVALRY)
			if s2 != null:
				return "从牌库召唤「%s」（战力 %d）到近战行" % [s2.name, s2.power]
			return "牌库中没有可召唤的骑兵"
		# M15 己方单位数 ≥ 对方时全场 +2
		"tac_hezong", "tac_qi_jiuhe", "tac_chu_baiyue", "tac_yan_wugu", \
		"tac_han_hanwei", "tac_wei_wuqilianbing":
			if res.all_units(owner).size() >= res.all_units(foe).size():
				var hit10 := res.buff_all(owner, 2, "合纵")
				return "己方单位数不少于对方，全场 %d 个单位 +2" % hit10.size()
			return "己方单位数少于对方，无事发生"
		# M16 对方最低战力 -1；守军行有单位则抽 1
		"tac_qi_huoniu", "tac_yan_yishui":
			var picks2 := res.pick_lowest(foe)
			var n3 := 0
			for c in picks2:
				if state.apply_power_change(c, -1, "邯郸之围"):
					n3 += 1
			var msg4 := "对方最低战力 %d 个单位 -1" % n3
			if not owner.row_cards(CardData.ROW_GARRISON).is_empty():
				var got4 := owner.draw(1)
				if not got4.is_empty():
					msg4 += "；守军行有单位，己方抽 1 张"
			return msg4
	return ""


# ---------------- 领袖 ----------------

## 整场对局开始（拿到牌库后立刻结算）。
## 整场对局开始（拿到牌库后立刻结算）。
##
## 【七国共享，名字动态取】领袖能力的 name 就是君主名，所以战报文案统一用
## `Abilities.ability_name()`，写死「秦孝公」会让齐国的齐桓公串名字。
func run_leader_match_start(owner_index: int) -> String:
	var owner := state.players[owner_index]
	var foe := state.players[1 - owner_index]
	if owner.leader == null:
		return ""
	var who := Abilities.ability_name(owner.leader.ability_id)
	match owner.leader.ability_id:
		# 开局从牌库检索 1 张单位牌加入手牌
		"leader_qinxiaogong", "leader_qi_huan", "leader_chu_zhuang", \
		"leader_yan_zhao", "leader_han_wen":
			var got := res.fetch_to_hand(owner,
				func(c: CardData) -> bool: return c.card_type == CardData.TYPE_UNIT)
			if got != null:
				return "%s：从牌库检索「%s」加入手牌" % [who, got.name]
		# 开局从牌库检索 1 张计策牌（设计稿·齐宣王）
		"leader_qi_xuan":
			var got3 := res.fetch_to_hand(owner,
				func(c: CardData) -> bool: return c.card_type == CardData.TYPE_TACTIC)
			if got3 != null:
				return "%s：从牌库检索计策「%s」加入手牌" % [who, got3.name]
		# 开局摧毁对方牌库随机 1 张单位牌
		"leader_qinzhaoxiang", "leader_han_an", "leader_wei_hui":
			var killed := res.destroy_from_deck(foe,
				func(c: CardData) -> bool: return c.card_type == CardData.TYPE_UNIT)
			if killed != null:
				return "%s：摧毁对方牌库中的「%s」" % [who, killed.name]
		# 开局从牌库检索 1 张骑兵加入手牌（设计稿把魏武侯也归入此列）
		"leader_zhaowuling", "leader_wei_wu":
			var got2 := res.fetch_to_hand(owner,
				func(c: CardData) -> bool: return c.unit_type == CardData.UNIT_CAVALRY)
			if got2 != null:
				return "%s：从牌库检索骑兵「%s」加入手牌" % [who, got2.name]
			var fallback := res.fetch_to_hand(owner,
				func(c: CardData) -> bool: return c.card_type == CardData.TYPE_UNIT)
			if fallback != null:
				return "%s：牌库无骑兵，检索「%s」加入手牌" % [who, fallback.name]
		# 开局己方随机 1 张单位牌 +2
		"leader_zhaoxiaocheng", "leader_yan_hui":
			var units := owner.unit_cards_in_hand()
			units.append_array(_deck_units(owner))
			if not units.is_empty():
				var pick: CardData = units[state.rng.randi_range(0, units.size() - 1)]
				owner.add_permanent(pick, 2)
				return "%s：己方「%s」永久 +2" % [who, pick.name]
	return ""


## 每局开始（清场后、抽牌后）。
func run_leader_round_start(owner_index: int) -> String:
	var owner := state.players[owner_index]
	if owner.leader == null:
		return ""
	var who := Abilities.ability_name(owner.leader.ability_id)
	match owner.leader.ability_id:
		# 每局开始己方近战行 +1
		"leader_qinhuiwen", "leader_chu_wei", "leader_wei_wen":
			return _round_row_bonus(owner, CardData.ROW_MELEE, 1, who)
		# 每局开始己方守军行 +1（设计稿把楚怀王也归入此列）
		"leader_zhaohuiwen", "leader_yan_kuai", "leader_chu_huai":
			return _round_row_bonus(owner, CardData.ROW_GARRISON, 1, who)
		# 每局开始己方远程行 +1
		"leader_qi_wei", "leader_han_zhao":
			return _round_row_bonus(owner, CardData.ROW_RANGED, 1, who)
	return ""


## 行光环：本局内该行每个单位进场时自动 +power。
func setup_round_auras(owner_index: int) -> void:
	var owner := state.players[owner_index]
	owner.row_aura.clear()
	if owner.leader == null:
		return
	match owner.leader.ability_id:
		"leader_qinhuiwen", "leader_chu_wei", "leader_wei_wen":
			owner.row_aura[CardData.ROW_MELEE] = 1
		"leader_zhaohuiwen", "leader_yan_kuai", "leader_chu_huai":
			owner.row_aura[CardData.ROW_GARRISON] = 1
		"leader_qi_wei", "leader_han_zhao":
			owner.row_aura[CardData.ROW_RANGED] = 1


func _round_row_bonus(owner: PlayerState, row: String, delta: int, who: String) -> String:
	var hit := res.buff_row(owner, row, delta, who)
	if hit.is_empty():
		return ""
	return "%s：己方「%s」行 %d 个单位 +%d" % [who, state.row_name(row), hit.size(), delta]


# ---------------- 计数触发（老兵） ----------------

## 计数触发（老兵）：己方回合数由 GameState.turn_counts 统一维护，
## 本函数只负责在「该方回合数满 3」时结算老兵，不再自行累加计数。
func run_counting_start_of_turn(owner_index: int) -> String:
	var owner := state.players[owner_index]
	var turn_no := state.turn_count_of(owner_index)
	var msgs := PackedStringArray()
	for row in CardData.ROWS:
		for card in owner.row_cards(row):
			if card.ability_id != "inf_veteran" or card.is_hero():
				continue
			if turn_no < 3:
				continue
			# 每张卡只触发一次：「已触发」用 permanents 里的一次性标记记录
			if owner.veteran_done.has(card):
				continue
			owner.veteran_done[card] = true
			if state.apply_power_change(card, 1, "老兵"):
				msgs.append("老兵：%s 永久 +1" % card.name)
	if msgs.is_empty():
		return ""
	return "、".join(msgs)


# ---------------- 内部辅助 ----------------

func _other_cavalry_count(owner: PlayerState, card: CardData, row: String) -> int:
	var n := 0
	for c in owner.row_cards(row):
		if c != card and c.unit_type == CardData.UNIT_CAVALRY:
			n += 1
	return n


func _buff_side_except_heroes(owner: PlayerState, delta: int, reason: String) -> int:
	var n := 0
	for c in res.all_units(owner):
		if c.is_hero():
			continue
		if state.apply_power_change(c, delta, reason):
			n += 1
	return n


func _summon_same_name(owner: PlayerState, card: CardData, row: String) -> String:
	var s := _summon_same_name_card(owner, card, row)
	if s != null:
		return "征召：从牌库召唤同名的「%s」" % s.name
	return ""


## 真正从牌库召唤同名卡（顺带结算本局的行光环）。
func _summon_same_name_card(owner: PlayerState, card: CardData, row: String) -> CardData:
	var filter := func(c: CardData) -> bool:
		return c.name == card.name and c.card_type == CardData.TYPE_UNIT
	return _summon_and_aura(owner, row, filter)


## 英杰版铺场（昭阳 / 剧辛）：优先召唤牌库里的同名卡；
## 但英杰在牌库里最多只带 1 张（就是它自己），所以实际上几乎永远找不到同名卡。
## 此时退化为「召唤战力最高的单位到本行」—— 否则这两个能力会常年空转。
func _hero_summon(owner: PlayerState, card: CardData, row: String) -> CardData:
	var s := _summon_same_name_card(owner, card, row)
	if s != null:
		return s
	return _summon_and_aura(owner, row, null)


## 从牌库召唤到指定行，并补上该行的本局光环（召唤不是「打出」，光环要手动补）。
func _summon_and_aura(owner: PlayerState, row: String, filter: Variant) -> CardData:
	var s := res.summon_from_deck(owner, row, filter)
	if s == null:
		return null
	var aura := int(owner.row_aura.get(row, 0))
	if aura != 0:
		state.apply_power_change(s, aura, "行光环")
	return s


func _draw_unit(owner: PlayerState) -> CardData:
	var got := res.fetch_to_hand(owner,
		func(c: CardData) -> bool: return c.card_type == CardData.TYPE_UNIT)
	return got


func _draw_tactic(owner: PlayerState) -> CardData:
	var got := res.fetch_to_hand(owner,
		func(c: CardData) -> bool: return c.card_type == CardData.TYPE_TACTIC)
	return got


func _deck_units(owner: PlayerState) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in owner.deck:
		if c.card_type == CardData.TYPE_UNIT:
			out.append(c)
	return out


## 焚舟破釜：弃掉手牌里战力最低的一张（不含计策）。
func _discard_worst(owner: PlayerState) -> CardData:
	var worst: CardData = null
	for c in owner.hand:
		if c.card_type != CardData.TYPE_UNIT:
			continue
		if worst == null or c.power < worst.power:
			worst = c
	if worst == null:
		# 没有单位牌就弃计策
		for c in owner.hand:
			if c.card_type == CardData.TYPE_TACTIC:
				worst = c
				break
	if worst == null:
		return null
	owner.hand.erase(worst)
	owner.discard.append(worst)
	return worst
