## 可操作战斗场景（等距版）。
##
## 在 [BattleController] 之上包一层**等距战场 + HUD**，验证"抛硬币 → 掷骰定序 → 行动二选一 →
## 弹刀 → 防御"这条最小闭环在真实操作下是否成立。**本场景不含技能**。
##
## 与上一版（卡片列表）的区别：单位不再是 [code]VBoxContainer[/code] 里的一张张卡片，
## 而是站在**等距菱形网格**上的场景精灵，按 [code]gx + gy[/code]（屏幕 y）排序遮挡。
## 逻辑层 [code]features/battle/[/code] 与 [code]tests/[/code] **零改动**——这正是当初分层的意义。
##
## 表现层约定：
## - 战场按 **640×360** 绘制，再整数倍（2×）放大到窗口 1280×720（见 [constant FIELD_SCALE]）；
## - 单位优先用 [code]assets/characters/*/idle.png[/code]；纹理缺失时退化成同尺寸色块，
##   保证"美术没到位也能跑通流程"；
## - 逻辑全部来自 [BattleController]，本脚本只负责收集输入、展示状态、推进流程；
## - 玩家输入采用"定点拆分"：控制器在 [method BattleController.begin_action] 处停下等待对抗模组，
##   本脚本在停下期间展示操作区，拿到输入后再调用 [method BattleController.resolve_attack]
##   与 [method BattleController.end_action] 收尾。
##
## 流程由 [enum Step] 状态机驱动，核心推进函数是 [method _advance]：敌方行动自动结算，
## 玩家行动则停下来等输入；玩家被进攻时开启防守反应窗口。
##
## 反应窗口不显示倒计时（规格书附录·批次 13：「敌人攻击后快要打到我时，我可以输入一个对抗模组」、
## 「反应不过来没输入，那就是失败」）：窗口长度**就是"敌人攻击过来"的演出时长**，
## 演出由 [method _update_telegraph] 逐帧驱动——进攻方起手泛白放大 → 攻击方块沿等距方向飞向防守方 →
## 方块抵达即窗口结束，没按出来即不对抗。**演出时长即难度旋钮。**
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name BattleScreen
extends Control

# ---------------------------------------------------------------------------
# 战斗规模
# ---------------------------------------------------------------------------

## 玩家方人数。
const PLAYER_COUNT := 3

## 敌方人数。
const ENEMY_COUNT := 3

## 玩家方生命值上限。
const PLAYER_HP := 12

## 敌方生命值上限。
const ENEMY_HP := 10

# ---------------------------------------------------------------------------
# 等距战场
# ---------------------------------------------------------------------------

## 战场的内部绘制尺寸。**等距资产按这个尺寸画**，再整数倍放大。
const FIELD_SIZE := Vector2(640, 360)

## 战场放大倍数：640×360 × 2 = 1280×720，正好铺满窗口。
##
## 用整数倍是为了像素不被拉花（非整数倍会出现像素宽窄不一）。
const FIELD_SCALE := 2.0

## 等距格尺寸，与 [code]assets/tiles/grid.png[/code] 一致。
const TILE_SIZE := Vector2(32, 16)

## 网格原点在**战场坐标**中的位置。
##
## 取 (320, 186) 使菱形场地位于战场中央，且两排单位的精灵（各 96px 高）**上下不重叠**。
const GRID_ORIGIN := Vector2(320, 186)

## 地面菱形网格的半径：保留 [code]|gx| + |gy| <= GRID_RADIUS[/code] 的格子。
const GRID_RADIUS := 7

## 单位精灵的占位尺寸。实际以纹理尺寸为准，纹理缺失时用它生成色块。
const UNIT_SIZE := Vector2(64, 96)

## 点击判定在精灵包围盒外额外放宽的像素（战场坐标）。
##
## 包围盒**恰好等于精灵**时，点歪一点点就选不中，而且 [method Rect2.has_point] 不含右/下边界，
## 连"正好点在脚底"都会落空。放宽一点才点得舒服。
const UNIT_HIT_PADDING := 5.0

## 描边精灵相对本体精灵的放大倍数，用来把描边从轮廓外扩出来。
const OUTLINE_SCALE := 1.08

## 可点选提示色：战场上的敌人现在可以点。
const MARKER_SELECTABLE := Color(0.40, 0.85, 1.00, 0.90)

## 悬停提示色：鼠标正停在这个敌人身上。
const MARKER_HOVER := Color(1.00, 0.86, 0.30, 1.00)

## 当前行动人提示色。
const MARKER_ACTOR := Color(0.40, 0.85, 1.00, 0.45)

## 被瞄准提示色：正在被进攻。
const MARKER_ALERT := Color(1.00, 0.25, 0.25, 0.95)

## 无提示。
const MARKER_NONE := Color(0.0, 0.0, 0.0, 0.0)

## 同排相邻单位的格间隔。
##
## **必须 ≥ 2**：64px 宽的精灵隔 1 格（32px）会互相压住 50%，糊成一堵墙。
## 精灵允许超出脚下那一格（站位只由脚底格点决定），但同排不能互相压住。
const CELL_STEP := 2

## 我方站位的深度键（[code]gx + gy[/code]），也是屏幕 y 的排序键。
##
## 取 +6 让本排的脚底落在网格中线下方；与敌方相差 12 个深度 = **96px**，
## 正好等于精灵高度，于是两排精灵上下**刚好不重叠**（重叠会让前排把后排挡住一半）。
const PLAYER_ROW_DEPTH := 6

## 敌方站位的深度键。
const ENEMY_ROW_DEPTH := -6

## 一排单位在屏幕上的横向位置：以战场中线为轴，左右各一个间隔。
##
## 取值 -2 / 0 / +2 使 [code]gx - gy[/code] 为 -4 / 0 / +4 → 屏幕 x 间隔 [constant CELL_STEP] × 16 = 64px。
const ROW_OFFSETS: Array[int] = [-CELL_STEP, 0, CELL_STEP]

## 我方站位（格坐标）。
##
## 由 [constant PLAYER_ROW_DEPTH] 与 [constant ROW_OFFSETS] 反解：满足
## [code]gx + gy = PLAYER_ROW_DEPTH[/code] 且 [code]gx - gy = 2 * ROW_OFFSETS[i][/code]。
const PLAYER_CELLS: Array[Vector2i] = [
	Vector2i(1, 5),
	Vector2i(3, 3),
	Vector2i(5, 1),
]

## 敌方站位（格坐标）。屏幕 x 与我方**逐一对齐**，形成正面对峙。
const ENEMY_CELLS: Array[Vector2i] = [
	Vector2i(-5, -1),
	Vector2i(-3, -3),
	Vector2i(-1, -5),
]

# ---------------------------------------------------------------------------
# 资产路径（缺失时自动退化为色块，不报错）
# ---------------------------------------------------------------------------

const TEX_BACKGROUND := "res://assets/backgrounds/battle_plaza.png"
const TEX_GRID := "res://assets/tiles/grid.png"
const TEX_SHADOW := "res://assets/characters/shadow.png"
const TEX_PLAYER := "res://assets/characters/hero_wolf/idle.png"
const TEX_ENEMY := "res://assets/characters/enemy_masked/idle.png"

## 单位描边着色器：按纹理 alpha 输出纯色轮廓，用作"这个敌人可以点"的提示。
##
## 不能用 [member CanvasItem.modulate] 代替——它是**乘法**，深色精灵乘亮色只会变暗。
const SHADER_UNIT_OUTLINE := "res://core/shaders/unit_outline.gdshader"

