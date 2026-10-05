extends Node
class_name BotPilot
## 「机哥」——替二号机开飞机的 AI。
##
## 它不去伪造 InputEvent，而是把意图写进 player.virtual_up，
## 于是和真人玩家走**完全同一条物理路径**（同样的升力、同样的重力、同样的判定）。
##
## 「失误」不是随机乱按键，而是**僵住**：保持上一次的操作不变一段时间。
## 这比乱按更像人 —— 真人失误就是反应慢了半拍，而不是突然反向操作。
## 队友倒地时会进入「认真模式」，跳过若干次失误判定，这就是"臭人机偶尔也能把人救回来"。

enum Level { STUPID, NORMAL, MASTER }

## 三档难度。数字都是"越大越菜"或"越大越强"，注释里写清楚了。
const LEVELS: Array[Dictionary] = [
	{
		"name": "臭人机",
		"miss_gap": Vector2(1.3, 2.6),    # 两次失误之间的间隔（秒），越小越常失误
		"miss_len": Vector2(0.50, 1.00),  # 每次僵住多久
		"react": 0.22,                    # 反应延迟：隔多久才重新看一眼该往哪飞
		"rescue": 0.30,                   # 队友倒地时，有多大概率跳过这次失误
		"clutch": 0.20,                   # 眼看要撞上时，有多大概率果断冲刺补救
		"lookahead": 0.35,                # 提前量：按"再过这么多秒会到哪"来预判
	},
	{
		"name": "普通人机",
		"miss_gap": Vector2(3.4, 6.0),
		"miss_len": Vector2(0.28, 0.55),
		"react": 0.11,
		"rescue": 0.65,
		"clutch": 0.65,
		"lookahead": 0.45,
	},
	{
		# 机哥：几乎不失误，反应几乎无延迟，而且会预判。
		# 但失误率**不是 0** —— 保留一点人性，偶尔还是会晃一下。
		"name": "机哥",
		"miss_gap": Vector2(22.0, 40.0),
		"miss_len": Vector2(0.06, 0.14),
		"react": 0.02,
		"rescue": 1.0,
		"clutch": 1.0,
		"lookahead": 0.55,
	},
]

## 目标线上下这么宽的迟滞带，避免在目标高度上来回抖
const BAND_UP: float = 10.0
const BAND_DOWN: float = 32.0
## 没找到路障时的巡航高度
const CRUISE_Y: float = 300.0
## 多近算"要撞上了"
const PANIC_DIST: float = 340.0
## 柱子宽度的一半（和 obstacle.gd 的 PILLAR_W 对应），用来判断"这根已经压上去了"
const HALF_PILLAR: float = 192.0

var level: int = Level.NORMAL

var player: CharacterBody2D
var course: Node2D
## 队友（一号机）。他倒地时 AI 会认真起来。
var mate: CharacterBody2D

var _react_left: float = 0.0
var _miss_left: float = 0.0
var _miss_gap_left: float = 0.0
var _target_y: float = CRUISE_Y
var _holding: bool = false
var _rng := RandomNumberGenerator.new()

## 累计犯了多少次错（僵住次数）。调试和难度平衡用。
var miss_count: int = 0
## 这次僵住已经持续了多久 / 这次总共要僵多久
var _miss_total: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_miss_gap_left = _rng.randf_range(1.5, 3.0)


func cfg() -> Dictionary:
	return LEVELS[clampi(level, 0, LEVELS.size() - 1)]


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_alive():
		if player != null and is_instance_valid(player):
			player.virtual_up = false
		return

	var c: Dictionary = cfg()
	_react_left -= delta
	_miss_left -= delta
	_miss_gap_left -= delta

	# 该不该犯一次错
	if _miss_left <= 0.0 and _miss_gap_left <= 0.0:
		if mate != null and is_instance_valid(mate) and mate.downed and _rng.randf() < float(c["rescue"]):
			# 认真模式：这次不失误了，把下一次往后推
			_miss_gap_left = _rng.randf_range(0.5, 1.2)
		else:
			_miss_left = _rng.randf_range(c["miss_len"].x, c["miss_len"].y)
			_miss_total = _miss_left
			miss_count += 1
			_miss_gap_left = _rng.randf_range(c["miss_gap"].x, c["miss_gap"].y)

	# 反应延迟：不是每帧都重新决策，而是每隔 react 秒才看一眼
	if _react_left <= 0.0:
		_react_left = float(c["react"])
		_target_y = _pick_target_y()

	# 失误期间僵住：保持上一次的操作，不重新评估
	if _miss_left > 0.0:
		player.virtual_up = _holding
		_try_clutch(c)
		return

	# 带迟滞的开关控制，免得在目标线上下反复横跳
	var y: float = player.global_position.y
	if _holding:
		if y < _target_y - BAND_DOWN:
			_holding = false
	else:
		if y > _target_y + BAND_UP:
			_holding = true
	player.virtual_up = _holding
	_try_clutch(c)


## 前方那一根路障的「安全飞行高度」（obstacle.gd 算好的 gap_center）。
##
## 关键是**提前量**：不是看"现在最近的那根"，而是按当前速度算"再过 lookahead 秒
## 我会飞到哪儿"。飞行器升力很强但降下来要靠重力，所以必须提前开始改高度，
## 否则永远在追着缝隙跑 —— 这正是机哥以前显得笨的原因。
func _pick_target_y() -> float:
	if course == null:
		return CRUISE_Y
	var lead: float = maxf(absf(player.velocity.x), 200.0) * float(cfg()["lookahead"])
	var probe_x: float = player.global_position.x + lead

	var best: Node2D = null
	var best_dx: float = 1.0e9
	for ch in course.get_children():
		if not (ch is Node2D) or not ch.is_in_group("obstacle"):
			continue
		var dx: float = (ch as Node2D).position.x - probe_x
		# 车头已经压上去的这根不用管（来不及了），只挑还没到的最近一根
		if dx < -HALF_PILLAR or dx > best_dx:
			continue
		best_dx = dx
		best = ch
	if best == null:
		return CRUISE_Y
	return best.gap_center


## 眼看要撞上时果断用冲刺补救。难度越高越靠得住 ——
## 这就是"机哥"能一次次从必死局里穿过去的原因。
func _try_clutch(c: Dictionary) -> void:
	if course == null or not player.dash_ready():
		return
	var px: float = player.global_position.x
	for ch in course.get_children():
		if not (ch is Node2D) or not ch.is_in_group("obstacle"):
			continue
		var ob: Node2D = ch
		var dx: float = ob.position.x - px
		if dx < 10.0 or dx > PANIC_DIST:
			continue
		# 只有真的没对准缝隙才慌。余量从 25 收到 12：柱子判定盒是 156x73 的矩形，
		# 光看中心点对准还不够，边缘也会蹭到。
		var y: float = player.global_position.y
		if y > ob.gap_top_edge + 12.0 and y < ob.gap_bottom_edge - 12.0:
			return
		if _rng.randf() < float(c["clutch"]):
			player.start_dash()
		return
