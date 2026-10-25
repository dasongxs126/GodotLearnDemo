## BattleDice 的面数规则与特殊骰子测试。
##
## 覆盖规格书 §三：默认面数 = 场上人物总和且最少 6 面，数字 1 至面数；
## 特殊战斗可使用固定点数的骰子。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 抽样次数，用于验证取值范围与分布。
const SAMPLE_COUNT := 500

## 入口：执行全部用例并输出退出码。
func _initialize() -> void:
	var helper := AssertHelper.new()
	_test_min_sides(helper)
	_test_sides_follow_unit_count(helper)
	_test_roll_range(helper)
	_test_fixed_dice(helper)
	_report(helper, "test_dice")

## 用例：场上人数不足 6 时，面数收敛到最少 6 面。
##
## @param helper 断言辅助
func _test_min_sides(helper: AssertHelper) -> void:
	helper._assert_eq(BattleDice.create_for_battle(3).sides(), 6, "3 人场面的最少面数")
	helper._assert_eq(BattleDice.create_for_battle(6).sides(), 6, "6 人场面的面数")
	helper._assert_eq(BattleDice.create_for_battle(0).sides(), 6, "空场面的最少面数")

## 用例：场上人数超过 6 时，面数等于人数。
##
## @param helper 断言辅助
func _test_sides_follow_unit_count(helper: AssertHelper) -> void:
	helper._assert_eq(BattleDice.create_for_battle(8).sides(), 8, "8 人场面的面数")
	helper._assert_eq(BattleDice.create_for_battle(13).sides(), 13, "13 人场面的面数")

## 用例：随机点数始终落在 1 至面数之间，且能取到两端。
##
## @param helper 断言辅助
func _test_roll_range(helper: AssertHelper) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var dice := BattleDice.create_for_battle(8, rng)
	var seen_low := false
	var seen_high := false
	for i in SAMPLE_COUNT:
		var value := dice.roll()
		helper._assert_between(value, 1, 8, "随机点数取值范围")
		seen_low = seen_low or value == 1
		seen_high = seen_high or value == 8
	helper._assert_true(seen_low, "%d 次抽样应出现过最小值 1" % SAMPLE_COUNT)
	helper._assert_true(seen_high, "%d 次抽样应出现过最大值 8" % SAMPLE_COUNT)

## 用例：固定点数骰子每次掷出都返回其固定值。
##
## @param helper 断言辅助
func _test_fixed_dice(helper: AssertHelper) -> void:
	var dice := BattleDice.create_fixed(4, 9)
	helper._assert_true(dice.is_fixed(), "固定点数骰子应标记为 fixed")
	helper._assert_eq(dice.sides(), 4, "固定点数骰子的面数")
	for i in 20:
		helper._assert_eq(dice.roll(), 9, "固定点数骰子的每次掷出")

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
