基于这篇文章，我为你拆解一个可直接落地的完整操作实例——以"用户积分查询接口"为例，展示从需求到交付的全流程：

---

 阶段一：项目初始化与文档准备
 Step 1: 创建项目地图 AGENTS.md
在仓库根目录创建，作为 Agent 的"入职手册"：
# AGENTS.md

## 项目结构
- /api: 接口层 (FastAPI)
- /service: 业务逻辑层
- /repository: 数据访问层 (SQLAlchemy)
- /tests: 测试目录

## 常用命令
- 启动: `make run`
- 测试: `make test`
- 类型检查: `make type-check`

## 变更约束（硬性规则）
- ❌ 禁止直接改动 /infra 目录
- ✅ 所有接口变更必须同步更新 /docs/api/
- ✅ 涉及数据库变更必须附迁移脚本（Alembic）
- ✅ 错误码必须按 ErrorCode-{模块}-{序号} 格式定义

## Definition of Done（验收标准）
1. 单元测试覆盖率 > 80%
2. 接口文档包含请求/响应示例
3. CHANGELOG.md 记录变更
4. 代码通过 mypy 类型检查


---

 Step 2: 编写需求合同 SPEC.md
# SPEC: 用户积分查询接口

## 目标
实现查询用户积分余额的 RESTful 接口，支持并发访问。

## 输入
- user_id: string (UUID 格式)
- include_expired: boolean (可选, 默认 false)

## 输出
```json
{
  "user_id": "uuid-string",
  "points": 1500,
  "expired_points": 200,
  "last_updated": "2024-01-15T10:30:00Z",
  "currency": "CNY"
}

 业务规则
- 积分为 0 时返回 200（非 404）
- 敏感操作需记录审计日志
- 响应时间 P99 < 100ms
 验收标准
- - [ ] 单测覆盖正常/异常/边界情况
- - [ ] 接口文档含错误码表
- - [ ] 压力测试通过（1000 QPS）

---

## 阶段二：Skill 固化（可复用能力）

### Step 3: 创建 Skill 目录结构

```bash
mkdir -p .opencode/skills/api-contract
touch .opencode/skills/api-contract/SKILL.md

 Step 4: 编写 SKILL.md
---
name: api-contract
description: 根据 SPEC.md 生成接口设计文档并检查边界
license: MIT
compatibility: opencode
---

## Inputs
- SPEC.md
- 现有 API 文档目录结构

## Tasks（执行步骤）
1. 读取 SPEC.md，提取输入输出与业务约束
2. 生成接口说明（路径、方法、参数、响应结构）
3. 生成成功/失败示例（含 curl 命令）
4. 检查清单：
   - [ ] 幂等性说明
   - [ ] 错误码定义（4xx/5xx）
   - [ ] 鉴权要求（JWT/AK）
   - [ ] 限流策略（QPS 限制）
   - [ ] 兼容性影响（Breaking Change 标注）

## Outputs
- docs/api/user-points.md（接口文档）
- docs/error-codes.md（错误码表更新）
- CHANGELOG.md（接口变更摘要）

## Acceptance Criteria（自我验证）
- 文档必须包含 JSON Schema
- 必须标注废弃字段（如有）
- 必须包含兼容性影响分析


---

 阶段三：多智能体协作执行（OmO 模式）
 Step 5: 启动 OpenCode 并触发多智能体流程
# 在项目根目录启动
opencode

OmO 角色分工与指令触发：
角色	触发方式	执行指令	输出产物
Planner (Prometheus)	Tab 键	分析 SPEC.md，生成任务清单	WORK_PLAN.md
Implementer (Hephaestus)	选中代码块	/start-work	代码变更
Tester (Atlas)	命令行	补全测试用例	test_user_points.py
Doc Writer	Skill 调用	skill({name: "api-contract"})	API 文档更新
具体操作流程：
1. Prometheus 规划阶段（按 Tab 键激活）：用户输入：实现积分查询接口

Prometheus 输出 WORK_PLAN.md：
---
tasks:
  - id: 1
    desc: 创建 Repository 层（数据库查询）
    assignee: implementer
    deps: []
   验收: 单测通过

  - id: 2
    desc: 实现 Service 层（业务逻辑）
    assignee: implementer
    deps: [1]
   验收: 逻辑正确

  - id: 3
    desc: 编写 API 层（FastAPI 路由）
    assignee: implementer
    deps: [2]
   验收: 接口契约符合 SPEC

  - id: 4
    desc: 生成接口文档
    assignee: doc-writer
    deps: [3]
   验收: skill(api-contract) 通过

  - id: 5
    desc: 集成测试与回归
    assignee: tester
    deps: [3]
   验收: 1000 QPS 压测通过

