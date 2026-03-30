# CppHDL 状态机 DSL 设计文档

**创建时间**: 2026-03-30  
**状态**: 设计草稿  
**作者**: DevMate  

---

## 1. 设计目标

为 CppHDL 提供类似 SpinalHDL 的状态机 DSL，支持：
- 简洁的状态定义
- 清晰的状态转换
- 自动状态寄存器生成
- 组合/时序逻辑分离

---

## 2. SpinalHDL 状态机参考

### 2.1 SpinalHDL 语法

```scala
val stateMachine = new StateMachine {
  val stateA = State()
  val stateB = State()
  
  stateA.whenIsActive {
    when(cond) {
      goto(stateB)
    }
  }
  
  stateB.whenIsActive {
    goto(stateA)
  }
  
  setEntry(stateA)
}
```

### 2.2 核心概念

| 概念 | SpinalHDL | CppHDL 对应 |
|------|-----------|-----------|
| 状态机 | `StateMachine` | `ch_state_machine` |
| 状态 | `State()` | `state<S>::A` |
| 激活时 | `whenIsActive` | `on_active()` |
| 跳转 | `goto(state)` | `transition_to(state)` |
| 入口 | `setEntry` | `set_entry(state)` |

---

## 3. CppHDL 状态机 DSL 设计

### 3.1 API 设计

```cpp
#include "chlib/state_machine.h"

// 定义状态枚举
enum class MyState : uint8_t {
    IDLE,
    RUNNING,
    DONE
};

// 在 Component 中使用
class MyModule : public ch::Component {
public:
    __io(
        ch_in<ch_bool> start;
        ch_in<ch_bool> done;
        ch_out<ch_bool> busy;
    )
    
    void describe() override {
        // 创建状态机
        ch_state_machine<MyState, 3> sm;
        
        // 定义状态行为
        sm.state<MyState::IDLE>()
          .on_entry([]() {
              // 入口动作
          })
          .on_active([this, &sm]() {
              // 活跃时逻辑
              if (io().start) {
                  sm.transition_to(MyState::RUNNING);
              }
          });
        
        sm.state<MyState::RUNNING>()
          .on_active([this, &sm]() {
              if (io().done) {
                  sm.transition_to(MyState::DONE);
              }
          });
        
        sm.state<MyState::DONE>()
          .on_exit([]() {
              // 出口动作
          });
        
        // 设置入口状态
        sm.set_entry(MyState::IDLE);
        
        // 构建状态机（生成状态寄存器和逻辑）
        sm.build();
        
        // 输出当前状态
        io().busy = (sm.current_state() == MyState::RUNNING);
    }
};
```

### 3.2 简化版本（推荐初版）

```cpp
// 更简洁的 DSL，使用宏和链式调用
class MyModule : public ch::Component {
public:
    void describe() override {
        CH_STATE_MACHINE_BEGIN(sm, MyState, 3);
        
        CH_STATE_BEGIN(sm, MyState::IDLE)
            CH_ON_ACTIVE(
                if (io().start) sm.goto_state(MyState::RUNNING);
            )
        CH_STATE_END();
        
        CH_STATE_BEGIN(sm, MyState::RUNNING)
            CH_ON_ACTIVE(
                if (io().done) sm.goto_state(MyState::DONE);
            )
        CH_STATE_END();
        
        CH_STATE_BEGIN(sm, MyState::DONE)
            // 无动作
        CH_STATE_END();
        
        CH_STATE_MACHINE_END(sm, MyState::IDLE);
    }
};
```

---

## 4. 实现方案

### 4.1 方案 A: 模板元编程（推荐）

**优点**:
- 类型安全
- 编译时检查
- IDE 支持好

**缺点**:
- 实现复杂
- 编译时间稍长

**核心结构**:
```cpp
template <typename StateEnum, size_t N>
class ch_state_machine {
public:
    using state_type = StateEnum;
    
    // 状态定义
    struct state_def {
        std::function<void()> on_entry;
        std::function<void()> on_active;
        std::function<void()> on_exit;
    };
    
    // 状态数组
    std::array<state_def, N> states_;
    
    // 当前状态寄存器
    ch_reg<ch_uint<compute_bits(N)>> current_state_;
    
    // 下一状态
    ch_uint<compute_bits(N)> next_state_;
    
    // API
    state_def& state(StateEnum s) { return states_[static_cast<size_t>(s)]; }
    void transition_to(StateEnum s) { next_state_ = static_cast<uint8_t>(s); }
    StateEnum current_state() const { return static_cast<StateEnum>(current_state_.value()); }
    void set_entry(StateEnum s) { /* ... */ }
    void build() { /* 生成状态寄存器和转换逻辑 */ }
};
```

