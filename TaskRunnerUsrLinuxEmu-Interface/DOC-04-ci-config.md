# DOC-04: CI/CD 配置与协作流程规范

> **版本**: v1.2-draft  
> **日期**: 2026-04-13  
> **状态**: 待评审  
> **适用范围**: UsrLinuxEmu 和 TaskRunner 的 Git 分支策略、PR 保护规则、CI 配置

---

## 一、推荐分支策略

### 1.1 两个项目统一的分支模型

```
main ────────────────────────────────────────  稳定发布
  │
  ├─ v0.2 (tag)
  ├─ v0.5 (tag)
  └─ v1.0 (tag)

develop ─────────────────────────────────────  开发集成
  │
  ├─ feature/ioctl-compat                     功能分支
  ├─ feature/gpu-plugin
  └─ feature/cuda-scheduler

hotfix/* ───────────────────────────────────── 紧急修复
  │
  └─ hotfix/alloc-crash
```

| 分支 | 用途 | 生命周期 | 谁可以推 |
|------|------|---------|---------|
| `main` | 稳定发布版本 | 永久 | 仅通过 PR 合并 |
| `develop` | 日常开发集成 | 永久 | 仅通过 PR 合并 |
| `feature/*` | 功能开发 | 临时（合并后删除） | 开发者自由创建 |
| `hotfix/*` | 紧急修复 main 的问题 | 临时（合并后删除） | 开发者自由创建 |

### 1.2 命名规范

```
feature/<类型>/<描述>

类型:
  feat     — 新功能        例: feature/feat/ioctl-compat
  fix      — bug 修复      例: feature/fix/alloc-null-check
  refactor — 重构          例: feature/refactor/memory-manager
  docs     — 文档          例: feature/docs/architecture-diagram
  chore    — 杂项          例: feature/chore/cmake-optimization
  ci       — CI 配置       例: feature/ci/add-gcc12
```

---

## 二、PR 保护规则（需手动配置）

### 2.1 UsrLinuxEmu 仓库

**Branch protection: `main`**

| 设置 | 值 | 说明 |
|------|-----|------|
| Require a pull request before merging | ✅ | 禁止直接 push |
| Require approvals | **1** | 至少 1 人 review |
| Dismiss stale approvals on new commits | ✅ | 新 commit 后需重新 review |
| Require review from Code Owners | ✅ | 必须 code owner 批准 |
| Require status checks to pass | ✅ | CI 必须绿 |
| Status checks: | `build-and-test` | CI job 名称 |
| Require branches to be up to date | ✅ | 必须 rebase 到最新 |
| Include administrators | ✅ | 管理员也受约束 |
| Allow force pushes | ❌ | 禁止 force push |
| Allow deletions | ❌ | 禁止删除分支 |

**Branch protection: `develop`**

| 设置 | 值 | 说明 |
|------|-----|------|
| Require a pull request before merging | ✅ | 禁止直接 push |
| Require approvals | **0** | 开发分支可以快速合入 |
| Require status checks to pass | ✅ | CI 必须绿 |
| Status checks: | `build-and-test` | CI job 名称 |
| Require branches to be up to date | ⚠️ 可选 | 开发阶段可以不要求 |
| Allow force pushes | ❌ | 禁止 force push |
| Allow deletions | ❌ | 禁止删除分支 |

### 2.2 TaskRunner 仓库

**Branch protection: `main`**

| 设置 | 值 | 说明 |
|------|-----|------|
| Require a pull request before merging | ✅ | 禁止直接 push |
| Require approvals | **1** | 至少 1 人 review |
| Require status checks to pass | ✅ | CI 必须绿 |
| Status checks: | `build-and-test` | TaskRunner CI job 名称 |
| Require branches to be up to date | ✅ | 必须 rebase 到最新 |
| Include administrators | ✅ | 管理员也受约束 |
| Allow force pushes | ❌ | 禁止 force push |
| Allow deletions | ❌ | 禁止删除分支 |

**Branch protection: `develop`**

