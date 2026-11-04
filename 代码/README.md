# RV32I 五级流水 CPU —— 紫光同创 FPGA 创新大赛赛题 1

基于 **RV32I 基础整数指令集 + Zicsr** 的五级流水线处理器工程骨架，包含可综合 RTL、
自检测试平台、自研汇编器与测试程序集，并已在 **Icarus Verilog 12** 与
**Vivado xsim 2023.1** 两套仿真器上全部跑通。

> 当前状态：基础任务（单周期/流水线内核 + 存储 + 基础外设 + 异常中断）已完成并通过回归；
> Cache、分支预测、AI 加速等高级任务在 `doc/03_后续路线.md` 中给出实施路径。

---

## 1. 目录结构

```
代码/
├── rtl/
│   ├── core/                 # 处理器内核
│   │   ├── riscv_defs.vh     #   全局常量（opcode/ALU/CSR/异常码）
│   │   ├── riscv_core.v      #   五级流水顶层（PC + 流水寄存器 + 冲突控制）
│   │   ├── riscv_decoder.v   #   指令译码 / 控制单元 / 立即数
│   │   ├── riscv_alu.v       #   32 位 ALU
│   │   ├── riscv_regfile.v   #   32x32 寄存器堆（2 读 1 写）
│   │   ├── riscv_hazard.v    #   转发 + load-use 停顿 + CSR 互锁
│   │   ├── riscv_btb.v       #   BTB + 两位饱和计数器分支预测
│   │   ├── riscv_divider.v   #   32 位恢复余数除法器（M 扩展）
│   │   ├── riscv_lsu.v       #   字节使能 / 符号扩展 / 非对齐访存
│   │   └── riscv_csr.v       #   CSR 寄存器组 + 异常/中断入口
│   ├── mem/
│   │   ├── imem.v            #   64 KB 指令存储器（4096 x 128 位，整行读）
│   │   ├── dmem.v            #   64 KB 数据存储器（128 位行读 + 16 字节使能写）
│   │   ├── icache.v          #   2 KB 指令 Cache（两路组相联）
│   │   └── dcache.v          #   2 KB 数据 Cache（两路组相联，写穿）
│   ├── ai/
│   │   └── ai_accel.v        #   INT8 矩阵-向量加速器（FC/RELU/ARGMAX）
│   ├── periph/               # UART TX/RX、GPIO、64 位定时器
│   └── soc/
│       ├── soc_top.v         #   SoC 顶层（内核 + 存储 + 外设 + 地址译码）
│       └── fpga_top.v        #   板级顶层（复位同步 + LED/按键/UART）
├── constraints/
│   ├── pango_pins_template.fdc   # PDS 引脚约束模板（按板卡填写）
│   └── timing_template.sdc       # PDS 时序约束模板
├── tb/
│   └── tb_soc.v              # 自检测试平台（+VCD/+TRACE/+EXTRACE/+DUMP）
├── sw/
│   ├── tools/rvasm.py        # 自研 RV32I 汇编器（免交叉工具链）
│   ├── tools/hexsplit.py     # Intel HEX -> imem.hex/dmem.hex
│   ├── tests/*.s             # 14 个自检测试程序（Cache/M/异常 专项）
│   ├── c/                    # 裸机 C 环境（crt0/link.ld/UART）
│   │   ├── bench.c           #   基准程序（筛法/矩阵/CRC/除法）
│   │   ├── coremark/         #   CoreMark 源码与本板 porting 层
│   │   ├── build.ps1         #   C 程序编译脚本
│   │   └── build_coremark.ps1#   CoreMark 编译脚本
│   └── build/                # 汇编输出（可选）
├── sim/
│   ├── run.ps1               # iverilog 一键汇编+编译+回归
│   ├── run_xsim.ps1          # Vivado xsim 交叉验证
│   └── work/                 # 仿真工作目录（imem.hex/dmem.hex/sim.vvp）
└── doc/
    ├── 01_架构设计.md
    ├── 02_验证报告.md
    └── 03_后续路线.md
```

## 2. 快速开始

### 2.1 全部测试（Icarus Verilog）

```powershell
cd 代码\sim
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Rebuild
```

输出示例：

```
Test         Result Cycles Commits  IPC
t01_alu      PASS   147    131     0.89
...
ALL 10 TESTS PASSED
```

### 2.2 单个测试 / 波形 / 轨迹

```powershell
.\run.ps1 -Test t06_sort                 # 只跑排序测试
.\run.ps1 -Test t06_sort -Trace          # 打印每条退休指令
.\run.ps1 -Test t06_sort -Vcd            # 生成 sim\work\tb_soc.vcd
.\run.ps1 -Test t06_sort -ExTrace        # 打印 EX 级操作数与转发选择
```

### 2.3 Vivado xsim 交叉验证

```powershell
cd 代码\sim
powershell -ExecutionPolicy Bypass -File .\run_xsim.ps1 -Test t01_alu -Rebuild
```

Vivado 路径在脚本内 `$vivado = 'F:\vivado\Vivado\2023.1'`，可自行修改。

### 2.4 手工汇编

```powershell
python sw\tools\rvasm.py sw\tests\t01_alu.s -o sim\work
# 生成 sim\work\imem.hex、dmem.hex、map.txt（符号表 + 列表）
```

## 3. 存储映射

