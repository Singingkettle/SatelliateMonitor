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

    % --- GPU 预热: 强制 MATLAB 接受高于内置 CUDA 库的 GPU (如 RTX 50/Blackwell)
    %   并主动触发一次 PTX JIT 编译, 否则会话 2 第一次跑 detect 会卡 60+ 秒.
    warmupGPU();

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

function warmupGPU()
    % WARMUPGPU 启用 CUDA 前向兼容 + 触发 PTX JIT 编译, 避免会话 2 首次
    %   跑 detect 时被编译开销 (60+ s) 拖死.
    %
    %   - 没有 Parallel Computing Toolbox 时直接静默返回 (CPU 模式)
    %   - GPU compute capability <= MATLAB 内置 CUDA 支持上限时无需开 forward
    %     compat, 但调用 enableCUDAForwardCompatibility(true) 也不会报错
    %   - 第一次预热完后, MATLAB user preference 会持久化到下次启动

    if exist('gpuDeviceCount', 'file') ~= 2
        return;   % 没装 Parallel Computing Toolbox
    end

    nGPU = 0;
    try
        nGPU = gpuDeviceCount;   %#ok<NASGU>
    catch
        return;
    end
    if nGPU == 0
        return;
    end

    % 1) 开启 CUDA forward compatibility (RTX 50 系列等 sm_120 必需)
    %   注: exist('parallel.gpu.xxx','file') 对 namespace 函数返回 0,
    %   所以这里直接 try 调用, 旧版 MATLAB 没这个 API 时会报错被吞掉.
    try
        parallel.gpu.enableCUDAForwardCompatibility(true);
    catch ME
        if ~contains(ME.identifier, 'UndefinedFunction', 'IgnoreCase', true)
            fprintf('  [GPU] forward compat 启用失败: %s\n', ME.message);
        end
    end

    % 2) 主动触发 PTX JIT (一次性, 之后会话 2 detect 直接命中缓存)
    try
        avail = gpuDeviceCount('available');
        if avail < 1
            fprintf('  [GPU] 已检测到 %d 块卡, 但 0 块可用 (driver/CUDA 版本不匹配?)\n', nGPU);
            return;
        end
        g = gpuDevice;
        fprintf('  [GPU] %s (CC %s, %.1f GB VRAM) - 预热中, 首次启动可能要 1-2 分钟...\n', ...
            g.Name, g.ComputeCapability, double(g.TotalMemory)/1e9);
        t0 = tic;
        A = gpuArray.rand(1024, 1024, 'single');
        B = A * A;          %#ok<NASGU>  触发 cuBLAS JIT
        C = fft2(A);        %#ok<NASGU>  触发 cuFFT JIT
        wait(g);
        fprintf('  [GPU] 预热完成 (%.1f s)\n', toc(t0));
    catch ME
        fprintf('  [GPU] 预热失败, 后续将回退 CPU: %s\n', ME.message);
    end
end
