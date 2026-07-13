# 性能记录 — 60MHz DSP48E1 交付配置

> **日期：** 2026-07-14  
> **Git commit：** `672a7d1` (mul v3), `05a684a` (design report)  
> **位流备份：** `bitstreams/soc_top_60m_v3dsp_20260714_0127.bit`（9.73 MB）  
> **流程：** Chiplab 发布包默认 `create_project.tcl`（规则 4.3.4 合规）

---

## 1. 频率与平台

| 参数 | 值 |
|------|-----|
| FPGA | Xilinx Artix-7 XC7A200T-FBG676-2 |
| Vivado | 2023.2 |
| 输入时钟 (clk) | 100 MHz |
| PLL VCO | 1,800 MHz（MMCM CLKFBOUT_MULT=18） |
| cpu_clk (CLKOUT0) | **60.00 MHz**（CLKOUT0_DIVIDE_F=30） |
| sys_clk (CLKOUT1) | 100 MHz（CLKOUT1_DIVIDE=18） |
| ddr_clk | 由 clk_pll_ddr 独立生成 |

---

## 2. 布线后时序

| 时钟域 | WNS | TNS | 失败端点 | WHS | THS |
|--------|-----|-----|----------|-----|-----|
| **cpu_clk** (60 MHz) | **+0.052 ns** | 0.000 ns | **0** | OK | 0 |
| sys_clk (100 MHz) | +2.620 ns | 0.000 ns | 0 | OK | 0 |
| ddr_clk | +2.107 ns | 0.000 ns | 0 | OK | 0 |
| clk (100 MHz) | +8.161 ns | 0.000 ns | 0 | OK | 0 |

**结论：全部时钟域 WNS≥0，0 个失败端点。时序满足交付要求。**

> 注：62.07 MHz（CLKOUT0_DIVIDE=29）时 cpu_clk WNS=-0.231ns（13 失败端点），不可交付。60 MHz 是当前 RTL 在默认流程下可收敛的最高频率。

---

## 3. 资源占用（soc_top，含 CPU + DDR3 + 外设）

| 资源 | 已用 | 可用 | 利用率 |
|------|------|------|--------|
| Slice LUTs | 17,253 | 133,800 | 12.89% |
| Slice Registers | 17,983 | 269,200 | 6.68% |
| Block RAM Tile | 12.5 | 365 | 3.42% |
| **DSP48E1** | **10** | 740 | 1.35% |
| Bonded IOB | 103 | 400 | 25.75% |
| BUFGCTRL | 8 | 32 | 25.00% |
| PLLE2_ADV | 3 | 10 | 30.00% |

> DSP 使用 10 个 slice：~4 用于 `mul.v` 的 32×32→64 乘法器（DSP48E1 级联推断），其余为 chiplab SoC 外设（crossbar、MIG 等）使用。

---

## 4. CPU 微架构

| 特性 | 参数 |
|------|------|
| 流水线 | 单发射 5 级静态（IF→ID→EXE→MEM→WB） |
| 指令集 | LA32R 基准整数子集（无浮点、无 TLB/MMU 特权指令） |
| I-Cache | 2 路组相联，256 组×16B = 8KB，128-bit 填充 |
| D-Cache | 2 路组相联，256 组×16B = 8KB，写直达+dirty，128-bit 填充 |
| 分支预测 | 64 条目 BTB + 8 条目 RAS |
| 乘法器 | **DSP48E1 推断**（4×DSP48E1 级联，1-cycle 延迟） |
| 除法器 | 迭代恢复除法（~34 周期） |
| 主存 | DDR3（经 MIG + AXI crossbar），延迟 ~10-20+ cycle |
| TLB/MMU | 存在但未使用（DA 直通模式，CSR_CRMD_DA=1） |

---

## 5. 功能验证

| 测试 | 平台 | 结果 |
|------|------|------|
| `nscscc_func` (func.mem) | Verilator 5.x (2-state) | ✅ PASS `num_data=0x3a00003a` |
| 基准 (Booth+Wallace mul) | Verilator | ✅ PASS `num_data=0x3a00003a` |
| DSP48E1 mul 输出匹配 | 逐位比对 | ✅ 与基准完全一致 |

> **阻塞**：LA32R 交叉编译工具链 (`loongarch32r-linux-gnusf-*`) 未安装，无法运行 `make run-func` / `make run-perf` 进行 20 个性能测试的完整回归。当前仅通过预编译 `sw/func.mem` 做冒烟验证。

---

## 6. 频率探索历程

| 频率 | CLKOUT0_DIVIDE | WNS | DSP mul 版本 | 备注 |
|------|------------|-----|-------------|------|
| 32.73 MHz | 55 | +8.593 ns | 原始 Booth+Wallace | chiplab 原始默认 |
| 62.07 MHz | 29 | -0.231 ns | v3（输入寄存器） | ❌ 13 端点失败 |
| 62.07 MHz | 29 | ~-1 ns | v4（输出寄存器 PREG） | ❌ 比 v3 更差 |
| **60.00 MHz** | **30** | **+0.052 ns** | **v3（输入寄存器）** | ✅ **交付** |

**v3 vs v4 结论**：输出寄存器（PREG）让 4 个 DSP48E1 的级联乘法完全组合化，EXE→DSP 布线 + 级联延迟超过 1 周期预算。输入寄存器（AREG/BREG 吸收）将组合路径截断在寄存器后，仅剩 DSP Tcko→fabric 的 ~2-3 ns 路径——比 v4 快 ~3 倍。

---

## 7. 下一优化方向（提频杠杆）

按预计收益排序：

| 优先级 | 方向 | 预计解锁 | 说明 |
|--------|------|----------|------|
| 1 | **缓存预取** (next-line prefetch) | +2-5% IPC | DDR3 延迟 ~10-20 cycle，L1 命中率是关键杠杆 |
| 2 | **流水线 mul_result** | 62+ MHz | 在 `mul` 后加输出寄存器→`mem_stage` 加 1 拍→回收 DSP→MEM 的 -0.231ns |
| 3 | **TLB 剥离** | ~0.05-0.10 ns | 删除 32 条目 CAM → 减少布局拥塞 → margin 用于提频 |
| 4 | **BTB→icache 流水线化** | ~0.10 ns | BTB nextpc→icache 地址组合环路 |
| 5 | **安装 LA32R 工具链** | 解锁回归 | 运行 20 个 perf 测试，建立 CPI 基准 |

---

## 8. 位流信息

| 文件 | 大小 | 路径 |
|------|------|------|
| soc_top_60m_v3dsp_20260714_0127.bit | 9,730,756 bytes | `bitstreams/` |
| soc_top_routed.dcp | — | `chiplab/fpga/.../impl_1/` |

位流生成参数：
- 综合策略：`Flow_PerfOptimized_high`
- 实现策略：`Performance_Explore`
- 约束文件：`soc_lite.xdc`（未修改）
- 综合/实现参数：默认（未修改）

---

## 9. Git 历史（本配置相关）

```
672a7d1 perf(core): DSP mul v3 (input regs) for 60MHz delivery; PLL CLKOUT0_DIVIDE 29->30
05a684a docs(report): final delivery timing — 60MHz WNS=+0.052ns, DSP48E1 optimized, chiplab flow verified
9205d10 fix(core): DSP mul output register breaks CLK→fabric critical path; func PASS 0x3a00003a
5da98e1 feat(core): DSP48E1 multiplier replaces LUT Wallace tree; fix axi_bridge rready reg/wire conflict; update design report §8 for delivery flow
```