# ---------------------------------------------------------------------------
# 流程参数
# ---------------------------------------------------------------------------

## 日志面板保留的最大行数，超过后清空历史避免面板卡顿。
##
## 自行计数而不依赖 [method RichTextLabel.get_line_count]：后者依赖布局完成，
## 在无头运行时恒为 0。
const MAX_LOG_LINES := 400

## 防守反应窗口的默认时长（秒）。
##
## 正式流程**不显示倒计时**，窗口长度 = 敌人这次攻击的演出时长，所以它同时也是一个**难度旋钮**：
## 演出越慢、留给玩家的反应时间越长。色块原型先用固定值占位，正式版应做成"每次攻击各自一个时长"。
const REACTION_SECONDS_DEFAULT := 3.0

## 反应窗口时长的可调下限（秒），试玩时用来找手感。
const REACTION_SECONDS_MIN := 0.8

## 反应窗口时长的可调上限（秒）。
const REACTION_SECONDS_MAX := 6.0

## 单帧 [method Node._process] 的 delta 封顶（秒）。
##
## 窗口开启后若遇到一次长卡顿（首帧着色器编译、拖动窗口、系统挂起），一个几秒的 delta 会把
## 整个反应窗口**一帧吃光**——玩家什么都没看见就"没按出来"。封顶之后演出与窗口同步暂停，
## 卡顿不会变成额外的失败。
const MAX_FRAME_DELTA := 0.1

## 演出前段占比：这一段只做"起手"预告，攻击方块还没飞出来。
const WINDUP_RATIO := 0.35

## 攻击方块在**战场坐标**下的尺寸（放大 2× 后为 36×36 屏幕像素）。
const PROJECTILE_SIZE := Vector2(18, 18)

## 是否提供"主动不对抗"按钮。
##
## 规格书附录·批次 13 第 30 条：**不按就是不对抗**。所以玩家侧不设主动不对抗，
## 只能靠"没来得及按"；改成 [code]true[/code] 可临时放开便于调试。
const ALLOW_EXPLICIT_NO_CONTEST := false

## 可选模组，按"石头 / 剪刀 / 布"顺序排列，按钮就按这个顺序生成。
const SYMBOLS: Array[int] = [
	ClashResolver.Symbol.ROCK,
	ClashResolver.Symbol.SCISSORS,
	ClashResolver.Symbol.PAPER,
]

## **进攻**选模组的键位：Q=石头、W=剪刀、E=布（与"石头剪刀布"同序）。
##
## 与弹刀分开两套键位，是为了让手不用在同一个键区里切换语义：
## 进攻用键盘左上排（Q/W/E），弹刀用键盘中排（A/S/D），
## **物理位置分得开**，反应时不容易把"防守"按成"进攻"。
const ATTACK_KEY_SYMBOLS := {
	KEY_Q: ClashResolver.Symbol.ROCK,
	KEY_W: ClashResolver.Symbol.SCISSORS,
	KEY_E: ClashResolver.Symbol.PAPER,
}

## **弹刀（防守）**选模组的键位：A=石头、S=剪刀、D=布。
##
## 不设"不对抗"键——反应慢了没按出来，本身就是不对抗。
const DEFEND_KEY_SYMBOLS := {
	KEY_A: ClashResolver.Symbol.ROCK,
	KEY_S: ClashResolver.Symbol.SCISSORS,
	KEY_D: ClashResolver.Symbol.PAPER,
}

## 进攻模组到按键提示的映射，用于按钮文案。
const ATTACK_KEY_HINTS := {
	ClashResolver.Symbol.ROCK: "Q",
	ClashResolver.Symbol.SCISSORS: "W",
	ClashResolver.Symbol.PAPER: "E",
}

## 弹刀模组到按键提示的映射，用于按钮文案。
const DEFEND_KEY_HINTS := {
	ClashResolver.Symbol.ROCK: "A",
	ClashResolver.Symbol.SCISSORS: "S",
	ClashResolver.Symbol.PAPER: "D",
}

## 弹刀规则提示，常驻在底部横条。
##
## 模组名仍是占位（规格书 §六 ⏳ 待结合世界观定名），界面上先用机制名"石头剪刀布"，
## 因为这三个名字玩家本来就懂，不需要额外学习。
const CLASH_RULE_TEXT := "弹刀＝剪刀石头布：石头克剪刀、剪刀克布、布克石头；平局双方无伤；没按出来＝不对抗＝直接受伤；胜方 +1 资源 ｜ 进攻 Q W E、弹刀 A S D（也可直接点按钮）"

## 底部规则条的高度（窗口坐标）。
const RULE_BAR_HEIGHT := 46.0

## 当前流程所处的状态。
enum Step {
	## 没有在等输入（结算中或尚未开始）。
	IDLE,
	## 等玩家选进攻还是防御。
	PLAYER_CHOICE,
	## 等玩家选攻击目标（点战场上的敌方单位，或用按钮）。
	PLAYER_TARGET,
	## 等玩家选进攻模组。
	PLAYER_SYMBOL,
	## 等玩家在反应窗口里选对抗模组。
	REACTION,
	## 敌方行动自动结算中。
	ENEMY_ACTING,
	## 战斗已结束。
	FINISHED,
}

# ---------------------------------------------------------------------------
# 节点
# ---------------------------------------------------------------------------

## 战场根节点，整体缩放 [constant FIELD_SCALE]。
var _field: Node2D
## 地面层：背景 + 菱形网格。固定顺序，不参与 y 排序。
var _ground: Node2D
## 单位层：开启 y 排序，等距遮挡由引擎按屏幕 y 自动处理。
var _units_layer: Node2D
## 特效层：攻击方块等，画在所有单位之上。
var _fx: Node2D
## HUD 层，位于窗口坐标（不随战场缩放）。
var _hud: Control

## 顶部轮次标签。
var _round_label: Label
## 顶部阶段标签。
var _phase_label: Label
## 行动队列面板。
var _queue_label: RichTextLabel
## 操作区容器。
var _action_box: VBoxContainer
## 操作提示标签。
var _hint_label: Label
## 战斗日志面板。
var _log: RichTextLabel
## 已写入日志面板的行数。
var _log_lines: int = 0
## 窗口时长滑条。
var _window_slider: HSlider = null
## 窗口时长显示标签。
var _window_label: Label = null

## 攻击方块。
var _projectile: ColorRect = null

# ---------------------------------------------------------------------------
# 状态
# ---------------------------------------------------------------------------

## 等距网格换算器。
var _grid := IsoGrid.new(GRID_ORIGIN, TILE_SIZE)

## 战斗控制器。
var _controller: BattleController

## 本场随机源，只用于给控制器播种。
var _rng := RandomNumberGenerator.new()

## 单位到其战场节点集合的映射，键为 [BattleUnit]。
var _views: Dictionary = {}

## 当前状态。
var _step: int = Step.IDLE
## 当前行动人。
var _actor: BattleUnit = null
## 玩家选定的攻击目标。
var _chosen_target: BattleUnit = null
## 玩家选定的进攻模组。
var _chosen_symbol: int = ClashResolver.Symbol.ROCK
## 鼠标当前悬停的敌方单位，用于高亮。
var _hover_unit: BattleUnit = null

