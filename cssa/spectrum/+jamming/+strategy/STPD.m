function jam = STPD(signalLen, totalEnergy, burstInfo, options)
    % STPD Sync-Triggered Pulsed Data-jamming (同步触发脉冲式数据段干扰)
    %
    %   jam = jamming.strategy.STPD(signalLen, totalEnergy, burstInfo)
    %
    % 创新点:
    %   - 利用同步头检测实现精准时域定位
    %   - 在数据段内施加周期性高功率脉冲
    %   - 能量高度集中，峰值功率显著高于STAD
    %   - 占空比可调，适应不同干扰硬件功率限制
    %
    % 输入:
    %   signalLen    - 信号长度 (采样点)
    %   totalEnergy  - 总干扰能量
    %   burstInfo    - burst 信息结构体
    %   options      - 可选参数:
    %       .dutyCycle     - 占空比 (0-1)，默认0.20
    %       .period        - 脉冲周期 (采样点)，默认100
    %
    % 输出:
    %   jam - 干扰信号向量
    %
    % 与传统脉冲干扰的区别:
    %   传统: 周期性脉冲覆盖整个信号
    %   STPD: 同步触发后脉冲仅在数据段内，能效更高
    %
    % 功率关系:
    %   设总能量为E，数据段长度为N，占空比为d
    %   脉冲功率 = E / (N * d)
    %   当d=0.2时，脉冲功率是STAD的5倍
    
    arguments
        signalLen (1,1) double {mustBePositive}
        totalEnergy (1,1) double {mustBeNonnegative}
        burstInfo struct = struct()
        options.dutyCycle (1,1) double = 0.20
        options.period (1,1) double {mustBePositive} = 100
    end
    
    % 验证占空比范围
    dutyCycle = max(0.01, min(1.0, options.dutyCycle));
    
    jam = zeros(signalLen, 1);
    
    if ~isfield(burstInfo, 'burstStarts') || isempty(burstInfo.burstStarts)
        return;
    end
    
    % 获取同步序列长度
    if isfield(burstInfo, 'syncSymbols') && burstInfo.syncSymbols > 0
        syncLen = burstInfo.syncSymbols;
    else
        syncLen = round(burstInfo.burstDuration * 0.1);
    end
    
    period = round(options.period);
    pulseWidth = max(1, round(period * dutyCycle));
    
    % 第一遍：计算所有burst数据段内的脉冲总采样数
    totalPulseSamples = 0;
    pulsePositions = {};
    
    for b = 1:burstInfo.numBursts
        burstStart = burstInfo.burstStarts(b);
        
        % 数据段范围
        dataStart = burstStart + syncLen;
        if isfield(burstInfo, 'burstEnds')
            dataEnd = min(burstInfo.burstEnds(b), signalLen);
        else
            dataEnd = min(burstStart + burstInfo.burstDuration - 1, signalLen);
        end
        
        dataLen = dataEnd - dataStart + 1;
        if dataLen <= 0
            pulsePositions{b} = []; 
            continue;
        end
        
        % 计算脉冲数量和位置
        numPulses = max(1, floor(dataLen / period));
        maxOffset = max(1, dataLen - numPulses * period);
        phaseOffset = randi(maxOffset) - 1;
        
        positions = zeros(numPulses, 2);
        for p = 0:numPulses-1
            pStart = dataStart + phaseOffset + p * period;
            pEnd = min(pStart + pulseWidth - 1, dataEnd);
            
            if pStart <= dataEnd && pEnd >= pStart
                positions(p+1, :) = [pStart, pEnd];
                totalPulseSamples = totalPulseSamples + (pEnd - pStart + 1);
            end
        end
        pulsePositions{b} = positions(positions(:,1) > 0, :); 
    end
    
    if totalPulseSamples == 0
        return;
    end
    
    % 能量集中到脉冲（功率提升 = 1/占空比）
    pulsePower = totalEnergy / totalPulseSamples;
    
    % 第二遍：生成脉冲干扰
    for b = 1:burstInfo.numBursts
        positions = pulsePositions{b};
        for i = 1:size(positions, 1)
            pStart = positions(i, 1);
            pEnd = positions(i, 2);
            pLen = pEnd - pStart + 1;
            jam(pStart:pEnd) = sqrt(pulsePower/2) * (randn(pLen, 1) + 1j * randn(pLen, 1));
        end
    end
end

