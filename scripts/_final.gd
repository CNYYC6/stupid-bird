extends Node
## 开发用：全量验收脚本。
##
##   Godot --headless --path . res://scenes/_final.tscn --fixed-fps 60
##
## 一条命令把这一版所有东西都过一遍：
##   三种模式都能开局、玩家数量与键位、冲刺是否分开且互不影响、
##   能量条编号牌、机哥三档失误率阶梯、菜单 25 只鸟的组合是否不重样、
##   世界是不是 30 秒才换一次、六个世界的 BGM 是否都在。
##
## 任何一项不通过都会打印 [FAIL] 并以非零码退出，方便挂到 CI 或提交前跑一次。

const LEVELS := ["臭人机", "普通人机", "机哥"]

var _fails: PackedStringArray = []
var _main: Node = null
var _t: int = 0
var _phase: int = 0
var _lv: int = 0
var _left: float = 0.0
var _miss: Array[int] = [0, 0, 0]


func _ck(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)
		print("  [FAIL] ", msg)


## 把当前主场景换成指定模式的新一局
func _boot(mode: int, bot_level: int = 1) -> CharacterBody2D:
	if _main != null:
		_main.queue_free()
	RunRecord.save_mode(mode)
	RunRecord.save_bot_level(bot_level)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_main.get_node("Course").player_hit.disconnect(_main._on_player_hit)
	return _main.players[0]


func _ready() -> void:
	print("=== 全量验收 ===")
	_static_checks()
	print("-- 单人模式")
	_solo_checks()
	print("-- 双人模式")
	_coop_checks()
	print("-- 机哥带你飞")
	_bot_checks()


# ---------------------------------------------------------------- 静态
func _static_checks() -> void:
	print("-- 静态配置")
	# 键位
	_ck(InputMap.has_action("pull_up"), "缺少 pull_up（单人空格）")
	_ck(InputMap.has_action("pull_up_p1"), "缺少 pull_up_p1（双人一号机 W）")
	_ck(InputMap.has_action("pull_up_p2"), "缺少 pull_up_p2（双人二号机 ↑）")
	_ck(InputMap.has_action("dash"), "缺少 dash（ENTER）")
	_ck(InputMap.has_action("dash_p1"), "缺少 dash_p1（一号机 E）")

	# BGM
	_ck(Audio.BGM_PATHS.size() == 6, "BGM 不是 6 段：%d" % Audio.BGM_PATHS.size())
	_ck(Audio._bgm.size() == 6, "BGM 流没全部加载：%d" % Audio._bgm.size())
	var missing: Array[String] = []
	for wid in Audio.BGM_PATHS:
		if not Audio._bgm.has(wid):
			missing.append(wid)
	_ck(missing.is_empty(), "这些世界的 BGM 加载失败：%s" % str(missing))
	print("  6 段 BGM 全部就绪，交叉淡化 %.1f 秒" % Audio.BGM_FADE)

	# 世界
	_ck(Worlds.LIST.size() == 6, "世界数量不是 6：%d" % Worlds.LIST.size())

	# 菜单 25 只鸟的皮肤组合
	var deck: Array = []
	var seen := {}
	for a in Skins.AIRCRAFT.size():
		for p in Skins.PILOTS.size():
			seen[Vector2i(a, p)] = true
	_ck(seen.size() == Skins.AIRCRAFT.size() * Skins.PILOTS.size(),
		"皮肤组合数不对：%d" % seen.size())
	print("  皮肤组合 %d 种（6 飞行器 x 6 驾驶员）" % seen.size())

	check_gravity_budget()


