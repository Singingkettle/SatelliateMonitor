function [txSignal, channelInfo, debugTx, frameMeta] = upTx(dataBits, config)
    % UPTX OneWeb用户终端上行链路基带调制与发射仿真
    % 基于OneWeb Ku段FCC技术附件实现SC-FDMA发射处理
    %
    % 输入参数:
    %   dataBits - 输入比特流
    %   config   - 配置参数（可选），包含:
    %             .mcs          - 调制编码方案索引 (1-10)
    %             .channelIndex   - 子信道索引 (1-12)
    %             .txPower      - 发射功率 (dBm)
    %             .beamAngle    - 波束指向角 [方位, 俯仰]
    %             .enableCFR    - 是否启用峰均比抑制
    %             .enableDPD    - 是否启用数字预失真
    %             .verbose      - 是否打印详细日志 (默认true)
    %
    % 输出参数:
    %   txSignal    - 复基带发射信号
    %   channelInfo - 频率与带宽信息
    %   debugTx     - 调试信息
    %   frameMeta   - 帧元数据（符号数、采样率等）
    %
    % 参考文献:
    %   [1] FCC IBFS File No. SAT-AMD-20161115-00118, OneWeb Ku-band Technical Attachment, 2016
    %   [2] ETSI TR 103 611 V1.1.1, Satellite IMT systems for dense urban access, 2018
    %   [3] R&S Application Card, Generate OneWeb-Compliant Signals for Receiver Tests
    %
    % 说明:
    %   - OneWeb Ku段用户终端采用SC-FDMA（单载波频分多址），20 MHz带宽，基于LTE标准
    %   - 终端最大发射功率2 W（33 dBm），最大EIRP 35 dBW
    %
    % ==================== 参数初始化 ====================
    if nargin < 2
        config = struct();
    end

    % 从配置文件获取物理层参数
    % Ku上行14.0-14.5 GHz, 单载波20 MHz（SC-FDMA / LTE参数集）
    phyParams = constellationPhyConfig('oneweb');

    % 合并用户配置和默认配置（从配置文件获取默认值）
    config = mergeConfig(phyParams.defaultTxConfig, config);
    verbose = config.verbose;

    %% ==================== 系统参数 ====================

    sysParam = struct();
    sysParam.nfft = phyParams.waveform.nfft;
    sysParam.nSubcarriers = phyParams.waveform.nSubcarriers;

    % 根据带宽模式获取参数 (统一接口)
    bwMode = config.bandwidthMode;
    modeKey = bwMode;

    if isfield(phyParams.channelization.modes, modeKey)
        modeParams = phyParams.channelization.modes.(modeKey);
    else
        error('OneWeb:InvalidMode', '不支持的带宽模式: %s', bwMode);
    end

    sysParam.bandwidth = modeParams.bandwidth;
    sysParam.sampleRate = modeParams.sampleRate;
    sysParam.subcarrierSpacing = phyParams.waveform.subcarrierSpacing; % SC-FDMA通常固定15kHz
    sysParam.cpLength = modeParams.cpLength;
    sysParam.cpLengthOther = phyParams.waveform.cpLengthOther;
    sysParam.symbolsPerSlot = phyParams.waveform.symbolsPerSlot;
    sysParam.slotsPerSubframe = phyParams.waveform.slotsPerSubframe;
    sysParam.subframeDuration = phyParams.waveform.subframeDuration;

    % MCS表 (与 constellationPhyConfig.m 保持一致)
    mcsTable = phyParams.mcsTable(:, 2:3);

    modOrder = mcsTable(config.mcs, 1);
    codeRate = mcsTable(config.mcs, 2);

    %% ==================== 1. LDPC编码（先确定长度） ====================
    if verbose
        fprintf('OneWeb: 准备LDPC编码 (码率 %.3f)...\n', codeRate);
    end

    parityCheckMatrix = selectLDPCMatrix(codeRate);
    parityCheckMatrix = sparse(parityCheckMatrix);
    ldpcCfg = ldpcEncoderConfig(parityCheckMatrix);

    K = size(parityCheckMatrix, 2) - size(parityCheckMatrix, 1);
    N = size(parityCheckMatrix, 2);

    % 先截断或填充到LDPC的K长度
    if length(dataBits) < K
        inputBits = [dataBits(:); zeros(K - length(dataBits), 1)];
    else
        inputBits = dataBits(1:K);
    end

    %% ==================== 2. 扰码（对截断后的数据） ====================
    if verbose
        fprintf('OneWeb: 执行扰码处理...\n');
    end

    % 从配置文件获取扰码参数
    polyVec = phyParams.coding.scramblerPoly;
    initState = phyParams.coding.scramblerInit;
    scrObj = comm.Scrambler('CalculationBase', 2, ...
        'Polynomial', polyVec, 'InitialConditions', initState);
    scrambledBits = scrObj(double(inputBits));

    %% ==================== 3. LDPC编码 ====================
    if verbose
        fprintf('OneWeb: 执行LDPC编码...\n');
    end

    encodedBits = ldpcEncode(scrambledBits, ldpcCfg);

    %% ==================== 3. 比特交织 ====================
    if verbose
        fprintf('OneWeb: 执行比特交织...\n');
    end

    bitsPerSymbol = log2(modOrder);
    % 从配置读取导频符号位置
    dmrsIndices = phyParams.waveform.dmrsSymbolIndices;

    % 确定帧结构参数
    symsPerSlot = sysParam.symbolsPerSlot;
    slotsPerSubframe = sysParam.slotsPerSubframe;
    symsPerSubframe = symsPerSlot * slotsPerSubframe;

    % 计算有效数据符号数量（扣除DMRS符号）
    isDmrsSymbol = false(symsPerSubframe, 1);
    isDmrsSymbol(dmrsIndices) = true;
    numDataSymsPerSubframe = sum(~isDmrsSymbol);

    nSubcarriers = sysParam.nSubcarriers; % SC-FDMA分配带宽 (DFT大小)
    nDataPerSym = nSubcarriers; % SC-FDMA数据填满分配带宽

    blockLen = nDataPerSym * bitsPerSymbol; % 每个SC-FDMA符号的比特数

    % 计算需要的总子帧数
    totalBits = length(encodedBits);
    bitsPerSubframe = numDataSymsPerSubframe * blockLen;
    numSubframes = ceil(totalBits / bitsPerSubframe);

    interleaverLen = numSubframes * bitsPerSubframe;

    if length(encodedBits) < interleaverLen
        encodedBits = [encodedBits; zeros(interleaverLen - length(encodedBits), 1)];
    else
        encodedBits = encodedBits(1:interleaverLen);
    end

    % 矩阵交织 (按子帧交织)
    rows = interleaverLen / blockLen;
    interleavedBits = matintrlv(encodedBits, rows, blockLen);

    %% ==================== 4. 调制映射 ====================
    if verbose
        fprintf('OneWeb: 执行%d-QAM映射...\n', modOrder);
    end

    if modOrder == 2
        modSymbols = pskmod(interleavedBits, 2, pi / 2, 'InputType', 'bit'); % BPSK, Gray映射
    else
        modSymbols = qammod(interleavedBits, modOrder, 'InputType', 'bit', 'UnitAveragePower', true);
    end

    %% ==================== 5. SC-FDMA帧构建 (DFT-s-OFDM) ====================
    if verbose
        fprintf('OneWeb: 构建SC-FDMA帧...\n');
    end

    uwSeq = generateUWSequence(sysParam.nfft, phyParams.waveform.uwPoly, phyParams.waveform.uwInit);
    dmrsCfg = phyParams.waveform.dmrs;
    dmrsFreqSeq = oneweb.generateDMRSSequence(sysParam.nSubcarriers, dmrsCfg);

    % SC-FDMA DMRS功率提升：
    % 数据符号经过DFT预编码后，频域幅度约为sqrt(Nsc)。
    % ZC序列幅度为1。为保持时域功率一致（PAPR特性），需在频域对DMRS进行缩放。
    dmrsFreqSeq = dmrsFreqSeq * sqrt(sysParam.nSubcarriers);

    % 初始化输出帧结构
    nTotalSyms = numSubframes * symsPerSubframe;
    ofdmSymbols = zeros(sysParam.nfft, nTotalSyms);

    dataSymIdx = 1;

    % 重塑调制符号以方便按SC-FDMA符号处理
    allDataSymbols = reshape(modSymbols, nDataPerSym, []);

    for sIdx = 1:nTotalSyms
        % 确定当前符号在子帧内的索引 (1-based)
        currentSymInSubframe = mod(sIdx - 1, symsPerSubframe) + 1;

        scMap = zeros(sysParam.nfft, 1);
        % 集中式映射 (Localized Mapping) - 将信号放在FFT中心
        % 排除DC (OneWeb/LTE通常不使用DC子载波，或者是半子载波移位)
        % 这里简化实现：直接映射到中心，包含DC
        carrierIndices = (sysParam.nfft / 2 - nSubcarriers / 2 + 1):(sysParam.nfft / 2 + nSubcarriers / 2);

        if ismember(currentSymInSubframe, dmrsIndices)
            % === DMRS 符号 ===
            % DMRS采用Zadoff-Chu CAZAC序列 (3GPP TS 36.211 §5.5)
            scMap(carrierIndices) = dmrsFreqSeq;
        else
            % === 数据符号 (SC-FDMA) ===
            if dataSymIdx <= size(allDataSymbols, 2)
                timeSym = allDataSymbols(:, dataSymIdx);
                dataSymIdx = dataSymIdx + 1;

                % 1. M-point DFT (Precoding)
                dftOut = fft(timeSym, nSubcarriers);

                % 2. Subcarrier Mapping
                % fft输出是[DC, Pos, Neg]，我们需要将其映射为[Neg, DC, Pos]到频谱中心
                scMap(carrierIndices) = fftshift(dftOut);
            end

        end

        % 3. N-point IFFT
        % Shift zero-frequency component to center of spectrum
        ofdmSymbols(:, sIdx) = ifft(ifftshift(scMap), sysParam.nfft);
    end

    cpLen = sysParam.cpLength;
    ofdmWithCP = zeros(sysParam.nfft + cpLen, nTotalSyms);

    for symIdx = 1:nTotalSyms
        sym = ofdmSymbols(:, symIdx);
        cp = sym(end - cpLen + 1:end);
        ofdmWithCP(:, symIdx) = [cp; sym];
    end

    % 参考专利/工程实践：确保不同帧成分（UW, Data）的时域平均功率一致
    % 这对接收机AGC和同步检测至关重要，防止功率跳变导致性能下降。
    dataTimeWaveform = ofdmWithCP(:);
    dataRMS = sqrt(mean(abs(dataTimeWaveform) .^ 2));

    % 如果数据段全零（极端情况），避免除零
    if dataRMS > 0
        uwSeq = normalizeRMS(uwSeq, dataRMS);
    end

    frame = [uwSeq; ofdmWithCP(:)];

    %% ==================== 6. 数字前端处理 ====================
    if verbose
        fprintf('OneWeb: 数字前端处理...\n');
    end

    shaped = frame; % 直接使用OFDM帧，保持30.72 Msps采样率（符合20 MHz LTE标准）

    if config.enableCFR
        shaped = applyCFR(shaped, phyParams.cfrThreshold_dB);
    end

    if config.enableDPD
        shaped = applyDPD(shaped, phyParams.ut.dpdCoeffs);
    end

    %% ==================== 7. 功率控制 ====================
    if verbose
        fprintf('OneWeb: 匹配功率...\n');
    end

    startFreq = phyParams.channelization.startFreq;

    % 使用模式特定的信道间隔
    if isfield(modeParams, 'channelSpacing')
        channelSpacing = modeParams.channelSpacing;
    else
        channelSpacing = 50e6; % Fallback
    end

    if isfield(modeParams, 'numChannels')
        numChannels = modeParams.numChannels;
    else
        numChannels = 1;
    end

    centerFreq = startFreq + (config.channelIndex - 0.5) * channelSpacing;

    currentPower = mean(abs(shaped) .^ 2);
    targetPower_W = min(10 ^ (config.txPower / 10) / 1000, 2.0); % 限制在2 W
    scaleFactor = sqrt(targetPower_W / currentPower);
    txSignal = shaped * scaleFactor;

    %% ==================== 输出配置 ====================
    % 存储信道信息 (统一驼峰命名风格)
    channelInfo.carrierFrequency = centerFreq;
    channelInfo.bandwidth = sysParam.bandwidth;
    channelInfo.sampleRate = sysParam.sampleRate;
    channelInfo.channelIndex = config.channelIndex;
    channelInfo.frequencyRange = [centerFreq - sysParam.bandwidth / 2, centerFreq + sysParam.bandwidth / 2];
    channelInfo.channelSpacing = channelSpacing;
    channelInfo.numChannels = numChannels;
    channelInfo.referenceChannelIndex = (numChannels + 1) / 2;

    %% ==================== 可选调试输出 ====================
    if nargout >= 3
        debugTx.K = K;
        debugTx.N = N;
        debugTx.inputBits = inputBits;
        debugTx.scrambledBits = scrambledBits;
        debugTx.encodedBits = encodedBits(1:min(length(encodedBits), 1000));
        debugTx.interleavedBits = interleavedBits(1:min(length(interleavedBits), 1000));
        debugTx.modSymbols = modSymbols(1:min(64, numel(modSymbols)));
        debugTx.sysParam = sysParam;
    else
        debugTx = struct();
    end

    % frameMeta 总是生成（与starlink.upTx保持一致）
    if nargout >= 4
        frameMeta = struct();
        frameMeta.subframeDuration_s = sysParam.subframeDuration;
        frameMeta.numSubframes = ceil(nTotalSyms / (sysParam.symbolsPerSlot * sysParam.slotsPerSubframe));
        frameMeta.totalSamples = length(txSignal);
        frameMeta.sampleRate = sysParam.sampleRate;
    end

    if verbose
        fprintf('OneWeb: 发射链路完成，输出长度 %d 样点。\n', length(txSignal));
    end

