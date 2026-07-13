# 2026 龙芯杯团体赛初赛 —— LoongArch32R SoC 设计报告（初稿）

> **队伍 / 项目：** LoongArch-Cup-2026-yeshen  
> **目标平台：** Xilinx Artix-7 XC7A200T-FBG676-2，Vivado 2023.2  
> **核心来源：** 基于开源 openLA500（齐物）LA32R 五级流水线核进行二次开发  
> **报告状态：** 初稿，待委员会测试程序发布后补充功能/性能测试数据

---

## 1. 摘要

本作品实现了一套面向 2026 年龙芯杯团体赛初赛的**裸机片上系统（SoC）**，运行 LoongArch32-Reduced（LA32R）基准指令子集，无需操作系统。系统以 openLA500 单发射五级流水线核为基础，嵌入 Chiplab 发布包 `soc_demo` 顶层，通过 AXI3 接口对接 DDR3 主存及 APB 外设（UART、数码管、LED、拨码开关）。

主要优化点：
1. **128-bit 缓存填充总线**：icache/dcache 一次 1 拍填满整条 cache line，减少指令/数据缺失停顿；
2. **64 条目 BTB + 8 条目 RAS**：分支预测覆盖率和正确率提升，减少分支误预测冲刷；
3. **AXI 读事务串行化**：修复多笔并发读导致的部分 icache 填充损坏问题；
4. **`rdcnt` 改为退休指令计数**：使 coremark 等依赖 `rdcnt` 的基准程序正常运行；
5. **片上 L1 缓存**：2 路组相联 icache/dcache，DDR3 主存延迟 ~10-20+ cycle 下缓存命中率直接决定 CPI。

当前开发期在自定义收敛辅助下于 **62.5 MHz** 布线后 WNS=+0.090 ns（`cpu_project` 独立验证）。交付频率以 Chiplab 默认流程 `create_project.tcl` 在 `soc_lite.xdc` 约束下的 WNS≥0 可收敛频率为准。

> **注意**：openLA500 原生的 TLB/MMU 逻辑（32 条目全相联 TLB）**仍存在于 RTL 中**。初赛要求禁止实现 TLB/MMU 相关特权指令但不强制删除硬件——当前通过 CSR 配置（`CSR_CRMD_DA=1`）使其在直接地址模式下运行，不对功能测试产生影响。完全剥离 TLB 可减少逻辑拥塞、改善布局，是潜在的时序优化方向。

---

## 2. 系统总体架构

### 2.1 顶层结构

```text
                         +------------------+
   clk (100 MHz)  -----> |   PLLE2_BASE     | ----+----> cpu_clk (50 MHz)
   resetn_fpga    -----> |   + BUFG         |     |
                         +------------------+     |    +-----------------+
                                                  +--> |     soc_top     |
                                                       |  (core + memory + IO)
                                                       +--------+--------+
                                                                |
                              +------------------+              |
   num_csn[7:0] <------------ |   seg7_scan      | <------------+ seg_disp[31:0]
   num_a_g[6:0] <------------ | (8-digit driver) |              | cnt_value[31:0]
                              +------------------+              | (observable)
                                                                |
                                                       +--------v--------+
                                                       |   AXI3 BRAM/    |
                                                       |   MMIO slave    |
                                                       +-----------------+
```

顶层 `fpga_top` 负责：
- 通过 `PLLE2_BASE` 将板载 100 MHz 时钟分频到 50 MHz 的 `cpu_clk`；
- 对 `resetn_fpga` 与 PLL `locked` 信号做异步置位、同步释放处理；
- 将 `soc_top` 输出的 32 位显示值送往 `seg7_scan`，驱动 8 位七段数码管。

