function jamData = jammer(constellation, terminalPos, commSatPos, commSatVel, companionPos, companionVel, options)
    % JAMMER 为会话3生成基带干扰评估数据
    %
    % 输入:
    %   constellation - 星座名称 ('starlink' 或 'oneweb')
    %   terminalPos   - 终端位置 [lat, lon, alt]
    %   commSatPos    - 通信卫星ECEF位置 [x; y; z]
    %   commSatVel    - 通信卫星ECEF速度 [vx; vy; vz]
    %   companionPos  - 伴飞卫星ECEF位置 [x; y; z]
    %   companionVel  - 伴飞卫星ECEF速度 [vx; vy; vz]
    %   options       - 可选参数结构体
    %
    % 输出:
    %   jamData - 干扰评估数据结构体，包含:
    %       .signal       - 含噪声的IQ信号
    %       .burstInfo    - burst位置、数量等信息
    %       .txBits       - 发送比特
    %       .rxConfig     - 接收配置
    %       .channelState - 信道状态
    %       .meta         - 元数据
    %
    % 示例:
    %   jamData = twin.signal.jammer('starlink', ...
    %       [39.9, 116.4, 0], commSatPos, commSatVel, companionPos, companionVel);

    if nargin < 7
        options = struct();
    end
    
    % 初始化输出结构
    jamData = struct();
    jamData.signal = [];
    jamData.burstInfo = struct();
    jamData.txBits = logical([]);
    jamData.rxConfig = struct();
    jamData.channelState = struct();
    jamData.meta = struct();
    
    % 确保位置是列向量
    commSatPos = commSatPos(:);
    commSatVel = commSatVel(:);
    companionPos = companionPos(:);
    companionVel = companionVel(:);
    
    % 时间戳
    timeInstant = posixtime(datetime('now', 'TimeZone', 'UTC'));

    %% ==================== 1. 加载配置 ====================
    spectrumConfig = spectrumMonitorConfig(constellation);
    phyParams = constellationPhyConfig(constellation);
    
    % 确定带宽模式
    supportedModes = dataGen.config.mode('list', phyParams);
    if isfield(options, 'forceBandwidthMode') && ~isempty(options.forceBandwidthMode)
        selectedBwMode = char(options.forceBandwidthMode);
    elseif ~isempty(supportedModes)
        selectedBwMode = supportedModes{1};  % 使用第一个支持的模式
    else
        f = fieldnames(phyParams.channelization.modes);
        selectedBwMode = f{1};
    end
    
    modeParams = phyParams.channelization.modes.(selectedBwMode);
    basebandSampleRate = modeParams.sampleRate;

    %% ==================== 2. 基带模式规划 ====================
    % 观察窗口时长（ms）
    obsWindow_ms = getFieldOr(options, 'observationWindow_ms', 30);
    
    % 规划参数
    guardMs = dataGen.burst.guard(spectrumConfig, selectedBwMode);
    guardMs = max(guardMs, eps);
    
    % 加载真实指纹库
    fprintf('[jammer] 使用带宽模式: %s\n', selectedBwMode);
    rfFingerprintDB = loadFingerprintDB(constellation, selectedBwMode);
    
    % 调用统一规划
    [terminalPlans, planInfo] = dataGen.burst.plan(obsWindow_ms, basebandSampleRate, ...
        constellation, selectedBwMode, ...
        'GuardTime_ms', guardMs, ...
        'OutputMode', 'baseband', ...
        'FingerprintDB', rfFingerprintDB, ...
        'SignalPresent', true, ...
        'SpectrumConfig', spectrumConfig, ...
        'Options', options);

    numTerminals = planInfo.numTerminals;
    totalBursts = planInfo.totalBursts;

    if totalBursts == 0 || numTerminals == 0
        jamData = buildEmptyJamData(constellation, selectedBwMode, basebandSampleRate, obsWindow_ms);
        return;
    end

    %% ==================== 3. 构建终端配置 ====================
    % 基带IQ缓冲区
    iqLength = round(obsWindow_ms * 1e-3 * basebandSampleRate);
    accumulatedIQ = complex(zeros(iqLength, 1));

    burstsLabel = struct([]);
    burstsStat = struct([]);
    burstsTimeMask = {};
    allTxBits = logical([]);  % 收集所有发送比特

    % 天气条件
    weatherCond = 'clear';
    if isfield(options, 'weatherCondition')
        weatherCond = options.weatherCondition;
    end

    validBurstsCount = 0;

    % 配置接收机参数
    obsBandwidth = dataGen.config.mode('bandwidth', phyParams, selectedBwMode);
    if ~isfield(options, 'receiverConfig') || ~isstruct(options.receiverConfig)
        options.receiverConfig = struct();
    end
    options.receiverConfig.observationBandwidth = obsBandwidth;
    options.receiverConfig.signalBandwidth = obsBandwidth;

    % planLimits
    planLimits = struct();
    planLimits.maxBurstSamples = planInfo.maxBurstSamples;
    planLimits.maxBurstRatio = planInfo.maxBurstRatio;
    planLimits.outputMode = 'baseband';
    planLimits.outputSampleRate = basebandSampleRate;
    planLimits.basebandSampleRate = basebandSampleRate;
    planLimits.maxBasebandSamples = planInfo.maxBurstSamples;
    planLimits.allowTruncation = false;  % 基带模式不截断

    %% ==================== 4. 生成 burst ====================
    for tIdx = 1:numTerminals
        termPlan = terminalPlans(tIdx);
        
        % 使用 dataGen.terminal.create 创建终端配置
        termProfile = dataGen.terminal.create(constellation, commSatPos, selectedBwMode, ...
            termPlan, rfFingerprintDB, spectrumConfig, options);
        
        % 覆盖终端位置为传入的位置
        termProfile.utPos = terminalPos(:)';
        
        if ~termProfile.initialized
            continue;
        end

        % 生成该终端的所有 burst
        for bIdx = 1:numel(termPlan.bursts)
            burstSpec = termPlan.bursts(bIdx);
            
            % 构建 burst 参数
            burstParams = struct();
            burstParams.startIdx = max(1, burstSpec.startIdx);
            burstParams.payloadBits = burstSpec.payloadBits;
            burstParams.mcsIndex = termPlan.mcsIndex;
            burstParams.modulation = termPlan.modulation;
            burstParams.codeRate = termPlan.codeRate;

            % 生成 burst
            [bIQ, bLabel, bStat, ~, bFeasible] = generateBurst( ...
                termProfile, constellation, selectedBwMode, ...
                companionPos, companionVel, commSatPos, ...
                weatherCond, timeInstant, spectrumConfig, options, ...
                burstParams, tIdx, planLimits);

            if bFeasible
                % 基带模式：放置到指定位置
                slotStart = min(max(1, burstSpec.startIdx), numel(accumulatedIQ));
                burstLen = numel(bIQ);
                slotEnd = min(slotStart + burstLen - 1, numel(accumulatedIQ));
                actualLen = slotEnd - slotStart + 1;
                
                if actualLen > 0
                    accumulatedIQ(slotStart:slotEnd) = accumulatedIQ(slotStart:slotEnd) + bIQ(1:actualLen);
                    basebandMask = false(numel(accumulatedIQ), 1);
                    basebandMask(slotStart:slotEnd) = true;
                    burstsTimeMask{end + 1} = basebandMask; 
                end

                if isempty(burstsLabel)
                    burstsLabel = bLabel;
                    burstsStat = bStat;
                else
                    burstsLabel(end + 1) = bLabel; 
                    burstsStat(end + 1) = bStat; 
                end
                
                % 收集发送比特
                if isfield(bLabel, 'txBits') && ~isempty(bLabel.txBits)
                    allTxBits = [allTxBits; logical(bLabel.txBits(:))]; 
                end

                validBurstsCount = validBurstsCount + 1;
            end
        end
    end

    %% ==================== 5. 添加噪声（基带模式）====================
    targetSNR_dB = getFieldOr(options, 'targetSNR_dB', 15);
    if validBurstsCount > 0 && ~isempty(burstsStat) && isfield(burstsStat(1), 'channelSNR')
        channelSNR = burstsStat(1).channelSNR;
        if isfinite(channelSNR)
            targetSNR_dB = channelSNR;
        end
    end
    
    % 计算信号功率（仅非零区域）
    signalMask = accumulatedIQ ~= 0;
    if any(signalMask)
        signalPower = mean(abs(accumulatedIQ(signalMask)).^2);
    else
        signalPower = 1;
    end
    
    if ~isfinite(signalPower) || signalPower <= 0
        signalPower = 1;
    end
    
    % 根据目标SNR计算噪声功率
    noisePower = signalPower / (10^(targetSNR_dB / 10));
    noiseStd = sqrt(noisePower / 2);
    noiseVector = noiseStd * (randn(length(accumulatedIQ), 1) + 1j * randn(length(accumulatedIQ), 1));
    finalIQ = accumulatedIQ + noiseVector;

    %% ==================== 6. 计算每个burst的SNR ====================
    measuredSNR = targetSNR_dB;
    if validBurstsCount > 0 && ~isempty(noiseVector)
        P_noise = mean(abs(noiseVector) .^ 2);
        
        for bIdx = 1:validBurstsCount
            if bIdx <= length(burstsStat) && isfield(burstsStat(bIdx), 'cleanSignalPower')
                P_sig = burstsStat(bIdx).cleanSignalPower;
                
                if P_sig > 0 && P_noise > 0
                    labelSNRMeasured = 10 * log10(P_sig / P_noise);
                    burstsLabel(bIdx).SNR = labelSNRMeasured;
                    burstsStat(bIdx).observedSNR = labelSNRMeasured;
                    if bIdx == 1
                        measuredSNR = labelSNRMeasured;
                    end
                end
            end
        end
    end

    %% ==================== 7. 构造 burstInfo ====================
    burstInfo = buildBurstInfo(finalIQ, validBurstsCount, burstsTimeMask, basebandSampleRate);

    %% ==================== 8. 构造干扰评估数据结构 ====================
    % 8.1 signal - 含噪声的基带信号
    jamData.signal = single(finalIQ(:));
    
    % 8.2 burstInfo - burst信息
    jamData.burstInfo = burstInfo;
    
    % 8.3 txBits - 发送比特
    jamData.txBits = allTxBits;
    
    % 8.4 rxConfig - 接收配置
    jamData.rxConfig = buildRxConfig(spectrumConfig, selectedBwMode, burstsLabel);
    
    % 8.5 channelState - 信道状态
    jamData.channelState = buildChannelState(burstsLabel, burstsStat);
    
    % 8.6 meta - 元数据
    jamData.meta = struct();
    jamData.meta.constellation = constellation;
    jamData.meta.bandwidthMode = selectedBwMode;
    jamData.meta.sampleRate = basebandSampleRate;
    jamData.meta.numBursts = validBurstsCount;
    jamData.meta.SNR = measuredSNR;
    jamData.meta.dutyCycle = sum(burstInfo.burstMask) / numel(finalIQ);
    
    if validBurstsCount > 0 && ~isempty(burstsLabel)
        jamData.meta.modulation = getFieldOr(burstsLabel(1), 'modulation', 'QPSK');
        jamData.meta.mcsIndex = getFieldOr(burstsLabel(1), 'mcsIndex', 1);
        jamData.meta.channelIndex = getFieldOr(burstsLabel(1), 'channelIndex', 1);
    else
        jamData.meta.modulation = 'QPSK';
        jamData.meta.mcsIndex = 1;
        jamData.meta.channelIndex = 1;
    end
    
    % 8.7 额外信息（用于GUI显示）
    jamData.cleanSignal = single(accumulatedIQ(:));  % 无噪声的干净信号
    jamData.noiseVector = single(noiseVector(:));    % 噪声向量
    
    fprintf('[jammer] 生成完成: %d bursts, SNR=%.1f dB, 占空比=%.1f%%\n', ...
        validBurstsCount, measuredSNR, jamData.meta.dutyCycle * 100);
