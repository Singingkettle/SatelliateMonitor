function [terminalPlans, planInfo] = plan(observationWindow_ms, sampleRate, constellation, bandwidthMode, varargin)
    % PLAN 统一规划终端与 burst（科学规划 + 策略执行）
    %
    %   [terminalPlans, planInfo] = dataGen.burst.plan(...)
    %
    % 规划逻辑：
    %   - 宽带模式：终端数量 = 随机(1, numChannels)，每终端可多burst（基于MCS计算容量）
    %   - 基带模式：固定1个终端，可多burst（用于干扰测试数据，需完整解调）
    %   - 起始位置在合理范围内随机偏移，增加多样性
    %   - 不同终端使用不同信道（FDMA），可时域重叠
    %   - 同一终端内burst不能时域重叠
    %   - 宽带模式支持边缘截断burst（模拟真实场景）：
    %       * 开始截断：burst在观察窗口开始前就已存在，只能看到后半部分
    %       * 结束截断：burst在观察窗口结束时被截断，只能看到前半部分

    p = inputParser;
    addParameter(p, 'GuardTime_ms', 0.1, @isnumeric);
    addParameter(p, 'MaxBurstRatio', 0.6, @isnumeric);
    addParameter(p, 'OutputMode', 'wideband', @(x) any(validatestring(x, {'wideband', 'baseband'})));
    addParameter(p, 'FingerprintDB', [], @(x) isempty(x) || isstruct(x));
    addParameter(p, 'SignalPresent', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'SpectrumConfig', struct(), @isstruct);
    addParameter(p, 'Options', struct(), @isstruct);
    addParameter(p, 'RandomSeed', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'TruncatedBurstProbability', 0.25, @isnumeric);  % 截断burst概率
    parse(p, varargin{:});

    guardTime_ms = p.Results.GuardTime_ms;
    maxBurstRatio = p.Results.MaxBurstRatio;
    outputMode = lower(p.Results.OutputMode);
    fingerprintDB = p.Results.FingerprintDB;
    signalPresent = logical(p.Results.SignalPresent);
    spectrumConfig = p.Results.SpectrumConfig;
    generatorOptions = p.Results.Options;
    truncatedBurstProb = p.Results.TruncatedBurstProbability;

    if ~isempty(p.Results.RandomSeed)
        rng(p.Results.RandomSeed);
    end

    terminalPlans = struct('fingerprintId', {}, 'mcsIndex', {}, 'modulation', {}, ...
        'codeRate', {}, 'bursts', {});

    % 加载信号长度对照表
    signalLengthSummary = loadSignalLengthTable();
    constField = matlab.lang.makeValidName(constellation);
    modeField = matlab.lang.makeValidName(bandwidthMode);

    if isempty(signalLengthSummary) || ~isfield(signalLengthSummary, constField) || ...
            ~isfield(signalLengthSummary.(constField), modeField)
        error('plan:NoLengthTable', '未找到 %s/%s 的信号长度信息。', constellation, bandwidthMode);
    end

    modeInfo = signalLengthSummary.(constField).(modeField);
    channelIndices = resolveChannelIndices(constellation, bandwidthMode);
    basebandSampleRate = modeInfo.sampleRate;
    
    isWidebandMode = strcmpi(outputMode, 'wideband');
    if isWidebandMode
        planSampleRate = sampleRate;
    else
        planSampleRate = basebandSampleRate;
    end

    windowSamples = max(1, round(observationWindow_ms * 1e-3 * planSampleRate));
    guardSamples = max(1, round(guardTime_ms * 1e-3 * planSampleRate));

    % 宽带模式允许截断，基带模式禁止截断
    allowTruncation = isWidebandMode;
    if allowTruncation
        maxBurstSamples = max(1, floor(windowSamples * maxBurstRatio));
    else
        % 基带模式：burst不能超出窗口
        maxBurstRatio = 1.0;
        maxBurstSamples = windowSamples;
    end

    % 预填 planInfo
    planInfo = struct();
    planInfo.signalPresent = signalPresent;
    planInfo.numTerminals = 0;
    planInfo.totalBursts = 0;
    planInfo.windowSamples = windowSamples;
    planInfo.windowDuration_ms = observationWindow_ms;
    planInfo.guardTime_ms = guardTime_ms;
    planInfo.guardSamples = guardSamples;
    planInfo.maxBurstRatio = maxBurstRatio;
    planInfo.maxBurstSamples = maxBurstSamples;
    planInfo.allowTruncation = allowTruncation;
    planInfo.outputMode = outputMode;
    planInfo.basebandSampleRate = basebandSampleRate;
    planInfo.outputSampleRate = planSampleRate;
    planInfo.constellation = constellation;
    planInfo.bandwidthMode = bandwidthMode;

    if ~signalPresent
        return;
    end

    [fingerprintIds, fingerprintMeta] = getFingerprintIds(fingerprintDB, bandwidthMode);
    resampleRatio = planSampleRate / basebandSampleRate;

    % ==================== 确定终端数量 ====================
    % 宽带模式：随机选择 1 到 min(numChannels, numFingerprints) 个终端
    % 基带模式：固定 1 个终端（干扰测试数据）
    if isWidebandMode
        maxTerminals = min(numel(channelIndices), numel(fingerprintIds));
        if maxTerminals == 0
            warning('plan:NoTerminals', '指纹库或信道数量不足。');
            return;
        end
        numTerminals = randi(2);
    else
        numTerminals = 1;  % 基带模式固定1个终端
    end

    if numTerminals == 0
        warning('plan:NoTerminals', '无法规划终端。');
        return;
    end

    % burst 结构扩展：支持截断信息
    emptyBursts = struct('startIdx', {}, 'payloadBits', {}, ...
        'isTruncatedStart', {}, 'isTruncatedEnd', {}, ...
        'truncatedStartSamples', {}, 'truncatedEndSamples', {}, ...
        'fullSignalLength', {});
    terminalPlans = repmat(struct('fingerprintId', '', 'fingerprintCategory', '', ...
        'mcsIndex', [], 'modulation', '', 'codeRate', [], 'channelIndex', [], ...
        'bursts', emptyBursts), 1, numTerminals);
    allMCS = fieldnames(modeInfo.byMCS);
    
    % 随机分配不重复的信道
    shuffledChannels = channelIndices(randperm(numel(channelIndices)));
    assignedChannels = shuffledChannels(1:numTerminals);

    knownProbability = 0.5;
    if isstruct(spectrumConfig) && isfield(spectrumConfig, 'orbit') ...
            && isstruct(spectrumConfig.orbit) && isfield(spectrumConfig.orbit, 'knownTerminalProbability')
        knownProbability = spectrumConfig.orbit.knownTerminalProbability;
    end

    totalSignalSamples = 0;
    totalBursts = 0;

    % ==================== 每个终端独立规划burst ====================
    for tIdx = 1:numTerminals
        [fingerprintMeta, selectedFingerprint] = chooseFingerprint(fingerprintMeta, knownProbability);
        terminalPlans(tIdx).fingerprintId = selectedFingerprint.id;
        terminalPlans(tIdx).fingerprintCategory = selectedFingerprint.category;
        
        % 随机选择MCS
        mcsField = allMCS{randi(numel(allMCS))};
        mcsIdx = sscanf(mcsField, 'mcs%d');
        mcsInfo = modeInfo.byMCS.(mcsField);
        terminalPlans(tIdx).mcsIndex = mcsIdx;
        terminalPlans(tIdx).modulation = mcsInfo.modulation;
        terminalPlans(tIdx).codeRate = mcsInfo.codeRate;
        terminalPlans(tIdx).mcsInfo = mcsInfo; 
        terminalPlans(tIdx).channelIndex = assignedChannels(tIdx);
        
        % ==================== 计算该MCS下最大可放burst数 ====================
        % 基于当前MCS的典型信号长度估算
        typicalPayloadBits = mean(mcsInfo.payloadBitsRange);
        typicalBasebandLength = round(mcsInfo.linearFit.slope * typicalPayloadBits + mcsInfo.linearFit.intercept);
        typicalSignalLength = round(typicalBasebandLength * resampleRatio);
        
        if allowTruncation
            % 宽带模式：信号可截断到maxBurstSamples
            effectiveSignalLength = min(typicalSignalLength, maxBurstSamples);
        else
            % 基带模式：信号不能截断
            effectiveSignalLength = typicalSignalLength;
        end
        
        % 计算窗口内最多能放几个burst
        slotSize = effectiveSignalLength + guardSamples;
        maxBurstsForThisMCS = max(1, floor(windowSamples / slotSize));
        
        % 随机选择 1 到 maxBurstsForThisMCS 个burst
        numBurstsForThisTerminal = randi(maxBurstsForThisMCS);
        
        % ==================== 截断burst规划（仅宽带模式） ====================
        % 每个终端独立决定是否生成边缘截断burst
        % 开始截断：burst在观察窗口开始前就已存在，从位置1开始可见
        % 结束截断：burst延伸超出观察窗口，在窗口末尾被截断
        generateStartTruncBurst = false;
        generateEndTruncBurst = false;
        if isWidebandMode && truncatedBurstProb > 0
            % 每个终端独立概率决定是否生成截断burst
            generateStartTruncBurst = rand() < truncatedBurstProb;
            generateEndTruncBurst = rand() < truncatedBurstProb;
        end
        
        % ==================== 起始位置随机偏移 ====================
        % 如果有开始截断burst，则从位置1开始；否则随机偏移
        if generateStartTruncBurst
            terminalPosition = 1;  % 开始截断burst必须从位置1开始
        else
        % 计算可用的随机偏移范围
        totalRequiredSamples = numBurstsForThisTerminal * slotSize;
        maxStartOffset = max(0, windowSamples - totalRequiredSamples);
        
        % 随机选择起始偏移（增加多样性）
        if maxStartOffset > 0
            startOffset = randi([0, maxStartOffset]);
        else
            startOffset = 0;
        end
            terminalPosition = 1 + startOffset;
        end
        
        % ==================== 开始截断burst ====================
        % 在终端时间线开始处生成一个被开始截断的burst
        % 最小有效信号长度（不使用 guardSamples，因为某些星座信号长度可能小于 guard time）
        minValidSignalLength = max(1000, round(1000 * resampleRatio));
        
        if generateStartTruncBurst
            [startTruncPayload, startTruncBasebandLen] = selectPayload( ...
                windowSamples, mcsInfo, outputMode, sampleRate, basebandSampleRate);
            startTruncFullLength = round(startTruncBasebandLen * resampleRatio);
            
            % 随机截断比例：10%-70%的信号被截掉（可见部分为30%-90%）
            truncRatio = 0.1 + rand() * 0.6;
            truncatedSamples = round(startTruncFullLength * truncRatio);
            visibleLength = startTruncFullLength - truncatedSamples;
            
            % 条件修改：使用 minValidSignalLength 而非 guardSamples
            if visibleLength > minValidSignalLength && visibleLength <= windowSamples * 0.6
                burst = struct();
                burst.startIdx = 1;  % 从窗口开始处可见
                burst.payloadBits = startTruncPayload;
                burst.isTruncatedStart = true;
                burst.isTruncatedEnd = false;
                burst.truncatedStartSamples = truncatedSamples;
                burst.truncatedEndSamples = 0;
                burst.fullSignalLength = startTruncFullLength;
                
                terminalPlans(tIdx).bursts(end + 1) = burst;
                totalSignalSamples = totalSignalSamples + visibleLength;
                totalBursts = totalBursts + 1;
                
                % 更新下一个burst的起始位置
                terminalPosition = 1 + visibleLength + guardSamples;
            end
        end
        
        % ==================== 完整burst规划 ====================
        % 生成完整的（不截断的）burst
        for bIdx = 1:numBurstsForThisTerminal
            availableSamples = windowSamples - terminalPosition + 1;
            if availableSamples <= guardSamples
                break;
            end
            
            % 如果打算生成结束截断burst，需要为它预留空间
            reserveForEndTrunc = 0;
            if generateEndTruncBurst && bIdx == numBurstsForThisTerminal
                reserveForEndTrunc = round(effectiveSignalLength * 0.5);  % 预留半个burst的空间
            end
            
            effectiveAvailable = availableSamples - reserveForEndTrunc;
            if effectiveAvailable <= guardSamples
                break;
            end
            
            [payloadBits, basebandLength] = selectPayload(effectiveAvailable, mcsInfo, outputMode, sampleRate, basebandSampleRate);
            signalLength = round(basebandLength * resampleRatio);
            
            if allowTruncation
                signalLength = min(signalLength, maxBurstSamples);
        end
            signalLength = max(1, signalLength);
            
            % 确保完整burst不超出窗口（为结束截断burst预留空间）
            maxEndPos = windowSamples - reserveForEndTrunc;
            if terminalPosition + signalLength - 1 > maxEndPos
                signalLength = maxEndPos - terminalPosition + 1;
            end
            
            % 检查信号长度是否足够（至少1000个基带样本对应的宽带长度）
            % 注：不使用 guardSamples 作为阈值，因为某些星座的信号长度可能小于 guard time
            minSignalLength = max(1000, round(1000 * resampleRatio));
            if signalLength <= minSignalLength
                break;
            end
            
            % 完整burst：无截断
            burst = struct();
            burst.startIdx = terminalPosition;
            burst.payloadBits = payloadBits;
            burst.isTruncatedStart = false;
            burst.isTruncatedEnd = false;
            burst.truncatedStartSamples = 0;
            burst.truncatedEndSamples = 0;
            burst.fullSignalLength = signalLength;
            
            terminalPlans(tIdx).bursts(end + 1) = burst; 
            
            terminalPosition = terminalPosition + signalLength + guardSamples;
            totalSignalSamples = totalSignalSamples + signalLength;
            totalBursts = totalBursts + 1;
        end
        
        % ==================== 结束截断burst ====================
        % 在终端时间线末尾生成一个被结束截断的burst
        if generateEndTruncBurst
            availableSamples = windowSamples - terminalPosition + 1;
            % 使用 minValidSignalLength 而非 guardSamples
            if availableSamples > minValidSignalLength
                [endTruncPayload, endTruncBasebandLen] = selectPayload( ...
                    windowSamples, mcsInfo, outputMode, sampleRate, basebandSampleRate);
                endTruncFullLength = round(endTruncBasebandLen * resampleRatio);
                
                % 随机截断比例：10%-50%的信号会超出窗口（可见部分为50%-90%）
                truncRatio = 0.1 + rand() * 0.4;
                desiredTruncEndSamples = round(endTruncFullLength * truncRatio);
                
                % 计算实际起始位置，使burst能按期望截断
                desiredStartIdx = windowSamples - endTruncFullLength + desiredTruncEndSamples + 1;
                actualStartIdx = max(terminalPosition, desiredStartIdx);
                
                % 使用 minValidSignalLength 而非 guardSamples
                if actualStartIdx <= windowSamples - minValidSignalLength
                    visibleEndLength = windowSamples - actualStartIdx + 1;
                    actualTruncEndSamples = endTruncFullLength - visibleEndLength;
                    
                    if visibleEndLength > minValidSignalLength && actualTruncEndSamples > 0
                        burst = struct();
                        burst.startIdx = actualStartIdx;
                        burst.payloadBits = endTruncPayload;
                        burst.isTruncatedStart = false;
                        burst.isTruncatedEnd = true;
                        burst.truncatedStartSamples = 0;
                        burst.truncatedEndSamples = actualTruncEndSamples;
                        burst.fullSignalLength = endTruncFullLength;
                        
                        terminalPlans(tIdx).bursts(end + 1) = burst;
                        totalSignalSamples = totalSignalSamples + visibleEndLength;
                        totalBursts = totalBursts + 1;
                    end
                end
            end
        end
    end

    % 过滤掉未成功规划 burst 的终端
    keepMask = arrayfun(@(t) ~isempty(t.bursts), terminalPlans);
    terminalPlans = terminalPlans(keepMask);
    if ~isempty(terminalPlans) && isfield(terminalPlans, 'mcsInfo')
        terminalPlans = rmfield(terminalPlans, 'mcsInfo');
    end

    planInfo.numTerminals = numel(terminalPlans);
    planInfo.totalBursts = totalBursts;
    planInfo.totalSignalSamples = totalSignalSamples;
    if planInfo.numTerminals > 0
        planInfo.fillRatio = totalSignalSamples / (windowSamples * planInfo.numTerminals);
    else
        planInfo.fillRatio = 0;
    end
    
    % 统计截断burst信息
    numStartTruncated = 0;
    numEndTruncated = 0;
    for tIdx = 1:numel(terminalPlans)
        for bIdx = 1:numel(terminalPlans(tIdx).bursts)
            b = terminalPlans(tIdx).bursts(bIdx);
            if isfield(b, 'isTruncatedStart') && b.isTruncatedStart
                numStartTruncated = numStartTruncated + 1;
            end
            if isfield(b, 'isTruncatedEnd') && b.isTruncatedEnd
                numEndTruncated = numEndTruncated + 1;
            end
        end
    end
    planInfo.numStartTruncatedBursts = numStartTruncated;
    planInfo.numEndTruncatedBursts = numEndTruncated;
    planInfo.truncatedBurstProbability = truncatedBurstProb;
