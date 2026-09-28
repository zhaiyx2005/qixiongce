extends Node

## 网络层（5B）：P2P 局域网对战。
##
## 架构：**主机权威（Host-Authoritative）**
##   - 主机（host）跑唯一一份 GameState，是唯一的规则裁判。
##   - 客户端（client）只发指令、不跑规则；收到主机广播的完整状态后覆盖本地。
##   - 主机先在本地 execute_command 校验并执行，成功才广播新状态；
##     失败则只给发起方回一条中文原因，状态不变。
##
## 同步策略：**全量状态同步**（状态 = GameState.serialize() 的 Dictionary）。
##   本作状态量很小（双方各 ~29 张牌），全量比增量简单且不会有一致性漂移。
##
## 玩家座位：主机固定 player 0，客户端固定 player 1。
##
## 【为什么用 rpc_id 而不是 rpc】
##   Godot 4 的 @rpc 默认会广播给所有对端。但「主机回传拒绝原因」只需要
##   发给发起方，「广播状态」需要发给其余所有人。这里统一用 rpc_id() 精确投递，
##   并在 @rpc 注解里声明 call_remote，避免本机重复触发。

signal connected                            # 连接建立
signal disconnected                         # 连接断开（含对手主动断开）
signal connection_failed(reason: String)    # 连接失败
signal rejected(reason: String)             # 主机回传的「操作无效」中文原因
signal command_received(cmd: Dictionary)    # 主机侧：收到客户端指令
signal state_received(state: Dictionary)    # 客户端侧：收到主机广播的完整状态
## 客户端侧：收到主机下发的「双方阵营」（七国联机）。
## 【为什么要两个阵营】两国时代「客户端 = 主机的反面」是唯一解；
## 七国之下同一件事有 6 种可能，客户端无法自行推导，必须由主机在广播里明确指定。
signal faction_choice_received(host_faction: String, client_faction: String, seed_value: int)
## 主机侧：客户端请求重发权威状态（客户端界面就绪后主动要一次）
signal state_request_received

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 2
## 客户端在 GameState.players 里的固定下标（主机固定 0）
const CLIENT_INDEX := 1

enum Role { NONE, HOST, CLIENT }

var role: int = Role.NONE
var peer: ENetMultiplayerPeer = null
## 本方在 GameState.players 里的下标：主机 0，客户端 1
var local_player: int = 0
## 远端玩家下标
var remote_player: int = 1

## 指令发送序号（5E 乱序/重复包处理）
var _send_seq: int = 0
## 已收到的远端指令最大序号（重复包丢弃）
var _last_recv_seq: int = 0

var is_connected_now: bool = false

## 本实例使用的 MultiplayerAPI。
##
## 【为什么需要显式持有】
##   默认情况下 `multiplayer` 取得的是节点所属 SceneTree 的**共享** MultiplayerAPI。
##   生产环境里 NetworkManager 是唯一的 Autoload，共享没问题；
##   但回归测试需要在同一进程里同时跑「主机 + 客户端」两个实例，共享会导致
##   后设置的 peer 覆盖前一个（客户端 create_client 覆盖掉主机的 create_server）。
##   调用 `use_isolated_multiplayer()` 可为该实例分配独立 API，测试与生产互不干扰。
var mp_api: MultiplayerAPI = null


## 为本实例创建独立的 MultiplayerAPI（仅测试需要；生产环境不调用）。
##
## Godot 4 的 SceneTree 按节点路径分配 MultiplayerAPI，默认所有节点共用树根那个。
## 这里用 `SceneTree.set_multiplayer(api, path)` 把本节点路径单独绑到一个新 API 上，
## 从而与同进程内的另一个 NetworkManager 实例互不干扰。
func use_isolated_multiplayer() -> void:
	if mp_api != null:
		return
	var tree := get_tree()
	if tree == null:
		push_warning("[NetworkManager] use_isolated_multiplayer 需要在已进入场景树后调用。")
		return
	mp_api = MultiplayerAPI.create_default_interface()
	tree.set_multiplayer(mp_api, get_path())


## 取当前应使用的 MultiplayerAPI（隔离优先，否则用节点默认的）。
func _api() -> MultiplayerAPI:
	if mp_api != null:
		return mp_api
	return get_tree().get_multiplayer() if get_tree() != null else multiplayer


# ---------------- 连接管理 ----------------

