function [rxSignal, channelState] = channelModel(txSignal, linkParams, timeInstant)
    % CHANNELMODEL 通用卫星上行链路动态信道模型
    % 通过 deterministic 链路预算 + MATLAB 官方 p681LMSChannel 组合得到可控的慢衰落与噪声
    %
    % 输入参数:
    %   txSignal    - 发射信号（任意复向量，功率无需预缩放）
    %   linkParams  - 链路参数结构，常用字段：
    %                .constellation        星座 ('starlink'/'oneweb')
    %                .utPosition           用户终端位置 [lat, lon, alt] (deg,deg,m)
    %                .satPosition          卫星位置 [x,y,z] (ECEF,m)
    %                .satVelocity          卫星速度 [vx,vy,vz] (ECEF,m/s)
    %                .frequency            载波频率 (Hz)
    %                .bandwidth            信号带宽 (Hz) —— 未提供时默认等于 sampleRate
    %                .sampleRate           采样率 (Hz) —— p681 插值、噪声带宽均基于此
    %                .txPower              发射功率 (W)
    %                .txGain/.rxGain       天线增益 (dBi)
    %                .polarization         极化 ('LHCP'/'RHCP'/'Linear')
    %                .weatherCond          天气 ('clear'/'rain'/'heavy_rain')
    %                .verbose              是否打印日志 (默认 true)
    %                --- 数字孪生/信道控制参数（可选，优先使用）---
    %                .elevation/.azimuth   动态仰角/方位角 (deg)
    %                .range                动态距离 (m)
    %                .dopplerShift         预计算的几何多普勒 (Hz)；若缺省则内部推导
    %                .mobileSpeed          地面平台速度 (m/s)
    %                .environment          p681 环境 (小写 'suburban'/'rural' 等)
    %                .lmsProfile           自定义配置标签（例如 'high-elevation'）
    %                .lmsNumStates         2 或 3 状态 p681 模型
    %                .randomSeed           固定 p681 噪声的随机种子
    %                .injectThermalNoise   是否在本函数中注入 AWGN（默认 true）
    %   timeInstant - 当前时刻 (秒)，用于标注 channelState
    %
    % 输出参数:
    %   rxSignal     - 归一化后的接收信号（平均功率 ≈ 1，便于后续处理）
    %   channelState - 信道状态信息：
    %                  * 顶层 SNR/Noise 字段反映“当前波形”的测量值
    %                  * channelState.physical 保留链路预算/噪声注入前的真实功率
    %                  * channelState.lms/pathGains/sampleTimes/stateSeries 记录 p681 统计元数据
    %
    % 参考文献:
    %   [1] ITU-R P.681-11, "Propagation data required for the design of Earth-space land mobile telecommunication systems".
    %       - 支持: LMS信道模型(Shadowing, Multipath, Doppler)
    %   [2] ITU-R P.676-12, "Attenuation by atmospheric gases".
    %       - 支持: 大气气体衰减计算
    %   [3] ITU-R P.618-13, "Propagation data and prediction methods required for the design of Earth-space telecommunication systems".
    %       - 支持: 降雨衰减, 闪烁损耗, 噪声温度计算
    %   [4] 3GPP TR 38.901, "Study on channel model for frequencies from 0.5 to 100 GHz".
    %       - 支持: 宽带信道建模通用原则
    %
    % 噪声/AGC 说明:
    %   - 噪声功率始终由本函数依据采样率与系统噪声温度计算；injectThermalNoise=false 时仅跳过叠加。
    %   - 输出 rxSignal 会在噪声注入后做一次全局 AGC，使平均功率约为 1，但 channelState.physical
    %     会记录 AGC 之前的真实功率与 SNR，方便链路预算与标注使用。

    %% ==================== 参数初始化 ====================
    c = 299792458; % 光速 (m/s)
    k_B = 1.38064852e-23; % 玻尔兹曼常数 (J/K)
    persistent p681Chan

    % 日志控制
    if isfield(linkParams, 'verbose') && ~isempty(linkParams.verbose)
        verbose = logical(linkParams.verbose);
    else
        verbose = true; % 默认打印日志（保持兼容性）
    end

    if isfield(linkParams, 'injectThermalNoise') && ~isempty(linkParams.injectThermalNoise)
        injectThermalNoise = logical(linkParams.injectThermalNoise);
    else
        injectThermalNoise = true;
    end

    % 额外仿真控制参数
    if isfield(linkParams, 'enablePhaseNoise')
        enablePhaseNoise = logical(linkParams.enablePhaseNoise);
    else
        enablePhaseNoise = true;
    end

    if isfield(linkParams, 'enableMultipath')
        enableMultipath = logical(linkParams.enableMultipath);
    else
        enableMultipath = true;
    end

    if isfield(linkParams, 'enableDoppler')
        enableDoppler = logical(linkParams.enableDoppler);
    else
        enableDoppler = true;
    end

    % 验证必需参数
    if ~isfield(linkParams, 'constellation')
        error('必须指定星座类型 (constellation)');
    end

    % 从统一配置文件获取默认参数
    if ~isfield(linkParams, 'frequency') || ~isfield(linkParams, 'bandwidth') || ...
            ~isfield(linkParams, 'txGain') || ~isfield(linkParams, 'rxGain') || ...
            ~isfield(linkParams, 'polarization')

        phyParams = constellationPhyConfig(linkParams.constellation);

        % 填充缺失参数
        if ~isfield(linkParams, 'frequency')
            linkParams.frequency = phyParams.frequency;
        end

        if ~isfield(linkParams, 'bandwidth')
            linkParams.bandwidth = phyParams.bandwidth;
        end

        if ~isfield(linkParams, 'txGain')
            linkParams.txGain = phyParams.ut.gainBoresight;
        end

        if ~isfield(linkParams, 'rxGain')
            linkParams.rxGain = phyParams.sat.defaultGain;
        end

        if ~isfield(linkParams, 'polarization')
            linkParams.polarization = phyParams.ut.polarization;
        end

    end

    if ~isfield(linkParams, 'weatherCond')
        linkParams.weatherCond = 'clear';
    end

    %% ==================== 1. 几何计算（优先使用数字孪生动态参数） ====================
    if verbose
        fprintf('计算%s链路几何参数...\n', upper(linkParams.constellation));
    end

    % 优先使用数字孪生传入的动态参数
    if isfield(linkParams, 'elevation') && ~isempty(linkParams.elevation)
        % 数字孪生模式：直接使用传入的动态参数
        elevationAngle = linkParams.elevation;

        if verbose
            fprintf('  [数字孪生] 使用动态仰角: %.1f°\n', elevationAngle);
        end

    else
        % 传统模式：本地计算
        utPosition_ECEF = lla2ecef(linkParams.utPosition)';  % 官方API返回行向量，转为列向量
        satPosCol = linkParams.satPosition(:);  % 确保是列向量
        rangeVector = satPosCol - utPosition_ECEF;
        [elevationAngle, ~] = calculateAngles(linkParams.utPosition, linkParams.satPosition);
    end

    if isfield(linkParams, 'azimuth') && ~isempty(linkParams.azimuth)
        azimuthAngle = linkParams.azimuth;

        if verbose
            fprintf('  [数字孪生] 使用动态方位角: %.1f°\n', azimuthAngle);
        end

    else

        if ~exist('rangeVector', 'var')
            utPosition_ECEF = lla2ecef(linkParams.utPosition)';  % 官方API返回行向量，转为列向量
            satPosCol = linkParams.satPosition(:);  % 确保是列向量
            rangeVector = satPosCol - utPosition_ECEF;
        end

        [~, azimuthAngle] = calculateAngles(linkParams.utPosition, linkParams.satPosition);
    end

    if isfield(linkParams, 'range') && ~isempty(linkParams.range)
        slantRange = linkParams.range;

        if verbose
            fprintf('  [数字孪生] 使用动态距离: %.2f km\n', slantRange / 1000);
        end

    else

        if ~exist('rangeVector', 'var')
            utPosition_ECEF = lla2ecef(linkParams.utPosition)';  % 官方API返回行向量，转为列向量
            satPosCol = linkParams.satPosition(:);  % 确保是列向量
            rangeVector = satPosCol - utPosition_ECEF;
        end

        slantRange = norm(rangeVector);
    end

    % 当禁用多普勒时，直接置零，不计算
    if ~enableDoppler
        dopplerShift = 0;
        radialVelocity = 0;
        
        if verbose
            fprintf('  [多普勒已禁用] dopplerShift = 0 Hz\n');
        end
    elseif isfield(linkParams, 'dopplerShift') && ~isempty(linkParams.dopplerShift)
        % 如果直接提供了多普勒频移，使用它
        dopplerShift = linkParams.dopplerShift;

        if verbose
            fprintf('  [数字孪生] 使用动态多普勒: %.2f kHz\n', dopplerShift / 1000);
        end

        % 从多普勒反推径向速度
        radialVelocity = -dopplerShift * c / linkParams.frequency;
    else
        % 本地计算径向速度和多普勒
        if ~exist('utPosition_ECEF', 'var')
            utPosition_ECEF = lla2ecef(linkParams.utPosition)';  % 官方API返回行向量，转为列向量
        end
        if ~exist('rangeVector', 'var')
            satPosCol = linkParams.satPosition(:);  % 确保是列向量
            rangeVector = satPosCol - utPosition_ECEF;
        end
        if ~exist('slantRange', 'var')
            slantRange = norm(rangeVector);
        end
        
        losDirection = rangeVector(:) / slantRange;  % 确保是列向量
        satVelCol = linkParams.satVelocity(:);       % 确保是列向量
        radialVelocity = dot(satVelCol, losDirection);
        dopplerShift = -radialVelocity * linkParams.frequency / c;

        if verbose
            fprintf('  [传统模式] 计算径向速度: %.2f m/s\n', radialVelocity);
        end

    end

    % 显示几何参数（如果不是数字孪生模式）
    if verbose && ~isfield(linkParams, 'elevation')
        fprintf('  距离: %.2f km, 仰角: %.1f°, 方位角: %.1f°\n', ...
            slantRange / 1000, elevationAngle, azimuthAngle);
        fprintf('  多普勒频移: %.2f kHz\n', dopplerShift / 1000);
    end

    %% ==================== 2. 路径损耗计算 ====================
    if verbose
        fprintf('计算路径损耗...\n');
    end

    % 2.1 自由空间路径损耗 (FSPL)
    % [Source: ITU-R P.525]
    lambda = c / linkParams.frequency;
    fspl_dB = 20 * log10(4 * pi * slantRange / lambda);

    % 2.2 大气衰减（基于星座特定模型）
    % [Source: ITU-R P.676]
    gasAtten_dB = calculateAtmosphericLoss(linkParams.constellation, ...
        linkParams.frequency / 1e9, elevationAngle, slantRange / 1000);

    % 2.3 降雨衰减
    % [Source: ITU-R P.618 / P.838]
    rainAtten_dB = calculateRainAttenuation(linkParams.constellation, ...
        linkParams.frequency / 1e9, elevationAngle, slantRange / 1000, ...
        linkParams.weatherCond);

    % 2.4 电离层效应（主要影响L波段，Ku/Ka较小但仍计算）
    % [Source: ITU-R P.531]
    ionosphericLoss_dB = calculateIonosphericLoss(linkParams.constellation, ...
        linkParams.frequency / 1e9, elevationAngle);

    % 2.5 闪烁损耗
    % [Source: ITU-R P.618]
    scintillationLoss_dB = calculateScintillationLoss(linkParams.constellation, ...
        linkParams.frequency / 1e9, elevationAngle);

    % 总路径损耗
    totalPathLoss_dB = fspl_dB + gasAtten_dB + rainAtten_dB + ...
        ionosphericLoss_dB + scintillationLoss_dB;

    if verbose
        fprintf('  自由空间损耗: %.2f dB\n', fspl_dB);
        fprintf('  大气衰减: %.2f dB\n', gasAtten_dB);
        fprintf('  降雨衰减: %.2f dB\n', rainAtten_dB);
        fprintf('  电离层损耗: %.2f dB\n', ionosphericLoss_dB);
        fprintf('  总路径损耗: %.2f dB\n', totalPathLoss_dB);
    end

    %% ==================== 3. 天线增益计算 ====================
    if verbose
        fprintf('计算天线增益...\n');
    end

    % 3.1 发射天线增益（考虑扫描损失）
    % Phased array scan loss ~ cos(theta)^k
    txGainActual = calculateActualTxGain(linkParams.constellation, ...
        linkParams.txGain, elevationAngle, azimuthAngle);

    % 初始化旁瓣接收相关变量（用于后续记录到channelState）
    offBoresightDeg_record = 0;
    offBoresightLoss_dB_record = 0;
    sidelobeSimulated = false;
    sidelobeRegion = 'none';
    
    % 3.1.1 伴飞离轴损耗（关键：UT 实际指向通信卫星，监测卫星位于主瓣外）
    % 在 dataGen.link.channel 中，satPosition=监测卫星(monSatPos)，commSatPosition=通信卫星(commSatPos)
    % 若不施加该损耗，会高估监测卫星接收到的功率，尤其当 separation/altitude 导致 ~1° 级角分离时。
    enableOffBoresightLoss = true;
    if isfield(linkParams, 'enableOffBoresightLoss') && ~isempty(linkParams.enableOffBoresightLoss)
        enableOffBoresightLoss = logical(linkParams.enableOffBoresightLoss);
    end

    if enableOffBoresightLoss && isfield(linkParams, 'commSatPosition') && ~isempty(linkParams.commSatPosition)
        % 仅当监测卫星与通信卫星不重合时才应用
        monMinusComm = linkParams.satPosition(:) - linkParams.commSatPosition(:);
        if norm(monMinusComm) > 1e-3
            utEcef = lla2ecef(linkParams.utPosition)'; % 列向量
            vMon = linkParams.satPosition(:) - utEcef;
            vComm = linkParams.commSatPosition(:) - utEcef;
            if norm(vMon) > 0 && norm(vComm) > 0
                cosang = dot(vMon, vComm) / (norm(vMon) * norm(vComm));
                cosang = max(-1, min(1, cosang));
                offBoresightDeg = acosd(cosang);

                method = 'auto';
                if isfield(linkParams, 'offBoresightLossMethod') && ~isempty(linkParams.offBoresightLossMethod)
                    method = lower(string(linkParams.offBoresightLossMethod));
                end

                offBoresightLoss_dB = 0.0;
                if method == "manual"
                    if isfield(linkParams, 'manualOffBoresightLoss') && ~isempty(linkParams.manualOffBoresightLoss)
                        offBoresightLoss_dB = double(linkParams.manualOffBoresightLoss);
                    else
                        offBoresightLoss_dB = 0.0;
                    end
                elseif method == "full_pattern"
                    % full_pattern: 完整天线方向图模型（含旁瓣）
                    [offBoresightLoss_dB, ~] = calculateUtAntennaPatternLoss( ...
                        offBoresightDeg, linkParams.constellation, linkParams);
                else
                    % auto: 使用改进的天线方向图模型
                    phyParamsTx = constellationPhyConfig(linkParams.constellation);
                    hpbw = 3.0; % deg, 兜底
                    if isfield(phyParamsTx, 'ut') && isfield(phyParamsTx.ut, 'beamwidth3dB') && ~isempty(phyParamsTx.ut.beamwidth3dB)
                        hpbw = double(phyParamsTx.ut.beamwidth3dB);
                    end
                    
                    % 判断是否启用旁瓣接收模型
                    enableSidelobe = false;
                    if isfield(linkParams, 'enableSidelobeReception')
                        enableSidelobe = linkParams.enableSidelobeReception;
                    end
                    
                    % 获取旁瓣接收概率（用于数据增强）
                    sidelobeProbability = 0.15;  % 默认值
                    if isfield(linkParams, 'sidelobeProbability')
                        sidelobeProbability = linkParams.sidelobeProbability;
                    end
                    
                    % 以 sidelobeProbability 概率模拟旁瓣接收场景
                    % 当真实离轴角在主瓣内时，随机增大离轴角使其进入旁瓣区域
                    simulatedSidelobe = false;
                    firstNullAngle = 1.22 * hpbw;  % 第一零点角度
                    
                    if enableSidelobe && hpbw > 0 && offBoresightDeg < firstNullAngle
                        if rand() < sidelobeProbability
                            % 模拟旁瓣接收：将离轴角增大到近旁瓣区域
                            % 随机选择 [firstNullAngle, 15°] 范围内的角度
                            minSidelobeAngle = firstNullAngle * 1.1;  % 略大于第一零点
                            maxSidelobeAngle = min(20.0, firstNullAngle * 4);  % 近旁瓣区域
                            offBoresightDeg = minSidelobeAngle + rand() * (maxSidelobeAngle - minSidelobeAngle);
                            simulatedSidelobe = true;
                            if verbose
                                fprintf('  [数据增强] 模拟旁瓣接收，虚拟离轴角: %.2f°\n', offBoresightDeg);
                            end
                        end
                    end
                    
                    if enableSidelobe && hpbw > 0
                        % 使用完整方向图模型
                        [offBoresightLoss_dB, region] = calculateUtAntennaPatternLoss( ...
                            offBoresightDeg, linkParams.constellation, linkParams);
                        if verbose && (~strcmp(region, 'mainlobe') || simulatedSidelobe)
                            fprintf('  [旁瓣接收] 区域: %s, 离轴角: %.2f°, 模拟=%d\n', region, offBoresightDeg, simulatedSidelobe);
                        end
                    elseif hpbw > 0
                        % 简单主瓣模型
                        offBoresightLoss_dB = 12 * (offBoresightDeg / hpbw) .^ 2;
                        offBoresightLoss_dB = min(offBoresightLoss_dB, 40);
                    end
                end

                txGainActual = txGainActual - offBoresightLoss_dB;
                
                % 记录旁瓣信息（用于标签）
                offBoresightDeg_record = offBoresightDeg;
                offBoresightLoss_dB_record = offBoresightLoss_dB;
                sidelobeSimulated = simulatedSidelobe;
                if exist('region', 'var')
                    sidelobeRegion = region;
                end

                if verbose
                    fprintf('  伴飞离轴角: %.2f° → 发射端离轴损耗: %.2f dB\n', offBoresightDeg, offBoresightLoss_dB);
                end
            end
        end
    end

    % 3.2 接收天线增益
    rxGainActual = linkParams.rxGain; % 假设卫星天线指向优化

    % 3.3 极化损失
    polarizationLoss_dB = calculatePolarizationLoss(linkParams.polarization, ...
        linkParams.constellation);

    if verbose
        fprintf('  发射增益: %.2f dBi\n', txGainActual);
        fprintf('  接收增益: %.2f dBi\n', rxGainActual);
        fprintf('  极化损失: %.2f dB\n', polarizationLoss_dB);
    end

    multipathComponents = [];

    %% ==================== 4. 信号缩放至物理接收功率 ====================
    if verbose
        fprintf('缩放基带信号以匹配链路预算...\n');
    end

    txPower_dBm = 10 * log10(linkParams.txPower * 1000);
    rxPower_dBm = txPower_dBm + txGainActual - totalPathLoss_dB + rxGainActual - polarizationLoss_dB;
    rxPower_W = 10 ^ ((rxPower_dBm - 30) / 10);

    inputSignalPower_W = mean(abs(txSignal) .^ 2);
    scalingFactor = sqrt(rxPower_W / max(inputSignalPower_W, eps));
    rxSignal_no_noise = txSignal * scalingFactor;

    if isfield(linkParams, 'sampleRate') && ~isempty(linkParams.sampleRate)
        Fs = linkParams.sampleRate;
    else
        Fs = linkParams.bandwidth;
    end

    %% ==================== 5. p681 LMS 信道建模 ====================
    pathGains = [];
    sampleTimes = [];
    stateSeries = [];
    lmsEnvironment = '';
    lmsProfileUsed = '';
    mobileSpeed = 0;

    if isfield(linkParams, 'mobileSpeed') && ~isempty(linkParams.mobileSpeed)
        mobileSpeed = linkParams.mobileSpeed;
    end

    applyP681 = enableMultipath;

    if applyP681 && exist('p681LMSChannel', 'class') ~= 8
        warning('satmon:channel:p681Unavailable', ...
        '当前 MATLAB 环境不可用 p681LMSChannel，将退回自由空间模型。');
        applyP681 = false;
    end

    if applyP681 && (elevationAngle < 0 || elevationAngle > 90)
        warning('satmon:channel:p681Elevation', ...
            '仰角 %.1f° 超出 p681LMSChannel 支持范围，退回自由空间模型。', elevationAngle);
        applyP681 = false;
    end

    if applyP681

        if isfield(linkParams, 'environment') && ~isempty(linkParams.environment)
            lmsEnvironment = linkParams.environment;
        else

            switch lower(linkParams.constellation)
                case 'oneweb'
                    lmsEnvironment = 'Rural';
                otherwise
                    lmsEnvironment = 'Suburban';
            end

            if isfield(linkParams, 'weatherCond') && ismember(lower(linkParams.weatherCond), {'rain', 'heavy_rain'})
                lmsEnvironment = 'Suburban';
            end

        end

        switch lower(char(lmsEnvironment))
            case 'urban'
                lmsEnvironment = 'Urban';
            case 'suburban'
                lmsEnvironment = 'Suburban';
            case 'highway'
                lmsEnvironment = 'Highway';
            case 'train'
                lmsEnvironment = 'Train';
            case 'rural'
                lmsEnvironment = 'Rural';
            case 'village'
                lmsEnvironment = 'Village';
            case 'residential'
                lmsEnvironment = 'Residential';
            otherwise
                lmsEnvironment = 'Suburban';
        end

        freqGHz = linkParams.frequency / 1e9;
        highFreqEnvs = {'Urban', 'Suburban', 'Highway', 'Train', 'Rural'};

        if freqGHz >= 10 && freqGHz <= 40

            if ~any(strcmpi(lmsEnvironment, highFreqEnvs))
                lmsEnvironment = 'Suburban';
            end

        end

        % ======== 配置 p681LMSChannel（符合OFDM系统特性）========
        % 
        % 【物理背景 - ITU-R P.681-11】
        % p681LMSChannel 建模的是 Land Mobile Satellite (LMS) 信道，主要描述：
        %   1. 阴影衰落 (Shadowing)：由地面遮挡物（建筑、树木）引起
        %      - 时间尺度：~100ms-1s（远大于OFDM符号时间 ~20μs）
        %   2. 多径衰落 (Multipath)：由地面散射引起
        %      - 对上行链路影响很小（到达卫星时空间积分平均掉了）
        %
        % 【OFDM系统约束】
        % 对于 OFDM 系统，信道必须在一个符号内保持准恒定（块衰落假设）。
        % 逐采样点应用快速变化的 pathGains 会：
        %   - 破坏子载波正交性 → 产生 ICI（Inter-Carrier Interference）
        %   - 导致信道估计失效 → 均衡器无法正确工作
        %
        % 【本实现策略】
        % 我们使用 p681 生成 **统计正确** 的衰落值，但在 **burst 级别** 应用，
        % 以符合真实 LEO 卫星上行链路的阴影衰落时间特性。
        
        if isempty(p681Chan)
            p681Chan = p681LMSChannel;
        end

        if isLocked(p681Chan)
            release(p681Chan);
        end

        % 基本参数配置
        p681Chan.CarrierFrequency = linkParams.frequency;
        p681Chan.ElevationAngle = elevationAngle;
        p681Chan.Environment = lmsEnvironment;
        p681Chan.AzimuthOrientation = azimuthAngle;
        
        % 多普勒相关参数
        % 【重要】SatelliteDopplerShift 在 p681 中只影响衰落的时变特性，
        % 不是实际的频率偏移。我们在后面单独应用几何多普勒频移。
        % 对于阴影衰落的统计特性，我们将 p681 的多普勒设为 0，
        % 这样可以使用较低的衰落采样率（1 kHz）来生成符合 OFDM 系统特性的慢变衰落。
        p681Chan.SatelliteDopplerShift = 0;
        p681Chan.MobileSpeed = mobileSpeed;  % 地面移动速度仍然影响阴影状态转换
        
        % 状态机配置
        if isfield(linkParams, 'lmsNumStates') && ~isempty(linkParams.lmsNumStates)
            p681Chan.NumStates = linkParams.lmsNumStates;
        else
            p681Chan.NumStates = 2;  % 默认双状态模型 (Good/Bad)
        end
        p681Chan.InitialState = 'Good';
        
        % 【关键修改】使用较低的采样率以获得 burst 级别的衰落
        % 典型 burst 持续时间 ~1-10ms，我们以 ~1ms 为衰落采样周期
        % 这样 pathGains 反映的是慢变阴影衰落，而不是快速多径
        fadingSampleRate = 1000;  % 1 kHz，即每 ms 一个衰落样本
        burstDuration = numel(rxSignal_no_noise) / Fs;  % 信号持续时间（秒）
        numFadingSamples = max(1, ceil(burstDuration * fadingSampleRate));
        
        p681Chan.SampleRate = fadingSampleRate;
        p681Chan.ChannelFiltering = false;
        p681Chan.NumSamples = numFadingSamples;
        
        % 随机数流配置
        if isfield(linkParams, 'randomSeed') && ~isempty(linkParams.randomSeed)
            p681Chan.RandomStream = 'mt19937ar with seed';
            p681Chan.Seed = linkParams.randomSeed;
        else
            p681Chan.RandomStream = 'Global stream';
        end

        % 记录使用的配置
        if isfield(linkParams, 'lmsProfile') && ~isempty(linkParams.lmsProfile)
            lmsProfileUsed = lower(string(linkParams.lmsProfile));
        else
            lmsProfileUsed = 'default';
        end

        % 执行 p681LMSChannel，返回路径增益
        [pathGainsSlow, sampleTimes, stateSeries] = p681Chan();

        % 将慢变衰落插值到信号采样率
        % 使用平滑插值以避免阶跃变化
        if isempty(pathGainsSlow)
            pathGains = ones(size(rxSignal_no_noise));
        elseif numel(pathGainsSlow) == 1
            % 单一衰落值，应用到整个 burst
            pathGains = pathGainsSlow * ones(size(rxSignal_no_noise));
        else
            % 使用样条插值进行平滑过渡
            slowTimeAxis = linspace(0, burstDuration, numel(pathGainsSlow));
            fastTimeAxis = (0:numel(rxSignal_no_noise)-1) / Fs;
            
            % 分别插值幅度和相位（避免相位缠绕问题）
            ampSlow = abs(pathGainsSlow);
            phaseSlow = unwrap(angle(pathGainsSlow));
            
            ampFast = interp1(slowTimeAxis, ampSlow, fastTimeAxis, 'pchip', 'extrap');
            phaseFast = interp1(slowTimeAxis, phaseSlow, fastTimeAxis, 'pchip', 'extrap');
            
            pathGains = ampFast(:) .* exp(1j * phaseFast(:));
        end
        
        % 记录原始 p681 输出用于信道状态分析
        pathGainsOriginal = pathGainsSlow;
        
        % 计算平均衰落功率（用于日志和诊断）
        avgFadingPower_dB = 10 * log10(mean(abs(pathGains).^2));
        
        % 应用衰落到信号
        rxSignal_no_noise = rxSignal_no_noise .* pathGains;

        if verbose
            fprintf('  ✓ p681LMSChannel (OFDM适配模式):\n');
            fprintf('      环境: %s, Mobile: %.1f m/s\n', lmsEnvironment, mobileSpeed);
            fprintf('      衰落采样: %d samples @ %d Hz\n', numFadingSamples, fadingSampleRate);
            fprintf('      平均衰落: %.2f dB\n', avgFadingPower_dB);
            if ~isempty(stateSeries)
                goodRatio = sum(stateSeries == 1) / numel(stateSeries) * 100;
                fprintf('      状态分布: %.1f%% Good, %.1f%% Bad\n', goodRatio, 100-goodRatio);
            end
        end

    else

        if verbose

            if enableMultipath
                fprintf('  [提示] 未使用 p681LMSChannel，保持自由空间链路。\n');
            else
                fprintf('  [仿真控制] 多径与阴影衰落已被禁用。\n');
            end

        end

    end

    % 5.4.1 应用几何多普勒频移 (适用于所有模型)
    % 注意: p681LMSChannel 仅模拟多普勒扩展(Fading Rate)，不包含几何产生的载波频移
    % 因此无论是否使用 p681，都需要应用几何多普勒
    if enableDoppler
        t = (0:length(rxSignal_no_noise) - 1)' / Fs;
        dopplerPhasor = exp(1j * 2 * pi * dopplerShift * t);
        rxSignal_no_noise = rxSignal_no_noise .* dopplerPhasor;
    end

    % 5.5 添加与信号功率匹配的热噪声
    % [Source: ITU-R P.618 System Noise Temperature]
    % 允许调用方传入系统噪声温度或G/T以更准确建模
    if isfield(linkParams, 'noiseTemp') && ~isempty(linkParams.noiseTemp)
        T_sys = linkParams.noiseTemp;
    elseif isfield(linkParams, 'GT') && ~isempty(linkParams.GT)
        % 由G/T与假定接收天线增益估算噪声温度（需要rxGain）
        % G/T = G_rx - 10*log10(T_sys)
        if isfield(linkParams, 'rxGain')
            G_linear = 10 ^ (linkParams.rxGain / 10);
            GT_linear = 10 ^ (linkParams.GT / 10);
            T_sys = G_linear / GT_linear;
        else
            T_sys = getSystemNoiseTemperature(linkParams.constellation);
        end

    else
        T_sys = getSystemNoiseTemperature(linkParams.constellation);
    end

    % 噪声带宽应该是采样率（不是信号带宽），因为添加到采样后信号上
    if isfield(linkParams, 'sampleRate') && ~isempty(linkParams.sampleRate)
        noiseSampleRate = linkParams.sampleRate;
    else
        noiseSampleRate = linkParams.bandwidth; % 退回到信号带宽
    end

    noiseBW = noiseSampleRate;
    noisePSD_WHz = k_B * T_sys; % 单边功率谱密度
    noisePowerDiscrete = noisePSD_WHz * noiseBW;

    applyAgc = true;

    if isfield(linkParams, 'disableAGC') && logical(linkParams.disableAGC)
        applyAgc = false;
    end

    if injectThermalNoise
        noiseStdNorm = sqrt(noisePowerDiscrete / 2);
        noise = noiseStdNorm * (randn(size(rxSignal_no_noise)) + 1j * randn(size(rxSignal_no_noise)));
        rxSignal = rxSignal_no_noise + noise;
        noisePowerObservedNorm = mean(abs(noise) .^ 2);
        noisePowerActualNorm = noisePowerObservedNorm;
    else
        rxSignal = rxSignal_no_noise;
        noisePowerObservedNorm = noisePowerDiscrete;
        noisePowerActualNorm = 0;
    end

    rxSignal_no_noise_raw = rxSignal_no_noise;

    rxSignal_no_noise_phys = rxSignal_no_noise_raw;

    % 5.6 相位噪声
    % [Source: Typical Oscillator Specs for Ku-band]
    if enablePhaseNoise
        phaseNoiseStd = getPhaseNoiseStd(linkParams.constellation);
        phaseNoise = phaseNoiseStd * randn(size(rxSignal));
        rxSignal = rxSignal .* exp(1j * phaseNoise);
    else

        if verbose
            fprintf('  [仿真控制] 相位噪声已禁用\n');
        end

    end

    %% ==================== 6. 信道状态信息 ====================
    % 重新计算SNR和C/N0以保证一致性
    noisePowerObserved = noisePowerObservedNorm;
    noisePowerActual = noisePowerActualNorm;

    signalPower = mean(abs(rxSignal_no_noise_phys) .^ 2);
    SNR_dB = 10 * log10(signalPower / noisePowerObserved);

    % C/N0
    cn0_dBHz = 10 * log10(signalPower / noisePSD_WHz);

    % 记录物理功率（AGC之前）
    physMetrics = struct( ...
        'rxPower_dBm', 10 * log10(signalPower * 1000), ...
        'signalPower', signalPower, ...
        'noisePowerObserved', noisePowerObserved, ...
        'noisePowerActual', noisePowerActual, ...
        'noisePowerDiscrete', noisePowerDiscrete, ...
        'noisePSD', noisePSD_WHz, ...
        'SNR_dB', SNR_dB, ...
        'CN0_dBHz', cn0_dBHz);

    agcGain = sqrt(mean(abs(rxSignal) .^ 2));

    if applyAgc && agcGain > 0
        rxSignal_no_noise = rxSignal_no_noise / agcGain;
        rxSignal = rxSignal / agcGain;
    else
        agcGain = 1;
    end

    measSignalPower = mean(abs(rxSignal_no_noise) .^ 2);
    measNoisePowerObserved = max(mean(abs(rxSignal - rxSignal_no_noise) .^ 2), eps);
    measNoisePowerActual = injectThermalNoise * measNoisePowerObserved;
    measNoisePSD = measNoisePowerObserved / noiseBW;
    measSNR_dB = 10 * log10(measSignalPower / measNoisePowerObserved);
    measCN0_dBHz = 10 * log10(measSignalPower / measNoisePSD);

    channelState = struct();
    channelState.constellation = linkParams.constellation;
    channelState.slantRange = slantRange;
    channelState.elevationAngle = elevationAngle;
    channelState.azimuthAngle = azimuthAngle;
    channelState.dopplerShift = dopplerShift;
    channelState.dopplerApplied = enableDoppler;  % 标记多普勒是否实际应用到信号
    channelState.radialVelocity = radialVelocity;
    channelState.pathLoss = totalPathLoss_dB;
    channelState.txGain = txGainActual;
    channelState.rxGain = rxGainActual;
    
    % 旁瓣接收信息
    channelState.offBoresightDeg = offBoresightDeg_record;
    channelState.offBoresightLoss_dB = offBoresightLoss_dB_record;
    channelState.sidelobeSimulated = sidelobeSimulated;
    channelState.sidelobeRegion = sidelobeRegion;
    channelState.rxPower = 10 * log10(measSignalPower * 1000);
    channelState.SNR = measSNR_dB;
    channelState.CN0 = measCN0_dBHz;
    channelState.noisePower = measNoisePowerObserved;
    channelState.noisePSD = measNoisePSD;
    channelState.noisebandwidth = noiseBW;
    channelState.noiseSampleRate = noiseSampleRate;
    channelState.noiseTemperature = T_sys;
    channelState.noisePowerObserved = measNoisePowerObserved;
    channelState.noisePowerActual = measNoisePowerActual;
    channelState.thermalNoiseInjected = injectThermalNoise;
    channelState.noise = struct( ...
        'psd', measNoisePSD, ...
        'bandwidth', noiseBW, ...
        'sampleRate', noiseSampleRate, ...
        'temperature_K', T_sys, ...
        'perSamplePower', measNoisePowerObserved, ...
        'perSamplePowerObserved', measNoisePowerObserved, ...
        'perSamplePowerInjected', measNoisePowerActual, ...
        'includedInWaveform', injectThermalNoise, ...
        'description', 'Thermal noise as seen by the receiver front-end', ...
        'physical', struct( ...
        'psd', physMetrics.noisePSD, ...
        'perSamplePower', physMetrics.noisePowerDiscrete, ...
        'perSamplePowerObserved', physMetrics.noisePowerObserved, ...
        'perSamplePowerInjected', physMetrics.noisePowerActual));
    % 记录 p681 信道状态信息
    if applyP681 && exist('pathGainsOriginal', 'var')
        lmsInfo = struct( ...
            'enabled', true, ...
            'environment', lmsEnvironment, ...
            'profile', lmsProfileUsed, ...
            'pathGainsOriginal', pathGainsOriginal, ...  % 原始慢采样衰落
            'pathGainsInterpolated', pathGains, ...       % 插值到信号采样率的衰落
            'sampleTimes', sampleTimes, ...
            'stateSeries', stateSeries, ...
            'mobileSpeed', mobileSpeed, ...
            'fadingSampleRate', fadingSampleRate, ...
            'avgFadingPower_dB', avgFadingPower_dB);
    else
        lmsInfo = struct( ...
            'enabled', applyP681, ...
            'environment', lmsEnvironment, ...
            'profile', lmsProfileUsed, ...
            'pathGainsOriginal', [], ...
            'pathGainsInterpolated', pathGains, ...
            'sampleTimes', sampleTimes, ...
            'stateSeries', stateSeries, ...
            'mobileSpeed', mobileSpeed, ...
            'fadingSampleRate', 0, ...
            'avgFadingPower_dB', 0);
    end
    channelState.lms = lmsInfo;
    channelState.delaySpread = 0;

    if ~isempty(multipathComponents)
        channelState.delaySpread = max(multipathComponents.delays);
    end

    channelState.phaseNoise = -80 + 20 * log10(linkParams.frequency / 1e9);
    channelState.timeInstant = timeInstant;
    channelState.agcApplied = applyAgc;
    channelState.agcGain = agcGain;
    channelState.physical = physMetrics;

    if verbose
        fprintf('  接收功率: %.2f dBm\n', channelState.rxPower);
        fprintf('  SNR: %.2f dB\n', channelState.SNR);
        fprintf('  C/N0: %.2f dB-Hz\n', channelState.CN0);
    end

