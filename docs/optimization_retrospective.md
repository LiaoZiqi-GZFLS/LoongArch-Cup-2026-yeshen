# 频率优化探索总结 & 破局方向

> **当前交付：62.07MHz (1800/29), WNS=+0.005ns, func PASS `0x3a00003a`**
>
> **原始频率：32.73MHz，提升 90%**

---

## 一、已探索方向

### 1.1 已验证有效的优化（6 项 RTL + 1 项工具）

| # | 优化 | 文件 | 原理 | 效果 |
|---|------|------|------|------|
| 1 | **DSP48E1 乘法器** | `mul.v` | Booth+Wallace LUT → DSP48E1 硬核推断（4 slices） | 消除 16.3ns Wallace 树路径 |
| 2 | **Mul 输出寄存器 + 2-cycle EXE** | `mycpu_top.v`, `exe_stage.v` | `mul_result_r` 截断 DSP→mem_stage 长路径 | 解锁 62MHz（WNS -0.231→+0.005） |
| 3 | **ALU 前递寄存器 + 2-cycle EXE** | `exe_stage.v` | `exe_result_r` 截断 ALU→前递→ID 路径 | 消除第二关键路径 |
| 4 | **CSR 静态数据寄存器** | `if_stage.v` | `csr_eentry_r`, `csr_era_r` 截断 WB→IF 32-bit 数据路径 | 突破 75MHz 瓶颈一步 |
| 5 | **Dcache 输出寄存器** | `mycpu_top.v` | `data_rdata_r`, `data_data_ok_r` 截断 BRAM→WB excp 路径 | 突破 81.8MHz 瓶颈一步 |
| 6 | **BTB 轮转替换** | `btb.v` | LFSR 随机 → 轮转指针替代 | 微提升分支预测精度 |
| 7 | **TLB CAM 剥离** | `addr_trans.v` | 删除 32 条目 CAM 实例 | 减少 LUT/布线拥塞 |

### 1.2 已尝试但回退的优化

| # | 优化 | 原因 | 教训 |
|---|------|------|------|
| A | **WB→IF 控制信号打拍** | `excp_flush` 延迟 1 拍 → 精确异常破坏（func `0x2e00002e`） | 异常重定向必须同周期——不可打拍 |
| B | **ws_pc+4 前移到 WB** | 瓶颈是 32-bit 布线延迟（~3-5ns），非加法器（~1ns） | 搬家不解决问题——宽总线跨芯片布线是物理瓶颈 |
| C | **Pblock 物理约束** | CPU 仅占 XC7A200T 的 13%，默认布局已紧凑，约束反增局部拥塞（WNS -0.480 vs -0.225） | 小设计加约束反效果 |
| D | **Retiming 属性** | Vivado 报 "NOT ENOUGH REGISTERS"——无多余寄存器可移动 | 每条路径都已有精确位置的管线寄存器 |
| E | **Dcache 预取** | 复用 dcache 状态机 → 阻塞 CPU → 性能下降（func PASS 但 bitcount 500M 超时） | 预取需独立状态机，不能复用主 FSM |
| F | **BTB 操作寄存器** | 新增 13 个寄存器增加拥塞，WNS 从 -0.225 恶化到 -1.318 | 寄存器本身消耗资源，非关键路径打拍反效果 |
| G | **Option B (ID→EXE 分支)** | 触及 5 文件，中间态 func 必失败，风险/收益不匹配 | 需更多开发时间，当前 deadline 不允 |
| H | **PLL 分数分频 (29.5)** | PLL 不支持分数 `CLKOUT0_DIVIDE_F` | 62.07MHz 和 60MHz 之间无可用的中间频率 |

---

## 二、频率瓶颈演化图

```
频率       最差路径                                    瓶颈本质
32.73MHz   DSP Wallace 树 (LUT)                       纯 LUT 组合延迟
60MHz      DSP→mem_stage (16.3ns)                     DSP 输出 + 32b 布线
62MHz      ALU→forwarding→ID (16.1ns)                 前递组合路径跨级
70+MHz     WB→IF excp_flush (14.6ns)                  1-bit 控制 + 32b 数据跨级
75MHz      WB→IF fs_excp_num (13.3ns)                半周期路径 (negedge→posedge)
81.8MHz    WB→IF→BTB ras_pc (13.9ns→12.2+1.7=13.9)   跨WB/IF/BTB三模块
```

**核心规律**：每次打拍消灭一条关键路径，下一条更短的跨级组合路径暴露。所有瓶颈最终汇聚到 **WB→IF→BTB** 的 32-bit 总线 + 1-bit 控制 + 半周期时序路径。这条路径不可打拍（精确异常需求）。

