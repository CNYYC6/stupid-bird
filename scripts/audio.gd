extends Node
## 全局音频管理器（autoload 单例）。
##
## 做成 autoload 有两个理由：
##   1. 背景音乐要跨场景连续播放 —— 开始界面 -> 游戏 -> 结算面板中间不能断；
##   2. 任何脚本都能一行触发音效，不用各自持有播放器。
##
## 音效走一个播放器池轮转，否则连吃金币时后一个音会把前一个掐断。

## 每个世界一段 BGM，切换世界时交叉淡化。
## 用 var 而不是 const：const 绑定不允许改属性，而循环点需要在运行时写进流里。
const BGM_PATHS: Dictionary = {
	"sky": "res://audio/bgm_sky.wav",
	"space": "res://audio/bgm_space.wav",
	"jungle": "res://audio/bgm_jungle.wav",
	"dream": "res://audio/bgm_dream.wav",
	"upside": "res://audio/bgm_upside.wav",
	"coin": "res://audio/bgm_coin.wav",
}
## 切世界时两段 BGM 交叉淡化的时长（秒）
const BGM_FADE: float = 1.4
## 淡出到底的音量（不是 -inf，避免 Godot 的 db 线性插值出问题）
const BGM_SILENT_DB: float = -58.0

const SFX: Dictionary = {
	"coin": preload("res://audio/sfx_coin.wav"),
	"flap": preload("res://audio/sfx_flap.wav"),
	"hit": preload("res://audio/sfx_hit.wav"),
	"ui": preload("res://audio/sfx_ui.wav"),
	"dash": preload("res://audio/sfx_dash.wav"),
	# 想换成 TTS 念的那版"哇哦"，把下面这行改成 sfx_wow_tts.wav
	"wow": preload("res://audio/sfx_wow.wav"),
	# 阵亡 / 倒地
	"death": preload("res://audio/sfx_death.wav"),
}

## 每种飞行器的循环飞行声。音量刻意压得很低 —— 这是**一直响着**的底噪，
## 再响一点就会把金币音和 BGM 盖掉。
const ENGINE_PATHS: Dictionary = {
	"classic": "res://audio/engine_classic.wav",
	"penguin": "res://audio/engine_penguin.wav",
	"rocket": "res://audio/engine_rocket.wav",
	"bat": "res://audio/engine_bat.wav",
	"paper": "res://audio/engine_paper.wav",
	"ufo": "res://audio/engine_ufo.wav",
}
## 飞行声的音量。比音效（-6 dB）低 16 dB，双人叠两个也还是很轻。
const ENGINE_DB: float = -22.0

const POOL_SIZE: int = 6
const MUSIC_DB: float = -13.0
const SFX_DB: float = -6.0

## 两路音乐播放器轮流当"当前"和"下一段"，交叉淡化就是在两者之间推音量
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _fading_out: AudioStreamPlayer = null
var _fade_left: float = 0.0
## 已经设好循环点的 BGM 流，按世界 id 缓存
var _bgm: Dictionary = {}
## 当前播放的世界 id（避免同一段被重复触发）
var _bgm_id: String = ""

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
## 飞行声流（已经设好循环点），按飞行器 id 缓存
var _engines: Dictionary = {}


func _ready() -> void:
	# 结算面板会把整棵树 pause 掉，音频必须照常
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in BGM_PATHS:
		var st := load(BGM_PATHS[id]) as AudioStreamWAV
		if st == null:
			continue
		# 循环点必须用「时长 × 采样率」：Godot 默认把 WAV 压成 ADPCM，
		# data.size() 是压缩后的字节数，直接换算会截掉一大半
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_bgm[id] = st

	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.volume_db = BGM_SILENT_DB
		add_child(m)
	_active = _music_a
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_DB
		add_child(player)
		_pool.append(player)
	for id in ENGINE_PATHS:
		var st := load(ENGINE_PATHS[id]) as AudioStreamWAV
		if st == null:
			continue
		# 循环点同样必须用「时长 × 采样率」，不能用 data.size()（WAV 默认被压成 ADPCM）
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_engines[id] = st


## 开始播放某个世界的 BGM（交叉淡化，已经在放同一段就什么都不做）
func play_world_bgm(id: String) -> void:
	if id == _bgm_id:
		return
	var st: AudioStream = _bgm.get(id)
	if st == null:
		return
	_bgm_id = id

	if _active.stream == null:
		# 第一段直接起播，不需要淡化（比如从菜单进游戏）
		_active.stream = st
		_active.volume_db = MUSIC_DB
		_active.play()
		return

	var incoming: AudioStreamPlayer = _music_b if _active == _music_a else _music_a
	incoming.stream = st
	incoming.volume_db = BGM_SILENT_DB
	incoming.play()
	# 上一段如果还没淡完，直接归位，免得三路叠在一起
	if _fading_out != null and _fading_out != incoming:
		_fading_out.stop()
		_fading_out.stream = null
	_fading_out = _active
	_active = incoming
	_fade_left = BGM_FADE


## 兼容旧调用：没有具体世界时放晴空那段
func start_music() -> void:
	play_world_bgm("sky")


func _process(delta: float) -> void:
	if _fade_left <= 0.0:
		return
	_fade_left = maxf(_fade_left - delta, 0.0)
	var t: float = 1.0 - _fade_left / BGM_FADE
	_active.volume_db = lerpf(BGM_SILENT_DB, MUSIC_DB, t)
	if _fading_out != null:
		_fading_out.volume_db = lerpf(MUSIC_DB, BGM_SILENT_DB, t)
		if _fade_left <= 0.0:
			_fading_out.stop()
			_fading_out.stream = null
			_fading_out = null


func _exit_tree() -> void:
	for m in [_music_a, _music_b]:
		if m != null and is_instance_valid(m):
			m.stop()
			m.stream = null
	for player in _pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_cleanly()


## 接手退出流程：先把音频停掉，留两帧让音频线程松手，再真正退出。
##
## 音频仍在播放时进程就结束的话，播放对象来不及释放，Godot 会在控制台报
## "ObjectDB instances leaked at exit"。实测把音乐提前停掉再退出就不会有这条警告，
## 所以这里把 auto_accept_quit 关掉、自己控制退出时机。
func _quit_cleanly() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.auto_accept_quit = false
	stop_music()
	for player in _pool:
		player.stop()
	await tree.create_timer(0.15).timeout
	tree.quit()


## 取某种飞行器的循环飞行声（给玩家自己的 AudioStreamPlayer 用，双人模式互不干扰）
func engine_stream(id: String) -> AudioStream:
	return _engines.get(id)


## 停止背景音乐
func stop_music() -> void:
	for m in [_music_a, _music_b]:
		if m != null and is_instance_valid(m):
			m.stop()
	_bgm_id = ""
	_fade_left = 0.0
	_fading_out = null


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = SFX.get(name)
	if stream == null:
		push_warning("未知音效: %s" % name)
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = SFX_DB + volume_db
	player.pitch_scale = pitch
	player.play()