end

%% ==================== 辅助函数 ====================
function signalLengthSummary = loadSignalLengthTable()
    persistent cachedSummary
    if isempty(cachedSummary)
        cacheFile = fullfile('data', 'cache', 'signalLengthTable.mat');
        if isfile(cacheFile)
            try
                cached = load(cacheFile, 'summary');
                cachedSummary = cached.summary;
            catch
                cachedSummary = struct();
            end
        else
            try
                [~, cachedSummary] = dataGen.burst.profile('Verbose', false);
            catch
                cachedSummary = struct();
            end
        end
    end
    signalLengthSummary = cachedSummary;
end

function [fingerprintIds, fingerprintMeta] = getFingerprintIds(fingerprintDB, modeKey)
    if isempty(fingerprintDB) || ~isstruct(fingerprintDB)
        error('plan:MissingFingerprintDB', '缺少指纹数据库。');
    end
    if ~isfield(fingerprintDB, modeKey)
        error('plan:NoFingerprintMode', '指纹库中缺少模式 %s。', modeKey);
    end
    modeEntry = fingerprintDB.(modeKey);
    [idList, categoryMap] = collectFingerprintIds(modeEntry);
    if isempty(idList.all)
        error('plan:EmptyFingerprintDB', '模式 %s 的指纹库为空。', modeKey);
    end
    fingerprintIds = idList.all(randperm(numel(idList.all)));
    fingerprintMeta = categoryMap;