## 创建房间（成为主机）。成功返回 true（端口可用即算成功，还没等到客户端接入）。
func host_game(port: int = DEFAULT_PORT) -> bool:
	_disconnect_internal()

	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_warning("[NetworkManager] 创建房间失败：%s" % error_string(err))
		connection_failed.emit("无法创建房间（端口 %d 可能被占用）。" % port)
		return false

	peer = p
	_api().multiplayer_peer = peer
	role = Role.HOST
	local_player = 0
	remote_player = CLIENT_INDEX
	_send_seq = 0
	_last_recv_seq = 0
	_connect_signals()
	return true


## 加入房间（成为客户端）。返回 true 只代表「已开始尝试连接」，
## 真正连上会触发 connected 信号，失败触发 connection_failed。
func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	_disconnect_internal()

	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		push_warning("[NetworkManager] 连接失败：%s" % error_string(err))
		connection_failed.emit("无法连接到 %s:%d。" % [ip, port])
		return false

	peer = p
	_api().multiplayer_peer = peer
	role = Role.CLIENT
	local_player = CLIENT_INDEX
	remote_player = 0
	_send_seq = 0
	_last_recv_seq = 0
	_connect_signals()
	return true


## 断开连接（回到单机）。
func disconnect_peer() -> void:
	_disconnect_internal()


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_active() -> bool:
	return role != Role.NONE


# ---------------- 发送 ----------------

## 客户端专用：把本机操作提交给主机裁决。
## 主机**不要**调用这个 —— 主机本地操作由 MatchScreen 直接 execute_command 并广播状态。
func send_command(cmd: Command) -> void:
	if cmd == null or role != Role.CLIENT:
		return
	_send_seq += 1
	cmd.seq = _send_seq
	_rpc_id(1, "_net_command", cmd.to_dict())


## 广播完整状态（仅主机调用）。
func send_state(state: Dictionary) -> void:
	if role != Role.HOST:
		return
	for id in _api().get_peers():
		_rpc_id(id, "_net_state", state)


## 主机在校验失败时，只回传一条中文原因给发起方（状态不变）。
func send_reject(reason: String) -> void:
	if role != Role.HOST:
		return
	for id in _api().get_peers():
		_rpc_id(id, "_net_reject", reason)


## 主机：广播「双方阵营 + 种子」（七国联机）。
## 客户端不能自己推导对手阵营（七国下不唯一），所以这里一次把两个都发过去。
## seed_value 一并广播，保证双方用同一种子开局（牌序一致）。
##
## 【为什么打包成 Dictionary】`Node._rpc_id(peer, method, ...)` 最多只接受
## 4 个实参（peer + method + 2 个 payload）。这里要送 3 个值，只能打包成一个
## 字典传 —— 与 `_net_command` 送 `Command.to_dict()` 是同一个理由。
func send_faction_choice(host_faction: String, client_faction: String, seed_value: int = 0) -> void:
	if role != Role.HOST:
		return
	var payload := {
		"host": host_faction, "client": client_faction, "seed": seed_value,
	}
	for id in _api().get_peers():
		_rpc_id(id, "_net_faction", payload)


## 主机：把收到的远端指令字典交给裁决者执行并广播结果。
## 【为什么放在这里而不是 MatchScreen】
##   这套「解包 -> execute_command -> 成功广播状态 / 失败回传原因」是最小同步协议，
##   属于网络层职责；MatchScreen 只需要连 command_received 做界面刷新。
##   adjudicate() 让「真实 RPC 路径」和「测试里手工喂包」走完全相同的代码，
##   避免测试覆盖不到的协议分支。
##
## state 必须是一个 GameState 实例；executor 是它的 execute_command 方法。
func adjudicate(data: Dictionary, state: GameState) -> CommandResult:
	if role != Role.HOST or state == null:
		return CommandResult.fail("非主机无法裁决指令。")
	var cmd := Command.from_dict(data)
	var result := state.execute_command(cmd)
	if result.ok:
		send_state(state.serialize())
	else:
		send_reject(result.reason)
	return result


## 客户端：请求主机重发一份权威状态。
##
## 【为什么需要】开机时序上，主机可能在客户端 MatchScreen 还没建好、
## 还没连上 state_received 信号之前就把初始状态发出去了（尤其主机选完阵营
## 立刻开局的情况）。这一帧的广播会丢，客户端就永远停在「等待同步」。
## 客户端构造好界面后主动要一次，即可自愈。
func request_state() -> void:
	if role != Role.CLIENT:
		return
	_rpc_id(1, "_net_request_state", null)


