classdef App < matlabshared.application.Application
    % APP 卫星终端认知与干扰防御平台主应用
    %
    %   使用 matlabshared.application 框架构建
    %   支持三种会话模式：
    %   1. 多种信号体制识别测试
    %   2. 典型终端信号识别测试
    %   3. 干扰防御测试
    %
    %   用法:
    %       app = twin.app.App();
    %       app.launch();
    %
    % 参考: satcom.internal.linkbudgetApp.Analyzer
    
    properties (SetAccess = protected)
        % 会话选择面板（初始显示）
        SessionVisual
        
        % 会话1 - 多种信号体制识别测试
        Session1TestFlow        % 测试流程面板
        Session1Result          % 识别结果面板
        
        % 会话2 - 典型终端信号识别测试
        Session2TestFlow        % 测试流程面板
        Session2Result          % 结果面板（左:识别结果 右:准确率统计）
        
        % 会话3 - 干扰防御测试
        Session3TestFlow        % 测试流程面板
        Session3Result          % 结果面板（左:干扰效果图 右:干扰性能评估）
        
        % 共用面板
        ViewerPanel             % 3D 场景查看器面板
        
        % 状态
        CurrentSession = 0      % 当前会话 (0=未选择, 1/2/3=对应会话)
        SessionStarted = false
    end
    
    methods
        function this = App()
        end
        
        function launch(this)
            % 启动应用
            open(this);
        end
        
        function startSession1(this)
            fprintf('启动会话1: 多种信号体制识别测试\n');
            this.startSessionLayout(1, this.Session1TestFlow, this.Session1Result);
            this.connectSession1Events();
        end
        
        function startSession2(this)
            fprintf('启动会话2: 典型终端信号识别测试\n');
            this.startSessionLayout(2, this.Session2TestFlow, this.Session2Result);
            this.connectSession2Events();
        end
        
        function startSession3(this)
            fprintf('启动会话3: 干扰防御测试\n');
            this.startSessionLayout(3, this.Session3TestFlow, this.Session3Result);
            this.connectSession3Events();
        end
        
        function startSessionLayout(this, sessionIdx, testFlowPanel, resultPanel)
            % STARTSESSIONLAYOUT 三会话共用 2x2 布局
            %   [ TestFlow | ViewerPanel ]
            %   [          ResultPanel             ]
            this.CurrentSession = sessionIdx;
            this.SessionStarted = true;
            
            this.hideAllPanels();
            testFlowPanel.FigureDocument.Visible = 1;
            this.ViewerPanel.FigureDocument.Visible = 1;
            resultPanel.FigureDocument.Visible = 1;
            
            update(testFlowPanel);
            update(this.ViewerPanel);
            update(resultPanel);
            
            appContainer = this.Window.AppContainer;
            tileOcc = this.Window.getTileOccupancy( ...
                testFlowPanel, this.ViewerPanel, resultPanel);
            
            appContainer.DocumentLayout = struct( ...
                'gridDimensions', struct('w', 2, 'h', 2), ...
                'columnWeights', [0.32 0.68], ...
                'rowWeights', [0.55 0.45], ...
                'tileCount', 3, ...
                'tileCoverage', [1 2; 3 3], ...   % 第 2 行 ResultPanel 跨两列
                'tileOccupancy', {tileOcc});
            
            drawnow;
        end
        
        function connectSession1Events(this)
            % 连接会话1的事件
            addlistener(this.Session1TestFlow, 'SignalImageReady', @(~,~) this.onSignalImageReady());
            addlistener(this.Session1TestFlow, 'AllStepsCompleted', @(~,~) this.onAllStepsCompleted());
        end
        
        function connectSession2Events(this)
            % 连接会话2的事件（验收流程）
            addlistener(this.Session2TestFlow, 'TestCellReady', @(~, evt) this.onSession2CellReady(evt));
            addlistener(this.Session2TestFlow, 'TestCompleted', @(~,~) this.onSession2TestCompleted());
            addlistener(this.Session2TestFlow, 'TestExportReady', @(~,~) this.onSession2ExportReady());
            addlistener(this.Session2TestFlow, 'AllStepsCompleted', @(~,~) this.onSession2AllStepsCompleted());
        end

        function onSession2CellReady(this, evt)
            % 单条样本完成 → 推送给 Session2Result 实时展示
            if ~isempty(this.Session2Result) && ismethod(this.Session2Result, 'onCellReady')
                this.Session2Result.onCellReady(evt);
            end
        end

        function onSession2ExportReady(~)
            fprintf('会话2: 测试报告已导出\n');
        end
        
        function connectSession3Events(this)
            % 连接会话3的事件
            addlistener(this.Session3TestFlow, 'SignalDisplayReady', @(~, evt) this.onSession3SignalReady(evt));
            addlistener(this.Session3TestFlow, 'JammingResultReady', @(~, evt) this.onSession3JamResultReady(evt));
            addlistener(this.Session3TestFlow, 'AllStepsCompleted', @(~,~) this.onSession3AllStepsCompleted());
        end
        
        function onSession3SignalReady(this, evt)
            % 会话3: 信号显示回调（TestFrameEventData.Payload）
            p = evt.Payload;
            this.Session3Result.displaySignal(p.Constellation, p.SignalType, p.IQData);
        end
        
        function onSession3JamResultReady(this, evt)
            % 会话3: 干扰结果回调（TestFrameEventData.Payload）
            p = evt.Payload;
            this.Session3Result.displayJammingResults(p.Constellation, p.Results);
        end
        
        function onSession3AllStepsCompleted(this)
            % 会话3: 所有步骤完成回调
            fprintf('会话3: 所有步骤已完成\n');
        end
        
        function onSession2TestCompleted(this)
            % 会话2: 测试完成回调
            fprintf('会话2: 测试完成\n');
        end
        
        function onSession2AllStepsCompleted(this)
            % 会话2: 所有步骤完成回调
            fprintf('会话2: 所有步骤已完成\n');
        end
        
        function onSignalImageReady(this)
            % 信号图像准备好的回调
            testFlow = this.Session1TestFlow;
            resultPanel = this.Session1Result;
            
            % 精简 6 步流程: 步骤3=Starlink STFT, 步骤4=OneWeb STFT
            if testFlow.CurrentStep == 3 && ~isempty(testFlow.StarlinkSignalImage)
                resultPanel.displayStarlinkSignal(testFlow.StarlinkSignalImage);
            elseif testFlow.CurrentStep == 4 && ~isempty(testFlow.OnewebSignalImage)
                resultPanel.displayOnewebSignal(testFlow.OnewebSignalImage);
            end
        end
        
        function onAllStepsCompleted(this)
            % 所有步骤完成的回调
            fprintf('会话1: 所有步骤已完成\n');
        end
        
        function hideAllPanels(this)
            panels = {this.SessionVisual, this.Session1TestFlow, this.Session1Result, ...
                      this.Session2TestFlow, this.Session2Result, ...
                      this.Session3TestFlow, this.Session3Result, ...
                      this.ViewerPanel};
            for i = 1:length(panels)
                if ~isempty(panels{i})
                    panels{i}.FigureDocument.Visible = 0;
                end
            end
        end
        
        function backToSessionSelect(this)
            % 返回会话选择界面
            this.hideAllPanels();
            this.CurrentSession = 0;
            this.SessionStarted = false;
            
            % 显示会话选择面板
            this.SessionVisual.FigureDocument.Visible = 1;
            
            appContainer = this.Window.AppContainer;
            appContainer.DocumentLayout = struct(...
                'gridDimensions', struct('w', 1, 'h', 1), ...
                'columnWeights', 1, ...
                'rowWeights', 1, ...
                'tileCount', 1, ...
                'tileCoverage', 1);
            
            this.SessionVisual.FigureDocument.Tile = 1;
        end
        
        function name = getName(~)
            name = '卫星终端认知与干扰防御平台';
        end
        
        function arrangeComponents(this, varargin) %#ok<INUSD>
            % 初始布局 - 显示会话选择界面
            this.hideAllPanels();
            
            this.SessionVisual.FigureDocument.Visible = 1;
            
            appContainer = this.Window.AppContainer;
            appContainer.DocumentLayout = struct(...
                'gridDimensions', struct('w', 1, 'h', 1), ...
                'columnWeights', 1, ...
                'rowWeights', 1, ...
                'tileCount', 1, ...
                'tileCoverage', 1);
            
            this.SessionVisual.FigureDocument.Tile = 1;
        end
    end
    
    methods (Hidden)
        function b = useMatlabTheme(~)
            b = true;
        end
        
        function pos = getDefaultPosition(~)
            pos = matlabshared.application.getInitialToolPosition([1600 950], 0.90);
        end
    end
    
    methods (Access = protected)
        function h = createToolstrip(this)
            % 创建工具条 - 参考官方 satcom.internal.linkbudgetApp.Toolstrip
            import matlab.ui.internal.toolstrip.*;
            
            h = TabGroup();
            h.Tag = 'CSSADigitalTwin';
            
            % 主标签页
            mainTab = h.addTab('数字孪生');
            mainTab.Tag = 'mainTab';
            
            % ===== 会话区 =====
            sessionSection = mainTab.addSection('会话');
            sessionSection.Tag = 'sessionSection';
            
            col1 = sessionSection.addColumn();
            
            % 新建会话按钮（带下拉菜单）- 参考官方 createFileSection
            newIcon = Icon.NEW_24;
            newSessionBtn = SplitButton('新建会话', newIcon);
            newSessionBtn.Tag = 'newSession';
            newSessionBtn.Description = '选择并启动测试会话';
            col1.add(newSessionBtn);
            
            % 下拉菜单
            popup = PopupList('IconSize', 24);
            
            % 会话1: 多种信号体制识别测试 - 使用搜索图标（频谱分析/体制识别）
            item1Icon = Icon.SEARCH_24;
            item1 = ListItem('多种信号体制识别测试', item1Icon);
            item1.ShowDescription = true;
            item1.Description = 'Starlink/OneWeb 双星座通信体制自动识别';
            item1.Tag = 'session1';
            item1.ItemPushedFcn = @(~,~) this.startSession1();
            
            % 会话2: 典型终端信号识别测试 - 使用运行图标（批量测试）
            item2Icon = Icon.RUN_24;
            item2 = ListItem('典型终端信号识别测试', item2Icon);
            item2.ShowDescription = true;
            item2.Description = '批量测试终端信号识别准确率';
            item2.Tag = 'session2';
            item2.ItemPushedFcn = @(~,~) this.startSession2();
            
            % 会话3: 干扰防御测试 - 使用导入图标（干扰注入/防御）
            item3Icon = Icon.IMPORT_24;
            item3 = ListItem('干扰防御测试', item3Icon);
            item3.ShowDescription = true;
            item3.Description = '智能干扰策略与感知防御效果评估';
            item3.Tag = 'session3';
            item3.ItemPushedFcn = @(~,~) this.startSession3();
            
            popup.add(item1);
            popup.add(item2);
            popup.add(item3);
            newSessionBtn.Popup = popup;
            
            % 默认点击行为
            newSessionBtn.ButtonPushedFcn = @(~,~) this.startSession1();
            
            % ===== 导航区 =====
            navSection = mainTab.addSection('导航');
            navSection.Tag = 'navSection';
            
            col2 = navSection.addColumn();
            
            % 返回按钮
            backIcon = Icon.UNDO_16;
            backBtn = Button('返回选择', backIcon);
            backBtn.Tag = 'backBtn';
            backBtn.Description = '返回会话选择界面';
            backBtn.ButtonPushedFcn = @(~,~) this.backToSessionSelect();
            col2.add(backBtn);
        end
        
        function c = createDefaultComponents(this)
            % 创建所有组件
            
            % 会话选择面板（初始显示）
            this.SessionVisual = twin.app.SessionVisual(this);
            
            % 会话1
            this.Session1TestFlow = twin.app.TestFlowPanel(this);
            this.Session1Result = twin.app.RecognitionResultPanel(this);
            
            % 会话2
            this.Session2TestFlow = twin.app.Session2TestFlowPanel(this);
            this.Session2Result = twin.app.Session2ResultPanel(this);
            
            % 会话3
            this.Session3TestFlow = twin.app.Session3TestFlowPanel(this);
            this.Session3Result = twin.app.Session3ResultPanel(this);
            
            % 共用面板
            this.ViewerPanel = twin.app.ViewerPanel(this);
            
            % 初始隐藏所有面板
            this.SessionVisual.FigureDocument.Visible = 0;
            this.Session1TestFlow.FigureDocument.Visible = 0;
            this.Session1Result.FigureDocument.Visible = 0;
            this.Session2TestFlow.FigureDocument.Visible = 0;
            this.Session2Result.FigureDocument.Visible = 0;
            this.Session3TestFlow.FigureDocument.Visible = 0;
            this.Session3Result.FigureDocument.Visible = 0;
            this.ViewerPanel.FigureDocument.Visible = 0;
            
            c = [this.SessionVisual ...
                 this.Session1TestFlow this.Session1Result ...
                 this.Session2TestFlow this.Session2Result ...
                 this.Session3TestFlow this.Session3Result ...
                 this.ViewerPanel];
        end
    end
end
