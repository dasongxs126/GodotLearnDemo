## BattleController 的回合循环、阶段管线与资源收支测试。
##
## 覆盖规格书 §二 / §四 / §五 / §八：掷骰到回合结束的管线顺序，行动二选一的两条链，
## 资源点与生命值不越界，以及相同种子下战斗可复现。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 固定随机种子，保证整场战斗可复现。
const SEED := 20261001

## 玩家方生命值上限，取值较低以便快速分出胜负。
const PLAYER_HP := 6

## 敌方生命值上限，取值较低以便快速分出胜负。
const ENEMY_HP := 4

## 记录进入过的管线阶段编号。
var _phases: Array[int] = []

## 记录打开过的任意时刻窗口编号。
var _windows: Array[int] = []

## 记录弹刀结算次数。
var _clash_count: int = 0

## 记录抛硬币结果。
var _coin_results: Array[int] = []

## 入口：执行全部用例并输出退出码。
func _initialize() -> void:
	var helper := AssertHelper.new()
	_test_coin_flip(helper)
	_test_attack_phase_order(helper)
	_test_defend_phase_order(helper)
	_test_manual_clash_split(helper)
	_test_full_battle(helper)
	_test_deterministic_replay(helper)
	_test_all_defend_battle(helper)
	_report(helper, "test_battle_flow")

## 用例：抛硬币决定先手方并广播结果。
##
## @param helper 断言辅助
func _test_coin_flip(helper: AssertHelper) -> void:
	var controller := _make_controller(2, 2)
	controller.coin_flipped.connect(_on_coin_flipped)
	_coin_results.clear()
	var seen := {}
	for i in 40:
		var team := controller.flip_coin()
		seen[team] = true
		helper._assert_eq(controller.first_team(), team, "first_team 应与抛硬币结果一致")
	helper._assert_eq(seen.size(), 2, "多次抛硬币应同时出现先手与后手")
	helper._assert_eq(_coin_results.size(), 40, "每次抛硬币都应广播结果")

## 用例：一次进攻行动经过"进攻前 → 弹刀判定前 → 弹刀判定后 → 进攻后"。
##
## @param helper 断言辅助
func _test_attack_phase_order(helper: AssertHelper) -> void:
	var controller := _make_controller(1, 1)
	controller.phase_entered.connect(_on_phase_entered)
	controller.begin_round()
	_phases.clear()
	controller.run_action(controller.queue().current())
	var expected: Array[int] = [
		BattlePhase.Id.ACTION_BEFORE,
		BattlePhase.Id.ATTACK_BEFORE,
		BattlePhase.Id.CLASH_CHECK_BEFORE,
		BattlePhase.Id.CLASH_CHECK_AFTER,
		BattlePhase.Id.ATTACK_AFTER,
		BattlePhase.Id.ACTION_AFTER,
	]
	helper._assert_eq(_phases, expected, "进攻行动的阶段顺序")

## 用例：一次防御行动经过"防御前 → 防御后"，且不进入弹刀判定。
##
## @param helper 断言辅助
func _test_defend_phase_order(helper: AssertHelper) -> void:
	var controller := _make_controller(1, 1)
	controller.action_choice_provider = func(_actor: BattleUnit) -> int:
		return BattleController.ActionChoice.DEFEND
	controller.phase_entered.connect(_on_phase_entered)
	controller.begin_round()
	_phases.clear()
	controller.run_action(controller.queue().current())
	var expected: Array[int] = [
		BattlePhase.Id.ACTION_BEFORE,
		BattlePhase.Id.DEFEND_BEFORE,
		BattlePhase.Id.DEFEND_AFTER,
		BattlePhase.Id.ACTION_AFTER,
	]
	helper._assert_eq(_phases, expected, "防御行动的阶段顺序")

## 用例：begin_action 停在等待对抗模组处，resolve_attack 用指定模组结算。
##
## @param helper 断言辅助
func _test_manual_clash_split(helper: AssertHelper) -> void:
	var controller := _make_controller(1, 1)
	controller.action_choice_provider = func(_actor: BattleUnit) -> int:
		return BattleController.ActionChoice.ATTACK
	controller.attacker_symbol_provider = func(_actor: BattleUnit) -> int:
		return ClashResolver.Symbol.ROCK
	controller.phase_entered.connect(_on_phase_entered)
	controller.begin_round()
	_phases.clear()
	var actor := controller.queue().current()
	controller.begin_action(actor)
	var expected_begin: Array[int] = [
		BattlePhase.Id.ACTION_BEFORE,
		BattlePhase.Id.ATTACK_BEFORE,
		BattlePhase.Id.CLASH_CHECK_BEFORE,
	]
	helper._assert_eq(_phases, expected_begin, "begin_action 应停在弹刀判定前")
	helper._assert_true(controller.has_pending_clash(), "进攻应停在等待对抗模组处")
	helper._assert_eq(controller.pending_attacker(), actor, "待结算进攻方应为当前行动人")
	var defender := controller.pending_defender()
	helper._assert_true(defender != null, "待结算弹刀应有防守方")
	controller.resolve_attack(ClashResolver.NO_CONTEST)
	helper._assert_true(not controller.has_pending_clash(), "结算后不应再有待处理弹刀")
	helper._assert_eq(defender.hp, defender.hp_max - BattleController.PLACEHOLDER_DAMAGE, "不对抗时防守方受伤")
	controller.end_action(actor)
	var expected_end: Array[int] = [
		BattlePhase.Id.ACTION_BEFORE,
		BattlePhase.Id.ATTACK_BEFORE,
		BattlePhase.Id.CLASH_CHECK_BEFORE,
		BattlePhase.Id.CLASH_CHECK_AFTER,
		BattlePhase.Id.ATTACK_AFTER,
		BattlePhase.Id.ACTION_AFTER,
	]
	helper._assert_eq(_phases, expected_end, "结算后应补齐弹刀判定后、进攻后与行动结束")