### 4.2 方案 B: 宏定义

**优点**:
- 实现简单
- 代码简洁

**缺点**:
- 调试困难
- 类型不安全

**核心宏**:
```cpp
#define CH_STATE_MACHINE_BEGIN(name, state_enum, n) \
    ch_state_machine<state_enum, n> name; \
    name.build_begin();

#define CH_STATE_BEGIN(sm, state) \
    sm.state_begin(state);

#define CH_ON_ACTIVE(code) \
    sm.on_active([&]() { code });

#define CH_STATE_MACHINE_END(sm, entry_state) \
    sm.build_end(entry_state);
```

---

## 5. 推荐实现（初版）

结合方案 A 的类型安全和方案 B 的简洁性：

```cpp
// 1. 定义状态枚举
enum class UartTxState : uint8_t {
    IDLE,
    START,
    DATA,
    STOP
};

// 2. 在 describe() 中使用
void describe() override {
    // 创建状态机
    ch_state_machine<UartTxState, 4> sm;
    
    // 状态：IDLE
    sm.state(UartTxState::IDLE)
      .on_active([this, &sm]() {
          io().uart_tx = true;
          io().busy = false;
          if (io().frame_start) {
              sm.transition_to(UartTxState::START);
          }
      });
    
    // 状态：START
    sm.state(UartTxState::START)
      .on_active([this, &sm]() {
          io().uart_tx = false;
          if (baud_counter == BAUD_LIMIT) {
              sm.transition_to(UartTxState::DATA);
              bit_counter = 0;
          }
      });
    
    // 状态：DATA
    sm.state(UartTxState::DATA)
      .on_active([this, &sm]() {
          // 发送数据位
      });
    
    // 状态：STOP
    sm.state(UartTxState::STOP)
      .on_exit([this, &sm]() {
          sm.transition_to(UartTxState::IDLE);
      });
    
    // 设置入口状态并构建
    sm.set_entry(UartTxState::IDLE);
    sm.build();
}
```

---

## 6. 状态机生成逻辑

### 6.1 状态寄存器

```cpp
// 当前状态寄存器
ch_reg<ch_uint<N>> state_reg;

// 下一状态逻辑
ch_uint<N> next_state;

// 状态转换
state_reg->next = next_state;
```

### 6.2 状态解码

```cpp
// 使用 one-hot 或 binary 编码
// Binary 编码（节省面积）
ch_bool is_state_A = (state_reg == 0);
ch_bool is_state_B = (state_reg == 1);

// One-hot 编码（速度快）
ch_bool is_state_A = state_reg[0];
ch_bool is_state_B = state_reg[1];
```

### 6.3 状态动作

```cpp
// 入口动作
if (state_changed && (next_state == STATE_A)) {
    // 执行 state_A 的 on_entry
}

// 活跃时动作
if (state_reg == STATE_A) {
    // 执行 state_A 的 on_active
}

// 出口动作
if (state_changed && (state_reg == STATE_A)) {
    // 执行 state_A 的 on_exit
}
```

---

## 7. 测试计划

### 7.1 单元测试

```cpp
TEST_CASE("State machine: Basic transition") {
    ch_device device;
    // 创建状态机
    // 验证状态转换
    // 验证入口/出口动作
}
```

### 7.2 集成测试

```cpp
TEST_CASE("UART TX: Complete frame") {
    ch_device device;
    // 发送完整帧
    // 验证波形
}
```

---

## 8. 实施计划

| 步骤 | 任务 | 工时 |
|------|------|------|
| 1 | 实现 ch_state_machine 核心模板 | 4h |
| 2 | 实现状态定义 API | 2h |
| 3 | 实现状态转换逻辑 | 2h |
| 4 | 实现入口/出口动作 | 2h |
| 5 | 单元测试 | 2h |
| 6 | UART TX 示例 | 4h |

**总计**: 16 小时（2 天）

---

## 9. 决策点

### Q1: 编码方式

- A) Binary 编码（节省面积）← 推荐
- B) One-hot 编码（速度快）
- C) 可配置

### Q2: Lambda 捕获

- A) 值捕获（安全）
- B) 引用捕获（灵活）← 推荐
- C) 混合

### Q3: 状态动作时机

- A) 组合逻辑（实时）← 推荐
- B) 时序逻辑（同步）

---

**版本**: v0.1（草稿）  
**状态**: 🟡 待评审
