# SatelliateMonitor — 卫星终端认知与干扰防御平台

> **Cognitive Satellite Spectrum Awareness Platform**
> 一个面向 **Starlink / OneWeb 双星座** 的「宽带频谱认知 + 信号体制识别 + 干扰防御」一体化 MATLAB 桌面应用。
> 入口脚本：[`tools/runTwinPlatform.m`](tools/runTwinPlatform.m) — 整套 GUI、3 个测试会话、6000-cell 验收测试都从这里启动。

---

## 目录

- [1. 平台定位 & 整体能力](#1-平台定位--整体能力)
- [2. 架构总览](#2-架构总览)
- [3. 三个会话的功能与流程](#3-三个会话的功能与流程)
  - [3.1 会话 1：多种信号体制识别 (demo)](#31-会话-1多种信号体制识别-demo)
  - [3.2 会话 2：典型终端信号识别 (验收测试, 6000 cells)](#32-会话-2典型终端信号识别-验收测试-6000-cells)
  - [3.3 会话 3：干扰防御 (demo)](#33-会话-3干扰防御-demo)
- [4. 代码目录详解](#4-代码目录详解)
- [5. 关键数据流 & 物理建模链路](#5-关键数据流--物理建模链路)
- [6. 运行环境](#6-运行环境)
- [7. 外部依赖 (TLE 数据 & YOLOX 检测模型)](#7-外部依赖-tle-数据--yolox-检测模型)
- [8. 安装 & 启动](#8-安装--启动)
- [9. 输出产物](#9-输出产物)
- [10. 二次开发指引](#10-二次开发指引)
- [11. 常见问题 (FAQ)](#11-常见问题-faq)
- [12. 许可证](#12-许可证)

---

## 1. 平台定位 & 整体能力

**SatelliateMonitor** 把「LEO 卫星轨道仿真 + 上行 OFDM 波形生成 + 端到端 RF 信道 + STFT 可视化 + YOLOX 目标检测 + 干扰策略评估」缝合成一个 **可单击运行的 MATLAB 桌面应用**：

| 能力 | 实现位置 | 说明 |
| --- | --- | --- |
| 真实星历驱动的 3D 卫星场景 | `satelliteScenario` + `satelliteScenarioViewer` (内嵌于 GUI) | TLE 来自 `data/TLE/` |
| Starlink / OneWeb 上行 OFDM 波形 | `cssa/com/+starlink`, `cssa/com/+oneweb`, `cssa/spectrum/+dataGen/+link/transmit.m` | OFDM + 同步序列 + MCS, 物理参数对齐 FCC/ETSI 公开文献 |
| 端到端 RF 信道 (FSPL/大气/雨衰/电离层/旁瓣/p681 LMS/多普勒/相位噪声/AWGN) | `cssa/com/simulation/channelModel.m` | 单函数, 全部 ITU-R 推荐书参考点直写 |
| 600 MHz 宽带伴飞接收机 (重采样 + 信道搬移 + LPF + DC 泄漏) | `cssa/spectrum/+dataGen/+signal/wideband.m` + `Session2TestFlowPanel::applyReceiverImpairments` | 输出 1.8e6 IQ |
| 640×640 STFT 时频图 | `cssa/spectrum/+dataGen/+io/spectrogram.m` | 给 YOLOX 直接吃 |
| YOLOX 目标检测 (Starlink / OneWeb 区分) | 外部 `detector.mat` (放在 `results/unified/detection/`, 不进 git) | GUI 自动找最新 detector |
| **6000 cell 验收测试矩阵 (会话 2)** | `cssa/+twin/+app/Session2TestFlowPanel.m` | 30 sat × 10 SNR × 10 Doppler × 2 星座, 含 95% Wilson CI |
| 4 种干扰策略 (white / STAD / STSD / STPD) | `cssa/spectrum/+jamming/+strategy/` | 含同步触发数据段干扰对照实验 |
| 自动导出 CSV / MAT / PNG / JSON 报告 | `Session2TestFlowPanel::exportReport` | 落到 `results/session2/<runTag>/` |

---

## 2. 架构总览

整个 GUI 基于 MATLAB 内部的 `matlabshared.application` 框架（与官方 `linkbudgetApp` 同源），实现 **多面板可停靠 + 可缩放 + 内嵌 3D 场景** 的体验：

```
            ┌────────────────────────────── 工具条 (Toolstrip) ──────────────────────────────┐
            │  [新建会话 ▼]      [返回选择]                                                  │
            └──────────────────────────────────────────────────────────────────────────────┘
            ┌─────────── TestFlow ───────────┐ ┌────── ViewerPanel (3D 场景) ──────┐
            │  步骤按钮列表 (整行可点击)     │ │ satelliteScenarioViewer 嵌入      │
            │  + 参数区 (滑块/spinner)       │ │ (非独立窗口, 与 GUI 一同缩放)     │
            └────────────────────────────────┘ └────────────────────────────────────┘
            ┌──────────────────────────── ResultPanel (横跨两列) ───────────────────────────┐
            │ 顶部: 元数据 + 累积准确率                                                    │
            │ 底部: 左 准确率-SNR 曲线   |   右 准确率-Doppler 曲线                        │
            └──────────────────────────────────────────────────────────────────────────────┘
       ┌─────────── (会话 2 专属) 弹出窗口: 样本检测明细 (滚动) ───────────┐
       │ 左半: 当前样本大图 + 累积混淆矩阵                                  │
       │ 右半: 最近 60 条样本明细 (原图 + 检测图 + 元数据), 红/绿边框区分错对 │
       └────────────────────────────────────────────────────────────────────┘
```

类层次（文件位于 `cssa/+twin/+app/`）：

```
twin.app.App                    主应用 (matlabshared.application.Application)
├─ SessionVisual                会话选择启动卡 (初始页)
├─ ViewerPanel                  satelliteScenarioViewer 容器
│
├─ TestFlowPanel                会话 1 流程 (6 步)
├─ RecognitionResultPanel       会话 1 结果 (Starlink/OneWeb 双 STFT + 检测)
│
├─ Session2TestFlowPanel        会话 2 流程 (7 步) + 内嵌 Plan/Generator/Evaluator/Reporter 静态方法
├─ Session2ResultPanel          会话 2 结果 (元数据 + 双曲线 + 弹出滚动窗口)
│
├─ Session3TestFlowPanel        会话 3 流程 (7 步)
└─ Session3ResultPanel          会话 3 结果 (双星座干扰评估)

twin.app.TestFrameEventData     通用事件载荷 (Payload struct), 三个会话都用
```

事件总线（`addlistener` 注册在 `App.connectSession{1,2,3}Events`）：

| 事件名 | 触发者 | 监听者 | 携带数据 |
| --- | --- | --- | --- |
| `SignalImageReady` | 会话 1 step3/4 | `RecognitionResultPanel` | 当前 STFT 图像 |
| `TestCellReady` | 会话 2 batch tick | `Session2ResultPanel.onCellReady` | `Payload = {CellInfo, Sample, Detection, Snapshot, Processed, TotalCells}` |
| `TestExportReady` | 会话 2 step7 | `App.onSession2ExportReady` | (无) |
| `SignalDisplayReady` / `JammingResultReady` | 会话 3 各 step | `Session3ResultPanel` | `Payload = {Constellation, SignalType, IQData}` 或 `{Constellation, Results}` |

---

## 3. 三个会话的功能与流程

### 3.1 会话 1：多种信号体制识别 (demo)

精简到 **6 步**，每步在按钮上同时显示「编号 + 步骤名」「输入 / 输出」两行：

| # | 步骤 | 输入 → 输出 |
| - | --- | --- |
| 1 | 创建场景 + 加载 Starlink/OneWeb 卫星 | TLE → `scenario` + 2 `satellite` |
| 2 | 部署终端 + 伴飞卫星 (共享一个偏移滑块) | 主卫星 + 偏移 km → 2 `groundStation` + 2 companion `satellite` |
| 3 | 生成并显示 Starlink 监测信号 | Starlink 链路 + simTime → 1.8e6 IQ + 640×640 STFT |
| 4 | 生成并显示 OneWeb 监测信号 | 同上 |
| 5 | 加载 YOLOX 检测模型 + 完成推理 | `detector.mat` + 两幅 STFT → bbox/labels/scores |
| 6 | 输出感知结果 | 检测结果 + 原 STFT → 渲染至 `Session1Result` 面板 |

定位：**对外演示**，证明端到端链路通；**不输出报告文件**。

### 3.2 会话 2：典型终端信号识别 (验收测试, 6000 cells)

精简到 **7 步**，全部参数集中在顶部参数区 (NumSat / NumSNR / NumDop / SNRmin / SNRmax / fdSL/kHz / fdOW/kHz / 偏移 / 检测器路径)：

| # | 步骤 | 输入 → 输出 |
| - | --- | --- |
| 1 | 创建仿真场景 | 起止时间, SampleTime → `satelliteScenario` |
| 2 | 加载 30+30 颗卫星 | TLE/starlink + TLE/oneweb → 30+30 `satellite` |
| 3 | 部署终端 + 伴飞卫星 | 主卫星 + 偏移 → 30+30 `groundStation` + 30+30 companion |
| 4 | 配置测试矩阵 | NumSat × NumSNR × NumDop → 6000 `cell` (含 SNR/Doppler/信道号) |
| 5 | 加载 YOLOX 检测模型 | `detector.mat` 路径 → detector 对象 |
| 6 | 批量生成 + 检测 + 实时统计 | 6000 cells × (1.8e6 IQ → 640×640 STFT) → 实时精度 + 混淆矩阵 |
| 7 | 汇总并导出测试报告 | Evaluator metrics → `results/session2/<runTag>/{csv,mat,png,json}` |

**测试矩阵** (默认值, 可在 GUI 改)：

| 维度 | 默认值 | 说明 |
| --- | --- | --- |
| 每星座卫星数 NumSat | 30 | 卫星从 `data/TLE/<constellation>/` 随机抽 |
| SNR 网格 | 10 点, `linspace(-10, 10, 10)` dB | 显示 X 轴标签 = 设定 SNR |
| Doppler 网格 | 10 点, Starlink ±360 kHz / OneWeb ±345 kHz | LEO 上行典型范围 |
| 信道号 | Starlink 8 / OneWeb 10, 每 cell 随机抽 | 对应 60 MHz / 20 MHz 模式 |
| 总样本数 | **30 × 10 × 10 × 2 = 6000** | 与技术报告对齐 |

**SNR 注入口径** (重要, 文档/审计要明白)：

1. 关闭 `channelModel` 内部噪声 (`injectThermalNoise = false`), 强制 `dopplerShift = doppler_Hz`
2. 1.8e6 IQ 完成宽带搬移 + 重采样后, 在 `timeMask` 标记的 burst 区算干净信号功率 `Ps_clean`
3. 按设定 SNR 反算 AWGN 标准差 `σ = sqrt(Ps_clean / 10^(SNR_eff/10) / 2)`, 加到全长 IQ
4. **挑战噪声**: 类属性 `ChallengeExtraNoise_dB` (默认 6 dB) 让分类器实际看到的 SNR 比 X 轴显示低 6 dB, 避免任意 SNR 都 100%
5. 加完噪声 → LPF (0.85×Nyquist FIR) + DC 泄漏 + 全局归一化 → STFT
6. **最终在归一化后的 IQ 上, 分别测 burst 区和非 burst 区功率, 反算「分类器真正看到的 SNR」**, 写入 `meta.snr_meas_burst_dB`

**「正确」的判定** (严格口径, 由 `aggregateDetection` 给出)：

| 检测结果 | 判定 | 计入混淆矩阵 |
| --- | --- | --- |
| 恰好 1 个 GT 类框 + 0 个其他类框 | ✅ correct | 对角格子 |
| 任意一个其他类框 | ✗ 错类 | 列 1 或 2 (错类) |
| 同类 ≥ 2 框 | ✗ 多检 / 虚警 | 第 3 列「漏检/多检」|
| 0 框 | ✗ 漏检 | 第 3 列「漏检/多检」|

定位：**报告主战场**，6000 cells 是技术报告里 "broadband signal cognition" 验收性能的支撑数据。

### 3.3 会话 3：干扰防御 (demo)

精简到 **7 步**：

| # | 步骤 | 说明 |
| - | --- | --- |
| 1 | 创建场景 + 加载 Starlink/OneWeb 卫星 | 同会话 1 |
| 2 | 部署终端 + 伴飞卫星 | 同会话 1, 共享偏移 |
| 3 | Starlink 通信链路 + 发射信号 + 显示 | 干净基带 + `burstInfo` |
| 4 | OneWeb 通信链路 + 发射信号 + 显示 | 同上 |
| 5 | 加载干扰策略集合 | `white / STAD / STSD / STPD` 4 种, 见 `cssa/spectrum/+jamming/+strategy/` |
| 6 | 对 Starlink 施加干扰 + 评估 | jammed IQ + BER 曲线 + 干扰链路 |
| 7 | 对 OneWeb 施加干扰 + 评估 | 同上 |

| 策略 | 全称 | 思想 |
| --- | --- | --- |
| `white` | Wide-band White Jamming | 全频段持续随机噪声 (基线对照) |
| `STAD` | Sync-Triggered Adaptive Data-jamming | 同步头检测后, 仅干扰数据段, 能效 +15 dB |
| `STSD` | Sync-Triggered Sync-Distorting jamming | 同步头检测后, 反复畸变同步序列 |
| `STPD` | Sync-Triggered Pilot-Destroying jamming | 同步头检测后, 在导频位置精准干扰 |

定位：**对外演示** 智能干扰策略的相对效能, 不输出报告文件。

---

## 4. 代码目录详解

```
SatelliateMonitor/
├─ tools/
│  └─ runTwinPlatform.m            ★ 唯一入口: addpath + twin.launch()
│
├─ cssa/                           ★ 全部 MATLAB 源码 (会被 addpath(genpath(...)) 加进路径)
│  ├─ +twin/
│  │  ├─ launch.m                  应用启动函数, 包装 try/catch + 控制台横幅
│  │  ├─ +app/                     ★ GUI 类全集中在这
│  │  │  ├─ App.m                  Application 类, 工具条 + 三个会话事件连接
│  │  │  ├─ SessionVisual.m        会话选择启动卡
│  │  │  ├─ ViewerPanel.m          内嵌 satelliteScenarioViewer
│  │  │  ├─ TestFlowPanel.m        会话 1 流程 (6 步)
│  │  │  ├─ RecognitionResultPanel.m  会话 1 结果
│  │  │  ├─ Session2TestFlowPanel.m   会话 2 流程 + Plan/Generator/Evaluator/Reporter (内嵌静态方法)
│  │  │  ├─ Session2ResultPanel.m     会话 2 结果 + 弹出滚动样本窗
│  │  │  ├─ Session3TestFlowPanel.m   会话 3 流程 (7 步)
│  │  │  ├─ Session3ResultPanel.m     会话 3 结果
│  │  │  └─ TestFrameEventData.m   通用事件 Payload 容器
│  │  ├─ +orbit/companion.m        给定主星 + 偏移 km, 求伴飞星 ECEF 位姿
│  │  └─ +signal/{terminal,jammer}.m   终端 LLA 候选搜索 + 干扰发射器
│  │
│  ├─ com/                         通信物理层 (Starlink + OneWeb 上行 + 信道)
│  │  ├─ +starlink/upTx.m, generateCESymbol.m   Starlink OFDM Tx + 同步符号
│  │  ├─ +oneweb/upTx.m,   generateDMRSSequence.m OneWeb Tx + DMRS
│  │  ├─ simulation/channelModel.m  ★ 端到端 RF 信道模型, ITU-R 全套损耗
│  │  ├─ simulation/antenna/{calculateActualTxGain,calculatePolarizationLoss}.m
│  │  └─ simulation/channel/
│  │     ├─ calculateAtmosphericLoss.m   (P.676)
│  │     ├─ calculateRainAttenuation.m   (P.618 / P.838)
│  │     ├─ calculateScintillationLoss.m (P.618)
│  │     ├─ calculateIonosphericLoss.m   (P.531)
│  │     └─ noise/{getPhaseNoiseStd,getSystemNoiseTemperature}.m
│  │
│  ├─ config/                      ★ 物理参数中心 (大量 dB / Hz / dBi 数值)
│  │  ├─ constellationPhyConfig.m            分发到具体星座
│  │  ├─ starlink/getStarlinkPhyParams.m     14.0–14.5 GHz, 60/240 MHz mode, MCS table
│  │  ├─ oneweb/getOneWebPhyParams.m         同上
│  │  └─ spectrumMonitorConfig.m             宽带监测参数 (sampleRate, IQ length, RF fingerprint, …)
│  │
│  ├─ orbit/                       轨道几何工具
│  │  ├─ calculateCompanionPosition.m
│  │  ├─ geometry/{calculateAngles,calculateLinkGeometry}.m
│  │  └─ tle/{loadConstellationTLE,propagateTLE}.m
│  │
│  └─ spectrum/
│     ├─ +dataGen/                 ★ 数据生成原子操作 (会话 2 generator 复用)
│     │  ├─ +burst/{plan,profile,guard,overlap}.m   burst 时序规划
│     │  ├─ +config/{mode,mcs,receiver}.m
│     │  ├─ +signal/{txParams,uplink,wideband,impairments,…}.m
│     │  ├─ +link/{transmit,propagate,receive,channel,label,tx}.m   ★ 三步式链路
│     │  ├─ +io/spectrogram.m      ★ STFT → 640×640 RGB
│     │  └─ +terminal/{create,position,elevation}.m
│     └─ +jamming/+strategy/{white,STAD,STSD,STPD}.m  ★ 4 种干扰策略
│
├─ data/                           ★ 不入库! 见 data/README.md
│  └─ TLE/{starlink,oneweb}/*.tle  单星一文件
│
├─ results/                        ★ 大部分不入库
│  ├─ unified/detection/<run>/detector.mat  ★ 必备的 YOLOX 模型, 见 results/unified/detection/README.md
│  └─ session2/<runTag>/           会话 2 自动产物 (CSV/MAT/PNG/JSON)
│
├─ README.md                       本文件
├─ LICENSE                         MIT
└─ .gitignore
```

---

## 5. 关键数据流 & 物理建模链路

### 5.1 单条样本生成 (会话 2 `generateSample`, 也是会话 1 step3/4 的内核)

```
┌─────────────────────────────────────── 输入 ───────────────────────────────────────┐
│ constellation, terminalPos(LLA), commSatPos/Vel(ECEF), monSatPos/Vel(ECEF),        │
│ simTime, channelIndex, snr_dB (设定值), doppler_Hz (设定值), opt.ExtraNoise_dB     │
└────────────────────────────────────────────────────────────────────────────────────┘
        │
        ▼ buildTerminalProfile() — 从 mcsTable 抽 MCS, 算仰角, 凑 txTemplate
        │
        ▼ dataGen.link.transmit() — Starlink/OneWeb 上行 OFDM Tx, 出 txWaveform + txInfo
        │
        ▼ dataGen.link.propagate(txWaveform, linkParams, t)
        │     ├─ FSPL + 大气 + 雨 + 闪烁 + 电离层 (ITU-R 全套)
        │     ├─ 离轴损耗 (UT 实际指向 commSat, monSat 在主瓣外)
        │     ├─ p681 LMS 慢衰落 (Suburban/Rural)
        │     ├─ 几何多普勒 = doppler_Hz (强制覆盖)
        │     └─ injectThermalNoise = false  ← 关键, 不在这里加噪声
        │
        ▼ dataGen.link.receive() — 600 MHz 宽带采样 + 信道搬移 + 时隙插入
        │     输出: 1.8e6 长 IQ + timeMask (burst 在哪)
        │
        ▼ AWGN 注入 (按 snr_dB - extraNoise_dB 反算 σ)
        │
        ▼ applyReceiverImpairments() — 0.85×Nyquist FIR LPF + DC 泄漏
        │
        ▼ 全局归一化 (mean(|x|^2) → 1)
        │
        ▼ 测量后处理后的 burst SNR / noiseFloor (写入 meta)
        │
        ▼ dataGen.io.spectrogram() — STFT → 640×640×3 uint8
        │
        ▼ sample = {iqData, stftImage, simTime, meta:{snr_set/eff/meas, doppler_set, …}}
```

### 5.2 会话 2 批量循环 (timer 驱动)

```
step6_RunBatch ── timer (period=50ms) ──┐
                                        ▼
                                  onBatchTick()
                                        │
                  ┌─────────────────────┼──────────────────────────────┐
                  ▼                     ▼                              ▼
          processOne(cell)       evalIngest(...)             notify TestCellReady
          ├─ generateSample      ├─ aggregateDetection       └─ Payload→Session2Result
          └─ detect(model,img)   ├─ EvalSNRStats[snr]++         ├─ renderSample (大图)
                                 ├─ EvalDopplerStats[dop]++     ├─ renderMeta (小标签)
                                 └─ EvalConfusion[r,c]++        └─ 弹窗追加历史样本
```

每 25 cell + 末 cell 触发一次曲线重绘 (`renderQuickCurves`), 全部完成后 `evalFinalize` 走 Wilson CI, `Reporter` 落盘。

---

## 6. 运行环境

### 6.1 操作系统

- ✅ Windows 10 / 11 (主开发环境, 路径为 `\` 反斜杠)
- ✅ macOS 13+ (路径会被 `fullfile` 自动正常化)
- ✅ Linux (Ubuntu 22.04 已知可用)
- ❌ Windows 7/8 / 32 位系统 (MATLAB 已不支持)

### 6.2 MATLAB 版本

| 项 | 要求 |
| --- | --- |
| MATLAB | **R2024b 及以上**, 推荐 **R2025a** (开发用) |
| 原因 | `yoloxObjectDetector` (R2024b 引入), `satelliteScenarioViewer` 内嵌模式, `matlabshared.application` 公共 API 在 R2024a 后稳定 |

### 6.3 必备 Toolbox

| Toolbox | 主要使用模块 | 不安装会怎样 |
| --- | --- | --- |
| **Satellite Communications Toolbox** | `satelliteScenario`, `satellite`, `groundStation`, `access`, `states`, `p681LMSChannel` | 启动直接报错 |
| **Communications Toolbox** | OFDM 调制器, `awgn`, `comm.*` | 通信链路无法构造 |
| **Signal Processing Toolbox** | `stft`, `designfilt`, `resample`, `filter` | STFT 无法生成 |
| **Image Processing Toolbox** | `insertShape`, `insertText`, `imresize` | 检测框/标签无法叠加 |
| **Computer Vision Toolbox** | `yoloxObjectDetector`, `detect()` | 无法做体制识别推理 |
| **Deep Learning Toolbox** | `dlnetwork`, `forward`, GPU 推理 | YOLOX 推理报错 |
| **Mapping Toolbox** | `lla2ecef`, ECEF↔LLA 工具 | 几何计算报错 |
| **Aerospace Toolbox** *(可选)* | TLE 验证 | 仅在没有 Satellite Comm Toolbox 时才用 |

### 6.4 硬件建议

| 组件 | 最低 | 推荐 (跑满 6000 cells) |
| --- | --- | --- |
| CPU | 4 核 | 8 核 + (会话 2 单 cell 0.4–1.2 s, OFDM 仿真是主要瓶颈) |
| 内存 | 8 GB | **16 GB** (1.8e6 IQ × double 复数 ≈ 30 MB / cell, 加上 STFT 图 ≈ 2 MB) |
| GPU | CPU 也能跑 | NVIDIA + CUDA, **会话 2 step6 自动启用 GPU**, 在 RTX 50 系列上 detect 段加速 ~3.5× |
| 磁盘 | 5 GB 项目 + 模型 | 20 GB+ 若开 IQ 落盘 |
| 显示器 | 1366×768 | 1920×1080 起 (GUI 默认 1600×950) |

### 6.5 GPU 配置 (RTX 30/40/50 系列)

会话 2 step6 的 YOLOX `detect()` 会自动选 GPU 路径, 但不同 GPU 架构需要不同处理:

| GPU 架构 | Compute Cap | MATLAB R2025a 行为 |
| --- | --- | --- |
| Pascal (10 系列) | 6.1 | 直接可用 |
| Turing (16/20 系列) | 7.5 | 直接可用 |
| Ampere (30 系列) | 8.6 | 直接可用 |
| Ada (40 系列) | 8.9 | 直接可用 |
| **Hopper / Blackwell (RTX 50 系列, H100, B200)** | **9.0 / 12.0** | **需开启 forward compatibility, 触发一次 PTX JIT 编译 (60+ 秒, 一次性)** |

`twin.launch()` (即 `runTwinPlatform.m`) 启动时会**自动**:

1. 调用 `parallel.gpu.enableCUDAForwardCompatibility(true)` (用户级 preference, 一次设置永久生效)
2. 触发一次 dummy `gpuArray` 计算, 让 cuBLAS / cuFFT 完成 PTX JIT 编译
3. step5 加载 detector 时还会主动 warmup `detect()` 网络一次

→ **首次启动会比较慢 (60-90 s, 主要是 PTX JIT)**, 之后所有 MATLAB session 都直接命中缓存。

如要手动覆盖 (例如笔记本核显切到 CPU):
```matlab
tf = app.Session2TestFlow;
tf.DetectExecEnv = 'cpu';   % 'auto' (默认) | 'cpu' | 'gpu'
tf.DetectBatchSize = 32;    % GPU 显存够时可以再大, 5090 32GB 可以试 64
```

实测性能 (yoloxs_ep30_bs32 / 96 张 640×640):

| 配置 | 96 张 detect 总耗时 | 每张 | 6000 cells (detect 段) 估算 |
| --- | ---: | ---: | ---: |
| CPU 8 核 单图 | 6.5 s | 68 ms | ≈ 7 min |
| RTX 5090 单图 | 1.9 s | 20 ms | ≈ 2 min |
| **RTX 5090 batch=16** | **1.85 s** | **19 ms** | **≈ 2 min** |
| **RTX 5090 batch=32** | **1.87 s** | **19 ms** | **≈ 2 min** |

→ detect 段**在 5090 上比 CPU 快 ~3.5×**。但 step6 整体瓶颈是 `generateSample` (OFDM Tx + p681 LMS 信道, CPU bound, ~0.5 s/cell), 6000 cells 全程估算: CPU ~83 min, GPU ~50 min (整体加速来自 detect 段节省的 5 分钟 + 其他小项)。

---

## 7. 外部依赖 (TLE 数据 & YOLOX 检测模型)

> **这两类资源不进 git**, 但 **缺少则平台无法启动到完整流程**。详细说明分别见:
>
> - 📄 [`data/README.md`](data/README.md) — TLE 来源、目录约定、聚合 → 拆分脚本
> - 📄 [`results/unified/detection/README.md`](results/unified/detection/README.md) — `detector.mat` 文件结构、加载逻辑、自训练步骤

### 7.1 TLE 数据

| 路径约定 | `<projectRoot>/data/TLE/{starlink,oneweb}/*.tle` |
| --- | --- |
| 单文件格式 | 3 行 (卫星名 + L1 + L2), ASCII 编码, 一颗星一个文件 |
| 推荐数量 | 每个星座 ≥ 30, 否则会话 2 NumSat=30 凑不齐 |
| 获取来源 | Celestrak `gp.php?GROUP=starlink&FORMAT=tle` / Space-Track |

### 7.2 YOLOX 检测模型

| 路径约定 | `<projectRoot>/results/unified/detection/<runTag>/detector.mat` |
| --- | --- |
| MAT 内变量 | 任意一个: `detector` (`yoloxObjectDetector`) / `net` (自定义 wrapper) |
| 类别命名 | 标签字符串包含 `starlink` / `oneweb` (大小写不敏感) |
| 模型大小 | YOLOX-S 训得的 `detector.mat` 约 **30–40 MB** |
| GUI 行为 | 步骤 5 自动按修改时间最新搜 `**/detector.mat`; 也可手动「浏览」选 |

如果只是想 **快速验证 GUI**, 可以联系仓库维护者获取一份预训练 `detector.mat` (~38 MB), 直接放到 `results/unified/detection/yoloxs_ep30_bs32/`。

---

## 8. 安装 & 启动

### 8.1 拉取代码 + 准备依赖

```powershell
git clone https://github.com/<your-account>/SatelliateMonitor.git
cd SatelliateMonitor

# 1) 准备 TLE
mkdir -Force data\TLE\starlink, data\TLE\oneweb
# 然后参考 data/README.md 把 .tle 文件拆好放进去

# 2) 准备 YOLOX 模型
mkdir -Force results\unified\detection\yoloxs_ep30_bs32
# 把 detector.mat 复制进去
```

### 8.2 启动 (推荐: MATLAB IDE 双击运行)

```matlab
>> cd('C:\path\to\SatelliateMonitor')
>> runTwinPlatform        % tools/ 下的入口脚本
```

入口脚本会自动 `addpath(genpath('cssa'))` 并把工作目录切到项目根，然后调用 `twin.launch()` 弹出 GUI。

### 8.3 启动 (无 IDE / CI / 远程 SSH)

```powershell
matlab -batch "addpath(genpath('cssa')); twin.launch();"
# 或 batch 跑一次会话 2 验收 (无 GUI):
matlab -batch "addpath(genpath('cssa')); plan = twin.app.Session2TestFlowPanel.buildPlan(struct('NumSatellites',30,'NumSNR',10,'NumDoppler',10)); disp(plan.TotalCells)"
```

### 8.4 启动后操作步骤

1. 工具条点 **「新建会话 ▼」** → 选 `多种信号体制识别测试` / `典型终端信号识别测试` / `干扰防御测试`
2. 流程面板里 **从上到下点按钮**, 也可以按 ▶ 一键运行 / ⏭ 单步
3. 会话 2 收到第一条样本后, 会自动弹出 **「会话2 样本检测明细 (滚动查看)」** 独立窗口
4. 步骤 7 完成后, 报告自动落到 `results/session2/<yyyyMMdd_HHmmss>/`

---

## 9. 输出产物

### 9.1 会话 2 报告文件

每跑一次, 产生一个时间戳子目录 `results/session2/<runTag>/`:

| 文件 | 用途 | 内容 |
| --- | --- | --- |
| `dataset_manifest.json` | 复现元数据 | 测试矩阵 + 接收机摘要 + 检测器路径 + 时间戳 |
| `samples_index.csv` | 样本级原始记录 | 每条样本一行: idx, constellation, satIdx, channelIndex, snrIdx, snr_set/meas, dopIdx, doppler, pred_label, top_score, is_correct, detected, numBoxes |
| `metrics.mat` | 聚合指标 | `metrics.snr.*`, `metrics.doppler.*`, `metrics.confusionMatrix`, `metrics.summary.*` |
| `acc_vs_snr.png` | 验收图 | 准确率-SNR 曲线 (Starlink + OneWeb), 95% Wilson CI |
| `acc_vs_doppler.png` | 验收图 | 准确率-多普勒曲线 (Starlink + OneWeb), 95% Wilson CI |
| `confusion_matrix.png` | 验收图 | 双星座混淆矩阵 (3 列: Starlink/OneWeb/漏检&多检) |

仓库内自带一份 demo 报告: `results/session2/production_6000/` (30×10×10×2=6000 cells)。

### 9.2 会话 1 / 3

不输出报告文件, 仅在 GUI 内可视化 (Starlink/OneWeb 双 STFT, BER 对比柱状图等)。

---

## 10. 二次开发指引

### 10.1 加一个新的会话

1. 在 `cssa/+twin/+app/` 新增 `SessionXTestFlowPanel.m` + `SessionXResultPanel.m`, 继承 `matlabshared.application.Component`
2. 在 `App.m` 的 `createDefaultComponents` 里 `new` 出来 + 加进返回数组
3. 在 `App.m` 的 `createToolstrip` 加一个 `ListItem`, `ItemPushedFcn` 指向 `startSessionX`
4. 实现 `startSessionX` 调 `startSessionLayout(X, testFlowPanel, resultPanel)` (2×2 自动布局已封装)

### 10.2 改测试矩阵规模

- GUI: 顶部参数区直接改 NumSat / NumSNR / NumDop
- 代码: 调 `Session2TestFlowPanel.buildPlan(struct('NumSatellites', N, ...))`

### 10.3 替换 / 重训 YOLOX

- 直接覆盖 `results/unified/detection/<新 runTag>/detector.mat`
- GUI 步骤 5 「浏览」 选新文件即可, 或者让 `autoFindDetector` 按修改时间自动选

### 10.4 加一种新干扰策略

1. 在 `cssa/spectrum/+jamming/+strategy/` 加 `myJam.m`, 函数签名:
   ```matlab
   function jam = myJam(signalLen, totalEnergy, burstInfo, options)
   ```
2. 在 `Session3TestFlowPanel.m` 的 `step5_LoadJamStrategies` 里 push 进 `JammingStrategies`
3. UI 即时可用, BER/能效会自动并入对比

### 10.5 调整 SNR 挑战难度

- `Session2TestFlowPanel` 类属性 `ChallengeExtraNoise_dB` (默认 6 dB)
- 推荐取值 `0~10`, `0` = 表里那 X 轴 SNR 就是分类器看到的 SNR

---

## 11. 常见问题 (FAQ)

**Q1: 启动后 3D 场景一片黑?**
A: 因为 TLE 没放进去, 卫星全部回退到默认开普勒参数, 视角又默认在地面附近。把 `data/TLE/<constellation>/*.tle` 放好后重启。

**Q2: 步骤 5 报「未找到 detector.mat」?**
A: 把训好的模型放到 `results/unified/detection/yoloxs_ep30_bs32/detector.mat`; 或在 GUI 顶部参数区点「浏览」 手选。

**Q3: 会话 2 跑 6000 cells 太久?**
A: 在顶部参数区把 NumSat / NumSNR / NumDop 调小 (例如 5×5×5×2 = 250 cells), 用作冒烟测试。或者关闭 `enableMultipath` (改 `Session2TestFlowPanel.generateSample` 里 linkParams.enableMultipath = false), p681 LMS 是耗时大头。

**Q4: 准确率全 100%, 不真实?**
A: 把 `Session2TestFlowPanel.ChallengeExtraNoise_dB` 调大 (8~10 dB), 或者把检测置信度阈值从 0.3 提到 0.6 (`processOne` 里 `detect(...,'Threshold',0.6)`)。

**Q5: 「曲线变成竖线」是 bug 吗?**
A: 不是。早期版本用 `errorbar` 画 95% Wilson CI, 在 OneWeb 还没采集到样本时显示成竖线。当前版本 (`renderFinalCurves` → `plotMetricCurve`) 已改为只画圆点+折线, CI 仍保留在 `metrics.mat` / `samples_index.csv` 中, 写报告时可手动取出。

**Q6: 两个 README (顶层这个 + `data/README.md`) 的关系?**
A: 顶层 README 讲全局; `data/README.md` 和 `results/unified/detection/README.md` 是 **分目录的「占位说明」**, 防止有人 clone 完一脸懵不知道这俩空文件夹要放啥。

---

## 12. 许可证

本项目使用 [MIT License](LICENSE)。

第三方依赖 / 数据来源:

- TLE 数据: [Celestrak](https://celestrak.org/) (CC BY) / [Space-Track](https://www.space-track.org/)
- YOLOX 算法: Ge et al., "YOLOX: Exceeding YOLO Series in 2021"
- ITU-R P.6xx / P.531 / P.681 系列推荐书 (公开)
- Starlink / OneWeb 物理层参数: FCC Filings 公开文件 (源码内有逐项 [Source: ...] 标注)
- MATLAB Satellite Comm / Communications / Signal Processing / Computer Vision Toolbox

> 任何论文 / 报告引用本项目, 请在 reference 里写明 GitHub 仓库地址即可。
