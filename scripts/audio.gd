extends Node
## 全局音频管理器（autoload 单例）。
##
## 做成 autoload 有两个理由：
##   1. 背景音乐要跨场景连续播放 —— 开始界面 -> 游戏 -> 结算面板中间不能断；
##   2. 任何脚本都能一行触发音效，不用各自持有播放器。
##
## 音效走一个播放器池轮转，否则连吃金币时后一个音会把前一个掐断。

# 用 var 而不是 const：const 绑定不允许改属性，而循环点需要在运行时写进流里
var _music_stream: AudioStreamWAV = preload("res://audio/bgm_day.wav")

const SFX: Dictionary = {
	"coin": preload("res://audio/sfx_coin.wav"),
	"flap": preload("res://audio/sfx_flap.wav"),
	"hit": preload("res://audio/sfx_hit.wav"),
	"ui": preload("res://audio/sfx_ui.wav"),
	"dash": preload("res://audio/sfx_dash.wav"),
	# 想换成 TTS 念的那版"哇哦"，把下面这行改成 sfx_wow_tts.wav
	"wow": preload("res://audio/sfx_wow.wav"),
}

const POOL_SIZE: int = 6
const MUSIC_DB: float = -13.0
const SFX_DB: float = -6.0

var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	# 结算面板会把整棵树 pause 掉，音频必须照常
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.volume_db = SFX_DB
		add_child(player)
		_pool.append(player)


## 开始播放背景音乐（已在播就什么都不做，所以各场景都能放心调用）
func start_music() -> void:
	if _music.playing:
		return
	# 循环点用时长换算，不能用 data.size()：
	# Godot 默认对 WAV 做 IMA-ADPCM 压缩，data 是压缩后的字节数，
	# 而 loop_end 要的是解码后的采样帧数，直接按字节数算会截掉一大半。
	var frames: int = int(_music_stream.get_length() * _music_stream.mix_rate)
	_music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_stream.loop_begin = 0
	_music_stream.loop_end = frames
	_music.stream = _music_stream
	_music.play()


func _exit_tree() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()
		_music.stream = null
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


## 停止背景音乐
func stop_music() -> void:
	if _music != null and is_instance_valid(_music):
		_music.stop()


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
