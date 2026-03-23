# 03_Engineering_&_Deployment.md

> **文档版本**: v1.0  
> **对应架构**: 02_Architecture_&_Runtime.md v1.0  
> **目标读者**: 核心开发者、DevOps 工程师、安全工程师  
> **关键约束**: P0 修复点为强制实现红线，L2 沙箱基础功能为 Phase 1.1 交付标准

---

## 文档摘要

| 项目 | 内容 |
|------|------|
| **工程定位** | 可落地的实现规范，含代码模板、调优参数、部署清单 |
| **P0 红线** | 线程安全 (`defer`)、协议握手 (v2.1)、Agent 单实例单会话 (`occupied_`) |
| **L2 沙箱** | 进程池预热、OverlayFS 配置、Namespace 逃逸防护 |
| **交付形态** | 单一二进制 + 可选前端资源，支持本地/远程/容器化部署 |
| **性能基线** | L2 预热后启动 <10ms，SQLite WAL 并发 >1000 TPS |

---

## 0. P0 核心修复与红线规范（强制实现）

### 0.1 线程安全红线（uWebSockets）

**约束**: 所有 `ws->send()` 必须在创建 WebSocket 的 Event Loop 线程执行

**错误实现**（禁止）:
```cpp
// 在 llama.cpp 回调线程（子线程）直接发送
llama_set_callback(ctx, [](void* user_data, const char* token) {
    auto* ws = static_cast<uWS::WebSocket*>(user_data);
    ws->send(token);  // ❌ 未定义行为，可能崩溃
});
```

**正确实现**（强制）:
```cpp
// engine-cpp/src/handlers/stream_handler.hpp
void on_llm_token(void* user_data, const std::string& token) {
    auto* ws = static_cast<uWS::WebSocket*>(user_data);
    auto* loop = uWS::Loop::get();  // 获取主线程 Event Loop
    
    // 通过 defer 抛回主线程
    loop->defer([ws, token]() {
        ws->send(token, uWS::OpCode::TEXT);
    });
}
```

**代码审查清单**:
- [ ] 所有 `ws->send()` 调用处是否包含在 `loop->defer()` 内？
- [ ] 子线程（ThreadPool、llama.cpp 回调）是否有直接操作 WebSocket？
- [ ] 是否使用了 `uWS::Loop::get()` 获取正确的事件循环实例？

### 0.2 协议版本握手（v2.1）

**强制流程**:
1. 连接建立后，客户端必须在 5 秒内发送 `handshake` 消息
2. 服务端验证 `version == "2.1"`，不匹配立即断开 (code 1008)
3. 协商背压参数 (`ack_batch_size`, `transport_high_water`)
4. 服务端响应 `handshake_ack`，之后才能收发业务消息

**服务端实现模板**:
```cpp
// engine-cpp/src/handlers/handshake_handler.hpp
inline void handle_handshake(auto* ws, std::string_view message) {
    auto* data = ws->getUserData();
    
    auto json = nlohmann::json::parse(message, nullptr, false);
    if (json.is_discarded() || json["type"] != "handshake") {
        ws->close(1008, "Handshake required first");
        return;
    }
    
    std::string client_version = json.value("version", "1.0");
    if (client_version != "2.1") {
        ws->send(R"({"error":{"code":"0x0002","message":"Protocol version mismatch"}})");
        ws->close(1008, "Protocol version mismatch");
        return;
    }
    
    // 协商背压参数
    data->ack_batch_size = json["backpressure"].value("ack_batch_size", 10);
    data->transport_high_water = json["backpressure"].value("transport_high_water", 1024*1024);
    
    // 标记握手完成
    data->handshake_completed = true;
    
    // 响应确认
    ws->send(R"({"type":"handshake_ack","version":"2.1","negotiated":{...}})");
}
```

**兼容性处理**:
- 若客户端未发送 `version` 字段，视为 1.0 版本，返回 `0x0002` 错误
- 若客户端能力集不包含 `sandbox:l2`，服务端不得强制使用 L2 沙箱

