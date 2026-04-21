function [sample, label, stat] = silence(spectrumConfig, options, constellation)
    % SILENCE 生成静默（纯噪声）样本 (dataGen.signal.silence)
    %
    %   [sample, label, stat] = dataGen.signal.silence(spectrumConfig, options)
    %   [sample, label, stat] = dataGen.signal.silence(spectrumConfig, options, constellation)
    %
    % 功能：
    %   生成不包含任何信号的纯噪声样本，用于：
    %   - 训练数据中的负样本
    %   - 无法建链时的降级处理
    %
    % 输出:
    %   sample - 包含 iq_data 的结构体
    %   label  - 标签（signalPresent=0）
    %   stat   - 统计信息

    % 生成纯噪声
    sample.iq_data = dataGen.signal.noise(spectrumConfig);

    % 确定星座名称
    if nargin >= 3 && ~isempty(constellation)
        constName = constellation;
    elseif isfield(spectrumConfig, 'constellation') && ~isempty(spectrumConfig.constellation)
        constName = spectrumConfig.constellation;
    else
        constName = 'noise';  % 更好的默认值
    end

    % 标签
    label.signalPresent = 0;
    label.constellation = constName;
    label.SNR = -inf;
    label.bandwidthMode = 'noise';
    label.modulation = 'noise';
    label.bursts = [];

    if nargin >= 2 && isstruct(options)
        if isfield(options, 'imageSize')
            label.imageSize = options.imageSize;
        end
        if isfield(options, 'nfft')
            label.nfft = options.nfft;
        end
    end

    % 样本时长
    label.sampleDuration = spectrumConfig.broadband.sampling.duration;

    % 统计
    stat.SNR = -inf;
    stat.signalPresent = 0;
    stat.bursts = [];
end