---

## 三、已探索方向分类

| 类别 | 已尝试 | 有效 | 无效 |
|------|--------|------|------|
| **RTL 管线打拍** | 7 项 | 4 项 (DSP, ALU, CSR, Dcache) | 3 项 (WB→IF ctrl, BTB, ws_pc+4) |
| **逻辑优化** | 2 项 | 1 项 (DSP48E1) | 1 项 (BTB 操作寄存) |
| **架构变更** | 2 项 | 0 | 2 项 (Option B, 预取) |
| **物理约束** | 2 项 | 0 | 2 项 (Pblock, ws_pc 移位) |
| **工具优化** | 1 项 | 0 | 1 项 (Retiming 属性) |
| **PLL 调谐** | 1 项 | 0 | 1 项 (分数分频) |
| **总计** | **15 项** | **5 项** | **10 项** |

---

## 四、尚未探索的方向

### 4.1 架构级（大改动，中高风险）

| 方向 | 预期效果 | 原理 |
|------|----------|------|
| **Option B: ID→EXE 分支解析** | 打破 ID→IF br_bus 同周期路径 | 分支在 EXE 用已前递操作数解析，预测信息经 `ds_to_es_bus` 传到 EXE。需改 5 文件。Worktree 分支曾实现（commit 65ad3d5 附近），func 通过 |
| **精确异常预判 (Early Exception)** | 打破 WB→IF excp_flush 路径 | 在 MEM 阶段预判异常，提前 1 周期发"快速 flush"到 IF。若 MEM 误判（false positive），IF 已开始取 handler——丢弃重新取。类似分支预测的 speculative execution |
| **独立预取状态机** | 打破 dcache 阻塞问题 | 当前预取复用 dcache 主状态机 → CPU 阻塞。独立状态机 + prefetch buffer → 不阻塞 CPU。代价：更多 BRAM/逻辑 |
| **L1 缓存扩容** | +1-3% IPC | 8KB→16KB，减少 DDR3 访问。BRAM 空闲 96.6%——大量资源可用 |
| **双发射 (Dual-Issue)** | IPC 1.0→1.5 | Worktree 分支曾实现 M1-M6。19/20 perf 绿。风险：时序需重新关闭 |

### 4.2 微架构级（小改动，低风险）

| 方向 | 预期效果 | 原理 |
|------|----------|------|
| **nextpc MUX 层级优化** | ~0.2ns | 当前 5 选 1 扁平 MUX。改为 3 层 2 选 1 树 → 减少逻辑级数 |
| **BTB 64 条目** | +1-2% 分支预测 | 当前 32 条目。Worktree 曾做到 64（c5c25c9）。需改 btb_index 位宽（5→6 bit），触 3 文件 |
| **寄存器堆写端口流水线化** | ~0.1ns | 写操作 1 拍 → 2 拍。增加 1 cycle 写回延迟。CPI +~0.05 |
| **load-use stall 优化** | ~0.05ns | 当前 `dep_need_stall = es_load_op`——所有 load 都 stall。若 dcache 命中，数据在 lookup 周期已可用 → 可跳过 stall |
| **icache addr 缓冲** | ~0.3ns | 在 icache 地址输入加寄存器 → 1 cycle fetch 延迟。但 BTB 预测仍提前 1 cycle 算地址 |

### 4.3 流程/工具级

| 方向 | 预期效果 | 原理 |
|------|----------|------|
| **Vivado `-retiming` 全局开启** | 可能 ~0.05-0.10ns | 综合时 `-retiming` 自动重平衡寄存器。但可能违反 4.3.4（修改综合参数） |
| **`phys_opt_design -directive Explore`** | ~0.1ns | 更强的物理优化。但默认已用 `Performance_Explore` |
| **增量编译 + 布线指导** | ~0.1ns | 保存好的布线结果，指导下次迭代。需多次 Vivado 运行 |
| **更换 FPGA 型号** | +30-50% 频率 | XC7A200T-2 是 -2 速度等级。若有 -3 等级可提升 ~15% |
| **Vivado 版本更新** | 未知 | Vivado 2023.2→2024.x 路由器有改进 |

### 4.4 软件/方法论

| 方向 | 预期效果 | 原理 |
|------|----------|------|
| **编译优化** | -2-5% cycles | 编译器调度独立指令到 load 后，减少 stall。使用 O2/Os 优化 |
| **关键循环展开** | -1-3% cycles | 手动展开 benchmark 中的热循环，减少分支 |
| **重写关键 benchmark** | 视情况 | 针对 sha/crc32 等计算密集 benchmark，手工优化汇编 |