## 反应窗口是否开启。
var _reaction_active: bool = false
## 本次反应窗口的时长（秒），由试玩面板可调。
var _reaction_seconds: float = REACTION_SECONDS_DEFAULT
## 反应窗口剩余秒数。
var _reaction_remaining: float = 0.0
## 触发反应窗口的进攻方。
var _reaction_attacker: BattleUnit = null
## 被进攻的我方单位。
var _reaction_defender: BattleUnit = null

## 缓存的纹理，缺失时为 [code]null[/code]（对应单位退化为色块）。
var _tex_background: Texture2D = null
var _tex_grid: Texture2D = null
var _tex_shadow: Texture2D = null
var _tex_player: Texture2D = null
var _tex_enemy: Texture2D = null

## 缓存的描边着色器；缺失时为 [code]null[/code]（单位就没有描边提示）。
var _outline_shader: Shader = null


## 构建界面并开始第一场战斗。
func _ready() -> void:
	# 根 Control 不拦截鼠标，让战场点击能落到 _unhandled_input；HUD 面板自己会消费点击。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	set_process(false)
	_load_textures()
	_build_field()
	_build_hud()
	_start_battle()


## 驱动"敌人攻击过来"的演出。
##
## 窗口内不显示任何倒计时，进度完全由演出表达：起手预告 → 攻击方块飞向防守方 → 抵达即结束。
##
## 单帧 delta 按 [constant MAX_FRAME_DELTA] 封顶：见该常量的说明（一次长卡顿不该吃掉整个窗口）。
##
## @param delta 距上一帧的秒数
func _process(delta: float) -> void:
	if not _reaction_active:
		return
	_reaction_remaining -= minf(delta, MAX_FRAME_DELTA)
	var progress := clampf(1.0 - _reaction_remaining / _reaction_seconds, 0.0, 1.0)
	_update_telegraph(progress)
	if _reaction_remaining <= 0.0:
		_append_log("[color=#ffaa00]没按出来，视为不对抗[/color]")
		_resolve_reaction(ClashResolver.NO_CONTEST)


# ===========================================================================
# 资产
# ===========================================================================

## 载入可选纹理。文件不存在时置空，单位与地面会自动退化为色块。
func _load_textures() -> void:
	_tex_background = _try_load(TEX_BACKGROUND)
	_tex_grid = _try_load(TEX_GRID)
	_tex_shadow = _try_load(TEX_SHADOW)
	_tex_player = _try_load(TEX_PLAYER)
	_tex_enemy = _try_load(TEX_ENEMY)
	_outline_shader = _try_load_resource(SHADER_UNIT_OUTLINE) as Shader


## 尝试载入一张纹理。
##
## @param path 资源路径
## @return 纹理；不存在或载入失败时为 [code]null[/code]
func _try_load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("缺少美术资源，将退化为色块：%s" % path)
		return null
	return load(path) as Texture2D


