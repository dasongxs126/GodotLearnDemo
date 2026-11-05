---
globs:
  - "docs/**"
---
# 文档、叙事与策划案约束

约束 `docs/` 下全部 Markdown 产物：哪类内容由哪套工具产出、落到哪个目录、用什么语言、交付前必须通过哪些校验。

## 一、工具分工（强制）

| 内容类型 | 必须使用的工具 | 产物目录 |
| --- | --- | --- |
| 世界观、角色、势力、术语、历史时间线、故事线、剧本、章节与场景文本 | story-skills（`.agents/skills/`，项目级） | `docs/narrative/` |
| 玩法、系统、战斗、关卡、数值、剧情落地（任务文本 / 对白）、美术需求、QA 用例、技术实现规范 | `game-design` MCP（`mcp__game-design__*`） | `docs/design/` |

- 禁止用 `game-design` MCP 产出世界观、角色、故事设定；禁止用 story-skills 设计玩法、数值、关卡。
- `docs/narrative/` 是设定的**唯一真相源**。`docs/design/` 只做派生：不新增世界观事实；发现设定缺口时先改 narrative，再改策划案。
- 两侧都不负责的代码实现，按 `.harness/rules/godot-workflow.md` 执行。
- 交付说明里必须写明用了哪套工具与哪个技能（story 技能名，或 `game-design` 的技能名），便于复查。

## 二、语言（强制）

- `docs/` 下所有 Markdown 产物正文使用**中文**。
- 只有以下内容允许英文：
  1. 明确的专有名词、API、类名、文件名、命令、配置键；
  2. story 工程中由工具生成或解析的结构：frontmatter 键与枚举值、`## Registry` 及表头、`## Synopsis`、`## World Overview`、`## Relationship Map`、`## Family Trees`、`## Story Structure`、`## Theme Tracking`、注册表空态占位（如 `*No chapters yet*`）；
  3. 代码块、路径、命令行输出。
- 禁止：整段英文叙述、英文模板占位（如 `Summarize the system...`）、无意义的中英重复。
- 标点使用全角（代码块、路径、命令内除外）；中文与英文术语之间不额外加空格。

## 三、story 工程操作规程

工程根为 `docs/narrative/`，遵循 story-skills 的 `schema-version: 2` 模型。

- **开工**：读 `story.md`、`continuity/questions/_index.md`、`worldbuilding/_index.md`，然后跑 `story check docs/narrative`。
- **登记未决项**：世界观/剧情中尚未拍板的内容必须写成 `continuity/questions/` 条目（`story add question`），不得只留在正文或对话里。
- **新增或改名实体**：先建实体，再 `story reindex docs/narrative`，最后 `story check docs/narrative`；两者退出码为 0 才算完成。
- **禁止手工编辑** `_index.md` 的注册表行；禁止在工程根放交接文件（会触发 `stray-file` 警告），交接信息写 `docs/README.md`。
- **大改前**：`story snapshot <标签>`；**改动后**：在 `docs/CHANGELOG-narrative.md` 记录版本、决策与对应提交。
- **状态诚实**：未定稿的内容标注「工作基线（可修订）」，不得宣称「定稿」。
- 需要的能力若未安装（如某技能不存在），明确说明并停在该步骤，不得编造流程。

## 四、策划案工程操作规程

- 目录固定为 `docs/design/game-narrative/`、`game-system/`、`game-art/`、`game-qa/`；整合稿为 `docs/design/GDD.md`。
- 每个文档开头标注来源与依据：

  ```markdown
  > 来源技能：`game-narrative-design`
  > 依据：`docs/narrative/`（story 工程）
  ```

- 引用设定实体时使用「中文名（id）」格式，例如 `异力管制局（magic-control-bureau）`。
- 不复制设定原文，只引用；需要展开时链接到 `docs/narrative/` 对应文件。
- `docs/design/` 只放 Markdown。截图与概念图放 `docs/screenshots/`，游戏内资产放 `assets/`。

## 五、交付前检查清单

- [ ] 内容类型与工具匹配（叙事 vs 游戏内），产物在正确目录
- [ ] 正文为中文，无英文模板或整段英文（允许项除外）
- [ ] `story check docs/narrative` 为 0 错误
- [ ] 注册表未被手工修改，`reindex` 已执行
- [ ] 未决事项已登记到 `continuity/questions/`
- [ ] 引用格式为「中文名（id）」
- [ ] `docs/CHANGELOG-narrative.md` 已记录本次变更

## 六、正例与反例

**正例**

```markdown
> 来源技能：`game-system-design`
> 依据：`docs/narrative/`（异力体系 `magic`）

战斗资源循环沿用「异力管制局（magic-control-bureau）」的登记制度，
玩家每次施法需完成一次登记豁免判定。
```

**反例**

- 用 `game-design` 直接生成「七座巨构的完整历史」——属于世界观，应走 story-skills。
- 在 `docs/design/` 里新造一个势力——违反唯一真相源。
- 在 `docs/narrative/` 里写英文占位段落，等以后翻译。
- 手工往 `characters/_index.md` 加一行注册表——会被 `story reindex` 覆盖。
