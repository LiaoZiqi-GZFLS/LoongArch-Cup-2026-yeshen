# 龙芯杯 CPU Demo 设计方案（基于 openLA500 复制改造）

- 日期：2026-06-29
- 方向：B2-甲-i —— 复制 openLA500 核改造 + 自写最小 SoC（纯 RTL）+ 手写演示程序，自包含可仿真
- 目标：搭出一个能在仿真里跑通"取指 → 流水线执行 → 写数码管 → 读周期计数器"完整链路的最小可演示 SoC，作为后续比赛工程的起点

---

## 1. 背景与约束

来自 `Description.md` 的硬性约束：

- ISA：LA32R 精简基准子集；**禁止浮点、禁止 TLB/MMU 虚拟内存特权指令**。
- 存储：仅用 FPGA 片内 BRAM，IMEM ≥ 8KB，DMEM ≥ 8KB，不接 DDR/Flash。
- 必备外设：片上系统计数器（性能打分依据）、8 位七段数码管、CPU 与 IO 互联。
- 平台：Xilinx Artix-7 XC7A200T，Vivado 2023.2，官方 LA32R 交叉编译工具链，AMBA 总线 IP。
- 地址空间须匹配《龙芯架构32位精简版参考手册》。
- 借鉴第三方代码/IP（openLA500）必须在报告中书面标注来源。

关键既有事实（已查证 openLA500 源码）：

- 复位 PC = `0x1c00_0000`（`if_stage.v:342` 的 trick：`fs_pc <= 32'h1bfffffc`）。
- 复位即直接映射模式：`CRMD.DA=1, PG=0`（`csr.v:323-324`），翻译天然恒等映射。
- DA 模式下可缓存性是**全局**的：`inst_uncache_en = da_mode && (csr_datf==0)`（`if_stage.v:321`），数据侧看 `DATM`；`disable_cache` 亦为全局 CSR 位。无按地址区分的原生机制。
- 核对外为 AXI3 主接口（`mycpu_top.v` 顶层模块名 `core_top`）。
- `mycpu.h` 中 `SIMU`（行为级 SRAM vs Xilinx IP）与 `HAS_LACC`（自定义协处理器）两个宏默认关闭。

---

## 2. 目录与复制策略

不修改原始 `open-la500-master/`（保留作参考与报告引用来源）。新建工作区：

```
soc/
  rtl/
    core/      复制 open-la500-master/*.v + *.h，在副本上改造
    soc/       新写：soc_top.v、axi_xbar.v(地址译码)、axi_bram.v
    periph/    新写：counter.v(周期计数器)、seg7.v(8位数码管)
  sim/         新写：tb_soc.v 测试平台
  sw/          demo.S(可读汇编注释) + demo.mem(手工汇编机器码) + gen_mem.py(辅助生成)
```

- 综合顶层：`soc_top`
- 仿真顶层：`tb_soc`

---

## 3. CPU 核改造（最小侵入）

复位即 DA 模式，翻译逻辑基本不动。仅做：

1. **TLB 特权指令中性化**：在 `id_stage.v` 把 `TLBSRCH/TLBRD/TLBWR/TLBFILL/INVTLB` 译码为保留指令（触发 INE 例外）或当 nop 处理，满足"禁止实现 MMU 特权指令"。`tlb_entry.v`/`addr_trans.v` 模块保留但在 DA 模式下永不被查询。报告中注明"运行于直接映射模式，未启用 MMU"。
2. **软件约定不开分页**：demo 程序永不写 `CRMD.PG=1`，保持恒等映射。
3. **SRAM 模型切换**：`mycpu.h` 中 `SIMU` 仿真时打开（icache/dcache 内置行为级 SRAM），综合时关闭（用 `IP/data_bank_sram.xcix`、`IP/tagv_sram.xcix`）。`HAS_LACC` 保持关闭。

不做（明确排除）：不物理删除 TLB 模块、不重写 CSR、不改流水线时序。

---

## 4. 可缓存性策略

DA 模式下缓存为全局开关，分两步走：