## 尝试载入任意资源，供着色器等非纹理资源使用。
##
## @param path 资源路径
## @return 资源；不存在或载入失败时为 [code]null[/code]
func _try_load_resource(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_warning("缺少资源：%s" % path)
		return null
	return load(path)


# ===========================================================================
# 战场
# ===========================================================================

## 构建等距战场：背景 + 菱形网格 + 单位层 + 特效层。
func _build_field() -> void:
	_field = Node2D.new()
	_field.name = "Field"
	_field.scale = Vector2.ONE * FIELD_SCALE
	add_child(_field)

	_ground = Node2D.new()
	_ground.name = "Ground"
	_field.add_child(_ground)

	if _tex_background != null:
		var bg := Sprite2D.new()
		bg.name = "Background"
		bg.texture = _tex_background
		bg.centered = false
		_ground.add_child(bg)
	else:
		var fallback := ColorRect.new()
		fallback.name = "BackgroundFallback"
		fallback.color = Color(0.10, 0.11, 0.14)
		fallback.size = FIELD_SIZE
		_ground.add_child(fallback)

	_build_grid()

	_units_layer = Node2D.new()
	_units_layer.name = "Units"
	# 等距遮挡靠屏幕 y 排序：y 小的（远）先画，y 大的（近）后画。
	_units_layer.y_sort_enabled = true
	_field.add_child(_units_layer)

	_fx = Node2D.new()
	_fx.name = "Fx"
	_field.add_child(_fx)

	_projectile = ColorRect.new()
	_projectile.size = PROJECTILE_SIZE
	_projectile.visible = false
	_projectile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(_projectile)


## 铺菱形地面网格。
##
## 网格是**半透明**的（[code]assets/tiles/grid.png[/code]），不是不透明地砖——
## 铺满不透明砖会把背景广场盖成一张地垫，抢光背景的戏。半透明青色正好接上背景里已有的全息线。
func _build_grid() -> void:
	var cells := _grid.diamond_cells(GRID_RADIUS)
	if _tex_grid == null:
		# 没有网格纹理时用线框菱形兜底，至少让站位可读。
		for cell in cells:
			var outline := Polygon2D.new()
			outline.polygon = _grid.diamond_points()
			outline.color = Color(0.55, 0.85, 1.0, 0.10)
			outline.position = _grid.to_screen(cell.x, cell.y)
			_ground.add_child(outline)
		return
	for cell in cells:
		var tile := Sprite2D.new()
		tile.texture = _tex_grid
		tile.position = _grid.to_screen(cell.x, cell.y)
		_ground.add_child(tile)


## 取某单位的格坐标。
##
## @param unit 目标单位
## @return 格坐标；不在场时回退到 (0, 0)
func _cell_of(unit: BattleUnit) -> Vector2i:
	var table := PLAYER_CELLS if unit.team == BattleUnit.Team.PLAYER else ENEMY_CELLS
	var index := clampi(unit.slot - 1, 0, table.size() - 1)
	return table[index]


## 按当前战场重建全部单位视图。
func _build_unit_views() -> void:
	for child in _units_layer.get_children():
		_units_layer.remove_child(child)
		child.queue_free()
	_views.clear()
	for unit in _controller.enemy_units():
		_units_layer.add_child(_make_unit_view(unit))
	for unit in _controller.player_units():
		_units_layer.add_child(_make_unit_view(unit))


## 生成一个单位的战场视图。
##
## 节点结构（均以**脚底格点**为原点）：
## [codeblock]
## Unit (Node2D, position = 格点)
## ├── Highlight  Polygon2D   脚下菱形高亮：当前行动人 / 可选目标 / 被瞄准
## ├── Shadow     Sprite2D    椭圆影子（等距下不可省，否则角色像浮空）
## ├── Outline    Sprite2D    纯色描边（着色器），"这个单位可以点"
## ├── Body       Sprite2D    角色精灵
## ├── Tint       Sprite2D    同图红色叠加，用于"被瞄准"的泛红
## ├── NameLabel  Label       头顶名字
## ├── HpBack     ColorRect   血条底
## └── HpFill     ColorRect   血条填充
## [/codeblock]
##
## @param unit 对应单位
## @return 单位节点
func _make_unit_view(unit: BattleUnit) -> Node2D:
	var node := Node2D.new()
	node.name = unit.display_name
	node.position = _grid.to_screen(_cell_of(unit).x, _cell_of(unit).y)

	var highlight := Polygon2D.new()
	highlight.name = "Highlight"
	highlight.polygon = _grid.diamond_points()
	highlight.color = Color(0, 0, 0, 0)
	node.add_child(highlight)

	if _tex_shadow != null:
		var shadow := Sprite2D.new()
		shadow.name = "Shadow"
		shadow.texture = _tex_shadow
		node.add_child(shadow)

	var body := Sprite2D.new()
	body.name = "Body"
	body.texture = _texture_for(unit)
	if body.texture == null:
		body.texture = _placeholder_texture(_unit_color(unit), UNIT_SIZE)
	var body_size := Vector2(body.texture.get_width(), body.texture.get_height())
	body.position = Vector2(0.0, -body_size.y * 0.5)
	node.add_child(body)

	var outline := _make_outline(body)
	node.add_child(outline)
	# 描边要压在角色**下面**：它靠放大 1.08 倍从轮廓边缘露出来，本体盖住中间部分才是"描边"。
	node.move_child(outline, body.get_index())

	var tint := Sprite2D.new()
	tint.name = "Tint"
	tint.texture = body.texture
	tint.position = body.position
	tint.modulate = Color(1.0, 0.28, 0.28, 0.0)
	node.add_child(tint)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	# 字号与宽度都受限于 64px 的站位间隔：标签一旦超过间隔就会和邻座的标签压在一起。
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size = Vector2(62, 11)
	name_label.position = Vector2(-31.0, -body_size.y - 13.0)
	node.add_child(name_label)

	var hp_back := ColorRect.new()
	hp_back.name = "HpBack"
	hp_back.color = Color(0.0, 0.0, 0.0, 0.65)
	hp_back.size = Vector2(36, 4)
	hp_back.position = Vector2(-18.0, -body_size.y - 4.0)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(hp_back)

	var hp_fill := ColorRect.new()
	hp_fill.name = "HpFill"
	hp_fill.color = Color(0.35, 0.90, 0.45)
	hp_fill.size = Vector2(36, 4)
	hp_fill.position = hp_back.position
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(hp_fill)

	_views[unit] = {
		"node": node,
		"highlight": highlight,
		"outline": outline,
		"body": body,
		"tint": tint,
		"name_label": name_label,
		"hp_back": hp_back,
		"hp_fill": hp_fill,
		"body_size": body_size,
	}
	return node


## 生成与角色精灵同形的纯色描边精灵。
##
## 与本体用同一张纹理，靠 [constant OUTLINE_SCALE] 放大后从轮廓外沿露出来。
## 着色器缺失（[member _outline_shader] 为 [code]null[/code]）时返回一个不可见的空精灵，
## 保证节点结构一致、调用方不必判空。
##
## @param body 角色本体精灵
## @return 描边精灵
func _make_outline(body: Sprite2D) -> Sprite2D:
	var outline := Sprite2D.new()
	outline.name = "Outline"
	outline.texture = body.texture
	outline.position = body.position
	outline.scale = Vector2.ONE * OUTLINE_SCALE
	outline.visible = false
	if _outline_shader != null:
		var material := ShaderMaterial.new()
		material.shader = _outline_shader
		outline.material = material
	return outline


## 取单位对应的角色精灵纹理。
##
## @param unit 目标单位
## @return 纹理；缺失时为 [code]null[/code]
func _texture_for(unit: BattleUnit) -> Texture2D:
	return _tex_player if unit.team == BattleUnit.Team.PLAYER else _tex_enemy


## 生成纯色占位纹理，用于美术缺失时。
##
## @param color 颜色
## @param size 尺寸
## @return 生成的纹理
func _placeholder_texture(color: Color, size: Vector2) -> ImageTexture:
	var image := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## 取某单位战场节点。
##
## @param unit 目标单位
## @return 节点；不在场时为 [code]null[/code]
func _node_of(unit: BattleUnit) -> Node2D:
	if unit == null:
		return null
	var nodes: Dictionary = _views.get(unit, {})
	return nodes.get("node", null)


## 取某单位在战场坐标中的脚底位置。
##
## @param unit 目标单位
## @return 战场坐标；不在场时为 [code]Vector2.ZERO[/code]
func _field_pos_of(unit: BattleUnit) -> Vector2:
	var node := _node_of(unit)
	return node.position if node != null else Vector2.ZERO


## 刷新全部单位的数值、血条与脚下高亮。
##
## 高亮取色统一走 [method _marker_color_for]，脚下菱形与轮廓描边**同色**——
## 只画脚下那一小块菱形的话，玩家根本看不出敌人能点（试玩反馈）。
func _refresh_units() -> void:
	# 悬停对象必须随状态失效：从"选目标"退回"二选一"后，之前悬停的敌人已经不可点了。
	if _hover_unit != null and not _can_click(_hover_unit):
		_hover_unit = null

	var actor := _controller.queue().current()
	for unit in _views:
		var nodes: Dictionary = _views[unit]

		var hp_fill: ColorRect = nodes["hp_fill"]
		var ratio := float(unit.hp) / float(maxi(unit.hp_max, 1))
		hp_fill.size = Vector2(36.0 * ratio, 4.0)
		hp_fill.color = Color(0.35, 0.90, 0.45).lerp(Color(0.92, 0.25, 0.25), 1.0 - ratio)

		var name_label: Label = nodes["name_label"]
		name_label.text = "%s %d/%d" % [unit.display_name, unit.hp, unit.hp_max]

		var body: Sprite2D = nodes["body"]
		var tint: Sprite2D = nodes["tint"]
		tint.modulate.a = 0.0
		# 演出会把进攻方精灵放大（见 _update_telegraph），这里必须一并复原：
		# 只复原 modulate 的话，进攻方弹刀结束后会永远比别大一圈。
		body.scale = Vector2.ONE
		body.modulate = Color.WHITE
		if not unit.is_alive():
			body.modulate = Color(1.0, 1.0, 1.0, 0.28)
			name_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
		elif unit == actor:
			name_label.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0))
		else:
			name_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96))

		_apply_marker(nodes, _marker_color_for(unit, actor))


## 把一个提示色同时应用到脚下菱形与轮廓描边。
##
## @param nodes 单位节点集合
## @param color 提示色，为 [constant MARKER_NONE] 时两者都隐藏
func _apply_marker(nodes: Dictionary, color: Color) -> void:
	var highlight: Polygon2D = nodes["highlight"]
	highlight.color = color
	var outline: Sprite2D = nodes["outline"]
	outline.visible = color.a > 0.0
	if outline.visible and outline.material is ShaderMaterial:
		(outline.material as ShaderMaterial).set_shader_parameter("outline_color", color)


## 取某单位当前应显示的提示色。
##
## 优先级：被瞄准 > 当前行动人 > 鼠标悬停 > 可点选。玩家最需要立刻看出来的信息排前面。
##
## @param unit 目标单位
## @param actor 当前行动单位
## @return 提示色，取 [constant MARKER_SELECTABLE] 等
func _marker_color_for(unit: BattleUnit, actor: BattleUnit) -> Color:
	if not unit.is_alive():
		return MARKER_NONE
	if _reaction_active and unit == _reaction_defender:
		return MARKER_ALERT
	if unit == actor:
		return MARKER_ACTOR
	if unit == _hover_unit and _can_click(unit):
		return MARKER_HOVER
	if _can_click(unit):
		return MARKER_SELECTABLE
	return MARKER_NONE


## 判断某单位此刻是否可以用鼠标点选。
##
## **二选一阶段就能直接点敌人**——点敌人隐含"我要进攻"，不必先点一次「进攻」按钮
## （试玩反馈：必须先在右侧面板点进攻，鼠标点选就没什么价值了）。
##
## @param unit 目标单位
## @return 可点选时为 [code]true[/code]
func _can_click(unit: BattleUnit) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.team != BattleUnit.Team.ENEMY:
		return false
	return _step == Step.PLAYER_CHOICE or _step == Step.PLAYER_TARGET