2. Hephaestus 编码阶段（自动激活）：- 读取 WORK_PLAN.md，按依赖顺序执行
- 每完成一个 Task，自动调用 git diff 生成变更摘要
- 若遇到编译错误，自动重试（Ralph Loop 机制）
3. Atlas 并行验证（后台执行）：# Atlas 自动执行
pytest tests/ -v --cov=service
# 若失败，回写错误日志到 WORK_PLAN.md 的 blockers 字段


---

 阶段四：Eval 回归验证
 Step 6: 建立最小 Eval 集
创建目录 /eval：
eval/
├── cases.json          # 测试用例
├── expected.json       # 期望输出
├── run.sh             # 回归脚本
└── prompts/           # Prompt 版本控制
    └── v1.0/
        └── planner-prompt.md

cases.json 示例：
[
  {
    "id": "points-normal",
    "input": {"user_id": "uuid-123", "include_expired": false},
    "expected": {"points": 1500, "status": 200},
    "check": ["points >= 0", "response_time < 100ms"]
  },
  {
    "id": "points-zero",
    "input": {"user_id": "uuid-empty", "include_expired": true},
    "expected": {"points": 0, "status": 200},
    "check": ["not 404", "expired_points == 0"]
  },
  {
    "id": "invalid-uuid",
    "input": {"user_id": "bad-id"},
    "expected": {"status": 400, "error_code": "E-USER-001"},
    "check": ["error_code matches pattern"]
  }
]

run.sh 回归脚本：
#!/bin/bash
# 每次变更 Skill 或 Prompt 后执行

echo "Running Eval Suite..."

# 1. 启动服务
make run & 
PID=$!

# 2. 运行测试
pytest eval/cases.json --json-report -o report-file=eval/result.json

# 3. 检查回归
python -c "
import json
with open('eval/result.json') as f:
    result = json.load(f)
    if result['summary']['failed'] > 0:
        exit(1)
"

# 4. 清理
kill $PID


---

 阶段五：EvoMap 能力沉淀（进阶）
 Step 7: 封装为可复用 Gene
当该接口开发完成后，将解决方案封装为 EvoMap Capsule：
# 安装 EvoMap CLI
npm install -g evomap-cli

# 创建能力胶囊
evo create capsule --name user-points-api --from ./.opencode/skills/api-contract

# 添加进化记录（记录踩过的坑）
evo log event \
  --type "bugfix" \
  --desc "修复了 UUID 格式校验绕过问题" \
  --solution "添加正则预校验 + 数据库参数化查询" \
  --severity "high"

Gene 结构：
# .evo/genes/user-points-gene.yaml
metadata:
  name: user-points-api
  version: 1.0.0
  source: "EvoMap/OpenCode 集成"
  
capability:
  inputs: ["SPEC.md"]
  outputs: ["API 文档", "测试用例", "实现代码"]
  constraints: ["P99<100ms", "并发安全"]
  
evolution:
  - event: "初始版本"
    date: 2024-01-15
    score: 85  # GDI 评分
  
  - event: "添加缓存层"
    date: 2024-02-01
    score: 92
    improvement: "引入 Redis，P99 降至 50ms"


---

 完整执行检查清单
阶段	关键动作	验收标准
准备	编写 AGENTS.md + SPEC.md	Agent 能正确理解项目边界
固化	创建 Skill（SKILL.md）	流程可重复执行，不依赖人工提示
协作	运行 OmO 多智能体	每个 Task 有明确产出和验收
验证	执行 Eval 回归	测试通过，无回归缺陷
进化	提交 EvoMap Capsule	能力可共享，经验可沉淀

---

 给后端工程师的速查指令
# 1. 初始化项目（Day 1）
echo "# AGENTS.md" > AGENTS.md && opencode init

# 2. 创建新 Skill（流程固化）
mkdir -p .opencode/skills/{name} && cat > .opencode/skills/{name}/SKILL.md << 'EOF'
---
name: {name}
description: {desc}
---
EOF

# 3. 触发多智能体（Tab 键后输入）
"根据 SPEC.md 实现该接口，遵循 AGENTS.md 的约束"

# 4. 运行 Eval（每次变更后）
./eval/run.sh

# 5. 查看工作流状态
cat WORK_PLAN.md

这套流程的核心价值：把"聊天式编程"变成"工程化交付"，每一步都有文档约束、有验收标准、有可追溯的变更记录。
