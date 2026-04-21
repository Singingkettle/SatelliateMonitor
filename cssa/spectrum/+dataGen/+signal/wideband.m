function [outputIQ, timeMask] = wideband(inputIQ, inputFs, outputFs, outputLength, varargin)
    % WIDEBAND 宽带接收机采样仿真 (dataGen.signal.wideband)
    %
    %   [outputIQ, timeMask] = dataGen.signal.wideband(inputIQ, inputFs, outputFs, outputLength, ...)
    %
    % 功能：
    %   将基带信号重采样到宽带采样率，进行频率搬移，并插入到指定时隙
    %   模拟伴飞卫星宽带接收机的数字化过程
    %
    % 输入:
    %   inputIQ      - 基带输入信号
    %   inputFs      - 输入采样率 (Hz)
    %   outputFs     - 输出采样率 (Hz)
    %   outputLength - 输出长度 (样本数)
    %
    % 可选参数:
    %   'ChannelIndex'   - 子信道索引
    %   'ChannelSpacing' - 信道间隔 (Hz)
    %   'NumChannels'    - 信道总数
    %   'ReferenceIndex' - 参考信道索引 (用于计算频偏)
    %   'InsertRandomly' - 是否随机插入位置 (默认true)
    %   'StartIndex'     - 指定插入起始索引
    %   'Bandwidth'      - 信号带宽 (用于低通滤波)
    %
    % 输出:
    %   outputIQ - 宽带IQ信号
    %   timeMask - 时域掩码 (true表示有信号)

    p = inputParser;
    addParameter(p, 'ChannelIndex', 1);
    addParameter(p, 'ChannelSpacing', 0);
    addParameter(p, 'NumChannels', 1);
    addParameter(p, 'ReferenceIndex', 1);
    addParameter(p, 'InsertRandomly', true);
    addParameter(p, 'StartIndex', []);
    addParameter(p, 'Bandwidth', []); % 信号带宽，用于低通滤波设计
    parse(p, varargin{:});

    channelIndex = p.Results.ChannelIndex;
    channelSpacing = p.Results.ChannelSpacing;
    refIndex = p.Results.ReferenceIndex;

    % 1. 重采样

    % 计算频偏
    freqOffset = (channelIndex - refIndex) * channelSpacing;

    % 创建全零宽带容器
    outputIQ = complex(zeros(outputLength, 1), zeros(outputLength, 1));
    timeMask = false(outputLength, 1);

    if isempty(inputIQ)
        % Empty input signal - return zero output (noise is added separately in generate.m)
        return;
    end

    % 1. 先重采样（避免先搬移后重采样导致的信号失真）
    [p_num, q_den] = rat(outputFs / inputFs);
    resampledIQ = resample(inputIQ, p_num, q_den);

    lenResampled = length(resampledIQ);

    % 2. 低通滤波（限制带外泄露）
    if ~isempty(p.Results.Bandwidth) && p.Results.Bandwidth > 0
        bandwidth = p.Results.Bandwidth;
        % 截止频率设为带宽的一半，但不超过奈奎斯特频率的90%
        cutoffFreq = min(bandwidth / 2, outputFs / 2 * 0.9);
        cutoffFreq = max(cutoffFreq, outputFs / 1000); % 至少为采样率的1/1000

        try
            % 设计FIR低通滤波器
            filterOrder = min(100, max(10, floor(lenResampled / 20)));
            lpFilter = designfilt('lowpassfir', ...
                'FilterOrder', filterOrder, ...
                'CutoffFrequency', cutoffFreq, ...
                'SampleRate', outputFs);
            filteredIQ = filter(lpFilter, resampledIQ);
        catch
            % 如果滤波器设计失败，使用简单的移动平均作为fallback
            windowSize = max(3, floor(outputFs / cutoffFreq / 10));
            filteredIQ = movmean(resampledIQ, windowSize);
        end

    else
        % 如果没有提供带宽信息，跳过滤波
        filteredIQ = resampledIQ;
    end

    % 3. 再搬移（基于重采样后的采样率）
    lenFiltered = length(filteredIQ);
    t = (0:lenFiltered - 1)' / outputFs;
    shiftedIQ = filteredIQ .* exp(1j * 2 * pi * freqOffset * t);

    % 4. 插入位置
    lenShifted = length(shiftedIQ);

    if lenShifted >= outputLength
        outputIQ = shiftedIQ(1:outputLength);
        timeMask(:) = true;
    else

        maxStart = outputLength - lenShifted + 1;
        startIdxParam = p.Results.StartIndex;

        if ~isempty(startIdxParam)
            startIdx = round(startIdxParam);
            startIdx = max(1, min(maxStart, startIdx));
        elseif p.Results.InsertRandomly
            maxStart = outputLength - lenShifted + 1;
            startIdx = randi(maxStart);
        else
            startIdx = floor((outputLength - lenShifted) / 2) + 1;
        end

        endIdx = startIdx + lenShifted - 1;

        outputIQ(startIdx:endIdx) = shiftedIQ;
        timeMask(startIdx:endIdx) = true;
    end

end
