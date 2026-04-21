function result = mode(action, varargin)
    % MODE 带宽模式工具函数 (dataGen.config.mode)
    %
    %   modes = dataGen.config.mode('list', phyParams)
    %   mode = dataGen.config.mode('pick', sampleIdx, scheduler, fallbackModes)
    %   bw = dataGen.config.mode('bandwidth', phyParams, modeKey)
    %
    % 功能：
    %   - list: 获取支持的带宽模式列表
    %   - pick: 从调度器选择模式
    %   - bandwidth: 获取模式对应的观测带宽

    switch lower(action)
        case 'list'
            result = listModes(varargin{:});
        case 'pick'
            result = pickMode(varargin{:});
        case 'bandwidth'
            result = getBandwidth(varargin{:});
        otherwise
            error('mode:InvalidAction', '无效操作: %s', action);
    end
end

%% ==================== 内部函数 ====================
function modes = listModes(phyParams)
    modes = {};

    if ~isfield(phyParams, 'channelization') || isempty(phyParams.channelization)
        return;
    end

    chan = phyParams.channelization;

    if isfield(chan, 'supportedModes') && ~isempty(chan.supportedModes)
        modes = chan.supportedModes;
        return;
    end

    if isfield(chan, 'modes') && ~isempty(chan.modes)
        modes = fieldnames(chan.modes);
    end
end

function mode = pickMode(sampleIdx, scheduler, fallbackModes)
    mode = '';

    if ~isstruct(scheduler) || ~isfield(scheduler, 'type')
        return;
    end

    schedulerType = lower(string(scheduler.type));

    switch schedulerType
        case "roundrobin"
            if isfield(scheduler, 'modes') && ~isempty(scheduler.modes)
                modeList = scheduler.modes;
            else
                modeList = fallbackModes;
            end

            if isempty(modeList)
                return;
            end

            idx = mod(sampleIdx - 1, numel(modeList)) + 1;
            mode = modeList{idx};
    end
end

function obsBw = getBandwidth(phyParams, modeKey)
    obsBw = [];

    if nargin < 2 || isempty(modeKey)
        return;
    end

    if ~isfield(phyParams, 'channelization') || ...
            ~isfield(phyParams.channelization, 'modes') || ...
            isempty(phyParams.channelization.modes)
        return;
    end

    modesStruct = phyParams.channelization.modes;
    targetKey = modeKey;

    if ~isfield(modesStruct, targetKey)
        if startsWith(modeKey, 'mode_')
            altKey = modeKey(6:end);
        else
            altKey = ['mode_' modeKey];
        end

        if isfield(modesStruct, altKey)
            targetKey = altKey;
        else
            return;
        end
    end

    modeCfg = modesStruct.(targetKey);

    if isfield(modeCfg, 'nominalBandwidth') && ~isempty(modeCfg.nominalBandwidth)
        obsBw = modeCfg.nominalBandwidth;
    elseif isfield(modeCfg, 'bandwidth') && ~isempty(modeCfg.bandwidth)
        obsBw = modeCfg.bandwidth;
    end
end

