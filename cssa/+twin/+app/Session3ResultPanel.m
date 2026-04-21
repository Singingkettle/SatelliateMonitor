classdef Session3ResultPanel < matlabshared.application.Component
    % SESSION3RESULTPANEL 会话3：干扰防御测试 - 结果显示面板
    %
    %   左侧：干扰效果图 (Starlink | OneWeb)
    %         每栏：干净信号、加噪信号、干扰后信号
    %   右侧：干扰性能评估 (Starlink | OneWeb)
    
    properties (Hidden)
        MainGrid
        
        % 左侧：干扰效果图
        EffectPanel
        StarlinkEffectAxes      % 3个axes: clean, noisy, jammed
        OnewebEffectAxes        % 3个axes: clean, noisy, jammed
        
        % 右侧：干扰性能评估
        EvalPanel
        StarlinkEvalAxes
        OnewebEvalAxes
        
        % 数据存储
        StarlinkCleanIQ
        StarlinkNoisyIQ
        StarlinkJammedIQ
        OnewebCleanIQ
        OnewebNoisyIQ
        OnewebJammedIQ
    end
    
    properties (Constant, Hidden)
        BgColor = [0.1 0.1 0.12]
        PanelColor = [0.12 0.12 0.14]
        TextColor = [0.85 0.85 0.85]
        AccentColor = [0.2 0.6 1.0]
    end
    
    methods
        function this = Session3ResultPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
        end
        
        function name = getName(~)
            name = '干扰防御测试结果';
        end
        
        function tag = getTag(~)
            tag = 'session3result';
        end
        
        function update(this)
            hFig = this.Figure;
            delete(hFig.Children);
            hFig.Color = this.BgColor;
            
            this.createUI(hFig);
        end
        
        function createUI(this, parent)
            % 主网格: 左右两栏
            this.MainGrid = uigridlayout(parent, [1, 2]);
            this.MainGrid.ColumnWidth = {'1x', '1x'};
            this.MainGrid.Padding = [10 10 10 10];
            this.MainGrid.ColumnSpacing = 10;
            this.MainGrid.BackgroundColor = this.BgColor;
            this.MainGrid.Scrollable = 'on';
            
            % 左侧：干扰效果图
            this.createEffectPanel();
            
            % 右侧：干扰性能评估
            this.createEvalPanel();
        end
        
        function createEffectPanel(this)
            % 干扰效果图面板
            this.EffectPanel = uipanel(this.MainGrid, ...
                'Title', '干扰效果图', ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'ForegroundColor', this.TextColor, ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'line', ...
                'HighlightColor', [0.3 0.3 0.35]);
            
            % 左右两栏：Starlink | OneWeb
            effectGrid = uigridlayout(this.EffectPanel, [1, 2]);
            effectGrid.ColumnWidth = {'1x', '1x'};
            effectGrid.Padding = [5 5 5 5];
            effectGrid.ColumnSpacing = 10;
            effectGrid.BackgroundColor = this.PanelColor;
            
            % 4行标签: 原始信号、加噪信号、STAD干扰、STSD干扰
            labels = {'原始信号 (通信卫星接收)', '加噪信号', 'STAD干扰 (同步触发自适应)', 'STSD干扰 (同步触发扫频)'};
            
            % Starlink栏
            starlinkPanel = uipanel(effectGrid, ...
                'Title', 'Starlink', ...
                'FontSize', 11, ...
                'ForegroundColor', [0.4 0.8 1.0], ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'none');
            
            starlinkGrid = uigridlayout(starlinkPanel, [4, 1]);
            starlinkGrid.RowHeight = {'1x', '1x', '1x', '1x'};
            starlinkGrid.Padding = [2 2 2 2];
            starlinkGrid.RowSpacing = 3;
            starlinkGrid.BackgroundColor = this.PanelColor;
            
            this.StarlinkEffectAxes = cell(4, 1);
            for i = 1:4
                axPanel = uipanel(starlinkGrid, ...
                    'Title', labels{i}, ...
                    'FontSize', 8, ...
                    'ForegroundColor', [0.7 0.7 0.7], ...
                    'BackgroundColor', [0.08 0.08 0.1], ...
                    'BorderType', 'none');
                ax = uiaxes(axPanel, ...
                    'Units', 'normalized', ...
                    'Position', [0.05 0.05 0.9 0.85], ...
                    'Color', [0.05 0.05 0.08], ...
                    'XColor', [0.5 0.5 0.5], ...
                    'YColor', [0.5 0.5 0.5]);
                ax.XTickLabel = {};
                ax.YTickLabel = {};
                title(ax, '', 'Color', this.TextColor);
                this.StarlinkEffectAxes{i} = ax;
            end
            
            % OneWeb栏
            onewebPanel = uipanel(effectGrid, ...
                'Title', 'OneWeb', ...
                'FontSize', 11, ...
                'ForegroundColor', [1.0 0.6 0.4], ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'none');
            
            onewebGrid = uigridlayout(onewebPanel, [4, 1]);
            onewebGrid.RowHeight = {'1x', '1x', '1x', '1x'};
            onewebGrid.Padding = [2 2 2 2];
            onewebGrid.RowSpacing = 3;
            onewebGrid.BackgroundColor = this.PanelColor;
            
            this.OnewebEffectAxes = cell(4, 1);
            for i = 1:4
                axPanel = uipanel(onewebGrid, ...
                    'Title', labels{i}, ...
                    'FontSize', 8, ...
                    'ForegroundColor', [0.7 0.7 0.7], ...
                    'BackgroundColor', [0.08 0.08 0.1], ...
                    'BorderType', 'none');
                ax = uiaxes(axPanel, ...
                    'Units', 'normalized', ...
                    'Position', [0.05 0.05 0.9 0.85], ...
                    'Color', [0.05 0.05 0.08], ...
                    'XColor', [0.5 0.5 0.5], ...
                    'YColor', [0.5 0.5 0.5]);
                ax.XTickLabel = {};
                ax.YTickLabel = {};
                title(ax, '', 'Color', this.TextColor);
                this.OnewebEffectAxes{i} = ax;
            end
            
            % 显示占位符
            this.showPlaceholders();
        end
        
        function createEvalPanel(this)
            % 干扰性能评估面板
            this.EvalPanel = uipanel(this.MainGrid, ...
                'Title', '干扰性能评估', ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'ForegroundColor', this.TextColor, ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'line', ...
                'HighlightColor', [0.3 0.3 0.35]);
            
            % 左右两栏
            evalGrid = uigridlayout(this.EvalPanel, [1, 2]);
            evalGrid.ColumnWidth = {'1x', '1x'};
            evalGrid.Padding = [5 5 5 5];
            evalGrid.ColumnSpacing = 10;
            evalGrid.BackgroundColor = this.PanelColor;
            
            % Starlink评估
            starlinkEvalPanel = uipanel(evalGrid, ...
                'Title', 'Starlink 干扰效果', ...
                'FontSize', 11, ...
                'ForegroundColor', [0.4 0.8 1.0], ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'none');
            
            this.StarlinkEvalAxes = uiaxes(starlinkEvalPanel, ...
                'Units', 'normalized', ...
                'Position', [0.1 0.1 0.85 0.8], ...
                'Color', [0.05 0.05 0.08], ...
                'XColor', this.TextColor, ...
                'YColor', this.TextColor);
            title(this.StarlinkEvalAxes, '等待评估...', 'Color', this.TextColor);
            xlabel(this.StarlinkEvalAxes, '干扰策略', 'Color', this.TextColor);
            ylabel(this.StarlinkEvalAxes, 'BER', 'Color', this.TextColor);
            
            % OneWeb评估
            onewebEvalPanel = uipanel(evalGrid, ...
                'Title', 'OneWeb 干扰效果', ...
                'FontSize', 11, ...
                'ForegroundColor', [1.0 0.6 0.4], ...
                'BackgroundColor', this.PanelColor, ...
                'BorderType', 'none');
            
            this.OnewebEvalAxes = uiaxes(onewebEvalPanel, ...
                'Units', 'normalized', ...
                'Position', [0.1 0.1 0.85 0.8], ...
                'Color', [0.05 0.05 0.08], ...
                'XColor', this.TextColor, ...
                'YColor', this.TextColor);
            title(this.OnewebEvalAxes, '等待评估...', 'Color', this.TextColor);
            xlabel(this.OnewebEvalAxes, '干扰策略', 'Color', this.TextColor);
            ylabel(this.OnewebEvalAxes, 'BER', 'Color', this.TextColor);
        end
        
        function showPlaceholders(this)
            % 显示占位符
            for i = 1:4
                if ~isempty(this.StarlinkEffectAxes) && numel(this.StarlinkEffectAxes) >= i ...
                        && ~isempty(this.StarlinkEffectAxes{i})
                    cla(this.StarlinkEffectAxes{i});
                    text(this.StarlinkEffectAxes{i}, 0.5, 0.5, '等待信号生成...', ...
                        'HorizontalAlignment', 'center', ...
                        'Color', [0.5 0.5 0.5], ...
                        'FontSize', 10, ...
                        'Units', 'normalized');
                end
                if ~isempty(this.OnewebEffectAxes) && numel(this.OnewebEffectAxes) >= i ...
                        && ~isempty(this.OnewebEffectAxes{i})
                    cla(this.OnewebEffectAxes{i});
                    text(this.OnewebEffectAxes{i}, 0.5, 0.5, '等待信号生成...', ...
                        'HorizontalAlignment', 'center', ...
                        'Color', [0.5 0.5 0.5], ...
                        'FontSize', 10, ...
                        'Units', 'normalized');
                end
            end
        end
        
        function displaySignal(this, constellation, signalType, iqData)
            % 显示信号
            %   constellation: 'starlink' 或 'oneweb'
            %   signalType: 'clean', 'noisy', 'jammed'
            %   iqData: IQ数据 (jammed时为struct，包含各策略)
            
            fprintf('[Session3Result] displaySignal: %s, %s, 数据长度=%d\n', ...
                constellation, signalType, numel(iqData));
            
            if strcmpi(constellation, 'starlink')
                axesArray = this.StarlinkEffectAxes;
            else
                axesArray = this.OnewebEffectAxes;
            end
            
            % 存储数据
            switch lower(signalType)
                case 'clean'
                    if strcmpi(constellation, 'starlink')
                        this.StarlinkCleanIQ = iqData;
                    else
                        this.OnewebCleanIQ = iqData;
                    end
                case 'noisy'
                    if strcmpi(constellation, 'starlink')
                        this.StarlinkNoisyIQ = iqData;
                    else
                        this.OnewebNoisyIQ = iqData;
                    end
                case 'jammed'
                    if strcmpi(constellation, 'starlink')
                        this.StarlinkJammedIQ = iqData;
                    else
                        this.OnewebJammedIQ = iqData;
                    end
            end
            
            % 收集所有信号用于计算统一的Y轴范围
            allSignals = {};
            if strcmpi(constellation, 'starlink')
                if ~isempty(this.StarlinkCleanIQ), allSignals{end+1} = this.StarlinkCleanIQ; end
                if ~isempty(this.StarlinkNoisyIQ), allSignals{end+1} = this.StarlinkNoisyIQ; end
                if ~isempty(this.StarlinkJammedIQ) && isstruct(this.StarlinkJammedIQ)
                    fns = fieldnames(this.StarlinkJammedIQ);
                    for k = 1:length(fns)
                        allSignals{end+1} = this.StarlinkJammedIQ.(fns{k}); 
                    end
                end
            else
                if ~isempty(this.OnewebCleanIQ), allSignals{end+1} = this.OnewebCleanIQ; end
                if ~isempty(this.OnewebNoisyIQ), allSignals{end+1} = this.OnewebNoisyIQ; end
                if ~isempty(this.OnewebJammedIQ) && isstruct(this.OnewebJammedIQ)
                    fns = fieldnames(this.OnewebJammedIQ);
                    for k = 1:length(fns)
                        allSignals{end+1} = this.OnewebJammedIQ.(fns{k}); 
                    end
                end
            end
            
            % 计算统一的Y轴范围
            yMax = 0;
            for k = 1:length(allSignals)
                sig = double(allSignals{k}(:));
                maxVal = max(abs([real(sig); imag(sig)]));
                if maxVal > yMax
                    yMax = maxVal;
                end
            end
            yLimits = [-yMax*1.1, yMax*1.1];
            if yMax == 0
                yLimits = [-1, 1];
            end
            
            % 绘制所有信号（使用统一的Y轴范围）
            colors = {[0.3 0.9 0.4], [0.9 0.9 0.3], [1.0 0.5 0.2], [1.0 0.3 0.3]};
            titles = {'原始信号', '加噪信号', 'STAD干扰', 'STSD干扰'};
            
            % 第1行：原始信号
            if strcmpi(constellation, 'starlink')
                cleanIQ = this.StarlinkCleanIQ;
            else
                cleanIQ = this.OnewebCleanIQ;
            end
            if ~isempty(cleanIQ)
                this.plotIQWaveform(axesArray{1}, cleanIQ, titles{1}, colors{1}, yLimits);
            end
            
            % 第2行：加噪信号
            if strcmpi(constellation, 'starlink')
                noisyIQ = this.StarlinkNoisyIQ;
            else
                noisyIQ = this.OnewebNoisyIQ;
            end
            if ~isempty(noisyIQ)
                this.plotIQWaveform(axesArray{2}, noisyIQ, titles{2}, colors{2}, yLimits);
            end
            
            % 第3、4行：干扰信号
            if strcmpi(constellation, 'starlink')
                jammedIQ = this.StarlinkJammedIQ;
            else
                jammedIQ = this.OnewebJammedIQ;
            end
            if ~isempty(jammedIQ) && isstruct(jammedIQ)
                if isfield(jammedIQ, 'STAD')
                    this.plotIQWaveform(axesArray{3}, jammedIQ.STAD, titles{3}, colors{3}, yLimits);
                elseif isfield(jammedIQ, 'white')
                    this.plotIQWaveform(axesArray{3}, jammedIQ.white, 'White干扰', colors{3}, yLimits);
                end
                if isfield(jammedIQ, 'STSD')
                    this.plotIQWaveform(axesArray{4}, jammedIQ.STSD, titles{4}, colors{4}, yLimits);
                end
            end
        end
        
        function plotIQWaveform(~, ax, iqData, titleStr, color, yLimits)
            % 绘制IQ时域波形（统一Y轴范围）
            cla(ax);
            
            if isempty(iqData)
                text(ax, 0.5, 0.5, '无数据', ...
                    'HorizontalAlignment', 'center', ...
                    'Color', [0.5 0.5 0.5], ...
                    'FontSize', 10, ...
                    'Units', 'normalized');
                return;
            end
            
            % 确保是列向量
            iqData = double(iqData(:));
            totalLen = length(iqData);
            
            % 智能选取有信号的区域（找到功率较大的部分）
            displayLen = min(2000, totalLen);  % 显示2000个点
            
            % 计算滑动窗口功率，找到功率最大的区域
            windowSize = displayLen;
            if totalLen > windowSize * 2
                % 用稀疏采样估计功率分布
                numBlocks = min(100, floor(totalLen / windowSize));
                blockPower = zeros(numBlocks, 1);
                for i = 1:numBlocks
                    startIdx = round((i-1) * (totalLen - windowSize) / (numBlocks - 1)) + 1;
                    endIdx = min(startIdx + windowSize - 1, totalLen);
                    blockPower(i) = mean(abs(iqData(startIdx:endIdx)).^2);
                end
                [~, maxBlock] = max(blockPower);
                startIdx = round((maxBlock-1) * (totalLen - windowSize) / (numBlocks - 1)) + 1;
            else
                startIdx = 1;
            end
            
            endIdx = min(startIdx + displayLen - 1, totalLen);
            displayData = iqData(startIdx:endIdx);
            N = length(displayData);
            t = (0:N-1)';  % 采样点索引
            
            % 绘制I和Q分量
            hold(ax, 'on');
            plot(ax, t, real(displayData), 'Color', color, 'LineWidth', 0.8);
            plot(ax, t, imag(displayData), 'Color', color * 0.6 + [0.2 0.2 0.2], 'LineWidth', 0.8, 'LineStyle', '--');
            hold(ax, 'off');
            
            xlim(ax, [0 N]);
            
            % 使用传入的统一Y轴范围
            if nargin >= 6 && ~isempty(yLimits)
                ylim(ax, yLimits);
            else
                % 自动调整Y轴范围
                maxVal = max(abs([real(displayData); imag(displayData)]));
                if maxVal > 0
                    ylim(ax, [-maxVal*1.1 maxVal*1.1]);
                end
            end
            
            title(ax, titleStr, 'Color', [0.85 0.85 0.85], 'FontSize', 9);
            ax.XTickLabel = {};
            ax.YTickLabel = {};
            grid(ax, 'on');
            ax.GridColor = [0.3 0.3 0.3];
            ax.GridAlpha = 0.5;
            
            % 添加图例说明
            legend(ax, {'I', 'Q'}, 'TextColor', [0.7 0.7 0.7], ...
                'Color', [0.1 0.1 0.12], 'EdgeColor', [0.3 0.3 0.3], ...
                'Location', 'northeast', 'FontSize', 7);
        end
        
        function displayJammingResults(this, constellation, results)
            % 显示干扰评估结果 - BER vs JSR 曲线
            
            if strcmpi(constellation, 'starlink')
                ax = this.StarlinkEvalAxes;
                titleColor = [0.4 0.8 1.0];
            else
                ax = this.OnewebEvalAxes;
                titleColor = [1.0 0.6 0.4];
            end
            
            cla(ax);
            
            if isempty(results) || ~isfield(results, 'strategies')
                text(ax, 0.5, 0.5, '无评估数据', ...
                    'HorizontalAlignment', 'center', ...
                    'Color', [0.5 0.5 0.5], ...
                    'FontSize', 10, ...
                    'Units', 'normalized');
                return;
            end
            
            % 获取JSR和BER数据
            if isfield(results, 'JSR_dB_array') && isfield(results, 'berCurves')
                % 有完整的曲线数据
                JSR_dB = results.JSR_dB_array;
                berCurves = results.berCurves;
            else
                % 只有单点数据，无法绘制曲线
                text(ax, 0.5, 0.5, '等待多JSR评估...', ...
                    'HorizontalAlignment', 'center', ...
                    'Color', [0.5 0.5 0.5], ...
                    'FontSize', 10, ...
                    'Units', 'normalized');
                return;
            end
            
            strategies = results.strategies;
            nStrategies = length(strategies);
            
            % 颜色方案
            colors = [
                0.2 0.6 1.0;   % white - 蓝色
                1.0 0.5 0.2;   % STAD - 橙色
                1.0 0.3 0.3;   % STSD - 红色
            ];
            if nStrategies > 3
                colors = [colors; lines(nStrategies - 3)];
            end
            
            % 绘制BER曲线
            hold(ax, 'on');
            markers = {'-o', '-s', '-d'};
            for s = 1:nStrategies
                stratName = strategies{s};
                if isfield(berCurves, stratName)
                    berData = berCurves.(stratName);
                    plot(ax, JSR_dB, berData, markers{min(s, 3)}, ...
                        'Color', colors(min(s, size(colors, 1)), :), ...
                        'LineWidth', 2, ...
                        'MarkerFaceColor', colors(min(s, size(colors, 1)), :), ...
                        'MarkerSize', 6, ...
                        'DisplayName', stratName);
                end
            end
            
            % BER阈值线
            yline(ax, 0.10, 'r--', 'LineWidth', 1.5, 'DisplayName', '系统崩溃(10%)');
            yline(ax, 0.05, 'm-.', 'LineWidth', 1.2, 'DisplayName', '严重降级(5%)');
            yline(ax, 0.01, 'k:', 'LineWidth', 1.2, 'DisplayName', '性能下降(1%)');
            
            hold(ax, 'off');
            
            % 设置坐标轴
            xlabel(ax, 'JSR (dB)', 'Color', [0.85 0.85 0.85], 'FontSize', 10);
            ylabel(ax, 'BER', 'Color', [0.85 0.85 0.85], 'FontSize', 10);
            title(ax, sprintf('%s 干扰效果曲线', upper(constellation)), ...
                'Color', titleColor, 'FontSize', 11);
            
            xlim(ax, [min(JSR_dB)-2, max(JSR_dB)+2]);
            ylim(ax, [0, 0.55]);
            
            grid(ax, 'on');
            ax.GridColor = [0.3 0.3 0.3];
            ax.GridAlpha = 0.5;
            ax.Color = [0.05 0.05 0.08];
            ax.XColor = [0.85 0.85 0.85];
            ax.YColor = [0.85 0.85 0.85];
            
            % 添加图例
            legend(ax, 'Location', 'northwest', 'TextColor', [0.8 0.8 0.8], ...
                'Color', [0.1 0.1 0.12], 'EdgeColor', [0.3 0.3 0.3], 'FontSize', 7);
        end
        
        function reset(this)
            % 重置面板，清除所有显示
            
            % 清除存储的数据
            this.StarlinkCleanIQ = [];
            this.StarlinkNoisyIQ = [];
            this.StarlinkJammedIQ = [];
            this.OnewebCleanIQ = [];
            this.OnewebNoisyIQ = [];
            this.OnewebJammedIQ = [];
            
            % 清除效果图（4行）
            for i = 1:4
                if ~isempty(this.StarlinkEffectAxes) && numel(this.StarlinkEffectAxes) >= i ...
                        && ~isempty(this.StarlinkEffectAxes{i}) && isvalid(this.StarlinkEffectAxes{i})
                    cla(this.StarlinkEffectAxes{i});
                    text(this.StarlinkEffectAxes{i}, 0.5, 0.5, '等待信号生成...', ...
                        'HorizontalAlignment', 'center', ...
                        'Color', [0.5 0.5 0.5], ...
                        'FontSize', 10, ...
                        'Units', 'normalized');
                end
                if ~isempty(this.OnewebEffectAxes) && numel(this.OnewebEffectAxes) >= i ...
                        && ~isempty(this.OnewebEffectAxes{i}) && isvalid(this.OnewebEffectAxes{i})
                    cla(this.OnewebEffectAxes{i});
                    text(this.OnewebEffectAxes{i}, 0.5, 0.5, '等待信号生成...', ...
                        'HorizontalAlignment', 'center', ...
                        'Color', [0.5 0.5 0.5], ...
                        'FontSize', 10, ...
                        'Units', 'normalized');
                end
            end
            
            % 清除评估图
            if ~isempty(this.StarlinkEvalAxes) && isvalid(this.StarlinkEvalAxes)
                cla(this.StarlinkEvalAxes);
                title(this.StarlinkEvalAxes, '等待评估...', 'Color', this.TextColor);
            end
            if ~isempty(this.OnewebEvalAxes) && isvalid(this.OnewebEvalAxes)
                cla(this.OnewebEvalAxes);
                title(this.OnewebEvalAxes, '等待评估...', 'Color', this.TextColor);
            end
        end
    end
end

