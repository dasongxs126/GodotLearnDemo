## 可操作战斗场景的冒烟测试。
##
## 在无头环境下实例化 [BattleScreen]，自动扮演玩家跑完整场战斗，确认
## "场景能加载 → 界面能构建 → 键盘操作能推进流程 → 战斗能结束"这条链路是通的。
##
## 断言只覆盖链路连通性，不校验数值与胜负（那些由 [code]test_battle_flow.gd[/code] 负责）。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 待测场景。
const SCREEN_SCENE := preload("res://playgrounds/battle_screen.tscn")

## 自动扮演玩家的最大步数，防止意外死循环。
const MAX_STEPS := 5000

## 每经过这么多次玩家抉择就改用防御，以便两条行动链都被走到。
const DEFEND_EVERY := 5

## 超时用例里用的窗口时长（秒），取很小值以便快速触发"没按出来"。
const TIMEOUT_WINDOW := 0.05

## 入口。
##
## 需要 [code]await[/code] 等界面 [method Node._ready] 跑完，所以整体是协程。
func _initialize() -> void:
	await _run()

## 依次执行各用例并输出结果。
func _run() -> void:
	var helper := AssertHelper.new()
	_test_key_map(helper)
	_test_formation(helper)
	await _test_key_split(helper)
	await _test_telegraph_restore(helper)
	await _test_reaction_timeout(helper)
	await _test_full_battle(helper)
	_report(helper, "test_battle_screen")

## 用例：攻击演出对精灵的改动必须在结算后复原。
##
## 演出会把进攻方泛白、放大 1.10 倍。只复原 [member CanvasItem.modulate] 不复原
## [member Node2D.scale] 的话，进攻方弹刀结束后会**永远比别大一圈**——而且很难被发现，
## 因为它只影响"打过人的那个单位"。
##
## @param helper 断言辅助
func _test_telegraph_restore(helper: AssertHelper) -> void:
	var screen: BattleScreen = await _spawn()
	# 长窗口：本用例不测时长，只要窗口别在用例中途自己超时
	screen._reaction_seconds = 60.0
	var opened: bool = await _drive_to_reaction(screen)
	helper._assert_true(opened, "推进行动后应出现防守反应窗口")
	if opened:
		var attacker: BattleUnit = screen._reaction_attacker
		helper._assert_true(attacker != null, "反应窗口应有进攻方")
		if attacker != null:
			var body: Sprite2D = screen._views[attacker]["body"]
			screen._debug_hold_reaction(0.5)
			helper._assert_true(body.scale.x > 1.0, "起手阶段进攻方精灵应被放大")
			screen._on_reaction_pressed(ClashResolver.Symbol.ROCK)
			helper._assert_eq(body.scale, Vector2.ONE, "结算后进攻方精灵缩放应复原")
			helper._assert_eq(body.modulate, Color.WHITE, "结算后进攻方精灵颜色应复原")
	screen.queue_free()
	await process_frame

## 用例：进攻用 Q/W/E、弹刀用 A/S/D，两套键位各自成立且互不重叠。
##
## 还要校验按钮提示表与键位表一致——否则界面写着 `Q 石头`、按下去却是别的模组。
##
## @param helper 断言辅助
func _test_key_map(helper: AssertHelper) -> void:
	helper._assert_eq(BattleScreen.ATTACK_KEY_SYMBOLS.get(KEY_Q), ClashResolver.Symbol.ROCK, "Q 应对应石头")
	helper._assert_eq(BattleScreen.ATTACK_KEY_SYMBOLS.get(KEY_W), ClashResolver.Symbol.SCISSORS, "W 应对应剪刀")
	helper._assert_eq(BattleScreen.ATTACK_KEY_SYMBOLS.get(KEY_E), ClashResolver.Symbol.PAPER, "E 应对应布")
	helper._assert_eq(BattleScreen.ATTACK_KEY_SYMBOLS.size(), 3, "进攻键位表应只有三系")

	helper._assert_eq(BattleScreen.DEFEND_KEY_SYMBOLS.get(KEY_A), ClashResolver.Symbol.ROCK, "A 应对应石头")
	helper._assert_eq(BattleScreen.DEFEND_KEY_SYMBOLS.get(KEY_S), ClashResolver.Symbol.SCISSORS, "S 应对应剪刀")
	helper._assert_eq(BattleScreen.DEFEND_KEY_SYMBOLS.get(KEY_D), ClashResolver.Symbol.PAPER, "D 应对应布")
	helper._assert_eq(BattleScreen.DEFEND_KEY_SYMBOLS.size(), 3, "弹刀键位表应只有三系，不设不对抗键")

	helper._assert_true(not BattleScreen.ALLOW_EXPLICIT_NO_CONTEST, "玩家侧不提供主动不对抗")

	# 两套键位不能重叠，否则同一个键在两个状态下语义冲突
	for key in BattleScreen.ATTACK_KEY_SYMBOLS:
		helper._assert_true(not BattleScreen.DEFEND_KEY_SYMBOLS.has(key), "进攻与弹刀的键位不应重叠")

	# 按钮提示表必须与键位表对得上：提示的键按下去要选中同一个模组
	for symbol in BattleScreen.SYMBOLS:
		var attack_hint: String = BattleScreen.ATTACK_KEY_HINTS.get(symbol, "")
		var attack_key := OS.find_keycode_from_string(attack_hint)
		helper._assert_eq(BattleScreen.ATTACK_KEY_SYMBOLS.get(attack_key), symbol, "进攻按钮提示的按键应选中同一模组")
		var defend_hint: String = BattleScreen.DEFEND_KEY_HINTS.get(symbol, "")
		var defend_key := OS.find_keycode_from_string(defend_hint)
		helper._assert_eq(BattleScreen.DEFEND_KEY_SYMBOLS.get(defend_key), symbol, "弹刀按钮提示的按键应选中同一模组")