### 0.3 Agent 单实例单会话约束（`occupied_`）

**原子性实现**（必须使用 `std::atomic` + `mutex` 双重保护）:

```cpp
// engine-cpp/src/session/agent_pool.hpp
struct AgentInstance {
    std::shared_ptr<LlamaAdapter> adapter;
    std::atomic<bool> occupied_{false};  // 原子标记
    std::mutex mutex_;                    // 保护状态变更
    
    std::shared_ptr<LlamaAdapter> acquire() {
        std::lock_guard<std::mutex> lock(mutex_);
        bool expected = false;
        // compare_exchange_strong: 原子检查并设置
        if (occupied_.compare_exchange_strong(expected, true)) {
            return adapter;
        }
        return nullptr;  // 已被占用
    }
    
    void release() {
        std::lock_guard<std::mutex> lock(mutex_);
        occupied_.store(false);
    }
};
```

**资源获取流程**（必须实现超时与错误码）:
```cpp
std::shared_ptr<LLMResource> AgentPool::acquire_llm(
    const std::string& model_hint,
    const ResourceBudget& budget,
    std::chrono::milliseconds timeout = 5s) {
    
    auto start = std::chrono::steady_clock::now();
    
    while (std::chrono::steady_clock::now() - start < timeout) {
        for (auto& instance : pools_[model_hint]) {
            if (auto res = instance->acquire()) {
                return res;
            }
        }
        // 短暂等待后重试（避免忙等）
        std::this_thread::sleep_for(10ms);
    }
    
    // 超时，返回标准错误码
    throw AgentPoolExhaustedException(ErrorCode::SYS_POOL_EXHAUSTED);
}
```

**内存序约束**:
- `acquire()` 使用 `std::memory_order_acq_rel`（默认）
- 禁止 `occupied_` 使用普通 `bool` 类型（非原子）

### 0.4 SQLite WAL 配置（并发优化）

**强制配置参数**:
```cpp
// engine-cpp/src/utils/sqlite_db.cpp
void SQLiteDB::init_wal_mode() {
    // 启用 WAL 模式（读写并发）
    exec("PRAGMA journal_mode=WAL;");
    
    // 同步策略：WAL 模式下可安全使用 NORMAL
    exec("PRAGMA synchronous=NORMAL;");
    
    //  busy 超时：自动重试 5 秒
    exec("PRAGMA busy_timeout=5000;");
    
    // 自动 checkpoint：每 1000 页 WAL 文件触发
    exec("PRAGMA wal_autocheckpoint=1000;");
    
    // 页大小优化（通常 4096 匹配 OS 页）
    exec("PRAGMA page_size=4096;");
}
```

**连接池配置**（若使用连接池）:
- 只读连接：可并发多个，用于查询会话历史
- 写入连接：单连接独占，用于状态更新

### 0.5 路径安全 (`safe_join`)

**实现模板**（防目录遍历）:
```cpp
// engine-cpp/src/utils/path_utils.hpp
inline std::optional<std::string> safe_join(
    const std::string& base_dir,
    const std::string& user_path) {
    
    // 1. 解析 base_dir 规范路径
    char real_base[PATH_MAX];
    if (!realpath(base_dir.c_str(), real_base)) {
        return std::nullopt;
    }
    
    // 2. 拼接并解析完整路径
    std::string full = base_dir + "/" + user_path;
    char real_full[PATH_MAX];
    if (!realpath(full.c_str(), real_full)) {
        // 文件可能不存在（新建），尝试解析父目录
        auto parent = std::filesystem::path(full).parent_path();
        if (!realpath(parent.c_str(), real_full)) {
            return std::nullopt;
        }
        std::string filename = std::filesystem::path(full).filename();
        full = std::string(real_full) + "/" + filename;
    } else {
        full = real_full;
    }
    
    // 3. 严格前缀检查（防止 ../ 逃逸）
    if (full.length() < std::string(real_base).length() + 1 ||
        full[std::string(real_base).length()] != '/' ||
        full.substr(0, std::string(real_base).length()) != real_base) {
        return std::nullopt;  // 路径逃逸
    }
    
    return full;
}
```

