extends Control

## 《七雄策》应用根节点：只负责加载卡牌库与屏幕切换。
## 主菜单 → 阵营选择 / 牌库编辑 / 设置 → 对局。对局规则在 GameState。
##
## 联机（5D）流程：
##   主菜单 →「联机对战」→ LobbyScreen（建/加房）→ 连接成功
##       主机：阵营选择（主机先选）→ 广播所选阵营 → 进入对局
##       客户端：阵营选择界面只读等待 → 收主机广播 → 自动取另一阵营 → 进入对局

var db: CardDB
var _current: Control = null
## 联机流程的临时状态（连接建立后到对局开始之间有效）
var _net_seed: int = 0
var _net_my_faction: String = ""
var _net_opp_faction: String = ""
## 联机对局是否已启动（防止双方阵营确定后重复进入）
var _net_match_started: bool = false
## 测试用：注入一个独立的 NetworkManager 实例（同进程双实例隔离需要）。
## 为 null 时从场景树取 Autoload "NetworkManager"。
var net_override: Node = null


func _ready() -> void:
	UiKit.apply_theme(self)
	db = CardDB.new()
	for err in db.load_errors:
		push_warning("[CardDB] " + err)
	# 【首帧构造主菜单：不带断连】
	# _ready 只是「把主菜单建出来」，玩家此刻还没做过任何联机操作。
	# 若这里沿用 _show_menu()（含 disconnect_peer），在「连接先建立、Main 后构造」
	# 的时序下会把一个活连接直接掐掉 —— 这正是端到端联机测试一直失败的原因，
	# 也是产品上的脆弱点（Main 一旦被重建，联机就断）。故首帧只清临时状态、不断连。
	_reset_net_state(false)
	_play_music("menu")
	_swap(_make_main_menu())


## 取音频管理器（Autoload）。返回 null 表示音频不可用（不影响游戏进行）。
func _audio() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


## 切到某个背景音乐场景。找不到 AudioManager 时静默跳过。
func _play_music(scene: String) -> void:
	var am := _audio()
	if am != null:
		am.play_music(scene)


# ---------------- 屏幕切换 ----------------

func _swap(screen: Control) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = screen
	add_child(screen)


func _show_menu() -> void:
	# 【重要】回主菜单 = 玩家主动离开联机流程 → 这里才允许真正断开连接。
	# `_ready()` 首次进主菜单时不走这条路径（见 _ready），否则会把一个
	# 已经建立好的连接误杀（测试里「先建连、后构造 Main」就踩过这个坑）。
	_reset_net_state(true)
	# 主菜单 / 大厅 / 阵营选择 / 牌库编辑 / 设置都属于「主场景」，共用一首音乐
	_play_music("menu")
	_swap(_make_main_menu())


## 构造主菜单界面并接线。首次进主菜单（_ready）与后续返回主菜单共用。
func _make_main_menu() -> Control:
	var screen := MainMenuScreen.new()
	screen.start_game.connect(_show_faction_select)
	screen.open_lobby.connect(_show_lobby)
	screen.open_decks.connect(_show_deck_editor)
	screen.open_settings.connect(_show_settings)
	screen.quit_game.connect(_quit_game)
	return screen


func _show_faction_select() -> void:
	var screen := FactionSelectScreen.new()
	screen.setup(db)
	_attach_net(screen)
	screen.faction_chosen.connect(_start_match)
	screen.back.connect(_show_menu)
	_swap(screen)


func _show_deck_editor() -> void:
	var screen := DeckEditorScreen.new()
	screen.setup(db)
	screen.back.connect(_show_menu)
	_swap(screen)


func _show_settings() -> void:
	var screen := SettingsScreen.new()
	screen.back.connect(_show_menu)
	_swap(screen)


# ---------------- 联机（5D） ----------------

func _show_lobby() -> void:
	var screen := LobbyScreen.new()
	_attach_net(screen)
	screen.back.connect(_show_menu)
	screen.link_ready.connect(_show_net_faction_select)
	_swap(screen)


## 把本节点的 NetworkManager 注入到子界面。
## 只有真正用到网络的界面才声明 `net_override`，所以这里**先探测再赋值** ——
## 直接对一个未声明的属性赋值会在运行时抛错。
##
## 【为什么必须注入】Main 自己可能被注入了独立 NetworkManager（测试 / 多实例），
## 此时子界面若走 `_net()` 的兜底分支，会拿到场景树里的 Autoload —— 那是另一个
## 完全无关、甚至未连接的实例，表现为界面收不到任何网络信号。
func _attach_net(screen: Node) -> void:
	if net_override == null:
		return
	if "net_override" in screen:
		screen.net_override = net_override


