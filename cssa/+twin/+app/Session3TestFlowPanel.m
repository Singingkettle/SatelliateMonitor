classdef Session3TestFlowPanel < matlabshared.application.Component
    % SESSION3TESTFLOWPANEL 干扰防御 - 会话3 测试流程面板
    %
    %   精简后 7 步固定流程（取代旧的 23 步）：
    %     1. 创建场景 + 加载 Starlink+OneWeb 卫星
    %     2. 部署终端 + 伴飞卫星 (共享偏移)
    %     3. Starlink 通信链路 + 发射信号 + 显示
    %     4. OneWeb 通信链路 + 发射信号 + 显示
    %     5. 加载干扰策略集合 (white / STAD / STSD / STPD)
    %     6. 对 Starlink 施加干扰 + 评估输出
    %     7. 对 OneWeb 施加干扰 + 评估输出
    
    properties (Hidden)
        MainGrid
        StepsLayout
        
        % 步骤按钮和标签
        StepButtons
        StepLabels
        StepStatus  % 0=pending, 1=active, 2=completed
        CurrentStep = 0
        
        % 场景对象
        Scenario
        StarlinkSatellite
        StarlinkTerminal
        StarlinkCompanion
        StarlinkCommAccess
        StarlinkMonitorAccess
        StarlinkJamAccess       % 干扰链路
        OnewebSatellite
        OnewebTerminal
        OnewebCompanion
        OnewebCommAccess
        OnewebMonitorAccess
        OnewebJamAccess         % 干扰链路
        
        % 伴飞卫星偏移距离
        StarlinkOffset = 5  % km
        OnewebOffset = 5    % km
        StarlinkOffsetSlider
        StarlinkOffsetLabel
        OnewebOffsetSlider
        OnewebOffsetLabel
        
        % 生成的信号数据（完整干扰评估数据结构）
        StarlinkJamData         % Starlink完整干扰数据
        StarlinkJammedIQ        % 各策略干扰后信号
        OnewebJamData           % OneWeb完整干扰数据
        OnewebJammedIQ
        
        % 干扰策略
        JammingStrategies       % 所有干扰策略名称
        JammingModels           % 加载的干扰模型
        
        % 干扰评估结果
        StarlinkJamResults
        OnewebJamResults
        
        % 状态
        StatusLabel
    end
    
    properties (Constant, Hidden)
        StepNames = {
            '创建场景 + 加载 Starlink/OneWeb 卫星'
            '部署终端 + 伴飞卫星 (共享偏移)'
            'Starlink 通信链路 + 发射信号 + 显示'
            'OneWeb 通信链路 + 发射信号 + 显示'
            '加载干扰策略集合 (white/STAD/STSD/STPD)'
            '对 Starlink 施加干扰 + 评估输出'
            '对 OneWeb 施加干扰 + 评估输出'
        }
        StepIO = {
            '输入: TLE/starlink + TLE/oneweb        输出: scenario + 2 颗 satellite'
            '输入: 主卫星 + 偏移 km                  输出: 2 个 groundStation + 2 个 companion satellite'
            '输入: Starlink 终端/通信星/伴飞星      输出: 干净基带 + burstInfo + 通信链路对象'
            '输入: OneWeb 终端/通信星/伴飞星        输出: 干净基带 + burstInfo + 通信链路对象'
            '输入: jamming.strategy.* 函数句柄      输出: 4 种策略的 functor 注册'
            '输入: Starlink 干净基带 + burstInfo    输出: jammed IQ + BER 曲线 + 干扰链路'
            '输入: OneWeb 干净基带 + burstInfo      输出: jammed IQ + BER 曲线 + 干扰链路'
        }
        
        BgColor = [0.1 0.1 0.12]
        TextColor = [0.85 0.85 0.85]
        AccentColor = [0.2 0.6 1.0]
        SuccessColor = [0.3 0.9 0.4]
        PendingColor = [0.5 0.5 0.5]
        ActiveColor = [1.0 0.8 0.2]
    end
    
    events
        StepCompleted
        AllStepsCompleted
        SignalDisplayReady      % 信号显示准备好
        JammingResultReady      % 干扰结果准备好
    end
    
    methods
        function this = Session3TestFlowPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
            n = numel(this.StepNames);
            this.StepButtons = cell(n, 1);
            this.StepLabels = cell(n, 1);
            this.StepStatus = zeros(n, 1);
        end
        
        function name = getName(~)
            name = '测试流程';
        end
        
        function tag = getTag(~)
            tag = 'session3testflow';
        end
        
        function update(this)
            hFig = this.Figure;
            delete(hFig.Children);
            hFig.Color = this.BgColor;
            
            this.createUI(hFig);
            this.resetSteps();
            
            % 启用第一步
            if ~isempty(this.StepButtons{1})
                this.StepButtons{1}.Enable = 'on';
            end
        end
        
        function createUI(this, parent)
            % 主网格：标题 + 步骤区域 + 状态栏 + 控制按钮
            this.MainGrid = uigridlayout(parent, [4, 1]);
            this.MainGrid.RowHeight = {40, '1x', 30, 45};
            this.MainGrid.Padding = [10 10 10 10];
            this.MainGrid.RowSpacing = 8;
            this.MainGrid.BackgroundColor = this.BgColor;
            
            % 标题栏
            titlePanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.15 0.15 0.18], ...
                'BorderType', 'none');
            titleLayout = uigridlayout(titlePanel, [1, 1]);
            titleLayout.ColumnWidth = {'1x'};
            titleLayout.Padding = [10 5 10 5];
            titleLayout.BackgroundColor = [0.15 0.15 0.18];
            
            uilabel(titleLayout, ...
                'Text', '干扰防御测试流程', ...
                'FontSize', 14, ...
                'FontWeight', 'bold', ...
                'FontColor', this.AccentColor, ...
                'BackgroundColor', [0.15 0.15 0.18]);
            
            % 创建可滚动的步骤区域
            scrollPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', this.BgColor, ...
                'BorderType', 'none', ...
                'Scrollable', 'on');
            
            % 步骤列表布局
            n = numel(this.StepNames);
            stepsLayout = uigridlayout(scrollPanel, [n, 1]);
            stepsLayout.RowHeight = repmat({'fit'}, 1, n);
            stepsLayout.Padding = [5 5 5 5];
            stepsLayout.RowSpacing = 6;
            stepsLayout.BackgroundColor = this.BgColor;
            this.StepsLayout = stepsLayout;
            
            % 创建每个步骤行
            for i = 1:n
                rowPanel = uipanel(stepsLayout, ...
                    'BackgroundColor', [0.14 0.14 0.16], ...
                    'BorderType', 'none');
                this.createNormalStepRow(rowPanel, i);
            end
            
            % 状态栏
            statusPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.12 0.12 0.14], ...
                'BorderType', 'none');
            statusLayout = uigridlayout(statusPanel, [1, 1]);
            statusLayout.ColumnWidth = {'1x'};
            statusLayout.Padding = [10 2 10 2];
            statusLayout.BackgroundColor = [0.12 0.12 0.14];
            
            this.StatusLabel = uilabel(statusLayout, ...
                'Text', '等待开始...', ...
                'FontSize', 11, ...
                'FontColor', this.TextColor, ...
                'BackgroundColor', [0.12 0.12 0.14]);
            
            % 控制按钮栏
            controlPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.12 0.12 0.14], ...
                'BorderType', 'none');
            controlLayout = uigridlayout(controlPanel, [1, 3]);
            controlLayout.ColumnWidth = {'1x', '1x', '1x'};
            controlLayout.Padding = [10 5 10 5];
            controlLayout.ColumnSpacing = 10;
            controlLayout.BackgroundColor = [0.12 0.12 0.14];
            
            uibutton(controlLayout, ...
                'Text', '▶ 一键运行', ...
                'FontSize', 11, ...
                'BackgroundColor', this.AccentColor, ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.runAllSteps());
            
            uibutton(controlLayout, ...
                'Text', '⏭ 单步', ...
                'FontSize', 11, ...
                'BackgroundColor', [0.4 0.7 0.3], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.runNextStep());
            
            % 重置按钮
            uibutton(controlLayout, ...
                'Text', '↺ 重置', ...
                'FontSize', 11, ...
                'BackgroundColor', [0.5 0.3 0.3], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) this.resetSteps());
        end
        
        function createNormalStepRow(this, rowPanel, stepIdx)
            grid = uigridlayout(rowPanel, [1, 3]);
            grid.ColumnWidth = {32, '1x', 100};
            grid.Padding = [8 4 8 4];
            grid.ColumnSpacing = 10;
            grid.BackgroundColor = [0.14 0.14 0.16];
            
            numLabel = uilabel(grid, ...
                'Text', sprintf('%d', stepIdx), ...
                'FontSize', 14, 'FontWeight', 'bold', ...
                'FontColor', this.PendingColor, ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.14 0.14 0.16]);
            
            mid = uigridlayout(grid, [2, 1]);
            mid.RowHeight = {'fit', 'fit'};
            mid.RowSpacing = 2;
            mid.Padding = [0 0 0 0];
            mid.BackgroundColor = [0.14 0.14 0.16];
            
            nameLabel = uilabel(mid, ...
                'Text', this.StepNames{stepIdx}, ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', this.TextColor, ...
                'BackgroundColor', [0.14 0.14 0.16]);
            
            ioRow = uigridlayout(mid, [1, 2]);
            ioRow.ColumnWidth = {'1x', 'fit'};
            ioRow.Padding = [0 0 0 0];
            ioRow.BackgroundColor = [0.14 0.14 0.16];
            
            uilabel(ioRow, ...
                'Text', this.StepIO{stepIdx}, ...
                'FontSize', 10, 'FontColor', [0.65 0.65 0.65], ...
                'BackgroundColor', [0.14 0.14 0.16]);
            
            paramHost = uigridlayout(ioRow, [1, 1]);
            paramHost.Padding = [0 0 0 0];
            paramHost.BackgroundColor = [0.14 0.14 0.16];
            if stepIdx == 2
                paramHost.ColumnWidth = {110, 100, 60};
                uilabel(paramHost, 'Text', '伴飞偏移:', 'FontSize', 10, ...
                    'FontColor', [0.7 0.7 0.7], ...
                    'HorizontalAlignment', 'right', ...
                    'BackgroundColor', [0.14 0.14 0.16]);
                slider = uislider(paramHost, ...
                    'Limits', [0 30], 'Value', this.StarlinkOffset, ...
                    'MajorTicks', [], 'MinorTicks', []);
                lbl = uilabel(paramHost, ...
                    'Text', sprintf('%d km', this.StarlinkOffset), ...
                    'FontSize', 10, 'FontColor', this.AccentColor, ...
                    'BackgroundColor', [0.14 0.14 0.16]);
                slider.ValueChangedFcn = @(src,~) this.onSharedOffsetChanged(src, lbl);
                this.StarlinkOffsetSlider = slider;
                this.StarlinkOffsetLabel = lbl;
                this.OnewebOffsetSlider = slider;
                this.OnewebOffsetLabel = lbl;
            end
            
            btn = uibutton(grid, ...
                'Text', '▶', 'FontSize', 11, ...
                'BackgroundColor', [0.25 0.25 0.28], ...
                'FontColor', this.TextColor, ...
                'Enable', 'off', ...
                'ButtonPushedFcn', @(~,~) this.executeStep(stepIdx));
            
            this.StepButtons{stepIdx} = btn;
            this.StepLabels{stepIdx} = struct('num', numLabel, 'name', nameLabel, 'panel', rowPanel);
        end
        
        function onSharedOffsetChanged(this, src, label)
            v = round(src.Value);
            this.StarlinkOffset = v;
            this.OnewebOffset = v;
            label.Text = sprintf('%d km', v);
        end
        function executeStep(this, stepIdx)
            this.setStepActive(stepIdx);
            this.StatusLabel.Text = sprintf('正在运行: %s...', this.StepNames{stepIdx});
            drawnow;
            
            try
                switch stepIdx
                    case 1, this.step1_CreateAndLoad();
                    case 2, this.step2_DeployTerminalsCompanions();
                    case 3, this.step3_StarlinkLinkAndSignal();
                    case 4, this.step4_OnewebLinkAndSignal();
                    case 5, this.step5_LoadJamStrategies();
                    case 6, this.step6_ApplyAndEvaluateStarlink();
                    case 7, this.step7_ApplyAndEvaluateOneweb();
                end
                
                this.setStepCompleted(stepIdx);
                this.StatusLabel.Text = sprintf('完成: %s', this.StepNames{stepIdx});
                
                notify(this, 'StepCompleted');
                
                if stepIdx < numel(this.StepNames)
                    this.StepButtons{stepIdx + 1}.Enable = 'on';
                else
                    notify(this, 'AllStepsCompleted');
                    this.StatusLabel.Text = '所有步骤已完成！';
                end
                
            catch ME
                this.setStepFailed(stepIdx);
                this.StatusLabel.Text = sprintf('错误: %s', ME.message);
                fprintf('步骤%d运行错误: %s\n', stepIdx, ME.message);
            end
        end
        
        %% ============== 7 步精简实现 ==============
        
        function step1_CreateAndLoad(this)
            startTime = datetime('now', 'TimeZone', 'UTC');
            stopTime = startTime + minutes(1);
            this.Scenario = satelliteScenario(startTime, stopTime, 1);
            if isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.createViewer(this.Scenario);
            end
            this.StarlinkSatellite = this.loadOneRandomSat('starlink', ...
                {6921000, 0.0001, 53, 0, 0, 0, 'Name', 'Starlink-默认', ...
                 'OrbitPropagator', 'two-body-keplerian'});
            this.OnewebSatellite = this.loadOneRandomSat('oneweb', ...
                {7571000, 0.0001, 87.9, 45, 0, 0, 'Name', 'OneWeb-默认', ...
                 'OrbitPropagator', 'two-body-keplerian'});
            fprintf('已加载 Starlink + OneWeb 通信卫星\n');
        end
        
        function step2_DeployTerminalsCompanions(this)
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
            fprintf('终端 + 伴飞卫星部署完成 (偏移=%d km)\n', this.StarlinkOffset);
        end
        
        function step3_StarlinkLinkAndSignal(this)
            % 链路 + 基带信号 + 干净信号显示
            this.StarlinkCommAccess = access(this.StarlinkTerminal, this.StarlinkSatellite);
            this.StarlinkCommAccess.LineColor = [0.2 0.8 0.4]; this.StarlinkCommAccess.LineWidth = 2;
            this.StarlinkMonitorAccess = access(this.StarlinkTerminal, this.StarlinkCompanion);
            this.StarlinkMonitorAccess.LineColor = [1.0 0.6 0.2]; this.StarlinkMonitorAccess.LineWidth = 2;
            try
                this.StarlinkJamData = this.generateBasebandSignal('starlink', ...
                    this.StarlinkTerminal, this.StarlinkSatellite, this.StarlinkCompanion);
            catch ME
                warning('Session3:SignalGenFailed', '%s', ME.message);
                this.StarlinkJamData = this.createFallbackJamData('starlink');
            end
            notify(this, 'SignalDisplayReady', ...
                twin.app.TestFrameEventData(struct( ...
                    'Constellation', 'starlink', ...
                    'SignalType', 'clean', ...
                    'IQData', this.StarlinkJamData.cleanSignal)));
        end
        
        function step4_OnewebLinkAndSignal(this)
            this.OnewebCommAccess = access(this.OnewebTerminal, this.OnewebSatellite);
            this.OnewebCommAccess.LineColor = [0.2 0.8 0.4]; this.OnewebCommAccess.LineWidth = 2;
            this.OnewebMonitorAccess = access(this.OnewebTerminal, this.OnewebCompanion);
            this.OnewebMonitorAccess.LineColor = [1.0 0.6 0.2]; this.OnewebMonitorAccess.LineWidth = 2;
            try
                this.OnewebJamData = this.generateBasebandSignal('oneweb', ...
                    this.OnewebTerminal, this.OnewebSatellite, this.OnewebCompanion);
            catch ME
                warning('Session3:SignalGenFailed', '%s', ME.message);
                this.OnewebJamData = this.createFallbackJamData('oneweb');
            end
            notify(this, 'SignalDisplayReady', ...
                twin.app.TestFrameEventData(struct( ...
                    'Constellation', 'oneweb', ...
                    'SignalType', 'clean', ...
                    'IQData', this.OnewebJamData.cleanSignal)));
        end
        
        function step5_LoadJamStrategies(this)
            this.JammingStrategies = {'white', 'STAD', 'STSD', 'STPD'};
            this.JammingModels = struct();
            for i = 1:numel(this.JammingStrategies)
                s = this.JammingStrategies{i};
                this.JammingModels.(s) = str2func(['jamming.strategy.' s]);
            end
            fprintf('已加载 %d 种干扰策略\n', numel(this.JammingStrategies));
        end
        
        function step6_ApplyAndEvaluateStarlink(this)
            if isempty(this.StarlinkJamData), error('请先生成 Starlink 基带信号'); end
            this.StarlinkJamAccess = access(this.StarlinkCompanion, this.StarlinkSatellite);
            this.StarlinkJamAccess.LineColor = [1.0 0.2 0.2]; this.StarlinkJamAccess.LineWidth = 3;
            
            jamData = this.StarlinkJamData;
            cleanSignal = double(jamData.cleanSignal(:));
            burstInfo = jamData.burstInfo;
            signalLen = length(cleanSignal);
            if isfield(burstInfo, 'burstMask') && any(burstInfo.burstMask)
                burstEnergy = sum(abs(cleanSignal(burstInfo.burstMask)).^2);
            else
                burstEnergy = sum(abs(cleanSignal).^2);
            end
            JSR_dB = 0;
            totalJamEnergy = burstEnergy * 10^(JSR_dB/10);
            this.StarlinkJammedIQ = struct();
            for i = 1:numel(this.JammingStrategies)
                s = this.JammingStrategies{i};
                try
                    j = this.generateJammingSignal(s, signalLen, totalJamEnergy, burstInfo);
                    this.StarlinkJammedIQ.(s) = cleanSignal + j;
                catch ME
                    warning('Session3:JamFailed', '%s: %s', s, ME.message);
                    this.StarlinkJammedIQ.(s) = cleanSignal;
                end
            end
            noisySignal = double(jamData.signal(:));
            notify(this, 'SignalDisplayReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'starlink', 'SignalType', 'noisy', 'IQData', noisySignal)));
            notify(this, 'SignalDisplayReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'starlink', 'SignalType', 'jammed', 'IQData', this.StarlinkJammedIQ)));
            this.StarlinkJamResults = this.evaluateJammingPerformance( ...
                cleanSignal, this.StarlinkJammedIQ, burstInfo, jamData.meta);
            notify(this, 'JammingResultReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'starlink', 'Results', this.StarlinkJamResults)));
        end
        
        function step7_ApplyAndEvaluateOneweb(this)
            if isempty(this.OnewebJamData), error('请先生成 OneWeb 基带信号'); end
            this.OnewebJamAccess = access(this.OnewebCompanion, this.OnewebSatellite);
            this.OnewebJamAccess.LineColor = [1.0 0.2 0.2]; this.OnewebJamAccess.LineWidth = 3;
            
            jamData = this.OnewebJamData;
            cleanSignal = double(jamData.cleanSignal(:));
            burstInfo = jamData.burstInfo;
            signalLen = length(cleanSignal);
            if isfield(burstInfo, 'burstMask') && any(burstInfo.burstMask)
                burstEnergy = sum(abs(cleanSignal(burstInfo.burstMask)).^2);
            else
                burstEnergy = sum(abs(cleanSignal).^2);
            end
            JSR_dB = 0;
            totalJamEnergy = burstEnergy * 10^(JSR_dB/10);
            this.OnewebJammedIQ = struct();
            for i = 1:numel(this.JammingStrategies)
                s = this.JammingStrategies{i};
                try
                    j = this.generateJammingSignal(s, signalLen, totalJamEnergy, burstInfo);
                    this.OnewebJammedIQ.(s) = cleanSignal + j;
                catch ME
                    warning('Session3:JamFailed', '%s: %s', s, ME.message);
                    this.OnewebJammedIQ.(s) = cleanSignal;
                end
            end
            noisySignal = double(jamData.signal(:));
            notify(this, 'SignalDisplayReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'oneweb', 'SignalType', 'noisy', 'IQData', noisySignal)));
            notify(this, 'SignalDisplayReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'oneweb', 'SignalType', 'jammed', 'IQData', this.OnewebJammedIQ)));
            this.OnewebJamResults = this.evaluateJammingPerformance( ...
                cleanSignal, this.OnewebJammedIQ, burstInfo, jamData.meta);
            notify(this, 'JammingResultReady', twin.app.TestFrameEventData(struct( ...
                'Constellation', 'oneweb', 'Results', this.OnewebJamResults)));
        end
        
        function sat = loadOneRandomSat(this, constellation, fallbackArgs)
            tleDir = fullfile(this.projectRoot(), 'data', 'TLE', constellation);
            files = dir(fullfile(tleDir, '*.tle'));
            sat = [];
            if ~isempty(files)
                for k = 1:min(5, numel(files))
                    idx = randi(numel(files));
                    try
                        s = satellite(this.Scenario, fullfile(files(idx).folder, files(idx).name));
                        if numel(s) > 1, s = s(1); end
                        sat = s; return;
                    catch
                    end
                end
            end
            warning('Session3:TLEFallback', '%s TLE 加载失败，使用默认开普勒参数', constellation);
            sat = satellite(this.Scenario, fallbackArgs{:});
        end
        
        function gs = addTerminalForSat(this, satObj, constellation, name)
            try
                cfg = struct('numCandidates', 200);
                pos = twin.signal.terminal(this.Scenario, satObj, constellation, [], cfg);
            catch
                [latArr, lonArr, ~] = states(satObj, this.Scenario.StartTime, ...
                    'CoordinateFrame', 'geographic');
                pos = [min(max(latArr(1), -89.5), 89.5), this.wrapLongitude(lonArr(1)), 0];
            end
            gs = groundStation(this.Scenario, pos(1), pos(2), ...
                'Name', name, 'MinElevationAngle', 10);
        end
        
        function root = projectRoot(~)
            classFile = which('twin.app.Session3TestFlowPanel');
            here = fileparts(classFile);
            root = fileparts(fileparts(fileparts(here)));
        end
        
        %% ============== 辅助函数 ==============
        
        function jamData = generateBasebandSignal(this, constellation, terminalObj, commSatObj, companionObj)
            % 生成基带信号，调用 twin.signal.jammer
            %
            % 输入:
            %   constellation - 星座名称
            %   terminalObj   - groundStation 对象
            %   commSatObj    - 通信卫星 satellite 对象
            %   companionObj  - 伴飞卫星 satellite 对象
            %
            % 输出:
            %   jamData - 完整干扰评估数据结构
            
            % 获取仿真时间（场景中间时刻）
            simTime = this.Scenario.StartTime + seconds(30);
            
            % 获取终端位置 [lat, lon, alt]
            terminalPos = [terminalObj.Latitude, terminalObj.Longitude, 0];
            
            % 获取通信卫星位置和速度 (ECEF)
            [commSatPos, commSatVel] = states(commSatObj, simTime, 'CoordinateFrame', 'ecef');
            commSatPos = commSatPos(:);
            commSatVel = commSatVel(:);
            
            % 获取伴飞卫星位置和速度 (ECEF)
            [companionPos, companionVel] = states(companionObj, simTime, 'CoordinateFrame', 'ecef');
            companionPos = companionPos(:);
            companionVel = companionVel(:);
            
            % 配置选项
            options = struct();
            options.observationWindow_ms = 30;  % 30ms观察窗口
            options.targetSNR_dB = 15;          % 目标SNR
            
            % 调用 jammer 函数生成完整干扰评估数据
            jamData = twin.signal.jammer(constellation, terminalPos, ...
                commSatPos, commSatVel, companionPos, companionVel, options);
        end
        
        function jamSignal = generateJammingSignal(~, stratName, signalLen, totalEnergy, burstInfo)
            % 根据策略生成干扰信号
            %
            % 参考 jamming.eval.metric 中的实现
            
            if strcmp(stratName, 'white')
                % 传统持续白噪声 - 基准对比
                jamSignal = jamming.strategy.white(signalLen, totalEnergy);
                
            elseif strcmp(stratName, 'STAD') || strcmp(stratName, 'reactive')
                % STAD: Sync-Triggered Adaptive Data-jamming
                % 同步触发自适应数据段干扰 - 最高能效
                jamSignal = jamming.strategy.STAD(signalLen, totalEnergy, burstInfo);
                
            elseif strcmp(stratName, 'STSD')
                % STSD: Sync-Triggered Sweep Data-jamming
                % 同步触发扫频数据段干扰 - 针对OFDM多子载波
                jamSignal = jamming.strategy.STSD(signalLen, totalEnergy, burstInfo);
                
            elseif startsWith(stratName, 'STPD') || strcmp(stratName, 'pulse')
                % STPD: Sync-Triggered Pulsed Data-jamming
                % 同步触发脉冲式数据段干扰 - 高峰值功率
                dutyCycle = 0.20;
                jamSignal = jamming.strategy.STPD(signalLen, totalEnergy, burstInfo, 'dutyCycle', dutyCycle);
                
            else
                warning('Session3:UnknownStrategy', '未知策略: %s，使用白噪声', stratName);
                jamSignal = jamming.strategy.white(signalLen, totalEnergy);
            end
        end
        
        function jamData = createFallbackJamData(~, constellation)
            % 创建后备的模拟干扰数据
            signalLen = 10000;
            sampleRate = 60e6;  % 默认采样率
            
            % 生成模拟信号
            cleanSignal = 0.1 * (randn(signalLen, 1) + 1j * randn(signalLen, 1));
            noiseVector = 0.01 * (randn(signalLen, 1) + 1j * randn(signalLen, 1));
            
            jamData = struct();
            jamData.signal = single(cleanSignal + noiseVector);
            jamData.cleanSignal = single(cleanSignal);
            jamData.noiseVector = single(noiseVector);
            jamData.txBits = logical([]);
            
            % burstInfo
            jamData.burstInfo = struct();
            jamData.burstInfo.numBursts = 1;
            jamData.burstInfo.sampleRate = sampleRate;
            jamData.burstInfo.burstStarts = 1;
            jamData.burstInfo.burstEnds = signalLen;
            jamData.burstInfo.burstDuration = signalLen;
            jamData.burstInfo.burstMask = true(signalLen, 1);
            jamData.burstInfo.syncSymbols = round(signalLen * 0.12);
            
            % rxConfig
            jamData.rxConfig = struct();
            jamData.rxConfig.bandwidthMode = 'mode_60MHz';
            jamData.rxConfig.mcs = 1;
            jamData.rxConfig.channelIndex = 1;
            
            % channelState
            jamData.channelState = struct();
            jamData.channelState.SNR = 15;
            jamData.channelState.dopplerShift = 0;
            
            % meta
            jamData.meta = struct();
            jamData.meta.constellation = constellation;
            jamData.meta.bandwidthMode = 'mode_60MHz';
            jamData.meta.sampleRate = sampleRate;
            jamData.meta.numBursts = 1;
            jamData.meta.SNR = 15;
            jamData.meta.dutyCycle = 1.0;
            jamData.meta.modulation = 'QPSK';
            
            warning('Session3:FallbackData', '使用模拟后备数据');
        end
        
        function results = evaluateJammingPerformance(this, cleanSignal, ~, burstInfo, meta)
            % 评估干扰性能（基于 jamming.eval.metric 的方法）
            % 在多个JSR水平下评估，生成BER曲线
            %
            % 输入:
            %   cleanSignal - 干净基带信号
            %   ~           - 单JSR干扰信号（不使用）
            %   burstInfo   - burst信息
            %   meta        - 元数据
            
            results = struct();
            results.meta = meta;
            
            % JSR测试范围
            JSR_dB_array = [-20, -10, -5, 0];
            results.JSR_dB_array = JSR_dB_array;
            
            % 计算信号能量和功率
            signalLen = length(cleanSignal);
            if isfield(burstInfo, 'burstMask') && any(burstInfo.burstMask)
                burstEnergy = sum(abs(cleanSignal(burstInfo.burstMask)).^2);
                signalPower = mean(abs(cleanSignal(burstInfo.burstMask)).^2);
            else
                burstEnergy = sum(abs(cleanSignal).^2);
                signalPower = mean(abs(cleanSignal).^2);
            end
            results.signalPower = signalPower;
            
            % 策略列表
            strategies = this.JammingStrategies;
            results.strategies = strategies;
            
            % 初始化BER曲线
            results.berCurves = struct();
            for s = 1:length(strategies)
                results.berCurves.(strategies{s}) = zeros(length(JSR_dB_array), 1);
            end
            
            fprintf('  评估多JSR水平: %s dB\n', mat2str(JSR_dB_array));
            
            % 对每个JSR水平评估
            for jIdx = 1:length(JSR_dB_array)
                JSR_dB = JSR_dB_array(jIdx);
                JSR_linear = 10^(JSR_dB / 10);
                totalJamEnergy = burstEnergy * JSR_linear;
                
                for s = 1:length(strategies)
                    stratName = strategies{s};
                    
                    % 生成干扰信号
                    try
                        jamSignal = this.generateJammingSignal(stratName, signalLen, totalJamEnergy, burstInfo);
                        jammedSignal = cleanSignal + jamSignal;
                        
                        % 计算BER
                        ber = computeSymbolBER(cleanSignal, jammedSignal, burstInfo);
                        results.berCurves.(stratName)(jIdx) = ber;
                    catch
                        results.berCurves.(stratName)(jIdx) = 0;
                    end
                end
                
                fprintf('    JSR=%d dB: ', JSR_dB);
                for s = 1:length(strategies)
                    fprintf('%s=%.3f ', strategies{s}, results.berCurves.(strategies{s})(jIdx));
                end
                fprintf('\n');
            end
            
            % BER阈值
            results.BERThresholds = struct();
            results.BERThresholds.systemCrash = 0.10;
            results.BERThresholds.severeDegradation = 0.05;
            results.BERThresholds.performanceLoss = 0.01;
        end
        
        function lon = wrapLongitude(~, lon)
            lon = mod(lon + 180, 360) - 180;
        end
        
        function updateStatus(this, msg)
            % 更新状态栏
            if ~isempty(this.StatusLabel)
                this.StatusLabel.Text = msg;
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
        
        function runNextStep(this)
            nextStep = this.CurrentStep + 1;
            if nextStep <= numel(this.StepNames)
                this.executeStep(nextStep);
            else
                this.updateStatus('所有步骤已完成');
            end
        end
        
        function resetSteps(this)
            for i = 1:numel(this.StepNames)
                this.resetStepUI(i);
            end
            this.CurrentStep = 0;
            
            % 清除场景视图
            if isprop(this.Application, 'ViewerPanel') && ~isempty(this.Application.ViewerPanel)
                this.Application.ViewerPanel.clearViewer();
            end
            
            % 清除结果面板
            if isprop(this.Application, 'Session3Result') && ~isempty(this.Application.Session3Result)
                this.Application.Session3Result.reset();
            end
            
            % 删除场景对象
            if ~isempty(this.Scenario) && isvalid(this.Scenario)
                delete(this.Scenario);
            end
            
            % 清除数据
            this.Scenario = [];
            this.StarlinkSatellite = [];
            this.StarlinkTerminal = [];
            this.StarlinkCompanion = [];
            this.StarlinkCommAccess = [];
            this.StarlinkMonitorAccess = [];
            this.StarlinkJamAccess = [];
            this.OnewebSatellite = [];
            this.OnewebTerminal = [];
            this.OnewebCompanion = [];
            this.OnewebCommAccess = [];
            this.OnewebMonitorAccess = [];
            this.OnewebJamAccess = [];
            this.StarlinkJamData = [];
            this.StarlinkJammedIQ = [];
            this.OnewebJamData = [];
            this.OnewebJammedIQ = [];
            this.JammingStrategies = {};
            this.JammingModels = struct();
            this.StarlinkJamResults = [];
            this.OnewebJamResults = [];
            
            % 启用第一步
            if ~isempty(this.StepButtons) && ~isempty(this.StepButtons{1})
                this.StepButtons{1}.Enable = 'on';
            end
            
            % 更新状态
            this.updateStatus('已重置 - 点击步骤1开始');
        end
        
        function resetStepUI(this, stepIdx)
            this.StepStatus(stepIdx) = 0;
            labels = this.StepLabels{stepIdx};
            labels.num.FontColor = this.PendingColor;
            labels.name.FontColor = this.TextColor;
            labels.panel.BackgroundColor = [0.14 0.14 0.16];
            
            btn = this.StepButtons{stepIdx};
            btn.Enable = 'off';
            btn.BackgroundColor = [0.25 0.25 0.28];
            btn.FontColor = this.TextColor;
            btn.Text = '▶';
        end
        
        function setStepActive(this, stepIdx)
            this.StepStatus(stepIdx) = 1;
            this.CurrentStep = stepIdx;
            labels = this.StepLabels{stepIdx};
            labels.num.FontColor = this.ActiveColor;
            labels.name.FontColor = this.ActiveColor;
            labels.panel.BackgroundColor = [0.18 0.18 0.12];
            
            btn = this.StepButtons{stepIdx};
            btn.Text = '…';
            btn.BackgroundColor = this.ActiveColor;
            btn.FontColor = [0 0 0];
        end
        
        function setStepCompleted(this, stepIdx)
            this.StepStatus(stepIdx) = 2;
            labels = this.StepLabels{stepIdx};
            labels.num.FontColor = this.SuccessColor;
            labels.name.FontColor = this.SuccessColor;
            labels.panel.BackgroundColor = [0.12 0.18 0.14];
            
            btn = this.StepButtons{stepIdx};
            btn.Text = '✓ 完成';
            btn.BackgroundColor = this.SuccessColor;
            btn.FontColor = [1 1 1];
            btn.Enable = 'off';
        end
        
        function setStepFailed(this, stepIdx)
            this.StepStatus(stepIdx) = -1;
            labels = this.StepLabels{stepIdx};
            labels.num.FontColor = [1.0 0.3 0.3];
            labels.name.FontColor = [1.0 0.3 0.3];
            labels.panel.BackgroundColor = [0.2 0.12 0.12];
            
            btn = this.StepButtons{stepIdx};
            btn.Text = '✗ 失败';
            btn.BackgroundColor = [0.8 0.2 0.2];
            btn.FontColor = [1 1 1];
        end
    end
end

%% ==================== 辅助函数: 符号级BER计算 ====================
function ber = computeSymbolBER(cleanSignal, jammedSignal, burstInfo)
    % 基于符号级 BER 估算（参考 jamming.eval.metric）
    % 对于 burst 窗口数据，计算数据段的符号错误率
    
    if ~isfield(burstInfo, 'burstStarts') || isempty(burstInfo.burstStarts)
        ber = 0.5;
        return;
    end
    
    totalErrors = 0;
    totalSymbols = 0;
    
    numBursts = burstInfo.numBursts;
    if numBursts == 0
        ber = 0.5;
        return;
    end
    
    for b = 1:numBursts
        burstStart = burstInfo.burstStarts(b);
        if isfield(burstInfo, 'burstEnds') && numel(burstInfo.burstEnds) >= b
            burstEnd = burstInfo.burstEnds(b);
        else
            burstEnd = burstStart + burstInfo.burstDuration - 1;
        end
        
        % 跳过同步序列，只评估数据段
        syncLen = burstInfo.syncSymbols;
        dataStart = burstStart + syncLen;
        dataEnd = min(burstEnd, length(cleanSignal));
        
        if dataStart >= dataEnd
            continue;
        end
        
        % 提取数据段
        cleanData = cleanSignal(dataStart:dataEnd);
        jammedData = jammedSignal(dataStart:dataEnd);
        
        % 符号级 BER 估算 (基于相位偏差)
        % 假设 QPSK 调制
        cleanPhase = angle(cleanData);
        jammedPhase = angle(jammedData);
        
        % 相位差超过 pi/4 认为错误
        phaseDiff = abs(wrapToPi(jammedPhase - cleanPhase));
        symbolErrors = sum(phaseDiff > pi/4);
        
        totalErrors = totalErrors + symbolErrors;
        totalSymbols = totalSymbols + length(cleanData);
    end
    
    if totalSymbols > 0
        ber = totalErrors / totalSymbols;
    else
        ber = 0.5;
    end
end

