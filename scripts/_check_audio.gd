extends SceneTree

## 音频系统回归检查。
##
## 【为什么值得单独立一个】本项目两首 BGM 与 12 个音效**全部是程序合成的资产**
## （合成脚本见 `tools/audio/`）。素材被重新生成、改名或删掉时，代码里的路径常量
## 不会自动跟着变 —— 那会变成「玩起来没声音但不报错」的静默故障。
## 这个套件就是那道防线：素材、总线、播放器池、降级行为四块一起管。
##
## 【注意】`AudioManager` 是 Autoload，`--script` 模式下依然会加载，
## 所以直接从 root 取实例即可。

## 音乐时长期望区间（秒）；超出说明素材被换掉或生成脚本出了偏差
const MUSIC_EXPECT := {
	"menu": [40.0, 75.0],
	"battle": [35.0, 60.0],
}
const SFX_MIN_LEN := 0.03
const SFX_MAX_LEN := 3.0
## 应有的音效短名数量
const SFX_COUNT := 12

var _pass := 0
var _fail := 0


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
	print("\n===== 音频系统检查 =====")

	var am: Node = root.get_node_or_null("AudioManager")
	if am == null:
		_ok(false, "AudioManager Autoload 在位")
		_summary()
		return
	_ok(true, "AudioManager Autoload 在位")
	await process_frame

	_check_buses(am)
	_check_music(am)
	_check_sfx(am)
	await _check_playback(am)
	_check_volume(am)

	_summary()


