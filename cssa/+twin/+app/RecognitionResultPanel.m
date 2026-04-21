classdef RecognitionResultPanel < matlabshared.application.Component
    % RECOGNITIONRESULTPANEL 通信体制识别结果演示面板
    %
    %   显示：
    %   - 左侧: Starlink (上: 原始STFT, 下: 检测结果)
    %   - 右侧: OneWeb (上: 原始STFT, 下: 检测结果)
    %   - 无坐标轴，图像铺满
    
    properties (Hidden)
        MainGrid
        
        % Starlink 图像显示
        StarlinkOriginalAxes    % 原始 STFT
        StarlinkResultAxes      % 检测结果
        StarlinkOriginalImage
        StarlinkResultImage
        
        % OneWeb 图像显示
        OnewebOriginalAxes      % 原始 STFT
        OnewebResultAxes        % 检测结果
        OnewebOriginalImage
        OnewebResultImage
        
        % 状态显示
        StatusPanel
        StatusLabel
        
        % 颜色配置
        BgColor = [0.08 0.08 0.10]
        TextColor = [0.85 0.85 0.85]
        StarlinkColor = [1.0 0.6 0.2]   % 橙色
        OnewebColor = [0.2 0.8 0.6]     % 青绿色
        
        % 状态
        IsInitialized = false
    end
    
    methods
        function this = RecognitionResultPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
        end
        
        function name = getName(~)
            name = '体制识别结果';
        end
        
        function tag = getTag(~)
            tag = 'recognitionresult';
        end
        
        function update(this)
            createUI(this);
        end
        
        function createUI(this)
            % 创建识别结果界面
            clf(this.Figure);
            this.Figure.Color = this.BgColor;
            
            % 主布局: 左右两栏 + 底部状态栏
            this.MainGrid = uigridlayout(this.Figure, [2, 2]);
            this.MainGrid.RowHeight = {'1x', 30};
            this.MainGrid.ColumnWidth = {'1x', '1x'};
            this.MainGrid.Padding = [5 5 5 5];
            this.MainGrid.RowSpacing = 5;
            this.MainGrid.ColumnSpacing = 10;
            this.MainGrid.BackgroundColor = this.BgColor;
            this.MainGrid.Scrollable = 'on';
            
            % ========== Starlink 面板 (上方) ==========
            starlinkPanel = uipanel(this.MainGrid, ...
                'Title', 'Starlink 信号识别', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.StarlinkColor, ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'BorderType', 'line', ...
                'BorderColor', this.StarlinkColor);
            starlinkPanel.Layout.Row = 1;
            starlinkPanel.Layout.Column = 1;
            
            % Starlink 内部布局: 左右两个图像
            starlinkLayout = uigridlayout(starlinkPanel, [1, 2]);
            starlinkLayout.ColumnWidth = {'1x', '1x'};
            starlinkLayout.Padding = [2 2 2 2];
            starlinkLayout.ColumnSpacing = 5;
            starlinkLayout.BackgroundColor = this.BgColor;
            
            % Starlink 原始 STFT (左)
            starlinkOrigPanel = uipanel(starlinkLayout, ...
                'Title', '原始 STFT', ...
                'BackgroundColor', [0.05 0.05 0.07], ...
                'ForegroundColor', [0.7 0.7 0.7], ...
                'FontSize', 10, ...
                'BorderType', 'none');
            this.StarlinkOriginalAxes = uiaxes(starlinkOrigPanel, ...
                'Position', [0 0 1 1], ...
                'Units', 'normalized');
            this.setupImageAxes(this.StarlinkOriginalAxes);
            
            % Starlink 检测结果 (右)
            starlinkResultPanel = uipanel(starlinkLayout, ...
                'Title', '检测结果', ...
                'BackgroundColor', [0.05 0.05 0.07], ...
                'ForegroundColor', this.StarlinkColor, ...
                'FontSize', 10, ...
                'BorderType', 'none');
            this.StarlinkResultAxes = uiaxes(starlinkResultPanel, ...
                'Position', [0 0 1 1], ...
                'Units', 'normalized');
            this.setupImageAxes(this.StarlinkResultAxes);
            
            % ========== OneWeb 面板 (下方) ==========
            onewebPanel = uipanel(this.MainGrid, ...
                'Title', 'OneWeb 信号识别', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.OnewebColor, ...
                'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'BorderType', 'line', ...
                'BorderColor', this.OnewebColor);
            onewebPanel.Layout.Row = 1;
            onewebPanel.Layout.Column = 2;
            
            % OneWeb 内部布局: 左右两个图像
            onewebLayout = uigridlayout(onewebPanel, [1, 2]);
            onewebLayout.ColumnWidth = {'1x', '1x'};
            onewebLayout.Padding = [2 2 2 2];
            onewebLayout.ColumnSpacing = 5;
            onewebLayout.BackgroundColor = this.BgColor;
            
            % OneWeb 原始 STFT (左)
            onewebOrigPanel = uipanel(onewebLayout, ...
                'Title', '原始 STFT', ...
                'BackgroundColor', [0.05 0.05 0.07], ...
                'ForegroundColor', [0.7 0.7 0.7], ...
                'FontSize', 10, ...
                'BorderType', 'none');
            this.OnewebOriginalAxes = uiaxes(onewebOrigPanel, ...
                'Position', [0 0 1 1], ...
                'Units', 'normalized');
            this.setupImageAxes(this.OnewebOriginalAxes);
            
            % OneWeb 检测结果 (右)
            onewebResultPanel = uipanel(onewebLayout, ...
                'Title', '检测结果', ...
                'BackgroundColor', [0.05 0.05 0.07], ...
                'ForegroundColor', this.OnewebColor, ...
                'FontSize', 10, ...
                'BorderType', 'none');
            this.OnewebResultAxes = uiaxes(onewebResultPanel, ...
                'Position', [0 0 1 1], ...
                'Units', 'normalized');
            this.setupImageAxes(this.OnewebResultAxes);
            
            % ========== 状态栏 (底部跨两列) ==========
            this.StatusPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', [0.06 0.06 0.08], ...
                'BorderType', 'none');
            this.StatusPanel.Layout.Row = 2;
            this.StatusPanel.Layout.Column = [1 2];
            
            statusLayout = uigridlayout(this.StatusPanel, [1, 2]);
            statusLayout.ColumnWidth = {'1x', 'fit'};
            statusLayout.Padding = [10 5 10 5];
            statusLayout.BackgroundColor = [0.06 0.06 0.08];
            
            this.StatusLabel = uilabel(statusLayout, ...
                'Text', '等待测试流程启动...', ...
                'FontSize', 11, ...
                'FontColor', this.TextColor, ...
                'BackgroundColor', [0.06 0.06 0.08]);
            
            uilabel(statusLayout, ...
                'Text', '卫星终端认知与干扰防御平台', ...
                'FontSize', 10, ...
                'FontColor', [0.4 0.4 0.4], ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', [0.06 0.06 0.08]);
            
            this.IsInitialized = true;
            
            % 显示占位图
            this.showPlaceholder();
        end
        
        function setupImageAxes(~, ax)
            % 设置图像坐标轴样式（无坐标轴，铺满）
            ax.Visible = 'off';
            ax.XTick = [];
            ax.YTick = [];
            ax.XColor = 'none';
            ax.YColor = 'none';
            ax.Color = [0.05 0.05 0.07];
            ax.Box = 'off';
            ax.Position = [0 0 1 1];
            ax.Units = 'normalized';
            axis(ax, 'off');
            ax.YDir = 'reverse';  % 图像坐标系：Y轴向下
        end
        
        function showPlaceholder(this)
            % 显示占位图
            if ~this.IsInitialized
                return;
            end
            
            % Starlink 原始占位
            cla(this.StarlinkOriginalAxes);
            text(this.StarlinkOriginalAxes, 0.5, 0.5, ...
                '等待步骤 3（Starlink 监测信号）', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.4 0.4 0.4]);
            
            % Starlink 结果占位
            cla(this.StarlinkResultAxes);
            text(this.StarlinkResultAxes, 0.5, 0.5, ...
                '等待检测', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.4 0.4 0.4]);
            
            % OneWeb 原始占位
            cla(this.OnewebOriginalAxes);
            text(this.OnewebOriginalAxes, 0.5, 0.5, ...
                '等待步骤 4（OneWeb 监测信号）', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.4 0.4 0.4]);
            
            % OneWeb 结果占位
            cla(this.OnewebResultAxes);
            text(this.OnewebResultAxes, 0.5, 0.5, ...
                '等待检测', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.4 0.4 0.4]);
        end
        
        function displayStarlinkSignal(this, img)
            % 显示 Starlink 原始 STFT（检测结果区域等待步骤 5 推理）
            if ~this.IsInitialized || isempty(img)
                return;
            end
            
            this.StarlinkOriginalImage = img;
            
            % 显示原始 STFT（无坐标轴，铺满）
            cla(this.StarlinkOriginalAxes);
            this.displayImageFull(this.StarlinkOriginalAxes, img);
            
            % 检测结果区域显示等待提示
            cla(this.StarlinkResultAxes);
            text(this.StarlinkResultAxes, 0.5, 0.5, ...
                '等待步骤 5（模型推理）', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.5 0.5 0.5]);
            
            this.updateStatus('Starlink 信号已加载，等待感知模型处理...');
        end
        
        function displayOnewebSignal(this, img)
            % 显示 OneWeb 原始 STFT（检测结果区域等待步骤 5 推理）
            if ~this.IsInitialized || isempty(img)
                return;
            end
            
            this.OnewebOriginalImage = img;
            
            % 显示原始 STFT（无坐标轴，铺满）
            cla(this.OnewebOriginalAxes);
            this.displayImageFull(this.OnewebOriginalAxes, img);
            
            % 检测结果区域显示等待提示
            cla(this.OnewebResultAxes);
            text(this.OnewebResultAxes, 0.5, 0.5, ...
                '等待步骤 5（模型推理）', ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontSize', 14, ...
                'Color', [0.5 0.5 0.5]);
            
            this.updateStatus('OneWeb 信号已加载，等待感知模型处理...');
        end
        
        function displayStarlinkDetection(this, img, bboxes, labels, scores)
            % 显示 Starlink 检测结果（带检测框）
            if ~this.IsInitialized || isempty(img)
                return;
            end
            
            this.StarlinkResultImage = img;
            
            cla(this.StarlinkResultAxes);
            this.displayImageFull(this.StarlinkResultAxes, img);
            hold(this.StarlinkResultAxes, 'on');
            
            % 绘制检测框
            if nargin >= 3 && ~isempty(bboxes)
                for i = 1:size(bboxes, 1)
                    bbox = bboxes(i, :);
                    rectangle(this.StarlinkResultAxes, 'Position', bbox, ...
                        'EdgeColor', this.StarlinkColor, ...
                        'LineWidth', 2);
                    
                    % 标签
                    if nargin >= 4 && i <= numel(labels)
                        labelText = labels{i};
                        % 替换标签：starlink -> 星链体制，oneweb -> 一网体制
                        labelStr = lower(char(labelText));
                        if contains(labelStr, 'starlink')
                            labelText = '星链体制';
                        elseif contains(labelStr, 'oneweb')
                            labelText = '一网体制';
                        end
                        if nargin >= 5 && i <= numel(scores)
                            labelText = sprintf('%s (%.1f%%)', labelText, scores(i)*100);
                        end
                        text(this.StarlinkResultAxes, bbox(1), bbox(2) - 5, ...
                            labelText, ...
                            'Color', [1 1 1], ...
                            'FontSize', 10, ...
                            'FontWeight', 'bold', ...
                            'BackgroundColor', this.StarlinkColor);
                    end
                end
            end
            
            hold(this.StarlinkResultAxes, 'off');
            axis(this.StarlinkResultAxes, 'off');
        end
        
        function displayOnewebDetection(this, img, bboxes, labels, scores)
            % 显示 OneWeb 检测结果（带检测框）
            if ~this.IsInitialized || isempty(img)
                return;
            end
            
            this.OnewebResultImage = img;
            
            cla(this.OnewebResultAxes);
            this.displayImageFull(this.OnewebResultAxes, img);
            hold(this.OnewebResultAxes, 'on');
            
            % 绘制检测框
            if nargin >= 3 && ~isempty(bboxes)
                for i = 1:size(bboxes, 1)
                    bbox = bboxes(i, :);
                    rectangle(this.OnewebResultAxes, 'Position', bbox, ...
                        'EdgeColor', this.OnewebColor, ...
                        'LineWidth', 2);
                    
                    % 标签
                    if nargin >= 4 && i <= numel(labels)
                        labelText = labels{i};
                        % 替换标签：starlink -> 星链体制，oneweb -> 一网体制
                        labelStr = lower(char(labelText));
                        if contains(labelStr, 'starlink')
                            labelText = '星链体制';
                        elseif contains(labelStr, 'oneweb')
                            labelText = '一网体制';
                        end
                        if nargin >= 5 && i <= numel(scores)
                            labelText = sprintf('%s (%.1f%%)', labelText, scores(i)*100);
                        end
                        text(this.OnewebResultAxes, bbox(1), bbox(2) - 5, ...
                            labelText, ...
                            'Color', [1 1 1], ...
                            'FontSize', 10, ...
                            'FontWeight', 'bold', ...
                            'BackgroundColor', this.OnewebColor);
                    end
                end
            end
            
            hold(this.OnewebResultAxes, 'off');
            axis(this.OnewebResultAxes, 'off');
        end
        
        function displayImageFull(this, ax, img)
            % 显示图像并确保铺满整个 axes
            % 使用 image 函数而不是 imshow，以便完全控制坐标轴范围
            
            % 确保图像是 RGB 格式
            if size(img, 3) == 1
                img = repmat(img, [1 1 3]);
            end
            
            % 获取图像尺寸
            [imgH, imgW, ~] = size(img);
            
            % 使用 image 函数显示
            image(ax, img);
            
            % 设置坐标轴范围，确保图像铺满
            ax.XLim = [0.5, imgW + 0.5];
            ax.YLim = [0.5, imgH + 0.5];
            
            % 设置坐标轴属性
            axis(ax, 'off');
            axis(ax, 'equal');
            ax.YDir = 'reverse';  % 图像坐标系：Y轴向下
            ax.Position = [0 0 1 1];
            ax.Units = 'normalized';
        end
        
        function updateStatus(this, msg)
            % 更新状态
            if this.IsInitialized
                this.StatusLabel.Text = msg;
                this.StatusLabel.FontColor = this.TextColor;
            end
        end
        
        function reset(this)
            % 重置面板
            if this.IsInitialized
                % 清除所有图像数据
                this.StarlinkOriginalImage = [];
                this.StarlinkResultImage = [];
                this.OnewebOriginalImage = [];
                this.OnewebResultImage = [];
                
                % 清除所有 axes 内容
                if ~isempty(this.StarlinkOriginalAxes)
                    cla(this.StarlinkOriginalAxes);
                    hold(this.StarlinkOriginalAxes, 'off');
                end
                if ~isempty(this.StarlinkResultAxes)
                    cla(this.StarlinkResultAxes);
                    hold(this.StarlinkResultAxes, 'off');
                end
                if ~isempty(this.OnewebOriginalAxes)
                    cla(this.OnewebOriginalAxes);
                    hold(this.OnewebOriginalAxes, 'off');
                end
                if ~isempty(this.OnewebResultAxes)
                    cla(this.OnewebResultAxes);
                    hold(this.OnewebResultAxes, 'off');
                end
                
                % 显示占位符
                this.showPlaceholder();
                this.updateStatus('等待测试流程启动...');
            end
        end
    end
end