end

%% ==================== 辅助函数: 加载指纹库 ====================
function rfFingerprintDB = loadFingerprintDB(constellation, bwMode)
    % 从 data/generated/fingerprint 加载真实指纹库
    
    rfFingerprintDB = struct();
    
    % 获取项目根目录
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(fileparts(fileparts(thisFile))));
    
    % 指纹库根目录
    fingerprintRoot = fullfile(projectRoot, 'data', 'generated', 'fingerprint', constellation, bwMode);
    
    if ~exist(fingerprintRoot, 'dir')
        warning('jammer:NoFingerprintDir', '指纹库目录不存在: %s，使用空指纹', fingerprintRoot);
        % 创建默认空指纹
        dummyFingerprint = struct('id', sprintf('jammer_%s_001', bwMode), ...
            'frequencyOffset', 0, 'phaseNoise', 0, 'dcOffset', 0, ...
            'iqImbalance', struct('amplitudeImbalance', 0, 'phaseImbalance', 0), ...
            'paNonlinearity', struct('coefficients', [1; 0; 0]));
        rfFingerprintDB.(bwMode) = struct('known', dummyFingerprint, 'unknown', struct([]));
        return;
    end
    
    modeEntry = struct('known', [], 'unknown', []);
    
    % 加载已知指纹（文件结构: data.fingerprintDB）
    knownFile = fullfile(fingerprintRoot, sprintf('rfFingerprint_%s_%s_known.mat', constellation, bwMode));
    if exist(knownFile, 'file')
        data = load(knownFile);
        if isfield(data, 'fingerprintDB')
            modeEntry.known = data.fingerprintDB;
            fprintf('[jammer] 已加载 %d 个已知指纹\n', numel(data.fingerprintDB));
        end
    end
    
    % 加载未知指纹（文件结构: data.fingerprintDB）
    unknownFile = fullfile(fingerprintRoot, sprintf('rfFingerprint_%s_%s_unknown.mat', constellation, bwMode));
    if exist(unknownFile, 'file')
        data = load(unknownFile);
        if isfield(data, 'fingerprintDB')
            modeEntry.unknown = data.fingerprintDB;
            fprintf('[jammer] 已加载 %d 个未知指纹\n', numel(data.fingerprintDB));
        end
    end
    
    % 如果没有加载到任何指纹，创建默认
    if isempty(modeEntry.known) && isempty(modeEntry.unknown)
        warning('jammer:EmptyFingerprint', '未找到指纹文件，使用默认指纹');
        dummyFingerprint = struct('id', sprintf('jammer_%s_001', bwMode), ...
            'frequencyOffset', 0, 'phaseNoise', 0, 'dcOffset', 0, ...
            'iqImbalance', struct('amplitudeImbalance', 0, 'phaseImbalance', 0), ...
            'paNonlinearity', struct('coefficients', [1; 0; 0]));
        modeEntry.known = dummyFingerprint;
    end
    
    rfFingerprintDB.(bwMode) = modeEntry;
