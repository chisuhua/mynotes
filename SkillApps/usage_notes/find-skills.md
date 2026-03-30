# find-skills 技能使用指南

> **用途**: 帮助用户发现和安装现有的 Agent Skills  
> **来源**: Anthropic 生态系统  
> **安装**: `npx skills add https://github.com/anthropics/skills --skill find-skills`

---

## 🎯 触发方式

当你询问以下类型的问题时自动触发：

```
"如何做 X？"
"有技能可以做 X 吗？"
"找一个 X 的技能"
"能帮我做 X 吗？" (X 是 specialized capability)
"我想扩展 agent 的能力"
```

---

## 📋 完整工作流程

```
┌─────────────────────────────────────────────────────────┐
│  find-skills 核心流程                                    │
├─────────────────────────────────────────────────────────┤
│  1. 理解需求 → 识别领域、具体任务、是否可能有技能        │
│  2. 查看排行榜 → 先检查 https://skills.sh/ 热门技能     │
│  3. 搜索技能 → 运行 npx skills find [query]             │
│  4. 验证质量 → 检查安装数、来源、GitHub stars           │
│  5. 呈现选项 → 向用户展示技能信息和安装命令              │
│  6. 协助安装 → 执行 npx skills add <package>            │
└─────────────────────────────────────────────────────────┘
```

---

## 💡 实际使用示例

### 搜索技能

```bash
# React 性能优化
"如何优化我的 React 应用性能？"
→ 自动触发 → npx skills find react performance

# PR 审查
"有技能可以帮我审查 Pull Request 吗？"
→ 自动触发 → npx skills find pr review

# Changelog 生成
"我需要一个生成 changelog 的技能"
→ 自动触发 → npx skills find changelog

# 测试技能
"帮我找 E2E 测试的技能"
→ 自动触发 → npx skills find e2e testing playwright
```

---

## 🔍 搜索技巧

### 常见技能类别

| 类别 | 示例查询 |
|------|---------|
| **Web 开发** | `react`, `nextjs`, `typescript`, `css`, `tailwind` |
| **测试** | `testing`, `jest`, `playwright`, `e2e`, `vitest` |
| **DevOps** | `deploy`, `docker`, `kubernetes`, `ci-cd`, `github-actions` |
| **文档** | `docs`, `readme`, `changelog`, `api-docs`, `swagger` |
| **代码质量** | `review`, `lint`, `refactor`, `best-practices` |
| **设计** | `ui`, `ux`, `design-system`, `accessibility`, `figma` |
| **生产力** | `workflow`, `automation`, `git`, `notion` |
| **数据处理** | `excel`, `csv`, `json`, `sql`, `pandas` |
| **AI/ML** | `embedding`, `rag`, `vector`, `llm`, `prompt` |

### 搜索建议

1. **使用具体关键词**: `"react testing"` 比 `"testing"` 更好
2. **尝试替代词**: 如果 `"deploy"` 没结果，试试 `"deployment"` 或 `"ci-cd"`
3. **检查热门来源**: 
   - `vercel-labs/agent-skills`
   - `anthropics/skills`
   - `microsoft/skills`
   - `ComposioHQ/awesome-claude-skills`

---

## ✅ 质量验证清单

**推荐前必须验证**：

| 检查项 | 标准 |
|--------|------|
| **安装数** | > 1K (谨慎 < 100) |
| **来源声誉** | 官方来源优先 (`vercel-labs`, `anthropics`, `microsoft`) |
| **GitHub stars** | > 100 stars |
| **最近更新** | 6 个月内有更新 |
| **文档完整** | 有 README 和使用示例 |

---

## 🛠️ 核心命令

### 搜索技能

```bash
# 交互式搜索
npx skills find

# 关键词搜索
npx skills find [query]

# 示例
npx skills find react performance
npx skills find pr review
npx skills find changelog
```

### 安装技能

