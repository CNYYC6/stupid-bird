extends Node
## 开发用：机哥单档长跑调参器。
##
##   Godot --headless --path . res://scenes/_debug.tscn --fixed-fps 60 -- --level=2 --seconds=120
##
## 参数（都走 `--` 之后的用户参数）：
##   --level=0|1|2     只跑哪一档（默认三档都跑）
##   --seconds=120     每档跑多久（默认 60）
##   --god=1           关掉死亡判定，只统计失误率（默认 0）
##
## 输出每档的：失误次数 / 僵住占比 / 活了多久 / 飞了多远 / 撞了几次。
## 调 bot_pilot.gd 里那张 LEVELS 表的时候用它，比开游戏手测快得多。

const LEVELS := ["臭人机", "普通人机", "机哥"]

var _only: int = -1
var _seconds: float = 60.0
var _god: bool = false

var _main: Node = null
var _lv: int = 0
var _left: float = 0.0
var _elapsed: float = 0.0
var _miss: Array[int] = []
var _frozen: Array[float] = []
var _deaths: Array[float] = []


func _init() -> void:
	for i in 3:
		_miss.append(0)
		_frozen.append(0.0)
		_deaths.append(-1.0)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			_only = int(a.split("=")[1])
		elif a.begins_with("--seconds="):
			_seconds = float(a.split("=")[1])
		elif a.begins_with("--god="):
			_god = int(a.split("=")[1]) == 1
	print("机哥调参：每档 %.0f 秒%s" % [_seconds, "（关掉死亡）" if _god else ""])
	_lv = 0 if _only < 0 else _only
	_start(_lv)


func _start(lv: int) -> void:
	if _main != null:
		_main.queue_free()
	RunRecord.save_mode(2)
	RunRecord.save_bot_level(lv)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	# 摘掉死亡判定：不做这个的话，一号机（真人位）会先撞死把整局结束掉
	_main.get_node("Course").player_hit.disconnect(_main._on_player_hit)
	_left = _seconds
	_elapsed = 0.0
	_miss[lv] = 0
	_frozen[lv] = 0.0
	_deaths[lv] = -1.0


func _physics_process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	_elapsed += delta
	var p1: CharacterBody2D = _main.players[0]
	var p2: CharacterBody2D = _main.players[1]

	if _god:
		# 无敌模式：谁倒了就立刻拉起来，保证三档跑满同样长的时间
		for p in [p1, p2]:
			if p.downed or not p.is_alive():
				p.revive(Vector2(p.global_position.x, 300.0))
	elif _deaths[_lv] < 0.0 and (p2.downed or not p2.is_alive()):
		_deaths[_lv] = _elapsed

	_frozen[_lv] += delta if _main.bot._miss_left > 0.0 else 0.0
	_miss[_lv] = _main.bot.miss_count

	if _left <= 0.0:
		_report(_lv)
		_lv += 1
		if _only >= 0:
			_lv = 3
		if _lv >= 3:
			_finish()
		else:
			_start(_lv)


func _report(lv: int) -> void:
	var lived: float = _deaths[lv] if _deaths[lv] >= 0.0 else _seconds
	print("  [%s] 失误 %d 次 / 僵住 %.1f 秒（%.0f%%）/ 二号机活了 %.1f 秒%s"
		% [LEVELS[lv], _miss[lv], _frozen[lv], _frozen[lv] / _seconds * 100.0, lived,
		   "" if _deaths[lv] < 0.0 else "  ← 中途阵亡"])


func _finish() -> void:
	print("")
	var ok: bool = _miss[0] > _miss[1] and _miss[1] > _miss[2]
	print("失误次数：臭人机 %d  >  普通人机 %d  >  机哥 %d   %s"
		% [_miss[0], _miss[1], _miss[2], "OK" if ok else "**阶梯不成立**"])
	get_tree().quit(0 if ok else 1)