---

## 1. L2 沙箱实现模板

### 1.1 ProcessSandbox 核心接口

```cpp
// engine-cpp/src/sandbox/l2_sandbox.hpp
class ProcessSandbox {
public:
    // 从进程池获取（推荐）
    static std::unique_ptr<ProcessSandbox> acquire_from_pool();
    
    // 生命周期管理
    void setup_namespaces(bool isolate_network);
    void apply_cgroups_limit(const ResourceLimits& limits);
    void mount_overlayfs(const std::string& base_dir);
    
    // 通信
    void send_context(const Context& ctx, int timeout_ms = 5000);
    Context recv_result(int timeout_ms = 60000);
    
    // 回收（返回进程池而非销毁）
    void recycle();

private:
    pid_t pid_{-1};
    int sock_fd_{-1};  // Unix Domain Socket
    std::string overlay_upper_;
    std::string overlay_work_;
};
```

### 1.2 进程池预热机制

**初始化配置**:
```cpp
// engine-cpp/src/sandbox/sandbox_controller.cpp
void SandboxController::warmup_l2_pool(size_t target_size) {
    while (l2_pool_.size() < target_size) {
        auto sb = std::make_unique<ProcessSandbox>();
        
        // 预创建 Namespace（延迟更低）
        pid_t pid = fork();
        if (pid == 0) {
            // 子进程：设置 Namespace 并等待命令
            setup_namespaces_impl();
            enter_sandbox_loop();
            exit(0);
        }
        
        sb->pid_ = pid;
        sb->sock_fd_ = create_socket_pair();  // 提前创建 socket
        
        l2_pool_.push(std::move(sb));
    }
}
```

**LRU 淘汰策略**:
```cpp
void SandboxController::maintain_pool() {
    // 内存压力下释放空闲进程
    if (get_system_memory_pressure() > 0.8) {
        while (l2_pool_.size() > min_pool_size_) {
            l2_pool_.pop();  // 销毁最老的沙箱进程
        }
    }
}
```

### 1.3 OverlayFS 配置模板

**挂载脚本**（C++ 调用）:
```cpp
void ProcessSandbox::mount_overlayfs(const std::string& base_dir) {
    // 创建临时目录（tmpfs 挂载点，内存中）
    std::string upper = "/tmp/localai_sandbox_upper_" + uuid();
    std::string work = "/tmp/localai_sandbox_work_" + uuid();
    std::string merged = "/tmp/localai_sandbox_merged_" + uuid();
    
    mkdir(upper.c_str(), 0755);
    mkdir(work.c_str(), 0755);
    mkdir(merged.c_str(), 0755);
    
    // 挂载 tmpfs（限制大小，防止占满磁盘）
    mount("tmpfs", upper.c_str(), "tmpfs", MS_NOEXEC | MS_NOSUID, 
          "size=256m,mode=0755");
    
    // 挂载 OverlayFS
    std::string opts = "lowerdir=" + base_dir + 
                      ",upperdir=" + upper + 
                      ",workdir=" + work;
    mount("overlay", merged.c_str(), "overlay", MS_NOATIME, opts.c_str());
    
    // 切换根目录（chroot）
    chroot(merged.c_str());
    chdir("/");
}
```

**清理脚本**（进程回收时）:
```bash
#!/bin/bash
# scripts/cleanup_sandbox.sh
umount -l /tmp/localai_sandbox_merged_*
rm -rf /tmp/localai_sandbox_upper_* /tmp/localai_sandbox_work_*
```

### 1.4 L2 与 L0 通信协议（IPC）

