classdef TestFlowPanel < matlabshared.application.Component
    % TESTFLOWPANEL 多种信号体制识别 - 会话1 测试流程面板
    %
    %   精简后 6 步固定流程（取代旧的 18 步流程）：
    %     1. 创建场景 + 加载 Starlink+OneWeb 卫星
    %     2. 部署 Starlink/OneWeb 终端 + 伴飞卫星 (共享一个偏移滑块)
    %     3. 生成并显示 Starlink 监测信号 (链路 + 宽带 IQ + STFT)
    %     4. 生成并显示 OneWeb 监测信号
    %     5. 加载 YOLOX 检测模型并完成推理
    %     6. 输出感知结果 (在右下结果面板可视化)
    
    properties (Hidden)
        MainGrid
        StepButtons
        StepLabels
        StepStatus
        ProgressBar
        StatusLabel
        
        % 步骤定义（精简为 6 步）
        StepNames = {
            '创建场景 + 加载 Starlink/OneWeb 卫星'
            '部署终端 + 伴飞卫星 (共享偏移)'
            '生成并显示 Starlink 监测信号'
            '生成并显示 OneWeb 监测信号'
            '加载感知模型 + 完成推理'
            '输出感知结果'
        }
        StepIO = {
            '输入: TLE/starlink + TLE/oneweb    输出: scenario + 2 颗 satellite'
            '输入: 主卫星 + 偏移 km             输出: 2 个 groundStation + 2 个 companion satellite'
            '输入: Starlink 链路, simTime         输出: 1.8e6 点 IQ + 640x640 STFT'
            '输入: OneWeb 链路, simTime           输出: 1.8e6 点 IQ + 640x640 STFT'
            '输入: detector.mat + 两幅 STFT      输出: bbox/labels/scores'
            '输入: 检测结果 + 原 STFT            输出: 渲染至 Session1Result 面板'
        }
        
        % 状态
        CurrentStep = 0
        CompletedSteps = []
        
        % 场景对象
        Scenario
        StarlinkSatellite
        StarlinkCompanion
        OnewebSatellite
        OnewebCompanion
        
        % 地面终端
        StarlinkTerminal          % Starlink 地面终端
        OnewebTerminal            % OneWeb 地面终端
        
        % 通信链路
        StarlinkCommAccess        % 终端到通信卫星链路
        StarlinkMonitorAccess     % 终端到伴飞卫星链路
        OnewebCommAccess          % 终端到通信卫星链路
        OnewebMonitorAccess       % 终端到伴飞卫星链路
        
        % 偏移距离配置
        StarlinkOffset = 5  % km
        OnewebOffset = 5    % km
        
        % 滑块控件
        StarlinkOffsetSlider
        StarlinkOffsetLabel
        OnewebOffsetSlider
        OnewebOffsetLabel
        
        % 信号数据
        StarlinkSignalIQ          % Starlink 宽带 IQ 数据
        StarlinkSignalImage       % Starlink STFT 图像
        OnewebSignalIQ            % OneWeb 宽带 IQ 数据
        OnewebSignalImage         % OneWeb STFT 图像
        
        % 检测模型
        DetectionModel
        DetectionThreshold = 0.35  % 默认检测置信度阈值
        StarlinkDetectionResult    % 存储 Starlink 推理结果
        OnewebDetectionResult      % 存储 OneWeb 推理结果
        
        % 颜色配置
        BgColor = [0.10 0.10 0.12]
        TextColor = [0.85 0.85 0.85]
        AccentColor = [0.3 0.8 1.0]
        SuccessColor = [0.3 0.9 0.4]
        PendingColor = [0.5 0.5 0.5]
        ActiveColor = [1.0 0.8 0.2]
    end
    
    events
        StepCompleted
        AllStepsCompleted
        SignalImageReady
    end
    
    methods
        function this = TestFlowPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
            n = numel(this.StepNames);
            this.StepButtons = cell(n, 1);
            this.StepLabels = cell(n, 1);
            this.StepStatus = zeros(n, 1);  % 0=pending, 1=active, 2=completed
        end
        
        function name = getName(~)
            name = '测试流程';
        end
        
        function tag = getTag(~)
            tag = 'testflow';
        end
        
        function update(this)
            createUI(this);
        end
        
        function createUI(this)
            % 创建测试流程界面
            clf(this.Figure);
            this.Figure.Color = this.BgColor;

            % 主布局 (与会话 2 一致): 标题 / 参数区 / 步骤区 / 状态条 / 控制区
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
                'Text', '多种信号体制识别 — 测试流程 (会话 1)', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', this.AccentColor, ...
                'BackgroundColor', [0.15 0.15 0.18]);

            % ---- 参数区 (步骤 2 共享伴飞偏移) ----
            this.buildConfigArea(this.MainGrid);

            % ---- 步骤按钮区 (整行可点击, 无单独触发列) ----
            stepsPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', this.BgColor, 'BorderType', 'none');
            n = numel(this.StepNames);
            stepsLayout = uigridlayout(stepsPanel, [n, 1]);
            stepsLayout.RowHeight = repmat({'1x'}, 1, n);
            stepsLayout.Padding = [0 0 0 0];
            stepsLayout.RowSpacing = 4;
            stepsLayout.BackgroundColor = this.BgColor;

            for i = 1:n
                this.createStepButton(stepsLayout, i);
            end

            % ---- 状态条 ----
            statusPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.12 0.12 0.14], 'BorderType', 'none');
            sl = uigridlayout(statusPanel, [1, 1]);
            sl.Padding = [10 1 10 1];
            sl.BackgroundColor = [0.12 0.12 0.14];
            this.StatusLabel = uilabel(sl, ...
                'Text', '准备就绪 — 点击下方任意步骤即可执行', ...
                'FontSize', 11, 'FontColor', this.TextColor, ...
                'BackgroundColor', [0.12 0.12 0.14]);

            % ---- 控制按钮 (与会话 2 同 4 键: ▶ 自动 / ⏭ 单步 / ⏹ 停止 / ↺ 重置) ----
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
            % 顶部参数区: 步骤 2 共享伴飞偏移 (Starlink/OneWeb 同值)
            cfgPanel = uipanel(parent, ...
                'Title', '参数 (步骤 2 伴飞偏移, Starlink/OneWeb 共享)', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', [0.55 0.55 0.55], ...
                'FontSize', 10, ...
                'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            grid = uigridlayout(cfgPanel, [1, 3]);
            grid.ColumnWidth = {'fit', 110, 60};
            grid.ColumnSpacing = 6;
            grid.Padding = [8 4 8 4];
            grid.BackgroundColor = this.BgColor;

            uilabel(grid, 'Text', '伴飞偏移:', 'FontSize', 10, ...
                'FontColor', [0.7 0.7 0.7], ...
                'BackgroundColor', this.BgColor);
            slider = uislider(grid, ...
                'Limits', [0 30], 'Value', this.StarlinkOffset, ...
                'MajorTicks', [], 'MinorTicks', [], ...
                'ValueChangedFcn', @(src,~) this.onSharedOffsetChanged(src.Value));
            lbl = uilabel(grid, ...
                'Text', sprintf('%d km', this.StarlinkOffset), ...
                'FontSize', 10, 'FontColor', this.AccentColor, ...
                'BackgroundColor', this.BgColor);
            this.StarlinkOffsetSlider = slider;
            this.StarlinkOffsetLabel = lbl;
            this.OnewebOffsetSlider = slider;
            this.OnewebOffsetLabel = lbl;
        end

        function createStepButton(this, parent, idx)
            % 整行 button (与会话 2 同款): 行 1 = 编号 + 步骤名, 行 2 = 输入/输出说明
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

        function onSharedOffsetChanged(this, value)
            value = round(value);
            this.StarlinkOffset = value;
            this.OnewebOffset = value;
            if ~isempty(this.StarlinkOffsetLabel)
                this.StarlinkOffsetLabel.Text = sprintf('%d km', value);
            end
        end

        function stopTest(this)
            % 会话 1 不存在批量 timer; 仅把状态条恢复为「停止」, 不打断当前 step
            this.updateStatus('已请求停止 (单步执行不可中断, 仅清空状态条)');
        end
        
        function executeStep(this, stepIdx)
            % 执行指定步骤
            if stepIdx > 1 && this.StepStatus(stepIdx - 1) ~= 2
                this.updateStatus(sprintf('请先完成步骤 %d', stepIdx - 1));
                return;
            end
            
            this.setStepActive(stepIdx);
            this.updateStatus(sprintf('正在运行: %s', this.StepNames{stepIdx}));
            drawnow;
            
            try
                switch stepIdx
                    case 1, this.step1_CreateAndLoad();
                    case 2, this.step2_DeployTerminalsCompanions();
                    case 3, this.step3_GenerateStarlinkSignal();
                    case 4, this.step4_GenerateOnewebSignal();
                    case 5, this.step5_LoadModelAndInfer();
                    case 6, this.step6_OutputResults();
                end
                
                this.setStepCompleted(stepIdx);
                this.updateStatus(sprintf('完成: %s', this.StepNames{stepIdx}));
                
                if stepIdx < numel(this.StepNames)
                    this.enableStep(stepIdx + 1);
                else
                    this.updateStatus('所有步骤已完成！');
                    notify(this, 'AllStepsCompleted');
                end
                notify(this, 'StepCompleted');
            catch ME
                this.updateStatus(sprintf('错误: %s', ME.message));
                this.setStepActive(stepIdx);
            end
        end
        
        function runNextStep(this)
            nextStep = find(this.StepStatus ~= 2, 1, 'first');
            if ~isempty(nextStep)
                this.executeStep(nextStep);
            end
        end
        
        function runAllSteps(this)
            for i = 1:numel(this.StepNames)
                if this.StepStatus(i) ~= 2
                    this.executeStep(i);
                    pause(0.2);
                    drawnow;
                end
            end
        end
        
        function resetSteps(this)
            this.CurrentStep = 0;
            this.StepStatus = zeros(numel(this.StepNames), 1);
            
            % 清除场景视图
            if ~isempty(this.Application) && isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.clearViewer();
            end
            
            % 清理场景对象
            if ~isempty(this.Scenario) && isvalid(this.Scenario)
                delete(this.Scenario);
            end
            this.Scenario = [];
            this.StarlinkSatellite = [];
            this.StarlinkCompanion = [];
            this.OnewebSatellite = [];
            this.OnewebCompanion = [];
            this.StarlinkTerminal = [];
            this.OnewebTerminal = [];
            this.StarlinkCommAccess = [];
            this.StarlinkMonitorAccess = [];
            this.OnewebCommAccess = [];
            this.OnewebMonitorAccess = [];
            this.StarlinkSignalIQ = [];
            this.StarlinkSignalImage = [];
            this.OnewebSignalIQ = [];
            this.OnewebSignalImage = [];
            this.DetectionModel = [];
            this.StarlinkDetectionResult = [];
            this.OnewebDetectionResult = [];
            
            % 重置结果面板
            if ~isempty(this.Application) && isprop(this.Application, 'Session1Result')
                resultPanel = this.Application.Session1Result;
                if ~isempty(resultPanel) && ismethod(resultPanel, 'reset')
                    resultPanel.reset();
                end
            end
            
            % 重置UI
            for i = 1:numel(this.StepNames)
                this.setStepPending(i);
            end
            this.enableStep(1);
            this.updateStatus('已重置，等待开始...');
        end
        
        %% ==================== 6 步精简实现 ====================
        
        function step1_CreateAndLoad(this)
            % 创建仿真场景 + 加载 Starlink + OneWeb 卫星
            startTime = datetime('now', 'TimeZone', 'UTC');
            stopTime = startTime + minutes(1);
            this.Scenario = satelliteScenario(startTime, stopTime, 1);
            if isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.createViewer(this.Scenario);
            end
            fprintf('[场景] %s 至 %s\n', datestr(startTime, 31), datestr(stopTime, 31));
            
            this.StarlinkSatellite = this.loadOneRandomSat('starlink', ...
                {6921000, 0.0001, 53, 0, 0, 0, 'Name', 'Starlink-默认', ...
                 'OrbitPropagator', 'two-body-keplerian'});
            this.OnewebSatellite = this.loadOneRandomSat('oneweb', ...
                {7571000, 0.0001, 87.9, 45, 0, 0, 'Name', 'OneWeb-默认', ...
                 'OrbitPropagator', 'two-body-keplerian'});
            fprintf('已加载 Starlink + OneWeb 通信卫星\n');
        end
        
        function step2_DeployTerminalsCompanions(this)
            % 部署 Starlink + OneWeb 终端 + 各自伴飞卫星 (共享偏移)
            if isempty(this.StarlinkSatellite) || isempty(this.OnewebSatellite)
                error('请先加载卫星');
            end
            if ~isempty(this.StarlinkOffsetSlider)
                this.StarlinkOffset = round(this.StarlinkOffsetSlider.Value);
                this.OnewebOffset = this.StarlinkOffset;
            end
            
            this.StarlinkTerminal = this.addTerminalForSat(this.StarlinkSatellite, 'starlink', 'Starlink-终端');
            [posTT, velTT] = twin.orbit.companion(this.Scenario, this.StarlinkSatellite, this.StarlinkOffset, 1);
            this.StarlinkCompanion = satellite(this.Scenario, posTT, velTT, ...
                'Name', sprintf('Starlink-Companion (%dkm)', this.StarlinkOffset), ...
                'CoordinateFrame', 'ecef');
            
            this.OnewebTerminal = this.addTerminalForSat(this.OnewebSatellite, 'oneweb', 'OneWeb-终端');
            [posTT, velTT] = twin.orbit.companion(this.Scenario, this.OnewebSatellite, this.OnewebOffset, 1);
            this.OnewebCompanion = satellite(this.Scenario, posTT, velTT, ...
                'Name', sprintf('OneWeb-Companion (%dkm)', this.OnewebOffset), ...
                'CoordinateFrame', 'ecef');
            
            % 同步建立通信/监测链路
            this.StarlinkCommAccess = access(this.StarlinkTerminal, this.StarlinkSatellite);
            this.StarlinkMonitorAccess = access(this.StarlinkTerminal, this.StarlinkCompanion);
            this.OnewebCommAccess = access(this.OnewebTerminal, this.OnewebSatellite);
            this.OnewebMonitorAccess = access(this.OnewebTerminal, this.OnewebCompanion);
            
            fprintf('已部署 Starlink/OneWeb 终端 + 伴飞卫星 (偏移=%d km)\n', this.StarlinkOffset);
        end
        
        function step3_GenerateStarlinkSignal(this)
            [this.StarlinkSignalIQ, this.StarlinkSignalImage] = ...
                this.generateAndDisplay('starlink', 'mode_60MHz', ...
                    this.StarlinkTerminal, this.StarlinkSatellite, this.StarlinkCompanion);
            notify(this, 'SignalImageReady');
        end
        
        function step4_GenerateOnewebSignal(this)
            [this.OnewebSignalIQ, this.OnewebSignalImage] = ...
                this.generateAndDisplay('oneweb', 'mode_20MHz', ...
                    this.OnewebTerminal, this.OnewebSatellite, this.OnewebCompanion);
            notify(this, 'SignalImageReady');
        end
        
        function step5_LoadModelAndInfer(this)
            % 加载 detector.mat + 对两幅 STFT 各跑一次推理
            if isempty(this.StarlinkSignalImage) || isempty(this.OnewebSignalImage)
                error('请先完成步骤 3 / 4 生成监测信号');
            end
            this.loadDetectorAuto();
            this.updateStatus('正在运行感知模型推理...');
            drawnow;
            this.StarlinkDetectionResult = this.runDetectionForImage(this.StarlinkSignalImage, 'Starlink');
            this.OnewebDetectionResult   = this.runDetectionForImage(this.OnewebSignalImage,   'OneWeb');
            fprintf('感知推理完成: Starlink=%d 框, OneWeb=%d 框\n', ...
                size(this.StarlinkDetectionResult.bboxes, 1), ...
                size(this.OnewebDetectionResult.bboxes, 1));
        end
        
        function step6_OutputResults(this)
            % 把检测结果渲染到 Session1Result 面板
            if isempty(this.Application) || ~isprop(this.Application, 'Session1Result')
                warning('未找到 Session1Result 面板'); return;
            end
            resultPanel = this.Application.Session1Result;
            if isempty(resultPanel), return; end
            if ~isempty(this.StarlinkDetectionResult)
                resultPanel.displayStarlinkDetection( ...
                    this.StarlinkDetectionResult.overlayImage, [], {}, []);
            end
            if ~isempty(this.OnewebDetectionResult)
                resultPanel.displayOnewebDetection( ...
                    this.OnewebDetectionResult.overlayImage, [], {}, []);
            end
            if ismethod(resultPanel, 'updateStatus')
                resultPanel.updateStatus('✓ 实现星链、一网两种卫星通信体制的识别');
            end
            this.updateStatus('实现星链、一网两种卫星通信体制的识别');
        end
        
        %% ==================== 6 步内部辅助 ====================
        
        function sat = loadOneRandomSat(this, constellation, fallbackArgs)
            % 随机抽 1 颗 TLE 卫星，失败回退到默认开普勒参数
            tleDir = fullfile(this.projectRoot(), 'data', 'TLE', constellation);
            tleFiles = dir(fullfile(tleDir, '*.tle'));
            sat = [];
            if ~isempty(tleFiles)
                attempts = min(5, numel(tleFiles));
                for k = 1:attempts
                    idx = randi(numel(tleFiles));
                    tlePath = fullfile(tleFiles(idx).folder, tleFiles(idx).name);
                    try
                        s = satellite(this.Scenario, tlePath);
                        if numel(s) > 1, s = s(1); end
                        sat = s;
                        return;
                    catch
                    end
                end
            end
            warning('TestFlowPanel:TLEFallback', '%s TLE 加载失败，使用默认开普勒参数', constellation);
            sat = satellite(this.Scenario, fallbackArgs{:});
        end
        
        function gs = addTerminalForSat(this, satObj, constellation, name)
            try
                cfg = struct('numCandidates', 200);
                pos = twin.signal.terminal(this.Scenario, satObj, constellation, [], cfg);
            catch ME
                warning('TestFlowPanel:TerminalFallback', '%s', ME.message);
                [latArr, lonArr, ~] = states(satObj, this.Scenario.StartTime, ...
                    'CoordinateFrame', 'geographic');
                pos = [min(max(latArr(1), -89.5), 89.5), this.wrapLongitude(lonArr(1)), 0];
            end
            gs = groundStation(this.Scenario, pos(1), pos(2), ...
                'Name', name, 'MinElevationAngle', 10);
        end
        
        function [iq, img] = generateAndDisplay(this, constellation, bwMode, termObj, satObj, compObj)
            simTime = this.Scenario.StartTime + seconds(30);
            [companionPos, companionVel] = states(compObj, simTime, 'CoordinateFrame', 'ecef');
            [commSatPos, ~] = states(satObj, simTime, 'CoordinateFrame', 'ecef');
            terminalPos = [termObj.Latitude, termObj.Longitude, 0];
            try
                [iq, img] = this.generateWidebandSignal(constellation, bwMode, terminalPos, ...
                    companionPos(:), companionVel(:), commSatPos(:), simTime);
            catch ME
                warning('TestFlowPanel:SignalGenFailed', '%s', ME.message);
                iq = [];
                img = this.generateMockSTFT(constellation);
            end
        end
        
        function loadDetectorAuto(this)
            % 自动从 results/unified/detection 找最新 detector.mat
            detPath = '';
            roots = {fullfile(this.projectRoot(), 'results', 'unified', 'detection'), ...
                     fullfile(this.projectRoot(), 'models', 'detection')};
            for k = 1:numel(roots)
                if ~exist(roots{k}, 'dir'), continue; end
                files = dir(fullfile(roots{k}, '**', 'detector.mat'));
                if isempty(files), continue; end
                [~, ord] = sort([files.datenum], 'descend');
                detPath = fullfile(files(ord(1)).folder, files(ord(1)).name);
                break;
            end
            if isempty(detPath)
                error('未找到 detector.mat');
            end
            d = load(detPath);
            if isfield(d, 'detector'),    this.DetectionModel = d.detector;
            elseif isfield(d, 'net'),     this.DetectionModel = d.net;
            else,                          this.DetectionModel = d;
            end
            fprintf('已加载检测模型: %s\n', detPath);
        end
        
        function root = projectRoot(~)
            classFile = which('twin.app.TestFlowPanel');
            here = fileparts(classFile);
            root = fileparts(fileparts(fileparts(here)));
        end
        
        
        %% ==================== UI 辅助方法 ====================
        
        function setStepPending(this, stepIdx)
            this.StepStatus(stepIdx) = 0;
            btn = this.StepButtons{stepIdx};
            btn.Enable = 'off';
            btn.BackgroundColor = [0.18 0.18 0.20];
            btn.FontColor = this.TextColor;
            btn.Text = this.formatStepText(stepIdx, 'pending');
        end

        function setStepActive(this, stepIdx)
            this.StepStatus(stepIdx) = 1;
            this.CurrentStep = stepIdx;
            btn = this.StepButtons{stepIdx};
            btn.Text = this.formatStepText(stepIdx, 'active');
            btn.BackgroundColor = this.ActiveColor;
            btn.FontColor = [0 0 0];
        end

        function setStepCompleted(this, stepIdx)
            this.StepStatus(stepIdx) = 2;
            btn = this.StepButtons{stepIdx};
            btn.Text = this.formatStepText(stepIdx, 'completed');
            btn.BackgroundColor = this.SuccessColor;
            btn.FontColor = [1 1 1];
            btn.Enable = 'off';
        end

        function enableStep(this, stepIdx)
            btn = this.StepButtons{stepIdx};
            btn.Enable = 'on';
            btn.BackgroundColor = this.AccentColor;
            btn.FontColor = [1 1 1];
            btn.Text = this.formatStepText(stepIdx, 'enabled');
        end
        
        function updateStatus(this, msg)
            % 更新状态标签
            this.StatusLabel.Text = msg;
        end
        
        %% ==================== 感知检测辅助 ====================
        
        function detResult = runDetectionForImage(this, img, defaultLabel)
            % 对单个 STFT 图像运行检测模型
            detector = this.DetectionModel;
            if isempty(detector)
                error('未加载检测模型');
            end
            
            imgRGB = this.ensureRgbImage(img);
            detectThreshold = this.DetectionThreshold;
            
            try
                try
                    [bboxes, scores, labelsRaw] = detect(detector, imgRGB, 'Threshold', detectThreshold);
                catch
                    [bboxes, scores] = detect(detector, imgRGB, 'Threshold', detectThreshold);
                    labelsRaw = [];
                end
            catch ME
                error('TestFlowPanel:DetectorInvokeFailed', '检测模型调用失败: %s', ME.message);
            end
            
            if isempty(bboxes)
                bboxes = zeros(0, 4);
                scores = zeros(0, 1);
            end
            scores = scores(:);
            labels = this.normalizeDetectionLabels(labelsRaw, size(bboxes, 1), defaultLabel);
            
            overlayImg = this.renderDetectionOverlay(imgRGB, bboxes, labels);
            
            detResult = struct( ...
                'image', imgRGB, ...
                'overlayImage', overlayImg, ...
                'bboxes', bboxes, ...
                'scores', scores, ...
                'labels', {labels});
        end
        
        function imgRGB = ensureRgbImage(~, img)
            % 将图像转换为 uint8 RGB
            if isa(img, 'gpuArray')
                img = gather(img);
            end
            if ~isa(img, 'uint8')
                img = im2uint8(mat2gray(img));
            end
            if ndims(img) == 2 || size(img, 3) == 1
                imgRGB = repmat(img(:, :, 1), 1, 1, 3);
            else
                imgRGB = img;
            end
        end
        
        function overlayImg = renderDetectionOverlay(~, imgRGB, bboxes, labels)
            % 将检测框渲染到图像上（支持中文标签）
            % 替换标签：starlink -> 星链体制，oneweb -> 一网体制
            labelsDisplay = labels;
            if iscell(labelsDisplay)
                for i = 1:numel(labelsDisplay)
                    labelStr = lower(char(labelsDisplay{i}));
                    if contains(labelStr, 'starlink')
                        labelsDisplay{i} = '星链体制';
                    elseif contains(labelStr, 'oneweb')
                        labelsDisplay{i} = '一网体制';
                    end
                end
            end
            
            % 使用 insertShape 绘制框，insertText 绘制文字（支持中文）
            overlayImg = imgRGB;
            
            if isempty(bboxes)
                return;
            end
            
            try
                % 先绘制检测框
                overlayImg = insertShape(overlayImg, 'Rectangle', bboxes, ...
                    'LineWidth', 2, 'Color', 'red');
                
                % 再绘制文字标签（使用支持中文的字体）
                for i = 1:size(bboxes, 1)
                    bbox = bboxes(i, :);
                    if i <= numel(labelsDisplay) && ~isempty(labelsDisplay{i})
                        labelText = char(labelsDisplay{i});
                        % 文字位置：框的左上角上方
                        textPos = [bbox(1), max(1, bbox(2) - 5)];
                        
                        % 尝试使用支持中文的字体
                        try
                            overlayImg = insertText(overlayImg, textPos, labelText, ...
                                'FontSize', 28, ...
                                'TextColor', 'white', ...
                                'BoxColor', 'red', ...
                                'BoxOpacity', 0.8, ...
                                'AnchorPoint', 'LeftBottom', ...
                                'Font', 'SimHei');  % 使用黑体字体支持中文
                        catch
                            % 如果 SimHei 不可用，尝试其他字体
                            try
                                overlayImg = insertText(overlayImg, textPos, labelText, ...
                                    'FontSize', 28, ...
                                    'TextColor', 'white', ...
                                    'BoxColor', 'red', ...
                                    'BoxOpacity', 0.8, ...
                                    'AnchorPoint', 'LeftBottom', ...
                                    'Font', 'Microsoft YaHei');
                            catch
                                % 最后回退：不指定字体（可能显示为方块，但不会报错）
                                overlayImg = insertText(overlayImg, textPos, labelText, ...
                                    'FontSize', 28, ...
                                    'TextColor', 'white', ...
                                    'BoxColor', 'red', ...
                                    'BoxOpacity', 0.8, ...
                                    'AnchorPoint', 'LeftBottom');
                            end
                        end
                    end
                end
            catch ME
                % 如果所有方法都失败，至少绘制框
                warning('TestFlowPanel:RenderFailed', '检测框渲染失败: %s', ME.message);
                try
                    overlayImg = insertShape(imgRGB, 'Rectangle', bboxes, ...
                        'LineWidth', 2, 'Color', 'red');
                catch
                    overlayImg = imgRGB;
                end
            end
        end
        
        function labels = normalizeDetectionLabels(~, labelsRaw, numBoxes, defaultLabel)
            if nargin < 4 || isempty(defaultLabel)
                defaultLabel = 'signal';
            end
            
            if isempty(labelsRaw)
                labels = repmat({defaultLabel}, numBoxes, 1);
                return;
            end
            
            if iscell(labelsRaw)
                labels = labelsRaw;
            elseif isa(labelsRaw, 'categorical') || isstring(labelsRaw)
                labels = cellstr(labelsRaw);
            else
                labels = repmat({defaultLabel}, numBoxes, 1);
            end
            
            if numel(labels) < numBoxes
                labels(end+1:numBoxes) = {defaultLabel}; 
            end
        end
        
        function img = generateMockSTFT(~, constellation)
            % 生成模拟 STFT 图像
            % 用于没有真实数据时的演示
            
            img = zeros(256, 256, 3, 'uint8');
            
            % 背景噪声
            noise = uint8(randn(256, 256) * 20 + 30);
            img(:,:,1) = noise;
            img(:,:,2) = noise;
            img(:,:,3) = uint8(double(noise) * 1.2);
            
            % 添加信号条纹
            if strcmp(constellation, 'starlink')
                % Starlink: 60MHz 带宽，8个信道
                for ch = 1:3
                    yStart = 30 + (ch-1) * 70;
                    yEnd = yStart + 50;
                    xStart = randi([20, 100]);
                    xEnd = xStart + randi([80, 150]);
                    
                    img(yStart:yEnd, xStart:xEnd, 1) = 200;
                    img(yStart:yEnd, xStart:xEnd, 2) = 150;
                    img(yStart:yEnd, xStart:xEnd, 3) = 50;
                end
            else
                % OneWeb: 20MHz 带宽，10个信道
                for ch = 1:4
                    yStart = 20 + (ch-1) * 55;
                    yEnd = yStart + 40;
                    xStart = randi([20, 100]);
                    xEnd = xStart + randi([80, 150]);
                    
                    img(yStart:yEnd, xStart:xEnd, 1) = 50;
                    img(yStart:yEnd, xStart:xEnd, 2) = 200;
                    img(yStart:yEnd, xStart:xEnd, 3) = 150;
                end
            end
        end
        
        function lonWrapped = wrapLongitude(~, lon)
            lonWrapped = mod(lon + 180, 360) - 180;
        end
        
        function [iqData, stftImage] = generateWidebandSignal(this, constellation, bwMode, ...
                terminalPos, companionPos, companionVel, commSatPos, simTime)
            % GENERATEWIDEBANDSIGNAL 生成宽带接收信号
            % 复用 dataGen 核心代码：transmit -> channel -> receive
            %
            % 输入:
            %   constellation - 星座名称 ('starlink', 'oneweb')
            %   bwMode        - 带宽模式 ('mode_60MHz', 'mode_20MHz')
            %   terminalPos   - 终端位置 [lat, lon, alt]
            %   companionPos  - 伴飞卫星 ECEF 位置 [x,y,z]
            %   companionVel  - 伴飞卫星 ECEF 速度 [vx,vy,vz]
            %   commSatPos    - 通信卫星 ECEF 位置 [x,y,z]
            %   simTime       - 仿真时间 (datetime)
            %
            % 输出:
            %   iqData    - 宽带 IQ 数据
            %   stftImage - STFT 图像矩阵
            
            fprintf('  [生成] 加载配置...\n');
            
            % 1. 加载配置
            spectrumConfig = spectrumMonitorConfig(constellation);
            phyParams = constellationPhyConfig(constellation);
            
            % 2. 创建简化的终端配置（不依赖指纹库）
            terminalProfile = this.buildSimpleTerminalProfile(...
                constellation, bwMode, terminalPos, commSatPos, phyParams, spectrumConfig);
            
            if ~terminalProfile.initialized
                error('无法创建终端配置');
            end
            
            fprintf('  [生成] 发射端处理...\n');
            
            % 3. 发射端处理 (复用 dataGen.link.transmit)
            [txWaveform, txInfo, ~] = dataGen.link.transmit(terminalProfile, constellation, bwMode);
            txInfo.constellation = constellation;
            
            % 确保 txInfo.txPower 存在（从终端配置获取）
            if ~isfield(txInfo, 'txPower') || isempty(txInfo.txPower)
                txInfo.txPower = terminalProfile.txTemplate.txPower;
            end
            
            fprintf('  [生成] 信道传播 (波形长度=%d)...\n', length(txWaveform));
            
            % 4. 信道传播 (复用 dataGen.link.channel)
            timeInstant = posixtime(simTime);
            options = struct('enableWidebandSampling', true);
            receiverCfg = dataGen.config.receiver(options, spectrumConfig);
            
            [rxWaveform, ~, ~] = dataGen.link.channel(txWaveform, txInfo, terminalProfile, ...
                companionPos, companionVel, commSatPos, 'clear', timeInstant, receiverCfg, true);
            
            fprintf('  [生成] 宽带接收处理...\n');
            
            % 5. 宽带接收处理 (复用 dataGen.link.receive)
            slotStartIdx = randi([1, round(spectrumConfig.broadband.sampling.IQSampleLength * 0.3)]);
            [iqData, ~] = dataGen.link.receive(rxWaveform, txInfo, spectrumConfig, slotStartIdx);
            
            % 6. 添加噪声
            k_B = 1.38064852e-23;
            T_sys = spectrumConfig.broadband.receiver.systemNoiseTemp;
            B = spectrumConfig.broadband.sampling.bandwidth;
            P_noise = k_B * T_sys * B;
            noiseStd = sqrt(P_noise / 2);
            noiseVector = noiseStd * (randn(length(iqData), 1) + 1j * randn(length(iqData), 1));
            iqData = iqData + noiseVector;
            
            % 7. 归一化
            combinedPower = mean(abs(iqData).^2);
            if combinedPower > 0
                scaleFactor = sqrt(1.0 / combinedPower);
                iqData = iqData * scaleFactor;
            end
            
            fprintf('  [生成] 计算 STFT...\n');
            
            % 8. 计算 STFT 图像
            stftImage = this.computeSTFTImage(iqData, spectrumConfig);
            
            fprintf('  [生成] 完成\n');
        end
        
        function profile = buildSimpleTerminalProfile(~, constellation, bwMode, ...
                terminalPos, commSatPos, phyParams, spectrumConfig)
            % 构建简化的终端配置（不依赖指纹库）
            
            profile = struct('initialized', false);
            
            if ~isfield(phyParams.channelization.modes, bwMode)
                return;
            end
            
            modeParams = phyParams.channelization.modes.(bwMode);
            
            % 终端位置保持 LLA 格式（dataGen.link.propagate 需要 LLA）
            utPosLLA = terminalPos;  % [lat, lon, alt]
            
            % 验证链路仰角
            [elevation, ~, ~] = calculateLinkGeometry(utPosLLA, commSatPos);
            minElev = 20;
            if elevation < minElev
                warning('仰角 %.1f° 低于最小要求 %d°', elevation, minElev);
            end
            
            fprintf('  [终端] 位置: [%.2f°, %.2f°], 仰角: %.1f°\n', ...
                utPosLLA(1), utPosLLA(2), elevation);
            
            % 随机选择 MCS (从 phyParams.mcsTable 获取)
            if isfield(phyParams, 'mcsTable') && ~isempty(phyParams.mcsTable)
                mcsTable = phyParams.mcsTable;
                mcsIdx = randi([size(mcsTable, 1)-1 size(mcsTable, 1)]);
                % mcsTable 格式: [index, modulationOrder, codeRate, ...]
                modOrder = mcsTable(mcsIdx, 2);
                codeRate = mcsTable(mcsIdx, 3);
                % 将调制阶数转换为名称
                switch modOrder
                    case 2
                        modulation = 'BPSK';
                    case 4
                        modulation = 'QPSK';
                    case 16
                        modulation = '16QAM';
                    case 64
                        modulation = '64QAM';
                    otherwise
                        modulation = 'QPSK';
                end
            else
                % 默认 MCS
                mcsIdx = 1;
                modulation = 'QPSK';
                codeRate = 0.5;
            end
            
            % 构建发射模板
            txTemplate = dataGen.signal.txParams(constellation, modeParams);
            txTemplate.modulation = modulation;
            txTemplate.codeRate = codeRate;
            txTemplate.mcsIndex = mcsIdx;
            txTemplate.channelIndex = randi(modeParams.numChannels);
            txTemplate.bandwidthMode = bwMode;
            
            % 确保 txPower 存在（W）
            if ~isfield(txTemplate, 'txPower') || isempty(txTemplate.txPower)
                % 默认 30 dBm = 1 W
                txTemplate.txPower = 1.0;
            end
            
            % 随机载荷比特数
            if isfield(phyParams.waveform, 'payloadBitsRange')
                rangeStruct = phyParams.waveform.payloadBitsRange;
                if isfield(rangeStruct, bwMode)
                    payloadRange = rangeStruct.(bwMode);
                    txTemplate.numInfoBits = randi(payloadRange);
                else
                    txTemplate.numInfoBits = 20000;
                end
            else
                txTemplate.numInfoBits = 20000;
            end
            
            % 简化的 RF 元数据（无射频损伤）
            rfMeta = struct();
            rfMeta.phaseNoise = 0;
            rfMeta.frequencyOffset = 0;
            rfMeta.dcOffset = 0;
            rfMeta.iqImbalance = struct('amplitudeImbalance', 0, 'phaseImbalance', 0);
            rfMeta.paModel = [];
            rfMeta.id = sprintf('%s_demo_%d', constellation, randi(1000));
            rfMeta.type = 'demo';
            
            % 组装配置
            profile.initialized = true;
            profile.utPos = utPosLLA(:)';  % 保持 LLA 格式 [lat, lon, alt]
            profile.modeKey = bwMode;
            profile.mcsIndex = mcsIdx;
            profile.modulation = modulation;
            profile.codeRate = codeRate;
            profile.txTemplate = txTemplate;
            profile.rfMeta = rfMeta;
            profile.tid = rfMeta.id;
            profile.txPowerBackoff_dB = 0;
            profile.fingerprintCategory = 'demo';
        end
        
        function stftImage = computeSTFTImage(~, iqData, spectrumConfig)
            % 计算 STFT 图像
            % 直接复用 dataGen.io.spectrogram 函数
            
            stftImage = dataGen.io.spectrogram(iqData, [], spectrumConfig, [640, 640]);
        end
    end
end