```bash
# 全局安装 (推荐)
npx skills add <owner/repo@skill> -g -y

# 项目级安装
npx skills add <owner/repo@skill>

# 安装特定技能
npx skills add vercel-labs/agent-skills --skill react-best-practices

# 安装多个技能
npx skills add vercel-labs/agent-skills --skill react --skill nextjs

# 列出仓库中的技能
npx skills add <owner/repo> --list
```

### 检查更新

```bash
# 检查技能更新
npx skills check

# 更新所有技能
npx skills update

# 更新特定技能
npx skills update <skill-name>
```

### 初始化新技能

```bash
# 创建新技能模板
npx skills init my-skill-name
```

---

## 📦 推荐技能列表

### 官方技能 (Anthropic)

| 技能 | 描述 | 安装数 |
|------|------|--------|
| `frontend-design` | 前端设计和 UI 组件 | 100K+ |
| `docx` | Word 文档处理 | 100K+ |
| `pdf` | PDF 文件处理 | 100K+ |
| `xlsx` | Excel 电子表格 | 100K+ |
| `mcp-builder` | MCP 服务器构建 | 50K+ |
| `webapp-testing` | Web 应用测试 | 50K+ |

### Vercel 技能

| 技能 | 描述 | 安装数 |
|------|------|--------|
| `react-best-practices` | React 最佳实践 | 185K+ |
| `nextjs-patterns` | Next.js 模式 | 150K+ |
| `typescript-expert` | TypeScript 专家 | 120K+ |

### 社区技能

| 技能 | 来源 | 描述 |
|------|------|------|
| `systematic-debugging` | obra/superpowers | 系统化调试 |
| `test-driven-development` | obra/superpowers | TDD 工作流 |
| `brainstorming` | obra/superpowers | 头脑风暴 |

---

## 🎯 响应示例

### 找到技能

```
我找到了一个可能对你有帮助的技能！

**技能名称**: react-best-practices
**描述**: React 和 Next.js 性能优化指南 (来自 Vercel 工程团队)
**安装数**: 185K
**来源**: vercel-labs/agent-skills

安装命令:
npx skills add vercel-labs/agent-skills@react-best-practices -g -y

了解更多: https://skills.sh/vercel-labs/agent-skills/react-best-practices
```

### 未找到技能

```
我搜索了 "xyz" 相关的技能，但没有找到匹配的结果。

不过我仍然可以直接帮你完成这个任务！你想要我继续吗？

如果这是你经常需要做的事情，你可以创建自己的技能:
npx skills init my-xyz-skill
```

---

## 🌐 技能市场

| 网站 | URL | 技能数量 |
|------|-----|---------|
| **skills.sh** | https://skills.sh | Vercel 维护，40+ agents |
| **ClaudeSkills.info** | https://claudeskills.info | 658+ curated |
| **Tessl Registry** | https://tessl.io/registry | 2000+ evaluated |
| **MCP Market** | https://mcpmarket.com/tools/skills | 66000+ directory |

---

## ⚠️ 注意事项

### 推荐原则
- 不要仅基于搜索结果推荐技能
- 必须验证安装数、来源、GitHub stars
- 对于安装数 < 100 的技能保持谨慎
- 优先推荐官方来源的技能

### 安装建议
- 使用 `-g` 标志全局安装（用户级别）
- 使用 `-y` 跳过确认提示
- 项目级技能放入 `./skills/` 目录
- 全局技能放入 `~/.agents/skills/` 或 `~/.claude/skills/`

### 当没有现成技能时
1. 承认没有现有技能
2. 提供直接帮助完成任务
3. 建议用户创建自己的技能 (`npx skills init`)
4. 或者使用 `skill-creator` 帮助创建

---

## 🔗 相关资源

- **技能市场**: https://skills.sh/
- **官方仓库**: https://github.com/anthropics/skills
- **Vercel 技能**: https://github.com/vercel-labs/skills
- **技能文档**: https://skills.sh/docs

---

*最后更新：2026-03-23*
