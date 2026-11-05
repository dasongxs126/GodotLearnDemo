# 文档索引

本目录分三块，各自由不同工具链维护：

| 目录 | 内容 | 维护方式 |
| --- | --- | --- |
| [`narrative/`](narrative/) | 《死寂之下》story 工程：世界观、角色、剧情、术语 | `story-skills`（`.agents/skills/`），校验用 `story check` |
| [`design/`](design/) | 游戏策划案：剧情落地、系统、美术需求 | `game-design` MCP 技能产出 |
| [`screenshots/`](screenshots/) | 原型与战斗场景截图（参考图，非美术资产） | 手工 |

## 权威边界

- **`narrative/` 是设定的唯一真相源**。世界规则、角色、历史、术语以它为准。
- **`design/` 只做派生**，把设定转成可开发的策划案；不重新定义世界观，冲突时回到 `narrative/` 修订。
- 策划案引用设定实体时，同时写 story 工程的 id 与中文名，例如「异力管制局（`magic-control-bureau`）」。

## 变更记录

- 文案/设定变更：[`CHANGELOG-narrative.md`](CHANGELOG-narrative.md)

## 版本与变更

- 世界观版本号记在 [`CHANGELOG-narrative.md`](CHANGELOG-narrative.md) 顶部，里程碑对应 commit hash。
- **不使用 git tag**：tag 指向整仓库快照，会与工程代码版本语义混淆；查历史用 `git log -- docs/narrative/`。

## 语言约定

- `docs/narrative/` 内的正文、标题、说明一律用中文。
- 以下内容由工具生成或解析，**保持英文**；改成中文后 `story reindex` 会重新追加英文小节，造成重复：
  - frontmatter 的键名与枚举值（`type`、`status` 等）
  - 注册表小节 `## Registry` 及表头
  - `story` 识别的固定标题：`## Synopsis`、`## World Overview`、`## Relationship Map`、`## Family Trees`、`## Story Structure`、`## Theme Tracking`
  - 注册表空态占位，例如 `*No chapters yet*`