- **第一步（本 demo 采用）方案①：全程非缓存。** 沿用复位默认 `DATF=DATM=0`，所有取指/访存绕过 Cache，以单拍 AXI 事务直达 BRAM/外设。外设天然正确、链路最简、最快跑通功能。代价是无 Cache 加速，性能不是本 demo 目标（功能分优先）。
- **第二步（文档化的后续升级）方案②：按地址区分缓存。** 在 `if_stage.v`/`mem_stage.v` 的 `uncache_en` 公式中增加按地址判断——RAM 区(`0x1c00_xxxx`)走缓存、MMIO 区强制非缓存；软件设 `DATF=DATM=1`。届时 RAM 享 Cache 加速、外设仍正确。`axi_bram.v` 在第一步即按支持 Cache 行突发读写设计，为方案②预留，无需返工。

---

## 5. SoC 总线与地址映射（纯 RTL 自写）

数据通路：`core_top`(AXI3 主) → `axi_xbar`(地址译码) → 各从设备。

| 地址区间 | 大小 | 设备 | 属性 |
|---|---|---|---|
| `0x1c00_0000 ~ 0x1c00_7fff` | 32KB | 主存 BRAM（指令+数据共用，满足 IMEM/DMEM 各 ≥8KB） | 复位取指起点 |
| `0x1fb0_0000` | 字 | 8 位数码管数据寄存器（写） | MMIO，非缓存 |
| `0x1fb0_0010` | 字 | 周期计数器（读低 32 位） | MMIO，非缓存 |

- 核为冯·诺依曼单 AXI 口（icache、dcache 共用一个 axi_bridge 主口），故主存为统一物理 BRAM，指令区与数据区由软件在 32KB 内划分。
- `axi_bram.v`：支持 Cache 行突发（INCR/WRAP）读写 + 单拍非缓存访问，支持 `$readmemh` 用 `demo.mem` 初始化。
- `axi_xbar.v`：按地址高位将事务路由到 BRAM 或 MMIO；MMIO 侧将 AXI 读写转为简单寄存器读写时序。
- 地址布局遵循 LA32R 参考手册常用的 `0x1c00_0000` 启动区约定（openLA500 复位 PC 即此）。

---

## 6. 外设

- **`counter.v`**：自由运行 32 位周期计数器，复位清零、每拍 +1，内存映射只读。对应比赛"片上系统计数器"——测试程序起止各读一次相减得运行周期数。
- **`seg7.v`**：内存映射 32 位寄存器，映射到 8 个十六进制数码管段码。仿真中观察该寄存器即可验证输出；上板时其输出再接真实七段译码/扫描逻辑（本 demo 不含板级扫描）。

---

## 7. 演示程序与验证

手工汇编一段 LA32R 指令（不依赖工具链，直接生成机器码 `demo.mem`）：

1. 读周期计数器，保存为 `start`；
2. 一个累加循环（制造若干周期），得到结果值；
3. 把累加结果写入数码管寄存器；
4. 再读周期计数器，计算 `end - start`，写入数码管寄存器或内存某地址；
5. 进入死循环结束。

`tb_soc.v`：实例化整个 `soc_top`，提供时钟/复位，运行至程序结束后 `$display` 打印数码管寄存器值与周期数，并 dump 波形（`.vcd`/`.wlf`）。

验证手段：iverilog 或 Vivado xsim 仿真；判定标准为数码管寄存器出现预期累加结果、周期计数器读数随程序推进单调增长且首尾差值合理。

---

## 8. 范围边界（YAGNI）

本 demo **不包含**：操作系统/特权切换、TLB/MMU 实际使用、浮点、Cache 性能优化（方案②）、板级数码管扫描与管脚约束、Vivado 工程文件、官方工具链编译流程、官方 AMBA/数码管 IP 替换。以上均为后续阶段工作，本 demo 仅打通最小功能链路。

---

## 9. 验收标准

- [ ] `soc/rtl/core/` 为 openLA500 改造副本，TLB 特权指令已中性化，DA 模式恒等映射。
- [ ] `soc_top` 在打开 `SIMU` 下可通过仿真综合（elaboration）。
- [ ] `tb_soc` 跑完手写 demo 程序，数码管寄存器出现预期累加结果。
- [ ] 周期计数器可被程序读取，首尾差值反映运行周期。
- [ ] 地址映射与复位 PC（`0x1c00_0000`）一致，主存 ≥32KB（覆盖 IMEM/DMEM 各 ≥8KB）。
- [ ] 原始 `open-la500-master/` 未被修改。
