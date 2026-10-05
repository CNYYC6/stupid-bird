class_name Worlds
extends RefCounted
## 生物群系（世界）注册表。
##
## 一个「世界」= 一张天空 + 4 层视差 + 一张地面 + 一套路障皮肤 + 若干规则。
##
## 约定（改美术时必须遵守，否则换世界会露出接缝）：
##   * 地面贴图的**顶边**永远画在 GROUND_Y 上，也就是地面碰撞面的高度；
##   * 4 层视差按 LAYER_Y 里的固定 y 摆放，换世界只换贴图、不动位置；
##   * 所有横向平铺的贴图都必须是 1920 宽且左右无缝（gen_worlds.py 负责）。

## 地面碰撞面的世界 y
const GROUND_Y: float = 700.0

## 4 层视差在世界坐标里的 y，和 main.tscn 里节点的 position.y 一一对应
const LAYER_Y: Array[float] = [60.0, 220.0, 424.0, 520.0]

## 每层视差系数：越小越远（越跟着相机走）
const LAYER_SCROLL: Array[float] = [0.08, 0.18, 0.38, 0.65]

## 每层的自动漂移速度（像素/秒）
const LAYER_SPEED: Array[float] = [8.0, 16.0, 28.0, 46.0]

const LIST: Array[Dictionary] = [
	{
		"id": "sky", "title": "晴空万里", "sub": "先热热身",
		"sky": "res://art/bg_sky.png",
		"clouds": "res://art/bg_clouds.png",
		"far": "res://art/bg_mountains_far.png",
		"mid": "res://art/bg_hills_mid.png",
		"near": "res://art/bg_trees_near.png",
		"ground": "res://art/bg_ground.png",
		"pillar": "res://art/obs_pillar.png",
		"cap_top": "res://art/obs_cap_top.png",
		"cap_hang": "res://art/obs_cap_hang.png",
		"flip": false,
		"gravity": 1.0,
	},
	{
		"id": "space", "title": "太空", "sub": "低重力，飘一点",
		"sky": "res://art/sp_sky.png",
		"clouds": "res://art/sp_stars.png",
		"far": "res://art/sp_planet.png",
		"mid": "res://art/sp_nebula.png",
		"near": "res://art/sp_debris.png",
		"ground": "res://art/sp_ground.png",
		"pillar": "res://art/obs_sp_pillar.png",
		"cap_top": "res://art/obs_sp_cap_top.png",
		"cap_hang": "res://art/obs_sp_cap_hang.png",
		"flip": false,
		"gravity": 0.62,
	},
	{
		"id": "jungle", "title": "原始森林", "sub": "树很密，别撞上",
		"sky": "res://art/ju_sky.png",
		"clouds": "res://art/ju_haze.png",
		"far": "res://art/ju_canopy_far.png",
		"mid": "res://art/ju_fern_mid.png",
		"near": "res://art/ju_trunks_near.png",
		"ground": "res://art/ju_ground.png",
		"pillar": "res://art/obs_ju_pillar.png",
		"cap_top": "res://art/obs_ju_cap_top.png",
		"cap_hang": "res://art/obs_ju_cap_hang.png",
		"flip": false,
		"gravity": 1.0,
	},
	{
		"id": "dream", "title": "梦幻世界", "sub": "这里不讲物理",
		"sky": "res://art/dr_sky.png",
		"clouds": "res://art/dr_clouds.png",
		"far": "res://art/dr_islands.png",
		"mid": "res://art/dr_candy.png",
		"near": "res://art/dr_balloons.png",
		"ground": "res://art/dr_ground.png",
		"pillar": "res://art/obs_dr_pillar.png",
		"cap_top": "res://art/obs_dr_cap_top.png",
		"cap_hang": "res://art/obs_dr_cap_hang.png",
		"flip": false,
		"gravity": 0.78,
	},
	{
		"id": "upside", "title": "上下颠倒", "sub": "你的肌肉记忆失效了",
		# 「上下颠倒」不额外画贴图：整屏翻转由相机 zoom.y 取负实现，
		# 所以它复用晴空那一套，翻转之后地平线跑到上面去，正好就是颠倒世界。
		"sky": "res://art/bg_sky.png",
		"clouds": "res://art/bg_clouds.png",
		"far": "res://art/bg_mountains_far.png",
		"mid": "res://art/bg_hills_mid.png",
		"near": "res://art/bg_trees_near.png",
		"ground": "res://art/bg_ground.png",
		"pillar": "res://art/obs_pillar.png",
		"cap_top": "res://art/obs_cap_top.png",
		"cap_hang": "res://art/obs_cap_hang.png",
		"flip": true,
		"gravity": 1.0,
	},
	{
		"id": "coin", "title": "金币维度", "sub": "20 秒，随便吃！",
		# 只有传送门事件会切到这里，不在常规轮换里
		"sky": "res://art/cn_sky.png",
		"clouds": "res://art/cn_clouds.png",
		"far": "res://art/cn_arches.png",
		"mid": "res://art/cn_pile.png",
		"near": "res://art/cn_gems.png",
		"ground": "res://art/cn_ground.png",
		"pillar": "res://art/obs_cn_pillar.png",
		"cap_top": "res://art/obs_cn_cap_top.png",
		"cap_hang": "res://art/obs_cn_cap_hang.png",
		"flip": false,
		"gravity": 1.0,
	},
]

## 常规轮换里出现哪些世界（金币维度是事件专属，不进轮换）
const ROTATION: Array[int] = [0, 1, 2, 3, 4]

const COIN_INDEX: int = 5


static func get_def(index: int) -> Dictionary:
	return LIST[wrapi(index, 0, LIST.size())]


static func rotation_index(step: int) -> int:
	return ROTATION[wrapi(step, 0, ROTATION.size())]


static func find(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return 0


## 换场横幅是带文字的贴图，路径要按当前语言取（见 scripts/ui_lang.gd）
static func title_path(id: String) -> String:
	return UiLang.path("w_title_%s.png" % id)


static func sub_path(id: String) -> String:
	return UiLang.path("w_sub_%s.png" % id)