| 地址范围 | 区域 | 说明 |
|---|---|---|
| `0x0000_0000 - 0x0000_FFFF` | IMEM 64 KB | 复位向量 `0x0`，异常向量 `mtvec` 默认 `0x40` |
| `0x1000_0000 - 0x1000_FFFF` | DMEM 64 KB | 数据/栈，字节写使能 |
| `0x2000_0000` | UART TX/RX | 写：发送字节；读：接收字节 |
| `0x2000_0004` | UART 状态 | `[1]=rx_valid, [0]=tx_busy` |
| `0x2000_1000 / 1004 / 1008` | GPIO | out / in / oe |
| `0x2000_2000 - 0x2000_200C` | TIMER | `mtime` lo/hi、`mtimecmp` lo/hi |
| `0x3000_0000` | 测试退出 | 写 `1` = PASS；写 `code<<1` = FAIL(code) |

## 4. 已实现指令

- **RV32I 全 37 条**：`LUI AUIPC JAL JALR BEQ BNE BLT BGE BLTU BGEU LB LH LW LBU LHU
  SB SH SW ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI ADD SUB SLL SLT SLTU XOR SRL
  SRA OR AND FENCE FENCE.I ECALL EBREAK`
- **M 扩展**：`MUL MULH MULHSU MULHU DIV DIVU REM REMU`
- **Zicsr**：`CSRRW CSRRS CSRRC CSRRWI CSRRCI CSRRWI` + `MRET`
- **Zifencei**：`FENCE.I` 作为 NOP
- 未实现：A/F/D/C 扩展（见后续路线）

## 5. 关键特性

| 特性 | 实现 |
|---|---|
| 流水级 | IF / ID / EX / MEM / WB |
| 数据通路 | 全转发（EX/MEM、MEM/WB）+ WB→ID 旁路 |
| 载入冒险 | load-use 停顿 1 拍 |
| 控制冒险 | 静态预测不跳转，EX 级解析；跳转清空 2 条指令 |
| 异常 | 非法指令、ECALL(M)、EBREAK、指令/数据地址非对齐（含 load/store） |
| 中断 | 机器定时器（MTIP）+ 外部中断（MEIP），mtvec 直接/向量模式，`mret` |
| CSR | mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip/mcycle/minstret |
| 非对齐访存 | 字/半字访问按对齐字处理（见限制说明） |
| I-Cache | 2 KB，64 组 x 2 路 x 4 字，伪 LRU，128 位整行突发填充（3 拍） |
| D-Cache | 2 KB，64 组 x 2 路 x 4 字，伪 LRU，写穿 + 不写分配，整行突发 |
| 分支预测 | 64 项 BTB + 两位饱和计数器，预测跳转零惩罚 |
| M 扩展 | MUL 系列在 MEM 级计算（依赖停顿 1 拍）；DIV/REM 32 拍迭代 |
| AI 加速 | 0x2000_4000 寄存器 + 0x2000_8000 8 KB 缓冲，INT8 FC/RELU/ARGMAX，4 路 MAC |
| 外设 | UART 8N1、GPIO、64 位定时器 |

## 6. 验证结果

15 个自检测试全部通过（iverilog 与 xsim 双仿真器），含 Cache 命中/缺失、
冲突、M 扩展、向量中断/非对齐异常专项，详见 `doc/02_验证报告.md`。

## 6b. 边缘 AI 加速（MNIST）

- 加速器：`0x2000_4000` 控制寄存器 + `0x2000_8000` 8 KB 本地缓冲；
  `FC`（INT8 矩阵-向量，4 路并行）、`RELU`、`ARGMAX`，硬件 busy/done 与周期计数。
- 模型：196-32-10 MLP（28x28 下采样到 14x14），权重 per-tensor 对称量化，
  激活按校准集定点缩放；Python 端 float 96.26% / INT8 仿真 96.19%。
- 实测：仿真跑 20 张测试图 **19/20 正确（95%）**，整程序 170,691 拍。
- 复现：
  ```powershell
  cd 代码\sw\ai ; python train_mnist.py        # 训练 + 量化 + 生成 mnist_data.h
  cd ..\c ; .\build.ps1 -Src mnist.c -Extra "-I../ai"
  cd ..\..\sim\work ; vvp sim.vvp +MAX=2000000 +UART
  ```

## 7. CoreMark

已移植 CoreMark 2K performance run，CRC 校验通过：

```
seedcrc   : 0xe9f5
crclist   : 0xe714
crcmatrix : 0x1fd7
crcstate  : 0x8e3a
crcfinal  : 0xe714
```

- 编译：`sw\c\build_coremark.ps1 -Iterations 1`
- 运行：`vvp sim.vvp +MAX=3000000 +UART`（`+UART` 解码串口打印）
- 1 次迭代计时区 **357,397 拍** ⇒ **≈2.80 CoreMark/MHz**（50 MHz 仿真时钟）

（EEMBC 要求单次运行 ≥10 秒，仿真相下用 CRC 校验证明功能正确，性能按拍数折算。）

## 8. 后续工作

见 `doc/03_后续路线.md`：Cache 两路组相联 / 关键块优先、BTB + 两位饱和计数器、
译码级分支解析、M 扩展、CoreMark 移植、PG2L200H 板级工程与 PDS 约束。
