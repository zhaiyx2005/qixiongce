extends Node

## 音频系统：背景音乐 ＋ 音效 ＋ 音量控制。
##
## 结构：本节点是 Autoload 单例（在 project.godot 里注册），随游戏启动就常驻，
## 因此切屏（主菜单 ↔ 对局 ↔ 设置）不会中断音乐。
##
## 三条音频总线（在 `_ready` 里用代码创建，避免手写 .tres 音频总线布局文件）：
##   Master ─┬─ Music   （背景音乐，2 个播放器轮换交叉淡化）
##           └─ Sfx     （音效，8 个播放器轮换复用）
##
## 音量用 `AudioServer.set_bus_volume_db()` 设置，但对外一律用 **0.0 ~ 1.0 的线性值**，
## 内部转成分贝：`db = linear_to_db(v)`。线性值更符合玩家直觉（滑块拉一半 ≈ 听感一半音量）。
## 全部静音时直接把总线 mute 掉，避免 linear_to_db(0) = -inf 参与运算。
##
## 【素材为本项目自行合成】`assets/music/`（2 首 BGM）与 `assets/sfx/`（12 个音效）
## 全部由程序合成 —— 四种音色：编钟（金属非谐泛音）、古筝（拨弦谐波衰减）、
## 战鼓（音高下滑 + 鼓槌噪声）、埙（气声 + 颤音）。合成脚本见 `tools/audio/`。

signal volume_changed(bus_name: String, linear: float)

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "Sfx"

## 两首背景音乐的资产路径。
##
## 【为什么是 .ogg】Godot 4 可解码的压缩格式只有 OGG Vorbis / MP3。
## 两首曲子都是 55 / 44 秒的循环曲，用 OGG 压到 0.3~0.5 MB（未压缩 WAV 会是 9 MB+）。
const MUSIC_MENU := "res://assets/music/menu.ogg"
const MUSIC_BATTLE := "res://assets/music/battle.ogg"

## ---------------- 音效 ----------------

## 短名 → 文件。调用方只写 `UiKit.sfx("click")`，路径细节留在本模块里。
##
## 【为什么音效用 WAV 而不是 OGG】极短音频（0.05~2 秒）经 Vorbis 编码会带上
## 前置静音与预回声，起音点会「糊」；WAV PCM16 单声道每个不到 200 KB，
## 合计 0.85 MB，是短音效的正确取舍。
const SFX_DIR := "res://assets/sfx/"
const SFX_FILES := {
	"click": "ui_click.wav",           # 按钮点击
	"hover": "ui_hover.wav",           # 鼠标悬停（很轻，只在少数界面用）
	"card_place": "card_place.wav",    # 单位牌落到战场
	"card_draw": "card_draw.wav",      # 抽牌
	"tactic": "tactic.wav",            # 计策释放
	"gong": "gong.wav",                # 高光时刻（将军 / 关键抉择）
	"destroy": "destroy.wav",          # 单位被摧毁
	"round_start": "round_start.wav",  # 一局开始
	"round_end": "round_end.wav",      # 一局结束
	"win": "win.wav",                  # 对局胜利
	"lose": "lose.wav",                # 对局失败
	"error": "error.wav",              # 操作被拒
}

## 音效播放器池大小。音效都很短，8 个足够应付「连点 + 同时触发的界面音」。
## 池满时覆盖最早启动的那个 —— 宁可掐掉一个旧音效，也不要静默吞掉新音效。
const SFX_PLAYERS := 8

## 场景名（给 play_music 用，避免调用方到处写资源路径）
const SCENE_MENU := "menu"
const SCENE_BATTLE := "battle"

## 淡入淡出时长（秒）。0 表示直接切。
const FADE_TIME := 0.8

## 音量配置存这里，与卡组同一套用户目录
const CONFIG_PATH := "user://settings.cfg"

var _players: Array[AudioStreamPlayer] = []
## 当前正在播放的场景名
var _current_scene: String = ""
## 缓存的音频流（避免每次切歌都重新 load）
var _streams: Dictionary = {}
## 线性音量
var _volumes: Dictionary = {}
## 静音开关（只作用于音乐，音效同理）
var _muted: Dictionary = {}

