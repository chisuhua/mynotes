

# Agent系统终端+可视化前端使用指南

## 一、系统架构概览

本系统采用**单进程后端服务**，同时支持终端CLI和Web可视化前端，完全遵循"100% Code Reuse"原则：

```
┌─────────────┐     ┌─────────────┐
│  终端客户端 │     │  可视化前端 │
└─────────────┘     └─────────────┘
          │             │
          ▼             ▼
┌─────────────────────────────────────┐
│          Agent后端服务 (单进程)       │
│  • 会话管理器 (SessionManager)       │
│  • Agent实例池 (AgentPool)           │
│  • C++20 AI引擎 (LLM/Stable Diffusion)│
└─────────────────────────────────────┘
```

---

## 二、后端服务安装与启动

### 1. 安装后端服务

```bash
# 从源码构建（确保已安装CMake和C++20编译器）
git clone https://github.com/your-repo/engine-cpp.git
cd engine-cpp
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_SESSION_MANAGER=ON ..
make -j$(nproc)
```

### 2. 启动后端服务

```bash
# 启动服务（默认端口9001）
./build/localai_dp --port 9001

# 服务启动日志示例
[INFO] Gateway started on port 9001
[INFO] SessionManager initialized (max sessions: 1000)
[INFO] AgentPool initialized (LLM: 5 instances, SD: 3 instances)
```

> **关键点**：后端服务**仅需启动一次**，同时支持终端和Web客户端。

---

## 三、终端客户端使用指南

### 1. 安装终端CLI工具

```bash
# 通过pip安装（Python 3.8+）
pip install agent-cli

# 或从源码构建
git clone https://github.com/your-repo/agent-cli.git
cd agent-cli
pip install .
```

### 2. 基本使用

```bash
# 启动终端会话（自动创建新会话ID）
agent-cli

# 与Agent对话
> 你好，能帮我查一下巴黎的天气吗？
[Agent] 请稍等，正在查询巴黎的天气...

> 明天呢？
[Agent] 明天巴黎的天气预计为晴，气温18-25°C。

# 退出会话
> exit
```

### 3. 高级用法

```bash
# 指定会话ID（用于恢复之前的会话）
agent-cli --session-id=weather-2023

# 与特定Agent类型交互
agent-cli --agent-type=weather-agent

# 查看帮助
agent-cli --help
```

### 4. 会话持久化

终端会话会自动保存到`~/.agent/sessions/`目录：

```
~/.agent/sessions/
├── weather-2023.json
├── coding-2023.json
└── default-2023.json
```

下次使用相同会话ID即可恢复对话历史：

```bash
agent-cli --session-id=weather-2023
```

---

## 四、可视化前端使用指南

### 1. 启动Web前端

```bash
# 启动Web服务（默认端口8080）
cd frontend
npm install
npm run dev

# 或使用Docker
docker run -p 8080:8080 your-frontend-image
```

### 2. 访问Web界面

在浏览器中打开：
```
http://localhost:8080
```

### 3. Web界面功能

- **会话管理**：创建、恢复、删除会话
- **Agent切换**：在Web界面选择不同Agent类型
- **上下文查看**：查看完整对话历史
- **配置设置**：调整Agent参数

![Web界面示意图](https://example.com/web-ui.png)

---

## 五、终端与Web前端协同工作

### 1. 共享会话ID

**终端**和**Web前端**可以使用**相同的会话ID**：

```bash
# 终端创建会话
agent-cli --session-id=shared-session

# Web界面使用相同会话ID
访问 http://localhost:8080?session_id=shared-session
```

### 2. 会话状态同步

当在终端中与Agent交互后，Web界面会自动更新：

```
[终端]
> 你好，帮我写个Python函数计算斐波那契数列
[Agent] 请稍等...

[Web界面]
正在处理：帮我写个Python函数计算斐波那契数列
```

### 3. 会话状态持久化

所有会话状态**同时保存**到：
- 终端：`~/.agent/sessions/`
- Web：浏览器本地存储（或后端数据库）

---

## 六、高级使用场景

### 场景1：开发人员高效工作流

```bash
# 1. 在终端中快速测试
agent-cli --session-id=dev-test
> 写个Python函数计算斐波那契数列

# 2. 将结果复制到Web界面
# 3. 在Web界面中进一步分析和可视化
```

### 场景2：研究团队协作

```bash
# 1. 研究员A在终端中创建会话
agent-cli --session-id=research-2023

# 2. 研究员B在Web界面中使用相同会话ID
访问 http://your-server:8080?session_id=research-2023
```

### 场景3：服务器运维

```bash
# 1. 通过SSH连接服务器
ssh user@server

# 2. 在服务器终端中与Agent交互
agent-cli --session-id=server-ops

# 3. 在本地Web界面中远程查看
访问 http://your-server:8080?session_id=server-ops
```

---

## 七、常见问题解决

### 1. 终端客户端无法连接

```bash
# 检查后端服务是否运行
curl http://localhost:9001/health

# 如果返回"OK"，服务已启动
# 如果返回"Connection refused"，检查端口是否被占用
```

### 2. 会话状态不一致

```bash
# 确保使用相同的会话ID
# 检查会话ID是否正确：
agent-cli --session-id=your-session-id

# 在Web界面中检查URL中的session_id参数
```

### 3. 会话超时

```bash
# 默认会话超时30分钟
# 临时延长会话：
agent-cli --session-id=your-session-id --timeout 3600
```

---

## 八、架构优势总结

| 特性 | 说明 | 优势 |
|------|------|------|
| **单进程后端** | 仅需启动一个服务 | 资源利用率高，避免进程爆炸 |
| **统一会话管理** | 会话ID在所有客户端中一致 | 无缝切换终端和Web |
| **会话持久化** | 自动保存到本地/服务器 | 会话恢复无需重新配置 |
| **Agent池化** | 复用Agent实例 | 避免重复初始化，提升性能 |
| **双层背压** | 应用层+传输层控制 | 确保系统稳定，避免过载 |

---

## 九、下一步建议

1. **为终端用户创建模板**：
   ```bash
   # 创建常用会话模板
   agent-cli --create-template weather --description "天气查询Agent"
   ```

2. **集成到开发环境**：
   - 将`agent-cli`集成到VS Code/IntelliJ插件
   - 在终端中直接调用Agent

3. **扩展API支持**：
   ```bash
   # 通过curl使用API
   curl -X POST http://localhost:9001/api/query \
        -H "X-Session-ID: terminal-001" \
        -d '{"query": "帮我写个Python函数计算斐波那契数列"}'
   ```

---

## 十、总结

本系统通过**单一后端服务**同时支持：
- **终端CLI**（适合开发者、研究人员）
- **Web可视化界面**（适合普通用户、团队协作）

**无需额外配置**，所有功能通过**统一的会话ID**实现无缝协同，完全遵循"100% Code Reuse"原则，避免了进程数爆炸问题。

> **关键提示**：终端和Web前端**共享相同的后端服务和会话管理机制**，您只需启动一次后端服务，即可同时支持所有交互方式。

---

**立即开始体验**：
```bash
# 启动后端
./build/localai_dp --port 9001

# 在另一个终端中
agent-cli

# 在浏览器中打开
http://localhost:8080
```