**消息格式**:
```cpp
struct IPCHeader {
    uint32_t magic{0x41474950};  // "AGIP" (Agentic IPC)
    uint32_t type;               // 1: LLM_REQUEST, 2: FS_ACCESS, 3: RESULT
    uint32_t payload_len;
    uint32_t checksum;
};

// 压缩选项（payload > 64KB 时启用）
enum class Compression : uint8_t { NONE = 0, ZLIB = 1, ZSTD = 2 };
```

**通信流程**:
```cpp
// L2 沙箱内（子进程）
void sandbox_main_loop() {
    while (true) {
        auto [header, payload] = recv_from_parent();
        
        if (header.type == MSG_LLM_REQUEST) {
            // 禁止直接执行，转发给父进程
            send_to_parent(MSG_LLM_FORWARD, payload);
            auto result = recv_from_parent();  // 等待父进程代理执行
            send_to_parent(MSG_RESULT, result);
        }
        else if (header.type == MSG_FS_ACCESS) {
            // 在 OverlayFS 内执行，无需代理
            auto result = handle_fs_access(payload);
            send_to_parent(MSG_RESULT, result);
        }
    }
}
```

---

## 2. 构建与配置

### 2.1 CMake 完整配置

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.20)
project(localai_core VERSION 2.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# P0 功能开关（强制启用）
option(ENABLE_THREAD_SAFETY "Enable uWS::Loop::defer for all ws->send()" ON)
option(ENABLE_PROTOCOL_HANDSHAKE "Enforce v2.1 protocol handshake" ON)
option(ENABLE_SQLITE_WAL "Enable SQLite WAL mode" ON)
option(ENABLE_AGENT_POOL_CONSTRAINTS "Enable occupied_ atomic checks" ON)

# 平台功能
option(ENABLE_WINDOWS_CONPTY "Enable Windows ConPTY support" ON)
option(ENABLE_L2_SANDBOX "Enable L2 Process Sandbox" ON)

# 依赖查找
find_package(uWebSockets REQUIRED)
find_package(llama.cpp REQUIRED)
find_package(SQLite3 REQUIRED)
find_package(cppcoro REQUIRED)

# L2 沙箱依赖
if(ENABLE_L2_SANDBOX AND UNIX)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SECCOMP libseccomp REQUIRED)
endif()

# 源文件
set(SOURCES
    src/main.cpp
    src/handlers/stream_handler.cpp
    src/handlers/handshake_handler.cpp
    src/handlers/pty_handler.cpp
    src/session/session_manager.cpp
    src/session/agent_pool.cpp
    src/dsl/engine.cpp
    src/dsl/topo_scheduler.cpp
    src/dsl/branch_executor.cpp
    src/sandbox/sandbox_controller.cpp
    src/sandbox/l2_sandbox.cpp
    src/utils/sqlite_db.cpp
    src/utils/path_utils.cpp
)

# 条件编译
if(ENABLE_THREAD_SAFETY)
    target_compile_definitions(localai_core PRIVATE THREAD_SAFETY_ENFORCED)
endif()

if(ENABLE_L2_SANDBOX)
    target_compile_definitions(localai_core PRIVATE L2_SANDBOX_ENABLED)
    target_sources(localai_core PRIVATE src/sandbox/l2_namespace.cpp)
endif()

if(WIN32 AND ENABLE_WINDOWS_CONPTY)
    target_compile_definitions(localai_core PRIVATE WINDOWS_CONPTY)
    target_link_libraries(localai_core PRIVATE conpty.lib)
endif()

target_link_libraries(localai_core PRIVATE
    uWebSockets::uWebSockets
    llama.cpp::llama
    SQLite3::SQLite3
    cppcoro::cppcoro
    seccomp  # Linux only
    pthread
)

# 安装规则
install(TARGETS localai_core DESTINATION bin)
install(DIRECTORY frontend/dist DESTINATION share/localai)
```

### 2.2 条件编译隔离

**桌面版 vs 无头版**:
```cpp
// src/config.hpp
#ifdef DESKTOP_BUILD
    #define ENABLE_TAURI_INTEGRATION 1
    #define ENABLE_SYSTEM_TRAY 1