---

## 五、破局分析

### 5.1 为什么 62→75MHz 差最后 0.23ns？

62MHz 下全部 7 个优化就位，WNS=+0.005ns。
75MHz 下初始路由 WNS=+0.260ns（证明硬件可关闭），但**路由器后续迭代确定性地恶化**到 -0.225ns。

```
Vivado "Performance_Explore" 布线流程:
  Pass 1: WNS=+0.260 ✅ ← 好布局
  Pass 2: WNS=-0.530   ← 尝试减少 TNS，破坏了好路径
  Pass 3: WNS=-0.427
  ...
  Final:  WNS=-0.225   ← 最终结果比 Pass 1 差 0.485ns
```

**根因**：`Performance_Explore` 策略用多轮迭代平衡 TNS 和 WNS。初始 pass 找到好解，但后续 pass 为了减少全局 TNS 而移动了关键路径上的逻辑。

**破局路径**：
1. 若能在 Pass 1 时"冻结"关键路径（不随后续迭代移动），75MHz 可关闭
2. 需要 `set_max_delay` 或 `-datapath_only` 约束关键路径 —— 但违反 4.3.4
3. 或使用 RTL 级 `(* DONT_TOUCH *)` 保护关键寄存器不被路由器移动

### 5.2 为什么打拍有效但有限？

每个打拍寄存器：✅ 物理上截断组合路径 → 该路径不再关键
❌ 自身消耗 LUT/FF + 布线资源 → 增加总拥塞
❌ 需要 stall 逻辑适配 → 增加控制路径延迟

当寄存器加在**真正关键路径**上（DSP, ALU, CSR, Dcache）：路径缩短收益 ≫ 拥塞代价
当寄存器加在**非关键路径**上（BTB 操作）：拥塞代价 ≫ 无收益

### 5.3 最可能的破局方向（按优先级）

| 优先级 | 方向 | 理由 |
|--------|------|------|
| **P0** | **精确异常预判 (Early Exception in MEM)** | 直接攻击最后的瓶颈——WB→IF 同周期需求。在 MEM 预判异常，提前发 flush。不需要改异常语义 |
| **P1** | **nextpc MUX 层级优化** | 简单、低风险、纯组合逻辑优化。5→3 层可能回收 0.2ns |
| **P2** | **Option B: ID→EXE 分支解析** | 已在 worktree 实现过。需 3-5 天稳定开发。打破 ID→IF br_bus 路径 |
| **P3** | **独立预取状态机** | 当前预取失败直接原因。降 CPI 方向。不帮频率 |
| **P4** | **双发射** | 终极性能方案。已在 worktree 实现 19/20 perf。但完全打破当前时序假设 |

### 5.4 评分模型下的最优策略

```
Score ∝ frequency / cycles

当前:  62 MHz / 1.0 CPI = 62.0 (归一化)
P0+P1+P2: 75 MHz / 1.0 CPI = 75.0 (+21%)  ← 纯频率优化
P3:       62 MHz / 0.95 CPI = 65.3 (+5%)   ← 纯 IPC 优化
P4:       50 MHz / 0.67 CPI = 74.6 (+20%)  ← 降频+双发射

最佳组合: P0+P1+P2+P3 = 75 MHz / 0.95 CPI = 78.9 (+27%)
```

---

## 六、项目当前状态

### 已验证的 RTL 改动（可交付）

| Commit | 改动 |
|--------|------|
| `5da98e1` | DSP48E1 乘法器 + axi_bridge 修复 |
| `672a7d1` | Mul 2-cycle EXE + 输出寄存器 @60MHz |
| `d8d0744` | Mul 输出寄存器 + 2-cycle EXE |
| `fae58b0` | TLB CAM 剥离 |
| `868b41f` | BTB 轮转替换 |
| `3fbd641` | ALU 前递寄存器 + 2-cycle EXE |
| `8c9409b` | Dcache 输出寄存器 |
| `ace2a7c` | CSR 数据寄存器 (if_stage) |
| `6eca7ff` | Retiming 属性（辅助性） |

### 位流

```
bitstreams/soc_top_62m_mulreg_20260714_1250.bit (9.28 MB)
    62.07 MHz, WNS=+0.005ns, func PASS 0x3a00003a
```

### 阻塞项

- LA32R 交叉工具链仅能在 WSL 中运行（Linux ELF）
- Perf 20 测试的完整回归未在 62MHz 配置上重跑（Verilator 慢，需 ~2-3h 后台 batch）
- Chiplab 项目多次 Vivado 运行后易损坏（IP 生成非确定性失败）