## 取单位色块颜色，按阵营区分色相、按站位区分深浅。
##
## 只在美术资源缺失时用于生成占位色块。
##
## @param unit 目标单位
## @return 颜色
func _unit_color(unit: BattleUnit) -> Color:
	var weight := float(unit.slot - 1) * 0.45
	if unit.team == BattleUnit.Team.PLAYER:
		return Color(0.28, 0.52, 0.95).lerp(Color(0.20, 0.80, 0.72), weight)
	return Color(0.88, 0.30, 0.32).lerp(Color(0.86, 0.58, 0.18), weight)


# ===========================================================================
# HUD
# ===========================================================================

## 构建 HUD：顶部状态条、右侧信息栏、底部规则条。
##
## HUD 位于**窗口坐标**（1280×720），不随战场缩放，所以文字是原生分辨率、清晰可读。
func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_build_top_bar()
	_build_side_panel()
	_build_rule_bar()


## 顶部状态条：轮次、先手、当前阶段、重开按钮。
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 0.0
	bar.offset_bottom = 40.0
	_hud.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	_round_label = Label.new()
	row.add_child(_round_label)

	_phase_label = Label.new()
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_phase_label)

	var reset_button := Button.new()
	reset_button.text = "重开一局"
	reset_button.pressed.connect(_start_battle)
	row.add_child(reset_button)


## 右侧信息栏：行动队列、操作区、战斗日志。
func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SidePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -380.0
	panel.offset_top = 48.0
	panel.offset_bottom = -48.0
	_hud.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	column.add_child(_make_section_label("行动队列（本轮顺序）"))
	_queue_label = RichTextLabel.new()
	_queue_label.bbcode_enabled = true
	# 6 个单位各占一行，字号压小一点才不至于出现滚动条。
	_queue_label.add_theme_font_size_override("normal_font_size", 13)
	_queue_label.custom_minimum_size = Vector2(0, 150)
	column.add_child(_queue_label)

	column.add_child(_make_section_label("操作"))
	var tune_row := HBoxContainer.new()
	tune_row.add_theme_constant_override("separation", 6)
	column.add_child(tune_row)

	_window_label = Label.new()
	_window_label.add_theme_font_size_override("font_size", 12)
	tune_row.add_child(_window_label)

	_window_slider = HSlider.new()
	_window_slider.min_value = REACTION_SECONDS_MIN
	_window_slider.max_value = REACTION_SECONDS_MAX
	_window_slider.step = 0.1
	_window_slider.value = REACTION_SECONDS_DEFAULT
	_window_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_window_slider.value_changed.connect(_on_window_changed)
	tune_row.add_child(_window_slider)
	_update_window_label()

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(0, 34)
	column.add_child(_hint_label)

	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 4)
	column.add_child(_action_box)

	column.add_child(_make_section_label("战斗日志"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 120)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)


## 底部常驻规则条：把弹刀规则一直摆在屏幕上。
##
## 上一版把规则藏在操作区里，玩家试玩时**根本不知道弹刀怎么按**——占位命名一旦上了界面，
## 就必须把规则一起写出来。
func _build_rule_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "RuleBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# 必须显式给负的 offset_top：只靠 custom_minimum_size 的话，矩形会从底边往下长（跑出屏幕），
	# 结果整条规则条根本不显示。PRESET_BOTTOM_WIDE 只是把锚点贴到底边，高度仍是 0。
	bar.offset_top = -RULE_BAR_HEIGHT
	bar.offset_bottom = 0.0
	_hud.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	var label := Label.new()
	label.text = CLASH_RULE_TEXT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.74, 0.78, 0.86))
	margin.add_child(label)


## 生成一个小节标题标签。
##
## @param text 标题文字
## @return 标签节点
func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.95))
	return label


# ===========================================================================
# 流程
# ===========================================================================

## 重开一局：重建控制器、单位视图与日志，抛硬币后推进到第一个需要输入的位置。
func _start_battle() -> void:
	var players: Array[BattleUnit] = []
	for i in PLAYER_COUNT:
		players.append(BattleUnit.new("P%d" % (i + 1), BattleUnit.Team.PLAYER, i + 1, PLAYER_HP))
	var enemies: Array[BattleUnit] = []
	for i in ENEMY_COUNT:
		enemies.append(BattleUnit.new("E%d" % (i + 1), BattleUnit.Team.ENEMY, i + 1, ENEMY_HP))

	_controller = BattleController.new()
	_controller.phase_entered.connect(_on_phase_entered)
	_controller.window_opened.connect(_on_window_opened)
	_controller.clash_resolved.connect(_on_clash_resolved)
	_controller.resource_changed.connect(_on_resource_changed)
	_controller.queue_changed.connect(_on_queue_changed)
	_controller.coin_flipped.connect(_on_coin_flipped)
	_controller.setup(players, enemies, BattleUnit.Team.PLAYER, _rng.randi())

	_build_unit_views()
	_log.clear()
	_log_lines = 0
	_reaction_active = false
	_reaction_attacker = null
	_reaction_defender = null
	_hover_unit = null
	_step = Step.IDLE
	set_process(false)
	if _projectile != null:
		_projectile.visible = false

	_append_log("[b]战斗开始[/b] ｜ 我方 %d 人 对 敌方 %d 人" % [PLAYER_COUNT, ENEMY_COUNT])
	_controller.flip_coin()
	_controller.begin_round()
	_append_log("[b]第 %d 轮开始[/b]" % _controller.round_index())
	_advance()


## 推进流程，直到需要玩家输入或战斗结束。
##
## 循环体内处理：轮次切换、阵亡单位跳过、敌方行动自动结算。
func _advance() -> void:
	while true:
		_refresh_all()
		if _controller.is_finished():
			_finish_battle()
			return

		var actor := _controller.queue().current()
		if actor == null:
			_controller.end_round()
			if _controller.is_finished():
				_finish_battle()
				return
			_append_log("[color=#888888]--- 第 %d 轮结束 ---[/color]" % _controller.round_index())
			_controller.begin_round()
			_append_log("[b]第 %d 轮开始[/b]" % _controller.round_index())
			continue

		if not actor.is_alive():
			_controller.advance_pointer()
			continue

		if actor.team == BattleUnit.Team.ENEMY:
			_act_enemy(actor)
			if _step == Step.REACTION:
				return
			continue

		_begin_player_turn(actor)
		return


## 自动结算一次敌方行动。
##
## 若被进攻的是我方单位，则转入限时反应窗口并返回，由玩家输入接管。
##
## @param actor 行动单位
func _act_enemy(actor: BattleUnit) -> void:
	_step = Step.ENEMY_ACTING
	_hint_label.text = "%s 正在行动…" % actor.display_name
	_clear_action_box()
	_add_action_label("%s 正在行动…" % actor.display_name)

	_clear_providers()
	_controller.begin_action(actor)
	if _controller.has_pending_clash():
		var defender := _controller.pending_defender()
		if defender != null and defender.team == BattleUnit.Team.PLAYER:
			_open_reaction(actor, defender)
			return
		_controller.resolve_attack_auto()
	_controller.end_action(actor)
	_controller.advance_pointer()