end

%% ==================== 辅助函数: Generate Burst ====================
function [iq, label, stat, timeMask, feasible] = generateBurst( ...
        terminalProfile, constellation, bwMode, ...
        monSatPos, monSatVel, commSatPos, ...
        weatherCond, timeInstant, config, options, ...
        burstParams, terminalIndex, planLimits)
    % GENERATEBURST 生成单个基带 burst

    iq = []; label = struct(); stat = struct(); timeMask = []; feasible = false;

    if ~terminalProfile.initialized
        return;
    end
    
    try
        % 应用规划参数到发射模板
        terminalProfile.txTemplate.mcsIndex = burstParams.mcsIndex;
        terminalProfile.txTemplate.modulation = burstParams.modulation;
        terminalProfile.txTemplate.codeRate = burstParams.codeRate;
        terminalProfile.txTemplate.numInfoBits = burstParams.payloadBits;

        % 1. 发射端处理
        [txWaveform, txInfo, txParams] = dataGen.link.transmit(terminalProfile, constellation, bwMode);
        txInfo.constellation = constellation;
        txInfo.txPower = txParams.txPower;

        % 2. 截断处理（基带模式不截断，直接检查是否超出）
        maxBasebandSamples = planLimits.maxBasebandSamples;
        if numel(txWaveform) > maxBasebandSamples
            warning('generateBurst:ExceedsWindow', ...
                '基带模式：终端 %d 的 burst 超出观察窗口，跳过。', terminalIndex);
            feasible = false;
            return;
        end

        % 3. 信道传播（基带模式启用AGC）
        receiverCfg = dataGen.config.receiver(options, config);
        enableWideband = false;  % 基带模式
        [rxWaveform, chState, ~] = dataGen.link.channel(txWaveform, txInfo, terminalProfile, ...
            monSatPos, monSatVel, commSatPos, weatherCond, timeInstant, receiverCfg, enableWideband);

        % 4. 输出
        iq = rxWaveform;
        timeMask = true(size(iq));
        feasible = true;

        % 5. 构建标签和统计
        [label, stat] = dataGen.link.label(txInfo, txParams, chState, terminalProfile, ...
            timeMask, iq, config, options, enableWideband, bwMode, terminalIndex);
        
        stat.cleanSignalPower = mean(abs(rxWaveform).^2);
        stat.cleanSignalEnergy = sum(abs(rxWaveform).^2);
        stat.cleanSignalLength = numel(rxWaveform);

    catch ME
        warning('generateBurst:Failed', '生成失败: %s', ME.message);
        feasible = false;
    end