func _summary() -> void:
	print("\n===== %d 通过 / %d 失败 =====\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ---------------- A 总线 ----------------

func _check_buses(_am: Node) -> void:
	print("\n[A] 三条音频总线")
	for bus_name in ["Master", "Music", "Sfx"]:
		_ok(AudioServer.get_bus_index(bus_name) != -1, "总线 %s 存在" % bus_name)


# ---------------- B 音乐 ----------------

func _check_music(am: Node) -> void:
	print("\n[B] 背景音乐素材")
	for scene in MUSIC_EXPECT.keys():
		var path := "res://assets/music/%s.ogg" % scene
		if not ResourceLoader.exists(path):
			_ok(false, "音乐素材存在：%s" % path)
			continue
		_ok(true, "音乐素材存在：%s" % path)
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			_ok(false, "%s 可解码" % scene)
			continue
		var span: Array = MUSIC_EXPECT[scene]
		var length := stream.get_length()
		_ok(length >= float(span[0]) and length <= float(span[1]),
			"%s 时长 %.1f 秒（期望 %.0f~%.0f）" % [scene, length, span[0], span[1]])
		_ok(stream is AudioStreamOggVorbis, "%s 解码为 OggVorbis" % scene)

	# 播放请求后必须被置为循环 —— 否则一曲放完就静音了
	am.call("play_music", "menu")
	var cached: Dictionary = am.get("_streams")
	var menu_path := "res://assets/music/menu.ogg"
	_ok(cached.has(menu_path), "播放后音乐流已进缓存")
	if cached.has(menu_path):
		var s: AudioStream = cached[menu_path]
		_ok(bool(s.get("loop")), "播放时把音乐流设为循环")


# ---------------- C 音效素材 ----------------

func _check_sfx(am: Node) -> void:
	var script: GDScript = load("res://scripts/AudioManager.gd")
	var files: Dictionary = script.SFX_FILES
	var dir: String = script.SFX_DIR
	print("\n[C] 音效素材（%d 个短名）" % files.size())
	_ok(files.size() == SFX_COUNT,
		"音效短名共 %d 个（实际 %d）" % [SFX_COUNT, files.size()])

	var missing: PackedStringArray = PackedStringArray()
	var bad_len: PackedStringArray = PackedStringArray()
	for key in files.keys():
		var ok_sfx: bool = am.call("has_sfx", key)
		if not ok_sfx:
			missing.append(str(key))
			continue
		var stream: AudioStream = load(dir + str(files[key])) as AudioStream
		var length := 0.0 if stream == null else stream.get_length()
		if length < SFX_MIN_LEN or length > SFX_MAX_LEN:
			bad_len.append("%s(%.2fs)" % [key, length])
	_ok(missing.is_empty(), "全部音效可加载（缺失：%s）"
		% ("无" if missing.is_empty() else ", ".join(missing)))
	_ok(bad_len.is_empty(), "音效时长都在 %.2f~%.1f 秒（异常：%s）"
		% [SFX_MIN_LEN, SFX_MAX_LEN, "无" if bad_len.is_empty() else ", ".join(bad_len)])


# ---------------- D 播放与池 ----------------

func _check_playback(am: Node) -> void:
	print("\n[D] 播放与播放器池")

	var ok_click: bool = am.call("play_sfx", "click")
	_ok(ok_click, "play_sfx(\"click\") 成功")
	var ok_bad: bool = am.call("play_sfx", "根本不存在的音效")
	_ok(not ok_bad, "未登记的短名返回 false（静默降级，不报错）")

	# 同一个音效连续触发：应占用不同播放器，而不是互相打断
	am.call("stop_all_sfx")
	await process_frame
	for i in 3:
		am.call("play_sfx", "tactic")
	var playing := _count_playing(am)
	_ok(playing >= 2, "连续触发同一音效占用多个播放器（实际 %d 个在播）" % playing)

	# 池溢出：连打远多于池容量，不应崩
	for i in 20:
		am.call("play_sfx", "click")
	_ok(_count_playing(am) > 0, "池溢出（连打 20 次）后仍有音效在播、未崩溃")

	am.call("stop_all_sfx")
	await process_frame
	_ok(_count_playing(am) == 0, "stop_all_sfx() 后没有残留播放")

	# 音乐：重复请求不重头播，切歌换播放器（交叉淡化）
	am.call("play_music", "menu")
	await process_frame
	var first: AudioStreamPlayer = am.get("_fade_player") as AudioStreamPlayer
	_ok(str(am.get("_current_scene")) == "menu", "play_music(menu) 后当前场景为 menu")
	am.call("play_music", "menu")
	_ok(am.get("_fade_player") == first, "重复请求同一首不重头播（播放器未更换）")
	am.call("play_music", "battle")
	_ok(str(am.get("_current_scene")) == "battle", "切到 battle 成功")
	_ok(am.get("_fade_player") != first, "切歌时换了播放器（交叉淡化生效）")

	# UiKit 转发入口（各界面统一用它）
	UiKit.sfx("click")
	UiKit.sfx("同样不存在的音效")
	_ok(true, "UiKit.sfx 转发可用且对未登记名字不崩")


func _count_playing(am: Node) -> int:
	var players: Array = am.get("_sfx_players")
	var n := 0
	for i in players.size():
		var p: AudioStreamPlayer = players[i] as AudioStreamPlayer
		if p != null and p.playing:
			n += 1
	return n


# ---------------- E 音量与持久化 ----------------

func _check_volume(am: Node) -> void:
	print("\n[E] 音量 / 静音 / 持久化")

	var old_master: float = am.call("get_volume", "Master")
	var old_music: float = am.call("get_volume", "Music")
	var old_sfx: float = am.call("get_volume", "Sfx")
	var old_mute: bool = am.call("is_muted", "Sfx")

	am.call("set_volume", "Music", 1.5)
	_ok(is_equal_approx(float(am.call("get_volume", "Music")), 1.0), "音量上限钳制到 1.0")
	am.call("set_volume", "Music", -0.5)
	_ok(is_equal_approx(float(am.call("get_volume", "Music")), 0.0), "音量下限钳制到 0.0")
	am.call("set_volume", "Music", 0.42)
	_ok(is_equal_approx(float(am.call("get_volume", "Music")), 0.42), "音量可写可读")

	am.call("set_muted", "Sfx", true)
	_ok(bool(am.call("is_muted", "Sfx")), "静音开关生效")
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "静音同步到 AudioServer")
	am.call("set_muted", "Sfx", false)
	_ok(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "取消静音后总线恢复")

	# 持久化：改值（会自动写盘）后重新载入，应读到刚写的值
	am.call("set_volume", "Music", 0.33)
	am.call("_load_settings")
	_ok(is_equal_approx(float(am.call("get_volume", "Music")), 0.33),
		"音量写盘后重新载入一致（user://settings.cfg）")

	# 还原，别把测试值留在玩家的设置里
	am.call("set_volume", "Master", old_master)
	am.call("set_volume", "Music", old_music)
	am.call("set_volume", "Sfx", old_sfx)
	am.call("set_muted", "Sfx", old_mute)
	_ok(is_equal_approx(float(am.call("get_volume", "Music")), old_music),
		"测试结束已还原用户音量设置")