| 设置 | 值 | 说明 |
|------|-----|------|
| Require a pull request before merging | ✅ | 禁止直接 push |
| Require approvals | **0** | 开发分支可以快速合入 |
| Require status checks to pass | ✅ | CI 必须绿 |
| Status checks: | `build-and-test` | TaskRunner CI job 名称 |
| Allow force pushes | ❌ | 禁止 force push |
| Allow deletions | ❌ | 禁止删除分支 |

### 2.3 CODEOWNERS 文件（两个项目都需要）

**`UsrLinuxEmu/.github/CODEOWNERS`**:
```
# UsrLinuxEmu 代码所有者
*               @<owner>
/include/       @<owner>
/drivers/       @<owner>
/src/           @<owner>
/docs/          @<owner>
/.github/       @<owner>
```

**`TaskRunner/.github/CODEOWNERS`**:
```
# TaskRunner 代码所有者
*               @<owner>
/src/           @<owner>
/include/       @<owner>
/external/      @<owner>
/docs/          @<owner>
```

---

## 三、Submodule 管理策略

### 3.1 推荐：跟踪 develop 分支

**`.gitmodules` 配置**（TaskRunner 仓库）：

```ini
[submodule "external/UsrLinuxEmu"]
    path = external/UsrLinuxEmu
    url = https://github.com/<org>/UsrLinuxEmu.git
    branch = develop
    shallow = true
    update = checkout
```

**为什么跟踪 develop 而不是 main**：

| 场景 | 跟踪 develop | 跟踪 main |
|------|-------------|----------|
| UsrLinuxEmu 改了 ioctl 接口 | TaskRunner 立即感知，PR 里就能发现不兼容 | 要等 UsrLinuxEmu 发版才知道 |
| UsrLinuxEmu 开发中的 bug | TaskRunner CI 可能失败，提前暴露问题 | TaskRunner 不受影响，但也得不到新接口 |
| TaskRunner 想尝试新 API | 直接用，不需要等 UsrLinuxEmu 发版 | 必须等发版 |
| 稳定性 | ⚠️ 可能遇到 develop 的未完成代码 | ✅ 稳定 |

**结论**：开发阶段（v0.2-v0.5）跟踪 develop，发布阶段（v1.0+）切换为跟踪 main 或特定 tag。

### 3.2 Submodule commit 更新工作流

**场景 1：UsrLinuxEmu 有更新，TaskRunner 想同步**

```bash
# 在 TaskRunner 仓库
cd external/UsrLinuxEmu
git fetch origin develop
git checkout develop
git pull origin develop

cd ../..
git add external/UsrLinuxEmu
git commit -m "chore: update UsrLinuxEmu to <short-commit-hash>"
```

**场景 2：feature 分支需要同步特定版本**

```bash
# TaskRunner 的 feature/cuda-scheduler 分支
cd external/UsrLinuxEmu
git fetch origin
git checkout <specific-commit-or-tag>

cd ../..
git add external/UsrLinuxEmu
git commit -m "chore: pin UsrLinuxEmu to <tag> for cuda-scheduler feature"
```

**场景 3：UsrLinuxEmu 接口变更，TaskRunner 需要同步修改**

```bash
# 1. 在 TaskRunner 创建 feature 分支
git checkout -b feature/fix/ioctl-api-update

# 2. 更新 submodule
cd external/UsrLinuxEmu
git fetch origin develop
git checkout develop
git pull origin develop

# 3. 修改 TaskRunner 代码适配新接口
# ... 编辑代码 ...

# 4. 提交
git add src/ external/UsrLinuxEmu
git commit -m "fix: adapt to UsrLinuxEmu ioctl API changes"

# 5. 推送到远程并创建 PR
git push origin feature/fix/ioctl-api-update
```

---

## 四、推荐的协作工作流

### 4.1 总体流程图

