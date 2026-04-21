function txSigImpaired = impairments(txSig, impairments, fc, fs)
    % IMPAIRMENTS 应用 RF 硬件损伤 (dataGen.signal.impairments)
    %
    %   txSigImpaired = dataGen.signal.impairments(txSig, impairments, fc, fs)
    %
    % 功能：
    %   模拟发射机硬件的非理想特性，生成RF指纹特征
    %
    % 损伤模型：
    %   1. 频率偏移 (ppm) - 本振漂移
    %   2. 相位噪声 (rms degrees) - 振荡器抖动
    %   3. DC 偏移 (dBc) - 混频器泄漏
    %
    % 输入:
    %   txSig       - 输入信号
    %   impairments - 损伤参数结构体 (.frequencyOffset, .phaseNoise, .dcOffset)
    %   fc          - 载波频率 (Hz)
    %   fs          - 采样率 (Hz)
    %
    % 输出:
    %   txSigImpaired - 叠加损伤后的信号

    % 1. 频率偏移
    freqOffsetHz = fc * (impairments.frequencyOffset / 1e6); % ppm -> Hz

    if freqOffsetHz ~= 0
        freqOffsetObj = comm.PhaseFrequencyOffset( ...
            'FrequencyOffset', freqOffsetHz, ...
            'SampleRate', fs);
        txSig = freqOffsetObj(txSig);
    end

    % 2. 相位噪声
    freqOffsetAbs = max(abs(freqOffsetHz), 1);
    phaseNoiseLevelDbc = helperGetPhaseNoise(impairments.phaseNoise, freqOffsetAbs);
    maxCommPhaseNoiseFs = 50e6; % comm.PhaseNoise becomes unstable for higher rates

    if ~isempty(phaseNoiseLevelDbc)

        if fs <= maxCommPhaseNoiseFs
            try
                phaseNoiseObj = comm.PhaseNoise( ...
                    'Level', phaseNoiseLevelDbc(:)', ...
                    'FrequencyOffset', freqOffsetAbs(:)', ...
                    'SampleRate', fs);
                txSig = phaseNoiseObj(txSig);
            catch
                % comm.PhaseNoise 在某些参数组合下不稳定，使用简化模型
                txSig = applySimplePhaseNoise(txSig, impairments.phaseNoise);
            end
        else
            txSig = applySimplePhaseNoise(txSig, impairments.phaseNoise);
        end

    end

    % 3. DC偏移
    dcOffsetLinear = 10 ^ (impairments.dcOffset / 10);
    txSigImpaired = txSig + dcOffsetLinear;

end

function sigOut = applySimplePhaseNoise(sigIn, rmsPhaseNoiseDeg)
    % 简化相位噪声模型 (用于高采样率场景，comm.PhaseNoise不稳定时的备选)
    sigOut = sigIn;

    if isempty(rmsPhaseNoiseDeg) || rmsPhaseNoiseDeg <= 0
        return;
    end

    sigmaRad = rmsPhaseNoiseDeg * pi / 180;
    alpha = 0.999; % emphasize low-frequency drift
    noise = sigmaRad * filter(1 - alpha, [1 - alpha], randn(size(sigIn)));
    sigOut = sigIn .* exp(1j * noise);
end

function phaseNoiseLevel_dBc = helperGetPhaseNoise(rmsPhaseNoise, freqOffset)
    % HELPERGETPHASENOISE 将RMS相位噪声转换为dBc/Hz功率谱密度
    % 简化模型，参考 MathWorks WLAN Example
    % 这里的 mask 只是示意，实际应基于 rmsPhaseNoise 生成 profile
    % 为简化，我们只生成单一频偏点的值
    % 实际应用中应构建完整的 mask

    % 简单的线性近似：更高 rms -> 更高 noise floor
    % Base level at 1kHz offset
    baseLevel = -100 + 20 * log10(rmsPhaseNoise / 0.1);

    % Decay 20dB/dec
    phaseNoiseLevel_dBc = baseLevel - 20 * log10(freqOffset / 1000);

    % Cap at -40 to -150
    phaseNoiseLevel_dBc = max(min(phaseNoiseLevel_dBc, -40), -150);
end