## 淡入淡出用的补间（同一时刻只允许一个）
var _fade: Tween = null
var _fade_player: AudioStreamPlayer = null

## 音效播放器池 + 轮换游标
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor := 0
## 音效流缓存：短名 → AudioStream（值为 null 表示已确认缺失，避免反复探测磁盘）
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_load_settings()
	# 两个播放器，用于交叉淡化：一个在放，一个在淡入
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUSIC
		p.name = "MusicPlayer%d" % i
		add_child(p)
		_players.append(p)
	# 音效池：多个播放器轮换，同一音效连续触发时不会互相打断（而是叠加）
	for i in SFX_PLAYERS:
		var s := AudioStreamPlayer.new()
		s.bus = BUS_SFX
		s.name = "SfxPlayer%d" % i
		add_child(s)
		_sfx_players.append(s)
	_apply_all_volumes()


# ---------------- 总线 ----------------

## 创建 Music / Sfx 两条子总线。已存在则跳过（重复调用安全）。
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_MASTER)


# ---------------- 音乐 ----------------

## 播放某个场景的背景音乐。
##
## 【为什么带 scene 名而不是直接传路径】调用方（Main / MatchScreen）只需要表达
## 「我要主菜单音乐」或「我要对战音乐」，路径细节留在本模块里。以后换素材不用改调用方。
## 重复请求同一首不会重头播（避免每次回主菜单都从头开始）。
func play_music(scene: String) -> void:
	if scene == _current_scene and _is_playing():
		return
	var path := _path_for(scene)
	if path.is_empty():
		return
	var stream := _load_stream(path)
	if stream == null:
		push_warning("[AudioManager] 无法加载音乐：%s" % path)
		return

	_current_scene = scene

	# 循环播放：AudioStream 的 loop 标志可以直接设（OggVorbis 支持）
	if stream is AudioStream:
		stream.set("loop", true)

	# 交叉淡化：旧播放器淡出，空闲播放器淡入
	var outgoing := _fade_player
	var incoming := _pick_idle_player(outgoing)
	if incoming == null:
		incoming = _players[0]

	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()

	_fade_player = incoming
	_start_fade(incoming, outgoing)


func stop_music() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade_player = null
	for p in _players:
		p.stop()
	_current_scene = ""


func _path_for(scene: String) -> String:
	match scene:
		SCENE_MENU:
			return MUSIC_MENU
		SCENE_BATTLE:
			return MUSIC_BATTLE
	return ""


func _load_stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		_streams[path] = null
		return null
	var s := load(path)
	_streams[path] = s
	return s


func _is_playing() -> bool:
	for p in _players:
		if p.playing:
			return true
	return false


## 挑一个「不是当前正在淡入的那个」播放器。
func _pick_idle_player(exclude: AudioStreamPlayer) -> AudioStreamPlayer:
	for p in _players:
		if p != exclude:
			return p
	return null


## 把 incoming 从 -60dB 拉到目标音量，同时把 outgoing 拉到 -60dB 并停掉。
func _start_fade(incoming: AudioStreamPlayer, outgoing: AudioStreamPlayer) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()

	var target_db := _db_for(BUS_MUSIC)
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(incoming, "volume_db", target_db, FADE_TIME)
	if outgoing != null and outgoing != incoming and outgoing.playing:
		_fade.tween_property(outgoing, "volume_db", -60.0, FADE_TIME)
		_fade.chain().tween_callback(outgoing.stop)


# ---------------- 音效 ----------------

## 播放音效。`name` 用 `SFX_FILES` 里的短名（如 "click" / "card_place"）。
##
## 返回是否成功播放 —— 素材缺失时返回 **false 并静默降级**（只警告一次），
## 这样即使音效资源被删，界面也不会因为少了音效就报错或崩掉。
##
## `pitch_variation`（建议 0.0 ~ 0.15）给播放加入轻微随机音高，
## 让连续点击 / 连续落牌听起来不呆板；结算音这类要稳定，保持默认 0。
## `base_pitch` 是固定的音高偏移，用来**区分同一音效的不同来源** ——
## 例如对手落牌用 0.9（更沉），一听就知道不是自己出的牌。
func play_sfx(name: String, pitch_variation: float = 0.0, base_pitch: float = 1.0) -> bool:
	var stream := _load_sfx(name)
	if stream == null:
		return false
	var player := _pick_sfx_player()
	if player == null:
		return false
	player.stream = stream
	var jitter := 1.0 if pitch_variation <= 0.0 \
		else 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.pitch_scale = base_pitch * jitter
	player.play()
	return true


