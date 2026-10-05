class_name Skins
extends RefCounted
## 皮肤注册表：飞行器（图集）+ 驾驶员（单帧小人）。
##
## 飞行器沿用 64x64 图集约定（4 帧 32x32），引擎侧用同一段代码切 AtlasTexture，
## 所以新增一种飞机不需要额外的 .tres 资源文件，改这里的表就行。

## 单帧边长（和 bird_blue.png 的切图规则一致）
const CELL: int = 32
const COLS: int = 2

const AIRCRAFT: Array[Dictionary] = [
	{"id": "classic", "name": "经典蓝鸟", "atlas": "res://art/bird_blue.png"},
	{"id": "penguin", "name": "胖企鹅", "atlas": "res://art/bird_penguin.png"},
	{"id": "rocket", "name": "小火箭", "atlas": "res://art/bird_rocket.png"},
	{"id": "bat", "name": "夜行蝙蝠", "atlas": "res://art/bird_bat.png"},
	{"id": "paper", "name": "纸飞机", "atlas": "res://art/bird_paper.png"},
	{"id": "ufo", "name": "飞碟", "atlas": "res://art/bird_ufo.png"},
]

const PILOTS: Array[Dictionary] = [
	{"id": "none", "name": "无人驾驶", "tex": ""},
	{"id": "cat", "name": "猫", "tex": "res://art/pilot_cat.png"},
	{"id": "dog", "name": "狗", "tex": "res://art/pilot_dog.png"},
	{"id": "robot", "name": "机器人", "tex": "res://art/pilot_robot.png"},
	{"id": "alien", "name": "外星人", "tex": "res://art/pilot_alien.png"},
	{"id": "chick", "name": "小鸡", "tex": "res://art/pilot_chick.png"},
]

static var _frame_cache: Dictionary = {}


static func clamp_aircraft(i: int) -> int:
	return clampi(i, 0, AIRCRAFT.size() - 1)


static func clamp_pilot(i: int) -> int:
	return clampi(i, 0, PILOTS.size() - 1)


## 存档里默认值要按玩家号给不同初始皮肤（一号机经典蓝鸟、二号机胖企鹅），
## 这样双人模式一开局就能看出是两个人。
static func default_for(player_index: int) -> int:
	return clampi(player_index, 0, AIRCRAFT.size() - 1)


static func aircraft_id(i: int) -> String:
	return str(AIRCRAFT[clamp_aircraft(i)]["id"])


static func aircraft_name(i: int) -> String:
	return str(AIRCRAFT[clamp_aircraft(i)]["name"])


static func pilot_name(i: int) -> String:
	return str(PILOTS[clamp_pilot(i)]["name"])


static func preview_path(kind: String, i: int) -> String:
	if kind == "pilot":
		return "res://art/skin_pilot_%s.png" % PILOTS[clamp_pilot(i)]["id"]
	return "res://art/skin_bird_%s.png" % AIRCRAFT[clamp_aircraft(i)]["id"]


## 把图集切成 4 帧的 SpriteFrames。结果按飞机 index 缓存，
## 25 只菜单小鸟 + 两个玩家共用同一份，不会每次换皮肤都重建。
static func frames(i: int) -> SpriteFrames:
	var idx: int = clamp_aircraft(i)
	if _frame_cache.has(idx):
		return _frame_cache[idx]
	var atlas := load(AIRCRAFT[idx]["atlas"]) as Texture2D
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("fly_bird")
	sf.set_animation_speed("fly_bird", 30.0)
	sf.set_animation_loop("fly_bird", true)
	for f in COLS * COLS:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(float(f % COLS) * CELL, float(f / COLS) * CELL, CELL, CELL)
		sf.add_frame("fly_bird", at)
	_frame_cache[idx] = sf
	return sf


## 驾驶员贴图。index 0 = 无人，返回 null。
static func pilot_texture(i: int) -> Texture2D:
	var path: String = str(PILOTS[clamp_pilot(i)]["tex"])
	if path.is_empty():
		return null
	return load(path) as Texture2D
