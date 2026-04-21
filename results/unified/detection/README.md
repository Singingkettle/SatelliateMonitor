# `results/unified/detection/` — YOLOX 检测模型 (不纳入版本控制)

整个 `results/unified/` 在 `.gitignore` 中被排除, 因为这里存放的是 **训练得到的检测模型权重** (`detector.mat`, 单文件 30 ~ 40 MB), 不适合直接进 GitHub。

## 期望的目录结构

```
results/unified/detection/
└─ <run_tag>/                # 例如 yoloxs_ep30_bs32, yoloxs_ep5_bs32
   ├─ detector.mat           # 必须存在, 内含一个 yoloxObjectDetector / dlnetwork
   └─ training_info.mat      # 可选, 训练日志/loss 曲线 (会忽略)
```

## 加载入口与自动选择规则

- `cssa\+twin\+app\Session2TestFlowPanel.m :: autoFindDetector`
  会按以下优先级递归搜索 `*.mat`, 选 **修改时间最新的那一个**:
    1. `<projectRoot>\results\unified\detection\**\detector.mat`
    2. `<projectRoot>\models\detection\**\detector.mat`
- `cssa\+twin\+app\TestFlowPanel.m :: loadDetectorAuto` 同样的策略, 用于会话 1。
- 也可以在 GUI 「步骤 5 检测器」按 「浏览」 手动指定任意路径。

## `detector.mat` 内部约定

加载后会读取下列字段中的任意一个 (按顺序匹配第一个存在的):

| MAT 中的变量 | 类型 | 说明 |
| ------------ | ---- | ---- |
| `detector`   | `yoloxObjectDetector` (R2024b+) | 推荐, GUI 默认调用 `detect(detector, img, 'Threshold', t)` |
| `net`        | `dlnetwork` 或自定义 wrapper     | 必须自带 `detect()` 方法, 输入 640×640 RGB, 输出 `[bboxes, scores, labels]` |

类别标签必须 **包含** `starlink` 和 `oneweb` (大小写不敏感, 中间可以加任何前后缀如 `starlink_terminal`), 这样 `aggregateDetection` 能正确归类。

## 自己训练的最小流程 (可选)

数据集生成模块 `cssa\spectrum\+dataGen\` 仍保留 (会话 2 的样本生成函数 `generateSample` 复用了同一套 STFT 链路), 可批量产出 (img, label) 配对供 `trainYOLOXObjectDetector` 使用:

```matlab
addpath(genpath('cssa'));
% 1) 用 Session2TestFlowPanel.generateSample 批量构造 (img, label) tfds
% 2) 调 R2024b+ 的 trainYOLOXObjectDetector
% 3) save('results/unified/detection/<runTag>/detector.mat', 'detector', '-v7');
```

如果你只想 **快速跑通 demo**, 可以联系仓库维护者获取一份 `yoloxs_ep30_bs32/detector.mat` 离线分发件 (~38 MB)。