## 停掉所有正在播放的音效（离开对局 / 结算清理时用）。
func stop_all_sfx() -> void:
	for p in _sfx_players:
		p.stop()


## 某个短名是否可用（测试与设置界面用来判断要不要提示「素材缺失」）。
func has_sfx(name: String) -> bool:
	return _load_sfx(name) != null


func _load_sfx(name: String) -> AudioStream:
	if _sfx_cache.has(name):
		return _sfx_cache[name]
	var file: String = str(SFX_FILES.get(name, ""))
	if file.is_empty():
		_sfx_cache[name] = null
		push_warning("[AudioManager] 未登记的音效名：%s" % name)
		return null
	var path := SFX_DIR + file
	if not ResourceLoader.exists(path):
		_sfx_cache[name] = null
		push_warning("[AudioManager] 音效素材缺失：%s" % path)
		return null
	var s := load(path) as AudioStream
	_sfx_cache[name] = s
	return s


## 挑一个播放器：优先空闲的；全在播则轮换覆盖最早启动的那个。
## 宁可掐掉一个旧音效，也不静默吞掉新音效 —— 玩家的操作反馈必须响。
func _pick_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for p in _sfx_players:
		if not p.playing:
			return p
	var p := _sfx_players[_sfx_cursor % _sfx_players.size()]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return p


# ---------------- 音量 ----------------

## 取某条总线的线性音量（0.0 ~ 1.0）。
func get_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 1.0))


## 取某条总线的分贝值（已考虑静音）。
func _db_for(bus_name: String) -> float:
	if is_muted(bus_name):
		return -80.0
	var v := get_volume(bus_name)
	if v <= 0.001:
		return -80.0
	return linear_to_db(v)


func is_muted(bus_name: String) -> bool:
	return bool(_muted.get(bus_name, false))


func set_volume(bus_name: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	_volumes[bus_name] = linear
	_apply_volume(bus_name)
	volume_changed.emit(bus_name, linear)
	_save_settings()


func set_muted(bus_name: String, muted: bool) -> void:
	_muted[bus_name] = muted
	_apply_volume(bus_name)
	volume_changed.emit(bus_name, get_volume(bus_name))
	_save_settings()


func _apply_volume(bus_name: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var muted := is_muted(bus_name)
	AudioServer.set_bus_mute(idx, muted)
	AudioServer.set_bus_volume_db(idx, _db_for(bus_name) if not muted else 0.0)
	# 音乐总线的音量变化要同步到正在播放的播放器（播放器直接读 bus 音量，
	# 但淡入淡出用的是 volume_db，这里保持一致以免被补间覆盖）
	if bus_name == BUS_MUSIC and _fade_player != null and _fade_player.playing:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_fade_player.volume_db = _db_for(BUS_MUSIC)


func _apply_all_volumes() -> void:
	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX]:
		_apply_volume(bus_name)


# ---------------- 持久化 ----------------

func _load_settings() -> void:
	_volumes[BUS_MASTER] = 1.0
	_volumes[BUS_MUSIC] = 0.7
	_volumes[BUS_SFX] = 0.8
	_muted[BUS_MASTER] = false
	_muted[BUS_MUSIC] = false
	_muted[BUS_SFX] = false

	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX]:
		_volumes[bus_name] = clampf(float(cfg.get_value("volume", bus_name, _volumes[bus_name])), 0.0, 1.0)
		_muted[bus_name] = bool(cfg.get_value("mute", bus_name, false))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX]:
		cfg.set_value("volume", bus_name, _volumes.get(bus_name, 1.0))
		cfg.set_value("mute", bus_name, _muted.get(bus_name, false))
	cfg.save(CONFIG_PATH)
