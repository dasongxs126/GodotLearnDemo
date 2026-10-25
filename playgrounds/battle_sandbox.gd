## 战斗沙盒：手工验证场景。
##
## 用按钮驱动 [BattleController]，把行动队列、指针位置与阶段流水打印到面板上，
## 用于肉眼确认排序优先级、指针语义与阶段顺序是否符合规格书。
##
## 界面全部由代码构建，场景文件只保留根节点与脚本挂载，避免手改节点树。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends Control

## 玩家方人数。
const PLAYER_COUNT := 3

## 敌方人数。
const ENEMY_COUNT := 2

## 玩家方生命值上限。
const PLAYER_HP := 12

## 敌方生命值上限。
const ENEMY_HP := 8

## 日志面板保留的最大行数，超过后清空历史避免面板卡顿。
const MAX_LOG_LINES := 400

## 战斗控制器。
var _controller: BattleController

## 日志面板。
var _log: RichTextLabel

## 已写入日志面板的行数，用于超长时清空历史。
##
## 自行计数而不依赖 [method RichTextLabel.get_line_count]：后者依赖布局完成，
## 在无头运行时恒为 0。
var _log_lines: int = 0

## 行动队列面板。
var _queue_label: RichTextLabel

## 状态栏。
var _status_label: Label

## "执行一次行动"按钮。
var _step_button: Button

## "跑完一轮"按钮。
var _round_button: Button

## 构建界面并开始第一场战斗。
func _ready() -> void:
	_build_ui()
	_start_battle()

## 构建界面。
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_status_label = Label.new()
	root.add_child(_status_label)

	_queue_label = RichTextLabel.new()
	_queue_label.custom_minimum_size = Vector2(0, 72)
	root.add_child(_queue_label)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)

	_step_button = Button.new()
	_step_button.text = "执行一次行动"
	_step_button.pressed.connect(_on_step_pressed)
	buttons.add_child(_step_button)

	_round_button = Button.new()
	_round_button.text = "跑完一轮"
	_round_button.pressed.connect(_on_round_pressed)
	buttons.add_child(_round_button)

	var battle_button := Button.new()
	battle_button.text = "跑完整场"
	battle_button.pressed.connect(_on_battle_pressed)
	buttons.add_child(battle_button)

	var reset_button := Button.new()
	reset_button.text = "重置"
	reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_button)

	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_log)

## 重置并开始一场新战斗。
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
	_controller.setup(players, enemies, BattleUnit.Team.PLAYER, randi())
	if _log != null:
		_log.clear()
	_log_lines = 0
	_append_log("[b]战斗开始[/b]，先手方：玩家")
	_controller.begin_round()
	_refresh()

## 刷新状态栏、队列面板与按钮可用性。
func _refresh() -> void:
	_status_label.text = "轮次 %d ｜ 状态：%s" % [_controller.round_index(), _status_text()]
	_queue_label.text = _queue_text()
	var finished := _controller.is_finished()
	_step_button.disabled = finished
	_round_button.disabled = finished

## 生成行动队列面板文本，用箭头标出当前操作人。
##
## @return 每个单位一行的队列文本
func _queue_text() -> String:
	var queue := _controller.queue()
	var lines := PackedStringArray()
	var index := 0
	for unit in queue.units():
		var marker := "▶" if index == queue.pointer_index() else "  "
		lines.append("%s %s[%s] HP %d/%d 资源 %d" % [marker, unit.display_name, _team_text(unit.team), unit.hp, unit.hp_max, unit.resource])
		index += 1
	return "\n".join(lines)

## 生成战斗状态文本。
##
## @return 状态文本
func _status_text() -> String:
	if not _controller.is_finished():
		return "进行中"
	var winner := _controller.winner_team()
	if winner == -1:
		return "达到轮数上限"
	return "%s获胜" % _team_text(winner)

## 取阵营中文名。
##
## @param team 阵营，取 [enum BattleUnit.Team]
## @return 中文名
func _team_text(team: int) -> String:
	return "我方" if team == BattleUnit.Team.PLAYER else "敌方"

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

## 向日志面板追加一行。
##
## @param line 日志内容，支持 BBCode
func _append_log(line: String) -> void:
	if _log == null:
		return
	if _log_lines >= MAX_LOG_LINES:
		_log.clear()
		_log.append_text("[color=gray]（日志过长，已清空历史）[/color]\n")
		_log_lines = 1
	_log.append_text(line + "\n")
	_log_lines += 1

## "执行一次行动"按钮回调。
func _on_step_pressed() -> void:
	if _controller.is_finished():
		_append_log("[color=gray]战斗已结束，请重置[/color]")
		return
	if _controller.queue().current() == null:
		_append_log("[color=gray]--- 本轮结束，进入下一轮 ---[/color]")
		_controller.begin_round()
	_controller.step_action()
	_refresh()

## "跑完一轮"按钮回调。
func _on_round_pressed() -> void:
	if _controller.is_finished():
		_append_log("[color=gray]战斗已结束，请重置[/color]")
		return
	_controller.run_round()
	_refresh()

## "跑完整场"按钮回调。
func _on_battle_pressed() -> void:
	if _controller.is_finished():
		_append_log("[color=gray]战斗已结束，请重置[/color]")
		return
	_controller.run_battle()
	_refresh()

## "重置"按钮回调。
func _on_reset_pressed() -> void:
	_start_battle()

## 阶段进入回调。
##
## @param phase 阶段编号
## @param actor 当前行动单位；轮次级阶段为 [code]null[/code]
func _on_phase_entered(phase: int, actor: BattleUnit) -> void:
	var suffix := ""
	if actor != null:
		suffix = "（%s）" % actor.display_name
	_append_log("[color=#66ccff]%s[/color]%s" % [BattlePhase.name_of(phase), suffix])

## 任意时刻窗口回调。
##
## @param phase 窗口编号
## @param actor 相关单位；无特定单位时为 [code]null[/code]
func _on_window_opened(phase: int, actor: BattleUnit) -> void:
	var suffix := ""
	if actor != null:
		suffix = "（%s）" % actor.display_name
	_append_log("[color=#ffaa00]窗口：%s[/color]%s" % [BattlePhase.name_of(phase), suffix])

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