## 进入玩家回合：等玩家选进攻还是防御。
##
## 战场上的敌人此刻就会亮起"可点"提示，**点敌人 = 直接进攻它**，不必先按「进攻」。
##
## @param actor 行动单位
func _begin_player_turn(actor: BattleUnit) -> void:
	_actor = actor
	_chosen_target = null
	_hover_unit = null
	_step = Step.PLAYER_CHOICE
	_hint_label.text = "%s 的回合：点战场上的敌人直接进攻，或选下面的行动" % actor.display_name
	_clear_action_box()
	_add_action_label("%s 的回合" % actor.display_name)
	var row := _add_action_row()
	_add_action_button(row, "进攻", func() -> void: _on_attack_pressed())
	_add_action_button(row, "防御", func() -> void: _on_defend_pressed())
	_refresh_units()


## "防御"按钮回调：走防御链，回血回资源，没有弹刀。
func _on_defend_pressed() -> void:
	var actor := _actor
	_step = Step.IDLE
	_clear_action_box()
	_controller.action_choice_provider = func(_a: BattleUnit) -> int: return BattleController.ActionChoice.DEFEND
	_controller.begin_action(actor)
	_controller.end_action(actor)
	_clear_providers()
	_controller.advance_pointer()
	_advance()


## "进攻"按钮回调：进入选目标（可点战场，也可点按钮）。
func _on_attack_pressed() -> void:
	var targets := _alive_enemies()
	if targets.is_empty():
		_append_log("[color=#888888]没有可选目标，跳过行动[/color]")
		_controller.advance_pointer()
		_advance()
		return
	_step = Step.PLAYER_TARGET
	_hover_unit = null
	_hint_label.text = "点战场上的敌人选目标，或用下面的按钮"
	_clear_action_box()
	_add_action_label("选择攻击目标")
	var row := _add_action_row()
	for unit in targets:
		var target := unit
		_add_action_button(row, "%s（HP %d）" % [target.display_name, target.hp], func() -> void: _on_target_pressed(target))
	var back := _add_action_row()
	_add_action_button(back, "返回", func() -> void: _begin_player_turn(_actor))
	_refresh_units()


## 选定攻击目标后进入选模组。
##
## @param target 选中的敌方单位
func _on_target_pressed(target: BattleUnit) -> void:
	_chosen_target = target
	_hover_unit = null
	_step = Step.PLAYER_SYMBOL
	_hint_label.text = "选择对 %s 使用的模组" % target.display_name
	_clear_action_box()
	_add_action_label("对 %s 使用哪枚模组？（键盘 Q / W / E，也可直接点按钮）" % target.display_name)
	var row := _add_action_row()
	for symbol in SYMBOLS:
		var pick: int = symbol
		_add_action_button(row, _symbol_button_text(pick, ATTACK_KEY_HINTS), func() -> void: _on_symbol_pressed(pick))
	var back := _add_action_row()
	_add_action_button(back, "返回", func() -> void: _on_attack_pressed())
	_refresh_units()


## 选定进攻模组：一次性把抉择、目标、模组注入控制器，跑完本次行动。
##
## @param symbol 选中的模组
func _on_symbol_pressed(symbol: int) -> void:
	var actor := _actor
	var target := _chosen_target
	var pick := symbol
	_step = Step.IDLE
	_clear_action_box()
	_controller.action_choice_provider = func(_a: BattleUnit) -> int: return BattleController.ActionChoice.ATTACK
	_controller.target_provider = func(_a: BattleUnit) -> BattleUnit: return target
	_controller.attacker_symbol_provider = func(_a: BattleUnit) -> int: return pick
	_controller.begin_action(actor)
	if _controller.has_pending_clash():
		_controller.resolve_attack_auto()
	_controller.end_action(actor)
	_clear_providers()
	_controller.advance_pointer()
	_advance()


## 开启防守反应窗口。
##
## **不显示倒计时**：窗口长度就是这次"敌人攻击过来"的演出时长。演出由 [method _update_telegraph]
## 逐帧驱动——起手预告 → 攻击方块沿等距方向飞向防守方 → 方块抵达即窗口结束；
## 期间没按出模组就是不对抗。
##
## @param attacker 进攻方
## @param defender 我方被进攻单位
func _open_reaction(attacker: BattleUnit, defender: BattleUnit) -> void:
	_reaction_attacker = attacker
	_reaction_defender = defender
	_reaction_active = true
	_reaction_remaining = _reaction_seconds
	_step = Step.REACTION
	_hint_label.text = "%s 正在进攻 %s" % [attacker.display_name, defender.display_name]
	_clear_action_box()
	_add_action_label("%s → %s" % [attacker.display_name, defender.display_name])
	_add_action_label("按 A 石头 / S 剪刀 / D 布（没按出来＝不对抗）")
	var row := _add_action_row()
	for symbol in SYMBOLS:
		var pick: int = symbol
		_add_action_button(row, _symbol_button_text(pick, DEFEND_KEY_HINTS), func() -> void: _on_reaction_pressed(pick))
	if ALLOW_EXPLICIT_NO_CONTEST:
		var row2 := _add_action_row()
		_add_action_button(row2, "不对抗", func() -> void: _on_reaction_pressed(ClashResolver.NO_CONTEST))
	if _projectile != null:
		_projectile.visible = false
		_projectile.color = _unit_color(attacker)
	set_process(true)


## 更新"敌人攻击过来"的演出。
##
## 前 [constant WINDUP_RATIO] 段只做起手预告（进攻方泛白、精灵放大），之后攻击方块从进攻方
## 沿**等距方向**飞向防守方，防守方精灵随方块逼近越来越红。**方块抵达就是窗口结束**，不看任何数字。
##
## 泛红改的是叠加精灵 [code]Tint[/code] 的 alpha，而不是角色精灵的 [member CanvasItem.modulate]：
## modulate 是**乘法**，深色底乘红只会发暗，看不出"被瞄准了"。
##
## @param progress 窗口进度，0 为刚开始，1 为抵达
func _update_telegraph(progress: float) -> void:
	var windup := minf(progress / WINDUP_RATIO, 1.0)

	var attacker_nodes: Dictionary = _views.get(_reaction_attacker, {})
	var attacker_body: Sprite2D = attacker_nodes.get("body", null)
	if attacker_body != null:
		attacker_body.modulate = Color.WHITE.lerp(Color(1.6, 1.6, 1.6), windup)
		attacker_body.scale = Vector2.ONE * (1.0 + 0.10 * windup)

	var defender_nodes: Dictionary = _views.get(_reaction_defender, {})
	var defender_tint: Sprite2D = defender_nodes.get("tint", null)
	if defender_tint != null:
		defender_tint.modulate = Color(1.0, 0.28, 0.28, 0.75 * progress)
	var defender_highlight: Polygon2D = defender_nodes.get("highlight", null)
	if defender_highlight != null:
		defender_highlight.color = Color(1.0, 0.25, 0.25, 0.20 + 0.40 * progress)

	if _projectile == null or progress < WINDUP_RATIO:
		if _projectile != null:
			_projectile.visible = false
		return
	var travel := (progress - WINDUP_RATIO) / (1.0 - WINDUP_RATIO)
	_projectile.visible = true
	_projectile.position = _field_pos_of(_reaction_attacker).lerp(_field_pos_of(_reaction_defender), travel) - PROJECTILE_SIZE * 0.5
	_projectile.modulate = Color(1, 1, 1, 0.4 + 0.6 * travel)


## 收起"攻击过来"的演出。
##
## 精灵颜色、缩放与脚下高亮由 [method _refresh_units] 在流程继续时统一复原，这里只收方块。
func _hide_telegraph() -> void:
	if _projectile != null:
		_projectile.visible = false