#else
    #define ENABLE_TAURI_INTEGRATION 0
    #define ENABLE_SYSTEM_TRAY 0
#endif

#ifdef L2_SANDBOX_ENABLED
    #include "sandbox/l2_sandbox.hpp"
#endif
```

**编译命令示例**:
```bash
# 桌面版（全功能）
cmake -B build -DENABLE_L2_SANDBOX=ON -DDESKTOP_BUILD=ON
cmake --build build --config Release

# 无头版（服务器）
cmake -B build_headless -DENABLE_L2_SANDBOX=ON -DDESKTOP_BUILD=OFF
cmake --build build_headless

# 最小版（无沙箱，仅 L0/L1）
cmake -B build_minimal -DENABLE_L2_SANDBOX=OFF
```

---

## 3. 部署与运维

### 3.1 单一二进制交付

**资源嵌入**（CMake）:
```cmake
# 将前端资源嵌入二进制
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/frontend_assets.cpp
    COMMAND xxd -i frontend/dist/index.html > ${CMAKE_BINARY_DIR}/frontend_assets.cpp
    DEPENDS frontend/dist/index.html
)
target_sources(localai_core PRIVATE ${CMAKE_BINARY_DIR}/frontend_assets.cpp)
```

**启动逻辑**:
```cpp
// src/main.cpp
int main(int argc, char** argv) {
    // 1. 检查本地覆盖（开发调试）
    if (std::filesystem::exists("~/.localai/frontend/index.html")) {
        serve_from_filesystem("~/.localai/frontend");
    } else {
        serve_from_embedded_resources();  // 从二进制内存提供
    }
    
    // 2. 启动引擎...
}
```

### 3.2 远程访问方案（SSH 隧道）

**自动化脚本**:
```bash
#!/bin/bash
# scripts/start_remote.sh
REMOTE_HOST=$1
REMOTE_USER=$2
LOCAL_PORT=${3:-9001}

# 1. 检查远程引擎
if ! ssh ${REMOTE_USER}@${REMOTE_HOST} "test -f ~/.localai/bin/localai_core"; then
    # 自动上传二进制（带 SHA256 校验）
    scp build/localai_core ${REMOTE_USER}@${REMOTE_HOST}:~/.localai/bin/
    ssh ${REMOTE_USER}@${REMOTE_HOST} "chmod +x ~/.localai/bin/localai_core"
fi

# 2. 启动远程引擎
ssh ${REMOTE_USER}@${REMOTE_HOST} "nohup ~/.localai/bin/localai_core --port 9001 > /dev/null 2>&1 &"

# 3. 建立隧道（StrictHostKeyChecking 可配置）
ssh -o ServerAliveInterval=60 \
    -o StrictHostKeyChecking=accept-new \
    -L ${LOCAL_PORT}:127.0.0.1:9001 \
    ${REMOTE_USER}@${REMOTE_HOST} -N
```

** systemd 服务文件**（服务器部署）:
```ini
# /etc/systemd/system/localai.service
[Unit]
Description=LocalAI Core Engine
After=network.target

[Service]
Type=simple
User=localai
ExecStart=/usr/local/bin/localai_core \
    --port 9001 \
    --models-dir /var/lib/localai/models \
    --max-agents 20 \
    --sandbox-pool-size 10 \
    --bind 127.0.0.1
Restart=always
RestartSec=10

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/localai

[Install]
WantedBy=multi-user.target
```

### 3.3 沙箱调优参数

**CLI 参数**:
```bash
localai_core \
    --max-total-agents=20 \          # AgentPool 总上限
    --max-llm-agents=10 \            # LLM 实例上限
    --sandbox-pool-size=10 \         # L2 进程池预热数量
    --sandbox-max-idle=20 \          # 最大空闲 L2 进程（超则销毁）
    --overlay-tmpfs-size=256MB \     # L2 可写层大小限制
    --cgroups-cpu-quota=100000 \     # L2 CPU 限制（us/period）
    --cgroups-memory-limit=512M \    # L2 内存限制
    --ipc-compression=auto \         # auto|none|zlib（payload>64KB 自动压缩）
