# skill-creator 技能使用指南

> **用途**: 创建、改进和测试新的 Agent Skills  
> **来源**: Anthropic 官方 (github.com/anthropics/skills/skills/skill-creator/)  
> **安装**: `npx skills add https://github.com/anthropics/skills --skill skill-creator`

---

## 🎯 触发方式

当你想创建或修改技能时，直接告诉 Claude：

```
"帮我创建一个技能，用于..."
"改进现有的 xxx 技能"
"测试我的技能效果如何"
"优化这个技能的触发描述"
```

---

## 📋 完整工作流程

```
┌─────────────────────────────────────────────────────────┐
│  skill-creator 核心流程                                  │
├─────────────────────────────────────────────────────────┤
│  1. 意图捕获 → 了解你想让技能做什么                      │
│  2. 访谈研究 → 询问边界情况、输入输出格式、成功标准      │
│  3. 编写 SKILL.md → 创建技能文档                         │
│  4. 测试用例 → 生成 2-3 个真实测试提示                    │
│  5. 运行评估 → 并行执行 with-skill 和 baseline 测试       │
│  6. 审查结果 → 浏览器查看器展示定性和定量结果            │
│  7. 迭代改进 → 根据反馈修改技能                          │
│  8. 描述优化 → 自动优化触发准确率                        │
│  9. 打包发布 → 生成 .skill 文件                          │
└─────────────────────────────────────────────────────────┘
```

---

## 💡 实际使用示例

### 创建新技能

```
"帮我创建一个技能，用于将 Markdown 转换为 PDF 报告"
"我需要一个技能来处理 Excel 数据并生成图表"
"创建一个技能，用于生成 API 文档"
```

### 改进现有技能

```
"我的 writing-voice 技能总是忽略段落长度，帮我改进"
"这个技能在处理大文件时太慢了，优化一下"
"技能描述不够准确，帮我优化触发描述"
```

### 测试技能

```
"运行测试看看这个技能的效果如何"
"对比新旧版本的技能表现"
"生成评估报告"
```

---

## 🔧 关键特性

| 特性 | 说明 |
|------|------|
| **并行测试** | 同时运行 with-skill 和 baseline (无技能) 对比 |
| **浏览器查看器** | HTML 界面展示测试结果和反馈 |
| **基准对比** | pass rate、耗时、token 用量统计 |
| **描述优化** | 自动优化 YAML frontmatter 的 description 字段 |
| **迭代循环** | 支持多轮改进直到满意 |

---

## 🛠️ 核心命令

### 运行测试循环

```bash
python -m scripts.run_loop \
  --eval-set <path-to-eval.json> \
  --skill-path <path-to-skill> \
  --model <model-id> \
  --max-iterations 5
```

### 生成审查界面

```bash
python -m scripts.generate_review.py \
  <workspace>/iteration-1 \
  --skill-name "my-skill" \
  --benchmark <workspace>/iteration-1/benchmark.json
```

### 打包技能

```bash
python -m scripts.package_skill <path/to/skill-folder>
```

---

## 📁 技能目录结构

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown instructions
└── Bundled Resources (optional)
    ├── scripts/    - Executable code for deterministic/repetitive tasks
    ├── references/ - Docs loaded into context as needed
    └── assets/     - Files used in output (templates, icons, fonts)
```

---

## ⚠️ 注意事项

### 测试用例设计
- 测试用例需要是**真实用户会说的话**，不要抽象
- 示例：
  - ❌ 坏：`"Format this data"`
  - ✅ 好：`"ok so my boss just sent me this xlsx file (its in my downloads, called something like 'Q4 sales final FINAL v2.xlsx') and she wants me to add a column that shows the profit margin as a percentage"`

### 描述优化
- 描述优化前需要先生成 20 个触发评估查询
- 包含 should-trigger (8-10) 和 should-not-trigger (8-10)
- 避免过于明显的负面测试用例

### 环境适配
- **Cowork 环境**: 使用 `--static` 生成 HTML 文件而非启动服务器
- **Claude.ai**: 无子 agent 支持，跳过基准对比
- **无显示环境**: 使用 `--static <output_path>` 输出静态 HTML

### 写作风格
- 描述中避免使用 `ALWAYS`/`NEVER` 大写（黄色警告）
- 解释**为什么**要做某事，而非只是指令
- 保持技能文档 < 500 行

---

## 📊 评估数据结构

### evals/evals.json

```json
{
  "skill_name": "example-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "User's task prompt",
      "expected_output": "Description of expected result",
      "files": [],
      "assertions": []
    }
  ]
}
```

### 触发评估查询

```json
[
  {"query": "the user prompt", "should_trigger": true},
  {"query": "another prompt", "should_trigger": false}
]
```

---

## 🔗 相关资源

- **官方仓库**: https://github.com/anthropics/skills
- **技能市场**: https://skills.sh/
- **评测查看器**: `eval-viewer/generate_review.py`
- **Grader 指南**: `agents/grader.md`
- **Analyzer 指南**: `agents/analyzer.md`

---

*最后更新：2026-03-23*
