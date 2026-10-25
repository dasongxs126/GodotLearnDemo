## [IsoGrid] 等距坐标换算测试。
##
## 只测纯数学：投影公式、逆运算往返、两条常用性质（同深度同屏幕 y、沿 gx 步进固定 x），
## 以及菱形场地与菱形顶点。**不依赖场景树**，可以独立跑。
##
## @author WorkBuddy AI
## @date 2026-10-01
extends SceneTree

## 浮点比较容差。
const EPSILON := 0.0001


## 入口。
func _initialize() -> void:
	var helper := AssertHelper.new()
	_test_roundtrip(helper)
	_test_row_is_horizontal(helper)
	_test_gx_step(helper)
	_test_diamond_cells(helper)
	_test_diamond_points(helper)
	if helper.failures == 0:
		print("[通过] test_iso_grid")
		quit(0)
		return
	push_error("[失败] test_iso_grid：共 %d 项断言失败" % helper.failures)
	quit(1)


## 用例：格坐标 → 屏幕坐标 → 格坐标，应当回到原处。
##
## @param helper 断言辅助
func _test_roundtrip(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(Vector2(320, 150), Vector2(32, 16))
	for gx in range(-6, 7, 2):
		for gy in range(-6, 7, 2):
			var screen := grid.to_screen(gx, gy)
			var back := grid.to_grid(screen)
			helper._assert_true(
				absf(back.x - gx) < EPSILON and absf(back.y - gy) < EPSILON,
				"往返换算应还原格坐标 (%d, %d)，实际 (%f, %f)" % [gx, gy, back.x, back.y]
			)


## 用例：[code]gx + gy[/code] 相同的格子，屏幕 y 必须相同。
##
## 这正是"一排人站在同一条水平线上"所依赖的性质。
##
## @param helper 断言辅助
func _test_row_is_horizontal(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(Vector2(320, 150), Vector2(32, 16))
	var row_depth := 2
	var ys: Array[float] = []
	for gx in [-2, 0, 2]:
		ys.append(grid.to_screen(gx, row_depth - gx).y)
	helper._assert_true(is_equal_approx(ys[0], ys[1]), "同深度格子的屏幕 y 应相同")
	helper._assert_true(is_equal_approx(ys[1], ys[2]), "同深度格子的屏幕 y 应相同")

	# 沿一排走意味着 gx + 1 且 gy - 1，屏幕 x 每格变化 2 * (tile.x / 2) = tile.x
	var xs: Array[float] = []
	for gx in [-2, 0, 2]:
		xs.append(grid.to_screen(gx, row_depth - gx).x)
	helper._assert_true(is_equal_approx(xs[1] - xs[0], 64.0), "沿一排走 2 格，屏幕 x 应移动 64px")


## 用例：沿 [code]gx[/code] 每走 1 格，屏幕 x 变化 [code]tile.x / 2[/code]、屏幕 y 变化 [code]tile.y / 2[/code]。
##
## @param helper 断言辅助
func _test_gx_step(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(Vector2.ZERO, Vector2(32, 16))
	var base := grid.to_screen(0, 0)
	var step_x := grid.to_screen(1, 0)
	var step_y := grid.to_screen(0, 1)
	helper._assert_true(is_equal_approx(step_x.x - base.x, 16.0), "沿 gx 走 1 格，屏幕 x 应 +16")
	helper._assert_true(is_equal_approx(step_x.y - base.y, 8.0), "沿 gx 走 1 格，屏幕 y 应 +8")
	helper._assert_true(is_equal_approx(step_y.x - base.x, -16.0), "沿 gy 走 1 格，屏幕 x 应 -16")
	helper._assert_true(is_equal_approx(step_y.y - base.y, 8.0), "沿 gy 走 1 格，屏幕 y 应 +8")


## 用例：菱形场地格数与深度排序。
##
## @param helper 断言辅助
func _test_diamond_cells(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(Vector2.ZERO, Vector2(32, 16))
	var radius := 3
	var cells := grid.diamond_cells(radius)
	# 半径为 r 的菱形（曼哈顿距离）格数 = 1 + 2r(r+1)
	var expected := 1 + 2 * radius * (radius + 1)
	helper._assert_eq(cells.size(), expected, "半径 %d 的菱形场地格数" % radius)

	var sorted_by_depth := true
	for i in cells.size() - 1:
		if grid.depth(cells[i].x, cells[i].y) > grid.depth(cells[i + 1].x, cells[i + 1].y):
			sorted_by_depth = false
			break
	helper._assert_true(sorted_by_depth, "场地格子应按深度升序排列，绘制顺序才对")

	var all_inside := true
	for cell in cells:
		if absi(cell.x) + absi(cell.y) > radius:
			all_inside = false
			break
	helper._assert_true(all_inside, "场地格子不应越出菱形边界")


## 用例：菱形顶点顺序为上、右、下、左。
##
## @param helper 断言辅助
func _test_diamond_points(helper: AssertHelper) -> void:
	var grid := IsoGrid.new(Vector2.ZERO, Vector2(32, 16))
	var points := grid.diamond_points()
	helper._assert_eq(points.size(), 4, "菱形应有四个顶点")
	helper._assert_eq(points[0], Vector2(0, -8), "第一点应为上顶点")
	helper._assert_eq(points[1], Vector2(16, 0), "第二点应为右顶点")
	helper._assert_eq(points[2], Vector2(0, 8), "第三点应为下顶点")
	helper._assert_eq(points[3], Vector2(-16, 0), "第四点应为左顶点")
