function [rxWaveform, chState] = propagate(txWaveform, linkParams, timeInstant)
    % PROPAGATE 原子信道传播操作 (dataGen.link.propagate)
    %
    %   [rxWaveform, chState] = dataGen.link.propagate(txWaveform, linkParams, timeInstant)
    %
    % 功能：
    %   最底层的信道传播仿真，不依赖任何高级结构体
    %   可被数据生成和数字孪生直接调用
    %
    % 输入:
    %   txWaveform  - 发射波形
    %   linkParams  - 链路参数结构体，必须包含:
    %       .utPosition       - 终端位置 [lat, lon, alt]
    %       .satPosition      - 卫星位置 (ECEF) [x, y, z]
    %       .satVelocity      - 卫星速度 (ECEF) [vx, vy, vz]
    %       .frequency        - 载波频率 (Hz)
    %       .bandwidth        - 信号带宽 (Hz)
    %       .txPower          - 发射功率 (W)
    %       .sampleRate       - 采样率 (Hz)
    %     可选:
    %       .rxGain           - 接收增益 (dB)
    %       .GT               - G/T值 (dB/K)
    %       .noiseTemp        - 噪声温度 (K)
    %       .weatherCond      - 天气条件
    %       .enableDoppler    - 是否启用多普勒
    %       .enableMultipath  - 是否启用多径
    %       .injectThermalNoise - 是否注入热噪声
    %   timeInstant - 时间戳 (POSIX时间)
    %
    % 输出:
    %   rxWaveform - 接收波形
    %   chState    - 信道状态
    %
    % 示例 (数字孪生调用):
    %   linkParams.utPosition = [40, 116, 100];
    %   linkParams.satPosition = [1e7, 0, 0];
    %   linkParams.satVelocity = [0, 7000, 0];
    %   linkParams.frequency = 14.25e9;
    %   linkParams.bandwidth = 60e6;
    %   linkParams.txPower = 0.5;
    %   linkParams.sampleRate = 60e6;
    %   [rxWfm, chState] = dataGen.link.propagate(txWfm, linkParams, posixtime(datetime));

    % 设置默认值
    if ~isfield(linkParams, 'constellation')
        linkParams.constellation = 'starlink';  % 默认星座
    end
    
    if ~isfield(linkParams, 'rxGain')
        linkParams.rxGain = 30;
    end
    
    if ~isfield(linkParams, 'GT')
        linkParams.GT = 10;
    end
    
    if ~isfield(linkParams, 'noiseTemp')
        linkParams.noiseTemp = 300;
    end
    
    if ~isfield(linkParams, 'weatherCond')
        linkParams.weatherCond = 'clear';
    end
    
    if ~isfield(linkParams, 'enableDoppler')
        linkParams.enableDoppler = true;
    end
    
    if ~isfield(linkParams, 'injectThermalNoise')
        linkParams.injectThermalNoise = false;
    end
    
    if ~isfield(linkParams, 'verbose')
        linkParams.verbose = false;
    end
    
    if ~isfield(linkParams, 'polarization')
        linkParams.polarization = 'RHCP';
    end

    % 计算链路几何（如果未提供）
    if ~isfield(linkParams, 'elevation') || ~isfield(linkParams, 'range')
        [elev, ~, rng] = calculateLinkGeometry(linkParams.utPosition, linkParams.satPosition);
        linkParams.elevation = elev;
        linkParams.range = rng;
    end

    % 调用信道模型
    [rxWaveform, chState] = channelModel(txWaveform, linkParams, timeInstant);
    
    % 记录几何信息
    chState.elevation = linkParams.elevation;
    chState.range = linkParams.range;
end