end

function [ids, refs] = collectFingerprintIds(modeEntry)
    ids = struct();
    ids.all = {};
    refs = struct();
    refs.allRefs = {};
    refs.knownRefs = {};
    refs.unknownRefs = {};
    categories = {'known', 'unknown'};
    for cIdx = 1:numel(categories)
        catName = categories{cIdx};
        if isfield(modeEntry, catName) && ~isempty(modeEntry.(catName))
            items = modeEntry.(catName);
            for i = 1:numel(items)
                if isfield(items(i), 'id')
                    ids.all{end + 1} = items(i).id; 
                    refEntry = struct('id', items(i).id, 'category', catName);
                    refs.allRefs{end + 1} = refEntry; 
                    if strcmp(catName, 'known')
                        refs.knownRefs{end + 1} = refEntry; 
                    else
                        refs.unknownRefs{end + 1} = refEntry; 
                    end
                end
            end
        end
    end
    ids.all = unique(ids.all, 'stable');
end

function [meta, ref] = chooseFingerprint(meta, knownProb)
    if isempty(meta.knownRefs) && isempty(meta.unknownRefs)
        if isempty(meta.allRefs)
            error('plan:FingerprintExhausted', '指纹库容量不足，无法为更多终端分配指纹。');
        end
        ref = meta.allRefs{1};
        meta.allRefs(1) = [];
        return;
    end

    useKnown = rand() < knownProb;
    if (useKnown && ~isempty(meta.knownRefs)) || isempty(meta.unknownRefs)
        bucket = 'knownRefs';
    else
        bucket = 'unknownRefs';
    end

    ref = meta.(bucket){1};
    meta.(bucket)(1) = [];

    % 同步全量列表，确保不会重复分配
    removeIdx = find(cellfun(@(r) strcmp(r.id, ref.id), meta.allRefs), 1, 'first');
    if ~isempty(removeIdx)
        meta.allRefs(removeIdx) = [];
    end
