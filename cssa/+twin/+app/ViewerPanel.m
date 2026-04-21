classdef ViewerPanel < matlabshared.application.Component
    % VIEWERPANEL 3D 场景查看器面板
    %
    %   将 satelliteScenarioViewer 嵌入到 FigureDocument.Figure 中
    %   参考: satcom.internal.linkbudgetApp.ScenarioViewer
    
    properties (Hidden)
        Viewer          % satelliteScenarioViewer 对象
    end
    
    methods
        function this = ViewerPanel(varargin)
            % 构造函数 - 不创建 UI
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
        end
        
        function name = getName(~)
            name = '3D 卫星场景';
        end
        
        function tag = getTag(~)
            tag = 'scenarioviewer';
        end
        
        function update(this)
            % update 方法 - 创建初始提示
            hFig = this.Figure;
            delete(hFig.Children);
            layout = uigridlayout(hFig, [1, 1]);
            layout.RowHeight = {'1x'};
            layout.ColumnWidth = {'1x'};
            uilabel(layout, ...
                'Text', '等待创建场景...', ...
                'FontSize', 16, ...
                'FontColor', [0.5 0.5 0.5], ...
                'HorizontalAlignment', 'center');
        end
        
        function createViewer(this, scenario)
            % 创建 Viewer
            
            % 删除旧的 Viewer
            if ~isempty(scenario.Viewers)
                numViewers = length(scenario.Viewers);
                for ii = 1:numViewers
                    delete(scenario.Viewers(end));
                end
            end
            
            % 清除 Figure
            delete(this.Figure.Children);
            
            % 创建新的 Viewer
            this.Viewer = satelliteScenarioViewer(scenario, ...
                "Parent", this.FigureDocument.Figure, ...
                "ShowDetails", true);
        end
        
        function refresh(~)
            % Viewer 会自动更新
        end
        
        function clearViewer(this)
            % 清除场景视图，显示初始提示
            if ~isempty(this.Viewer) && isvalid(this.Viewer)
                delete(this.Viewer);
            end
            this.Viewer = [];
            
            % 恢复初始界面
            hFig = this.Figure;
            delete(hFig.Children);
            layout = uigridlayout(hFig, [1, 1]);
            layout.RowHeight = {'1x'};
            layout.ColumnWidth = {'1x'};
            layout.BackgroundColor = [0.1 0.1 0.12];
            uilabel(layout, ...
                'Text', '等待创建场景...', ...
                'FontSize', 16, ...
                'FontColor', [0.5 0.5 0.5], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.1 0.1 0.12]);
        end
    end
end