## 用例：整场战斗能正常跑完，管线阶段齐全，数值不越界。
##
## @param helper 断言辅助
func _test_full_battle(helper: AssertHelper) -> void:
	var controller := _make_controller(3, 2)
	controller.phase_entered.connect(_on_phase_entered)
	controller.window_opened.connect(_on_window_opened)
	_phases.clear()
	_windows.clear()
	controller.run_battle()
	helper._assert_true(controller.is_finished(), "战斗应当结束")
	helper._assert_true(controller.round_index() >= 1, "至少进行过一轮")
	helper._assert_true(controller.winner_team() != -1, "应当分出胜负")
	helper._assert_true(_phases.has(BattlePhase.Id.ROLL_BEFORE), "应经过掷骰前阶段")
	helper._assert_true(_phases.has(BattlePhase.Id.ROLL_AFTER), "应经过掷骰后阶段")
	helper._assert_true(_phases.has(BattlePhase.Id.ROUND_AFTER), "应经过回合结束阶段")
	helper._assert_true(_windows.has(BattlePhase.Id.QUEUE_CHANGED), "应触发行动序列变动窗口")
	for unit in controller.player_units() + controller.enemy_units():
		helper._assert_between(unit.resource, 0, BattleUnit.RESOURCE_MAX, "%s 的资源点不应越界" % unit.display_name)
		helper._assert_between(unit.hp, 0, unit.hp_max, "%s 的生命值不应越界" % unit.display_name)

## 用例：相同种子下两场战斗得到相同的轮数与胜负。
##
## @param helper 断言辅助
func _test_deterministic_replay(helper: AssertHelper) -> void:
	var first := _make_controller(3, 2)
	first.run_battle()
	var second := _make_controller(3, 2)
	second.run_battle()
	helper._assert_eq(first.round_index(), second.round_index(), "相同种子应得到相同轮数")
	helper._assert_eq(first.winner_team(), second.winner_team(), "相同种子应得到相同胜负")

## 用例：全体选择防御时不发生弹刀，生命值回满、资源点收敛到上限。
##
## @param helper 断言辅助
func _test_all_defend_battle(helper: AssertHelper) -> void:
	var controller := _make_controller(2, 1)
	controller.action_choice_provider = func(_actor: BattleUnit) -> int:
		return BattleController.ActionChoice.DEFEND
	controller.clash_resolved.connect(_on_clash_resolved)
	_clash_count = 0
	controller.run_battle()
	helper._assert_eq(_clash_count, 0, "全体防御时不应发生弹刀")
	helper._assert_true(controller.is_finished(), "双方都无法造成伤害时应在轮数上限结束")
	for unit in controller.player_units() + controller.enemy_units():
		helper._assert_eq(unit.hp, unit.hp_max, "%s 应通过防御回满生命值" % unit.display_name)
		helper._assert_eq(unit.resource, BattleUnit.RESOURCE_MAX, "%s 的资源点应收敛到上限" % unit.display_name)

## 构造一场参数可控的战斗。
##
## @param player_count 玩家方人数
## @param enemy_count 敌方人数
## @return 已完成初始化的战斗控制器
func _make_controller(player_count: int, enemy_count: int) -> BattleController:
	var players: Array[BattleUnit] = []
	for i in player_count:
		players.append(BattleUnit.new("P%d" % (i + 1), BattleUnit.Team.PLAYER, i + 1, PLAYER_HP))
	var enemies: Array[BattleUnit] = []
	for i in enemy_count:
		enemies.append(BattleUnit.new("E%d" % (i + 1), BattleUnit.Team.ENEMY, i + 1, ENEMY_HP))
	var controller := BattleController.new()
	controller.setup(players, enemies, BattleUnit.Team.PLAYER, SEED)
	return controller

## 记录进入过的管线阶段。
##
## @param phase 阶段编号
## @param _actor 当前行动单位，本测试不使用
func _on_phase_entered(phase: int, _actor: BattleUnit) -> void:
	_phases.append(phase)

## 记录打开过的任意时刻窗口。
##
## @param phase 窗口编号
## @param _actor 相关单位，本测试不使用
func _on_window_opened(phase: int, _actor: BattleUnit) -> void:
	_windows.append(phase)

## 记录弹刀结算次数。
##
## @param _attacker 进攻方，本测试不使用
## @param _defender 防守方，本测试不使用
## @param _attacker_symbol 进攻方模组，本测试不使用
## @param _defender_symbol 防守方模组，本测试不使用
## @param _outcome 对拼结果，本测试不使用
## @param _damaged 受伤方，本测试不使用
func _on_clash_resolved(_attacker: BattleUnit, _defender: BattleUnit, _attacker_symbol: int, _defender_symbol: int, _outcome: int, _damaged: int) -> void:
	_clash_count += 1

## 记录抛硬币结果。
##
## @param first_team 先手阵营
func _on_coin_flipped(first_team: int) -> void:
	_coin_results.append(first_team)

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