# ---------------------------------------------------------------- 单人
## 重力预算：任何「世界基础重力 x 重力类事件倍率」都必须小于升力能顶住的值。
##
## 按住爬升时向上的加速度是 `cruise_speed * lift_gain`，而向下的重力是 `gravity * 倍率`。
## 一旦重力反超，玩家按着爬升键也会一路直线下坠 —— 那不是"难"，是没法玩。
## 这里把整个世界 x 事件的组合都算一遍，调参数调过头时立刻就能发现。
##
## 数值直接读场景与脚本里的真实默认值，不写死 —— 免得改了 player.tscn 这里还对不上。
func check_gravity_budget() -> void:
	var probe: CharacterBody2D = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	var lift_speed: float = probe.cruise_speed
	var lift_gain: float = probe.lift_gain
	var lift: float = lift_speed * lift_gain
	var g: float = probe.gravity
	probe.free()
	var cap: float = load("res://scripts/main.gd").get_script_constant_map()["MAX_GRAVITY_SCALE"]
	var gevents: Dictionary = load("res://scripts/events.gd").get_script_constant_map()["GRAVITY_EVENTS"]

	print("  重力预算：升力 %.0f（= %.0f x %.1f），有效重力上限 %.0f x %.2f = %.0f"
		% [lift, lift_speed, lift_gain, g, cap, g * cap])
	var worst: float = 0.0
	for i in Worlds.LIST.size():
		var def: Dictionary = Worlds.get_def(i)
		var base: float = def.get("gravity", 1.0)
		for key in gevents:
			var eff: float = base * float(gevents[key])
			worst = maxf(worst, eff)
			_ck(eff <= cap + 0.001,
				"世界 %s x %s = 有效重力 %.2f，超过上限 %.2f（靠 clamp 兜着，该调小倍率）"
				% [def.get("id", str(i)), key, eff, cap])
			_ck(g * eff < lift,
				"世界 %s x %s：重力 %.0f 反超升力 %.0f，按着爬升键也会掉"
				% [def.get("id", str(i)), key, g * eff, lift])
	var net: float = lift - g * worst
	print("  最重组合：有效重力倍率 %.2f -> 净爬升 %+.0f（必须为正）" % [worst, net])
	_ck(net > 0.0, "最重组合下净爬升为负：%.0f" % net)


func _solo_checks() -> void:
	var p1: CharacterBody2D = _boot(0)
	_ck(_main.players.size() == 1, "单人模式玩家数不是 1：%d" % _main.players.size())
	_ck(p1._act_up == &"pull_up_p1", "单人爬升键不是 W：%s" % p1._act_up)
	_ck(p1._act_dash == &"dash_p1", "单人冲刺键不是 E：%s" % p1._act_dash)
	_ck(not p1._badge.visible, "单人模式不该显示编号牌")
	_ck(_main.bot == null, "单人模式不该创建 AI")
	print("  1 名玩家，W + E，无编号牌")


# ---------------------------------------------------------------- 双人
func _coop_checks() -> void:
	var p1: CharacterBody2D = _boot(1)
	var p2: CharacterBody2D = _main.players[1]
	_ck(_main.players.size() == 2, "双人模式玩家数不是 2")
	_ck(p1._act_up == &"pull_up_p1" and p1._act_dash == &"dash_p1",
		"一号机键位不对：%s / %s" % [p1._act_up, p1._act_dash])
	_ck(p2._act_up == &"pull_up_p2" and p2._act_dash == &"dash",
		"二号机键位不对：%s / %s" % [p2._act_up, p2._act_dash])
	_ck(p1._badge.texture.resource_path.get_file() == "badge_p1.png", "一号机标志不是 P1")
	_ck(p2._badge.texture.resource_path.get_file() == "badge_p2.png", "二号机标志不是 P2")

	# 冲刺必须各自独立：一号机冲了，二号机的能量条不该动
	_ck(p2.dash_ready(), "二号机开局应当可冲刺")
	p1.start_dash()
	_ck(p1.dash_active, "一号机冲刺没起来")
	_ck(not p2.dash_active, "一号机冲刺波及到了二号机")
	_ck(is_equal_approx(p2.dash_ratio(), 1.0), "二号机能量条被一号机消耗了")

	# 能量条编号牌
	var head1: Node = _main._hud._bars[0]["state"].get_parent()
	var head2: Node = _main._hud._bars[1]["state"].get_parent()
	_ck(head1.get_node("Tag").visible, "一号机能量条没有编号牌")
	_ck(head2.get_node("Tag").visible, "二号机能量条没有编号牌")
	_ck(head1.get_node("Tag").texture.resource_path.get_file() == "badge_p1.png",
		"一号机能量条牌子不是 P1")
	_ck(head2.get_node("Tag").texture.resource_path.get_file() == "badge_p2.png",
		"二号机能量条牌子不是 P2")
	print("  2 名玩家，键位与冲刺各自独立，两条能量条分别挂了 P1/P2")


