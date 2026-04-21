function [txSignal, channelInfo, debugTx, frameMeta] = upTx(dataBits, config)
    % UPTX 星链用户终端上行链路基带调制与发射仿真
    % 基于公开技术文献实现星链上行物理层信号处理
    %
    % 输入参数:
    %   dataBits - 输入比特流数据
    %   config   - 配置参数结构体，包含:
    %              .mcs          - 调制编码方案索引 (1-8)
    %              .channelIndex   - 子信道索引 (1-8)
    %              .txPower      - 发射功率 (dBm)
    %              .beamAngle    - 波束指向角度 [azimuth, elevation]
    %              .enableCFR    - 是否启用CFR (默认true)
    %              .enableDPD    - 是否启用DPD (默认true)
    %              .pilotPowerBoost - 导频功率加成 (dB)
    %              .verbose      - 是否打印详细日志 (默认true)
    %
    % 输出参数:
    %   txSignal        - 发射信号
    %   channelInfo     - 信道信息
    %   debugTx         - 调试信息
    %   frameMeta       - 帧元数据
    %
    % 参考文献:
    %   [1] US12003350B1 - Configurable OFDM signal for UT-SAT uplink
    %   [2] SpaceX 星链卫星互联网星座核心技术解析 - 中国指挥与控制学会
    %
    % ==================== 参数初始化 ====================
    if nargin < 2
        config = struct();
    end

    % [更新 - 2025-11-19] 参数标准化更新：
    % 1. 所有的物理层参数（如带宽、采样率、CP长度、扰码多项式等）现在统一从
    %    cssa/config/starlink/getStarlinkPhyParams.m 获取，不再在代码中硬编码。
    % 2. 移除了对 generateStarlinkUplinkSignal.m 中旧参数格式的依赖。
    % 3. 增加了对 240MHz 宽带模式的支持（phyParams.bandwidth_240MHz）。

    % 从配置文件获取物理层参数
    phyParams = constellationPhyConfig('starlink');

    % 合并用户配置和默认配置（从配置文件获取默认值）
    config = mergeConfig(phyParams.defaultTxConfig, config);
    verbose = config.verbose;

    % 从配置文件获取系统参数（基于最新调研报告）
    % 参考: US12003350B1专利，FCC文档
    sysParam = struct();
    sysParam.nfft = phyParams.waveform.nfft;
    sysParam.nSubcarriers = phyParams.waveform.nSubcarriers;
    sysParam.cpLength = phyParams.waveform.cpLength;
    sysParam.csLength = phyParams.waveform.csLength;

    % 根据带宽模式选择采样率和带宽
    % 处理 modeKey (由 config.bandwidthMode 衍生)
    bwMode = config.bandwidthMode;
    modeKey = bwMode;

    if isfield(phyParams.channelization.modes, modeKey)
        modeParams = phyParams.channelization.modes.(modeKey);
    else
        % Fallback or Error
        error('Starlink:InvalidMode', '不支持的带宽模式: %s', bwMode);
    end

    sysParam.bandwidth = modeParams.bandwidth;
    sysParam.nominalBandwidth = modeParams.nominalBandwidth;
    sysParam.sampleRate = modeParams.sampleRate;
    sysParam.cpLength = modeParams.cpLength;

    sysParam.subcarrierSpacing = sysParam.bandwidth / sysParam.nSubcarriers;

    % 从配置文件获取MCS参数表
    mcsTable = phyParams.mcsTable(:, 2:3); % 只取调制阶数和码率列

    modOrder = mcsTable(config.mcs, 1);
    codeRate = mcsTable(config.mcs, 2);

    %% ==================== 1. 扰码处理 ====================
    % 使用 Communications Toolbox 提供的乘性扰码器实现：comm.Scrambler
    % 参考: MathWorks 文档 "comm.Scrambler System object"
    if verbose
        fprintf('执行扰码处理...\n');
    end

    % 从配置文件获取扰码参数
    polyVec = phyParams.coding.scramblerPoly;
    initState = phyParams.coding.scramblerInit;
    scrObj = comm.Scrambler('CalculationBase', 2, ...
        'Polynomial', polyVec, ...
        'InitialConditions', initState);
    scrambledBits = scrObj(double(dataBits(:)));

    %% ==================== 2. LDPC信道编码 ====================
    % 使用DVB-S2 LDPC码作为近似（MATLAB内置）
    if verbose
        fprintf('执行LDPC编码 (码率: %.2f)...\n', codeRate);
    end

    % 根据码率选择DVB-S2 LDPC奇偶校验矩阵，并使用ldpcEncode编码
    if codeRate == 1/2
        parityCheckMatrix = dvbs2ldpc(1/2);
    elseif codeRate == 2/3
        parityCheckMatrix = dvbs2ldpc(2/3);
    elseif codeRate == 5/6
        parityCheckMatrix = dvbs2ldpc(5/6);
    else
        parityCheckMatrix = dvbs2ldpc(2/3); % 默认2/3码率
    end

    parityCheckMatrix = sparse(parityCheckMatrix);
    % 创建LDPC编码配置
    ldpcCfg = ldpcEncoderConfig(parityCheckMatrix);

    % 确保输入长度匹配
    K = size(parityCheckMatrix, 2) - size(parityCheckMatrix, 1);
    N = size(parityCheckMatrix, 2);

    % 填充或截断数据以匹配编码器输入长度
    if length(scrambledBits) < K
        paddedBits = [scrambledBits; zeros(K - length(scrambledBits), 1)];
    elseif length(scrambledBits) > K
        paddedBits = scrambledBits(1:K);
    else
        paddedBits = scrambledBits;
    end

    encodedBits = ldpcEncode(paddedBits, ldpcCfg);

    %% ==================== 3. 比特交织 ====================
    % 块交织器，深度与每个OFDM数据符号承载的比特数匹配（仅数据子载波）
    if verbose
        fprintf('执行比特交织...\n');
    end

    bitsPerSymbol = log2(modOrder);
    % 从配置文件获取导频间隔
    if isfield(modeParams, 'pilotSpacing')
        pilotSpacing = modeParams.pilotSpacing;
    else
        pilotSpacing = phyParams.waveform.pilotSpacing; % fallback
    end

    nPilotsPerSymbol = numel(1:pilotSpacing:sysParam.nSubcarriers);
    nDataSubcarriers = sysParam.nSubcarriers - nPilotsPerSymbol;
    interleaverDepth = nDataSubcarriers * bitsPerSymbol;
    interleaverRows = ceil(length(encodedBits) / interleaverDepth);
    totalInterleaverLen = interleaverRows * interleaverDepth;

    if length(encodedBits) < totalInterleaverLen
        encodedBitsPadded = [encodedBits; zeros(totalInterleaverLen - length(encodedBits), 1)];
    else
        encodedBitsPadded = encodedBits;
    end

    interleavedBits = matintrlv(encodedBitsPadded, interleaverRows, interleaverDepth);

    %% ==================== 4. 调制映射 ====================
    if verbose
        fprintf('执行%d-QAM调制映射...\n', modOrder);
    end

    % 调试：打印调制前的前几个比特

    % 确保比特数是调制阶数的整数倍
    numPadBits = mod(length(interleavedBits), bitsPerSymbol);

    if numPadBits > 0
        interleavedBits = [interleavedBits; zeros(bitsPerSymbol - numPadBits, 1)];
    end

    % QAM调制
    if modOrder == 2
        modSymbols = pskmod(interleavedBits, 2, 'InputType', 'bit');
    else
        modSymbols = qammod(interleavedBits, modOrder, 'InputType', 'bit', 'UnitAveragePower', true);
    end

    % 调试：验证映射

    %% ==================== 5. OFDM帧结构设计 ====================
    if verbose
        fprintf('构建OFDM帧结构...\n');
    end

    % 5.1 生成UW同步序列（Unique Word）
    uwLength = sysParam.nfft;
    uwSeq = generateUWSequence(uwLength, phyParams.waveform);

    % 5.2 生成信道估计符号（CE Symbol）
    % 修正：CE符号也是OFDM符号，必须遵循相同的子载波映射规则以保证频谱居中
    % 参考专利：CE通常是频域已知的导频序列
    ceFreqDomain = starlink.generateCESymbol(sysParam.nSubcarriers, phyParams.waveform.ce); % 确定性QPSK符号

    % 映射到FFT输入（中心对称，与数据符号一致）
    ceFftInput = zeros(sysParam.nfft, 1);
    ceFftInput(2:sysParam.nSubcarriers / 2 + 1) = ceFreqDomain(1:sysParam.nSubcarriers / 2);
    ceFftInput(end - sysParam.nSubcarriers / 2 + 1:end) = ceFreqDomain(sysParam.nSubcarriers / 2 + 1:end);

    % 5.3 导频插入
    % 分布式导频：均匀分布在频域（从配置文件获取间隔）
    pilotIndices = 1:pilotSpacing:sysParam.nSubcarriers;
    nPilots = length(pilotIndices);
    dataIndices = setdiff(1:sysParam.nSubcarriers, pilotIndices);

    % 生成导频符号（BPSK）- 使用确定性序列
    pilotSymbols = generatePilotSymbols(nPilots);
    pilotBoostLinear = 10 ^ (config.pilotPowerBoost / 20);
    pilotSymbols = pilotSymbols * pilotBoostLinear;

    % 5.4 资源映射
    % 将数据符号映射到OFDM子载波
    nDataSubcarriers = length(dataIndices);
    nOFDMSymbols = ceil(length(modSymbols) / nDataSubcarriers);

    % 填充数据以匹配OFDM符号数
    totalDataSymbols = nOFDMSymbols * nDataSubcarriers;

    if length(modSymbols) < totalDataSymbols
        modSymbols = [modSymbols; zeros(totalDataSymbols - length(modSymbols), 1)];
    end

    % 频域旋转扰码（0°, 90°, 180°, 270°相位旋转）- 使用确定性序列
    % ！！关键修正：在填充后应用旋转，确保与Rx端序列长度一致
    enableRotation = config.enableRotation;

    if enableRotation
        rotationSeq = generateRotationSequence(length(modSymbols)); % 现在length = totalDataSymbols
        rotationFactors = exp(1j * rotationSeq * pi / 2);
        modSymbols = modSymbols .* rotationFactors;
    else

        if verbose
            fprintf('  [调试Tx] 频域旋转已禁用（调试模式）\n');
        end

        rotationSeq = []; % 定义为空数组，避免后续debug输出出错
    end

    % 构建OFDM符号
    ofdmSymbols = zeros(sysParam.nfft, nOFDMSymbols);
    dataSymbolsReshaped = reshape(modSymbols(1:totalDataSymbols), nDataSubcarriers, nOFDMSymbols);

    for symIdx = 1:nOFDMSymbols
        % 频域资源映射
        subcarrierMap = zeros(sysParam.nSubcarriers, 1);

        % 插入数据
        subcarrierMap(dataIndices) = dataSymbolsReshaped(:, symIdx);

        % 插入导频
        subcarrierMap(pilotIndices) = pilotSymbols;

        % 映射到FFT输入（中心对称）
        fftInput = zeros(sysParam.nfft, 1);
        % 左半部分
        fftInput(2:sysParam.nSubcarriers / 2 + 1) = subcarrierMap(1:sysParam.nSubcarriers / 2);
        % 右半部分
        fftInput(end - sysParam.nSubcarriers / 2 + 1:end) = subcarrierMap(sysParam.nSubcarriers / 2 + 1:end);

        % IFFT生成时域信号
        ofdmSymbols(:, symIdx) = ifft(fftInput, sysParam.nfft);
    end

    % 5.5 添加循环前缀和循环后缀
    ofdmWithCP = zeros(sysParam.nfft + sysParam.cpLength + sysParam.csLength, nOFDMSymbols);

    for symIdx = 1:nOFDMSymbols
        symbol = ofdmSymbols(:, symIdx);
        % 循环前缀：复制末尾部分到开头
        cp = symbol(end - sysParam.cpLength + 1:end);
        % 循环后缀：复制开头部分到末尾
        cs = symbol(1:sysParam.csLength);
        ofdmWithCP(:, symIdx) = [cp; symbol; cs];
    end

    % 5.6 组装完整帧
    ceTimeDomain = ifft(ceFftInput, sysParam.nfft);
    ceWithCP = addCyclicPrefixSuffix(ceTimeDomain, sysParam.cpLength, sysParam.csLength);

    % 参考专利[US12003350B1, Fig.13-14]：确保不同帧的时域功率平衡
    dataTimeWaveform = ofdmWithCP(:);
    dataRMS = sqrt(mean(abs(dataTimeWaveform) .^ 2));
    ceWithCP = normalizeRMS(ceWithCP, dataRMS);
    uwSeq = normalizeRMS(uwSeq, dataRMS);

    % 帧结构：UW + CE + 数据OFDM符号
    frame = [uwSeq; ceWithCP; ofdmWithCP(:)];

    %% ==================== 6. 数字前端处理 ====================
    if verbose
        fprintf('执行数字前端处理...\n');
    end

    % 6.1 成形（OFDM不进行采样率提升，保持sysParam.sampleRate）
    % 如需边沿整形可改用窗口化OFDM，这里保持恒等以确保采样率/带宽一致性
    shapedUp = frame;

    % 6.2 CFR - 峰值因数削减
    if config.enableCFR

        if verbose
            fprintf('  - 应用CFR峰值抑制...\n');
        end

        % 从配置文件获取CFR阈值
        cfrThreshold = phyParams.cfrThreshold_dB;
        shapedUp = applyCFR(shapedUp, cfrThreshold);
    end

    % 6.3 DPD - 数字预失真
    if config.enableDPD

        if verbose
            fprintf('  - 应用DPD预失真...\n');
        end

        dpdCoeffs = phyParams.ut.dpdCoeffs; % 从配置获取DPD系数
        shapedUp = applyDPD(shapedUp, dpdCoeffs);
    end

    % 6.4 频谱整形完成（保持采样率不变）
    filteredSignal = shapedUp;

    %% ==================== 7. 上变频到指定子信道 ====================
    % 基带输出：不进行数模上变频，中心频点由channelInfo给出
    % 使用配置文件中的信道化参数
    startFreq = phyParams.channelization.startFreq;

    if isfield(modeParams, 'channelSpacing')
        channelSpacing = modeParams.channelSpacing;
    else
        channelSpacing = 62.5e6; % Fallback
    end

    if isfield(modeParams, 'numChannels')
        numChannels = modeParams.numChannels;
    else
        numChannels = 8; % Fallback
    end

    centerFreq = startFreq + (config.channelIndex - 0.5) * channelSpacing;

    % 存储信道信息 (统一驼峰命名风格)
    channelInfo.carrierFrequency = centerFreq;
    channelInfo.bandwidth = sysParam.bandwidth;
    channelInfo.sampleRate = sysParam.sampleRate;
    channelInfo.channelIndex = config.channelIndex;
    channelInfo.frequencyRange = [centerFreq - sysParam.bandwidth / 2, centerFreq + sysParam.bandwidth / 2];
    channelInfo.channelSpacing = channelSpacing;
    channelInfo.numChannels = numChannels;
    channelInfo.referenceChannelIndex = (numChannels + 1) / 2;

    %% ==================== 8. 功率控制与发射 ====================
    if verbose
        fprintf('应用功率控制...\n');
    end

    % 根据配置的发射功率调整信号幅度（从配置文件获取最大功率限制）
    targetPower_W = 10 ^ (config.txPower / 10) / 1000; % dBm转换为瓦特
    % 限制最大发射功率
    maxTxPower = phyParams.ut.maxTxPower_W;
    targetPower_W = min(targetPower_W, maxTxPower);

    % 在复基带信号上进行功率缩放
    currentPower = mean(abs(filteredSignal) .^ 2);
    scaleFactor = sqrt(targetPower_W / currentPower);
    txSignal = filteredSignal * scaleFactor;

    % 移除上变频和EIRP计算，这些属于信道模型和链路预算的范畴
    % The output is now a complex baseband signal with correct average power

    %% ==================== 显示仿真结果 ====================
    if verbose
        fprintf('\n========== 星链上行发射配置概览 ==========\n');
    end

    if verbose
        fprintf('配置总结:\n');
    end

    if verbose
        fprintf('  - MCS: %d (调制: %d-QAM, 编码率: %.2f)\n', config.mcs, modOrder, codeRate);
    end

    if verbose
        fprintf('  - 物理信道: %d (中心频率 %.3f GHz)\n', config.channelIndex, centerFreq / 1e9);
    end

    if verbose
        fprintf('  - 目标发射功率: %d dBm\n', config.txPower);
    end

    if verbose
        fprintf('  - 波束指向: [%.1f°, %.1f°]\n', config.beamAngle(1), config.beamAngle(2));
    end

    if verbose
        fprintf('  - 导频功率加成: %.1f dB\n', config.pilotPowerBoost);
    end

    if verbose
        fprintf('  - 信号样本数: %d 点\n', length(txSignal));
    end

    if verbose
        fprintf('  - PAPR: %.2f dB\n', 10 * log10(max(abs(txSignal) .^ 2) / mean(abs(txSignal) .^ 2)));
    end

    if verbose
        fprintf('==========================================\n');
    end

    %% ==================== 调试导出 ====================
    % 输出关键中间比特流，便于端到端一致性验证
    if nargout >= 3
        debugTx.K = K; % LDPC信息长度
        debugTx.N = N; % LDPC码长
        debugTx.scrambledBits = scrambledBits;
        debugTx.encodedBitsN = encodedBits; % 编码后N比特
        debugTx.interleavedBits = interleavedBits; % 交织并填充后的比特流
        % 调试：打印扰码后前10比特
        if verbose
            fprintf('  [调试Tx] 扰码后前10比特: [%d %d %d %d %d %d %d %d %d %d]\n', paddedBits(1:min(10, end)));
        end

        debugTx.bitsPerSymbol = bitsPerSymbol;
        debugTx.sysParam = sysParam;
        debugTx.pilotIndices = pilotIndices;
        debugTx.dataIndices = dataIndices;
        debugTx.nOFDMSymbols = nOFDMSymbols;
        debugTx.totalDataSymbols = totalDataSymbols; % 旋转序列作用的符号总数
        debugTx.pilotPowerBoost = config.pilotPowerBoost;

        if ~isempty(rotationSeq)
            debugTx.rotationSeqLength = length(rotationSeq); % 应与totalDataSymbols相等
        else
            debugTx.rotationSeqLength = 0; % 旋转禁用时为0
        end

        debugTx.modSymbolsRotated = modSymbols(1:min(100, length(modSymbols))); % 旋转后的前100个符号（禁用时即为原始符号）
    else
        debugTx = struct();
    end

    if nargout >= 4
        frameMeta = struct();
        frameMeta.frameLengthSamples = length(frame);
        frameMeta.dataSymbolCount = totalDataSymbols;
        frameMeta.ofdmSymbolCount = nOFDMSymbols;
    end