```

**动态调优**（通过 `/config` WebSocket 路径）:
```json
{
  "type": "config_update",
  "sandbox": {
    "pool_size": 15,
    "tmpfs_size": "512MB"
  },
  "backpressure": {
    "ack_batch_size": 30
  }
}
```

---

## 4. 跨平台适配

### 4.1 Windows ConPTY 配置

**SDK 要求**: Windows 10 1809+ (Build 17763), Windows SDK 10.0.17763+

**CMake 检测**:
```cmake
if(WIN32)
    include(CheckIncludeFileCXX)
    check_include_file_cxx("conpty.h" HAVE_CONPTY_H)
    if(NOT HAVE_CONPTY_H)
        message(WARNING "ConPTY not available, falling back to legacy console")
        set(ENABLE_WINDOWS_CONPTY OFF)
    endif()
endif()
```

**实现代码**:
```cpp
#ifdef WINDOWS_CONPTY
#include <windows.h>
#include <conptyapi.h>

class WindowsPty {
public:
    bool spawn(const std::string& cmd) {
        HPCON hPC;
        HANDLE hIn, hOut;
        
        // 创建伪控制台
        CreatePseudoConsole(COORD{80, 25}, hIn, hOut, 0, &hPC);
        
        // 启动子进程并附加
        STARTUPINFOEX siEx{sizeof(siEx)};
        siEx.lpAttributeList = nullptr;
        CreateProcess(nullptr, (LPSTR)cmd.c_str(), nullptr, nullptr, FALSE,
                     EXTENDED_STARTUPINFO_PRESENT, nullptr, nullptr, 
                     &siEx.StartupInfo, &pi_);
        
        return true;
    }
};
#endif
```

### 4.2 POSIX 兼容性（Linux/macOS）

**PTY 回退**:
```cpp
#ifndef WINDOWS_CONPTY
#include <pty.h>
#include <unistd.h>

