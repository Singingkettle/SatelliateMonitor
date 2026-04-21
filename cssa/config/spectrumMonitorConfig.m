function config = spectrumMonitorConfig(constellation)
    % SPECTRUMMONITORCONFIG 频谱监测系统综合配置
    %
    %   config = spectrumMonitorConfig(constellation)
    %
    % 功能：
    %   返回频谱监测系统的完整配置参数
    %   覆盖数据生成、模型训练、评估的所有环节
    %
    % 输入:
    %   constellation - 星座类型 ('starlink' / 'oneweb')
    %
    % 输出:
    %   config - 配置结构体，主要包含：
    %       .broadband    - 宽带频谱监测配置
    %           .sampling     - 采样参数
    %           .receiver     - 伴飞接收机参数
    %           .processing   - 频谱图生成参数
    %           .dataset      - 数据集生成参数
    %       .jamming      - 干扰评估配置
    %           .burst        - burst 结构参数
    %           .strategies   - 干扰策略配置
    %       .detection    - YOLOX 检测配置
    %       .classification - 分类模型配置
    %
    % 参见: constellationPhyConfig

    configDir = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(configDir);
    repoRoot = fileparts(projectRoot);

    %% ========== 0. 基础与场景配置 (Common) ==========
    config.constellation = constellation;
    config.version = '2.0';
    config.createdDate = datetime('now');

    phyParams = constellationPhyConfig(constellation);
    modeList = resolveModeList(phyParams);
    modulationList = resolveModulationList(phyParams);
    config.runtime = struct();
    config.runtime.modeList = modeList;
    config.runtime.modulationList = modulationList;

    % 轨道与几何
    config.orbit.maxSatelliteAttempts = 20;
    config.orbit.numUTCandidates = 100000;
    config.orbit.defaultNumUTCandidates = 20;
    config.orbit.signalPresentProbability = 1;
    config.orbit.knownTerminalProbability = 0.8;
    config.orbit.maxElevationOptimizationIterations = 10;

    % 天气模型
    config.weather.conditions = {'clear', 'rain', 'heavy_rain'};
    config.weather.probabilities = [0.7, 0.2, 0.1];

    % RF 指纹 (硬件特征库)
    config.RFFingerprint.enable = true;
    config.RFFingerprint.databasePath = fullfile(repoRoot, 'models', sprintf('rfFingerprintDB_%s.mat', constellation));
    config.RFFingerprint.phaseNoiseRangeRMS = [0.01, 0.3];
    config.RFFingerprint.freqOffsetRangePPM = [-4, 4];
    config.RFFingerprint.dcOffsetRangeDBC = [-50, -32];

    %% ========== 1. 宽带监测任务配置 (broadband Task) ==========
    config.broadband = struct();

    % 1.1 伴飞场景 (几何)
    config.broadband.companion.separation = 14e3; % 14 km
    config.broadband.companion.enableOffBoresightLoss = true;
    config.broadband.companion.offBoresightLossMethod = 'auto';  % 'auto', 'manual', 'full_pattern'
    config.broadband.companion.manualOffBoresightLoss = 0;
    
    % 旁瓣接收模型配置
    % 当 offBoresightLossMethod = 'full_pattern' 时启用完整天线方向图模型
    % 支持主瓣、近旁瓣、远旁瓣三个区域的不同增益模型
    config.broadband.companion.antennaPatternModel = 'itu_s1528';  % 'simple', 'itu_s1528', 'measured'
    config.broadband.companion.enableSidelobeReception = false;  % 是否允许旁瓣接收
    config.broadband.companion.sidelobeProbability = 0.15;  % 旁瓣接收概率（用于数据增强）

    % 1.2 接收机射频参数 (Monitor Receiver RF)
    config.broadband.receiver.type = 'Phased Array';
    config.broadband.receiver.elementSpacing = 10;
    config.broadband.receiver.arraySize = [330, 330];
    config.broadband.receiver.frequency = [14.0, 14.5];
    config.broadband.receiver.systemNoiseTemp = 300;
    config.broadband.receiver.beamwidth = 5;

    % 星座特定接收参数
    switch lower(constellation)
        case 'starlink'
            config.broadband.receiver.gain14p0GHz = 32.6;
            config.broadband.receiver.gain14p5GHz = 33.1;
            config.broadband.receiver.GT = 6.3;
            config.broadband.receiver.polarization = 'LHCP';
        case 'oneweb'
            config.broadband.receiver.gain14p0GHz = 43.0;
            config.broadband.receiver.gain14p5GHz = 43.5;
            config.broadband.receiver.GT = 18.7;
            config.broadband.receiver.arraySize = [1300, 1300];
            config.broadband.receiver.beamwidth = 1.3;
            config.broadband.receiver.polarization = 'RHCP';
        otherwise
            config.broadband.receiver.gain14p0GHz = 30.0;
            config.broadband.receiver.gain14p5GHz = 30.5;
            config.broadband.receiver.GT = 3.0;
            config.broadband.receiver.polarization = 'Linear';
    end

    config.broadband.receiver.pointingAssumption = 'Optimal';
    config.broadband.receiver.pointingLossRange_dB = [0, 3]; % monitor pointing error loss

    % 1.3 采样与信号处理 (Sampling & Processing)
    config.broadband.sampling.centerFrequency = 14.25e9;
    config.broadband.sampling.bandwidth = 600e6;
    config.broadband.sampling.sampleRate = 600e6;
    config.broadband.sampling.IQSampleLength = 1800000;
    config.broadband.sampling.duration = config.broadband.sampling.IQSampleLength / config.broadband.sampling.sampleRate;

    config.broadband.processing.windowType = 'hann';
    config.broadband.processing.windowLength = 1342;
    config.broadband.processing.overlap = 1;
    config.broadband.processing.nfft = 1342;

    % 1.4 数据集生成参数 (Dataset Generation)
    config.broadband.dataset.samplesPerCombo = struct('train', 8000, 'val', 2000, 'test', 2000);
    config.broadband.dataset.comboOverrides = struct(); % 可选: 针对特定 mode/mod 自定义
    config.broadband.dataset.trainRatio = 0.8;
    config.broadband.dataset.valRatio = 0.1;
    config.broadband.dataset.testRatio = 0.1;

    spectrumSamplesOverride = getenv('SATMON_SPECTRUM_TOTAL_SAMPLES');

    if ~isempty(spectrumSamplesOverride)
        overrideVal = str2double(spectrumSamplesOverride);

        if ~isnan(overrideVal) && overrideVal > 0
            % 只按带宽模式分组，不再乘以调制方式数量
            perComboTotal = max(1, floor(overrideVal / max(1, numel(modeList))));
            ratioVec = [config.broadband.dataset.trainRatio, ...
                            config.broadband.dataset.valRatio, ...
                            config.broadband.dataset.testRatio];
            ratioVec = ratioVec / max(sum(ratioVec), eps);
            trainCount = max(0, round(perComboTotal * ratioVec(1)));
            valCount = max(0, round(perComboTotal * ratioVec(2)));
            testCount = max(0, max(perComboTotal - trainCount - valCount, 0));
            config.broadband.dataset.samplesPerCombo = struct( ...
                'train', max(trainCount, 1), ...
                'val', max(valCount, 0), ...
                'test', max(testCount, 0));
        end

    end

    baseSpectrumCombos = buildComboPlan(modeList, modulationList, config.broadband.dataset.samplesPerCombo, config.broadband.dataset.comboOverrides);
    [spectrumSplitTotals, spectrumTotalSamples] = summarizeComboTotals(baseSpectrumCombos);
    config.broadband.dataset.comboPlan = baseSpectrumCombos;
    config.broadband.dataset.splitCounts = spectrumSplitTotals;
    config.broadband.dataset.totalSamples = spectrumTotalSamples;

    config.broadband.dataset.SNRRange = [0, 30];
    config.broadband.dataset.numKnownEmitters = 3;
    config.broadband.dataset.numUnknownEmitters = 1;
    config.broadband.dataset.imageSize = [640, 640];
    config.broadband.dataset.maximizeSNR = false;
    config.broadband.dataset.minMonitorElevation = 60;
    config.broadband.dataset.maxEmittersPerSample = 5;
    config.broadband.dataset.maxBurstsPerTerminal = 3;
    config.broadband.dataset.txPowerBackoff_dB = [3, 35]; % UT power-control/backoff range (dB); wideband数据集里会对txPower做随机回退，扩大范围以覆盖低SNR场景
    config.broadband.dataset.defaultBurstGuard_ms = config.broadband.sampling.duration * 1e3;

    switch lower(constellation)
        case 'starlink'
            config.broadband.dataset.burstGuards_ms = struct( ...
                'mode_60MHz', 1.45, ...
                'mode_240MHz', 0.66, ...
                'default', 1.45);
        case 'oneweb'
            % OneWeb 上行沿用 LTE/SC-FDMA 帧结构：子帧 1 ms、slot 0.5 ms（3GPP TS 36.211 v16.4.0 §4.2）
            % 5 ms 级的 Guard 会远大于 3 ms 观察窗口，导致无法安排任何 burst。
            % 这里采用 0.25 ms (= 1/4 子帧) 的保护间隔，可在 3 ms 窗口内安排多个 burst 而不重叠。
            config.broadband.dataset.burstGuards_ms = struct( ...
                'mode_20MHz', 0.25, ...
                'default', 0.25);
        otherwise
            config.broadband.dataset.burstGuards_ms = struct('default', config.broadband.dataset.defaultBurstGuard_ms);
    end

    % 兼容性映射 (供 Detection 等后续模块使用)
    config.broadband.dataset.nfft = config.broadband.processing.nfft;

    %% ========== 2. 干扰策略评估任务配置 (Jamming Task) ==========
    % 重构说明:
    %   基于论文 arXiv-2304.09535v1 的 Starlink 信号测量结果
    %   采用 burst 间隔模型生成符合实际场景的干扰测试数据
    config.jamming = struct();

    % 2.1 数据集路径与存储 (与 spectrum 任务目录结构一致)
    % 路径格式: data/generated/spectrum/jamming/<constellation>/<bandwidthMode>/
    config.jamming.datasetRoot = fullfile(repoRoot, 'data', 'generated', 'spectrum', 'jamming');
    overrideRoot = getenv('SATMON_JAMMER_DATASET_ROOT');
    if ~isempty(overrideRoot)
        config.jamming.datasetRoot = char(overrideRoot);
    end
    config.jamming.storage.filePattern = 'sample_%05d.mat';

    % 2.2 Burst 行为参数 (按星座和带宽模式区分)
    % =========================================================================
    % 参考文献 (References):
    %
    %   [1] Stock W., Hofmann C.A., Knopp A., "LEO-PNT With Starlink: 
    %       Development of a Burst Detection Algorithm Based on Signal 
    %       Measurements", arXiv:2304.09535v1, 2023.
    %       引用:
    %       - "BRI ∈ {6.67, 8.00, 9.33, 10.67, 16.00, 18.67} ms"
    %       - "The burst duration [...] 0.84 ms [...] adaptable in timesteps 
    %          of 17.87 μs"
    %       - "L̇_c = 1200 and γL̇_c = 220" (@ 562.5 MSps)
    %       - "the vast majority of bursts [...] have bandwidth ≈ 62.5 MHz"
    %
    %   [2] Humphreys T.E. et al., "Signal Structure of the Starlink Ku-Band 
    %       Downlink", IEEE Trans. Aerospace and Electronic Systems, 2022.
    %       引用:
    %       - "frame length T_f = 1.333 ms"
    %       - "subsequences are T_c^k = 4.27 μs, 127 DPSK-modulated symbols"
    %       - "data signal d_i includes 302 OFDM-like symbols"
    %
    %   [3] ETSI TR 103 611 V1.1.1 (2018-09), "Satellite IMT systems".
    %       引用: OneWeb SC-FDMA, 20 MHz 载波带宽
    %
    %   [4] 3GPP TS 36.211, "Physical channels and modulation".
    %       引用: LTE 子帧 1ms, 子载波间隔 15kHz, Normal CP 4.7μs
    % =========================================================================
    config.jamming.burst = struct();
    config.jamming.burst.modes = struct();
    
    switch lower(string(constellation))
        case "starlink"
            % --- mode_60MHz (62.5 MHz 上行子信道) [Ref 1] ---
            m60 = struct();
            m60.briOptions_ms = [6.67, 8.00, 9.33, 10.67, 16.00, 18.67]; % [Ref 1]
            m60.typicalDuration_ms = 0.84;      % [Ref 1]
            m60.durationStepSize_us = 17.87;    % [Ref 1]
            m60.syncSubseqCount = 8;            % [Ref 1]
            m60.syncSubseqLength = 1200;        % @ 562.5 MSps [Ref 1]
            m60.syncPrefixLength = 220;         % γ = 1/32 [Ref 1]
            m60.syncPrefixRatio = 1/32;
            m60.firstSubseqInverted = true;     % [Ref 1,2]
            config.jamming.burst.modes.mode_60MHz = m60;
            
            % --- mode_240MHz (宽带/下行模式) [Ref 2] ---
            m240 = struct();
            m240.briOptions_ms = [1.33];        % 帧周期 [Ref 2]
            m240.typicalDuration_ms = 1.33;     % [Ref 2]
            m240.durationStepSize_us = 4.27;    % 子序列时长 [Ref 2]
            m240.syncSubseqCount = 8;           % [Ref 2]
            m240.syncSubseqLength = 127;        % DPSK 符号 [Ref 2]
            m240.syncPrefixRatio = 1/32;        % [Ref 2]
            m240.firstSubseqInverted = true;    % [Ref 2]
            m240.dataSymbolCount = 302;         % OFDM 符号 [Ref 2]
            config.jamming.burst.modes.mode_240MHz = m240;
            
        case "oneweb"
            % --- mode_20MHz (SC-FDMA 上行) [Ref 3,4] ---
            m20 = struct();
            m20.briOptions_ms = [1.0, 2.0, 4.0, 10.0]; % LTE 子帧 [Ref 4]
            m20.typicalDuration_ms = 1.0;       % 1ms 子帧 [Ref 4]
            m20.durationStepSize_us = 66.67;    % 1/15kHz [Ref 4]
            m20.subcarrierSpacing_kHz = 15;     % [Ref 4]
            m20.slotsPerSubframe = 2;           % [Ref 4]
            m20.symbolsPerSlot = 7;             % Normal CP [Ref 4]
            m20.cpDuration_us = 4.7;            % Normal CP [Ref 4]
            m20.dmrsSymbolCount = 2;            % [Engineering Assumption]
            config.jamming.burst.modes.mode_20MHz = m20;
            
        otherwise
            % 默认参数 (基于 Starlink 60MHz)
            mDef = struct();
            mDef.briOptions_ms = [6.67, 8.00, 10.67];
            mDef.typicalDuration_ms = 0.84;
            mDef.durationStepSize_us = 17.87;
            mDef.syncSubseqCount = 8;
            mDef.syncSubseqLength = 1200;
            mDef.syncPrefixRatio = 1/32;
            mDef.firstSubseqInverted = true;
            config.jamming.burst.modes.default = mDef;
    end
    
    % 观察窗口配置
    config.jamming.burst.observationWindow_ms = 30;  % 30ms 观察窗口
    config.jamming.burst.maxBursts = 6;              % 窗口内最大 burst 数
    config.jamming.burst.minBursts = 2;              % 窗口内最小 burst 数

    % 2.3 BER 阈值定义 (LDPC/DVB-S2 编码系统)
    % [Source: DVB-S2 Standard ETSI EN 302 307]
    config.jamming.BERThresholds = struct();
    config.jamming.BERThresholds.systemCrash = 0.10;       % 10% - FEC 解码失败
    config.jamming.BERThresholds.severeDegradation = 0.05; % 5%  - 接近瀑布点
    config.jamming.BERThresholds.performanceLoss = 0.01;   % 1%  - 开始明显重传

    % 2.4 干扰策略配置
    % 策略实现: white -> STAD (同步触发自适应数据段干扰)
    %          reactive -> STAD
    %          pulse -> STPD (同步触发脉冲式数据段干扰)
    config.jamming.strategies = struct();
    config.jamming.strategies.available = {'white', 'reactive', 'pulse'};
    config.jamming.strategies.default = 'reactive';
    config.jamming.strategies.defaultPulseDutyCycle = 0.10;  % pulse 策略默认占空比

    % 2.5 数据生成配置
    config.jamming.generation = struct();
    config.jamming.generation.enableDoppler = true;  % 启用多普勒频移（真实信道效应）
    
    switch lower(string(constellation))
        case "starlink"
            config.jamming.generation.minSNR_dB = 5;
            config.jamming.generation.maxSNR_dB = 25;
        case "oneweb"
            config.jamming.generation.minSNR_dB = 3;
            config.jamming.generation.maxSNR_dB = 20;
        otherwise
            config.jamming.generation.minSNR_dB = 5;
            config.jamming.generation.maxSNR_dB = 25;
    end

    % 干扰数据不需要训练/验证/测试划分（只用于评估）
    % 所有样本统一用于干扰策略能效评估
    jammerSampleCounts = struct('train', 50, 'val', 0, 'test', 0);

    jammerSamplesOverride = getenv('SATMON_JAMMER_SAMPLE_COUNTS');

    if ~isempty(jammerSamplesOverride)
        overrideTokens = regexp(jammerSamplesOverride, '[,;\s]+', 'split');
        overrideValues = str2double(overrideTokens);

        if numel(overrideValues) >= 3 && all(isfinite(overrideValues(1:3)))
            jammerSampleCounts.train = max(0, floor(overrideValues(1)));
            jammerSampleCounts.val = max(0, floor(overrideValues(2)));
            jammerSampleCounts.test = max(0, floor(overrideValues(3)));
        end

    end

    config.jamming.generation.samplesPerCombo = jammerSampleCounts;
    config.jamming.generation.comboOverrides = struct();
    baseJammerCombos = buildComboPlan(modeList, modulationList, jammerSampleCounts, config.jamming.generation.comboOverrides);
    [jammerSplitTotals, jammerTotalSamples] = summarizeComboTotals(baseJammerCombos);
    config.jamming.generation.comboPlan = baseJammerCombos;
    config.jamming.generation.sampleCounts = jammerSplitTotals;
    config.jamming.generation.totalSamples = jammerTotalSamples;
    config.jamming.generation.maxAttempts = 1000;
    config.jamming.generation.maxCleanBER = 1e-3;  % 允许微小的基线BER

    % 2.6 评估配置
    config.jamming.evaluation = struct();
    config.jamming.evaluation.JSR_dB = [-20, -15, -10, -5, 0, 5, 10, 15, 20];  % JSR 测试范围
    config.jamming.evaluation.numTrials = 50;         % 每配置测试次数
    config.jamming.evaluation.targetBERs = [0.01, 0.05, 0.10];  % 目标 BER 阈值
    
    % 2.7 结果保存路径
    config.jamming.results = struct();
    config.jamming.results.outputRoot = fullfile(repoRoot, 'results', constellation, 'jamming');
    config.jamming.results.figureFormat = {'png', 'fig'};
    config.jamming.results.saveData = true;

    %% ========== 3. 信号检测任务配置 (Detection Task) ==========
    % 依赖 broadband 数据
    config.detection.yoloX.modelType = 's';
    config.detection.yoloX.numEpochs = 5;
    config.detection.yoloX.miniBatchSize = 32;
    config.detection.yoloX.datasetRoot = fullfile(repoRoot, 'data', 'generated', 'spectrum');
    config.detection.yoloX.datasetDirNames = struct('starlink', 'detection', 'oneweb', 'detection', 'unified', 'detection');
    config.detection.yoloX.resultsRoot = fullfile(repoRoot, 'results');
    config.detection.yoloX.detectionSubdir = 'detection';
    config.detection.yoloX.detectorFileName = 'detector.mat';
    config.detection.yoloX.trainingInfoFileName = 'training_info.mat';
    config.detection.yoloX.configFileName = 'config.json';
    config.detection.yoloX.evaluation.scoreThreshold = 0.3;

    %% ========== 4. 分类任务配置 (Classification Task) ==========
    config.classification = struct();
    config.classification.datasetRoot = fullfile(repoRoot, 'data', 'generated', 'spectrum');
    config.classification.outputRoot = fullfile(repoRoot, 'data', 'generated', 'spectrum', 'classification');
    config.classification.resultsRoot = fullfile(repoRoot, 'results');
    
    % 调制分类参数
    config.classification.modulation = struct( ...
        'targetSymbols', 1024, ...           % 目标符号长度
        'removeSyncSymbols', 512, ...        % 去除同步头符号数（调整为targetSymbols的一半）
        'includeNoiseClass', true);          % 是否包含噪声类
    
    % 辐射源分类参数
    config.classification.emitter = struct( ...
        'targetSymbols', 1024, ...           % 目标符号长度（同步头）
        'useSyncExtractor', true);           % 使用同步提取器
    
    % 噪声样本生成参数
    config.classification.noise = struct( ...
        'minGuardSamples', max(64, round(config.broadband.sampling.sampleRate * 0.0005)), ...
        'maxAttempts', 30, ...
        'minWidthPixels', 18, ...
        'minHeightPixels', 18, ...
        'overlapThreshold', 0.1);            % 噪声框与GT框的最大IOU
    
    % 数据准备参数
    % IOU双阈值策略：
    %   >= iouPosThreshold: 匹配成功（正样本，使用GT标签）
    %   <  iouNegThreshold: 未匹配（负样本，标记为噪声）
    %   介于两者之间: 忽略（不确定区域，不参与训练）
    config.classification.dataPrep = struct( ...
        'iouPosThreshold', 0.5, ...          % IOU正样本阈值（>=此值认为匹配成功）
        'iouNegThreshold', 0.3, ...          % IOU负样本阈值（<此值认为未匹配）
        'detectThreshold', 0.3, ...          % 检测器置信度阈值
        'enableNoise', true, ...             % 是否生成噪声类样本
        'cleanOldData', true, ...            % 准备前清理旧数据
        'parallelWorkers', 0, ...            % 并行worker数 (0=自动)
        'randomSeed', 42);                   % 随机种子
    
    % 评估参数
    config.classification.evaluation = struct( ...
        'detectorScoreThreshold', 0.3);      % 检测器置信度阈值

    %% ========== 5. 运行流程控制 (Runtime) ==========
    config.runtime.verbose = false;
    config.runtime.debugLog = false;
    config.runtime.savePNG = true;
    config.runtime.visualizeBoundingBox = false;
    config.runtime.useParallel = false;
    config.runtime.numWorkers = 0;
    config.runtime.visualizeGT = false;
    config.runtime.visualizeGTDir = 'gt_visualizations';

    %% ========== 6. 路径配置 (Paths) ==========
    config.paths.repoRoot = repoRoot;
    config.paths.modelsRoot = fullfile(repoRoot, 'models');
    config.paths.fingerprintRoot = fullfile(repoRoot, 'data', 'generated', 'fingerprint');
    config.paths.dataRoot = fullfile(repoRoot, 'data', 'generated');

