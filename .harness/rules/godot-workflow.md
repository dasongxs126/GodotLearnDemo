---
globs:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/*.gdshader"
  - "project.godot"
---
# Godot 工程与工具链约束

约束本仓库的目录结构、场景/脚本改动方式、MCP 使用边界与验证流程。命令均已在本仓库（Godot 4.7.2 stable，`~/.local/bin/godot`）实测。

## 一、工程事实

- 引擎：Godot 4.7.2 stable，渲染 `Forward Plus`，3D 物理 `Jolt Physics`，Windows 渲染后端 `d3d12`。
- 项目配置：`project.godot`，版本 `config_version=5`；窗口拉伸 `canvas_items` + `expand`。
- 当前未设置 `run/main_scene`，主场景由任务显式指定，禁止为了跑通测试擅自修改主场景。
- Autoload：`MCPRuntime`（`res://addons/godot_mcp/runtime/mcp_runtime.gd`），由 godot_mcp 插件维护，禁止删除或改名。
- 已启用编辑器插件：`res://addons/godot_mcp/plugin.cfg`。

## 二、目录与文件约束

- `addons/` 为第三方插件目录，只读。禁止修改 `res://addons/godot_mcp/**` 下的源码；确需写入时 MCP 会要求 `force=true`，未经用户明确要求不得使用。
- `.godot/` 是引擎缓存，已 gitignore，禁止提交、禁止手工编辑、禁止当作数据源读取。
- `.uid` 文件由引擎生成并与 `.gd` 一并提交，禁止手写或单独删除。
- `project.godot` 优先通过 MCP 的 `update_project_settings`、`configure_input_map`、`setup_autoload` 修改；只有 MCP 无法覆盖的字段才手工编辑，并在改动处注明原因。
- 新游戏代码放在 `features/`（玩法）、`core/`（存档、音频、事件总线等基础能力）、`tests/`（自动化测试）、`playgrounds/`（手工验证场景），不要平铺在 `res://` 根目录。
- 大文件、二进制资源（`.png`、`.ogg`、`.fbx`）不用 MCP `write_file` 写入，改用引擎导入流程或让用户手工放入。

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
5. **无法验证时**：明确说明未验证项与原因（无显示环境、缺资源、需要人工操作等），不得默认“应该没问题”。

## 五、已知工具链限制

- `godot --headless --path . --quit` 与 `--quit-after` 在本工程会挂住直到超时；需要“只加载一次”的场合使用 `--import` 或 `--script` 入口脚本自行 `quit()`。
- `godot_get_console_log` 不包含 Debugger 的 Errors 面板内容；运行期 `push_error` 常只出现在 `godot_get_errors`，两者都要查。
- `godot_take_screenshot` / `godot_send_input` 依赖 `MCPRuntime`，必须先 `godot_run_scene({ wait_for_runtime: true })`，否则报 “Runtime helper not connected”。
- 编辑器模式下的 `godot_call_method` 不能调用非 `@tool` 脚本的自定义方法；驱动游戏逻辑需要 `runtime: true` 且游戏正在运行。
- `godot_call_method` 对含 `await` 的方法是 fire-and-forget，返回值不可靠；用 `godot_wait` + `godot_query_runtime_node` 观察结果。
- 本机未安装 `gdlint` / `gdformat`，风格依靠编辑器默认格式与本规范约束，不要假设存在 Lint 命令。

## 六、提交约束

- 提交前确认工作区不含 `.godot/`、`addons/godot_mcp/cache/`、临时验证场景与 `*.tmp` 残留。
- `.tscn`、`.tres`、`project.godot` 属于必需提交项；若改动由 MCP 触发，注意 `.uid` 是否一并生成。
- 提交信息说明：改动的场景/脚本、验证方式（`--import` / `--check-only` / 运行截图 / 测试退出码）与未覆盖项。