end

%% ==================== UT 天线方向图损耗计算 ====================
function [loss_dB, region] = calculateUtAntennaPatternLoss(theta_deg, constellation, linkParams) %#ok<INUSD>
    % CALCULATEUTANTENNAPATTERNLOSS 计算 UT 天线方向图损耗（支持主瓣和旁瓣）
    %
    % 基于 ITU-R S.1528 参考天线方向图模型和相控阵天线理论
    %
    % 输入:
    %   theta_deg    - 离轴角 (度)
    %   constellation - 星座名称
    %   linkParams   - 链路参数（保留用于未来扩展，如自定义天线参数）
    %
    % 输出:
    %   loss_dB - 相对于波束峰值的损耗 (dB, 正值表示损耗)
    %   region  - 区域标识: 'mainlobe', 'near_sidelobe', 'far_sidelobe', 'backlobe'
    
    % 获取星座特定的天线参数
    try
        phyParams = constellationPhyConfig(constellation);
    catch
        phyParams = struct();
    end
    
    % 默认参数
    hpbw = 3.0;  % 3dB 波束宽度 (度)
    peakSidelobe_dB = -18;  % 第一旁瓣电平
    envelopeDecay = 25;  % 旁瓣包络衰减斜率
    farSidelobe_dB = -32;  % 远旁瓣电平
    backlobe_dB = -42;  % 背瓣电平
    firstNullFactor = 1.22;  % 第一零点位置因子
    
    % 从星座配置读取参数
    if isfield(phyParams, 'ut')
        if isfield(phyParams.ut, 'beamwidth3dB')
            hpbw = double(phyParams.ut.beamwidth3dB);
        end
        if isfield(phyParams.ut, 'sidelobe')
            sl = phyParams.ut.sidelobe;
            if isfield(sl, 'peakLevel_dB'), peakSidelobe_dB = sl.peakLevel_dB; end
            if isfield(sl, 'envelopeDecay'), envelopeDecay = sl.envelopeDecay; end
            if isfield(sl, 'farSidelobeLevel_dB'), farSidelobe_dB = sl.farSidelobeLevel_dB; end
            if isfield(sl, 'backlobeLevel_dB'), backlobe_dB = sl.backlobeLevel_dB; end
            if isfield(sl, 'firstNullFactor'), firstNullFactor = sl.firstNullFactor; end
        end
    end
    
    % 关键角度边界
    theta_null1 = firstNullFactor * hpbw;  % 第一零点角度
    theta_near_far = 20.0;  % 近旁瓣/远旁瓣边界
    theta_backlobe = 90.0;  % 背瓣边界
    
    theta = abs(theta_deg);  % 取绝对值处理
    
    if theta <= hpbw / 2
        % ==================== 主瓣峰值区域 ====================
        % 使用高斯近似：G(θ) = G_max - 12*(θ/HPBW)^2
        region = 'mainlobe';
        loss_dB = 12 * (theta / hpbw)^2;
        
    elseif theta <= theta_null1
        % ==================== 主瓣边缘（到第一零点） ====================
        % 继续使用主瓣公式，但限制最大损耗
        region = 'mainlobe';
        loss_dB = 12 * (theta / hpbw)^2;
        loss_dB = min(loss_dB, abs(peakSidelobe_dB) + 3);  % 限制在旁瓣峰值附近
        
    elseif theta <= theta_near_far
        % ==================== 近旁瓣区域 ====================
        % ITU-R S.1528 模型: G = G_max + SLL - decay*log10(θ/θ_s)
        % SLL = peak sidelobe level (负值)
        region = 'near_sidelobe';
        
        % 在第一零点处，损耗应接近第一旁瓣峰值
        % 旁瓣包络随角度衰减
        if theta > theta_null1
            loss_dB = abs(peakSidelobe_dB) + envelopeDecay * log10(theta / theta_null1);
        else
            loss_dB = abs(peakSidelobe_dB);
        end
        
        % 添加旁瓣振荡（可选，增加真实性）
        % 使用正弦函数模拟旁瓣峰谷
        oscillation_period = hpbw * 0.8;  % 旁瓣周期
        oscillation = 3 * sin(2 * pi * (theta - theta_null1) / oscillation_period);
        loss_dB = loss_dB + abs(oscillation);  % 只添加正向（更多损耗）
        
        % 限制范围
        loss_dB = max(loss_dB, abs(peakSidelobe_dB));
        loss_dB = min(loss_dB, abs(farSidelobe_dB));
        
    elseif theta <= theta_backlobe
        % ==================== 远旁瓣区域 ====================
        % 较平坦的旁瓣电平
        region = 'far_sidelobe';
        
        % 在 theta_near_far 处应为 farSidelobe_dB
        % 向背瓣过渡
        transitionFactor = (theta - theta_near_far) / (theta_backlobe - theta_near_far);
        loss_dB = abs(farSidelobe_dB) + transitionFactor * (abs(backlobe_dB) - abs(farSidelobe_dB));
        
    else
        % ==================== 背瓣区域 ====================
        region = 'backlobe';
        loss_dB = abs(backlobe_dB);
        
        % 背瓣可能有轻微变化
        if theta > 120
            loss_dB = loss_dB + 5 * (theta - 120) / 60;  % 向正后方略微增加损耗
        end
    end
    
    % 最终限制
    loss_dB = max(0, loss_dB);  % 不能有增益（损耗为正）
    loss_dB = min(loss_dB, 60);  % 最大损耗 60 dB
end