end

%% ==================== 辅助函数: 构建 burstInfo ====================
function burstInfo = buildBurstInfo(finalIQ, validBurstsCount, burstsTimeMask, sampleRate)
    
    burstInfo = struct();
    burstInfo.numBursts = validBurstsCount;
    burstInfo.sampleRate = sampleRate;
    
    if validBurstsCount > 0 && ~isempty(burstsTimeMask)
        combinedMask = false(size(finalIQ));
        burstStarts = zeros(validBurstsCount, 1);
        burstEnds = zeros(validBurstsCount, 1);
        
        for bIdx = 1:validBurstsCount
            if bIdx <= length(burstsTimeMask) && ~isempty(burstsTimeMask{bIdx})
                mask = burstsTimeMask{bIdx}(:);
                mask = adjustLength(mask, length(combinedMask));
                combinedMask = combinedMask | mask;
                indices = find(mask);
                if ~isempty(indices)
                    burstStarts(bIdx) = indices(1);
                    burstEnds(bIdx) = indices(end);
                end
            end
        end
        
        burstInfo.burstMask = combinedMask;
        burstInfo.burstStarts = burstStarts;
        burstInfo.burstEnds = burstEnds;
        
        if ~isempty(burstEnds) && ~isempty(burstStarts) && burstEnds(1) > burstStarts(1)
            burstInfo.burstDuration = burstEnds(1) - burstStarts(1) + 1;
        else
            burstInfo.burstDuration = 0;
        end
        
        syncRatio = 0.12;
        burstInfo.syncSymbols = round(burstInfo.burstDuration * syncRatio);
    else
        burstInfo.burstMask = false(size(finalIQ));
        burstInfo.burstStarts = [];
        burstInfo.burstEnds = [];
        burstInfo.burstDuration = 0;
        burstInfo.syncSymbols = 0;
    end