## 把正在进行的攻击演出**定格**到指定进度，供截图与人工核对使用。
##
## 反应窗口由真实时间驱动，靠"跑够多少帧"很难稳定停在演出中段，所以留这个确定性入口：
## 直接把剩余时间换算成目标进度再调一次 [method _update_telegraph]。
## **不属于游戏流程**，没有反应窗口时是空操作。
##
## @param progress 目标进度，0 为刚开始、1 为方块抵达
## @return 成功定格时为 [code]true[/code]
func _debug_hold_reaction(progress: float) -> bool:
	if not _reaction_active:
		return false
	_reaction_remaining = _reaction_seconds * (1.0 - clampf(progress, 0.0, 1.0))
	_update_telegraph(clampf(progress, 0.0, 1.0))
	return true


## 反应窗口时长滑条回调。
##
## @param value 新的窗口时长（秒）
func _on_window_changed(value: float) -> void:
	_reaction_seconds = value
	_update_window_label()


## 刷新窗口时长标签。
func _update_window_label() -> void:
	if _window_label == null:
		return
	_window_label.text = "窗口 %.1fs" % _reaction_seconds


## 反应窗口按钮回调。
##
## @param symbol 选中的模组，或 [constant ClashResolver.NO_CONTEST]
func _on_reaction_pressed(symbol: int) -> void:
	_resolve_reaction(symbol)


## 关闭反应窗口并用指定模组结算本次弹刀，然后继续推进流程。
##
## @param symbol 对抗模组，取 [enum ClashResolver.Symbol] 或 [constant ClashResolver.NO_CONTEST]
func _resolve_reaction(symbol: int) -> void:
	if not _reaction_active:
		return
	_reaction_active = false
	set_process(false)
	var attacker := _reaction_attacker
	_reaction_attacker = null
	_reaction_defender = null
	_step = Step.IDLE
	_hide_telegraph()
	_controller.resolve_attack(symbol)
	_controller.end_action(attacker)
	_controller.advance_pointer()
	_advance()


## 战斗结束：展示结果与重开按钮。
func _finish_battle() -> void:
	_step = Step.FINISHED
	_reaction_active = false
	set_process(false)
	var winner := _controller.winner_team()
	var text := "达到轮数上限，未分胜负"
	if winner != -1:
		text = "%s获胜" % _team_text(winner)
	_append_log("[b]战斗结束：%s[/b]" % text)
	_hint_label.text = text
	_clear_action_box()
	_add_action_label("战斗结束：%s" % text)
	var row := _add_action_row()
	_add_action_button(row, "重开一局", func() -> void: _start_battle())
	_refresh_all()


## 清空控制器上的决策注入，让敌方走默认行为（全体进攻 + 等概率随机模组）。
func _clear_providers() -> void:
	_controller.action_choice_provider = Callable()
	_controller.target_provider = Callable()
	_controller.attacker_symbol_provider = Callable()


## 刷新顶部、队列与单位视图。
func _refresh_all() -> void:
	_round_label.text = "第 %d 轮 ｜ 先手：%s" % [_controller.round_index(), _team_text(_controller.first_team())]
	_queue_label.text = _queue_text()
	_refresh_units()


## 生成行动队列文本。
##
## 每行带 HP 与资源点：战场上的头顶标签为了不被邻座压住只能写名字与 HP，
## 资源点就放到这里统一显示。
##
## @return 每行一个单位，箭头标出当前操作人
func _queue_text() -> String:
	var queue := _controller.queue()
	var lines := PackedStringArray()
	var index := 0
	for unit in queue.units():
		var marker := "▶" if index == queue.pointer_index() else "　"
		var dead := "" if unit.is_alive() else "（阵亡）"
		lines.append("%s %s %s 点数%d HP%d %s%s" % [
			marker,
			unit.display_name,
			_team_short(unit.team),
			queue.roll_of(unit),
			unit.hp,
			_resource_dots(unit.resource),
			dead,
		])
		index += 1
	if lines.is_empty():
		lines.append("（本轮已走完）")
	return "\n".join(lines)


## 取我方存活单位。
##
## @return 存活单位数组
func _alive_enemies() -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in _controller.enemy_units():
		if unit.is_alive():
			result.append(unit)
	return result


## 用圆点表示资源点，便于一眼看出余量。
##
## @param value 当前资源点
## @return 形如 [code]●●●○○[/code] 的字符串
func _resource_dots(value: int) -> String:
	var text := ""
	for i in BattleUnit.RESOURCE_MAX:
		text += "●" if i < value else "○"
	return text


## 取模组按钮的文案：按键在前，便于反应时扫字母。
##
## 进攻与弹刀用**两套键位**，所以按键提示由调用方指定，不要在这里写死。
##
## @param symbol 模组，取 [enum ClashResolver.Symbol]
## @param key_hints 键位提示表，取 [constant ATTACK_KEY_HINTS] 或 [constant DEFEND_KEY_HINTS]
## @return 形如 [code]Q 石头[/code] 的文案
func _symbol_button_text(symbol: int, key_hints: Dictionary) -> String:
	return "%s %s" % [key_hints.get(symbol, "?"), ClashResolver.symbol_name(symbol)]


## 取阵营中文名。
##
## @param team 阵营，取 [enum BattleUnit.Team]
## @return 中文名
func _team_text(team: int) -> String:
	return "我方" if team == BattleUnit.Team.PLAYER else "敌方"


## 取阵营单字简称，用于宽度受限的队列行。
##
## @param team 阵营，取 [enum BattleUnit.Team]
## @return [code]我[/code] 或 [code]敌[/code]
func _team_short(team: int) -> String:
	return "我" if team == BattleUnit.Team.PLAYER else "敌"


## 取受伤方中文名。
##
## @param damaged 受伤方，取 [enum ClashResolver.Side]
## @return 中文名
func _damaged_text(damaged: int) -> String:
	match damaged:
		ClashResolver.Side.ATTACKER:
			return "进攻方"
		ClashResolver.Side.DEFENDER:
			return "防守方"
		_:
			return "无"


# ===========================================================================
# 输入
# ===========================================================================

## 键盘输入：**进攻 Q/W/E、弹刀 A/S/D**；鼠标负责点选。
##
## 两套键位分开，是因为同一个键在"选进攻模组"与"防守反应窗口"里语义不同——
## 混用一套会让手在反应时按错。映射见 [constant ATTACK_KEY_SYMBOLS] 与 [constant DEFEND_KEY_SYMBOLS]。
##
## **不设不对抗键**——规格书附录·批次 13 第 30 条：不按就是不对抗，所以"没按出来"本身就是不对抗。
##
## 鼠标负责**全部选择**：行动二选一、选目标、选模组都有按钮可点；**敌人可以直接点**——
## 二选一阶段点敌人即隐含"我要进攻这个目标"，选目标阶段点敌人即选定目标。
## 可点的敌人会亮起同色的脚下菱形与轮廓描边（见 [method _apply_marker]）。
##
## HUD 面板会自行消费落在其上的点击，所以这里收到的必然是点在场地上的。
##
## @param event 输入事件
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _can_click_anything():
			_update_hover(_unit_at(_to_field(motion.position), BattleUnit.Team.ENEMY))
		else:
			_update_hover(null)
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _can_click_anything():
			var target := _unit_at(_to_field(mouse_event.position), BattleUnit.Team.ENEMY)
			if target != null:
				_on_target_pressed(target)
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match _step:
		Step.PLAYER_SYMBOL:
			if ATTACK_KEY_SYMBOLS.has(key_event.keycode):
				var attack_pick: int = ATTACK_KEY_SYMBOLS[key_event.keycode]
				_on_symbol_pressed(attack_pick)
		Step.REACTION:
			if DEFEND_KEY_SYMBOLS.has(key_event.keycode):
				var defend_pick: int = DEFEND_KEY_SYMBOLS[key_event.keycode]
				_on_reaction_pressed(defend_pick)
		_:
			pass