end

function list = resolveModeList(phyParams)

    list = {};

    if isfield(phyParams, 'channelization')
        chan = phyParams.channelization;

        if isfield(chan, 'supportedModes') && ~isempty(chan.supportedModes)
            list = chan.supportedModes;
        elseif isfield(chan, 'modes')
            list = fieldnames(chan.modes);
        end

    end

    if isempty(list)
        list = {'mode_default'};
    end

    list = cellfun(@char, list, 'UniformOutput', false);
end

function list = resolveModulationList(phyParams)

    list = {};

    if isfield(phyParams, 'mcsTable') && ~isempty(phyParams.mcsTable)
        mcs = phyParams.mcsTable;

        if size(mcs, 2) >= 2
            orders = unique(mcs(:, 2));
            list = cell(numel(orders), 1);

            for i = 1:numel(orders)
                list{i} = orderToModulationName(orders(i));
            end

        end

    end

    if isempty(list)
        list = {'QPSK'};
    end

    list = cellfun(@char, list, 'UniformOutput', false);
end

function fallbackStruct = buildFallbackWindowStruct(phyParams)

    fallbackValue = 0;

    if isfield(phyParams, 'waveform') && isfield(phyParams.waveform, 'nfft') && ~isempty(phyParams.waveform.nfft)
        fallbackValue = 4 * double(phyParams.waveform.nfft);
    end

    fallbackStruct = struct('default', fallbackValue);

    if isfield(phyParams, 'channelization') && isfield(phyParams.channelization, 'modes')
        modes = fieldnames(phyParams.channelization.modes);

        for idx = 1:numel(modes)
            modeName = modes{idx};
            fallbackStruct.(modeName) = fallbackValue;
        end

    end