## 用例：两套键位互不串台——选进攻模组时按弹刀键无效，反之亦然。
##
## @param helper 断言辅助
func _test_key_split(helper: AssertHelper) -> void:
	var screen: BattleScreen = await _spawn()
	var guard := 0
	while screen._step != BattleScreen.Step.PLAYER_SYMBOL and guard < 800:
		guard += 1
		match screen._step:
			BattleScreen.Step.PLAYER_CHOICE:
				screen._on_attack_pressed()
			BattleScreen.Step.PLAYER_TARGET:
				var targets := screen._alive_enemies()
				if targets.is_empty():
					break
				screen._on_target_pressed(targets[0])
			BattleScreen.Step.REACTION:
				# 敌方先手时流程会先进弹刀窗口，按个键把它走掉，才能轮到我方选模组
				_press_key(screen, KEY_A)
			_:
				pass
		await process_frame
	helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "应能推进到选进攻模组")

	if screen._step == BattleScreen.Step.PLAYER_SYMBOL:
		_press_key(screen, KEY_A)
		await process_frame
		helper._assert_eq(screen._step, BattleScreen.Step.PLAYER_SYMBOL, "选进攻模组时按弹刀键 A 不应生效")
		_press_key(screen, KEY_Q)
		await process_frame
		helper._assert_true(screen._step != BattleScreen.Step.PLAYER_SYMBOL, "选进攻模组时按进攻键 Q 应生效")

	screen.queue_free()
	await process_frame

