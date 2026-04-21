function [iq, timeMask] = receive(rxWaveform, txInfo, config, slotStartIdx)
    % RECEIVE 宽带接收处理 (dataGen.link.receive)
    %
    %   [iq, timeMask] = dataGen.link.receive(rxWaveform, txInfo, config, slotStartIdx)
    %
    % 功能：
    %   模拟伴飞卫星的宽带接收过程：
    %   - 上变频到指定子信道
    %   - 重采样到宽带采样率
    %   - 在指定时隙位置插入信号
    %
    %   此函数仅用于宽带数据生成，干扰数据直接使用基带信号
    %
    % 输入:
    %   rxWaveform  - 接收波形 (基带)
    %   txInfo      - 发射信息 (包含子信道信息)
    %   config      - spectrumConfig
    %   slotStartIdx - 时隙起始索引 (可选)
    %
    % 输出:
    %   iq       - 宽带 IQ 信号
    %   timeMask - 时域掩码

    if nargin < 4
        slotStartIdx = [];
    end

    % 调用 wideband 采样函数
    [iq, timeMask] = dataGen.signal.wideband(rxWaveform, txInfo.sampleRate, ...
        config.broadband.sampling.sampleRate, ...
        config.broadband.sampling.IQSampleLength, ...
        'ChannelIndex', txInfo.channelIndex, ...
        'ChannelSpacing', txInfo.channelSpacing, ...
        'NumChannels', txInfo.numChannels, ...
        'ReferenceIndex', txInfo.referenceChannelIndex, ...
        'InsertRandomly', isempty(slotStartIdx), ...
        'StartIndex', slotStartIdx, ...
        'Bandwidth', txInfo.bandwidth);
end

