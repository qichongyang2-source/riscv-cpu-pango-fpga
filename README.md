# RISC-V 指令集 CPU 设计（紫光同创 FPGA）

基于国产 FPGA 平台的 **RV32I 五级流水 RISC-V 处理器**，配套两路组相联 Cache、
BTB 动态分支预测、M 扩展乘除法、完整机器模式异常/中断，以及一块 **INT8 边缘 AI 加速器**（MNIST 推理）。

> 2026 紫光同创杯 FPGA 创新大赛 · 赛题一参赛作品（已适配紫光同创 PG2L200H 实验箱，完成板级仿真）

## 关键指标

| 指标 | 数值 |
|---|---|
| 流水线 / 指令集 | 5 级 / RV32I + Zicsr + M |
| Cache | 2 KB × 2 路 × 2 套，16 B 行，整行突发（缺失 3 拍） |
| 分支预测 | 64 项 BTB + 两位饱和计数器 |
| 主存 | 2 × 64 KB，4096 × 128 位（BRAM） |
| CoreMark | 357 397 拍/迭代，CRC 与官方一致，≈2.80 CoreMark/MHz |
| MNIST | 19/20（95%），INT8 加速器实测 |
| 综合 | 10 919 LUT / 3 726 FF / 28 BRAM / 20 DSP（Artix-7 OOC 估算） |

## 目录

| 路径 | 内容 |
|---|---|
| `代码/rtl/` | RTL：core（流水线/译码/ALU/冒险/BTB/CSR/乘除）、mem（Cache/主存）、ai、periph、soc |
| `代码/tb/` | 自检测试平台（TRACE / UART 解码 / STATS） |
| `代码/sw/tests/` | 15 个汇编自检测试 |
| `代码/sw/c/` | 裸机 C 运行时、bench、MNIST 推理、CoreMark 移植 |
| `代码/sw/ai/` | MNIST 训练与量化脚本 |
| `代码/sim/` | Icarus Verilog 与 Vivado xsim 一键脚本 |
| `文档/` | 技术文档、项目总结报告、架构图、仿真日志 |

## 快速开始

```powershell
# 15 项回归（需要 Icarus Verilog）
cd 代码/sim
powershell -ExecutionPolicy Bypass -File .\run.ps1 -Rebuild

# CoreMark
cd ../sw/c
powershell -ExecutionPolicy Bypass -File .\build_coremark.ps1 -Iterations 1
cd ../../sim/work
vvp sim.vvp +MAX=3000000 +UART

# MNIST（需先用 train_mnist.py 下载数据并训练）
cd 代码/sw/ai
python train_mnist.py
cd ../c
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Src mnist.c -Extra "-I../ai"
cd ../../sim/work
vvp sim.vvp +MAX=2000000 +UART
```

## 工具链

- 仿真：Icarus Verilog 12.0 / Vivado Simulator 2023.1
- 综合：Vivado 2023.1（Artix-7，OOC 评估；实际器件为紫光同创 PG2L200H，板级工程见 `rtl_flat/` 与 `文档/上板记录.md`）
- 交叉编译：riscv-none-elf-gcc 14.2.0（`-march=rv32im_zicsr -O2`）
- PC 端：Python 3 + numpy

## 许可与致谢

- CoreMark 源码遵循其原始许可（Apache-2.0），位于 `代码/sw/c/coremark/`。
- MNIST 数据集不随仓库分发，由 `train_mnist.py` 从官方地址下载后使用。
- 其余 RTL、测试、脚本为本作品原创。
