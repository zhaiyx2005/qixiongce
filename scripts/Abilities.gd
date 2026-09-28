extends RefCounted
class_name Abilities

## 能力定义表 + 触发分发。
##
## 共 46 个能力：
##   步卒 6 / 弓弩手 4 / 骑兵 4（14）
##   英杰 8
##   领袖 6
##   计策 16（秦 8 / 赵 8）
##   合计 44 张卡的 46 个能力位（秦赵各 23 个：10步卒? 见下）
##
## 触发时机（TIMING_*）：
##   ON_PLAY      打出时（单位进场 / 计策结算）
##   DYNAMIC      动态（每次读战力实时计算）
##   COUNTING     计数触发（己方回合开始检查）
##   PASSIVE      被动常驻
##   MATCH_START  整场对局开始（领袖）
##   ROUND_START  每局开始时（领袖）

const TIMING_ON_PLAY := "on_play"
const TIMING_DYNAMIC := "dynamic"
const TIMING_COUNTING := "counting"
const TIMING_PASSIVE := "passive"
const TIMING_MATCH_START := "match_start"
const TIMING_ROUND_START := "round_start"

## ability_id -> { timing, name, text, owner }（owner: 卡面所在阵营，用于断言覆盖）
## 动态能力不需要进入这张表的效果部分，但保留描述便于 UI 展示。
const DEFS := {
	# ---------------- 步卒 6 ----------------
	"inf_comrade": {
		"timing": TIMING_DYNAMIC, "name": "同袍",
		"text": "本卡每有 1 名左右相邻单位，战力 +1。",
	},
	"inf_formation": {
		"timing": TIMING_DYNAMIC, "name": "结阵",
		"text": "本行含本卡在内有 ≥3 个单位时，本卡战力 +2。",
	},
	"inf_valor": {
		"timing": TIMING_ON_PLAY, "name": "奋勇",
		"text": "打出前若本行落后于对方同行，本卡永久 +3。",
	},
	"inf_summon": {
		"timing": TIMING_ON_PLAY, "name": "征召",
		"text": "从牌库召唤 1 张同名卡到本行。",
	},
	"inf_deathwish": {
		"timing": TIMING_PASSIVE, "name": "死志",
		"text": "免疫战力减少，但不免疫摧毁。",
	},
	"inf_veteran": {
		"timing": TIMING_COUNTING, "name": "老兵",
		"text": "己方回合数满 3 时永久 +1（只触发一次，跨局重置，离场清零）。",
	},
	# ---------------- 弓弩手 4 ----------------
	"arc_volley": {
		"timing": TIMING_ON_PLAY, "name": "齐射",
		"text": "对方近战行所有单位 -1。",
	},
	"arc_precise": {
		"timing": TIMING_ON_PLAY, "name": "精准",
		"text": "对方全场最高战力的所有单位 -2。",
	},
	"arc_formation": {
		"timing": TIMING_DYNAMIC, "name": "弩阵",
		"text": "本行每有 1 名弓弩手（含本卡），本卡战力 +1。",
	},
	"arc_cover": {
		"timing": TIMING_ON_PLAY, "name": "掩护",
		"text": "己方近战行所有单位永久 +1。",
	},
	# ---------------- 骑兵 4 ----------------
	"cav_raid": {
		"timing": TIMING_ON_PLAY, "name": "突袭",
		"text": "限近战行打出：对方远程行所有单位 -1（远程行打出不触发）。",
	},
	"cav_ironride": {
		"timing": TIMING_DYNAMIC, "name": "铁骑",
		"text": "本行只有骑兵时本卡 +2（空行打出第一张也触发）。",
	},
	"cav_trample": {
		"timing": TIMING_ON_PLAY, "name": "践踏",
		"text": "限近战行打出且本行已有 ≥1 张其他骑兵：对方近战行 -1。",
	},
	"cav_charge": {
		"timing": TIMING_ON_PLAY, "name": "冲阵",
		"text": "对方全场最低战力的所有单位 -2。",
	},
	# ---------------- 英杰 8 ----------------
	"hero_baiqi": {
		"timing": TIMING_ON_PLAY, "name": "白起",
		"text": "摧毁对方战力最高的所有单位。",
	},
	"hero_wangjian": {
		"timing": TIMING_ON_PLAY, "name": "王翦",
		"text": "灭国：抽 1 张单位牌。",
	},
	"hero_simacuo": {
		"timing": TIMING_ON_PLAY, "name": "司马错",
		"text": "抽 1 张单位牌。",
	},
	"hero_chuliji": {
		"timing": TIMING_ON_PLAY, "name": "樗里疾",
		"text": "抽 1 张计策牌。",
	},
	"hero_limu": {
		"timing": TIMING_ON_PLAY, "name": "李牧",
		"text": "己方总战力 < 对方时，己方全场单位 +1（英杰不吃）。",
	},
	"hero_lianpo": {
		"timing": TIMING_ON_PLAY, "name": "廉颇",
		"text": "移除同行所有单位的减战力效果，恢复至卡面基础战力。",
	},
	"hero_zhaoshe": {
		"timing": TIMING_ON_PLAY, "name": "赵奢",
		"text": "本行落后时，对方同行所有单位 -2（受死志影响）。",
	},
	"hero_linxiangru": {
		"timing": TIMING_ON_PLAY, "name": "蔺相如",
		"text": "收回己方最低战力单位；该牌再打出时永久 +1（只触发一次）。",
	},
	# ---------------- 领袖 6 ----------------
	"leader_qinxiaogong": {
		"timing": TIMING_MATCH_START, "name": "秦孝公",
		"text": "开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_qinhuiwen": {
		"timing": TIMING_ROUND_START, "name": "秦惠文王",
		"text": "每局开始己方近战行 +1。",
	},
	"leader_qinzhaoxiang": {
		"timing": TIMING_MATCH_START, "name": "秦昭襄王",
		"text": "开局摧毁对方牌库随机 1 张单位牌。",
	},
	"leader_zhaowuling": {
		"timing": TIMING_MATCH_START, "name": "赵武灵王",
		"text": "开局从牌库检索 1 张骑兵牌加入手牌。",
	},
	"leader_zhaohuiwen": {
		"timing": TIMING_ROUND_START, "name": "赵惠文王",
		"text": "每局开始己方守军行 +1。",
	},
	"leader_zhaoxiaocheng": {
		"timing": TIMING_MATCH_START, "name": "赵孝成王",
		"text": "开局己方随机 1 张单位牌 +2。",
	},
	# ---------------- 计策 16（秦 8） ----------------
	"tac_yuanjiao": {
		"timing": TIMING_ON_PLAY, "name": "远交近攻",
		"text": "对方战力最高的所有单位 -2。",
	},
	"tac_lianheng": {
		"timing": TIMING_ON_PLAY, "name": "连横",
		"text": "对方战力最高的行所有单位 -1，己方抽 1 张。",
	},
	"tac_jungong": {
		"timing": TIMING_ON_PLAY, "name": "军功爵",
		"text": "己方全场单位 +1。",
	},
	"tac_zhengguoqu": {
		"timing": TIMING_ON_PLAY, "name": "郑国渠",
		"text": "己方抽 2 张。",
	},
	"tac_hangu": {
		"timing": TIMING_ON_PLAY, "name": "函谷关",
		"text": "清除己方守军行所有单位的减战力效果。",
	},
	"tac_ironeagle": {
		"timing": TIMING_ON_PLAY, "name": "铁鹰剑士",
		"text": "从牌库召唤 1 张战力最高的单位牌到守军行。",
	},
	"tac_fenzhou": {
		"timing": TIMING_ON_PLAY, "name": "焚舟破釜",
		"text": "弃 1 张手牌，己方全场 +2。",
	},
	"tac_qincrossbow": {
		"timing": TIMING_ON_PLAY, "name": "秦弩阵",
		"text": "对方近战行所有单位 -2。",
	},
	# ---------------- 计策 16（赵 8） ----------------
	"tac_hufu": {
		"timing": TIMING_ON_PLAY, "name": "胡服骑射",
		"text": "己方全场骑兵 +2。",
	},
	"tac_wanbi": {
		"timing": TIMING_ON_PLAY, "name": "完璧归赵",
		"text": "收回己方最低战力单位，己方抽 1 张。",
	},
	"tac_jiangxiang": {
		"timing": TIMING_ON_PLAY, "name": "将相和",
		"text": "己方全场单位 +1。",
	},
	"tac_yuyu": {
		"timing": TIMING_ON_PLAY, "name": "阏与之战",
		"text": "若己方总战力落后，对方战力最高的行所有单位 -2。",
	},
	"tac_jianbi": {
		"timing": TIMING_ON_PLAY, "name": "坚壁清野",
		"text": "清除己方守军行减益，己方守军行 +1。",
	},
	"tac_daijun": {
		"timing": TIMING_ON_PLAY, "name": "代郡铁骑",
		"text": "从牌库召唤 1 张骑兵牌到近战行。",
	},
	"tac_hezong": {
		"timing": TIMING_ON_PLAY, "name": "合纵",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_handan": {
		"timing": TIMING_ON_PLAY, "name": "邯郸之围",
		"text": "对方最低战力所有单位 -1；若己方守军行有单位，抽 1 张。",
	},

	# ================================================================
	#  七国扩展：齐 / 楚 / 燕 / 韩 / 魏
	# ----------------------------------------------------------------
	#  【设计原则】新国家的英杰 / 领袖 / 计策**不引入任何新的效果机制**，
	#  全部由既有的原子操作组合而成（复用秦赵已经验证过的 8 种英杰机制、
	#  7 种领袖机制、15 种计策机制）。这样做的理由：
	#    1. 秦赵的兵种分布已经被证明会带来平衡差异，再叠一层「新机制」，
	#       一旦失衡将无法归因；
	#    2. 已有 121 项回归全部继续适用；
	#    3. 国家差异由「机制组合 + 兵种分布 + 卡名」共同体现，足够。
	#  若日后要加真正的独占机制，请单独评估并补平衡测试。
	# ================================================================

	# ---------------- 英杰 20（齐楚燕韩魏 各 4） ----------------
	# 【第 20 阶段按设计稿重排】每张卡的文字必须与 EffectRunner 里的分支严格对应，
	# 否则玩家在卡面上看到的效果和实际打出来的不一致（历史上李牧/廉颇就是这样错的）。
	# 齐
	"hero_qi_sunbin": {
		"timing": TIMING_ON_PLAY, "name": "孙膑",
		"text": "围魏救赵：抽 1 张计策牌。",
	},
	"hero_qi_tianji": {
		"timing": TIMING_ON_PLAY, "name": "田忌",
		"text": "赛马：己方总战力落后时，己方骑兵 +2。",
	},
	"hero_qi_guanzhong": {
		"timing": TIMING_ON_PLAY, "name": "管仲",
		"text": "通货积财：抽 1 张计策牌。",
	},
	"hero_qi_kuangzhang": {
		"timing": TIMING_ON_PLAY, "name": "匡章",
		"text": "破函谷：己方场上单位数 ≥ 对方时，对方战力最高的所有单位 -2。",
	},
	# 楚
	"hero_chu_xiangyan": {
		"timing": TIMING_ON_PLAY, "name": "项燕",
		"text": "楚虽三户：对方战力最高的所有单位 −2。",
	},
	"hero_chu_quyuan": {
		"timing": TIMING_ON_PLAY, "name": "屈原",
		"text": "美政：抽 1 张计策牌，并清除己方守军行所有减益。",
	},
	"hero_chu_zhaoyang": {
		"timing": TIMING_ON_PLAY, "name": "昭阳",
		"text": "灭越之师：从牌库召唤 1 张牌到本行（优先同名卡，否则召唤战力最高者）。",
	},
	"hero_chu_zhuangqiao": {
		"timing": TIMING_ON_PLAY, "name": "庄蹻",
		"text": "入滇：己方总战力 < 对方时，己方全场单位 +1（英杰不吃）。",
	},
	# 燕
	"hero_yan_yueyi": {
		"timing": TIMING_ON_PLAY, "name": "乐毅",
		"text": "下齐七十城：抽 1 张单位牌。",
	},
	"hero_yan_jingke": {
		"timing": TIMING_ON_PLAY, "name": "荆轲",
		"text": "图穷匕见：对方战力最高的 1 个单位 −2（英杰免疫）。",
	},
	"hero_yan_juxin": {
		"timing": TIMING_ON_PLAY, "name": "剧辛",
		"text": "整军：从牌库召唤 1 张牌到本行（优先同名卡，否则召唤战力最高者）。",
	},
	"hero_yan_yuecheng": {
		"timing": TIMING_ON_PLAY, "name": "乐乘",
		"text": "乘胜：己方场上单位数 > 对方时，己方全场单位 +1（英杰不吃）。",
	},
	# 韩
	"hero_han_baoyuan": {
		"timing": TIMING_ON_PLAY, "name": "暴鸢",
		"text": "劲弩：对方战力最高的所有单位 -2。",
	},
	"hero_han_shenbuhai": {
		"timing": TIMING_ON_PLAY, "name": "申不害",
		"text": "术治：抽 1 张计策牌。",
	},
	"hero_han_feizi": {
		"timing": TIMING_ON_PLAY, "name": "韩非",
		"text": "法治：抽 1 张计策牌，并清除己方远程行所有减益。",
	},
	"hero_han_gongsunyan": {
		"timing": TIMING_ON_PLAY, "name": "公孙衍",
		"text": "合纵：收回己方最低战力单位；该牌再打出时永久 +1（只触发一次）。",
	},
	# 魏
	"hero_wei_wuqi": {
		"timing": TIMING_ON_PLAY, "name": "吴起",
		"text": "魏武卒：抽 1 张单位牌。",
	},
	"hero_wei_pangjuan": {
		"timing": TIMING_ON_PLAY, "name": "庞涓",
		"text": "围邯郸：本行落后时，对方同行所有单位 -2（受死志影响）。",
	},
	"hero_wei_xinlingjun": {
		"timing": TIMING_ON_PLAY, "name": "信陵君",
		"text": "窃符救赵：收回己方最低战力单位；该牌再打出时永久 +1（只触发一次）。",
	},
	"hero_wei_leyang": {
		"timing": TIMING_ON_PLAY, "name": "乐羊",
		"text": "攻中山：从牌库召唤 1 张战力最高的单位牌到近战行。",
	},

	# ---------------- 领袖 15（齐楚燕韩魏 各 3） ----------------
	# 齐
	"leader_qi_huan": {
		"timing": TIMING_MATCH_START, "name": "齐桓公",
		"text": "尊王攘夷：开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_qi_wei": {
		"timing": TIMING_ROUND_START, "name": "齐威王",
		"text": "一鸣惊人：每局开始己方远程行 +1。",
	},
	"leader_qi_xuan": {
		"timing": TIMING_MATCH_START, "name": "齐宣王",
		"text": "稷下先生：开局从牌库检索 1 张计策牌加入手牌。",
	},
	# 楚
	"leader_chu_zhuang": {
		"timing": TIMING_MATCH_START, "name": "楚庄王",
		"text": "三年不鸣：开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_chu_wei": {
		"timing": TIMING_ROUND_START, "name": "楚威王",
		"text": "带甲百万：每局开始己方近战行 +1。",
	},
	"leader_chu_huai": {
		"timing": TIMING_ROUND_START, "name": "楚怀王",
		"text": "张仪欺楚：每局开始己方守军行 +1。",
	},
	# 燕
	"leader_yan_zhao": {
		"timing": TIMING_MATCH_START, "name": "燕昭王",
		"text": "千金买骨：开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_yan_kuai": {
		"timing": TIMING_ROUND_START, "name": "燕王哙",
		"text": "苦寒之地：每局开始己方守军行 +1。",
	},
	"leader_yan_hui": {
		"timing": TIMING_MATCH_START, "name": "燕惠王",
		"text": "临阵易将：开局己方随机 1 张单位牌 +2。",
	},
	# 韩
	"leader_han_zhao": {
		"timing": TIMING_ROUND_START, "name": "韩昭侯",
		"text": "申子之术：每局开始己方远程行 +1。",
	},
	"leader_han_wen": {
		"timing": TIMING_MATCH_START, "name": "韩文侯",
		"text": "宜阳铁冶：开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_han_an": {
		"timing": TIMING_MATCH_START, "name": "韩王安",
		"text": "上党之祸：开局摧毁对方牌库随机 1 张单位牌。",
	},
	# 魏
	"leader_wei_wen": {
		"timing": TIMING_ROUND_START, "name": "魏文侯",
		"text": "李悝变法：每局开始己方近战行 +1。",
	},
	"leader_wei_wu": {
		"timing": TIMING_MATCH_START, "name": "魏武侯",
		"text": "招贤纳士：开局从牌库检索 1 张单位牌加入手牌。",
	},
	"leader_wei_hui": {
		"timing": TIMING_MATCH_START, "name": "魏惠王",
		"text": "逢泽之会：开局摧毁对方牌库随机 1 张单位牌。",
	},

	# ---------------- 计策 40（齐楚燕韩魏 各 8） ----------------
	# 齐
	"tac_qi_zunwang": {
		"timing": TIMING_ON_PLAY, "name": "尊王攘夷", "text": "己方全场单位 +1。",
	},
	"tac_qi_weiwei": {
		"timing": TIMING_ON_PLAY, "name": "围魏救赵", "text": "对方战力最高的所有单位 -2。",
	},
	"tac_qi_huoniu": {
		"timing": TIMING_ON_PLAY, "name": "火牛阵",
		"text": "对方最低战力所有单位 -1；若己方守军行有单位，抽 1 张。",
	},
	"tac_qi_jixia": {
		"timing": TIMING_ON_PLAY, "name": "稷下学宫", "text": "己方抽 2 张。",
	},
	"tac_qi_jimo": {
		"timing": TIMING_ON_PLAY, "name": "即墨守城",
		"text": "清除己方守军行减益，己方守军行 +1。",
	},
	"tac_qi_jiji": {
		"timing": TIMING_ON_PLAY, "name": "技击之术", "text": "弃 1 张手牌，己方全场 +2。",
	},
	"tac_qi_jiuhe": {
		"timing": TIMING_ON_PLAY, "name": "九合诸侯",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_qi_tianji": {
		"timing": TIMING_ON_PLAY, "name": "田忌赛马",
		"text": "对方战力最高的行所有单位 -1，己方抽 1 张。",
	},
	# 楚
	"tac_chu_wending": {
		"timing": TIMING_ON_PLAY, "name": "问鼎中原", "text": "对方战力最高的所有单位 -2。",
	},
	"tac_chu_bilu": {
		"timing": TIMING_ON_PLAY, "name": "筚路蓝缕", "text": "己方全场单位 +1。",
	},
	"tac_chu_yunmeng": {
		"timing": TIMING_ON_PLAY, "name": "云梦泽", "text": "己方抽 2 张。",
	},
	"tac_chu_fangcheng": {
		"timing": TIMING_ON_PLAY, "name": "方城为城",
		"text": "清除己方守军行减益，己方守军行 +1。",
	},
	"tac_chu_shenxi": {
		"timing": TIMING_ON_PLAY, "name": "申息之甲",
		"text": "从牌库召唤 1 张战力最高的单位牌到守军行。",
	},
	"tac_chu_chucai": {
		"timing": TIMING_ON_PLAY, "name": "楚材晋用",
		"text": "收回己方最低战力单位，己方抽 1 张。",
	},
	"tac_chu_baiyue": {
		"timing": TIMING_ON_PLAY, "name": "百越归附",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_chu_yanying": {
		"timing": TIMING_ON_PLAY, "name": "鄢郢血战",
		"text": "若己方总战力落后，对方战力最高的行所有单位 -2。",
	},
	# 燕
	"tac_yan_huangjin": {
		"timing": TIMING_ON_PLAY, "name": "黄金台", "text": "己方抽 2 张。",
	},
	"tac_yan_xiaqi": {
		"timing": TIMING_ON_PLAY, "name": "下齐七十城", "text": "对方战力最高的所有单位 -2。",
	},
	"tac_yan_kuhan": {
		"timing": TIMING_ON_PLAY, "name": "苦寒之地", "text": "己方全场单位 +1。",
	},
	"tac_yan_jingke": {
		"timing": TIMING_ON_PLAY, "name": "荆轲刺秦", "text": "对方近战行所有单位 -2。",
	},
	"tac_yan_liaodong": {
		"timing": TIMING_ON_PLAY, "name": "辽东坚守",
		"text": "清除己方守军行减益，己方守军行 +1。",
	},
	"tac_yan_zhaoxian": {
		"timing": TIMING_ON_PLAY, "name": "招贤纳士",
		"text": "收回己方最低战力单位，己方抽 1 张。",
	},
	"tac_yan_wugu": {
		"timing": TIMING_ON_PLAY, "name": "五国伐齐",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_yan_yishui": {
		"timing": TIMING_ON_PLAY, "name": "易水送别",
		"text": "对方最低战力所有单位 -1；若己方守军行有单位，抽 1 张。",
	},
	# 韩
	"tac_han_jinnu": {
		"timing": TIMING_ON_PLAY, "name": "劲弩之师", "text": "对方近战行所有单位 -2。",
	},
	"tac_han_yiyang": {
		"timing": TIMING_ON_PLAY, "name": "宜阳铁冶", "text": "己方全场单位 +1。",
	},
	"tac_han_shuzhi": {
		"timing": TIMING_ON_PLAY, "name": "术治之国", "text": "己方抽 2 张。",
	},
	"tac_han_shenzi": {
		"timing": TIMING_ON_PLAY, "name": "申子之教",
		"text": "清除己方守军行所有单位的减战力效果。",
	},
	"tac_han_hanwei": {
		"timing": TIMING_ON_PLAY, "name": "韩魏联军",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_han_xinzheng": {
		"timing": TIMING_ON_PLAY, "name": "新郑坚城",
		"text": "从牌库召唤 1 张战力最高的单位牌到守军行。",
	},
	"tac_han_nubing": {
		"timing": TIMING_ON_PLAY, "name": "弩兵齐发",
		"text": "对方战力最高的行所有单位 -1，己方抽 1 张。",
	},
	"tac_han_shangdang": {
		"timing": TIMING_ON_PLAY, "name": "上党之守",
		"text": "清除己方守军行减益，己方守军行 +1。",
	},
	# 魏
	"tac_wei_wuzu": {
		"timing": TIMING_ON_PLAY, "name": "武卒选练", "text": "己方全场单位 +1。",
	},
	"tac_wei_wuzuzhi": {
		"timing": TIMING_ON_PLAY, "name": "武卒之制", "text": "对方战力最高的所有单位 -2。",
	},
	"tac_wei_likui": {
		"timing": TIMING_ON_PLAY, "name": "李悝变法", "text": "己方抽 2 张。",
	},
	"tac_wei_qiefu": {
		"timing": TIMING_ON_PLAY, "name": "窃符救赵",
		"text": "收回己方最低战力单位，己方抽 1 张。",
	},
	"tac_wei_ximen": {
		"timing": TIMING_ON_PLAY, "name": "西门豹渠", "text": "弃 1 张手牌，己方全场 +2。",
	},
	"tac_wei_wuqilianbing": {
		"timing": TIMING_ON_PLAY, "name": "吴起练兵",
		"text": "若己方场上单位数 ≥ 对方，己方全场 +2。",
	},
	"tac_wei_daliang": {
		"timing": TIMING_ON_PLAY, "name": "大梁之战",
		"text": "若己方总战力落后，对方战力最高的行所有单位 -2。",
	},
	"tac_wei_henei": {
		"timing": TIMING_ON_PLAY, "name": "河内之甲",
		"text": "从牌库召唤 1 张骑兵牌到近战行。",
	},
}


## 动态能力：返回该卡的额外动态战力。
## owner 为持有方，row 为该卡当前所在行。
static func dynamic_bonus(state: GameState, owner: PlayerState, card: CardData, row: String) -> int:
	match card.ability_id:
		"inf_comrade":
			return _comrade_bonus(owner, card, row)
		"inf_formation":
			return 2 if owner.row_cards(row).size() >= 3 else 0
		"arc_formation":
			var n := 0
			for c in owner.row_cards(row):
				if c.unit_type == CardData.UNIT_ARCHER:
					n += 1
			return n
		"cav_ironride":
			var cards := owner.row_cards(row)
			if cards.is_empty():
				return 0
			for c in cards:
				if c.unit_type != CardData.UNIT_CAVALRY:
					return 0
			return 2
	return 0


## 同袍：每个左右相邻单位 +1（只看紧邻位置）。
static func _comrade_bonus(owner: PlayerState, card: CardData, row: String) -> int:
	var cards := owner.row_cards(row)
	var idx := cards.find(card)
	if idx < 0:
		return 0
	var bonus := 0
	if idx > 0:
		bonus += 1
	if idx < cards.size() - 1:
		bonus += 1
	return bonus


static func def(ability_id: String) -> Dictionary:
	return DEFS.get(ability_id, {})


static func ability_name(ability_id: String) -> String:
	var d := def(ability_id)
	if d.is_empty():
		return ""
	return str(d.get("name", ""))


static func ability_text(ability_id: String) -> String:
	var d := def(ability_id)
	if d.is_empty():
		return ""
	return str(d.get("text", ""))