end

function name = orderToModulationName(order)

    switch order
        case 2
            name = 'BPSK';
        case 4
            name = 'QPSK';
        case 8
            name = '8QAM';
        case 16
            name = '16QAM';
        case 32
            name = '32QAM';
        case 64
            name = '64QAM';
        otherwise
            name = sprintf('%dQAM', max(2, order));
    end

end

function comboPlan = buildComboPlan(modeList, ~, baseCounts, overrides)
    % 只按带宽模式分组，不按调制方式（调制方式在生成时随机选择）
    comboPlan = struct('bandwidthMode', {}, 'counts', {});
    idx = 0;

    for iMode = 1:numel(modeList)
        modeName = modeList{iMode};
        counts = applyModeCountOverrides(baseCounts, overrides, modeName);

        if counts.train + counts.val + counts.test <= 0
            continue;
        end

        idx = idx + 1;
        comboPlan(idx).bandwidthMode = char(modeName);
        comboPlan(idx).counts = counts;
    end

    if isempty(comboPlan)
        comboPlan = struct('bandwidthMode', 'mode_default', 'counts', baseCounts);
    end

end

function countsOut = applyModeCountOverrides(baseCounts, overrides, modeName)

    countsOut = baseCounts;

    if isfield(overrides, modeName)
        custom = overrides.(modeName);
        fields = fieldnames(baseCounts);

        for i = 1:numel(fields)
            fieldName = fields{i};

            if isfield(custom, fieldName) && ~isempty(custom.(fieldName))
                countsOut.(fieldName) = max(0, floor(custom.(fieldName)));
            end

        end

    end

end


function [splitTotals, totalSamples] = summarizeComboTotals(comboPlan)

    splitTotals = struct('train', 0, 'val', 0, 'test', 0);

    for i = 1:numel(comboPlan)
        counts = comboPlan(i).counts;
        if isfield(counts, 'train'), splitTotals.train = splitTotals.train + counts.train; end
        if isfield(counts, 'val'), splitTotals.val = splitTotals.val + counts.val; end
        if isfield(counts, 'test'), splitTotals.test = splitTotals.test + counts.test; end
    end

    totalSamples = splitTotals.train + splitTotals.val + splitTotals.test;
end