```
┌────────────────── UsrLinuxEmu 仓库 ──────────────────┐
│                                                        │
│  main ──[v0.2]───[v0.3]───[v0.5]───[v1.0]           │
│    ↑             ↑         ↑          ↑              │
│    │ merge       │ merge   │ merge    │ merge        │
│  develop ──────► develop ─► develop ─► develop       │
│    ↑             ↑         ↑                          │
│    │ PR          │ PR      │ PR                       │
│  feature/*     feature/* feature/*                   │
│                                                        │
└────────────────────────────────────────────────────────┘
         │ Submodule commit 引用
         ▼
┌────────────────── TaskRunner 仓库 ───────────────────┐
│                                                        │
│  main ──[v0.2]───[v0.3]───[v0.5]───[v1.0]           │
│    ↑             ↑         ↑          ↑              │
│    │ merge       │ merge   │ merge    │ merge        │
│  develop ──────► develop ─► develop ─► develop       │
│    ↑             ↑         ↑                          │
│    │ PR          │ PR      │ PR                       │
│  feature/*     feature/* feature/*                   │
│                                                        │
│  external/UsrLinuxEmu → 指向 UsrLinuxEmu 的特定 commit │
└────────────────────────────────────────────────────────┘
```

### 4.2 典型开发场景

**场景 A：纯 UsrLinuxEmu 开发（不影响 TaskRunner）**

```bash
# UsrLinuxEmu 开发者
git checkout -b feature/feat/linux-compat
# ... 开发 ...
git push origin feature/feat/linux-compat
# 创建 PR → develop
# PR 合并后，develop 有更新

# TaskRunner 开发者（可选同步）
cd TaskRunner/external/UsrLinuxEmu
git pull origin develop
cd ../..
git add external/UsrLinuxEmu
git commit -m "chore: sync UsrLinuxEmu develop"
git push origin develop
```

**场景 B：UsrLinuxEmu 接口变更，TaskRunner 需要同步修改**

```bash
# 步骤 1: UsrLinuxEmu 先合入接口变更
# UsrLinuxEmu 开发者创建 PR → develop，合并

# 步骤 2: TaskRunner 开发者创建适配 PR
git checkout -b feature/fix/adapt-ioctl-changes
cd external/UsrLinuxEmu
git fetch origin develop
git checkout origin/develop   # 指向最新的 develop
cd ../..
# 修改 TaskRunner 代码适配新接口
git add src/ external/UsrLinuxEmu
git commit -m "fix: adapt to new ioctl API"
git push origin feature/fix/adapt-ioctl-changes
# 创建 PR → develop
# CI 会自动构建 TaskRunner + 最新 UsrLinuxEmu submodule
```

**场景 C：TaskRunner 新功能，需要 UsrLinuxEmu 还没合入的接口**

```bash
# 步骤 1: UsrLinuxEmu 开发者创建接口 PR（未合并）
# PR #42: "Add BARRIER_SYNC to GpuCommandPacket"

# 步骤 2: TaskRunner 开发者基于该 PR 的分支开发
cd TaskRunner/external/UsrLinuxEmu
git fetch origin
git checkout feature/feat/barrier-sync  # UsrLinuxEmu 的 feature 分支
cd ../..
git add external/UsrLinuxEmu
git commit -m "chore: pin to UsrLinuxEmu barrier-sync branch"

# TaskRunner 开发新功能
git checkout -b feature/feat/task-barrier
# ... 开发 ...
git push origin feature/feat/task-barrier
# TaskRunner PR 的 CI 会基于 UsrLinuxEmu 的 feature 分支构建

# 步骤 3: 两个 PR 都通过后
# 先合 UsrLinuxEmu PR #42 → develop
# 再合 TaskRunner PR，更新 submodule 指向 develop
```

### 4.3 发布流程

```
1. 从 develop 创建 release 分支
   git checkout -b release/v0.2 develop

2. 更新 UsrLinuxEmu submodule 到稳定版本
   cd external/UsrLinuxEmu
   git checkout develop  # 确认是最新的
   cd ../..
   git add external/UsrLinuxEmu
   git commit -m "chore: pin UsrLinuxEmu for v0.2 release"

3. 在 release 分支上做最后修复（不引入新功能）

4. 合并到 main 并打 tag
   git checkout main
   git merge --no-ff release/v0.2
   git tag -a v0.2 -m "Release v0.2"
   git push origin main --tags

5. 合并回 develop（同步 release 分支的修复）
   git checkout develop
   git merge release/v0.2
   git push origin develop

6. 删除 release 分支
   git branch -d release/v0.2
```