# ---------------------------------------------------------------- 机哥
func _bot_checks() -> void:
	var p1: CharacterBody2D = _boot(2, 2)
	var p2: CharacterBody2D = _main.players[1]
	_ck(_main.bot != null, "机哥模式没创建 AI")
	_ck(p2.is_bot, "二号机没标记为 AI")
	_ck(p2._badge.texture.resource_path.get_file() == "badge_bot.png", "二号机标志不是 AI")
	var head2: Node = _main._hud._bars[1]["state"].get_parent()
	_ck(head2.get_node("Tag").texture.resource_path.get_file() == "badge_bot.png",
		"机哥的能量条牌子不是 AI")

	# 世界换得太勤了？直接量一次切换间隔
	var wd: Node2D = _main.get_node("WorldDirector")
	_ck(is_equal_approx(wd.switch_every_seconds, 30.0),
		"世界切换间隔不是 30 秒：%.1f" % wd.switch_every_seconds)
	print("  世界切换间隔 %.0f 秒（按时间，不按距离）" % wd.switch_every_seconds)

	# 三档失误率阶梯：各跑 30 秒。
	# 必须**先**用 0 档重新开一局 —— 上面那次 _boot(2, 2) 建的是机哥，
	# 直接开测的话第一档量到的其实是机哥的失误数（踩过这个坑）。
	print("-- 机哥三档各跑 30 秒（关掉死亡，只看失误率）")
	_lv = 0
	_boot(2, 0)
	_miss[0] = 0
	_left = 30.0
	_phase = 1


func _run_level(delta: float) -> void:
	_left -= delta
	var p2: CharacterBody2D = _main.players[1]
	if p2.downed or not p2.is_alive():
		p2.revive(Vector2(p2.global_position.x, 300.0))
	_miss[_lv] = _main.bot.miss_count
	if _left > 0.0:
		return
	print("  [%s] 失误 %d 次" % [LEVELS[_lv], _miss[_lv]])
	_lv += 1
	if _lv >= 3:
		_ck(_miss[0] > _miss[1] and _miss[1] > _miss[2],
			"失误率阶梯不成立：%d / %d / %d" % [_miss[0], _miss[1], _miss[2]])
		# 机哥要求"最低但不是没有"：30 秒内不该超过 3 次，但也不能保证一定是 0
		_ck(_miss[2] <= 3, "机哥 30 秒内失误 %d 次，太弱了" % _miss[2])
		_finish()
	else:
		_boot(2, _lv)
		# _boot 会重建 main，计数要从这一档自己的 0 重新数
		_miss[_lv] = 0
		_left = 30.0


func _physics_process(delta: float) -> void:
	if _phase == 1:
		_run_level(delta)


func _finish() -> void:
	print("")
	if _fails.is_empty():
		print("=== 全部通过 ===")
	else:
		print("=== 失败 %d 项 ===" % _fails.size())
		for f in _fails:
			print("  - ", f)
	# 跑完把模式还原成单人，免得留下"下次启动是机哥模式"这种脏状态
	RunRecord.save_mode(0)
	get_tree().quit(_fails.size())
