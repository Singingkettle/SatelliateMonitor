function iq_noise = noise(spectrumConfig, varargin)
    % NOISE 生成纯噪声样本 (dataGen.signal.noise)
    %
    %   iq_noise = dataGen.signal.noise(spectrumConfig)
    %   iq_noise = dataGen.signal.noise(spectrumConfig, 'NumSamples', N, ...)
    %
    % 功能：
    %   生成基于系统噪声温度的复高斯白噪声
    %   用于模拟接收机热噪声底噪
    %
    % 可选参数:
    %   'NumSamples' - 样本数量 (默认从spectrumConfig获取)
    %   'Bandwidth'  - 噪声带宽 (Hz)
    %   'NoiseTemp'  - 噪声温度 (K，默认300K)
    %
    % 输出:
    %   iq_noise - 复高斯白噪声向量

    p = inputParser;
    addParameter(p, 'NumSamples', spectrumConfig.sampling.IQSampleLength, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'Bandwidth', spectrumConfig.sampling.bandwidth, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    defaultNoiseTemp = 300;

    if isfield(spectrumConfig, 'monitorAntenna') && ...
            isfield(spectrumConfig.monitorAntenna, 'systemNoiseTemp')
        defaultNoiseTemp = spectrumConfig.monitorAntenna.systemNoiseTemp;
    end

    addParameter(p, 'NoiseTemp', defaultNoiseTemp, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    parse(p, varargin{:});

    numSamples = round(p.Results.NumSamples);

    if numSamples <= 0
        iq_noise = complex(zeros(0, 1));
        return;
    end

    bandwidth = p.Results.Bandwidth;

    if isempty(bandwidth)
        bandwidth = spectrumConfig.sampling.bandwidth;
    end

    noiseTemp = p.Results.NoiseTemp;

    if isempty(noiseTemp)
        noiseTemp = defaultNoiseTemp;
    end

    % 噪声功率（基于系统噪声温度）
    k_B = 1.38064852e-23; % 玻尔兹曼常数 (J/K)
    P_noise = k_B * noiseTemp * bandwidth;

    % 噪声标准差
    sigma = sqrt(max(P_noise, 0) / 2);

    % 生成复高斯白噪声
    I_noise = sigma * randn(numSamples, 1);
    Q_noise = sigma * randn(numSamples, 1);
    iq_noise = complex(I_noise, Q_noise);

end