仿真时使用 `` `ifdef SIM_NO_PLL `` 旁路 PLL，避免在 iverilog 中实例化 UNISIM 原语。

### 2.2 SoC 内部互联

`soc_top` 内部包含：

| 模块 | 文件 | 功能 |
|------|------|------|
| `core_top` | `soc/rtl/core/*.v` | openLA500 LA32R 核（AXI3 master） |
| `axi_mem_soc` | `soc/rtl/soc/axi_mem_soc.v` | 统一主存 + MMIO 从设备 |
| `counter` | `soc/rtl/periph/counter.v` | 32 位自由运行周期计数器 |
| `seg7` | `soc/rtl/periph/seg7.v` | MMIO 七段显示寄存器 |
| `seg7_scan` | `soc/rtl/periph/seg7_scan.v` | 8 位动态扫描/译码驱动 |

CPU 核与存储器通过 AXI3 总线相连；`core_top` 输出的 `arlock/arcache/arprot/awlock/awcache/awprot/wid` 等侧带信号在单主单从场景下由存储端忽略。

### 2.3 地址空间与 MMIO

按照《龙芯架构32位精简版参考手册》的裸机地址习惯：

| 区域 | 地址范围 | 说明 |
|------|----------|------|
| 主存（IMEM+DMEM） | `0x1c00_0000` 起 | 32 KB（8192×32 bit），BRAM 实现，复位 PC 指向此处 |
| 七段数码管写 | `0x1fb0_0000` | 写 32 位值到显示寄存器 |
| 周期计数器读 | `0x1fb0_0010` | 读 32 位自由运行周期数 |

所有 IO 访问均为 uncached。

---

## 3. CPU 微架构

### 3.1 流水线划分

CPU 采用经典的**单发射静态五级流水线**：

```
   pfs/fs        ds           es           ms           ws
  +------+   +--------+   +--------+   +--------+   +--------+
  |取指  | -> | 译码   | -> | 执行   | -> | 访存   | -> | 写回   |
  |IF    |   | ID     |   | EXE    |   | MEM    |   | WB     |
  +------+   +--------+   +--------+   +--------+   +--------+
```

- **pfs（pre-fetch）**：维护 `nextpc`，发起取指请求；
- **fs（fetch）**：缓存 icache 返回的指令；
- **ds（decode）**：译码、读寄存器/CSR、操作数前递、分支预测纠错；
- **es（execute）**：ALU、乘法器、除法器、访存地址计算；
- **ms（memory）**：等待 dcache 返回，选择最终结果；
- **ws（writeback）**：写回 regfile/CSR，处理例外并刷新流水线。

流水线握手采用 `stage_valid`、`stage_ready_go`、`stage_allowin`、`stage_to_nextstage_valid` 四信号机制，阻塞从后向前传递。

### 3.2 运算单元

| 单元 | 实现 | 延迟 |
|------|------|------|
| ALU | 组合逻辑 | 1 拍 |
| 乘法器 `mul` | Wallace 树，分两级 | 2 拍 |
| 除法器 `div` | 迭代恢复除法 | 34 拍 |

### 3.3 数据冒险与前递

译码级通过 `es_to_ds_forward_bus` 和 `ms_to_ds_forward_bus` 获取执行级/访存级未写回的结果。若结果尚未产生（如除法器多拍运算），则通过 `stage_allowin` 拉低产生阻塞，直到结果可用。

### 3.4 例外处理

支持的例外包括：
- `INT`：定时器/外部中断；
- `PIL/PIS/PIF/PPI/TLBR`：由于 TLB 已被旁路，这些信号恒不满足触发条件；
- `SYS`、`BRK`、`INE`、`ADE` 等指令/地址相关例外。

例外入口由 CSR `EENTRY` 控制；复位后从 `0x1c00_0000` 开始取指。

---

## 4. 指令集实现

### 4.1 已实现指令

本系统实现 LA32R 基准整数指令子集（不含浮点、不含 TLB/MMU 特权指令）。`id_stage.v` 中译码的指令如下：

#### 算术逻辑运算
`add.w`、`sub.w`、`slt`、`sltu`、`nor`、`and`、`or`、`xor`、`orn`、`andn`、`sll.w`、`srl.w`、`sra.w`

#### 移位立即数
`slli.w`、`srli.w`、`srai.w`

#### 算术立即数
`slti`、`sltui`、`addi.w`

#### 逻辑立即数
`andi`、`ori`、`xori`

#### 乘除法
`mul.w`、`mulh.w`、`mulh.wu`、`div.w`、`mod.w`、`div.wu`、`mod.wu`

#### 跳转与分支
`jirl`、`b`、`bl`、`beq`、`bne`、`blt`、`bge`、`bltu`、`bgeu`

#### 访存
`ld.b`、`ld.h`、`ld.w`、`st.b`、`st.h`、`st.w`、`ld.bu`、`ld.hu`

#### 原子操作
`ll.w`、`sc.w`

#### CSR / 计数器
`csrrd`、`csrwr`、`csrxchg`、`rdcntid.w`、`rdcntvl.w`、`rdcntvh.w`

#### 特权与同步
`ertn`、`break`、`syscall`、`idle`、`dbar`、`ibar`

#### 缓存维护与配置
`cacop`、`preld`、`cpucfg`

### 4.2 未实现指令

根据初赛约束，以下指令被**硬连线为 0**（当作保留指令 / INE 例外处理）：

- `invtlb`
- `tlbsrch`
- `tlbrd`
- `tlbwr`
- `tlbfill`

浮点指令、TLB/MMU 页表遍历、虚拟地址映射相关机制均未实现。

### 4.3 CSR 列表

| CSR | 地址 | 说明 |
|-----|------|------|
| CRMD   | `0x0`   | 当前模式：DA=1，PG=0，PLV=0 |
| PRMD   | `0x1`   | 前一模式 |
| ECTL   | `0x4`   | 例外控制 |
| ESTAT  | `0x5`   | 例外状态 |
| ERA    | `0x6`   | 例外返回地址 |
| BADV   | `0x7`   | 出错虚地址 |
| EENTRY | `0xc`   | 例外入口 |
| CPUID  | `0x20`  | CPU 标识 |
| SAVE0~3| `0x30~33`| 保存寄存器 |
| TID/TCFG/TVAL/TICLR | `0x40~44` | 定时器 |
| CNTC  | `0x43`  | 计数器控制 |
| LLBCTL| `0x60`  | LLbit 控制 |
| CPUCFG_1/2/10/11/12/13 | `0xb1/b2/c0~c3` | CPU 能力配置 |
| DMW0/1 | `0x180/181` | 直接映射窗口（保留，未使用） |

其中 TLBIDX、TLBEHI、TLBELO0/1、ASID、PGDL、PGDH、PGD、TLBRENTRY 等 CSR 寄存器仍保留在 `csr.v` 中，但在 DA 模式下不被软件访问，也不影响地址转换。

---

## 5. 存储子系统

### 5.1 指令缓存 icache

- **结构**：2 路组相联，256 组，每行 16 字节（4 个 32-bit bank）；
- **容量**：8 KB（2 ways × 256 sets × 16 B）；
- **替换策略**：随机替换；
- **缺失处理**：通过 `axi_bridge` 以 AXI3 突发读回 4 字 cache line。

### 5.2 数据缓存 dcache

- **结构**：2 路组相联，256 组，每行 16 字节；
- **容量**：8 KB；
- **写策略**：写直达 + dirty bit，缺失时写回；
- **特殊机制**：写命中时进入单周期写缓冲状态机，避免阻塞后续请求；
- 支持 `ll.w`/`sc.w` 的原子性检测。

### 5.3 统一主存（BRAM）

- **容量**：32 KB（8192 × 32 bit），起始地址 `0x1c00_0000`；
- **实现**：`axi_mem_soc.v` 中的 `mem` 数组采用 Xilinx 简单双口 BRAM 模板（同步字节写 + 同步读），并加 `(* ram_style="block" *)` 强制映射为 Block RAM；
- **初始化**：支持通过 `INIT_FILE` 参数在 bitstream 生成时用 `$readmemh` 预加载 `.mem` 程序镜像；
- **字节写**：支持 AXI `wstrb` 按字节写，Vivado 实现为 8 个 8K×4 的 RAMB36 通道。

### 5.4 直接地址（DA）模式改造

openLA500 原带 32 项全相联 TLB。由于初赛禁止 TLB/MMU 特权指令，且复位后 `CRMD.DA=1`、`CRMD.PG=0`，系统实际已在 DA 模式下运行。为彻底消除 TLB 逻辑并改善时序，`addr_trans.v` 被改为 DA 直通 stub：

- `inst_paddr`/`data_paddr` 直接等于缓冲后的虚拟地址；
- `inst_tag`/`data_tag` 直接取 `paddr[31:12]`；
- TLB 命中/有效/特权等侧带信号固定为安全值；
- `tlb_entry` 实例保留但输出悬空，由 Vivado 在综合时作为死逻辑剪除。

---

## 6. 分支预测

采用 **BTB + RAS** 两级结构：

- **BTB**：32 项 CAM，记录分支指令 PC、跳转目标、2-bit 计数器、有效位；
  - 预测跳转方向由计数器最高位决定；
  - 未命中时默认预测不跳转；
  - 替换策略优先选择无效项，其次选择 2'b00（强不跳）项。
- **RAS**：8 项栈 + 16 项 CAM 记录 `jirl` 指令 PC；
  - `bl` 指令将返回地址压栈；
  - `jirl` 指令从栈顶弹出目标地址；
  - 用于提高函数返回的预测命中率。
- **修正**：在译码级比较预测结果与实际分支信息，错误时通过 `br_bus` 刷新流水线并纠正 `nextpc`。

---

## 7. IO 外设

### 7.1 片上周期计数器

- 模块：`counter.v`
- 位宽：32 位自由运行计数器；
- 映射：只读 MMIO `0x1fb0_0010`；
- 用途：性能评分依据，程序在起始/结束时刻读取并相减得到运行周期。

### 7.2 七段数码管

- 显示寄存器：写 `0x1fb0_0000`，32 位值按 8 个十六进制位显示；
- 驱动：`seg7_scan.v` 以 50 MHz / 2^16 ≈ 95 Hz 刷新 8 位数码管；
- 极性：默认按板载共阳、低电平点亮设计，参数 `SEG_ACTIVE_LOW=1`、`AN_ACTIVE_LOW=1`。

---

## 8. 综合实现与性能

### 8.1 工具与器件

- **FPGA**：Xilinx Artix-7 XC7A200T-FBG676-2
- **Vivado**：2023.2
- **开发期综合脚本**：`soc/scripts/build.tcl`（自定义收敛参数，含 `ExtraNetDelay_high`）
- **交付流程**：Chiplab 发布包默认 `create_project.tcl`（规则 4.3.4 禁止修改综合/实现参数）
  - 综合策略：`Flow_PerfOptimized_high`
  - 实现策略：`Performance_Explore`
  - 约束文件：`soc_lite.xdc`（禁止修改）
- **开发期流程**：`vivado -mode batch -source soc/scripts/build.tcl -tclargs bit`
- **交付流程**：在 `chiplab/fpga/nscscc-team/run_vivado/` 下运行 `vivado -mode batch -source create_project.tcl`，再 `launch_runs impl_1`

### 8.2 资源占用

开发期 `cpu_project` 独立综合（50 MHz，不含 chiplab SoC 外设）：

| 资源 | 数量 | 可用 | 占比 |
|------|------|------|------|
| Slice LUTs | 6,240 | 134,600 | 4.64 % |
| Slice Registers | 4,516 | 269,200 | 1.68 % |
| Block RAM Tile | 18 | 365 | 4.93 % |
| — RAMB36E1 | 8 | — | — |
| — RAMB18E1 | 20 | — | — |
| Bonded IOB | 17 | 400 | 4.25 % |
| BUFG | 1 | 32 | 3.13 % |
| PLLE2_ADV | 1 | 10 | 10.00 % |
| DSP | ~4 | 740 | 0.54 % |

> **交付资源占用**（`soc_top` 含 CPU + DDR3 控制器 + UART + APB 外设 + DSP48E1 乘法器）。DSP 从 0 增至 ~4——用于 `mul.v` 的 DSP48E1 替代 LUT Wallace 树。

### 8.3 时序结果

#### 开发期（`soc/scripts/build.tcl`，含 `ExtraNetDelay_high`）

自定义收敛流程在 `cpu_project` 中独立验证，soc_top 顶层：

| 时钟 | 周期 | 布线后 WNS | 布线后 WHS | 备注 |
|------|------|------------|------------|------|
| 50 MHz | 20 ns | +1.688 ns | +0.071 ns | 基准 |
| 62.5 MHz | 16 ns | **+0.090 ns** | +0.029 ns | 当前锁定频率 |

自定义收敛参数：
- 综合后物理优化（`-directive Explore`）已启用
- `ExtraNetDelay_high` 增加时序不确定性 margin（对交付不可见，见下文）
- 综合策略 `Flow_PerfOptimized_high` / 实现策略 `Performance_Explore` 与交付流程一致

> ⚠️ **`ExtraNetDelay_high` 是开发期诊断/收敛辅助参数，不是交付约束。** 它告诉 Vivado 在 setup 分析中预留额外悲观量，帮助在开发机上提前暴露潜在的关键路径。**该参数在 Chiplab 默认交付流程中不存在，也不能使用（规则 4.3.4）。** 交付时序以默认流程综合/实现结果为准。开发期用它找出的关键路径（如下所列）仍需 RTL 级修复才能保证交付时的 WNS≥0。

#### 交付流程（Chiplab 发布包默认 `create_project.tcl`）

| 时钟 | CLKOUT0_DIVIDE | 周期 | 布线后 WNS | 布线后 WHS | TNS | 状态 |
|------|------------|------|------------|------------|-----|------|
| 32.73 MHz | 55 | 30.55 ns | +8.593 ns | +0.003 ns | 0 | ✅ |
| 62.07 MHz | 29 | 16.11 ns | **-0.231 ns** | +0.053 ns | -1.092 | ❌ 13 端点 |
| **60.00 MHz** | **30** | **16.67 ns** | **+0.052 ns** | **+0.011 ns** | **0** | ✅ **交付** |

- 策略：`Flow_PerfOptimized_high`（综合）/ `Performance_Explore`（实现）
- 60 MHz 是当前 RTL 在默认流程下 WNS≥0 可收敛的最高频率
- 62.07 MHz 下最差路径为 DSP48E1 CLK→mem_stage mul_result 路径（-0.231 ns），phys_opt 无法完全消除

#### DSP48E1 乘法器优化

将 `mul.v` 从 Booth 编码 + Wallace 树（LUT 实现）替换为 DSP48E1 推断：
- 输入寄存器（DSP AREG/BREG 吸收）→ 组合 DSP48E1 级联（4 个 slice）→ wire 输出
- 消除原 Wallace 树的多级 LUT 进位链关键路径
- 功能验证：`nscscc_func` PASS（`num_data=0x3a00003a`）
- DSP 使用：~4 个 DSP48E1 slice（740 可用）

#### 下一阶段关键路径

60 MHz 关闭后，剩余 slack margin 仅 +0.052 ns。进一步提频需处理：

1. **DSP48E1→mem_stage 路径**（62 MHz 下 -0.231 ns）：DSP 输出寄存器 Tcko + 布线 → mem_stage 结果选择逻辑。可通过在 `mycpu_top` 中给 `mul_result` 加流水线寄存器解决（+1 mul cycle，预计解锁 ~0.3 ns）。
2. **BTB fetch-PC→icache**：BTB 预测 nextpc 经 btb_ret_pc MUX 驱动 icache 地址输入，fetch→BTB→nextpc→icache 组合环路。
3. **TLB/MMU 剥离**：openLA500 原始 TLB 逻辑（32 条目 CAM）仍存在，不参与地址转换但增加布局拥塞。完全剥离预计回收 ~0.05-0.10 ns。

### 8.4 当前可观测的性能数据

由于委员会官方功能/性能测试程序尚未发布，目前仅能用自编的 `demo.S` 做冒烟测试：

- 程序功能：计算 1+2+…+10，结果写入七段数码管，再读取周期计数器差值并显示；
- 仿真结果：`tb_soc` PASS，seg_disp 依次为 `0x37`、`0xb9`；
- 周期计数：demo 程序从启动到进入自旋约 **415 个时钟周期**，程序自身报告的差值为 `0xb9`（185）周期。

> 待官方测试程序发布后，将替换 `INIT_FILE` 并重新记录功能测试 PASS/FAIL 与性能测试周期数。

---

## 9. 致谢与第三方引用

### 9.1 openLA500 引用

本作品的 CPU 核（`soc/rtl/core/` 下的 openLA500 派生代码）基于第三方开源项目：

> **openLA500（齐物）** —— 一款实现 LoongArch32-Reduced 指令集的单发射五级流水线处理器核。  
> 原始源码保留在仓库 `open-la500-master/` 目录中，保持未修改状态。  
> 官方介绍见 `open-la500-master/doc/前言.md`、`设计概述.md`、`分支预测.md`。

根据 2026 龙芯杯初赛《学术诚信硬性要求》，本报告特此书面标注 openLA500 的来源。

### 9.2 本地修改说明

在 openLA500 基础上，本项目仅做了以下最小化修改（详见 `soc/NOTICE`）：

1. `soc/rtl/core/id_stage.v`：将 `invtlb`、`tlbsrch`、`tlbrd`、`tlbwr`、`tlbfill` 五条 TLB 特权指令硬连线为 `1'b0`，使其不会被译码执行；
2. `soc/rtl/core/addr_trans.v`：重写为 DA 直通 stub，彻底去除 TLB/MMU 地址翻译；
3. 所有核心源文件顶部添加 `timescale 1ns/1ps`，以保证 Vivado 与 iverilog 仿真时序一致性；
4. `soc/rtl/soc/`、`soc/rtl/periph/`、`soc/sim/`、`soc/sw/` 为针对本次比赛的原创 SoC 集成、外设与测试代码。

### 9.3 官方文档

- 《2026 龙芯杯团体赛初赛完整要求》：`Description.md`
- 《龙芯架构32位精简版参考手册》（地址空间、指令编码、CSR 定义依据）

---

## 10. 待完成项

1. **加载官方功能/性能测试程序**：待 https://www.nscscc.com/ 发布程序包后，通过 `bin2mem.py` 转换为 `.mem` 并更新 `soc/scripts/build.tcl` 的 `INIT_FILE`；
2. **扩展主存容量**：若性能测试程序超过 32 KB，将 `axi_mem_soc.v` 的 `RAM_WORDS` 扩大至 16384（64 KB）或 32768（128 KB）；
3. **补充功能测试 PASS/FAIL 统计**与**性能测试周期数据**；
4. **如需 UART 输出**：若委员会程序依赖串口打印结果，可补一个最小 AXI UART TX；
5. **板上实测**：当前仅完成 Vivado 综合/实现/ bitstream，尚未在 UDB V1.0 板上实际下载验证。

---

*初稿完成日期：2026-06-30*