---

## 五、CI 工作流配置

### 5.1 Runner 配置

```yaml
runs-on: [self-hosted, linux, x64, dev]
```

### 5.2 UsrLinuxEmu CI

```yaml
# .github/workflows/ci.yml
name: UsrLinuxEmu CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  build-and-test:
    runs-on: [self-hosted, linux, x64, dev]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup ccache
        uses: hendrikmuhs/ccache-action@v1.2
        with:
          key: ${{ runner.os }}-gcc-release

      - name: Configure
        run: |
          cmake -B build \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER=gcc-11 \
            -DCMAKE_CXX_COMPILER=g++-11 \
            -DUSE_CCACHE=ON

      - name: Build
        run: cmake --build build -j$(nproc)

      - name: Test
        run: ctest --test-dir build --output-on-failure
```

### 5.3 TaskRunner CI（含 Submodule）

```yaml
# .github/workflows/ci.yml
name: TaskRunner CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  build-and-test:
    runs-on: [self-hosted, linux, x64, dev]

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Setup ccache
        uses: hendrikmuhs/ccache-action@v1.2
        with:
          key: ${{ runner.os }}-gcc-release

      - name: Configure
        run: |
          cmake -B build \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER=gcc-11 \
            -DCMAKE_CXX_COMPILER=g++-11 \
            -DUSE_CCACHE=ON

      - name: Build
        run: cmake --build build -j$(nproc)

      - name: Test
        run: ctest --test-dir build --output-on-failure
```

### 5.4 交叉集成测试（UsrLinuxEmu 推动时触发）

```yaml
# .github/workflows/integration.yml
# 放在 UsrLinuxEmu 仓库，当 develop 有更新时自动测试 TaskRunner
name: TaskRunner Integration Test

on:
  push:
    branches: [develop]

jobs:
  integration:
    runs-on: [self-hosted, linux, x64, dev]
    # 同 Org 无需 PAT，GITHUB_TOKEN 即可 checkout
    steps:
      - name: Checkout TaskRunner
        uses: actions/checkout@v4
        with:
          repository: ${{ github.repository_owner }}/TaskRunner
          ref: develop
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Update UsrLinuxEmu submodule to HEAD
        run: |
          cd external/UsrLinuxEmu
          git fetch origin develop
          git checkout FETCH_HEAD
          cd ../..

      - name: Setup ccache
        uses: hendrikmuhs/ccache-action@v1.2
        with:
          key: integration-${{ github.sha }}

      - name: Build
        run: |
          cmake -B build \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_COMPILER=gcc-11 \
            -DCMAKE_CXX_COMPILER=g++-11
          cmake --build build -j$(nproc)

      - name: Test
        run: ctest --test-dir build --output-on-failure
```

---

## 六、ccache 配置

```bash
export CCACHE_DIR=$HOME/.ccache
export CCACHE_MAXSIZE=5G
ccache --set-config=compiler_check=content
ccache --set-config=sloppiness=time_macros
```

---

## 七、分支策略与 CI 对照表

| 分支 | CI 触发 | Submodule 策略 | PR 要求 |
|------|---------|---------------|---------|
| `main` | push + PR | 锁定稳定 commit/tag | 1 review + CI 绿 |
| `develop` | push + PR | 跟踪 UsrLinuxEmu develop | CI 绿（0 review） |
| `feature/*` | PR only | 可指向 UsrLinuxEmu feature 分支 | CI 绿（0 review） |
| `release/*` | push + PR | 锁定发布版本 | 1 review + CI 绿 |

---

## 八、PR 模板

### 8.1 UsrLinuxEmu PR 模板

**`.github/PULL_REQUEST_TEMPLATE.md`**:

