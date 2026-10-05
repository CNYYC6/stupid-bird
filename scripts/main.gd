extends Node2D
## 主场景装配 + 单局状态（距离 / 金币 / 记录）+ 死亡结算 + 世界坐标重定基。

## 世界像素换算成"米"的比例
const METERS_PER_PIXEL: float = 0.1

## 每收集这么多金币就播一次"哇哦"
const WOW_EVERY: int = 30

## 连击：连着吃金币不断档，倍率阶梯上升；撞一次或断档 3 秒清零
const COMBO_TIMEOUT: float = 3.0
const COMBO_STEPS: Array[int] = [10, 25, 50]      # 达到这些数量，倍率 +1
const COMBO_MAX: int = 4
## 磁铁吸金币的半径与吸力
const MAGNET_RADIUS: float = 620.0
const MAGNET_PULL: float = 900.0
## 金币爆发一次炸出多少枚
const BURST_COINS: int = 16

## 世界坐标重定基步长。
## 相机和所有世界物体用的是 float32 变换，坐标涨到几百万像素后像素吸附会开始抖动；
## 这里在超过一个步长时把整个世界整体平移回去。取 2 的幂保证平移量精确可表示。
const REBASE_STEP: float = 262144.0

@export_file("*.tscn") var start_menu_scene: String = "res://scenes/start_menu.tscn"
@export var spawn_point: Vector2 = Vector2(91.0, 657.0)
## 双人模式的初始位置偏移：二号机在一号机后面一个身位。
## 两人横向速度完全一致，所以这个间距会一直保持；垂直高度各自按键各自飞。
## 取 170 是因为飞行器可视宽度约 174 像素，刚好不重叠又能同屏看全。
@export var coop_offset: Vector2 = Vector2(-170.0, 0.0)
## 双人模式里倒地后队友要撑住多少秒才能把人拉起来
@export var coop_revive_seconds: float = 5.0