class PosixPty {
public:
    bool spawn(const std::string& cmd) {
        int master;
        char name[256];
        openpty(&master, &slave_, name, nullptr, nullptr);
        
        pid_t pid = fork();
        if (pid == 0) {
            close(master);
            login_tty(slave_);
            execl("/bin/sh", "sh", "-c", cmd.c_str(), nullptr);
            exit(1);
        }
        return true;
    }
};
#endif
```

---

## 5. 安全加固

### 5.1 L2 Namespace 逃逸防护

**检查清单**:
- [ ] `unshare(CLONE_NEWUSER)` 禁用（防止用户命名空间提权）
- [ ] `proc` 和 `sys` 文件系统重新挂载为只读
- [ ] `ptrace` 系统调用被 Seccomp 禁止（防止进程注入）
- [ ] 禁止 `mount` 系统调用（防止重新挂载逃逸）

**Seccomp 白名单示例**（L2 最小权限）:
```cpp
void setup_strict_seccomp() {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_KILL);  // 默认拒绝
    
    // 允许的基本调用
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(write), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(exit_group), 0);
    
    // 允许的文件操作（但受 OverlayFS 限制）
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(openat), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(close), 0);
    
    // 禁止的危险调用
    seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ptrace), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(mount), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(umount2), 0);
    seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(chroot), 0);
    
    seccomp_load(ctx);
}
```

### 5.2 Unix Socket 性能优化

**大 Context 分片**（>1MB）:
```cpp
void send_large_context(int sock_fd, const std::string& data) {
    constexpr size_t CHUNK_SIZE = 64 * 1024;  // 64KB 分片
    
    size_t offset = 0;
    while (offset < data.size()) {
        size_t len = std::min(CHUNK_SIZE, data.size() - offset);
        send(sock_fd, data.data() + offset, len, MSG_NOSIGNAL);
        offset += len;
    }
}
```

**压缩策略**:
```cpp
Compression select_compression(size_t payload_size) {
    if (payload_size < 64 * 1024) return Compression::NONE;
    if (payload_size < 1024 * 1024) return Compression::ZLIB;
    return Compression::ZSTD;  // 大 payload 用 ZSTD
}
```

---

## 6. 测试矩阵

### 6.1 功能测试

| 测试项 | L0 | L1 | L2 | Branch 并发 | 级联 Session |
|--------|----|----|----|------------|-------------|
| DSL 解析 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 工具调用 | ✅ | ✅ | ✅ | ✅ | ✅ |
| LLM 推理 | ✅ | ✅ | ❌（禁止） | ✅（序列化） | ✅ |
| 文件操作 | ✅ | ✅ | ✅（OverlayFS）| ✅ | ✅ |
| 网络访问 | ✅ | ✅（过滤）| ✅（Namespace）| ✅ | ✅ |
| Fork/Join | ✅ | ✅ | ✅ | ✅ | ✅ |

### 6.2 性能测试

| 指标 | 目标值 | 测试方法 |
|------|--------|----------|
| L2 冷启动 | <50ms | `time acquire_l2_sandbox()` |
| L2 预热后 | <10ms | 进程池命中测试 |
| IPC 延迟 | <1ms（<1MB）| ping-pong 测试 |
| IPC 吞吐 | >100MB/s | 大文件传输测试 |
| SQLite WAL | >1000 TPS | 并发写入测试 |
| Branch 并发 | 加速比 >0.8×N | N 分支并行 vs 顺序执行 |

### 6.3 安全测试

| 攻击向量 | 防护验证 | 测试工具 |
|---------|---------|---------|
| 目录遍历 | `safe_join` 拦截 `../` | 模糊测试 |
| L2 逃逸 | Seccomp 拦截 `mount/ptrace` | `nsjail` 测试套件 |
| 资源耗尽 | Cgroups 限制生效 | `stress-ng` |
| 并发竞态 | `occupied_` 原子性 | ThreadSanitizer |

### 6.4 CI/CD 集成

**GitHub Actions 示例**:
```yaml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Dependencies
        run: |
          sudo apt-get install libseccomp-dev zlib1g-dev
      
      - name: Build
        run: |
          cmake -B build -DENABLE_L2_SANDBOX=ON
          cmake --build build -j$(nproc)
      
      - name: P0 Checks
        run: |
          # 检查线程安全 defer 使用
          grep -r "ws->send" src/ | grep -v "loop->defer" && exit 1
          # 检查协议版本硬编码
          grep -r '"2.1"' src/handlers/handshake_handler.hpp
      
      - name: Unit Tests
        run: ./build/test/localai_test --gtest_filter="*Sandbox*:*AgentPool*"
      
      - name: Integration Tests
        run: |
          ./build/localai_core --port 9001 &
          ./scripts/test_websocket_protocol.sh
```

---

## 7. 故障排查指南

### 7.1 常见错误码处理

| 错误码 | 现象 | 排查步骤 |
|--------|------|---------|
| `0x0002` | 客户端连接后立即断开 | 检查客户端协议版本是否为 2.1；检查握手消息格式 |
| `0x4001` | 请求卡住后返回"Pool Exhausted" | 检查 `AgentPool` 大小；检查是否有实例未正确 `release()` |
| `0x4004` | L2 沙箱崩溃 | 检查 `overlay-tmpfs-size` 是否足够；检查 Seccomp 规则是否过严 |
| `0x2004` | 权限错误 | 检查 DSL 是否尝试写入 `/lib/**`；检查沙箱级别是否不足 |

### 7.2 性能调优检查清单

- [ ] L2 进程池大小是否匹配并发需求？（建议：并发数 × 1.5）
- [ ] SQLite `busy_timeout` 是否设置？（推荐 5000ms）
- [ ] WebSocket `ack_batch_size` 是否根据网络延迟调整？（高延迟网络用更大的 batch）
- [ ] 是否启用了 IPC 压缩？（局域网可禁用，广域网建议启用）
