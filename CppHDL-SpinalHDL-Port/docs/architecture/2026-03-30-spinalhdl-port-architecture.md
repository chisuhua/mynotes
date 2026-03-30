# SpinalHDL 示例移植架构设计

**创建时间**: 2026-03-30  
**状态**: 草稿  
**评审状态**: 待评审  

---

## 1. 目标与范围

### 1.1 目标
将 SpinalHDL 经典示例移植到 CppHDL 框架，验证 CppHDL 的功能完备性和易用性。

### 1.2 移植范围
- ✅ Counter（计数器）- P0
- ✅ FIFO（先进先出队列）- P0
- ✅ UART（串行通信）- P1
- ✅ GPIO（通用输入输出）- P1
- ✅ PWM（脉宽调制）- P2
- ✅ SPI Controller（SPI 控制器）- P2
- ⏸️ VGA Controller - P3（可选）
- ⏸️ RISC-V Core - P3（可选）

---

## 2. 架构设计原则

### 2.1 与现有 CppHDL 框架对齐
- 使用 `ch_uint<N>`, `ch_bool` 作为基础数据类型
- 时序逻辑使用 `ch_reg<T>` + `ch_pushcd` 时钟域
- 组合逻辑使用 `ch_comb` 作用域
- 模块接口使用 `ch_stream<T>`, `ch_bundle`

### 2.2 SpinalHDL 语义映射

| SpinalHDL 概念 | CppHDL 对应实现 |
|---------------|----------------|
| `UInt(N bits)` | `ch_uint<N>` |
| `Bool` | `ch_bool` |
| `RegInit(value)` | `ch_reg<T>{init_value}` |
| `when(cond) { ... }` | `ch_if(cond) { ... }` |
| `switch(value) { case(x) { ... } }` | `ch_switch(value) { ch_case(x) { ... } }` |
| `Stream(DataType)` | `ch_stream<DataType>` |
| `Flow(DataType)` | `ch_flow<DataType>` |
| `Bundle { ... }` | `struct : bundle_base<...>` |
| `Component` | `class : ch_device<...>` |

---

## 3. 示例详细设计

### 3.1 Counter（计数器）

**SpinalHDL 原代码**:
```scala
class Counter extends Component {
  val io = new Bundle {
    val enable = in Bool()
    val clear = in Bool()
    val value = out UInt(8 bits)
  }
  
  val counterReg = RegInit(U(0, 8 bits))
  when(io.clear) {
    counterReg := 0
  } elsewhen(io.enable) {
    counterReg := counterReg + 1
  }
  io.value := counterReg
}
```

**CppHDL 移植设计**:
```cpp
#include "ch.hpp"
#include "core/reg.h"
#include "core/uint.h"

using namespace ch::core;

class Counter : public ch_device<Counter> {
public:
    // IO 定义
    ch_bool enable;
    ch_bool clear;
    ch_uint<8> value;
    
    // 内部寄存器
    ch_reg<ch_uint<8>> counter_reg{0};
    
    void describe() {
        ch_pushcd(clk, rst);  // 时钟域
        
        ch_comb {
            // 使用 ch_nextEn 实现条件更新
            counter_reg.next() = ch_nextEn(
                counter_reg + 1,  // 新值
                enable,           // 使能条件
                0                 // 复位值
            );
            
            // 优先复位
            if (clear) {
                counter_reg.next() = 0;
            }
            
            value = counter_reg;
        }
    }
};
```

**验收标准**:
- [ ] 编译通过（CMake）
- [ ] 仿真输出正确波形（VCD）
- [ ] 生成 Verilog 可综合
- [ ] 单元测试通过（Catch2）

---

### 3.2 FIFO（先进先出队列）

**SpinalHDL 原代码**:
```scala
class Fifo extends Component {
  val io = new Bundle {
    val push = slave Stream(UInt(8 bits))
    val pop = master Stream(UInt(8 bits))
    val occupancy = out UInt(3 bits)
  }
  
  val mem = Mem(UInt(8 bits), 8)
  val wrPtr = RegInit(U(0, 3 bits))
  val rdPtr = RegInit(U(0, 3 bits))
  
  when(io.push.fire) {
    mem(wrPtr) := io.push.payload
    wrPtr := wrPtr + 1
  }
  
  when(io.pop.fire) {
    rdPtr := rdPtr + 1
  }
  
  io.pop.payload := mem(rdPtr)
  io.occupancy := wrPtr - rdPtr
}
```

**CppHDL 移植设计**:
```cpp
#include "chlib/stream.h"
#include "chlib/fifo.h"
#include "core/mem.h"

template<unsigned DATA_WIDTH = 8, unsigned DEPTH = 8>
class Fifo : public ch_device<Fifo<DATA_WIDTH, DEPTH>> {
public:
    // IO 定义
    ch_stream<ch_uint<DATA_WIDTH>> push;
    ch_stream<ch_uint<DATA_WIDTH>> pop;
    ch_uint<3> occupancy;
    
    // 内部状态
    ch_mem<ch_uint<DATA_WIDTH>, DEPTH> mem;
    ch_reg<ch_uint<3>> wr_ptr{0};
    ch_reg<ch_uint<3>> rd_ptr{0};
    
    void describe() {
        ch_pushcd(clk, rst);
        
        ch_comb {
            // 写操作
            if (push.valid && !full()) {
                mem[wr_ptr] = push.payload;
                wr_ptr.next() = wr_ptr + 1;
                push.ready = true;
            } else {
                push.ready = false;
            }
            
            // 读操作
            if (pop.ready && !empty()) {
                rd_ptr.next() = rd_ptr + 1;
                pop.valid = true;
                pop.payload = mem[rd_ptr];
            } else {
                pop.valid = false;
            }
            
            // 占用计数
            occupancy = wr_ptr - rd_ptr;
        }
    }
    
private:
    ch_bool full() { return (wr_ptr - rd_ptr) == DEPTH; }
    ch_bool empty() { return wr_ptr == rd_ptr; }
};
```