## 连接建立后进入阵营选择。主机可选、客户端只读。
func _show_net_faction_select() -> void:
	var nm := _net()
	if nm == null:
		_show_menu()
		return
	_net_seed = 0
	_net_my_faction = ""
	_net_opp_faction = ""
	_net_match_started = false

	# 【为什么种子要在这里先生成】阵营选择界面在按下阵营卡时会**立即**把
	# 「所选阵营 + 种子」广播给客户端，客户端收到后立刻开局。如果种子等到
	# Main 收到 faction_chosen 才生成，广播出去的就是 0，客户端会用一个
	# 空种子开局，与主机牌序不一致（表现为客户端状态错乱/卡住）。
	if nm.is_host():
		_net_seed = _make_seed()

	var screen := FactionSelectScreen.new()
	screen.setup(db)
	_attach_net(screen)
	screen.net_mode = true
	screen.net_is_host = nm.is_host()
	screen.net_my_index = nm.local_player
	screen.net_seed = _net_seed

	screen.faction_chosen.connect(_on_net_faction_chosen)
	screen.faction_chosen_seed.connect(_on_net_faction_chosen_seed)
	screen.back.connect(_show_menu)
	_swap(screen)
	# 注意：阵营选择界面在按下阵营卡时**自己**广播（见 FactionSelectScreen），
	# Main 这里不再重复广播，否则客户端会收到两条。
	# 客户端此刻只读等待，等主机广播后由 _on_net_faction_chosen 起局。


## 某一方确定了阵营（本方阵营 + 对手阵营 + 种子，三者已在同一条信号里就位）。
##
## 【七国改动】原先对手阵营是「本方阵营的反面」，客户端可以自行推导；
## 七国之下不再唯一，改由主机在广播里明确指派，因此这里**不再做任何推导**，
## 直接用 `faction_chosen_seed`（先于起局信号发射）已经填好的值。
## 种子也必须在这里就位 —— `setup_network` 会用到它，晚一步双方牌序就不一致。
func _on_net_faction_chosen_seed(faction: String, opp_faction: String, seed_value: int) -> void:
	_net_seed = seed_value
	_net_my_faction = faction
	_net_opp_faction = opp_faction


func _on_net_faction_chosen(_faction: String) -> void:
	if _net_match_started:
		return
	var nm := _net()
	if nm == null:
		_show_menu()
		return
	# 主机与客户端在这里是同一条路径：阵营映射已就位，直接起局。
	#   主机：自己开好局，开局后 push_initial_state 会把权威状态广播给客户端
	#   客户端：种子已由 _on_net_faction_chosen_seed 从广播里取到
	_start_net_match()


func _start_net_match() -> void:
	_net_match_started = true
	# 进入对局：一记大锣交代「要开打了」，再切战斗音乐
	UiKit.sfx("gong")
	_play_music("battle")
	var nm := _net()
	var my_index := 0
	var opp_index := 1
	if nm != null:
		my_index = nm.local_player
		opp_index = nm.remote_player

	var screen := MatchScreen.new()
	# 【必须转发 net_override】Main 被注入了独立 NetworkManager 时（测试/多实例），
	# 它新建的子界面必须用**同一个**实例，否则 _net() 会退回场景树里的 Autoload，
	# 连到另一个完全无关（甚至未连接）的 NetworkManager 上 —— 表现为界面永远收不到
	# 网络信号、联机测试全红，但生产里因为只有一个 Autoload 而看不出来。
	_attach_net(screen)
	screen.setup_network(db, _net_my_faction, my_index, opp_index, _net_opp_faction, _net_seed)
	screen.exit_to_menu.connect(_show_menu)
	_swap(screen)

	# 主机：开局完成后立刻把初始状态广播给客户端，客户端据此同步
	if nm != null and nm.is_host():
		screen.push_initial_state()


## 生成对局种子（非 0，保证可复现且双方一致）。
func _make_seed() -> int:
	var t := Time.get_unix_time_from_system()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t) ^ (randi() & 0xffff)
	return int(rng.randi() & 0x7fffffff) + 1


## 清理联机临时状态；`kill_connection` 为真时**同时断开连接**。
##
## 【为什么需要这个开关】「回到主菜单」有两种语义，必须区分：
##   1. 玩家主动离开联机流程（大厅返回 / 对局中途退出 / 阵营选择返回）
##      → kill_connection = true，必须断连，否则残留 peer 会污染后续单机对局。
##   2. Main 首帧构造主菜单（`_ready`）
##      → kill_connection = false，此时玩家还没做过任何联机操作；
##        若无条件断连，会误杀「连接先建立、Main 后构造」时序下活着的连接。
##        （端到端联机测试长期失败的真凶；产品上 Main 被重建也会断网。）
##
## 【为什么断开动作放在这里】大厅的 `_exit_tree()` 不能断连（那时双方正要
## 进阵营选择，断了就双卡「等待对手」），所以统一的收尾点必须集中在「回主菜单」。
func _reset_net_state(kill_connection: bool) -> void:
	if kill_connection:
		var nm := _net()
		if nm != null and nm.is_active():
			nm.disconnect_peer()
	_net_seed = 0
	_net_my_faction = ""
	_net_opp_faction = ""
	_net_match_started = false


func _net() -> Node:
	if net_override != null:
		return net_override
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("NetworkManager")


# ---------------- 单机对局 ----------------

func _start_match(faction: String) -> void:
	_play_music("battle")
	var screen := MatchScreen.new()
	screen.setup(db, faction)
	screen.exit_to_menu.connect(_show_menu)
	_swap(screen)


func _quit_game() -> void:
	get_tree().quit()