## 0 = 单人闯关，1 = 双人合作，2 = 机哥带你飞
var mode: int = 0
## 机哥模式下的 AI（挂在二号机上）
var bot: BotPilot = null
## 参战的所有玩家（单人时只有一个）
var players: Array[CharacterBody2D] = []

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COIN_SCENE: PackedScene = preload("res://scenes/coin.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Camera
@onready var _road: Node2D = $Road
@onready var _course: Node2D = $Course
@onready var _hud: CanvasLayer = $Hud
@onready var _game_over: CanvasLayer = $GameOver
@onready var _worlds: Node2D = $WorldDirector
@onready var _events: Node2D = $Events

var distance_px: float = 0.0
var coins: int = 0
var alive: bool = true

var _shown_meters: int = -1

## 连击
var combo: int = 0
var _combo_left: float = 0.0

## 磁铁剩余时间（<= 0 表示没生效）
var _magnet_left: float = 0.0


func _ready() -> void:
	Audio.start_music()
	mode = RunRecord.load_mode()
	_setup_players()
	_course.begin(_player, spawn_point.x)
	_course.player_hit.connect(_on_player_hit)
	_course.coin_collected.connect(_on_coin_collected)
	_worlds.banner_requested.connect(_hud.show_world_banner)
	_events.banner.connect(_hud.show_event_banner)
	_events.fever_changed.connect(_hud.set_fever)
	_events.meteor_hit.connect(_on_player_hit)
	_events.turbo_granted.connect(grant_turbo_all)
	_course.powerup_picked.connect(_on_powerup_picked)
	_game_over.retry_requested.connect(retry)
	_game_over.menu_requested.connect(_go_to_menu)
	_hud.set_distance(0.0)
	_hud.set_coins(0)
	_hud.setup_players(players.size())


## 按存档里的模式摆好玩家。双人时二号机是运行时实例化的，
## 单人玩家不为它付任何代价（少一个 CharacterBody2D + 一套碰撞）。
func _setup_players() -> void:
	players.clear()
	var two_players: bool = mode != 0
	_player.configure(0, spawn_point, two_players)
	players.append(_player)
	if two_players:
		var p2 := PLAYER_SCENE.instantiate() as CharacterBody2D
		p2.name = "Player2"
		# 一号机的 6 倍像素放大是 main.tscn 里的实例覆盖，不是 player.tscn 自带的；
		# 代码实例化出来的二号机必须手动抄过来，否则会是一只 1 倍大的迷你鸟。
		p2.scale = _player.scale
		add_child(p2)
		# mode 2 时二号机由机哥代打（头顶换成 AI 标志）
		p2.configure(1, spawn_point + coop_offset, true, mode == 2)
		players.append(p2)
		if mode == 2:
			bot = BotPilot.new()
			bot.name = "BotPilot"
			bot.level = RunRecord.load_bot_level()
			bot.player = p2
			bot.mate = _player
			bot.course = _course
			p2.add_child(bot)
	# 换装：两名玩家分别读各自的存档（菜单里是分开编辑的）
	for i in players.size():
		var aircraft: int = RunRecord.load_setting("aircraft%d" % (i + 1), i)
		var pilot: int = RunRecord.load_setting("pilot%d" % (i + 1), 0)
		players[i].apply_skin(aircraft, pilot)
		players[i].apply_engine(Skins.aircraft_id(aircraft))
	_camera.set_targets(players)


func _physics_process(delta: float) -> void:
	_apply_world_gravity()
	if alive:
		_track_distance(delta)
		_course.traveled_meters = distance_px * METERS_PER_PIXEL
	_tick_coop(delta)
	_tick_combo(delta)
	_tick_magnet(delta)
	# 能量条每帧跟一次：冲刺 3 秒内要从满放到空，靠信号触发反而要做插值
	for i in players.size():
		_hud.set_dash(i, players[i].dash_ratio(), int(players[i].dash_state()))
	_rebase_world()


## 重力 = 世界自己的倍率 × 事件倍率。集中在这里算，
## 就不需要 WorldDirector 和 Events 各自去戳玩家（双人时有不止一个玩家）。
func _apply_world_gravity() -> void:
	var g: float = _worlds.base_gravity_scale() * _events.gravity_multiplier
	for p in players:
		if is_instance_valid(p):
			p.set_gravity_scale(g)


## 双人合作的拉人逻辑：一个人倒地，另一个还活着，撑满时间就能把他救回来
func _tick_coop(_delta: float) -> void:
	if players.size() < 2:
		return
	for i in players.size():
		var p: CharacterBody2D = players[i]
		if not p.downed:
			continue
		var mate: CharacterBody2D = players[1 - i]
		if not mate.is_alive():
			continue                      # 队友也倒了，没人来救
		if p.revive_left <= 0.0:
			# 在队友上方一点复活，别直接叠在柱子里
			p.revive(mate.global_position + Vector2(-120.0, -220.0))
			Audio.play("coin", 1.0, 1.25)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_record()


## 连击：3 秒内没吃到新金币就断档
func _tick_combo(delta: float) -> void:
	if combo <= 0:
		return
	_combo_left = maxf(_combo_left - delta, 0.0)
	if _combo_left <= 0.0:
		combo = 0
		_hud.set_combo(0, 1)


func combo_multiplier() -> int:
	var m: int = 1
	for step in COMBO_STEPS:
		if combo >= step:
			m += 1
	return mini(m, COMBO_MAX)


## 磁铁：把半径内的金币往玩家身上拽。
## 直接改金币的 position，不走物理 —— 它们本来就是 Area2D，没有刚体。
func _tick_magnet(delta: float) -> void:
	if _magnet_left <= 0.0:
		return
	_magnet_left = maxf(_magnet_left - delta, 0.0)
	_hud.set_powerup(0, _magnet_left)
	if _magnet_left <= 0.0:
		_hud.set_powerup(-1, 0.0)
		return
	var pullers: Array[CharacterBody2D] = []
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			pullers.append(p)
	if pullers.is_empty():
		return
	for coin in get_tree().get_nodes_in_group("coin"):
		var c := coin as Node2D
		var best: CharacterBody2D = null
		var best_d: float = MAGNET_RADIUS
		for p in pullers:
			var d: float = c.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
		if best == null:
			continue
		var dir: Vector2 = (best.global_position - c.global_position).normalized()
		# 越近吸得越快，远的地方只是轻微偏转，看起来才像磁场
		var speed: float = MAGNET_PULL * (1.0 - best_d / MAGNET_RADIUS) + 200.0
		c.global_position += dir * speed * delta


func _track_distance(delta: float) -> void:
	if _player.velocity.x > 0.0:
		distance_px += _player.velocity.x * delta
	var meters: int = int(distance_px * METERS_PER_PIXEL)
	if meters == _shown_meters:
		return
	_shown_meters = meters
	_hud.set_distance(float(meters))


## 世界坐标整体平移，把玩家拉回原点附近（详见 REBASE_STEP 注释）
func _rebase_world() -> void:
	var steps: float = floorf(_player.global_position.x / REBASE_STEP)
	if steps < 1.0:
		return
	var dx: float = steps * REBASE_STEP
	_player.global_position.x -= dx
	# 走相机自己的 shift：它会连平滑器的内部状态一起平移
	_camera.shift_x(dx)
	for node in [_road, _course]:
		for child in node.get_children():
			if child is Node2D:
				child.position.x -= dx


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_to_menu()
	elif event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		retry()


func _on_coin_collected() -> void:
	combo += 1
	_combo_left = COMBO_TIMEOUT
	var mult: int = _events.coin_multiplier() * combo_multiplier()
	coins += mult
	_hud.set_coins(coins)
	_hud.set_combo(combo, combo_multiplier())
	# 轻微随机音高，连吃一串金币时不会像复读机
	Audio.play("coin", 0.0, randf_range(0.94, 1.08))
	if coins % WOW_EVERY == 0:
		Audio.play("wow", 3.0)


## who 是撞上的那个玩家（双人模式必须分得清是谁撞的）
func _on_player_hit(who: Node2D = null) -> void:
	if not alive:
		return
	var victim: CharacterBody2D = who if who is CharacterBody2D and who in players else _first_alive()
	if victim == null:
		return
	# 无敌判定放在这里而不是只放在 course 里：陨石是 events 直接发过来的，
	# 走的不是 course 那条路，只拦一处会漏。
	if victim.is_invincible():
		return

	# 连击断档
	combo = 0
	_combo_left = 0.0
	_hud.set_combo(0, 1)

	# 护盾先顶一次
	if victim.consume_shield():
		Audio.play("ui", 2.0, 0.7)
		return

	# 双人模式：只要还有队友活着，被撞的人只是"倒地"，等队友来救
	if players.size() > 1 and _alive_count() > 1:
		victim.go_down(coop_revive_seconds)
		Audio.play("death", 0.0, 1.15)
		return

	alive = false
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			p.die()
	Audio.play("death", 0.0, 1.0)
	_commit_record()
	_game_over.show_result(distance_px * METERS_PER_PIXEL, coins)
	# 冻结整棵树；GameOver 的 process_mode = ALWAYS，仍然能响应按钮和按键
	get_tree().paused = true


## 免费冲刺发给所有还活着的玩家（单人就是发给自己）
func grant_turbo_all(seconds: float) -> void:
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			p.grant_turbo(seconds)


# ------------------------------------------------------------------ 道具
func _on_powerup_picked(kind: int) -> void:
	Audio.play("coin", 2.0, 0.8)
	match kind:
		0:      # 磁铁
			_magnet_left = 9.0
			_hud.set_powerup(0, _magnet_left)
		1:      # 护盾
			for p in players:
				if is_instance_valid(p) and p.is_alive():
					p.give_shield()
			_hud.set_powerup(1, 0.0)
		2:      # 金币爆发
			_burst_coins()
			_hud.set_powerup(2, 1.4)


## 在每个玩家周围炸出一圈金币
func _burst_coins() -> void:
	for p in players:
		if not is_instance_valid(p) or not p.is_alive():
			continue
		for i in BURST_COINS:
			var a: float = TAU * float(i) / float(BURST_COINS)
			var coin := COIN_SCENE.instantiate()
			coin.position = p.global_position + Vector2(cos(a), sin(a)) * randf_range(140.0, 260.0)
			_course.add_child(coin)
			coin.collected.connect(_on_coin_collected)


func _first_alive() -> CharacterBody2D:
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			return p
	return null


func _alive_count() -> int:
	var n: int = 0
	for p in players:
		if is_instance_valid(p) and p.is_alive():
			n += 1
	return n


## 重开一局：直接重载场景，保证路障/金币/物理状态全部干净
func retry() -> void:
	_commit_record()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _go_to_menu() -> void:
	_commit_record()
	get_tree().paused = false
	get_tree().change_scene_to_file(start_menu_scene)


func _commit_record() -> void:
	RunRecord.save_best(int(distance_px * METERS_PER_PIXEL), coins)