end

%% ==================== 辅助函数 ====================

function uwSeq = generateUWSequence(seqLength, waveformParams)
    % 参考专利[US12003350B1]：128-sample BPSK code word, PN-rotated into QPSK
    % repeated 8 times within 1024 symbols.
    %
    % [修正逻辑 - 2025-11-19] UW生成逻辑修正：
    % 1. 之前的逻辑是先插值(Resample)再旋转(Rotation)，这会导致物理层含义错误，
    %    因为π/2-BPSK旋转是在"符号"层级定义的，而非"采样点"层级。
    % 2. 修正后的逻辑：
    %    (1) 在标称符号率(1024 symbols)下生成BPSK序列并进行π/2旋转。
    %    (2) 对旋转后的复数符号序列进行Resample插值到目标采样率(1152 samples)。
    % 3. 这样的生成方式保证了：
    %    - 符号间的相位跃变严格符合π/2定义。
    %    - 插值滤波器保证了波形的平滑过渡和正确的频谱特性，无带外泄露。

    if nargin < 2
        % 兼容旧调用（虽然不推荐，但防止报错）
        waveformParams = struct();
        waveformParams.uwNominalLength = 1024;
        waveformParams.uwBaseLength = 128;
        waveformParams.uwPoly = [8 4 3 2 0];
        waveformParams.uwInit = [1 0 0 0 0 0 0 1];
    end

    targetLength = seqLength; % 目标长度 (1152)
    nominalLength = waveformParams.uwNominalLength; % 标称长度 (1024)
    baseLen = waveformParams.uwBaseLength;

    % 1. 在标称率下生成 (60MHz)
    pnSeq = comm.PNSequence('Polynomial', waveformParams.uwPoly, ...
        'InitialConditions', waveformParams.uwInit, ...
        'SamplesPerFrame', baseLen);

    pnBits = step(pnSeq);
    uwBpsk = 2 * pnBits - 1; % BPSK: +1/-1

    % 重复8次填满 1024 长度
    reps = ceil(nominalLength / baseLen); % = 8
    tiled = repmat(uwBpsk, reps, 1);
    uwNominal = tiled(1:nominalLength);

    % 2. 应用频域旋转 (在标称符号层级应用，符合pi/2-BPSK定义)
    % 修正：先旋转，再重采样。确保符号间的相位跃变是准确的pi/2。
    rotation = exp(1j * (0:nominalLength - 1).' * pi / 2);
    uwNominalComplex = uwNominal .* rotation;

    % 3. 上采样到目标采样率 (60MHz -> 67.5MHz)
    % 使用resample对复数符号进行插值
    if targetLength ~= nominalLength
        [P, Q] = rat(targetLength / nominalLength); % P/Q = 9/8
        uwResampled = resample(uwNominalComplex, P, Q);

        % 修正重采样可能带来的微小长度误差
        if length(uwResampled) > targetLength
            uwResampled = uwResampled(1:targetLength);
        elseif length(uwResampled) < targetLength
            uwResampled = [uwResampled; zeros(targetLength - length(uwResampled), 1)];
        end

        uwSeq = uwResampled;
    else
        uwSeq = uwNominalComplex;
    end

    uwSeq = normalizeRMS(uwSeq, 1);
end

function seq = generateRotationSequence(n)
    % 生成确定性的频域旋转序列 [0,1,2,3] 循环
    base = repmat((0:3).', ceil(n / 4), 1);
    seq = base(1:n);
end

function pilotSymbols = generatePilotSymbols(nPilots)
    % 生成确定性的BPSK导频 (+1/-1) 序列
    bits = repmat([0; 1], ceil(nPilots / 2), 1);
    bits = bits(1:nPilots);
    pilotSymbols = pskmod(bits, 2);
end

function signalWithCP = addCyclicPrefixSuffix(signal, cpLen, csLen)
    % 添加循环前缀和循环后缀
    cp = signal(end - cpLen + 1:end);
    cs = signal(1:csLen);
    signalWithCP = [cp; signal; cs];
end

function signalOut = normalizeRMS(signalIn, targetRMS)
    % 对齐不同时域帧的RMS，保证发射信号的平均功率一致
    signalOut = signalIn;

    if targetRMS <= 0
        return;
    end

    currentRMS = sqrt(mean(abs(signalOut(:)) .^ 2));

    if currentRMS == 0
        return;
    end

    scale = targetRMS / currentRMS;
    signalOut = signalOut * scale;
end

function outSignal = applyCFR(inSignal, threshold_dB)
    % 峰值因数削减(CFR)
    threshold = 10 ^ (threshold_dB / 20);
    magnitude = abs(inSignal);
    phase = angle(inSignal);

    % 限幅
    clippedMag = min(magnitude, threshold * mean(magnitude));
    outSignal = clippedMag .* exp(1j * phase);
end

function outSignal = applyDPD(inSignal, coeffs)
    % 简化的多项式数字预失真(DPD)
    % y = a0*x + a1*x*|x|^2 + a2*x*|x|^4 + ...
    outSignal = zeros(size(inSignal));

    for k = 1:length(coeffs)
        outSignal = outSignal + coeffs(k) * inSignal .* (abs(inSignal) .^ (2 * (k - 1)));
    end

end

function config = mergeConfig(defaultConfig, userConfig)
    % 合并配置参数
    config = defaultConfig;

    if ~isempty(userConfig)
        fields = fieldnames(userConfig);

        for i = 1:length(fields)
            config.(fields{i}) = userConfig.(fields{i});
        end

    end

end
