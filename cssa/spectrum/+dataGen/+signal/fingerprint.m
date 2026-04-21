function fingerprintDB = fingerprint(numTerminals, terminalType, rfConfig, varargin)
    % FINGERPRINT 生成或加载 RF 指纹数据库 (dataGen.signal.fingerprint)
    %
    % 使用可选 CacheFile 时，优先从缓存加载；否则重新生成并写入缓存。
    %
    % 可选参数:
    %   Constellation: 星座名称 (用于生成结构化ID)
    %   ModeName: 模式名称 (用于生成结构化ID)
    %
    % ID格式: {constellation}_{modeName}_{terminalType}_{index}
    % 例如: starlink_mode_60MHz_known_1

    if nargin < 3
        error('rfConfig required');
    end

    p = inputParser;
    addRequired(p, 'numTerminals', @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addRequired(p, 'terminalType', @(x) ischar(x) || isstring(x));
    addRequired(p, 'rfConfig', @isstruct);
    addParameter(p, 'CacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'ForceRegenerate', false, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'Constellation', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'ModeName', '', @(x) ischar(x) || isstring(x));
    parse(p, numTerminals, terminalType, rfConfig, varargin{:});

    numTerminals = round(p.Results.numTerminals);
    terminalType = char(lower(strtrim(p.Results.terminalType)));
    rfConfig = p.Results.rfConfig;
    cacheFile = char(p.Results.CacheFile);
    forceRegenerate = logical(p.Results.ForceRegenerate);
    constellation = char(strtrim(p.Results.Constellation));
    modeName = char(strtrim(p.Results.ModeName));

    if numTerminals <= 0
        defaultId = generateFingerprintId(constellation, modeName, terminalType, 0);
        fingerprintDB = repmat(struct('phaseNoise', 0, 'frequencyOffset', 0, 'dcOffset', 0, 'type', terminalType, 'id', defaultId), 0, 1);
        return;
    end

    phaseNoiseRange = rfConfig.phaseNoiseRangeRMS;
    freqOffsetRange = rfConfig.freqOffsetRangePPM;
    dcOffsetRange = rfConfig.dcOffsetRangeDBC;

    fingerprintDB = [];

    if ~forceRegenerate && ~isempty(cacheFile) && exist(cacheFile, 'file')

        try
            cacheData = load(cacheFile, 'fingerprintDB', 'metadata');

            if isfield(cacheData, 'fingerprintDB')
                cachedDB = cacheData.fingerprintDB;

                metadata = struct();

                if isfield(cacheData, 'metadata')
                    metadata = cacheData.metadata;
                end

                if validateCache(metadata, terminalType, numTerminals, phaseNoiseRange, freqOffsetRange, dcOffsetRange, constellation, modeName)
                    fingerprintDB = cachedDB;

                    if numel(fingerprintDB) > numTerminals
                        fingerprintDB = fingerprintDB(1:numTerminals);
                    elseif numel(fingerprintDB) < numTerminals
                        fingerprintDB = [];
                    else
                        % 如果提供了constellation和modeName，但缓存中的ID是旧格式（数字），需要更新ID
                        if ~isempty(constellation) && ~isempty(modeName) && numel(fingerprintDB) > 0
                            needsIdUpdate = false;

                            if isnumeric(fingerprintDB(1).id) || (ischar(fingerprintDB(1).id) && ~contains(fingerprintDB(1).id, '_'))
                                needsIdUpdate = true;
                            end

                            if needsIdUpdate

                                for i = 1:numel(fingerprintDB)
                                    fingerprintDB(i).id = generateFingerprintId(constellation, modeName, terminalType, i);
                                end

                                % 更新缓存文件
                                try
                                    metadata.constellation = constellation;
                                    metadata.modeName = modeName;
                                    save(cacheFile, 'fingerprintDB', 'metadata');
                                catch
                                    % 如果保存失败，继续使用更新后的内存版本
                                end

                            end

                        end

                    end

                end

            end

        catch
            fingerprintDB = [];
        end

    end

    if isempty(fingerprintDB)
        fingerprintDB = repmat(struct('phaseNoise', 0, 'frequencyOffset', 0, 'dcOffset', 0, 'type', terminalType, 'id', ''), numTerminals, 1);

        for i = 1:numTerminals
            pn = phaseNoiseRange(1) + (phaseNoiseRange(2) - phaseNoiseRange(1)) * rand();
            fo = freqOffsetRange(1) + (freqOffsetRange(2) - freqOffsetRange(1)) * rand();
            dc = dcOffsetRange(1) + (dcOffsetRange(2) - dcOffsetRange(1)) * rand();

            fingerprintDB(i).phaseNoise = pn;
            fingerprintDB(i).frequencyOffset = fo;
            fingerprintDB(i).dcOffset = dc;
            fingerprintDB(i).type = terminalType;
            fingerprintDB(i).id = generateFingerprintId(constellation, modeName, terminalType, i);
        end

        if ~isempty(cacheFile)
            cacheDir = fileparts(cacheFile);

            if ~isempty(cacheDir) && ~exist(cacheDir, 'dir')
                mkdir(cacheDir);
            end

            metadata = struct( ...
                'terminalType', terminalType, ...
                'numTerminals', numTerminals, ...
                'phaseNoiseRange', phaseNoiseRange, ...
                'freqOffsetRange', freqOffsetRange, ...
                'dcOffsetRange', dcOffsetRange, ...
                'generatedAt', datetime('now'));

            if ~isempty(constellation)
                metadata.constellation = constellation;
            end

            if ~isempty(modeName)
                metadata.modeName = modeName;
            end

            save(cacheFile, 'fingerprintDB', 'metadata');
        end

    end

end

function isValid = validateCache(metadata, terminalType, numTerminals, phaseNoiseRange, freqOffsetRange, dcOffsetRange, constellation, modeName)
    isValid = isfield(metadata, 'terminalType') && strcmpi(metadata.terminalType, terminalType) && ...
        isfield(metadata, 'numTerminals') && metadata.numTerminals == numTerminals && ...
        isfield(metadata, 'phaseNoiseRange') && isequal(metadata.phaseNoiseRange, phaseNoiseRange) && ...
        isfield(metadata, 'freqOffsetRange') && isequal(metadata.freqOffsetRange, freqOffsetRange) && ...
        isfield(metadata, 'dcOffsetRange') && isequal(metadata.dcOffsetRange, dcOffsetRange);

    % 如果提供了constellation和modeName，验证它们是否匹配（如果metadata中存在）
    if ~isempty(constellation) && isfield(metadata, 'constellation')
        isValid = isValid && strcmpi(metadata.constellation, constellation);
    end

    if ~isempty(modeName) && isfield(metadata, 'modeName')
        isValid = isValid && strcmpi(metadata.modeName, modeName);
    end

end

function idStr = generateFingerprintId(constellation, modeName, terminalType, index)
    % GENERATEFINGERPRINTID 生成结构化指纹ID
    %
    % 格式: {constellation}_{modeName}_{terminalType}_{index}
    % 例如: starlink_mode_60MHz_known_1

    if isempty(constellation) || isempty(modeName)
        % 向后兼容：如果没有提供星座和模式信息，使用简单数字ID
        if index > 0
            idStr = sprintf('%d', index);
        else
            idStr = '0';
        end

        return;
    end

    % 清理输入，移除特殊字符
    constellation = regexprep(lower(constellation), '[^a-z0-9]', '');
    modeName = regexprep(lower(modeName), '[^a-z0-9]', '');
    terminalType = regexprep(lower(terminalType), '[^a-z0-9]', '');

    if index > 0
        idStr = sprintf('%s_%s_%s_%d', constellation, modeName, terminalType, index);
    else
        idStr = sprintf('%s_%s_%s_0', constellation, modeName, terminalType);
    end

end
