function guardMs = guard(spectrumConfig, modeKey)
    % GUARD 获取指定模式的 burst 保护间隔 (dataGen.burst.guard)
    %
    %   guardMs = dataGen.burst.guard(spectrumConfig, modeKey)
    %
    % 输入:
    %   spectrumConfig - 频谱监测配置
    %   modeKey        - 带宽模式名称
    %
    % 输出:
    %   guardMs - 保护间隔 (ms)

    guardMs = spectrumConfig.broadband.dataset.defaultBurstGuard_ms;

    if ~isfield(spectrumConfig.broadband.dataset, 'burstGuards_ms')
        return;
    end

    guardStruct = spectrumConfig.broadband.dataset.burstGuards_ms;
    lookupKeys = {modeKey};

    if startsWith(modeKey, 'mode_')
        lookupKeys{end + 1} = modeKey(6:end);
    else
        lookupKeys{end + 1} = ['mode_' modeKey];
    end

    lookupKeys{end + 1} = 'default';

    for iKey = 1:numel(lookupKeys)
        key = lookupKeys{iKey};

        if isfield(guardStruct, key) && guardStruct.(key) > 0
            guardMs = guardStruct.(key);
            return;
        end
    end
end

