function [table, summary] = profile(varargin)
    % PROFILE 生成信号长度对照表
    %
    %   [table, summary] = dataGen.burst.profile()
    %   [table, summary] = dataGen.burst.profile('Constellation', 'starlink')
    %   [table, summary] = dataGen.burst.profile('SamplePoints', [2000, 5000, 10000])
    %
    % 功能:
    %   遍历所有星座、带宽模式、MCS组合，测试不同 payload bits 生成的信号长度。
    %   用于科学规划 burst 位置，避免重叠。
    %
    % 输出:
    %   table   - 结构体数组，每条记录包含:
    %             constellation, bandwidthMode, mcsIndex, modulation, codeRate,
    %             payloadBits, signalLength, sampleRate, duration_ms
    %   summary - 汇总信息，按星座/模式分组的范围统计

    p = inputParser;
    addParameter(p, 'Constellation', 'all', @(x) any(validatestring(x, {'all', 'starlink', 'oneweb'})));
    addParameter(p, 'SamplePoints', [], @isnumeric);
    addParameter(p, 'Verbose', true, @islogical);
    addParameter(p, 'CacheFile', '', @ischar);
    parse(p, varargin{:});
    
    verbose = p.Results.Verbose;
    cacheFile = p.Results.CacheFile;
    
    % 检查缓存
    if ~isempty(cacheFile) && isfile(cacheFile)
        try
            cached = load(cacheFile, 'table', 'summary', 'generatedAt');
            if isfield(cached, 'generatedAt') && (datetime('now') - cached.generatedAt) < days(7)
                table = cached.table;
                summary = cached.summary;
                if verbose
                    fprintf('[burst.profile] 使用缓存 (%s)\n', cacheFile);
                end
                return;
            end
        catch
        end
    end
    
    % 确定要测试的星座
    if strcmpi(p.Results.Constellation, 'all')
        constellations = {'starlink', 'oneweb'};
    else
        constellations = {lower(p.Results.Constellation)};
    end
    
    table = struct('constellation', {}, 'bandwidthMode', {}, 'mcsIndex', {}, ...
        'modulation', {}, 'codeRate', {}, 'payloadBits', {}, 'signalLength', {}, ...
        'sampleRate', {}, 'duration_ms', {});
    
    summary = struct();
    
    for cIdx = 1:numel(constellations)
        constellation = constellations{cIdx};
        phyParams = constellationPhyConfig(constellation);
        mcsTable = phyParams.mcsTable;
        modes = fieldnames(phyParams.channelization.modes);
        
        if verbose
            fprintf('\n=== %s 信号长度 ===\n', upper(constellation));
        end
        
        for mIdx = 1:numel(modes)
            modeName = modes{mIdx};
            modeParams = phyParams.channelization.modes.(modeName);
            sampleRate = modeParams.sampleRate;
            
            % 获取 payload bits 范围
            if isfield(phyParams.waveform, 'payloadBitsRange') && ...
               isfield(phyParams.waveform.payloadBitsRange, modeName)
                bitsRange = phyParams.waveform.payloadBitsRange.(modeName);
            else
                bitsRange = [2000, 20000];
            end
            
            % 确定采样点
            if ~isempty(p.Results.SamplePoints)
                samplePoints = p.Results.SamplePoints;
            else
                minBits = bitsRange(1);
                maxBits = bitsRange(2);
                step = ceil((maxBits - minBits) / 10);
                samplePoints = unique([minBits, minBits:step:maxBits, maxBits]);
            end
            
            if verbose
                fprintf('  %s: [%d, %d] bits\n', modeName, bitsRange(1), bitsRange(2));
            end
            
            % 遍历 MCS
            for mcsIdx = 1:size(mcsTable, 1)
                modOrder = mcsTable(mcsIdx, 2);
                codeRate = mcsTable(mcsIdx, 3);
                modulation = orderToMod(modOrder);
                
                for payloadBits = samplePoints
                    if payloadBits < bitsRange(1) || payloadBits > bitsRange(2)
                        continue;
                    end
                    
                    try
                        signalLength = measureLength(constellation, modeName, mcsIdx, payloadBits);
                        duration_ms = signalLength / sampleRate * 1000;
                        
                        entry = struct();
                        entry.constellation = constellation;
                        entry.bandwidthMode = modeName;
                        entry.mcsIndex = mcsIdx;
                        entry.modulation = modulation;
                        entry.codeRate = codeRate;
                        entry.payloadBits = payloadBits;
                        entry.signalLength = signalLength;
                        entry.sampleRate = sampleRate;
                        entry.duration_ms = duration_ms;
                        
                        table(end+1) = entry; 
                    catch
                    end
                end
            end
        end
    end
    
    % 构建汇总
    summary = buildSummary(table);
    
    % 保存缓存
    if ~isempty(cacheFile)
        try
            generatedAt = datetime('now');
            save(cacheFile, 'table', 'summary', 'generatedAt', '-v7.3');
            if verbose
                fprintf('[burst.profile] 缓存已保存\n');
            end
        catch
        end
    end
    
    if verbose
        printSummary(summary);
    end
