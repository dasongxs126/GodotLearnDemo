## 测试断言辅助。
##
## 断言失败时通过 [method push_error] 输出可定位信息，并累计失败次数；
## 测试脚本据此决定退出码（0 通过，非 0 失败）。
##
## @author WorkBuddy AI
## @date 2026-10-01
class_name AssertHelper
extends RefCounted

## 累计的失败断言数量。
var failures: int = 0

## 断言两个值相等。
##
## @param actual 实际值
## @param expected 期望值
## @param message 失败时的定位信息
func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("[断言失败] %s：期望 %s，实际 %s" % [message, str(expected), str(actual)])

## 断言条件为真。
##
## @param condition 待检查条件
## @param message 失败时的定位信息
func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("[断言失败] %s" % message)

## 断言数值落在闭区间内。
##
## @param value 待检查数值
## @param min_value 下界，含
## @param max_value 上界，含
## @param message 失败时的定位信息
func _assert_between(value: int, min_value: int, max_value: int, message: String) -> void:
	if value >= min_value and value <= max_value:
		return
	failures += 1
	push_error("[断言失败] %s：期望落在 [%d, %d]，实际 %d" % [message, min_value, max_value, value])