end

%% ==================== 辅助函数: 构建接收配置 ====================
function rxConfig = buildRxConfig(spectrumConfig, bwMode, burstsLabel)
    % 构建接收机配置
    rxConfig = struct();
    rxConfig.bandwidthMode = bwMode;
    
    % 默认值
    rxConfig.GT = 0;
    rxConfig.antennaGain = 30;
    rxConfig.noiseTemp = 300;
    rxConfig.pilotPowerBoost = 0;
    rxConfig.enableRotation = true;
    rxConfig.verbose = false;
    
    % 从 spectrumConfig 获取
    if isfield(spectrumConfig, 'receiver')
        if isfield(spectrumConfig.receiver, 'GT')
            rxConfig.GT = spectrumConfig.receiver.GT;
        end
        if isfield(spectrumConfig.receiver, 'antennaGain')
            rxConfig.antennaGain = spectrumConfig.receiver.antennaGain;
        end
        if isfield(spectrumConfig.receiver, 'noiseTemp')
            rxConfig.noiseTemp = spectrumConfig.receiver.noiseTemp;
        end
    end
    
    % 从 burstsLabel 获取
    if ~isempty(burstsLabel) && isstruct(burstsLabel)
        if isfield(burstsLabel(1), 'mcsIndex')
            rxConfig.mcs = burstsLabel(1).mcsIndex;
        else
            rxConfig.mcs = 1;
        end
        if isfield(burstsLabel(1), 'channelIndex')
            rxConfig.channelIndex = burstsLabel(1).channelIndex;
        else
            rxConfig.channelIndex = 1;
        end
    else
        rxConfig.mcs = 1;
        rxConfig.channelIndex = 1;
    end