end

function signalLength = measureLength(constellation, bandwidthMode, mcsIdx, payloadBits)
    phyParams = constellationPhyConfig(constellation);
    
    txConfig = phyParams.defaultTxConfig;
    txConfig.mcs = mcsIdx;
    txConfig.bandwidthMode = bandwidthMode;
    txConfig.channelIndex = 1;
    txConfig.verbose = false;
    
    dataBits = randi([0 1], payloadBits, 1);
    
    switch lower(constellation)
        case 'starlink'
            [txSignal, ~] = starlink.upTx(dataBits, txConfig);
        case 'oneweb'
            [txSignal, ~] = oneweb.upTx(dataBits, txConfig);
        otherwise
            error('不支持: %s', constellation);
    end
    
    signalLength = length(txSignal);
end

function modulation = orderToMod(modOrder)
    switch modOrder
        case 2, modulation = 'BPSK';
        case 4, modulation = 'QPSK';
        case 16, modulation = '16QAM';
        case 64, modulation = '64QAM';
        case 256, modulation = '256QAM';
        otherwise, modulation = sprintf('%d-QAM', modOrder);
    end
end

function summary = buildSummary(table)
    summary = struct();
    if isempty(table), return; end
    
    constellations = unique({table.constellation});
    
    for cIdx = 1:numel(constellations)
        constellation = constellations{cIdx};
        constField = matlab.lang.makeValidName(constellation);
        summary.(constField) = struct();
        
        constEntries = table(strcmp({table.constellation}, constellation));
        modes = unique({constEntries.bandwidthMode});
        
        for mIdx = 1:numel(modes)
            modeName = modes{mIdx};
            modeField = matlab.lang.makeValidName(modeName);
            
            modeEntries = constEntries(strcmp({constEntries.bandwidthMode}, modeName));
            
            modeInfo = struct();
            modeInfo.sampleRate = modeEntries(1).sampleRate;
            modeInfo.payloadBitsRange = [min([modeEntries.payloadBits]), max([modeEntries.payloadBits])];
            modeInfo.signalLengthRange = [min([modeEntries.signalLength]), max([modeEntries.signalLength])];
            modeInfo.durationRange_ms = [min([modeEntries.duration_ms]), max([modeEntries.duration_ms])];
            modeInfo.numEntries = numel(modeEntries);
            
            % 按 MCS 分组
            mcsIndices = unique([modeEntries.mcsIndex]);
            modeInfo.byMCS = struct();
            
            for mcsIdx = mcsIndices
                mcsEntries = modeEntries([modeEntries.mcsIndex] == mcsIdx);
                mcsField = sprintf('mcs%d', mcsIdx);
                
                mcsInfo = struct();
                mcsInfo.modulation = mcsEntries(1).modulation;
                mcsInfo.codeRate = mcsEntries(1).codeRate;
                mcsInfo.payloadBitsRange = [min([mcsEntries.payloadBits]), max([mcsEntries.payloadBits])];
                mcsInfo.signalLengthRange = [min([mcsEntries.signalLength]), max([mcsEntries.signalLength])];
                mcsInfo.durationRange_ms = [min([mcsEntries.duration_ms]), max([mcsEntries.duration_ms])];
                
                if numel(mcsEntries) >= 2
                    X = [mcsEntries.payloadBits]';
                    Y = [mcsEntries.signalLength]';
                    coeffs = polyfit(X, Y, 1);
                    mcsInfo.linearFit = struct('slope', coeffs(1), 'intercept', coeffs(2));
                else
                    mcsInfo.linearFit = struct('slope', 1, 'intercept', 0);
                end
                
                modeInfo.byMCS.(mcsField) = mcsInfo;
            end
            
            summary.(constField).(modeField) = modeInfo;
        end
    end
end

function printSummary(summary)
    fprintf('\n========== 信号长度汇总 ==========\n');
    
    constellations = fieldnames(summary);
    for cIdx = 1:numel(constellations)
        constField = constellations{cIdx};
        fprintf('\n【%s】\n', upper(constField));
        
        modes = fieldnames(summary.(constField));
        for mIdx = 1:numel(modes)
            modeField = modes{mIdx};
            info = summary.(constField).(modeField);
            
            fprintf('  %s (Fs=%.2f MHz):\n', modeField, info.sampleRate/1e6);
            fprintf('    时长: [%.3f, %.3f] ms\n', info.durationRange_ms(1), info.durationRange_ms(2));
            
            mcsFields = fieldnames(info.byMCS);
            for i = 1:numel(mcsFields)
                mcsField = mcsFields{i};
                mcsInfo = info.byMCS.(mcsField);
                fprintf('      %s (%s): %.3f~%.3f ms\n', mcsField, mcsInfo.modulation, ...
                    mcsInfo.durationRange_ms(1), mcsInfo.durationRange_ms(2));
            end
        end
    end
    fprintf('\n');
end

