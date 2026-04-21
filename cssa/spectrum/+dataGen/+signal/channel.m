function channelIndex = channel(constellation, bandwidthMode)
    % CHANNEL 依据配置选择信道索引 (dataGen.signal.channel)
    %
    %   channelIndex = dataGen.signal.channel(constellation)
    %   channelIndex = dataGen.signal.channel(constellation, bandwidthMode)
    %
    % 功能：
    %   根据星座配置的信道化参数，随机选择一个可用子信道
    %   用于模拟终端在多信道环境中的频率分配
    %
    % 输入:
    %   constellation - 星座名称 ('starlink' / 'oneweb')
    %   bandwidthMode - 带宽模式 (可选，如 'mode_60MHz' 或 '60MHz')
    %
    % 输出:
    %   channelIndex - 随机选择的信道索引

    phyParams = constellationPhyConfig(constellation);

    % Determine range based on mode if provided
    range = [];

    if nargin >= 2 && ~isempty(bandwidthMode) && isfield(phyParams, 'channelization') && isfield(phyParams.channelization, 'modes')

        % 尝试直接匹配
        if isfield(phyParams.channelization.modes, bandwidthMode)
            modeKey = bandwidthMode;
        else
            % 尝试添加 mode_ 前缀
            modeKey = sprintf('mode_%s', bandwidthMode);
        end

        if isfield(phyParams.channelization.modes, modeKey)
            modeParams = phyParams.channelization.modes.(modeKey);

            if isfield(modeParams, 'numChannels')
                range = [1, modeParams.numChannels];
            end

        end

    end

    % Fallback to legacy or default
    if isempty(range)

        if isfield(phyParams, 'channelIndexRange') && ~isempty(phyParams.channelIndexRange)
            range = phyParams.channelIndexRange;
        else
            % Try to find default mode
            if isfield(phyParams, 'channelization') && isfield(phyParams.channelization, 'modes')
                % Use first mode
                fields = fieldnames(phyParams.channelization.modes);

                if ~isempty(fields)
                    modeParams = phyParams.channelization.modes.(fields{1});

                    if isfield(modeParams, 'numChannels')
                        range = [1, modeParams.numChannels];
                    end

                end

            end

        end

    end

    if isempty(range)
        error('selectChannel:MissingRange', ...
            '%s 未在配置中定义有效的信道范围。', upper(constellation));
    end

    if isnumeric(range) && numel(range) == 2
        minIdx = round(range(1));
        maxIdx = round(range(2));
        channelIndex = randi([minIdx, maxIdx]);
    elseif isnumeric(range) && numel(range) > 2
        channelIndex = range(randi(numel(range)));
    else
        error('selectChannel:InvalidRange', ...
            '%s 的 channelIndexRange 配置无效。', upper(constellation));
    end

end