```markdown
## 变更类型
- [ ] 新功能
- [ ] Bug 修复
- [ ] 重构
- [ ] 文档
- [ ] CI/配置

## 描述

<!-- 简要描述变更内容 -->

## 接口变更
- [ ] 不影响 TaskRunner（纯内部实现）
- [ ] 影响 TaskRunner（需要 TaskRunner 同步修改）
  - 影响范围：<!-- 描述影响了哪些接口 -->

## 测试
- [ ] 已通过本地测试
- [ ] 新增测试用例

## 关联 Issue
<!-- 关联的 issue 编号 -->
```

### 8.2 TaskRunner PR 模板

**`.github/PULL_REQUEST_TEMPLATE.md`**:

```markdown
## 变更类型
- [ ] 新功能
- [ ] Bug 修复
- [ ] 重构
- [ ] 文档
- [ ] CI/配置

## 描述

<!-- 简要描述变更内容 -->

## Submodule 变更
- [ ] 无变更
- [ ] 更新 UsrLinuxEmu 到最新 develop
- [ ] 更新 UsrLinuxEmu 到特定 commit: `_______`
- [ ] 指向 UsrLinuxEmu 的 feature 分支: `_______`

## UsrLinuxEmu 接口依赖
- [ ] 不依赖新接口
- [ ] 依赖 UsrLinuxEmu 的哪个 PR/变更: <!-- 描述 -->

## 测试
- [ ] 已通过本地测试
- [ ] 新增测试用例
```

---

## 九、设置清单（需要你手动完成）

### 9.1 GitHub 仓库设置

#### UsrLinuxEmu 仓库

- [ ] **创建 `develop` 分支**
  ```bash
  git checkout -b develop
  git push -u origin develop
  ```

- [ ] **配置 `develop` 分支保护**
  - Settings → Branches → Add rule → `develop`
  - ✅ Require a pull request before merging
  - ✅ Require status checks to pass → `build-and-test`
  - ❌ Require approvals（开发阶段不需要）
  - ❌ Allow force pushes

- [ ] **配置 `main` 分支保护**
  - Settings → Branches → Add rule → `main`
  - ✅ Require a pull request before merging
  - ✅ Require approvals → 1
  - ✅ Require status checks to pass → `build-and-test`
  - ✅ Require branches to be up to date
  - ✅ Include administrators
  - ❌ Allow force pushes

- [ ] **添加 CODEOWNERS 文件**
  - 创建 `.github/CODEOWNERS`（见第二节）

- [ ] **添加 PR 模板**
  - 创建 `.github/PULL_REQUEST_TEMPLATE.md`（见第八节）

#### TaskRunner 仓库

- [ ] **创建 `develop` 分支**
  ```bash
  git checkout -b develop
  git push -u origin develop
  ```

- [ ] **配置 `develop` 分支保护**（同上，0 review + CI 绿）

- [ ] **配置 `main` 分支保护**（同上，1 review + CI 绿）

- [ ] **添加 CODEOWNERS 文件**

- [ ] **添加 PR 模板**（TaskRunner 版本，含 Submodule 变更部分）

- [ ] **添加 Submodule**
  ```bash
  git submodule add https://github.com/<org>/UsrLinuxEmu.git external/UsrLinuxEmu
  git commit -m "chore: add UsrLinuxEmu submodule (track develop)"
  ```

### 9.2 CI Runner 设置

- [ ] 在 GitHub Org Settings → Actions → Runners 中注册自建 Runner
- [ ] 给 Runner 打标签：`linux`, `x64`, `dev`
- [ ] 在 Runner 机器上安装 gcc-11、cmake ≥ 3.20、ccache

### 9.3 CI 工作流文件

- [ ] 在 UsrLinuxEmu 创建 `.github/workflows/ci.yml`
- [ ] 在 TaskRunner 创建 `.github/workflows/ci.yml`
- [ ] 在 UsrLinuxEmu 创建 `.github/workflows/integration.yml`（可选，建议后期添加）

---

**维护**: CTO  
**最后更新**: 2026-04-13