## 当前状态下是否有任何单位可以被点选。
##
## 鼠标事件本身不区分"点在哪"，所以先做一次粗判，避免在无关状态下反复做命中测试。
##
## @return 可以点选时为 [code]true[/code]
func _can_click_anything() -> bool:
	return _step == Step.PLAYER_CHOICE or _step == Step.PLAYER_TARGET


## 把视口坐标换算到战场坐标。
##
## 用**事件自带的 position**，而不是 [method Node2D.get_local_mouse_position]：
## 后者读的是全局鼠标状态，注入事件（自动化测试、截图工具）时对不上真实点位，
## 于是"点战场选目标"在测试里永远测不出来。
##
## 用 [method Node2D.get_global_transform_with_canvas] 而不是 [method Node2D.get_global_transform]：
## 前者含画布变换，[code]stretch/mode="canvas_items"[/code] 下窗口大于 640×360 时输入坐标会被
## 按比例缩放，只有带上画布变换才能换算回战场坐标（否则窗口一改大，点击就全部偏掉）。
##
## @param viewport_pos 视口坐标
## @return 战场坐标
func _to_field(viewport_pos: Vector2) -> Vector2:
	return _field.get_global_transform_with_canvas().affine_inverse() * viewport_pos


## 取战场坐标下命中的单位。
##
## 判定用精灵的外接矩形**外扩 [constant UNIT_HIT_PADDING]**：包围盒恰好等于精灵时点歪一点就落空，
## 而且 [method Rect2.has_point] 不含右/下边界，连"正好点在脚底"都会被排除。
##
## 多个命中时按两级规则决胜，**结果与遍历顺序无关**：
## 1. 屏幕 y 更大者胜（等距下更靠前，重叠时点到的是视觉上在前面的那个）；
## 2. 同一排（屏幕 y 相同）时，横向离点击点更近者胜——外扩余量让邻座的判定区互相重叠 10px，
##    不做这级决胜的话，点在缝里会随字典遍历顺序随机选中一个。
##
## @param point 战场坐标
## @param team 只接受这个阵营的单位，取 [enum BattleUnit.Team]
## @return 命中的单位；没命中时为 [code]null[/code]
func _unit_at(point: Vector2, team: int) -> BattleUnit:
	var pad := Vector2.ONE * UNIT_HIT_PADDING
	var hits: Array[BattleUnit] = []
	for unit in _views:
		if not unit.is_alive() or unit.team != team:
			continue
		var nodes: Dictionary = _views[unit]
		var node: Node2D = nodes["node"]
		var size: Vector2 = nodes["body_size"]
		var rect := Rect2(node.position + Vector2(-size.x * 0.5, -size.y) - pad, size + pad * 2.0)
		if rect.has_point(point):
			hits.append(unit)
	if hits.is_empty():
		return null

	var best: BattleUnit = hits[0]
	var best_node: Node2D = _views[best]["node"]
	for unit in hits:
		var node: Node2D = _views[unit]["node"]
		if node.position.y > best_node.position.y + 0.5:
			best = unit
			best_node = node
		elif absf(node.position.y - best_node.position.y) <= 0.5 \
				and absf(point.x - node.position.x) < absf(point.x - best_node.position.x):
			best = unit
			best_node = node
	return best


## 更新鼠标悬停对象。
##
## 只记状态、由 [method _refresh_units] 统一取色，避免"脚下菱形"和"轮廓描边"两处各写一套颜色判断。
##
## @param unit 当前悬停的单位，离开时为 [code]null[/code]
func _update_hover(unit: BattleUnit) -> void:
	if unit == _hover_unit:
		return
	_hover_unit = unit
	_refresh_units()


# ===========================================================================
# 操作区
# ===========================================================================

## 清空操作区。
func _clear_action_box() -> void:
	if _action_box == null:
		return
	for child in _action_box.get_children():
		_action_box.remove_child(child)
		child.queue_free()


## 在操作区新增一行。
##
## @return 新增的行容器
func _add_action_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_action_box.add_child(row)
	return row


## 在操作区新增一行说明文字。
##
## @param text 文字
## @return 新增的标签
func _add_action_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_box.add_child(label)
	return label


## 在指定行新增一个按钮。
##
## @param row 目标行
## @param text 按钮文字
## @param handler 点击回调
## @return 新增的按钮
func _add_action_button(row: HBoxContainer, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	row.add_child(button)
	return button


# ===========================================================================
# 日志与回调
# ===========================================================================

## 向日志面板追加一行。
##
## @param line 日志内容，支持 BBCode
func _append_log(line: String) -> void:
	if _log == null:
		return
	if _log_lines >= MAX_LOG_LINES:
		_log.clear()
		_log.append_text("[color=#888888]（日志过长，已清空历史）[/color]\n")
		_log_lines = 1
	_log.append_text(line + "\n")
	_log_lines += 1


## 阶段进入回调。
##
## @param phase 阶段编号
## @param actor 当前行动单位；轮次级阶段为 [code]null[/code]
func _on_phase_entered(phase: int, actor: BattleUnit) -> void:
	var suffix := ""
	if actor != null:
		suffix = "（%s）" % actor.display_name
	_phase_label.text = "阶段：%s%s" % [BattlePhase.name_of(phase), suffix]
	_append_log("[color=#66ccff]%s[/color]%s" % [BattlePhase.name_of(phase), suffix])


## 任意时刻窗口回调。
##
## @param phase 窗口编号
## @param actor 相关单位；无特定单位时为 [code]null[/code]
func _on_window_opened(phase: int, actor: BattleUnit) -> void:
	var suffix := ""
	if actor != null:
		suffix = "（%s）" % actor.display_name
	_append_log("[color=#d9a441]窗口：%s[/color]%s" % [BattlePhase.name_of(phase), suffix])


## 行动序列变动回调。
func _on_queue_changed() -> void:
	_append_log("[color=#888888]行动序列已重排[/color]")


## 抛硬币回调。
##
## @param first_team 先手阵营
func _on_coin_flipped(first_team: int) -> void:
	_append_log("抛硬币决定先手：%s" % _team_text(first_team))


## 弹刀结算回调。
##
## @param attacker 进攻方
## @param defender 防守方
## @param attacker_symbol 进攻方模组
## @param defender_symbol 防守方模组
## @param outcome 对拼结果
## @param damaged 受伤方
func _on_clash_resolved(attacker: BattleUnit, defender: BattleUnit, attacker_symbol: int, defender_symbol: int, outcome: int, damaged: int) -> void:
	_append_log("    弹刀 %s(%s) → %s(%s)：%s，受伤方 %s" % [
		attacker.display_name,
		ClashResolver.symbol_name(attacker_symbol),
		defender.display_name,
		ClashResolver.symbol_name(defender_symbol),
		ClashResolver.outcome_name(outcome),
		_damaged_text(damaged),
	])


## 资源点变动回调。
##
## @param unit 目标单位
## @param before 变动前资源点
## @param after 变动后资源点
func _on_resource_changed(unit: BattleUnit, before: int, after: int) -> void:
	_append_log("    资源 %s：%d → %d" % [unit.display_name, before, after])