end

%% ==================== 辅助函数 ====================
function parityCheckMatrix = selectLDPCMatrix(codeRate)
    % 选择合适的DVB-S2 LDPC矩阵，优先使用新API
    if exist('ldpcPCM', 'file')

        try
            parityCheckMatrix = ldpcPCM(codeRate, 'short');
            return;
        catch
        end

    end

    if exist('dvbsLDPCPCM', 'file')

        try
            parityCheckMatrix = dvbsLDPCPCM(codeRate, 'short');
            return;
        catch
        end

    end

    switch codeRate
        case 1/2
            parityCheckMatrix = dvbs2ldpc(1/2);
        case 2/3
            parityCheckMatrix = dvbs2ldpc(2/3);
        case 3/4
            parityCheckMatrix = dvbs2ldpc(3/4);
        case 5/6
            parityCheckMatrix = dvbs2ldpc(5/6);
        otherwise
            parityCheckMatrix = dvbs2ldpc(2/3);
    end

end

function uwSeq = generateUWSequence(len, poly, init)
    pn = comm.PNSequence('Polynomial', poly, ...
        'InitialConditions', init, 'SamplesPerFrame', len);
    uwBits = step(pn);
    uwSeq = 2 * uwBits - 1;
end

function outSignal = applyCFR(inSignal, threshold_dB)
    threshold = 10 ^ (threshold_dB / 20);
    magnitude = abs(inSignal);
    phase = angle(inSignal);
    clipped = min(magnitude, threshold * mean(magnitude));
    outSignal = clipped .* exp(1j * phase);
end

function outSignal = applyDPD(inSignal, coeffs)
    outSignal = zeros(size(inSignal));

    for k = 1:length(coeffs)
        outSignal = outSignal + coeffs(k) * inSignal .* (abs(inSignal) .^ (2 * (k - 1)));
    end

end

function config = mergeConfig(defaultConfig, userConfig)
    config = defaultConfig;

    if ~isempty(userConfig)
        fields = fieldnames(userConfig);

        for i = 1:length(fields)
            config.(fields{i}) = userConfig.(fields{i});
        end

    end

end

function signalOut = normalizeRMS(signalIn, targetRMS)
    % 对齐不同时域帧的RMS，保证发射信号的平均功率一致
    % 此函数用于确保UW与数据段的功率平�
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
