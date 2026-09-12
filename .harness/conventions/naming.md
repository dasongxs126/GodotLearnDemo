---
alwaysApply: true
---
# 命名规范与代码风格（Godot 4 / GDScript）

适用于本仓库全部 GDScript（`.gd`）、场景（`.tscn`）、资源（`.tres`、`.gdshader`）与项目配置（`project.godot`）。第三方目录 `addons/` 沿用上游风格，不强制改写。

## 代码风格

- 遵循 GDScript 官方风格与 Godot 编辑器默认格式，不做个人化排版。
- 使用 Tab 缩进（Godot 默认，与 `addons/` 现有代码一致），禁止空格与 Tab 混用；禁止行尾空格。
- 文件、函数之间保留一个空行；文件末尾保留一个换行。
- 保持 `extends` / `class_name` 在文件首部的常规位置，`@tool`、`@icon` 等注解写在其上方。
- 静态类型优先：参数、返回值、成员变量、信号参数一律显式标注类型，能用 `:=` 推断时不重复写类型。
- 每个 `.gd` 必须与 Godot 自动生成的同名 `.uid` 文件一起提交，禁止手工编辑 `.uid`，禁止单独删除。

## 命名规范

- 脚本文件、场景文件、资源文件使用 `snake_case.gd` / `.tscn` / `.tres`，文件名与 `class_name` 语义一致：`player_controller.gd` 声明 `class_name PlayerController`。
- `class_name` 使用 `PascalCase`；不注册全局名时省略 `class_name`，仅用 `extends`。
- 函数、成员变量、局部变量、常量名使用 `snake_case`。
- 常量使用 `CONSTANT_CASE`；私有成员与内部辅助函数使用 `_` 前缀（如 `_hp`、`_apply_gravity()`）。
- `@export` 变量使用 `snake_case`，命名面向策划与编辑器使用者，避免 `m_`、`tmp`、`data1` 一类无意义前缀。
- 信号使用完成时态的 `snake_case`：`health_changed`、`wave_cleared`、`save_completed`；信号回调函数使用 `_on_<节点>_<信号>`，例如 `_on_player_died`。
- 枚举类型与枚举常量使用 `PascalCase` 常量项：`enum Difficulty { EASY, HARD }`。
- 节点名使用 `PascalCase`：`PlayerSpawn`、`Ui/HealthBar`；场景根节点名与场景文件名语义对应（`player_controller.tscn` 根节点为 `PlayerController`）。
- 场景内导航路径写成常量或 `@export var xxx_path: NodePath`，不要在业务逻辑里散落硬编码的长路径字符串。
- Autoload 单例使用 `PascalCase` 且在 `project.godot` 的 `[autoload]` 中集中注册，例如 `SaveManager`、`AudioBus`。
- 输入动作（InputMap）使用 `snake_case`：`move_left`、`jump`、`open_inventory`；动作名不带键位信息（不写 `space_jump`）。
- 物理层、分组、碰撞掩码等在 `project.godot` 中命名字段时使用小写 `snake_case`，代码里通过常量引用层号，禁止裸写魔法数字。
- 资源与美术文件沿用现有前缀：`ic_*`（图标）、`bgm_*`、`sfx_*`、`tex_*`、`anim_*`、`mat_*`、`fx_*`。

## 场景与资源组织

- 场景文件与主脚本同名放置于同一目录，功能目录示例：`features/player/`、`features/ui/`、`core/save/`。
- 可复用单元做成独立 `.tscn` 并通过 `instance_scene` 实例化，禁止复制粘贴节点树。
- 跨场景引用一律使用 `res://` 绝对路径，禁止使用 `../` 相对路径跳出资源目录。
- 全局状态只通过 Autoload、信号或显式依赖传递，禁止用 `get_node("/root/...")` 随处抓取兄弟系统。

## 测试命名

- 单元与集成测试放在 `tests/`，场景与脚本使用 `test_<被测对象>.tscn` / `test_<被测对象>.gd`，例如 `test_inventory.gd`。
- 断言辅助函数放在 `tests/helpers/`，命名以 `_assert_` 开头。
- 手工验证场景放在 `playgrounds/`，目录内添加 `.gdignore` 之外的 `README.md` 说明用途，禁止把验证场景设为主场景。

## 文档语言

- `AGENTS.md`、`.harness/` 下规则文件、`README.md` 与 `task_plan.md`、`findings.md`、`progress.md` 等计划文档统一使用中文书写。
- 代码注释优先中文，Godot 关键字、类名、API 名、信号名、shader 术语保留英文原文。
