function [label, stat] = label(txInfo, txParams, chState, terminalProfile, ...
        timeMask, iq, config, options, enableWideband, bwMode, terminalIndex)
    % LABEL 构建信号标签和统计信息 (dataGen.link.label)
    %
    %   [label, stat] = dataGen.link.label(...)
    %
    % 功能：
    %   从发射、信道、接收信息构建统一的标签结构
    %   可被干扰数据和宽带数据生成共用
    %
    % 输入:
    %   txInfo          - 发射信息
    %   txParams        - 发射参数
    %   chState         - 信道状态
    %   terminalProfile - 终端配置
    %   timeMask        - 时域掩码
    %   iq              - 输出信号 (用于计算时域信息)
    %   config          - spectrumConfig
    %   options         - 生成选项
    %   enableWideband  - 是否宽带模式
    %   bwMode          - 带宽模式
    %   terminalIndex   - 终端索引
    %
    % 输出:
    %   label - 信号标签
    %   stat  - 统计信息

    % 从终端配置提取
    rfMeta = terminalProfile.rfMeta;
    tid = terminalProfile.tid;
    txPowerBackoff_dB = terminalProfile.txPowerBackoff_dB;
    modulation = terminalProfile.modulation;
    codeRate = terminalProfile.codeRate;

    % 基础标签
    label.signalPresent = 1;
    label.constellation = txInfo.constellation;
    label.centerFreq = txInfo.carrierFrequency;
    label.bandwidth = txInfo.bandwidth;
    label.bandwidthMode = bwMode;
    label.modulation = modulation;
    label.codeRate = codeRate;
    label.utId = tid;
    label.txPower_dBm = 10 * log10(txParams.txPower * 1000);
    label.txPowerBackoff_dB = txPowerBackoff_dB;
    label.terminalIndex = terminalIndex;

    % 终端类型
    if isfield(rfMeta, 'type')
        label.terminalType = rfMeta.type;
    end

    % 发射比特
    label.txBits = txInfo.txBits;

    % 频率偏移 (多普勒 + RF 损伤)
    rfFreqOffset = 0;
    if ~isempty(rfMeta) && isfield(rfMeta, 'frequencyOffset')
        rfFreqOffset = rfMeta.frequencyOffset;
    end
    label.freqOffset = chState.dopplerShift + rfFreqOffset * 1e-6 * txInfo.carrierFrequency;

    % 时域信息
    tIndices = find(timeMask);
    
    if enableWideband
        fs = config.broadband.sampling.sampleRate;
    else
        fs = txInfo.sampleRate;
    end

    if ~isempty(tIndices)
        label.signalStart = (tIndices(1) - 1) / fs;
        label.signalEnd = (tIndices(end) - 1) / fs;
    else
        label.signalStart = 0;
        label.signalEnd = 0;
    end

    label.signalDuration = label.signalEnd - label.signalStart;
    label.sampleRate = fs;

    if isfield(options, 'imageSize')
        label.imageSize = options.imageSize;
    end
    if isfield(options, 'nfft')
        label.nfft = options.nfft;
    end

    % 样本时长
    if enableWideband
        label.sampleDuration = config.broadband.sampling.IQSampleLength / fs;
    else
        label.sampleDuration = numel(iq) / fs;
    end

    % MCS 和载荷信息
    label.mcsIndex = txParams.mcsIndex;
    label.payloadLength = txInfo.payloadLength;
    label.channelState = chState;

    if isfield(txInfo, 'channelIndex')
        label.channelIndex = txInfo.channelIndex;
    end

    if isfield(txInfo, 'frameMeta') && isfield(txInfo.frameMeta, 'frameLengthSamples')
        label.frameLengthSamples = txInfo.frameMeta.frameLengthSamples;
    else
        label.frameLengthSamples = numel(iq);
    end

    % 截断信息标注
    % 开始截断：burst在观察窗口开始前就已存在，只能看到后半部分
    % 结束截断：burst在观察窗口结束时被截断，只能看到前半部分
    label.isTruncatedStart = false;
    label.isTruncatedEnd = false;
    label.truncatedStartSamples = 0;
    label.truncatedEndSamples = 0;
    label.fullWaveformLength = numel(iq);
    label.visibleWaveformLength = numel(iq);
    
    if isfield(txInfo, 'isTruncatedStart') && txInfo.isTruncatedStart
        label.isTruncatedStart = true;
        if isfield(txInfo, 'truncatedStartSamples')
            label.truncatedStartSamples = txInfo.truncatedStartSamples;
        end
    end
    
    if isfield(txInfo, 'isTruncatedEnd') && txInfo.isTruncatedEnd
        label.isTruncatedEnd = true;
        if isfield(txInfo, 'truncatedEndSamples')
            label.truncatedEndSamples = txInfo.truncatedEndSamples;
        end
    end
    
    if isfield(txInfo, 'fullWaveformLength')
        label.fullWaveformLength = txInfo.fullWaveformLength;
    end
    if isfield(txInfo, 'visibleWaveformLength')
        label.visibleWaveformLength = txInfo.visibleWaveformLength;
    end
    
    % 旁瓣接收信息（用于分析和可视化）
    label.offBoresightDeg = 0;
    label.offBoresightLoss_dB = 0;
    label.sidelobeSimulated = false;
    label.sidelobeRegion = 'none';
    if isfield(chState, 'offBoresightDeg')
        label.offBoresightDeg = chState.offBoresightDeg;
    end
    if isfield(chState, 'offBoresightLoss_dB')
        label.offBoresightLoss_dB = chState.offBoresightLoss_dB;
    end
    if isfield(chState, 'sidelobeSimulated')
        label.sidelobeSimulated = chState.sidelobeSimulated;
    end
    if isfield(chState, 'sidelobeRegion')
        label.sidelobeRegion = chState.sidelobeRegion;
    end

    % 统计信息
    if isfield(chState, 'physical') && isfield(chState.physical, 'SNR_dB')
        stat.channelSNR = chState.physical.SNR_dB;
    else
        stat.channelSNR = chState.SNR;
    end

    % 纯净信号功率 (加噪声前)
    stat.cleanSignalPower = mean(abs(iq).^2);
    stat.cleanSignalEnergy = sum(abs(iq).^2);
    stat.cleanSignalLength = numel(iq);
    stat.modulation = txInfo.modulation;
    stat.terminalIndex = terminalIndex;
    
    % 截断统计信息
    stat.isTruncatedStart = label.isTruncatedStart;
    stat.isTruncatedEnd = label.isTruncatedEnd;
    stat.truncatedStartSamples = label.truncatedStartSamples;
    stat.truncatedEndSamples = label.truncatedEndSamples;
end

