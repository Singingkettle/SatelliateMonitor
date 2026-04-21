function [rxWaveform, chState, linkParams] = channel(txWaveform, txInfo, terminalProfile, ...
        monSatPos, monSatVel, commSatPos, weatherCond, timeInstant, receiverCfg, enableWideband)
    % CHANNEL 信道传播模型 (dataGen.link.channel)
    %
    %   [rxWaveform, chState, linkParams] = dataGen.link.channel(txWaveform, txInfo, ...)
    %
    % 功能：
    %   模拟信号从终端到监测卫星的传播
    %   此函数是高级接口，内部调用原子操作 dataGen.link.propagate
    %
    % 输入:
    %   txWaveform      - 发射波形
    %   txInfo          - 发射信息 (来自 dataGen.link.transmit)
    %   terminalProfile - 终端配置
    %   monSatPos       - 监测卫星位置 (ECEF)
    %   monSatVel       - 监测卫星速度 (ECEF)
    %   commSatPos      - 通信卫星位置 (ECEF，用于仰角参考)
    %   weatherCond     - 天气条件
    %   timeInstant     - 时间戳
    %   receiverCfg     - 接收机配置
    %   enableWideband  - 是否宽带模式
    %
    % 输出:
    %   rxWaveform - 接收波形 (未加噪声)
    %   chState    - 信道状态
    %   linkParams - 链路参数
    %
    % 参见: dataGen.link.propagate (原子操作，供数字孪生直接调用)

    % 从终端配置提取位置
    utPos = terminalProfile.utPos;

    % 构建链路参数
    linkParams = struct();
    linkParams.constellation = txInfo.constellation;
    linkParams.utPosition = utPos;
    linkParams.satPosition = monSatPos;
    linkParams.satVelocity = monSatVel;
    linkParams.frequency = txInfo.carrierFrequency;
    linkParams.bandwidth = txInfo.bandwidth;
    linkParams.txPower = txInfo.txPower;
    linkParams.weatherCond = weatherCond;
    linkParams.commSatPosition = commSatPos;
    linkParams.sampleRate = txInfo.sampleRate;

    % 接收机参数
    linkParams.rxGain = receiverCfg.rxGain;
    linkParams.GT = receiverCfg.GT;
    if isfield(receiverCfg, 'polarization')
        linkParams.polarization = receiverCfg.polarization;
    end
    if isfield(receiverCfg, 'enableOffBoresightLoss')
        linkParams.enableOffBoresightLoss = receiverCfg.enableOffBoresightLoss;
    end
    if isfield(receiverCfg, 'offBoresightLossMethod')
        linkParams.offBoresightLossMethod = receiverCfg.offBoresightLossMethod;
    end
    if isfield(receiverCfg, 'manualOffBoresightLoss')
        linkParams.manualOffBoresightLoss = receiverCfg.manualOffBoresightLoss;
    end
    
    % 旁瓣接收配置
    if isfield(receiverCfg, 'enableSidelobeReception')
        linkParams.enableSidelobeReception = receiverCfg.enableSidelobeReception;
    end
    if isfield(receiverCfg, 'sidelobeProbability')
        linkParams.sidelobeProbability = receiverCfg.sidelobeProbability;
    end
    if isfield(receiverCfg, 'antennaPatternModel')
        linkParams.antennaPatternModel = receiverCfg.antennaPatternModel;
    end

    % 噪声统一在 generate.m 最后添加
    linkParams.injectThermalNoise = false;
    
    if enableWideband
        linkParams.disableAGC = true;
    end

    if isfield(receiverCfg, 'noiseTemp') && ~isempty(receiverCfg.noiseTemp)
        linkParams.noiseTemp = receiverCfg.noiseTemp;
    end

    linkParams.verbose = false;

    % 多普勒控制
    if isfield(receiverCfg, 'enableDoppler')
        linkParams.enableDoppler = receiverCfg.enableDoppler;
    end

    % 调用原子操作
    [rxWaveform, chState] = dataGen.link.propagate(txWaveform, linkParams, timeInstant);
end

