function profile = create(constellation, commSatPos, modeKey, terminalPlan, rfDB, config, options)
    % CREATE 根据规划创建终端 (dataGen.terminal.create)
    %
    %   profile = dataGen.terminal.create(constellation, commSatPos, modeKey, terminalPlan, rfDB, config, options)
    %
    % 功能:
    %   根据 burst.plan 的规划结果创建终端，使用规划中的：
    %   - 指纹ID (fingerprintId)
    %   - MCS索引 (mcsIndex)
    %   - 调制方式 (modulation)
    %   - 码率 (codeRate)
    %
    % 输入:
    %   constellation  - 星座名称
    %   commSatPos     - 通信卫星ECEF位置 [x,y,z]
    %   modeKey        - 带宽模式
    %   terminalPlan   - 来自 burst.plan 的终端规划结构体
    %   rfDB           - RF指纹数据库
    %   config         - spectrumConfig
    %   options        - 生成选项
    %
    % 输出:
    %   profile - 终端配置结构体

    profile = struct('initialized', false);

    phyParams = constellationPhyConfig(constellation);
    
    if ~isfield(phyParams.channelization.modes, modeKey)
        warning('dataGen:terminal:InvalidMode', '无效模式 %s', modeKey);
        return;
    end
    
    modeParams = phyParams.channelization.modes.(modeKey);

    % 1. 选择 UT 位置（仍然随机选择，但验证链路可用性）
    numCandidates = config.orbit.numUTCandidates;
    utCandidates = dataGen.terminal.position(constellation, numCandidates);
    minElev = dataGen.terminal.elevation(constellation);

    [elevations, ~] = computeCandidateGeometry(utCandidates, commSatPos);
    validIdx = find(elevations >= minElev);

    if isempty(validIdx)
        return; % 无可用链路
    end

    % 选择仰角最小的有效候选（极端工况，确保模型鲁棒性）
    validIdx = validIdx(:);
    validElevations = elevations(validIdx);
    [~, minIdx] = min(validElevations);
    utPos = utCandidates(validIdx(minIdx), :);

    % 2. 使用规划中的指纹ID获取RF指纹
    [rfMeta, tid] = getFingerprintById(rfDB, modeKey, terminalPlan.fingerprintId);

    % 3. 使用规划中的 MCS（不再随机选择）
    mcsIdx = terminalPlan.mcsIndex;
    modulation = terminalPlan.modulation;
    codeRate = terminalPlan.codeRate;

    % 4. 构建发射模板
    txTemplate = dataGen.signal.txParams(constellation, modeParams);
    txPowerBackoff_dB = 0;

    enableWideband = isfield(options, 'enableWidebandSampling') && options.enableWidebandSampling;
    
    if enableWideband && isfield(config, 'broadband') && isfield(config.broadband, 'dataset') && ...
            isfield(config.broadband.dataset, 'txPowerBackoff_dB')
        txBackoffRange = config.broadband.dataset.txPowerBackoff_dB;
        if ~isempty(txBackoffRange) && numel(txBackoffRange) == 2 && txBackoffRange(2) > 0
            txPowerBackoff_dB = txBackoffRange(1) + rand() * (txBackoffRange(2) - txBackoffRange(1));
            txTemplate.txPower = txTemplate.txPower / (10 ^ (txPowerBackoff_dB / 10));
        end
    end
    
    txTemplate.modulation = modulation;
    txTemplate.codeRate = codeRate;
    txTemplate.mcsIndex = mcsIdx;
    if isfield(terminalPlan, 'channelIndex') && ~isempty(terminalPlan.channelIndex)
        txTemplate.channelIndex = terminalPlan.channelIndex;
    else
        txTemplate.channelIndex = dataGen.signal.channel(constellation, modeKey);
    end
    txTemplate.bandwidthMode = modeKey;

    % 5. 组装终端配置
    profile.initialized = true;
    profile.utPos = utPos;
    profile.modeKey = modeKey;
    profile.mcsIndex = mcsIdx;
    profile.modulation = modulation;
    profile.codeRate = codeRate;
    profile.txTemplate = txTemplate;
    profile.rfMeta = rfMeta;
    profile.tid = tid;
    profile.txPowerBackoff_dB = txPowerBackoff_dB;
    profile.channelIndex = txTemplate.channelIndex;
end

%% ==================== 辅助函数 ====================
function [elevations, azimuths] = computeCandidateGeometry(utPositions, satPosEcef)
    numCandidates = size(utPositions, 1);
    elevations = zeros(numCandidates, 1);
    azimuths = zeros(numCandidates, 1);

    for i = 1:numCandidates
        [elev, az, ~] = calculateLinkGeometry(utPositions(i, :), satPosEcef);
        elevations(i) = elev;
        azimuths(i) = az;
    end
end

function [rfMeta, terminalId] = getFingerprintById(rfDB, modeKey, fingerprintId)
    % 根据指纹ID获取RF指纹（严格执行，未找到即报错）
    if isempty(rfDB) || ~isstruct(rfDB)
        error('terminal:create:MissingFingerprintDB', '缺少指纹数据库。');
    end

    if ~isfield(rfDB, modeKey)
        error('terminal:create:MissingMode', '指纹库中缺少模式 %s。', modeKey);
    end

    modeEntry = rfDB.(modeKey);
    sources = {'known', 'unknown'};

    for sIdx = 1:numel(sources)
        srcName = sources{sIdx};
        if isfield(modeEntry, srcName) && ~isempty(modeEntry.(srcName))
            db = modeEntry.(srcName);
            for i = 1:numel(db)
                if isfield(db(i), 'id') && strcmp(db(i).id, fingerprintId)
                    rfMeta = db(i);
                    terminalId = fingerprintId;
                    return;
                end
            end
        end
    end

    error('terminal:create:FingerprintNotFound', ...
        '指纹库中未找到 ID=%s (mode=%s) 的记录。', fingerprintId, modeKey);
end
