function jam = STSD(signalLen, totalEnergy, burstInfo, options)
    % STSD Sync-Triggered Sweep Data-jamming (同步触发扫频数据段干扰)
    %
    %   jam = jamming.strategy.STSD(signalLen, totalEnergy, burstInfo)
    %
    % 创新点:
    %   - 利用同步头检测实现精准时域定位
    %   - 扫频覆盖数据段内多个子载波（带宽由检测任务获取）
    %   - 能量集中在数据承载区域，避免干扰同步头
    %   - 对OFDM系统多子载波造成时变干扰，难以被均衡器消除
    %
    % 输入:
    %   signalLen    - 信号长度 (采样点)
    %   totalEnergy  - 总干扰能量
    %   burstInfo    - burst 信息结构体 (含检测任务获取的带宽)
    %   options      - 可选参数:
    %       .sweepBW         - 扫频带宽 (Hz)，默认从burstInfo获取
    %       .numSweeps       - 每个数据段的扫频次数
    %
    % 输出:
    %   jam - 干扰信号向量
    %
    % 与传统扫频干扰的区别:
    %   传统: 持续扫频，覆盖整个信号（含同步头）
    %   STSD: 同步触发后仅在数据段扫频，能效提升显著
    
    arguments
        signalLen (1,1) double {mustBePositive}
        totalEnergy (1,1) double {mustBeNonnegative}
        burstInfo struct = struct()
        options.sweepBW (1,1) double = 0      % 0表示从burstInfo自动获取
        options.numSweeps (1,1) double {mustBePositive} = 2
    end
    
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
    
    % 获取采样率（从burstInfo或使用默认值）
    if isfield(burstInfo, 'sampleRate') && burstInfo.sampleRate > 0
        sampleRate = burstInfo.sampleRate;
    else
        sampleRate = 100e6;  % 默认100MHz
    end
    
    % 获取扫频带宽（优先使用检测任务提供的带宽信息）
    if options.sweepBW > 0
        sweepBW = options.sweepBW;
    elseif isfield(burstInfo, 'bandwidth') && burstInfo.bandwidth > 0
        % 从检测任务获取的带宽，使用80%作为扫频范围
        sweepBW = burstInfo.bandwidth * 0.8;
    else
        % 默认使用采样率的60%作为扫频带宽
        sweepBW = sampleRate * 0.6;
    end
    
    % 计算干扰范围（仅数据段）
    jamRanges = [];
    totalJamSamples = 0;
    
    for b = 1:burstInfo.numBursts
        burstStart = burstInfo.burstStarts(b);
        
        % 数据段范围：同步头检测后的数据承载区域
        dataStart = burstStart + syncLen;
        if isfield(burstInfo, 'burstEnds')
            dataEnd = min(burstInfo.burstEnds(b), signalLen);
        else
            dataEnd = min(burstStart + burstInfo.burstDuration - 1, signalLen);
        end
        
        if dataStart < signalLen && dataEnd > dataStart
            dataLen = dataEnd - dataStart + 1;
            totalJamSamples = totalJamSamples + dataLen;
            jamRanges = [jamRanges; dataStart, dataEnd]; 
        end
    end
    
    if totalJamSamples == 0
        return;
    end
    
    % 计算干扰振幅
    jamPower = totalEnergy / totalJamSamples;
    amplitude = sqrt(jamPower);
    
    % 生成同步触发扫频干扰
    for i = 1:size(jamRanges, 1)
        dataStart = jamRanges(i, 1);
        dataEnd = jamRanges(i, 2);
        dataLen = dataEnd - dataStart + 1;
        
        % 时间向量
        t = (0:dataLen-1)' / sampleRate;
        
        % 单次扫频持续时间
        sweepDuration = dataLen / options.numSweeps / sampleRate;
        
        % chirp rate: 从 -BW/2 扫到 +BW/2
        chirpRate = sweepBW / sweepDuration;
        
        % 锯齿波形式扫频（多次重复覆盖）
        tmod = mod(t, sweepDuration);
        phase = 2 * pi * (-sweepBW/2 * tmod + 0.5 * chirpRate * tmod.^2);
        
        % 添加随机初始相位（每个burst独立）
        phase = phase + 2 * pi * rand();
        
        jam(dataStart:dataEnd) = amplitude * exp(1j * phase);
    end
end

