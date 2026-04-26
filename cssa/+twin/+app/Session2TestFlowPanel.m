classdef Session2TestFlowPanel < matlabshared.application.Component
    % SESSION2TESTFLOWPANEL 会话2 验收测试流程面板
    %
    %   7 步固定流程：
    %     1. 创建仿真场景            （输入：起止时间/SampleTime；输出：satelliteScenario）
    %     2. 加载 30+30 颗卫星        （输入：TLE 集合；输出：60 个 satellite 对象）
    %     3. 部署终端 + 伴飞卫星      （输入：satellite；输出：60 ground station + 60 companion）
    %     4. 配置测试矩阵            （输入：NumSat/NumSNR/NumDoppler；输出：6000 个 cell）
    %     5. 加载 YOLOX 检测模型     （输入：detector.mat 路径；输出：detector 对象）
    %     6. 批量生成 + 检测 + 实时统计 （驱动 Generator+Evaluator）
    %     7. 汇总并导出测试报告       （调 Reporter，写入 results/session2/<runTag>/）
    %
    %   每步在 UI 上显式标注「输入 / 输出 / 规模」。
    
    properties (Hidden)
        MainGrid
        StepsLayout
        
        StepButtons
        StepLabels
        StepStatus              % 0=pending, 1=active, 2=completed
        CurrentStep = 0
        
        % --- 配置控件 ---
        NumSatEdit              % 每星座卫星数（默认 30）
        NumSNREdit              % SNR 点数（默认 10）
        NumDopplerEdit          % 多普勒点数（默认 10）
        SnrMinEdit              % SNR 最小（默认 -10）
        SnrMaxEdit              % SNR 最大（默认  10）
        DopStarEdit             % Starlink 最大频偏 kHz（默认 360）
        DopOneEdit              % OneWeb   最大频偏 kHz（默认 345）
        OffsetSlider            % 伴飞偏移 km（默认 14）
        OffsetLabel
        DetectorPathLabel

        % --- 状态栏 ---
        StatusLabel
        ProgressLabel

        % --- 域对象（Plan/Generator/Evaluator/Reporter 已 inline 为本类的静态方法/内部状态）---
        Plan struct = struct()                  % 由 Session2TestFlowPanel.buildPlan 返回
        DetectionModel
        DetectorPath = ''

        % --- Evaluator 内部状态（替代原 +session2/Evaluator.m）---
        EvalRecords struct = struct( ...
            'idx', {}, 'constellation', {}, 'satIdx', {}, 'channelIndex', {}, ...
            'snrIdx', {}, 'snr_set_dB', {}, 'snr_meas_dB', {}, ...
            'dopIdx', {}, 'doppler_set_Hz', {}, ...
            'pred_label', {}, 'top_score', {}, 'is_correct', {}, ...
            'detected', {}, 'numBoxes', {})
        EvalNumRecorded (1,1) double = 0
        EvalSNRStats struct = struct()
        EvalDopplerStats struct = struct()
        EvalConfusion (2,3) double = zeros(2,3)
        EvalConstellations cell = {'starlink', 'oneweb'}

        % --- 场景与卫星阵列（Cell array, 长度 = NumSatellites） ---
        Scenario
        StarlinkSats
        OnewebSats
        StarlinkUTs
        OnewebUTs
        StarlinkCompanions
        OnewebCompanions

        % --- 运行时 ---
        AnimationTimer
        IsRunning = false
        ProcessIdx = 0

        % --- 默认值 ---
        ScenarioDuration_sec = 60
        ScenarioSampleTime_sec = 1
        CompanionOffset_km = 14

        % --- 验收口径 ---
        % 在按 snr_dB 注入 AWGN 之外, 再叠一层"挑战噪声"使分类器实际看到的
        % SNR 比设定低这么多 dB. 显示的 X 轴 SNR 范围保持不变, 让曲线随 SNR
        % 真实下沉, 避免任意 SNR 都 100% 准确率. 0 表示禁用.
        ChallengeExtraNoise_dB (1,1) double = 6

        % --- 批检测加速 ---
        % step6 攒满 BatchSize 张 STFT 后一次性 detect, 在 GPU 上速度提升明显.
        % 0 或 1 = 退化为逐张 detect.
        % 5090 (32GB) batch=32 实测每张 ~18ms (vs 单图 ~50ms / 单图 CPU ~80ms).
        DetectBatchSize (1,1) double = 32
        DetectExecEnv (1,:) char = 'auto'   % 'auto' | 'cpu' | 'gpu'
    end
    
    properties (Constant, Hidden)
        StepNames = { ...
            '创建仿真场景' ...
            '加载 30+30 颗卫星' ...
            '部署地面终端 + 伴飞卫星' ...
            '配置测试矩阵' ...
            '加载 YOLOX 检测模型' ...
            '批量生成 + 检测 + 实时统计' ...
            '汇总并导出测试报告' ...
        }

        StepIO = { ...
            '输入: 起止时间, SampleTime    输出: satelliteScenario' ...
            '输入: TLE/starlink + TLE/oneweb    输出: 30+30 颗 satellite 对象' ...
            '输入: 主卫星 + 偏移距离      输出: 30+30 个 groundStation + companion 卫星' ...
            '输入: NumSat × NumSNR × NumDop    输出: 6000 个测试 cell (含 SNR/Doppler/信道号)' ...
            '输入: results/.../detector.mat   输出: YOLOX detector 对象' ...
            '输入: 6000 cells × (1.8e6点 IQ → 640×640 STFT)    输出: 实时精度+混淆矩阵' ...
            '输入: Evaluator.metrics      输出: results/session2/<runTag>/{csv,mat,png,json}' ...
        }

        BgColor = [0.10 0.10 0.12]
        TextColor = [0.85 0.85 0.85]
        AccentColor = [0.20 0.60 1.00]
        SuccessColor = [0.30 0.90 0.40]
        PendingColor = [0.50 0.50 0.50]
        ActiveColor = [1.00 0.80 0.20]
    end
    
    events
        StepCompleted
        AllStepsCompleted
        TestCellReady           % 单条样本完成 (TestFrameEventData, Payload 内含 Cell/Sample/Detection/Snapshot/Processed/TotalCells)
        TestCompleted           % 整个测试矩阵完成
        TestExportReady         % 报告导出完成
    end
    
    methods
        function this = Session2TestFlowPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
            this.StepButtons = cell(numel(this.StepNames), 1);
            this.StepLabels = cell(numel(this.StepNames), 1);
            this.StepStatus = zeros(numel(this.StepNames), 1);
        end
        
        function name = getName(~)
            name = '测试流程';
        end
        
        function tag = getTag(~)
            tag = 'session2testflow';
        end
        
        function update(this)
            createUI(this);
        end
        
        function createUI(this)
            clf(this.Figure);
            this.Figure.Color = this.BgColor;
            
            this.MainGrid = uigridlayout(this.Figure, [5, 1]);
            this.MainGrid.RowHeight = {32, 'fit', '1x', 24, 36};
            this.MainGrid.ColumnWidth = {'1x'};
            this.MainGrid.Padding = [8 8 8 8];
            this.MainGrid.RowSpacing = 6;
            this.MainGrid.BackgroundColor = this.BgColor;
            
            % ---- 标题 ----
            titlePanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.15 0.15 0.18], 'BorderType', 'none');
            tl = uigridlayout(titlePanel, [1, 1]);
            tl.Padding = [10 2 10 2];
            tl.BackgroundColor = [0.15 0.15 0.18];
            uilabel(tl, ...
                'Text', '典型终端信号识别 — 验收测试流程 (会话 2)', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', this.AccentColor, ...
                'BackgroundColor', [0.15 0.15 0.18]);
            
            % ---- 参数区 (步骤 3 偏移 / 步骤 4 矩阵 / 步骤 5 检测器) ----
            this.buildConfigArea(this.MainGrid);

            % ---- 步骤按钮区 (整行可点击, 无单独「执行」按钮) ----
            stepsPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', this.BgColor, 'BorderType', 'none');
            n = numel(this.StepNames);
            this.StepsLayout = uigridlayout(stepsPanel, [n, 1]);
            this.StepsLayout.RowHeight = repmat({'1x'}, 1, n);
            this.StepsLayout.Padding = [0 0 0 0];
            this.StepsLayout.RowSpacing = 4;
            this.StepsLayout.BackgroundColor = this.BgColor;
            
            for i = 1:n
                this.createStepButton(this.StepsLayout, i);
            end

            % ---- 状态栏 ----
            statusPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.12 0.12 0.14], 'BorderType', 'none');
            sl = uigridlayout(statusPanel, [1, 2]);
            sl.ColumnWidth = {'1x', 'fit'};
            sl.Padding = [10 1 10 1];
            sl.BackgroundColor = [0.12 0.12 0.14];

            this.StatusLabel = uilabel(sl, ...
                'Text', '准备就绪 — 点击下方任意步骤即可执行', ...
                'FontSize', 11, 'FontColor', this.TextColor, ...
                'BackgroundColor', [0.12 0.12 0.14]);
            this.ProgressLabel = uilabel(sl, ...
                'Text', '进度: 0 / 0', 'FontSize', 11, ...
                'FontColor', this.AccentColor, ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', [0.12 0.12 0.14]);
            
            % ---- 控制按钮 ----
            controlPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.12 0.12 0.14], 'BorderType', 'none');
            cl = uigridlayout(controlPanel, [1, 4]);
            cl.ColumnWidth = {'1x', '1x', '1x', '1x'};
            cl.Padding = [8 2 8 2];
            cl.ColumnSpacing = 8;
            cl.BackgroundColor = [0.12 0.12 0.14];

            uibutton(cl, ...
                'Text', '▶ 自动执行', 'FontSize', 11, ...
                'BackgroundColor', this.AccentColor, 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.runAllSteps());
            uibutton(cl, ...
                'Text', '⏭ 单步', 'FontSize', 11, ...
                'BackgroundColor', [0.4 0.7 0.3], 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.runNextStep());
            uibutton(cl, ...
                'Text', '⏹ 停止', 'FontSize', 11, ...
                'BackgroundColor', [0.7 0.5 0.2], 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.stopTest());
            uibutton(cl, ...
                'Text', '↺ 重置', 'FontSize', 11, ...
                'BackgroundColor', [0.5 0.3 0.3], 'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.resetSteps());
            
            this.enableStep(1);
        end
        
        function buildConfigArea(this, parent)
            % 顶部参数区: 把步骤 3/4/5 的可编辑参数集中, 让步骤按钮保持整齐
            cfgPanel = uipanel(parent, ...
                'Title', '参数 (步骤 3 偏移 · 步骤 4 测试矩阵 · 步骤 5 检测器)', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', [0.55 0.55 0.55], ...
                'FontSize', 10, ...
                'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            grid = uigridlayout(cfgPanel, [2, 1]);
            grid.RowHeight = {'fit', 'fit'};
            grid.RowSpacing = 4;
            grid.Padding = [8 4 8 4];
            grid.BackgroundColor = this.BgColor;

            % --- 矩阵参数 (NumSat/NumSNR/NumDop + SNR/Doppler 上下限) ---
            matRow = uigridlayout(grid, [1, 14]);
            matRow.ColumnWidth = repmat({'fit'}, 1, 14);
            matRow.ColumnSpacing = 4;
            matRow.Padding = [0 0 0 0];
            matRow.BackgroundColor = this.BgColor;
            this.NumSatEdit     = this.makeSpinner(matRow, 'NumSat',   30,  [1 200]);
            this.NumSNREdit     = this.makeSpinner(matRow, 'NumSNR',   10,  [2 50]);
            this.NumDopplerEdit = this.makeSpinner(matRow, 'NumDop',   10,  [2 50]);
            this.SnrMinEdit     = this.makeSpinner(matRow, 'SNRmin',   -10, [-30 20]);
            this.SnrMaxEdit     = this.makeSpinner(matRow, 'SNRmax',   10,  [-30 30]);
            this.DopStarEdit    = this.makeSpinner(matRow, 'fdSL/kHz', 360, [10 1000]);
            this.DopOneEdit     = this.makeSpinner(matRow, 'fdOW/kHz', 345, [10 1000]);

            % --- 偏移滑块 + 检测器路径 ---
            bottomRow = uigridlayout(grid, [1, 5]);
            bottomRow.ColumnWidth = {'fit', 110, 60, '1x', 60};
            bottomRow.ColumnSpacing = 6;
            bottomRow.Padding = [0 0 0 0];
            bottomRow.BackgroundColor = this.BgColor;
            uilabel(bottomRow, 'Text', '伴飞偏移:', 'FontSize', 10, ...
                'FontColor', [0.7 0.7 0.7], ...
                'BackgroundColor', this.BgColor);
            this.OffsetSlider = uislider(bottomRow, ...
                'Limits', [0 30], 'Value', this.CompanionOffset_km, ...
                'MajorTicks', [], 'MinorTicks', [], ...
                'ValueChangedFcn', @(src,~) this.onOffsetChanged(src.Value));
            this.OffsetLabel = uilabel(bottomRow, ...
                'Text', sprintf('%.0f km', this.CompanionOffset_km), ...
                'FontSize', 10, 'FontColor', this.AccentColor, ...
                'BackgroundColor', this.BgColor);
            this.DetectorPathLabel = uilabel(bottomRow, ...
                'Text', '检测器: (auto)', ...
                'FontSize', 9, 'FontColor', [0.7 0.7 0.7], ...
                'BackgroundColor', this.BgColor);
            uibutton(bottomRow, 'Text', '浏览', 'FontSize', 9, ...
                'BackgroundColor', [0.25 0.25 0.28], ...
                'FontColor', this.TextColor, ...
                'ButtonPushedFcn', @(~,~) this.pickDetectorFile());
        end

        function createStepButton(this, parent, idx)
            % 整行 button: 第一行 = 编号 + 步骤名, 第二行 = 输入/输出说明
            btn = uibutton(parent, ...
                'Text', this.formatStepText(idx, 'pending'), ...
                'FontSize', 11, ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', [0.18 0.18 0.20], ...
                'FontColor', this.TextColor, ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(~,~) this.executeStep(idx));
            this.StepButtons{idx} = btn;
            this.StepLabels{idx} = struct('btn', btn);
        end

        function txt = formatStepText(this, idx, state)
            % state: 'pending' | 'active' | 'completed' | 'enabled'
            switch state
                case 'completed', prefix = '✓';
                case 'active',    prefix = '▶';
                otherwise,        prefix = sprintf('%d', idx);
            end
            line1 = sprintf('  %s   %s', prefix, this.StepNames{idx});
            line2 = sprintf('       %s', this.StepIO{idx});
            txt = {line1; line2};
        end

        function ed = makeSpinner(this, host, label, defaultVal, limits)
            uilabel(host, ...
                'Text', label, 'FontSize', 9, ...
                'FontColor', [0.7 0.7 0.7], ...
                'BackgroundColor', this.BgColor);
            ed = uieditfield(host, 'numeric', ...
                'Value', defaultVal, 'Limits', limits, ...
                'FontSize', 9, ...
                'BackgroundColor', [0.20 0.20 0.22], ...
                'FontColor', this.TextColor);
        end

        % ============================================================
        %   控件事件
        % ============================================================
        function onOffsetChanged(this, v)
            this.CompanionOffset_km = v;
            this.OffsetLabel.Text = sprintf('%.0f km', v);
        end

        function pickDetectorFile(this)
            [f, p] = uigetfile({'detector.mat;*.mat', 'YOLOX detector'}, ...
                '选择 YOLOX 检测器 .mat', this.defaultDetectorRoot());
            if isequal(f, 0); return; end
            full = fullfile(p, f);
            this.DetectorPath = full;
            this.DetectorPathLabel.Text = full;
        end

        % ============================================================
        %   单步 / 自动执行调度
        % ============================================================
        function executeStep(this, idx)
            this.setStepActive(idx);
            this.updateStatus(sprintf('正在执行: %s', this.StepNames{idx}));
            drawnow;
            
            try
                switch idx
                    case 1, this.step1_CreateScenario();
                    case 2, this.step2_LoadConstellations();
                    case 3, this.step3_DeployTerminalsAndCompanions();
                    case 4, this.step4_BuildPlan();
                    case 5, this.step5_LoadDetector();
                    case 6, this.step6_RunBatch();
                    case 7, this.step7_ExportReport();
                end
                this.setStepCompleted(idx);
                this.updateStatus(sprintf('完成: %s', this.StepNames{idx}));
                if idx < numel(this.StepNames)
                    this.enableStep(idx + 1);
                else
                    notify(this, 'AllStepsCompleted');
                end
                notify(this, 'StepCompleted');
            catch ME
                this.updateStatus(sprintf('错误: %s', ME.message));
                this.setStepActive(idx);
                rethrow(ME);
            end
        end
        
        function runAllSteps(this)
            for i = 1:numel(this.StepNames)
                if this.StepStatus(i) ~= 2
                    try
                    this.executeStep(i);
                    catch
                        return;
                    end
                    pause(0.2); drawnow;
                end
            end
        end
        
        function runNextStep(this)
            nextStep = this.CurrentStep + 1;
            if nextStep <= numel(this.StepNames)
                this.executeStep(nextStep);
            end
        end
        
        function stopTest(this)
            this.IsRunning = false;
            if ~isempty(this.AnimationTimer) && isvalid(this.AnimationTimer)
                stop(this.AnimationTimer);
            end
            this.updateStatus('测试已停止');
        end

        function resetSteps(this)
            this.stopTest();
            if ~isempty(this.AnimationTimer) && isvalid(this.AnimationTimer)
                delete(this.AnimationTimer);
            end
            this.AnimationTimer = [];

            % 清场景
            if ~isempty(this.Scenario) && isvalid(this.Scenario)
                try, delete(this.Scenario); catch, end
            end
            this.Scenario = [];
            this.StarlinkSats = {}; this.OnewebSats = {};
            this.StarlinkUTs = {};  this.OnewebUTs = {};
            this.StarlinkCompanions = {}; this.OnewebCompanions = {};

            this.Plan = struct();
            this.evalReset();
            this.DetectionModel = [];

            this.ProcessIdx = 0;
            this.CurrentStep = 0;
            
            for i = 1:numel(this.StepNames)
                this.setStepPending(i);
            end
            this.enableStep(1);

            if isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.clearViewer();
            end
            if isprop(this.Application, 'Session2Result') && ~isempty(this.Application.Session2Result)
                if ismethod(this.Application.Session2Result, 'reset')
                    this.Application.Session2Result.reset();
                end
            end

            this.updateProgress(0, 0);
            this.updateStatus('已重置');
        end

        % ============================================================
        %   各步实现
        % ============================================================
        function step1_CreateScenario(this)
            startTime = datetime('now', 'TimeZone', 'UTC');
            stopTime = startTime + seconds(this.ScenarioDuration_sec);
            
            this.Scenario = satelliteScenario(startTime, stopTime, ...
                this.ScenarioSampleTime_sec, 'AutoSimulate', false);
            
            if isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.createViewer(this.Scenario);
            end
            fprintf('[Session2] 场景: %s ~ %s, SampleTime=%.1fs\n', ...
                datestr(startTime), datestr(stopTime), this.ScenarioSampleTime_sec);
        end

        function step2_LoadConstellations(this)
            if isempty(this.Scenario), error('请先创建场景'); end
            numSat = round(this.NumSatEdit.Value);

            this.StarlinkSats = this.loadRandomSats('starlink', numSat);
            this.OnewebSats   = this.loadRandomSats('oneweb', numSat);

            fprintf('[Session2] 已加载 Starlink %d 颗, OneWeb %d 颗\n', ...
                numel(this.StarlinkSats), numel(this.OnewebSats));
        end

        function step3_DeployTerminalsAndCompanions(this)
            if isempty(this.StarlinkSats) || isempty(this.OnewebSats)
                error('请先加载卫星');
            end
            this.StarlinkUTs = cell(numel(this.StarlinkSats), 1);
            this.StarlinkCompanions = cell(numel(this.StarlinkSats), 1);
            this.OnewebUTs = cell(numel(this.OnewebSats), 1);
            this.OnewebCompanions = cell(numel(this.OnewebSats), 1);

            this.deployForConstellation('starlink', ...
                this.StarlinkSats, 'StarlinkUTs', 'StarlinkCompanions');
            this.deployForConstellation('oneweb', ...
                this.OnewebSats, 'OnewebUTs', 'OnewebCompanions');

            fprintf('[Session2] 终端 + 伴飞卫星部署完成（Starlink %d，OneWeb %d）\n', ...
                numel(this.StarlinkUTs), numel(this.OnewebUTs));
        end

        function step4_BuildPlan(this)
            this.Plan = twin.app.Session2TestFlowPanel.buildPlan(struct( ...
                'NumSatellites', round(this.NumSatEdit.Value), ...
                'NumSNR', round(this.NumSNREdit.Value), ...
                'NumDoppler', round(this.NumDopplerEdit.Value), ...
                'SnrRange_dB', [this.SnrMinEdit.Value, this.SnrMaxEdit.Value], ...
                'DopplerMaxStarlink_Hz', this.DopStarEdit.Value * 1e3, ...
                'DopplerMaxOneweb_Hz',   this.DopOneEdit.Value * 1e3));

            n = numel(this.Plan.Cells);
            this.evalInit();
            this.updateProgress(0, n);

            % 通知 Result 面板：测试矩阵已就绪
            if isprop(this.Application, 'Session2Result') && ~isempty(this.Application.Session2Result)
                if ismethod(this.Application.Session2Result, 'onPlanReady')
                    this.Application.Session2Result.onPlanReady(this.Plan);
                end
            end

            fprintf('[Session2] 测试矩阵: %d sat × %d SNR × %d Doppler × 2 = %d cells\n', ...
                this.Plan.NumSatellites, this.Plan.NumSNR, this.Plan.NumDoppler, n);
        end

        function step5_LoadDetector(this)
            path = this.DetectorPath;
            if isempty(path)
                path = this.autoFindDetector();
            end
            if isempty(path) || ~exist(path, 'file')
                error('未找到 detector.mat，请通过「浏览」选择');
            end
            data = load(path);
            if isfield(data, 'detector')
                this.DetectionModel = data.detector;
            elseif isfield(data, 'net')
                this.DetectionModel = data.net;
            else
                error('detector.mat 格式不识别');
            end
            this.DetectorPath = path;
            if ~isempty(this.DetectorPathLabel)
                this.DetectorPathLabel.Text = path;
            end
            fprintf('[Session2] 已加载检测器: %s\n', path);

            % --- 主动 warmup detect 网络, 避免 step6 第一个 batch 卡顿 ---
            execEnv = this.resolveExecEnv();
            try
                tWarm = tic;
                dummy = uint8(randi(255, 640, 640, 3));
                detect(this.DetectionModel, dummy, ...
                    'Threshold', 0.30, 'ExecutionEnvironment', execEnv);
                fprintf('[Session2] detect 网络预热完成 (%s, %.1fs)\n', execEnv, toc(tWarm));
            catch ME
                fprintf('[Session2] detect 预热失败: %s\n', ME.message);
            end
        end

        function step6_RunBatch(this)
            % 同步 batch 循环: 攒 BatchSize 张 STFT 一次 detect (优先 GPU).
            % 与原 timer 逐张 detect 相比, 在 GPU 上每张 detect 耗时从几十
            % ms 降到几 ms (摊薄到每张, batch=16~32 时基本是 GPU 拷贝主导).
            if isempty(this.Plan) || ~isfield(this.Plan, 'Cells') || isempty(this.Plan.Cells)
                error('请先完成步骤 4');
            end
            if isempty(this.DetectionModel)
                error('请先加载检测模型');
            end

            cells = this.Plan.Cells;
            n = numel(cells);
            this.ProcessIdx = 0;
            this.IsRunning = true;
            this.updateProgress(0, n);

            execEnv = this.resolveExecEnv();
            B = max(1, round(this.DetectBatchSize));
            fprintf('[Session2] step6: BatchSize=%d, ExecEnv=%s, total=%d cells\n', B, execEnv, n);

            t0 = tic;
            i = 0;
            while i < n
                if ~this.IsRunning, break; end

                % --- 1) 当前 batch 内逐条 generateSample ---
                jEnd = min(i + B, n);
                bsz = jEnd - i;
                samples = cell(bsz, 1);
                imgsBatch = zeros(640, 640, 3, bsz, 'uint8');
                cellsBatch = cells(i+1:jEnd);
                badMask = false(bsz, 1);

                for k = 1:bsz
                    try
                        samples{k} = this.generateSampleForCell(cellsBatch(k));
                        img = samples{k}.stftImage;
                        if size(img, 3) == 1, img = repmat(img, 1, 1, 3); end
                        if ~isa(img, 'uint8')
                            if max(img(:)) <= 1, img = uint8(img * 255); else, img = uint8(img); end
                        end
                        imgsBatch(:, :, :, k) = img;
                    catch ME
                        fprintf('[Session2] sample #%d 生成失败: %s\n', i+k, ME.message);
                        badMask(k) = true;
                    end
                end

                if any(badMask)
                    % 给坏样本塞个全黑兜底, batch 完整性优先
                    imgsBatch(:, :, :, badMask) = 0;
                end

                % --- 2) 一次性 batch detect ---
                detResultsCell = cell(bsz, 1);
                try
                    if bsz == 1
                        [bb, sc, lb] = detect(this.DetectionModel, imgsBatch(:,:,:,1), ...
                            'Threshold', 0.30, 'ExecutionEnvironment', execEnv);
                        detResultsCell{1} = struct('bboxes', bb, 'scores', sc, 'labels', lb);
                    else
                        [bbC, scC, lbC] = detect(this.DetectionModel, imgsBatch, ...
                            'Threshold', 0.30, 'ExecutionEnvironment', execEnv);
                        for k = 1:bsz
                            detResultsCell{k} = struct( ...
                                'bboxes', bbC{k}, 'scores', scC{k}, 'labels', lbC{k});
                        end
                    end
                catch ME
                    fprintf('[Session2] batch detect 失败 (%s), 退化为逐张\n', ME.message);
                    for k = 1:bsz
                        try
                            [bb, sc, lb] = detect(this.DetectionModel, imgsBatch(:,:,:,k), ...
                                'Threshold', 0.30);
                            detResultsCell{k} = struct('bboxes', bb, 'scores', sc, 'labels', lb);
                        catch
                            detResultsCell{k} = struct('bboxes', zeros(0,4), 'scores', [], 'labels', {{}});
                        end
                    end
                end

                % --- 3) 回填 evaluator + notify TestCellReady (按顺序) ---
                for k = 1:bsz
                    if badMask(k), continue; end
                    cellInfo = cellsBatch(k);
                    detection = detResultsCell{k};
                    if isempty(detection)
                        detection = struct('bboxes', zeros(0,4), 'scores', [], 'labels', {{}});
                    end
                    sample = samples{k};
                    try
                        this.evalIngest(cellInfo, sample, detection);
                        this.ProcessIdx = i + k;
                        snapshot = this.evalSnapshot();
                        notify(this, 'TestCellReady', ...
                            twin.app.TestFrameEventData(struct( ...
                                'CellInfo', cellInfo, ...
                                'Sample', sample, ...
                                'Detection', detection, ...
                                'Snapshot', snapshot, ...
                                'Processed', this.ProcessIdx, ...
                                'TotalCells', n)));
                    catch ME
                        fprintf('[Session2] cell #%d 入库失败: %s\n', i+k, ME.message);
                    end
                end

                this.updateProgress(this.ProcessIdx, n);
                drawnow limitrate;

                % 节流统计 (每 batch 打印一次)
                if mod(jEnd, B*8) == 0 || jEnd == n
                    elapsed = toc(t0);
                    rate = this.ProcessIdx / max(elapsed, eps);
                    eta = (n - this.ProcessIdx) / max(rate, eps);
                    fprintf('[Session2] %d/%d cells, %.1f cells/s, ETA %.0fs\n', ...
                        this.ProcessIdx, n, rate, eta);
                end

                i = jEnd;
            end

            this.IsRunning = false;
            this.updateStatus('批量测试完成，可执行步骤 7 导出报告');
            notify(this, 'TestCompleted');

            % 用户中途点了「⏹ 停止」-> 抛错让 executeStep 标错误
            if this.ProcessIdx < n
                error('twin:Session2:BatchAborted', ...
                    '批量测试被用户停止 (已处理 %d / %d, 评估记录 %d 条)', ...
                    this.ProcessIdx, n, this.EvalNumRecorded);
            end
        end

        function execEnv = resolveExecEnv(this)
            % 'auto' -> 有 GPU 用 'gpu', 否则 'cpu'
            execEnv = 'cpu';
            switch lower(this.DetectExecEnv)
                case 'gpu', execEnv = 'gpu';
                case 'cpu', execEnv = 'cpu';
                otherwise   % auto
                    try
                        if exist('gpuDeviceCount', 'file') && gpuDeviceCount('available') > 0
                            execEnv = 'gpu';
                        end
                    catch
                        execEnv = 'cpu';
                    end
            end
        end

        function sample = generateSampleForCell(this, cellInfo)
            % 拆出来给 batch 路径用 (原 processOne 里前半段)
            con = cellInfo.constellation;
            switch lower(con)
                case 'starlink'
                    satObj = this.StarlinkSats{cellInfo.satIdx};
                    utObj = this.StarlinkUTs{cellInfo.satIdx};
                    compObj = this.StarlinkCompanions{cellInfo.satIdx};
                case 'oneweb'
                    satObj = this.OnewebSats{cellInfo.satIdx};
                    utObj = this.OnewebUTs{cellInfo.satIdx};
                    compObj = this.OnewebCompanions{cellInfo.satIdx};
                otherwise
                    error('未知星座 %s', con);
            end
            duration_sec = seconds(this.Scenario.StopTime - this.Scenario.StartTime);
            offsetSec = rand() * max(0.0, duration_sec);
            simTime = this.Scenario.StartTime + seconds(offsetSec);
            [commSatPos, ~] = states(satObj, simTime, 'CoordinateFrame', 'ecef');
            [companionPos, companionVel] = states(compObj, simTime, 'CoordinateFrame', 'ecef');

            terminalPos = [utObj.Latitude, utObj.Longitude, 0];
            sample = twin.app.Session2TestFlowPanel.generateSample( ...
                con, terminalPos, commSatPos(:), companionPos(:), companionVel(:), ...
                simTime, cellInfo.channelIndex, cellInfo.snr_dB, cellInfo.doppler_Hz, ...
                'Seed', cellInfo.sampleSeed, ...
                'ExtraNoise_dB', this.ChallengeExtraNoise_dB);
        end

        function step7_ExportReport(this)
            if this.IsRunning
                error('twin:Session2:BatchStillRunning', ...
                    '步骤 6 批量测试仍在运行 (%d / %d), 请等待完成或先点「⏹ 停止」', ...
                    this.ProcessIdx, numel(this.Plan.Cells));
            end
            if this.EvalNumRecorded == 0
                error('请先完成步骤 6 (无评估记录)');
            end
            metrics = this.evalFinalize();
            recvSummary = this.summarizeReceiver();
            paths = twin.app.Session2TestFlowPanel.exportReport( ...
                this.Plan, metrics, ...
                'DetectorPath', this.DetectorPath, ...
                'ReceiverSummary', recvSummary);

            fprintf('[Session2] 测试报告导出完成 -> %s\n', paths.outputDir);
            disp(paths);

            % 通知结果面板拉取最终曲线/混淆矩阵
            if isprop(this.Application, 'Session2Result') && ~isempty(this.Application.Session2Result)
                if ismethod(this.Application.Session2Result, 'onMetricsFinalized')
                    this.Application.Session2Result.onMetricsFinalized(metrics, paths);
                end
            end
            notify(this, 'TestExportReady');
        end

        % ============================================================
        %   工具方法
        % ============================================================
        function sats = loadRandomSats(this, constellation, numSat)
            % 随机抽取 numSat 个 TLE 文件，并构造 satellite 对象数组（cell）
            projectRoot = this.projectRoot();
            tleDir = fullfile(projectRoot, 'data', 'TLE', constellation);
            files = dir(fullfile(tleDir, '*.tle'));
            if isempty(files)
                error('未找到 TLE 文件: %s', tleDir);
            end

            order = randperm(numel(files));
            sats = cell(numSat, 1);
            picked = 0;
            for k = 1:numel(order)
                if picked >= numSat, break; end
                tlePath = fullfile(files(order(k)).folder, files(order(k)).name);
                try
                    s = satellite(this.Scenario, tlePath);
                    if numel(s) > 1, s = s(1); end
                    picked = picked + 1;
                    sats{picked} = s;
                catch ME
                    fprintf('[Session2] 跳过 %s: %s\n', files(order(k)).name, ME.message);
                end
            end
            if picked < numSat
                warning('twin:session2:Panel:NotEnoughSats', ...
                    '%s 仅成功加载 %d 颗（请求 %d）', constellation, picked, numSat);
                sats = sats(1:picked);
            end
        end

        function deployForConstellation(this, constellation, sats, utField, compField)
            % 为每颗 sat 生成一个 ground station + 一个 companion satellite
            n = numel(sats);
            for i = 1:n
                satObj = sats{i};
                try
                    % 用 terminal.m 默认 80 候选 (已批量化), 显式传以防默认变化
                    cfg = struct('numCandidates', 80);
                    utPos = twin.signal.terminal(this.Scenario, satObj, constellation, [], cfg);
                catch ME
                    fprintf('[Session2] %s sat#%d 终端搜索失败 (%s)，回退星下点\n', ...
                        constellation, i, ME.message);
                    [latArr, lonArr, ~] = states(satObj, this.Scenario.StartTime, ...
                        'CoordinateFrame', 'geographic');
                    utPos = [min(max(latArr(1), -89), 89), ...
                        mod(lonArr(1) + 180, 360) - 180, 0];
                end

                gs = groundStation(this.Scenario, utPos(1), utPos(2), ...
                    'Name', sprintf('%s-UT-%02d', constellation, i), ...
                    'MinElevationAngle', 5);
                this.(utField){i} = gs;

                [posTT, velTT] = twin.orbit.companion(this.Scenario, satObj, ...
                    this.CompanionOffset_km, 1);
                comp = satellite(this.Scenario, posTT, velTT, ...
                    'Name', sprintf('%s-Comp-%02d', constellation, i), ...
                    'CoordinateFrame', 'ecef');
                this.(compField){i} = comp;
                end
            end
            
        function path = autoFindDetector(this)
            path = '';
            projectRoot = this.projectRoot();
            roots = { ...
                fullfile(projectRoot, 'results', 'unified', 'detection'), ...
                fullfile(projectRoot, 'models', 'detection') ...
            };
            for k = 1:numel(roots)
                if ~exist(roots{k}, 'dir'), continue; end
                files = dir(fullfile(roots{k}, '**', 'detector.mat'));
                if isempty(files), continue; end
                [~, ord] = sort([files.datenum], 'descend');
                files = files(ord);
                path = fullfile(files(1).folder, files(1).name);
                return;
            end
        end

        function root = defaultDetectorRoot(this)
            root = fullfile(this.projectRoot(), 'results');
            if ~exist(root, 'dir'), root = this.projectRoot(); end
        end

        function summary = summarizeReceiver(this)
            summary = struct();
            try
                cfgSL = spectrumMonitorConfig('starlink');
                summary.bandwidth_Hz = cfgSL.broadband.sampling.bandwidth;
                summary.sampleRate_Hz = cfgSL.broadband.sampling.sampleRate;
                summary.centerFrequency_Hz = cfgSL.broadband.sampling.centerFrequency;
                summary.IQSampleLength = cfgSL.broadband.sampling.IQSampleLength;
                summary.duration_sec = cfgSL.broadband.sampling.duration;
                summary.companionSeparation_m = cfgSL.broadband.companion.separation;
                summary.systemNoiseTemp_K = cfgSL.broadband.receiver.systemNoiseTemp;
            catch ME
                summary.error = ME.message;
            end
            summary.companionOffset_km = this.CompanionOffset_km;
        end

        % ============================================================
        %   UI 状态辅助
        % ============================================================
        function setStepPending(this, idx)
            this.StepStatus(idx) = 0;
            btn = this.StepButtons{idx};
            btn.Enable = 'off';
            btn.BackgroundColor = [0.18 0.18 0.20];
            btn.FontColor = this.TextColor;
            btn.Text = this.formatStepText(idx, 'pending');
        end

        function setStepActive(this, idx)
            this.StepStatus(idx) = 1;
            this.CurrentStep = idx;
            btn = this.StepButtons{idx};
            btn.Text = this.formatStepText(idx, 'active');
            btn.BackgroundColor = this.ActiveColor;
            btn.FontColor = [0 0 0];
        end

        function setStepCompleted(this, idx)
            this.StepStatus(idx) = 2;
            btn = this.StepButtons{idx};
            btn.Text = this.formatStepText(idx, 'completed');
            btn.BackgroundColor = this.SuccessColor;
            btn.FontColor = [1 1 1];
            btn.Enable = 'off';
        end

        function enableStep(this, idx)
            btn = this.StepButtons{idx};
            btn.Enable = 'on';
            btn.BackgroundColor = this.AccentColor;
            btn.FontColor = [1 1 1];
            btn.Text = this.formatStepText(idx, 'enabled');
        end

        function updateStatus(this, msg)
            if ~isempty(this.StatusLabel)
                this.StatusLabel.Text = msg;
            end
        end

        function updateProgress(this, processed, total)
            if ~isempty(this.ProgressLabel)
                this.ProgressLabel.Text = sprintf('进度: %d / %d', processed, total);
            end
        end
    end

    % ============================================================
    %   Evaluator 私有实例方法（替代原 +session2/Evaluator.m）
    % ============================================================
    methods (Access = private)
        function evalInit(this)
            % 初始化评估器状态（在 step4 plan 构建之后调用）
            this.evalReset();
            cons = this.EvalConstellations;
            for k = 1:numel(cons)
                this.EvalSNRStats.(cons{k}) = struct( ...
                    'correct', zeros(1, this.Plan.NumSNR), ...
                    'total',   zeros(1, this.Plan.NumSNR));
                this.EvalDopplerStats.(cons{k}) = struct( ...
                    'correct', zeros(1, this.Plan.NumDoppler), ...
                    'total',   zeros(1, this.Plan.NumDoppler));
            end
        end

        function evalReset(this)
            this.EvalRecords = struct( ...
                'idx', {}, 'constellation', {}, 'satIdx', {}, 'channelIndex', {}, ...
                'snrIdx', {}, 'snr_set_dB', {}, 'snr_meas_dB', {}, ...
                'dopIdx', {}, 'doppler_set_Hz', {}, ...
                'pred_label', {}, 'top_score', {}, 'is_correct', {}, ...
                'detected', {}, 'numBoxes', {});
            this.EvalNumRecorded = 0;
            this.EvalSNRStats = struct();
            this.EvalDopplerStats = struct();
            this.EvalConfusion = zeros(2, 3);
        end

        function evalIngest(this, cellInfo, sample, detection)
            agg = twin.app.Session2TestFlowPanel.aggregateDetection( ...
                detection, cellInfo.constellation);
            isCorrect = strcmpi(agg.predLabel, cellInfo.constellation);

            r = struct();
            r.idx = cellInfo.idx;
            r.constellation = cellInfo.constellation;
            r.satIdx = cellInfo.satIdx;
            r.channelIndex = cellInfo.channelIndex;
            r.snrIdx = cellInfo.snrIdx;
            r.snr_set_dB = cellInfo.snr_dB;
            if isstruct(sample) && isfield(sample, 'meta') && ...
                    isfield(sample.meta, 'snr_meas_burst_dB')
                r.snr_meas_dB = sample.meta.snr_meas_burst_dB;
            else
                r.snr_meas_dB = NaN;
            end
            r.dopIdx = cellInfo.dopIdx;
            r.doppler_set_Hz = cellInfo.doppler_Hz;
            r.pred_label = agg.predLabel;
            r.top_score = agg.topScore;
            r.is_correct = isCorrect;
            r.detected = ~isempty(detection.bboxes);
            if isfield(detection, 'bboxes') && ~isempty(detection.bboxes)
                r.numBoxes = size(detection.bboxes, 1);
            else
                r.numBoxes = 0;
            end

            this.EvalNumRecorded = this.EvalNumRecorded + 1;
            this.EvalRecords(this.EvalNumRecorded) = r;

            con = cellInfo.constellation;
            this.EvalSNRStats.(con).total(cellInfo.snrIdx) = ...
                this.EvalSNRStats.(con).total(cellInfo.snrIdx) + 1;
            this.EvalDopplerStats.(con).total(cellInfo.dopIdx) = ...
                this.EvalDopplerStats.(con).total(cellInfo.dopIdx) + 1;
            if isCorrect
                this.EvalSNRStats.(con).correct(cellInfo.snrIdx) = ...
                    this.EvalSNRStats.(con).correct(cellInfo.snrIdx) + 1;
                this.EvalDopplerStats.(con).correct(cellInfo.dopIdx) = ...
                    this.EvalDopplerStats.(con).correct(cellInfo.dopIdx) + 1;
            end

            rowIdx = find(strcmpi(this.EvalConstellations, con), 1, 'first');
            switch lower(agg.predLabel)
                case 'starlink', colIdx = 1;
                case 'oneweb',   colIdx = 2;
                otherwise,       colIdx = 3;       % unknown / multiple → 异常
            end
            this.EvalConfusion(rowIdx, colIdx) = this.EvalConfusion(rowIdx, colIdx) + 1;
        end

        function snap = evalSnapshot(this)
            snap = struct();
            for k = 1:numel(this.EvalConstellations)
                con = this.EvalConstellations{k};
                tot = sum(this.EvalSNRStats.(con).total);
                cor = sum(this.EvalSNRStats.(con).correct);
                if tot > 0, snap.(con).accuracy = cor / tot * 100;
                else,       snap.(con).accuracy = NaN; end
                snap.(con).total = tot;
                snap.(con).correct = cor;
            end
            grandTotal = snap.starlink.total + snap.oneweb.total;
            grandCorrect = snap.starlink.correct + snap.oneweb.correct;
            if grandTotal > 0, snap.overall.accuracy = grandCorrect / grandTotal * 100;
            else,              snap.overall.accuracy = NaN; end
            snap.overall.total = grandTotal;
            snap.overall.correct = grandCorrect;
            snap.confusionMatrix = this.EvalConfusion;
            snap.numRecorded = this.EvalNumRecorded;
        end

        function metrics = evalFinalize(this)
            metrics = struct();
            metrics.constellations = this.EvalConstellations;
            metrics.snrGrid_dB = this.Plan.SNRGrid_dB;
            metrics.dopplerGrid_Hz = this.Plan.DopplerGrid_Hz;

            for k = 1:numel(this.EvalConstellations)
                con = this.EvalConstellations{k};
                metrics.snr.(con) = twin.app.Session2TestFlowPanel.statsWithCI( ...
                    this.EvalSNRStats.(con).correct, this.EvalSNRStats.(con).total);
                metrics.doppler.(con) = twin.app.Session2TestFlowPanel.statsWithCI( ...
                    this.EvalDopplerStats.(con).correct, this.EvalDopplerStats.(con).total);
            end

            cm = this.EvalConfusion;
            metrics.confusionMatrix = cm;
            for k = 1:numel(this.EvalConstellations)
                con = this.EvalConstellations{k};
                rowSum = sum(cm(k, :));
                if rowSum > 0
                    metrics.summary.(con).total = rowSum;
                    metrics.summary.(con).accuracy_pct = cm(k, k) / rowSum * 100;
                    other = 3 - k;  % 1->2, 2->1
                    metrics.summary.(con).misclassified_pct = cm(k, other) / rowSum * 100;
                    metrics.summary.(con).missed_pct = cm(k, 3) / rowSum * 100;
                else
                    metrics.summary.(con).total = 0;
                    metrics.summary.(con).accuracy_pct = NaN;
                    metrics.summary.(con).misclassified_pct = NaN;
                    metrics.summary.(con).missed_pct = NaN;
                    end
                end
            grandTotal = sum(cm(:));
            if grandTotal > 0
                metrics.summary.overall.total = grandTotal;
                metrics.summary.overall.accuracy_pct = (cm(1,1) + cm(2,2)) / grandTotal * 100;
            else
                metrics.summary.overall.total = 0;
                metrics.summary.overall.accuracy_pct = NaN;
            end

            metrics.records = this.EvalRecords(1:this.EvalNumRecorded);
        end
    end

    % ============================================================
    %   Plan / Generator / Reporter 静态实现（替代 +session2）
    % ============================================================
    methods (Static, Access = public)
        function plan = buildPlan(opts)
            % BUILDPLAN  生成测试矩阵: NumSat × NumSNR × NumDoppler × 2 颗星座
            %   opts 字段: NumSatellites, NumSNR, NumDoppler, SnrRange_dB,
            %              DopplerMaxStarlink_Hz, DopplerMaxOneweb_Hz, Seed
            if nargin < 1, opts = struct(); end
            if ~isfield(opts, 'NumSatellites'),         opts.NumSatellites = 30; end
            if ~isfield(opts, 'NumSNR'),                opts.NumSNR = 10; end
            if ~isfield(opts, 'NumDoppler'),            opts.NumDoppler = 10; end
            if ~isfield(opts, 'SnrRange_dB'),           opts.SnrRange_dB = [-10, 10]; end
            if ~isfield(opts, 'DopplerMaxStarlink_Hz'), opts.DopplerMaxStarlink_Hz = 360e3; end
            if ~isfield(opts, 'DopplerMaxOneweb_Hz'),   opts.DopplerMaxOneweb_Hz = 345e3; end
            if ~isfield(opts, 'Seed'),                  opts.Seed = 20260420; end

            plan = struct();
            plan.Constellations = {'starlink', 'oneweb'};
            plan.NumSatellites = opts.NumSatellites;
            plan.NumSNR = opts.NumSNR;
            plan.NumDoppler = opts.NumDoppler;
            plan.SnrRange_dB = opts.SnrRange_dB;
            plan.SNRGrid_dB = linspace(opts.SnrRange_dB(1), opts.SnrRange_dB(2), opts.NumSNR);
            plan.DopplerMax_Hz = struct( ...
                'starlink', opts.DopplerMaxStarlink_Hz, ...
                'oneweb',   opts.DopplerMaxOneweb_Hz);
            plan.DopplerGrid_Hz = struct( ...
                'starlink', linspace(-opts.DopplerMaxStarlink_Hz, opts.DopplerMaxStarlink_Hz, opts.NumDoppler), ...
                'oneweb',   linspace(-opts.DopplerMaxOneweb_Hz,   opts.DopplerMaxOneweb_Hz,   opts.NumDoppler));
            plan.BandwidthMode = struct('starlink', 'mode_60MHz', 'oneweb', 'mode_20MHz');
            plan.NumChannels = struct('starlink', 8, 'oneweb', 10);
            plan.Seed = opts.Seed;

            rng(opts.Seed, 'twister');
            n = numel(plan.Constellations) * opts.NumSatellites * opts.NumSNR * opts.NumDoppler;
            tmpl = struct('idx', 0, 'constellation', '', 'satIdx', 0, ...
                'snrIdx', 0, 'snr_dB', 0, 'dopIdx', 0, 'doppler_Hz', 0, ...
                'channelIndex', 0, 'bwMode', '', 'sampleSeed', 0);
            cells = repmat(tmpl, 1, n);

            k = 0;
            for ci = 1:numel(plan.Constellations)
                con = plan.Constellations{ci};
                bw = plan.BandwidthMode.(con);
                numCh = plan.NumChannels.(con);
                snrList = plan.SNRGrid_dB;
                dopList = plan.DopplerGrid_Hz.(con);
                for s = 1:opts.NumSatellites
                    for si = 1:opts.NumSNR
                        for di = 1:opts.NumDoppler
                            k = k + 1;
                            cells(k).idx = k;
                            cells(k).constellation = con;
                            cells(k).satIdx = s;
                            cells(k).snrIdx = si;
                            cells(k).snr_dB = snrList(si);
                            cells(k).dopIdx = di;
                            cells(k).doppler_Hz = dopList(di);
                            cells(k).channelIndex = randi(numCh);
                            cells(k).bwMode = bw;
                            cells(k).sampleSeed = opts.Seed + k;
                        end
                    end
                end
            end
            plan.Cells = cells;
            plan.TotalCells = n;
            plan.CellsPerConstellation = opts.NumSatellites * opts.NumSNR * opts.NumDoppler;
        end

        function sample = generateSample(constellation, terminalPos, commSatPos, ...
                monSatPos, monSatVel, simTime, channelIndex, snr_dB, doppler_Hz, varargin)
            % GENERATESAMPLE 生成单条 1.8e6 点 IQ + 640x640 STFT
            %   - 关闭 channelModel 内部噪声叠加
            %   - 强制 dopplerShift = doppler_Hz
            %   - 在 burst timeMask 区域按目标 SNR 反算 AWGN 注入
            %   - 可选 'ExtraNoise_dB': 在已注入噪声基础上再叠一层挑战噪声,
            %     使分类器实际看到的 SNR 比设定值低 ExtraNoise_dB
            opt = struct('Seed', [], 'ExtraNoise_dB', 0);
            for kk = 1:2:numel(varargin)
                opt.(varargin{kk}) = varargin{kk+1};
            end
            if ~isempty(opt.Seed), rng(opt.Seed, 'twister'); end
            extraNoise_dB = max(0, opt.ExtraNoise_dB);
            
            spectrumConfig = spectrumMonitorConfig(constellation);
            phyParams = constellationPhyConfig(constellation);
            switch lower(constellation)
                case 'starlink', bwMode = 'mode_60MHz';
                case 'oneweb',   bwMode = 'mode_20MHz';
                otherwise, error('twin:Session2:UnknownConstellation', '%s', constellation);
            end

            % --- 终端 + 发射 ---
            terminalProfile = twin.app.Session2TestFlowPanel.buildTerminalProfile( ...
                constellation, bwMode, terminalPos, commSatPos, channelIndex, phyParams);
            if ~terminalProfile.initialized
                error('twin:Session2:TerminalInitFailed', '%s ch=%d', constellation, channelIndex);
            end
            
            [txWaveform, txInfo, ~] = dataGen.link.transmit(terminalProfile, constellation, bwMode);
            txInfo.constellation = constellation;
            if ~isfield(txInfo, 'txPower') || isempty(txInfo.txPower)
                txInfo.txPower = terminalProfile.txTemplate.txPower;
            end
            
            % --- 信道传播（关闭噪声 + 注入指定 doppler） ---
            timeInstant = posixtime(simTime);
            options = struct('enableWidebandSampling', true);
            receiverCfg = dataGen.config.receiver(options, spectrumConfig);
            
            linkParams = struct();
            linkParams.constellation = txInfo.constellation;
            linkParams.utPosition = terminalProfile.utPos;
            linkParams.satPosition = monSatPos(:);
            linkParams.satVelocity = monSatVel(:);
            linkParams.commSatPosition = commSatPos(:);
            linkParams.frequency = txInfo.carrierFrequency;
            linkParams.bandwidth = txInfo.bandwidth;
            linkParams.sampleRate = txInfo.sampleRate;
            linkParams.txPower = txInfo.txPower;
            linkParams.weatherCond = 'clear';
            linkParams.verbose = false;
            linkParams.rxGain = receiverCfg.rxGain;
            linkParams.GT = receiverCfg.GT;
            if isfield(receiverCfg, 'polarization'), linkParams.polarization = receiverCfg.polarization; end
            if isfield(receiverCfg, 'noiseTemp'),    linkParams.noiseTemp = receiverCfg.noiseTemp; end
            linkParams.injectThermalNoise = false;
            linkParams.disableAGC = true;
            linkParams.enableDoppler = true;
            linkParams.dopplerShift = doppler_Hz;
            for fld = {'enableOffBoresightLoss','offBoresightLossMethod', ...
                       'manualOffBoresightLoss','enableSidelobeReception', ...
                       'sidelobeProbability','antennaPatternModel'}
                f = fld{1};
                if isfield(receiverCfg, f), linkParams.(f) = receiverCfg.(f); end
            end

            [rxWaveform, ~] = dataGen.link.propagate(txWaveform, linkParams, timeInstant);

            % --- 宽带接收 → IQ + 时域掩码 ---
            slotStartIdx = randi([1, round(spectrumConfig.broadband.sampling.IQSampleLength * 0.3)]);
            [iqData, timeMask] = dataGen.link.receive(rxWaveform, txInfo, ...
                spectrumConfig, slotStartIdx);

            % --- 按 burst SNR 注入 AWGN ---
            if isempty(timeMask) || ~any(timeMask)
                % 没有 timeMask 时退化处理：尝试按幅度阈值定位 burst
                threshold = max(abs(iqData)) * 0.01;
                timeMask = abs(iqData) > threshold;
                if ~any(timeMask)
                    timeMask = true(size(iqData));
                end
            end
            burstIdx = timeMask(:);
            noiseIdx = ~burstIdx;
            Ps_clean = mean(abs(iqData(burstIdx)).^2);     % 注噪前 burst 区的纯信号功率

            snrInfo = struct( ...
                'Ps_clean', 0, ...
                'Pn_target', 0, ...
                'snr_set_dB', snr_dB, ...
                'snr_meas_dB', NaN, ...
                'snr_meas_after_filter_dB', NaN, ...
                'noiseFloor_dB', NaN);

            if isfinite(Ps_clean) && Ps_clean > 0
                % 让分类器实际看到的 SNR 等于 (snr_dB - extraNoise_dB)
                effective_snr_dB = snr_dB - extraNoise_dB;
                Pn_target = Ps_clean / 10^(effective_snr_dB / 10);
                noiseStd = sqrt(Pn_target / 2);
                n = noiseStd * (randn(size(iqData)) + 1j * randn(size(iqData)));
                iqData = iqData + n;

                % 注噪声后立即测量 (burst+noise 区 vs 纯噪声区)
                Pburst_pre = mean(abs(iqData(burstIdx)).^2);
                if any(noiseIdx)
                    Pnoise_pre = mean(abs(iqData(noiseIdx)).^2);
                else
                    Pnoise_pre = Pn_target;
                end
                Ps_meas_pre = max(eps, Pburst_pre - Pnoise_pre);
                snrInfo.Ps_clean = Ps_clean;
                snrInfo.Pn_target = Pn_target;
                snrInfo.snr_meas_dB = 10 * log10(Ps_meas_pre / max(eps, Pnoise_pre));
            end

            % --- 接收机损伤 (LPF + DC 泄漏) + 归一化 ---
            iqData = twin.app.Session2TestFlowPanel.applyReceiverImpairments(iqData);
            p = mean(abs(iqData).^2);
            if p > 0, iqData = iqData * sqrt(1.0 / p); end

            % --- 后处理后的 SNR 实测（这是分类器真正看到的） ---
            if any(burstIdx) && any(noiseIdx)
                Pburst_post = mean(abs(iqData(burstIdx)).^2);
                Pnoise_post = mean(abs(iqData(noiseIdx)).^2);
                Ps_post = max(eps, Pburst_post - Pnoise_post);
                snrInfo.snr_meas_after_filter_dB = 10 * log10(Ps_post / max(eps, Pnoise_post));
                snrInfo.noiseFloor_dB = 10 * log10(max(eps, Pnoise_post));
            end

            % --- STFT ---
            stftImage = dataGen.io.spectrogram(iqData, [], spectrumConfig, [640, 640]);

            % --- 元数据 ---
            meta = struct();
            meta.constellation = constellation;
            meta.bwMode = bwMode;
            meta.channelIndex = channelIndex;
            meta.snr_set_dB = snr_dB;
            meta.snr_meas_burst_dB = snrInfo.snr_meas_after_filter_dB;  % 分类器实际看到的 SNR
            meta.snr_meas_pre_filter_dB = snrInfo.snr_meas_dB;
            meta.signalPower_burst = snrInfo.Ps_clean;
            meta.noisePower_injected = snrInfo.Pn_target;
            meta.noiseFloor_dB = snrInfo.noiseFloor_dB;
            meta.burstFraction = sum(burstIdx) / numel(iqData);
            meta.extraNoise_dB = extraNoise_dB;
            meta.snr_effective_dB = snr_dB - extraNoise_dB;
            meta.doppler_set_Hz = doppler_Hz;
            meta.doppler_applied_Hz = doppler_Hz;
            meta.terminalLLA = terminalProfile.utPos;
            meta.modulation = terminalProfile.modulation;
            meta.mcsIndex = terminalProfile.mcsIndex;
            meta.codeRate = terminalProfile.codeRate;
            meta.iqLength = numel(iqData);
            meta.imageSize = [640, 640];

            sample = struct();
            sample.constellation = constellation;
            sample.simTime = simTime;
            sample.iqData = iqData;
            sample.stftImage = stftImage;
            sample.meta = meta;
        end

        function agg = aggregateDetection(detection, gtClass)
            % AGGREGATEDETECTION 严格口径: 每条样本 GT 只有 1 个信号, 因此
            %   - 恰好 1 个 GT 类框 + 0 个其他类框 → 判该 GT 类 (correct)
            %   - 0 个框                          → 'unknown'  (漏检)
            %   - 多于 1 个同类框                 → 'multiple' (虚警/重复)
            %   - 至少有 1 个非 GT 类框           → 判最强非 GT 类
            % 这样多框 / 错类 / 漏检都不会被算作 100% 正确.
            agg.predLabel = 'unknown';
            agg.topScore = 0;
            agg.numStarBoxes = 0;
            agg.numOneBoxes = 0;

            if ~isfield(detection, 'labels') || isempty(detection.labels), return; end

            labels = detection.labels;
            if iscategorical(labels), labels = cellstr(labels);
            elseif isstring(labels), labels = cellstr(labels);
            elseif ischar(labels),   labels = {labels};
            end
            scores = [];
            if isfield(detection, 'scores') && ~isempty(detection.scores)
                scores = detection.scores(:)';
            end
            if numel(scores) < numel(labels), scores(end+1:numel(labels)) = 0; end

            isStar = contains(string(labels), 'starlink', 'IgnoreCase', true);
            isOne  = contains(string(labels), 'oneweb',   'IgnoreCase', true);
            nStar = sum(isStar);
            nOne  = sum(isOne);
            agg.numStarBoxes = nStar;
            agg.numOneBoxes  = nOne;

            sStar = 0; if nStar > 0, sStar = max(scores(isStar)); end
            sOne  = 0; if nOne  > 0, sOne  = max(scores(isOne));  end

            switch lower(gtClass)
                case 'starlink'
                    if nStar == 1 && nOne == 0
                        agg.predLabel = 'starlink'; agg.topScore = sStar;
                    elseif nOne >= 1                              % 出现错类
                        agg.predLabel = 'oneweb';   agg.topScore = sOne;
                    elseif nStar > 1                              % 多检 (虚警)
                        agg.predLabel = 'multiple'; agg.topScore = sStar;
                    else                                          % 漏检
                        agg.predLabel = 'unknown';
                    end
                case 'oneweb'
                    if nOne == 1 && nStar == 0
                        agg.predLabel = 'oneweb';   agg.topScore = sOne;
                    elseif nStar >= 1
                        agg.predLabel = 'starlink'; agg.topScore = sStar;
                    elseif nOne > 1
                        agg.predLabel = 'multiple'; agg.topScore = sOne;
                    else
                        agg.predLabel = 'unknown';
                    end
                otherwise
                    if ~isempty(scores), agg.topScore = max(scores); end
                end
            end
            
        function paths = exportReport(plan, metrics, varargin)
            % EXPORTREPORT 一次性写出 manifest/csv/mat/png 到 results/session2/<runTag>/
            opt = struct('OutputRoot', '', 'RunTag', '', ...
                'DetectorPath', '', 'ReceiverSummary', struct(), 'ExtraNotes', struct());
            for kk = 1:2:numel(varargin)
                opt.(varargin{kk}) = varargin{kk+1};
            end
            if isempty(opt.OutputRoot)
                opt.OutputRoot = fullfile(twin.app.Session2TestFlowPanel.projectRoot(), ...
                    'results', 'session2');
            end
            if isempty(opt.RunTag)
                opt.RunTag = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            end
            outputDir = fullfile(opt.OutputRoot, opt.RunTag);
            if ~exist(outputDir, 'dir'), mkdir(outputDir); end

            paths = struct();
            paths.outputDir = outputDir;
            paths.runTag = opt.RunTag;
            paths.manifest = twin.app.Session2TestFlowPanel.writeManifest( ...
                outputDir, opt.RunTag, plan, opt.DetectorPath, opt.ReceiverSummary, opt.ExtraNotes);
            paths.samplesCsv = twin.app.Session2TestFlowPanel.writeSamplesCsv(outputDir, metrics);
            paths.metricsMat = twin.app.Session2TestFlowPanel.writeMetricsMat(outputDir, plan, metrics);
            paths.accSnrFig = twin.app.Session2TestFlowPanel.plotAccVsSNR(outputDir, metrics);
            paths.accDopFig = twin.app.Session2TestFlowPanel.plotAccVsDoppler(outputDir, metrics);
            paths.confusionFig = twin.app.Session2TestFlowPanel.plotConfusion(outputDir, metrics);
        end
    end

    % ============================================================
    %   私有静态辅助方法
    % ============================================================
    methods (Static, Access = private)
        function root = projectRoot()
            % which 在静态方法里始终返回 classdef 文件的完整路径
            classFile = which('twin.app.Session2TestFlowPanel');
            here = fileparts(classFile);  % .../cssa/+twin/+app
            root = fileparts(fileparts(fileparts(here)));
        end

        function profile = buildTerminalProfile(constellation, bwMode, terminalPos, ...
                commSatPos, channelIndex, phyParams)
            profile = struct('initialized', false);
            if ~isfield(phyParams.channelization.modes, bwMode), return; end
            modeParams = phyParams.channelization.modes.(bwMode);
            
            utPosLLA = terminalPos(:)';
            try
            [elevation, ~, ~] = calculateLinkGeometry(utPosLLA, commSatPos);
            catch
                elevation = NaN;
            end
            if isfinite(elevation) && elevation < 5
                warning('twin:Session2:LowElevation', '终端仰角 %.1f° 偏低', elevation);
            end

            if isfield(phyParams, 'mcsTable') && ~isempty(phyParams.mcsTable)
                mcsTable = phyParams.mcsTable;
                mcsIdx = randi([max(1, size(mcsTable, 1) - 1), size(mcsTable, 1)]);
                modOrder = mcsTable(mcsIdx, 2);
                codeRate = mcsTable(mcsIdx, 3);
                switch modOrder
                    case 2,  modulation = 'BPSK';
                    case 4,  modulation = 'QPSK';
                    case 16, modulation = '16QAM';
                    case 64, modulation = '64QAM';
                    otherwise, modulation = 'QPSK';
                end
            else
                mcsIdx = 1; modulation = 'QPSK'; codeRate = 0.5;
            end
            
            txTemplate = dataGen.signal.txParams(constellation, modeParams);
            txTemplate.modulation = modulation;
            txTemplate.codeRate = codeRate;
            txTemplate.mcsIndex = mcsIdx;
            txTemplate.channelIndex = max(1, min(channelIndex, modeParams.numChannels));
            txTemplate.bandwidthMode = bwMode;
            if ~isfield(txTemplate, 'txPower') || isempty(txTemplate.txPower)
                txTemplate.txPower = 1.0;
            end
            if isfield(phyParams.waveform, 'payloadBitsRange')
                rangeStruct = phyParams.waveform.payloadBitsRange;
                if isfield(rangeStruct, bwMode)
                    txTemplate.numInfoBits = randi(rangeStruct.(bwMode));
                else
                    txTemplate.numInfoBits = 20000;
                end
            else
                txTemplate.numInfoBits = 20000;
            end
            
            rfMeta = struct( ...
                'phaseNoise', 0, 'frequencyOffset', 0, 'dcOffset', 0, ...
                'iqImbalance', struct('amplitudeImbalance', 0, 'phaseImbalance', 0), ...
                'paModel', [], ...
                'id', sprintf('%s_s2_%d', constellation, randi(1e6)), ...
                'type', 'session2');
            
            profile.initialized = true;
            profile.utPos = utPosLLA;
            profile.modeKey = bwMode;
            profile.mcsIndex = mcsIdx;
            profile.modulation = modulation;
            profile.codeRate = codeRate;
            profile.txTemplate = txTemplate;
            profile.rfMeta = rfMeta;
            profile.tid = rfMeta.id;
            profile.txPowerBackoff_dB = 0;
            profile.fingerprintCategory = 'session2';
            profile.elevation_deg = elevation;
        end

        function iqOut = applyReceiverImpairments(iqIn)
            % 500MHz 双边带 LPF + DC/LO 泄漏（与训练数据一致）
            iqOut = iqIn;
            N = numel(iqIn);
            if N <= 0, return; end
            passbandNorm = 0.85;
            transitionNorm = 0.05;
            stopbandAtten_dB = 50;

            X = fft(iqIn);
            freqAxis = (0:N-1)' / N;
            freqAxis(freqAxis >= 0.5) = freqAxis(freqAxis >= 0.5) - 1;
            freqAxis = abs(freqAxis) * 2;

            H = ones(N, 1);
            stopbandNorm = passbandNorm + transitionNorm;
            stopbandGain = 10^(-stopbandAtten_dB / 20);
            transitionMask = (freqAxis > passbandNorm) & (freqAxis <= stopbandNorm);
            if any(transitionMask)
                t = (freqAxis(transitionMask) - passbandNorm) / transitionNorm;
                H(transitionMask) = 0.5 * (1 + cos(pi * t));
            end
            H(freqAxis > stopbandNorm) = stopbandGain;

            X = X .* H;
            iqOut = ifft(X);

            signalRMS = sqrt(mean(abs(iqOut).^2));
            if isfinite(signalRMS) && signalRMS > 0
                dcRatio = 0.03 + rand() * 0.05;
                dcScale = 0.8 + 0.4 * rand();
                dcI = signalRMS * dcRatio * (-1) * dcScale;
                dcQ = signalRMS * dcRatio * (-1) * dcScale;
                iqOut = iqOut + complex(dcI, dcQ);
            end
        end

        function out = statsWithCI(correctVec, totalVec)
            % 返回 accuracy/CI low/high (per cell)
            n = numel(totalVec);
            acc = nan(1, n); lo = nan(1, n); hi = nan(1, n);
            for i = 1:n
                if totalVec(i) > 0
                    [acc(i), lo(i), hi(i)] = twin.app.Session2TestFlowPanel.wilsonInterval( ...
                        correctVec(i), totalVec(i));
                end
            end
            out = struct('correct', correctVec, 'total', totalVec, ...
                'accuracy_pct', acc * 100, ...
                'ci_low_pct', lo * 100, 'ci_high_pct', hi * 100);
        end

        function [p, lo, hi] = wilsonInterval(k, n)
            if n == 0, p = NaN; lo = NaN; hi = NaN; return; end
            z = 1.959963984540054;
            phat = k / n;
            denom = 1 + z^2 / n;
            center = (phat + z^2 / (2*n)) / denom;
            margin = (z * sqrt(phat*(1-phat)/n + z^2/(4*n^2))) / denom;
            p = phat;
            lo = max(0, center - margin);
            hi = min(1, center + margin);
        end

        function fp = writeManifest(outputDir, runTag, plan, detectorPath, recv, extra)
            fp = fullfile(outputDir, 'dataset_manifest.json');
            doc = struct();
            doc.runTag = runTag;
            doc.generatedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            doc.plan = struct( ...
                'constellations', {plan.Constellations}, ...
                'numSatellitesPerConstellation', plan.NumSatellites, ...
                'snrGrid_dB', plan.SNRGrid_dB, ...
                'dopplerGrid_Hz', plan.DopplerGrid_Hz, ...
                'bandwidthMode', plan.BandwidthMode, ...
                'numChannels', plan.NumChannels, ...
                'totalCells', plan.TotalCells, ...
                'cellsPerConstellation', plan.CellsPerConstellation, ...
                'seed', plan.Seed);
            doc.receiver = recv;
            doc.detectorPath = detectorPath;
            doc.notes = extra;
            txt = jsonencode(doc, 'PrettyPrint', true);
            fid = fopen(fp, 'w');
            if fid < 0, error('twin:Session2:WriteFail', '%s', fp); end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
        end

        function fp = writeSamplesCsv(outputDir, metrics)
            fp = fullfile(outputDir, 'samples_index.csv');
            recs = metrics.records;
            n = numel(recs);
            header = strjoin({'idx','constellation','satIdx','channelIndex', ...
                'snrIdx','snr_set_dB','snr_meas_dB', ...
                'dopIdx','doppler_set_Hz', ...
                'pred_label','top_score','is_correct','detected','numBoxes'}, ',');
            fid = fopen(fp, 'w');
            if fid < 0, error('twin:Session2:WriteFail', '%s', fp); end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '%s\n', header);
            for i = 1:n
                r = recs(i);
                fprintf(fid, '%d,%s,%d,%d,%d,%.6f,%.6f,%d,%.3f,%s,%.6f,%d,%d,%d\n', ...
                    r.idx, r.constellation, r.satIdx, r.channelIndex, ...
                    r.snrIdx, r.snr_set_dB, r.snr_meas_dB, ...
                    r.dopIdx, r.doppler_set_Hz, ...
                    r.pred_label, r.top_score, r.is_correct, r.detected, r.numBoxes);
            end
        end

        function fp = writeMetricsMat(outputDir, plan, metrics) %#ok<INUSL>
            fp = fullfile(outputDir, 'metrics.mat');
            planSummary = struct( ...
                'constellations', {plan.Constellations}, ...
                'numSatellitesPerConstellation', plan.NumSatellites, ...
                'snrGrid_dB', plan.SNRGrid_dB, ...
                'dopplerGrid_Hz', plan.DopplerGrid_Hz, ...
                'totalCells', plan.TotalCells, ...
                'seed', plan.Seed); %#ok<NASGU>
            save(fp, 'metrics', 'planSummary', '-v7');
        end

        function fp = plotAccVsSNR(outputDir, metrics)
            fp = fullfile(outputDir, 'acc_vs_snr.png');
            fig = figure('Visible', 'off', 'Position', [100 100 900 520], 'Color', 'white');
            ax = axes(fig); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
            colors = struct('starlink', [1.0 0.45 0.0], 'oneweb', [0.0 0.55 0.85]);
            cons = fieldnames(metrics.snr);
            for k = 1:numel(cons)
                con = cons{k};
                acc = metrics.snr.(con).accuracy_pct;
                lo = metrics.snr.(con).ci_low_pct;
                hi = metrics.snr.(con).ci_high_pct;
                snr = metrics.snrGrid_dB;
                negErr = max(0, acc - lo);
                posErr = max(0, hi - acc);
                errorbar(ax, snr, acc, negErr, posErr, 'o-', ...
                    'Color', colors.(con), 'MarkerFaceColor', colors.(con), ...
                    'LineWidth', 1.6, 'MarkerSize', 6, 'CapSize', 6, 'DisplayName', con);
            end
            yline(ax, 90, '--', '指标基线 90%', 'Color', [0.4 0.4 0.4], ...
                'LineWidth', 1.0, 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
            ylim(ax, [50, 102]);
            xlabel(ax, 'SNR (dB)'); ylabel(ax, '识别准确率 (%)');
            title(ax, '典型终端识别准确率 - SNR 扫描 (95% Wilson CI)');
            legend(ax, 'Location', 'southeast');
            exportgraphics(fig, fp, 'Resolution', 200);
            close(fig);
        end

        function fp = plotAccVsDoppler(outputDir, metrics)
            fp = fullfile(outputDir, 'acc_vs_doppler.png');
            fig = figure('Visible', 'off', 'Position', [100 100 1100 520], 'Color', 'white');
            cons = fieldnames(metrics.doppler);
            colors = struct('starlink', [1.0 0.45 0.0], 'oneweb', [0.0 0.55 0.85]);
            for k = 1:numel(cons)
                con = cons{k};
                ax = subplot(1, numel(cons), k, 'Parent', fig);
                hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
                acc = metrics.doppler.(con).accuracy_pct;
                lo = metrics.doppler.(con).ci_low_pct;
                hi = metrics.doppler.(con).ci_high_pct;
                dop_kHz = metrics.dopplerGrid_Hz.(con) / 1e3;
                negErr = max(0, acc - lo);
                posErr = max(0, hi - acc);
                errorbar(ax, dop_kHz, acc, negErr, posErr, 'o-', ...
                    'Color', colors.(con), 'MarkerFaceColor', colors.(con), ...
                    'LineWidth', 1.6, 'MarkerSize', 6, 'CapSize', 6);
                yline(ax, 90, '--', '90%', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.0);
                ylim(ax, [50, 102]);
                xlabel(ax, '多普勒频偏 (kHz)');
                ylabel(ax, '识别准确率 (%)');
                title(ax, sprintf('%s 识别准确率 - 多普勒扫描', con));
            end
            sgtitle(fig, '典型终端识别准确率随多普勒频偏变化曲线');
            exportgraphics(fig, fp, 'Resolution', 200);
            close(fig);
        end

        function fp = plotConfusion(outputDir, metrics)
            fp = fullfile(outputDir, 'confusion_matrix.png');
            fig = figure('Visible', 'off', 'Position', [100 100 700 520], 'Color', 'white');
            ax = axes(fig); hold(ax, 'on');
            cm = metrics.confusionMatrix;
            colNames = {'Starlink', 'OneWeb', '漏检/多检'};
            rowNames = {'Starlink', 'OneWeb'};
            cmPct = zeros(size(cm));
            for r = 1:size(cm, 1)
                rs = sum(cm(r, :));
                if rs > 0, cmPct(r, :) = cm(r, :) / rs * 100; end
            end
            imagesc(ax, cmPct);
            colormap(ax, parula);
            cb = colorbar(ax); cb.Label.String = '行归一化百分比 (%)';
            caxis(ax, [0, 100]);
            ax.XTick = 1:size(cm, 2); ax.YTick = 1:size(cm, 1);
            ax.XTickLabel = colNames; ax.YTickLabel = rowNames;
            xlabel(ax, '预测类别'); ylabel(ax, '真实类别');
            title(ax, '识别混淆矩阵 (行=真实, 列=预测)');
            for r = 1:size(cm, 1)
                for c = 1:size(cm, 2)
                    txt = sprintf('%d\n(%.1f%%)', cm(r, c), cmPct(r, c));
                    if cmPct(r, c) > 50, col = [0 0 0]; else, col = [1 1 1]; end
                    text(ax, c, r, txt, ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                        'Color', col, 'FontSize', 11, 'FontWeight', 'bold');
                end
            end
            axis(ax, 'image'); ax.Box = 'on';
            exportgraphics(fig, fp, 'Resolution', 200);
            close(fig);
        end
    end
end
