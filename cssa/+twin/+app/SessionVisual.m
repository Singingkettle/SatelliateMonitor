classdef SessionVisual < matlabshared.application.Component
    % SESSIONVISUAL 会话选择提示面板
    %
    %   初始显示界面，提示用户点击工具栏的"新建会话"下拉菜单选择会话类型
    %
    % 参考: satcom.internal.linkbudgetApp.SessionVisual
    
    methods
        function this = SessionVisual(varargin)
            this@matlabshared.application.Component(varargin{:});
            addLabelToFigure(this);
        end
        
        function name = getName(~)
            name = '会话选择';
        end
        
        function tag = getTag(~)
            tag = 'sessionvisual';
        end
        
        function update(~)
            % 无需更新
        end
        
        function addLabelToFigure(this)
            % 添加提示界面
            clf(this.Figure);
            this.Figure.Color = [0.12 0.12 0.14];
            
            % 主布局 - 垂直居中
            mainLayout = uigridlayout(this.Figure, [5, 1]);
            mainLayout.RowHeight = {'1x', 'fit', 'fit', 'fit', '1x'};
            mainLayout.ColumnWidth = {'1x'};
            mainLayout.BackgroundColor = [0.12 0.12 0.14];
            mainLayout.Padding = [40 40 40 40];
            mainLayout.RowSpacing = 15;
            
            % 上方占位
            uilabel(mainLayout, 'Text', '', 'BackgroundColor', [0.12 0.12 0.14]);
            
            % 主标题
            uilabel(mainLayout, ...
                'Text', '卫星终端认知与干扰防御平台', ...
                'FontSize', 32, ...
                'FontWeight', 'bold', ...
                'FontColor', [0.3 0.8 1.0], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.12 0.12 0.14]);
            
            % 副标题
            uilabel(mainLayout, ...
                'Text', 'Cognitive Satellite Spectrum Awareness', ...
                'FontSize', 14, ...
                'FontColor', [0.6 0.6 0.6], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.12 0.12 0.14]);
            
            % 提示信息
            uilabel(mainLayout, ...
                'Text', '点击工具栏的「新建会话」下拉菜单，选择要启动的测试会话类型', ...
                'FontSize', 16, ...
                'FontColor', [0.85 0.85 0.85], ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.12 0.12 0.14]);
            
            % 下方占位
            uilabel(mainLayout, 'Text', '', 'BackgroundColor', [0.12 0.12 0.14]);
        end
    end
end