## 用例：3v3 站位几何。
##
## 等距下"一排人"是沿 [code]gx[/code] 轴排的，屏幕 y 必须完全相同（否则不是一排）；
## 相邻间隔必须 ≥ 精灵宽度（否则 64px 宽的精灵互相压住）；
## 敌我屏幕 x 逐一对齐，形成正面对峙。
##
## @param helper 断言辅助
func _test_formation(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(BattleScreen.GRID_ORIGIN, BattleScreen.TILE_SIZE)
	var player_points := _row_points(grid, BattleScreen.PLAYER_CELLS)
	var enemy_points := _row_points(grid, BattleScreen.ENEMY_CELLS)

	helper._assert_eq(player_points.size(), BattleScreen.PLAYER_COUNT, "我方站位表人数")
	helper._assert_eq(enemy_points.size(), BattleScreen.ENEMY_COUNT, "敌方站位表人数")

	for i in player_points.size() - 1:
		helper._assert_true(
			is_equal_approx(player_points[i].y, player_points[i + 1].y),
			"我方同排应落在同一水平线上"
		)
		helper._assert_true(
			player_points[i + 1].x - player_points[i].x >= BattleScreen.UNIT_SIZE.x,
			"我方相邻单位屏幕间距不应小于精灵宽度，否则会互相压住"
		)
	for i in enemy_points.size() - 1:
		helper._assert_true(
			is_equal_approx(enemy_points[i].y, enemy_points[i + 1].y),
			"敌方同排应落在同一水平线上"
		)
		helper._assert_true(
			enemy_points[i + 1].x - enemy_points[i].x >= BattleScreen.UNIT_SIZE.x,
			"敌方相邻单位屏幕间距不应小于精灵宽度，否则会互相压住"
		)
	for i in player_points.size():
		helper._assert_true(
			is_equal_approx(enemy_points[i].x, player_points[i].x),
			"敌方第 %d 位应与我方同列" % (i + 1)
		)
	helper._assert_true(enemy_points[0].y < player_points[0].y, "敌方应位于我方后方（屏幕 y 更小）")
	# 两排必须拉开至少一个精灵高度，否则前排会把后排挡住一半
	helper._assert_true(
		player_points[0].y - enemy_points[0].y >= BattleScreen.UNIT_SIZE.y,
		"两排精灵上下不应重叠（间隔应 ≥ 精灵高度）"
	)

## 取一排格坐标在屏幕上的位置。
##
## @param grid 等距网格
## @param cells 格坐标数组
## @return 屏幕坐标数组
func _row_points(grid: IsoGrid, cells: Array[Vector2i]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for cell in cells:
		result.append(grid.to_screen(cell.x, cell.y))
	return result

## 统计某阵营的单位视图数量。
##
## @param screen 待测场景
## @param team 阵营，取 [enum BattleUnit.Team]
## @return 视图数量
func _view_count(screen: BattleScreen, team: int) -> int:
	var count := 0
	for unit in screen._views:
		if unit.team == team:
			count += 1
	return count

## 用例：反应窗口超时且未按键时，按"不对抗"结算。
##
## @param helper 断言辅助
func _test_reaction_timeout(helper: AssertHelper) -> void:
	var screen: BattleScreen = await _spawn()
	screen._reaction_seconds = TIMEOUT_WINDOW
	var opened: bool = await _drive_to_reaction(screen)
	helper._assert_true(opened, "推进行动后应出现防守反应窗口")
	if opened:
		var waited := 0
		while screen._reaction_active and waited < 600:
			waited += 1
			await process_frame
		helper._assert_true(not screen._reaction_active, "窗口应在演出走完后关闭")
		helper._assert_true(screen._log.get_parsed_text().contains("没按出来"), "超时未按键应记为不对抗")
	screen.queue_free()
	await process_frame

## 用例：用键盘自动扮演玩家，能跑完整场战斗。
##
## @param helper 断言辅助
func _test_full_battle(helper: AssertHelper) -> void:
	var screen: BattleScreen = await _spawn()
	helper._assert_eq(_view_count(screen, BattleUnit.Team.PLAYER), BattleScreen.PLAYER_COUNT, "我方单位视图数量")
	helper._assert_eq(_view_count(screen, BattleUnit.Team.ENEMY), BattleScreen.ENEMY_COUNT, "敌方单位视图数量")
	helper._assert_eq(screen._units_layer.get_child_count(), BattleScreen.PLAYER_COUNT + BattleScreen.ENEMY_COUNT, "战场单位层节点数")
	helper._assert_true(screen._queue_label.get_parsed_text() != "", "行动队列面板应有内容")
	helper._assert_true(screen._log.get_parsed_text() != "", "战斗日志应有内容")

	var reactions := 0
	var steps := 0
	while not screen._controller.is_finished() and steps < MAX_STEPS:
		steps += 1
		match screen._step:
			BattleScreen.Step.PLAYER_CHOICE:
				if steps % DEFEND_EVERY == 0:
					screen._on_defend_pressed()
				else:
					screen._on_attack_pressed()
			BattleScreen.Step.PLAYER_TARGET:
				var targets := screen._alive_enemies()
				helper._assert_true(not targets.is_empty(), "选目标时应有可选敌人")
				if targets.is_empty():
					break
				screen._on_target_pressed(targets[0])
			BattleScreen.Step.PLAYER_SYMBOL:
				_press_key(screen, KEY_E)
			BattleScreen.Step.REACTION:
				reactions += 1
				_press_key(screen, KEY_A)
			_:
				break
		await process_frame

	helper._assert_true(steps < MAX_STEPS, "自动扮演玩家不应陷入死循环")
	helper._assert_true(screen._controller.is_finished(), "自动扮演玩家应能跑完整场战斗")
	helper._assert_eq(screen._step, BattleScreen.Step.FINISHED, "战斗结束后应进入 FINISHED 状态")
	helper._assert_true(reactions > 0, "我方被进攻时应至少开启过一次反应窗口")
	helper._assert_true(screen._log.get_parsed_text().contains("弹刀"), "日志应记录弹刀结算")

	screen.queue_free()
	await process_frame

## 实例化场景并等界面 [method Node._ready] 跑完。
##
## @return 已就绪的场景实例
func _spawn() -> BattleScreen:
	var screen := SCREEN_SCENE.instantiate() as BattleScreen
	root.add_child(screen)
	await process_frame
	await process_frame
	return screen

## 推进到出现防守反应窗口为止。
##
## @param screen 待驱动场景
## @return 出现反应窗口时为 [code]true[/code]
func _drive_to_reaction(screen: BattleScreen) -> bool:
	var guard := 0
	while screen._step != BattleScreen.Step.REACTION and guard < 400:
		guard += 1
		match screen._step:
			BattleScreen.Step.PLAYER_CHOICE:
				screen._on_attack_pressed()
			BattleScreen.Step.PLAYER_TARGET:
				screen._on_target_pressed(screen._alive_enemies()[0])
			BattleScreen.Step.PLAYER_SYMBOL:
				_press_key(screen, KEY_Q)
			_:
				break
		await process_frame
	return screen._step == BattleScreen.Step.REACTION

## 模拟一次按键，走 [_unhandled_input] 那条真实路径。
##
## @param screen 目标场景
## @param keycode 键码，取 [enum Key]
func _press_key(screen: BattleScreen, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	screen._unhandled_input(event)

## 输出测试结果并结束进程。
##
## @param helper 断言辅助
## @param suite_name 用例集名称
func _report(helper: AssertHelper, suite_name: String) -> void:
	if helper.failures == 0:
		print("[通过] %s" % suite_name)
		quit(0)
		return
	push_error("[失败] %s：共 %d 项断言失败" % [suite_name, helper.failures])
	quit(1)