end

%% ==================== 辅助函数: 构建信道状态 ====================
function channelState = buildChannelState(burstsLabel, burstsStat)
    % 构建信道状态
    channelState = struct();
    
    % 默认值
    channelState.SNR = NaN;
    channelState.dopplerShift = 0;
    channelState.pathLoss = 0;
    channelState.propagationDelay = 0;
    channelState.elevation = 45;
    
    % 从 burstsLabel/burstsStat 获取
    if ~isempty(burstsLabel) && isstruct(burstsLabel)
        label = burstsLabel(1);
        if isfield(label, 'SNR')
            channelState.SNR = label.SNR;
        end
        if isfield(label, 'dopplerShift')
            channelState.dopplerShift = label.dopplerShift;
        end
    end
    
    if ~isempty(burstsStat) && isstruct(burstsStat)
        stat = burstsStat(1);
        if isfield(stat, 'channelSNR')
            channelState.SNR = stat.channelSNR;
        end
        if isfield(stat, 'observedSNR')
            channelState.observedSNR = stat.observedSNR;
        end
        if isfield(stat, 'pathLoss')
            channelState.pathLoss = stat.pathLoss;
        end
        if isfield(stat, 'propagationDelay')
            channelState.propagationDelay = stat.propagationDelay;
        end
        if isfield(stat, 'elevation')
            channelState.elevation = stat.elevation;
        end
    end
end

%% ==================== 辅助函数: 构建空数据 ====================
function jamData = buildEmptyJamData(constellation, bwMode, sampleRate, obsWindow_ms)
    % 构建无信号时的空数据结构
    iqLength = round(obsWindow_ms * 1e-3 * sampleRate);
    
    jamData = struct();
    
    % signal - 纯噪声
    noiseStd = 0.01;
    noiseVector = noiseStd * (randn(iqLength, 1) + 1j * randn(iqLength, 1));
    jamData.signal = single(noiseVector);
    
    % burstInfo - 空
    jamData.burstInfo = struct();
    jamData.burstInfo.numBursts = 0;
    jamData.burstInfo.sampleRate = sampleRate;
    jamData.burstInfo.burstMask = false(iqLength, 1);
    jamData.burstInfo.burstStarts = [];
    jamData.burstInfo.burstEnds = [];
    jamData.burstInfo.burstDuration = 0;
    jamData.burstInfo.syncSymbols = 0;
    
    % txBits - 空
    jamData.txBits = logical([]);
    
    % rxConfig
    jamData.rxConfig = struct();
    jamData.rxConfig.bandwidthMode = bwMode;
    jamData.rxConfig.mcs = 1;
    jamData.rxConfig.channelIndex = 1;
    
    % channelState
    jamData.channelState = struct();
    jamData.channelState.SNR = NaN;
    jamData.channelState.dopplerShift = 0;
    
    % meta
    jamData.meta = struct();
    jamData.meta.constellation = constellation;
    jamData.meta.bandwidthMode = bwMode;
    jamData.meta.sampleRate = sampleRate;
    jamData.meta.numBursts = 0;
    jamData.meta.SNR = NaN;
    jamData.meta.dutyCycle = 0;
    jamData.meta.modulation = 'N/A';
    jamData.meta.mcsIndex = 0;
    jamData.meta.channelIndex = 0;
    
    % 额外信息
    jamData.cleanSignal = single(zeros(iqLength, 1));
    jamData.noiseVector = single(noiseVector);
    
    fprintf('[jammer] 无有效信号，返回空数据\n');
end

%% ==================== 辅助函数 ====================
function vec = adjustLength(vec, targetLen)
    if length(vec) > targetLen
        vec = vec(1:targetLen);
    elseif length(vec) < targetLen
        vec = [vec; zeros(targetLen - length(vec), 1)];
    end
end

function value = getFieldOr(structure, fieldName, defaultValue)
    if isstruct(structure) && isfield(structure, fieldName) && ~isempty(structure.(fieldName))
        value = structure.(fieldName);
    else
        value = defaultValue;
    end
end
