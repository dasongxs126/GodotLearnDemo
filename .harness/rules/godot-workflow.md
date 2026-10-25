---
globs:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/*.gdshader"
  - "project.godot"
---
# Godot 工程与工具链约束

约束本仓库的目录结构、场景/脚本改动方式、MCP 使用边界与验证流程。命令均已在本仓库实测；本机可用的 Godot 可执行文件路径与版本见第五节。

## 一、工程事实

- 引擎：Godot 4.7.2 stable，渲染 `Forward Plus`，3D 物理 `Jolt Physics`，Windows 渲染后端 `d3d12`。
  本机可执行文件：`D:\SDK\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（`PATH` 上没有 `godot` 命令，需写全路径；批量校验可先 `GODOT="<上述路径>"`）。
- 项目配置：`project.godot`，版本 `config_version=5`；窗口 **1280×720**（= 战场内部绘制尺寸 640×360 的整数倍 2×），拉伸 `canvas_items` + `keep`。
- `run/main_scene` 指向 `res://playgrounds/battle_screen.tscn`（原型期的可玩入口）。改动主场景要**在回复里说明**，不要默默改。
- Autoload：`MCPRuntime`（`res://addons/godot_mcp/runtime/mcp_runtime.gd`），由 godot_mcp 插件维护，禁止删除或改名。
- 已启用编辑器插件：`res://addons/godot_mcp/plugin.cfg`。

## 二、目录与文件约束

- `addons/` 为第三方插件目录，只读。禁止修改 `res://addons/godot_mcp/**` 下的源码；确需写入时 MCP 会要求 `force=true`，未经用户明确要求不得使用。
- `.godot/` 是引擎缓存，已 gitignore，禁止提交、禁止手工编辑、禁止当作数据源读取。
- `.uid` 文件由引擎生成并与 `.gd` 一并提交，禁止手写或单独删除。
- `project.godot` 优先通过 MCP 的 `update_project_settings`、`configure_input_map`、`setup_autoload` 修改；只有 MCP 无法覆盖的字段才手工编辑，并在改动处注明原因。
- 新游戏代码放在 `features/`（玩法）、`core/`（存档、音频、事件总线、等距坐标换算等基础能力）、`tests/`（自动化测试）、`playgrounds/`（手工验证场景），不要平铺在 `res://` 根目录。
- `core/iso_grid.gd` 是**战斗与箱庭共用的等距坐标换算**（纯数学、`extends RefCounted`、不碰场景树）。改等距投影只改这一处，不要在场景脚本里另写一份公式。
- `tools/` 是**离线工具**（不进 Godot 运行时）：`process_art.py` / `mock_battle.py` / `compare_scale.py` 是 Python 美术处理脚本（`assets/raw/` 原始大图 → 游戏规格），`capture_screen.gd` 是 GDScript 离屏截图工具。跑法见 `docs/design/art_requirements.md` §八。
- `assets/` 是美术资源根目录：`raw/`（AI 原始大图，**已 `.gdignore`**）→ 处理后落到 `characters/`、`tiles/`、`backgrounds/`、`fx/`、`ui/`。**只有后四类进 Godot 资源管线**。
- `tmp_preview/` 是美术脚本的临时预览图，**已 `.gdignore` + gitignore**，禁止当作资源引用。
- 大文件、二进制资源（`.png`、`.ogg`、`.fbx`）不用 MCP `write_file` 写入，改用引擎导入流程或让用户手工放入。

### 像素风相关设置（已落地）

- `project.godot` 的 `[rendering] textures/canvas_textures/default_texture_filter=0`（**Nearest**）。
  像素风必需，否则低分辨率精灵放大后会糊。改动此值等于全局改观感，需在回复里说明。
- 美术处理脚本用独立 venv：`C:/Users/Administrator/.workbuddy-ai/binaries/python/envs/default/Scripts/python.exe`（Pillow 12.x）。
- **缩小 AI 大图必须用 LANCZOS（面积平均）**，用 NEAREST 等于每隔 N 像素抽 1 个 → 噪点。
- **纯几何图形（等距菱形 tile）不要交给 AI 画**，程序生成（见 `tools/process_art.py` → `_diamond()`）。

## 三、改动方式：MCP 优先

Godot 编辑器与 MCP 服务处于同一工程，改动优先走 MCP 工具，避免与编辑器内存状态不一致：

| 目标 | 工具 |
| --- | --- |
| 新建/修改 GDScript | `godot_create_script` / `godot_edit_script` |
| 语法校验 | `godot_validate_script` |
| 建场景、增删改节点 | `godot_create_scene` / `godot_add_node` / `godot_remove_node` / `godot_move_node` / `godot_rename_node` |
| 改属性（单个/批量） | `godot_modify_node_property` / `godot_set_node_properties` |
| 挂载脚本、连接信号 | `godot_attach_script` / `godot_connect_signal` / `godot_list_signal_connections` |
| 运行时探查与驱动 | `godot_run_scene` / `godot_query_runtime_node` / `godot_send_input` / `godot_call_method` / `godot_take_screenshot` |
| 报错与日志 | `godot_get_errors` / `godot_get_console_log` / `godot_get_runtime_log` |
| 不熟悉的引擎 API | `godot_classdb_query`（先查再写，禁止凭记忆猜 API） |

- 同一场景/脚本的多次改动合并成一次 `godot_batch_execute`（默认 `atomic=true`），失败可用 `godot_mcp_undo` 整体回滚。
- 破坏性操作（`delete_file`、`delete_folder`、`queue_free`、`set_script`、`remove_child`、`replace_by`、`reparent`）必须显式 `confirm=true`，只在用户明确要求删除时使用。
- 直接读写文件（`read` / `edit` / `write`）适用于 `.md`、`.json`、`.gdshader`、`.gitignore` 等非场景文件；`.tscn` 尽量不手改文本。
- 若用户正在编辑器中打开相关场景，改动前先 `godot_scene_tree_dump` 确认存在未保存的编辑，避免覆盖用户改动。

## 四、验证流程（必做）

改完代码不等于完成任务。按改动类型执行下列验证，并把结果写进回复：

1. **GDScript 语法/解析**：MCP 可用时用 `godot_validate_script`；否则用 CLI 逐文件校验（失败退出码非 0）：

   ```bash
   godot --headless --path . --script res://path/to/file.gd --check-only
   ```

2. **资源与引用同步**：涉及新增/重命名/删除脚本、场景、资源后执行导入刷新，确认无新增报错：

   ```bash
   godot --headless --path . --import
   ```

3. **运行验证**：MCP 可用时按最小闭环执行

   `godot_run_scene({ wait_for_runtime: true })` → `godot_get_errors` → `godot_send_input` + `godot_wait` → `godot_query_runtime_node` → `godot_take_screenshot` → `godot_get_errors` → `godot_stop_scene`。

   运行前后都要看 `godot_get_errors`；性能相关改动再用 `godot_get_performance_monitors` 给出前后数值对比，无数据不得声称“更流畅”。
4. **自动化测试**：`tests/` 下的测试脚本继承 `SceneTree`，在 `_initialize()` 中断言并 `quit(exit_code)`：

   ```bash
   godot --headless --path . --script res://tests/test_inventory.gd   # 0 通过，非 0 失败
   ```

   断言失败必须用 `push_error` 输出可定位信息，禁止只 `quit(1)` 不给原因。

   **输入链路测试要跑两遍**——`tests/test_battle_input.gd` 覆盖"事件真能穿过引擎路由到达场景"，
   其中鼠标用例在无头下必然跳过（见第五节），必须在真实窗口下补跑一次：

   ```bash
   godot --headless --path . --script res://tests/test_battle_input.gd          # 几何 / 提示 / 键盘路由
   godot --path . --resolution 1920x1080 --script res://tests/test_battle_input.gd   # 追加鼠标路由
   ```

   分辨率**故意取非 1280×720**：窗口等于基准尺寸时 `get_final_transform()` 是单位矩阵，
   坐标换算的 bug 会被掩盖掉。
5. **无法验证时**：明确说明未验证项与原因（无显示环境、缺资源、需要人工操作等），不得默认“应该没问题”。

## 五、已知工具链限制

- `godot --headless --path . --quit` 与 `--quit-after <N>` 实测均可正常退出（退出码 0）；早期记录的"挂住"是在 `run/main_scene` 未设置时出现的，设了主场景后不复现。需要"只加载一次"的场合仍推荐用 `--import` 或 `--script` 入口脚本自行 `quit()`。
- `godot_get_console_log` 不包含 Debugger 的 Errors 面板内容；运行期 `push_error` 常只出现在 `godot_get_errors`，两者都要查。
- `godot_take_screenshot` / `godot_send_input` 依赖 `MCPRuntime`，必须先 `godot_run_scene({ wait_for_runtime: true })`，否则报 “Runtime helper not connected”。
- 编辑器模式下的 `godot_call_method` 不能调用非 `@tool` 脚本的自定义方法；驱动游戏逻辑需要 `runtime: true` 且游戏正在运行。
- `godot_call_method` 对含 `await` 的方法是 fire-and-forget，返回值不可靠；用 `godot_wait` + `godot_query_runtime_node` 观察结果。
- 本机未安装 `gdlint` / `gdformat`，风格依靠编辑器默认格式与本规范约束，不要假设存在 Lint 命令。
- **引擎路径**：`PATH` 与 `~/.local/bin/` 下都没有 `godot` 命令，必须写全路径。当前用
  `D:\SDK\Godot\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（4.7.2，与工程声明一致）。
  同目录下还有 4.5.1（`Godot_v4.5.1-stable_win64.exe\...`）与 4.5（`D:\Program Files\Godot\...`）两个旧版本，不要误用。
  4.7.2 跑 `--check-only` / `--import` / `--script` 实测可用，且**不会改写 `project.godot`**（每次跑完用 `git status` 复核即可）。
- **`class_name` 需要先导入**：新增 `.gd` 后直接 `--script ... --check-only` 会报 `Identifier not found` 或 `Could not find type "X" in the current scope`，因为全局类还没进 `.godot/global_script_class_cache.cfg`。先跑一次 `--import` 再校验。
- **枚举不能作为返回类型**：`static func f() -> Side` 而 `return Side.X` 会报 `Cannot return a value of type "X.Side" as "Side"`。4.5.1 与 4.7.2 均实测如此，属 GDScript 现状而非版本问题。返回枚举值时把返回类型声明为 `int`，在文档注释里写 `取 [enum X]`。
- **无头下的 `RichTextLabel`**：`text` 与 `get_line_count()` 依赖布局完成，无头运行时读不到 `append_text()` 写入的内容（`get_line_count()` 恒为 0）。无头断言请改用 `get_parsed_text()`；需要按行数截断日志时自行计数，不要依赖 `get_line_count()`。
- **MCP 可能未挂载**：会话工具列表里没有 `godot_*` 时，按第三节的降级路径走——用文件写入改 `.gd` / `.tscn`，用 CLI 做校验，并在回复里说明未走 MCP 的原因。
- **无头驱动场景**：`SceneTree._initialize()` 里可以 `await`。引擎对 `_initialize` 是动态调用，不会触发"coroutine must be awaited"的编译错误，所以 `func _initialize() -> void: await _run()` 是合法写法，`_run()` 里 `await process_frame` 两次后界面 `_ready()` 才会跑完。注意 `_initialize()` 执行时 `root.is_inside_tree()` 仍是 `false`，此时 `root.get_child_count()` 不含尚未 `_ready` 的节点，别用它做断言。
- **`preload(...).instantiate()` 的类型是 Variant**：`preload` 静态返回 `Resource`，`instantiate()` 解析不到，整条表达式退化为 Variant。需要静态类型时写 `preload("res://x.tscn").instantiate() as XClass`。
- **从 Variant 推断类型是"警告即错误"**：`var x := await 协程()`、`var x := 某个返回 Variant 的调用` 会报 `The variable type is being inferred from a Variant value`。改成显式标注：`var x: BattleScreen = await _spawn()`。`await` 的静态返回类型一律是 Variant，凡是用 `:=` 接 `await` 的都要改。
- **离屏截图**：`--headless` 用空渲染器，拿不到图像。要截图就**不加** `--headless`，并显式给分辨率：
  `"$GODOT" --path . --resolution 1280x800 --script <截图脚本>`；脚本内 `await RenderingServer.frame_post_draw` 后 `root.get_texture().get_image().save_png("res://x.png")`。本机有可用的 D3D12 设备（RTX 3060），实测可出图。
- **界面自动化的取值口径**：无头断言控件文本用 `get_parsed_text()`；`Label.text` 可直接读；`RichTextLabel` 记得开 `bbcode_enabled = true`，否则 BBCode 标签会原样显示。
- **`PRESET_BOTTOM_WIDE` 不设高度就不显示**：`set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)` 只把锚点贴到底边，矩形高度仍是 0；此时只给 `custom_minimum_size` 会让它**从底边往下长**（跑出屏幕），结果是**整条面板根本不渲染**。必须显式给负的 `offset_top`：
  ```gdscript
  bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
  bar.offset_top = -BAR_HEIGHT
  bar.offset_bottom = 0.0
  ```
  `PRESET_TOP_WIDE` / `PRESET_RIGHT_WIDE` 没这个问题（增长方向朝屏幕内）。本项目踩过：底部弹刀规则条一度完全不可见。
- **Control 可以放进 Node2D**：`Label` / `ColorRect` 作为 `Node2D` 的子节点能正常渲染，用 `position` / `size` 直接定位即可（不套容器）。等距战场里的头顶血条与名字就是这么做的。
- **战场点击拾取要用 `event.position` + `get_global_transform_with_canvas()`，不要用 `Node2D.get_local_mouse_position()`**（本条曾在早期写成相反结论，**已实测证伪**）：
  - `get_local_mouse_position()` 读的是**全局鼠标状态**（`DisplayServer.mouse_get_position()`），**注入事件时对不上真实点位**，于是"点战场选目标"在自动化测试里永远测不出来——本项目踩过：真实输入链路一直没被覆盖，用户试玩才发现点不中。
  - 正确写法（`BattleScreen._to_field`）：
    ```gdscript
    func _to_field(viewport_pos: Vector2) -> Vector2:
        return _field.get_global_transform_with_canvas().affine_inverse() * viewport_pos
    ```
    用 `get_global_transform_with_canvas()` 而不是 `get_global_transform()`：前者含画布变换，跨视口才可靠。
  - **`Rect2.has_point()` 不含右/下边界**：判定矩形恰好等于精灵包围盒时，连"正好点在脚底"（`pos.y == rect.end.y`）都会落空。判定区要外扩几个像素（本项目 `UNIT_HIT_PADDING = 5`）。
  - 同一排单位在等距下**屏幕 y 完全相同**，外扩后的判定区会互相重叠；只按 y 决胜会退化成"谁先被字典遍历到"，必须再加一级"横向离点击点最近者胜"。
- **`--headless` 收不到鼠标事件**：空显示驱动下 `root.size` 被压成 64×64、`DisplayServer.window_get_size()` 为 (0, 0)，`Input.parse_input_event` 注入的**鼠标**事件到不了 `_unhandled_input`（**键盘事件不受影响**）。鼠标链路的自动化测试**必须在真实窗口下跑**（不加 `--headless`，加 `--resolution`），无头下应显式跳过并打印说明，不要假装通过。
- **`Input.parse_input_event` 注入鼠标要給"窗口坐标"，不是内容坐标**：注入的事件会被 `Viewport::_make_input_local` 按 `get_final_transform().affine_inverse()` 变换一次才到达 `_unhandled_input`。所以注入方要给**变换前**的坐标：
  ```gdscript
  var content_point: Vector2 = field.get_global_transform_with_canvas() * field_local_point
  var window_point: Vector2 = root.get_final_transform() * content_point
  event.position = window_point
  ```
  窗口正好 1280×720 时 `get_final_transform()` 是单位矩阵，给内容坐标也能过——**只有把窗口放大才会暴露**（实测 1920×1080 全偏）。
- **`root.size` 是窗口尺寸，不是 `content_scale_size`**：`stretch/mode="canvas_items"` 下 `root.canvas_transform` 是**单位矩阵**，缩放全在 `get_final_transform()` 里（1920×1080 实测 = `scale(1.4648, 1.4653) + origin(23, 0)`），`root.get_visible_rect()` 才是 1280×720。排查输入坐标问题时先打印这三个值，别凭直觉猜。
- **根 `Control` 要设 `mouse_filter = MOUSE_FILTER_IGNORE`** 才能让战场点击落到 `_unhandled_input`：`Control` 默认是 `STOP`，全屏的根节点会把所有鼠标事件吃掉。HUD 子面板保留默认 `STOP`，于是"点面板"与"点战场"天然分开，不需要手写矩形排除。
- **`_process` 驱动演出时不要用"跑够多少帧"做定位**：帧率不保证，且流程在玩家决策处会停住，同样的帧数落在完全不同的状态。要截图定格就显式设状态（本项目用 `BattleScreen._debug_hold_reaction(progress)`）。

## 六、把游戏跑起来给用户试玩

用户会说"跑起来让我体验一下"。**窗口是交付物**，所以进程必须在本次回答结束后继续活着。

- ✅ **正确做法**：用 Bash 工具的**后台任务**通道启动，**用非控制台版 exe**（少一个黑框）：
  ```bash
  "/d/SDK/Godot/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe" --path .
  ```
  启动后用 `tasklist //FI "IMAGENAME eq Godot*"` 确认进程与内存（几百 MB 说明窗口已渲染）。
- ❌ **不要用 `Start-Process`**（PowerShell 通道）：实测进程会随父进程一起被回收，`tasklist` 查不到，
  但游戏本身没问题——`timeout 15 godot --path .` 能稳定跑满 15 秒、退出码 124（被 timeout 杀），全程零报错。
  也就是说"起不来"是启动方式的问题，**不要误判成游戏崩了去改代码**。
- 试玩会话结束后（后台任务 completed）先看输出：只有引擎版本 + 显卡两行 = **干净跑完，没有运行时报错**，
  这本身是一条有效结论，可以写进回复。
- 用户关掉窗口后**不要自动重启**，先问；同时把启动命令留给他，万一窗口被回收可以自己起。

## 七、提交约束

- 提交前确认工作区不含 `.godot/`、`addons/godot_mcp/cache/`、临时验证场景与 `*.tmp` 残留。
- `.tscn`、`.tres`、`project.godot` 属于必需提交项；若改动由 MCP 触发，注意 `.uid` 是否一并生成。
- 提交信息说明：改动的场景/脚本、验证方式（`--import` / `--check-only` / 运行截图 / 测试退出码）与未覆盖项。
