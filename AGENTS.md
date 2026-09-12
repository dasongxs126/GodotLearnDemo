# AGENTS.md — 规则路由

本仓库采用 harness 风格约束：本文件只做路由与摘要，具体规则存放在 `.harness/` 下。任何时候都以 `.harness/` 中的原文为准，本文件若与规则文件冲突，以规则文件为准。

## 项目概况

- Godot 4.7.2 stable（Forward Plus / Jolt Physics）2D+3D 工程，主语言 GDScript，`config_version=5`。
- 工程根：`res://` = 仓库根目录；已启用编辑器插件与 Autoload `MCPRuntime`（`addons/godot_mcp`）。
- 目录现状：业务代码尚未建立，只有 `addons/`（第三方，只读）、`project.godot`、`icon.svg`。新增代码按 `.harness/rules/godot-workflow.md` 的目录约定落地。
- 尚未设置 `run/main_scene`；测试入口通过 `--script` 指定继承 `SceneTree` 的脚本。

## 规则文件

| 规则文件 | 作用域 | 何时适用 |
| --- | --- | --- |
| `.harness/conventions/naming.md` | 全仓库 | 新建/重命名 `.gd`、`.tscn`、`.tres`、节点、信号、`@export`、Autoload、InputMap、物理层、测试与资源文件时 |
| `.harness/conventions/comment-rules.md` | 全仓库（`alwaysApply`，针对 `**/*.gd`） | 编写或修改任何 GDScript 的注释、文档注释、`TODO`/`FIXME` 时 |
| `.harness/rules/godot-workflow.md` | `.gd` / `.tscn` / `.tres` / `.gdshader` / `project.godot` | 改动场景与脚本、使用 Godot MCP 工具、执行验证与提交时 |

下表只记录现有规则文件。`.harness/` 下出现新目录或新规则文件时，以本文件“变更本套约束”一节为准同步更新本表。

## 必须遵守的核心约束（摘要）

1. 文档注释用 `##`，函数用 `@param` / `@return`，脚本头部带 `@author` 与 `@date yyyy-MM-dd`；函数内部注释用 `#` 且写在语句上方独占一行，禁止 `/* */`，禁止行尾注释。（详见 comment-rules）
2. 命名：文件 `snake_case.gd`，`class_name` 用 `PascalCase`，函数/变量 `snake_case`，私有成员 `_` 前缀，信号用完成时态（`health_changed`），节点名 `PascalCase`，InputMap 动作 `snake_case`。（详见 naming）
3. 改场景/脚本优先使用 Godot MCP 工具，多步改动合并为一次 `godot_batch_execute`；`addons/`、`.godot/`、`.uid` 不得改写。（详见 godot-workflow）
4. 改完必须验证：`godot_validate_script` 或 `godot --headless --path . --script res://<file>.gd --check-only`；资源增删改后跑 `godot --headless --path . --import`；行为改动跑 `run_scene` + `get_errors` + `query_runtime_node` + `take_screenshot` 闭环；`tests/` 下测试脚本退出码即结果。（详见 godot-workflow）
5. 不熟悉的引擎 API 先 `godot_classdb_query` 确认，禁止凭记忆编写 Godot 4 API；性能结论必须有 `get_performance_monitors` 前后数据。
6. 文档、计划文件（`task_plan.md` / `findings.md` / `progress.md`）与代码注释使用中文，Godot 类名、API、关键字保留英文。（详见 naming）

## 上下文与工具

- Godot MCP 配置见 `.mcp.json`（`godot-mcp-server@0.6.0`，lazy 启动）。不确定用哪个工具时先查 `godot_get_guide` / `godot_read_quick_tool_index_by_goal`，再调用。
- 项目约定、验证命令与已知工具限制集中在 `.harness/rules/godot-workflow.md` 第五节，遇到新的踩坑请追加到该节，不要只写在对话里。

## 变更本套约束

现有目录含义：`conventions/` 存放与具体文件类型无关、长期生效的全局约定；`rules/` 存放按文件类型（`globs:`）触发的操作规程。

- 新增跨语言/长期生效的规则：放进 `.harness/conventions/`，并在上面的“规则文件”表登记。
- 新增按文件类型触发的规则：放进 `.harness/rules/`，front matter 使用 `globs:` 声明触发范围。
- **确实不属于以上任一目录语义时，在 `.harness/` 下新建目录存放**，不要为塞进去而把无关主题混进现有文件，也不要在仓库根目录另起一套 `.rules/`、`docs/standards/` 之类的并行体系。可选语义示例：`architecture/`（架构与分层约束）、`workflows/`（联调、打包、发布等流程 SOP）、`domain/`（玩法与业务术语）、`knowledge/`（踩坑记录、引擎行为备忘）。
- 新建目录时同步做到：目录名用小写英文复数、名字直接表达主题；目录内放一个 `README.md` 说明边界与收录范围，避免后续规则误投；首个规则文件写清适用范围与检查清单；在本文件“规则文件”表登记一行（文件、作用域、何时适用）。
- 同一主题只保留一个规则文件；规则文件保持单一主题、中文书写、给出正例代码块与检查清单。
