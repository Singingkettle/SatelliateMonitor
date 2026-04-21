function app = launch()
    % LAUNCH 启动卫星终端认知与干扰防御平台
    %
    %   twin.launch()
    %
    % 功能:
    %   使用 matlabshared.application 框架构建
    %   satelliteScenarioViewer 嵌入到 GUI 内部（非独立窗口）
    %   支持窗口等比例缩放
    %
    % 参考:
    %   C:\Program Files\MATLAB\R2025a\toolbox\satcom\satcom\+satcom\+internal\+linkbudgetApp
    %
    % 操作步骤:
    %   1. 创建地球场景
    %   2. 加载卫星列表
    %   3. 选择一颗卫星（自动渲染）
    %   4. 添加地面终端
    %   5. 生成 IQ 信号
    
    fprintf('\n');
    fprintf('╔════════════════════════════════════════════════════════════════╗\n');
    fprintf('║     卫星终端认知与干扰防御平台                                 ║\n');
    fprintf('║         Cognitive Satellite Spectrum Awareness                 ║\n');
    fprintf('║                                                                ║\n');
    fprintf('║   基于 matlabshared.application 框架                           ║\n');
    fprintf('║   3D 场景嵌入 GUI 内部 (非独立窗口)                            ║\n');
    fprintf('╚════════════════════════════════════════════════════════════════╝\n');
    fprintf('\n');
    fprintf('  正在启动...\n');
    
    try
        % 创建并启动应用
        app = twin.app.App();
        app.launch();
        
        fprintf('  ✓ 平台已启动\n\n');
        fprintf('  使用说明:\n');
        fprintf('    点击工具栏「新建会话」下拉菜单，选择测试会话类型：\n');
        fprintf('      - 会话1: 多种信号体制识别测试\n');
        fprintf('      - 会话2: 典型终端信号识别测试\n');
        fprintf('      - 会话3: 干扰防御测试\n');
        fprintf('\n');
        
    catch ME
        fprintf('  ✗ 启动失败: %s\n\n', ME.message);
        fprintf('  错误详情:\n');
        disp(getReport(ME, 'extended'));
        
        if nargout > 0
            app = [];
        end
        return;
    end
    
    if nargout == 0
        clear app;
    end
end