# ---------------- 接收（@rpc 回调） ----------------

@rpc("any_peer", "call_remote", "reliable")
func _net_request_state() -> void:
	if role != Role.HOST:
		return
	state_request_received.emit()


@rpc("any_peer", "call_remote", "reliable")
func _net_command(data: Dictionary) -> void:
	if role != Role.HOST:
		return
	var seq := int(data.get("seq", 0))
	if seq != 0 and seq <= _last_recv_seq:
		return   # 重复 / 乱序包，丢弃
	_last_recv_seq = seq
	command_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _net_state(data: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	state_received.emit(data)


@rpc("authority", "call_remote", "reliable")
func _net_reject(reason: String) -> void:
	if role != Role.CLIENT:
		return
	rejected.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _net_faction(payload: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	faction_choice_received.emit(
		str(payload.get("host", "")),
		str(payload.get("client", "")),
		int(payload.get("seed", 0)))


# ---------------- 内部 ----------------

func _connect_signals() -> void:
	var api := _api()
	if not api.peer_connected.is_connected(_on_peer_connected):
		api.peer_connected.connect(_on_peer_connected)
	if not api.peer_disconnected.is_connected(_on_peer_disconnected):
		api.peer_disconnected.connect(_on_peer_disconnected)
	if not api.connected_to_server.is_connected(_on_connected_to_server):
		api.connected_to_server.connect(_on_connected_to_server)
	if not api.connection_failed.is_connected(_on_connection_failed):
		api.connection_failed.connect(_on_connection_failed)
	if not api.server_disconnected.is_connected(_on_server_disconnected):
		api.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(_id: int) -> void:
	if role != Role.HOST:
		return
	is_connected_now = true
	connected.emit()


func _on_peer_disconnected(_id: int) -> void:
	is_connected_now = false
	if role != Role.NONE:
		disconnected.emit()


func _on_connected_to_server() -> void:
	is_connected_now = true
	connected.emit()


func _on_connection_failed() -> void:
	is_connected_now = false
	connection_failed.emit("连接失败，请检查 IP 与端口，以及双方是否在同一局域网。")


func _on_server_disconnected() -> void:
	is_connected_now = false
	if role != Role.NONE:
		disconnected.emit()


func _disconnect_internal() -> void:
	# 断开前先把信号解绑，避免 close() 触发的回调再发 disconnected 造成重入
	var api := _api()
	if api != null:
		if api.peer_connected.is_connected(_on_peer_connected):
			api.peer_connected.disconnect(_on_peer_connected)
		if api.peer_disconnected.is_connected(_on_peer_disconnected):
			api.peer_disconnected.disconnect(_on_peer_disconnected)
		if api.connected_to_server.is_connected(_on_connected_to_server):
			api.connected_to_server.disconnect(_on_connected_to_server)
		if api.connection_failed.is_connected(_on_connection_failed):
			api.connection_failed.disconnect(_on_connection_failed)
		if api.server_disconnected.is_connected(_on_server_disconnected):
			api.server_disconnected.disconnect(_on_server_disconnected)

	if peer != null:
		peer.close()
		peer = null
	if api != null:
		api.multiplayer_peer = null

	role = Role.NONE
	is_connected_now = false


## 精确投递一条 RPC。
##
## 【为什么用 self.rpc_id 而不是 api.rpc_id】
##   `rpc_id()` 是 **Node** 的方法，不是 MultiplayerAPI 的方法 —— MultiplayerAPI
##   （SceneMultiplayer）只提供 `send_bytes` 之类底层接口，没有 rpc_id。
##   Node.rpc_id 会通过「该节点路径所绑定的 MultiplayerAPI」发送，
##   所以只要 use_isolated_multiplayer() 已经把本节点路径绑到独立 API 上，
##   这里调 self.rpc_id 就自然走独立通道，无需手动传 api。
## 【参数约定】payload 传 null 表示「该 RPC 不带参数」（如 _net_request_state），
## 此时走 rpc_id(id, method) 两参形式；Godot 会按目标方法的签名校验参数个数，
## 多传一个 null 会报参数数量不匹配。
func _rpc_id(id: int, method: String, payload: Variant, extra: Variant = null) -> void:
	if peer == null:
		return
	if payload == null:
		rpc_id(id, method)
	elif extra == null:
		rpc_id(id, method, payload)
	else:
		rpc_id(id, method, payload, extra)