**验收标准**:
- [ ] 支持 backpressure（反压）
- [ ] 空满标志正确
- [ ] 读写指针不溢出
- [ ] 仿真验证数据完整性

---

### 3.3 UART TX（串行发送）

**SpinalHDL 原代码**:
```scala
class UartTx extends Component {
  val io = new Bundle {
    val frameStart = in Bool()
    val data = in UInt(8 bits)
    val uartTx = out Bool()
    val busy = out Bool()
  }
  
  val baudCounter = RegInit(U(0, 16 bits))
  val bitCounter = RegInit(U(0, 3 bits))
  val state = RegInit(U(0, 2 bits))  // IDLE, START, DATA, STOP
  
  val shiftReg = RegInit(U(0xFF, 9 bits))  // 9 bits: start(0) + 8 data
  
  // 波特率发生器、状态机、移位寄存器逻辑...
}
```

**CppHDL 移植设计**:
```cpp
template<unsigned BAUD_RATE = 115200, unsigned CLK_FREQ = 50000000>
class UartTx : public ch_device<UartTx<BAUD_RATE, CLK_FREQ>> {
public:
    // IO 定义
    ch_bool frame_start;
    ch_uint<8> data;
    ch_bool uart_tx;
    ch_bool busy;
    
    // 状态枚举
    enum class State : uint8_t { IDLE, START, DATA, STOP };
    
    // 内部状态
    ch_reg<ch_uint<16>> baud_counter{0};
    ch_reg<ch_uint<3>> bit_counter{0};
    ch_reg<State> state{State::IDLE};
    ch_reg<ch_uint<9>> shift_reg{0x1FF};  // 空闲状态
    
    void describe() {
        ch_pushcd(clk, rst);
        
        constexpr unsigned BAUD_LIMIT = CLK_FREQ / BAUD_RATE;
        
        ch_comb {
            // 状态机
            ch_switch(state) {
                ch_case(State::IDLE) {
                    uart_tx = true;
                    busy = false;
                    if (frame_start) {
                        state.next() = State::START;
                        shift_reg.next() = {data, 1'b0};  // 添加起始位
                    }
                }
                
                ch_case(State::START) {
                    if (baud_counter == BAUD_LIMIT - 1) {
                        baud_counter.next() = 0;
                        state.next() = State::DATA;
                        bit_counter.next() = 0;
                    } else {
                        baud_counter.next() = baud_counter + 1;
                    }
                }
                
                ch_case(State::DATA) {
                    // 发送 8 位数据...
                }
                
                ch_case(State::STOP) {
                    // 发送停止位...
                }
            }
        }
    }
};
```

**验收标准**:
- [ ] 波特率准确（误差 < 2%）
- [ ] 帧格式正确（1 起始位 +8 数据位 +1 停止位）
- [ ] 忙标志正确
- [ ] 环回测试通过

---

## 4. 任务分解与实施计划

### Phase 1: 基础示例（2 周）
- [ ] Task 001: Counter - 3 小时
- [ ] Task 002: FIFO - 8 小时
- [ ] Task 003: 单元测试框架搭建 - 4 小时
- [ ] Task 004: VCD 波形生成验证 - 2 小时

### Phase 2: 通信协议（3 周）
- [ ] Task 005: UART TX - 8 小时
- [ ] Task 006: UART RX - 8 小时
- [ ] Task 007: GPIO - 4 小时
- [ ] Task 008: PWM - 6 小时

### Phase 3: 高级示例（3 周）
- [ ] Task 009: SPI Controller - 12 小时
- [ ] Task 010: I2C Controller - 12 小时
- [ ] Task 011: VGA Controller（可选）- 20 小时

### Phase 4: 集成与文档（1 周）
- [ ] Task 012: 集成测试 - 8 小时
- [ ] Task 013: 文档整理 - 8 小时
- [ ] Task 014: 性能对比报告 - 4 小时

---

## 5. 验收标准

### 5.1 代码质量
- [ ] 编译无警告（`-Wall -Wextra -Wpedantic`）
- [ ] 通过 clang-format 格式化
- [ ] 通过 cpplint 检查
- [ ] 单元测试覆盖率 > 80%

### 5.2 功能验证
- [ ] C++ 仿真结果正确
- [ ] 生成 Verilog 仿真结果一致
- [ ] 可综合（通过综合工具检查）

### 5.3 文档完整
- [ ] 每个示例有 README.md
- [ ] 有波形截图
- [ ] 有 SpinalHDL 原代码对比

---

## 6. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| CppHDL 缺少某些原语 | 高 | 先实现缺失原语（如 ch_mem） |
| 仿真与 Verilog 行为不一致 | 高 | 每个示例都进行双仿真验证 |
| 任务延期 | 中 | 优先完成 P0/P1 示例，P3 可选 |

---

## 7. 下一步行动

1. **架构评审**：等待老板评审本设计文档
2. **同步到编码仓库**：评审通过后同步到 `/workspace/CppHDL/docs/architecture/`
3. **开始 Phase 1**：执行 Task 001 (Counter)

---

**评审人**: 待指定  
**评审日期**: 待安排  
**状态**: 🟡 草稿（待评审）
