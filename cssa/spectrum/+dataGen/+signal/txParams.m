function txParams = txParams(constellation, modeParams)
    % TXPARAMS 获取默认发射参数 (dataGen.signal.txParams)
    %
    %   txParams = dataGen.signal.txParams(constellation)
    %   txParams = dataGen.signal.txParams(constellation, modeParams)
    %
    % 功能：
    %   从星座物理层配置构建发射参数结构体
    %   用于初始化终端发射配置
    %
    % 输入:
    %   constellation - 星座名称 ('starlink' / 'oneweb')
    %   modeParams    - 带宽模式参数 (可选，含 sampleRate, bandwidth)
    %
    % 输出:
    %   txParams - 发射参数结构体，包含:
    %       .constellation, .carrierFrequency, .modulation, .codeRate
    %       .mcsIndex, .channelIndex, .txPower, .sampleRate, .bandwidth 等

    % 加载物理层配置
    phyParams = constellationPhyConfig(constellation);

    % 默认发射机配置
    if isfield(phyParams, 'defaultTxConfig') && ~isempty(phyParams.defaultTxConfig)
        defaultTx = phyParams.defaultTxConfig;
    else
        defaultTx = struct();
    end

    % 载波、带宽、调制等基础信息
    txParams = struct();
    txParams.constellation = constellation;
    txParams.carrierFrequency = phyParams.frequency;
    txParams.modulation = 'QPSK';
    txParams.codeRate = 2/3;
    txParams.mcsIndex = getNumericField(defaultTx, 'mcs', 3);
    txParams.channelIndex = getNumericField(defaultTx, 'channelIndex', 1);
    txParams.beamAngle = getArrayField(defaultTx, 'beamAngle', [0, 45]);

    % 发射功率（dBm -> W）
    % 安全获取默认功率，避免字段不存在的情况
    if isfield(phyParams, 'ut') && isfield(phyParams.ut, 'maxTxPower_dBm')
        fallbackPowerDbm = phyParams.ut.maxTxPower_dBm;
    else
        fallbackPowerDbm = 30;  % 默认 30 dBm = 1 W
    end
    defaultTxPowerDbm = getNumericField(defaultTx, 'txPower', fallbackPowerDbm);
    txParams.txPower = 10 ^ ((defaultTxPowerDbm - 30) / 10);

    % CFR / DPD 开关
    txParams.enableCFR = getLogicalField(defaultTx, 'enableCFR', false);
    txParams.enableDPD = getLogicalField(defaultTx, 'enableDPD', false);

    % 如果提供了 modeParams，优先使用其中的参数
    if nargin >= 2 && ~isempty(modeParams)
        txParams.sampleRate = modeParams.sampleRate;

        if isfield(modeParams, 'bandwidth')
            txParams.bandwidth = modeParams.bandwidth;
        end

        if isfield(modeParams, 'nominalBandwidth')
            txParams.bandwidth = modeParams.nominalBandwidth;
        end

        % 覆盖 nfft 和 cpLength
        if isfield(modeParams, 'cpLength')
            txParams.cpLength = modeParams.cpLength;
        end

        % 尝试推断 bandwidthMode 字符串 (用于 selectChannel 等)
        % 这里不一定是必须的，但为了保持一致性
        % 实际上调用者应该显式设置 txParams.bandwidthMode 如果需要
    end

    % Starlink 特有处理
    if strcmp(constellation, 'starlink')
        txParams.nfft = phyParams.waveform.nfft;
        txParams.nSubcarriers = phyParams.waveform.nSubcarriers;

        if ~isfield(txParams, 'cpLength')
            txParams.cpLength = phyParams.waveform.cpLength;
        end

    else % OneWeb
        txParams.nfft = phyParams.waveform.nfft;

        if isfield(phyParams.waveform, 'nRB')
            txParams.nRB = phyParams.waveform.nRB;
        end

        txParams.nSubcarriers = phyParams.waveform.nSubcarriers;

        if isfield(phyParams.waveform, 'subcarrierSpacing')
            txParams.subcarrierSpacing = phyParams.waveform.subcarrierSpacing;
        end

        if ~isfield(txParams, 'sampleRate')
            txParams.sampleRate = phyParams.waveform.sampleRate;
        end

    end

end

function value = getNumericField(s, name, fallback)
    % 安全获取数值字段
    if isfield(s, name) && ~isempty(s.(name))
        value = double(s.(name));
    else
        value = fallback;
    end

end

function value = getArrayField(s, name, fallback)
    % 安全获取数组字段
    if isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = fallback;
    end

end

function value = getLogicalField(s, name, fallback)
    % 安全获取逻辑字段
    if isfield(s, name) && ~isempty(s.(name))
        value = logical(s.(name));
    else
        value = fallback;
    end

end