end

function [payloadBits, basebandLength] = selectPayload(availableSamples, mcsInfo, outputMode, widebandRate, basebandRate)
    fit = mcsInfo.linearFit;
    minBits = mcsInfo.payloadBitsRange(1);
    maxBits = mcsInfo.payloadBitsRange(2);

    if strcmpi(outputMode, 'wideband')
        availableBasebandSamples = availableSamples * basebandRate / widebandRate;
    else
        availableBasebandSamples = availableSamples;
    end
    availableBasebandSamples = max(availableBasebandSamples, mcsInfo.signalLengthRange(1));

    if fit.slope > 0
        targetBits = floor((availableBasebandSamples - fit.intercept) / fit.slope);
    else
        targetBits = mean([minBits, maxBits]);
    end

    payloadBits = max(minBits, min(maxBits, targetBits));
    basebandLength = round(fit.slope * payloadBits + fit.intercept);
    basebandLength = max(basebandLength, mcsInfo.signalLengthRange(1));
end

function channelIndices = resolveChannelIndices(constellation, bandwidthMode)
    channelIndices = [];
    try
        phyParams = constellationPhyConfig(constellation);
    catch
        phyParams = struct();
    end

    if isstruct(phyParams) && isfield(phyParams, 'channelization') && isfield(phyParams.channelization, 'modes')
        modeKey = bandwidthMode;
        if ~isfield(phyParams.channelization.modes, modeKey) && startsWith(modeKey, 'mode_')
            modeKey = modeKey(6:end);
            modeKey = ['mode_' modeKey];
        elseif ~startsWith(modeKey, 'mode_')
            prefixed = ['mode_' modeKey];
            if isfield(phyParams.channelization.modes, prefixed)
                modeKey = prefixed;
            end
        end
        if isfield(phyParams.channelization.modes, modeKey)
            modeParams = phyParams.channelization.modes.(modeKey);
            if isfield(modeParams, 'numChannels') && modeParams.numChannels > 0
                channelIndices = 1:modeParams.numChannels;
            end
        end
    end

    if isempty(channelIndices) && isfield(phyParams, 'channelIndexRange')
        range = phyParams.channelIndexRange;
        if isnumeric(range) && numel(range) == 2
            channelIndices = range(1):range(2);
        elseif isnumeric(range) && ~isempty(range)
            channelIndices = range(:)';
end
    end

    if isempty(channelIndices)
        channelIndices = 1;
    end
end
