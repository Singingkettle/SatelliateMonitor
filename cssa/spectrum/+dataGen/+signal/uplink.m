function [txWaveform, txInfo] = uplink(txParams, rfFingerprint, constellation)
    % UPLINK 生成上行链路信号 (dataGen.signal.uplink)
    %
    %   [txWaveform, txInfo] = dataGen.signal.uplink(txParams, rfFingerprint, constellation)
    %
    % 功能：
    %   调用星座物理层发射机生成基带波形，并叠加RF指纹损伤
    %
    % 输入:
    %   txParams      - 发射参数 (.mcsIndex, .channelIndex, .bandwidthMode, .numInfoBits)
    %   rfFingerprint - RF指纹结构体 (可为空)
    %   constellation - 星座名称 ('starlink' / 'oneweb')
    %
    % 输出:
    %   txWaveform - 发射波形 (已含RF损伤)
    %   txInfo     - 发射信息 (采样率、载频、带宽、MCS等)

    if nargin < 3
        constellation = 'starlink';
    end

    phyParams = constellationPhyConfig(constellation);

    % 1. 配置发射参数
    txConfig = phyParams.defaultTxConfig;
    txConfig.mcs = txParams.mcsIndex;
    txConfig.channelIndex = txParams.channelIndex;

    if isfield(txParams, 'bandwidthMode')
        txConfig.bandwidthMode = txParams.bandwidthMode;
    end

    if isfield(txParams, 'numInfoBits')
        payloadBits = txParams.numInfoBits;
    else
        payloadBits = 20000; % Default fallback

        if isfield(phyParams.waveform, 'payloadBitsRange')
            rangeStruct = phyParams.waveform.payloadBitsRange;

            % Determine range based on mode
            range = [];

            if isfield(txParams, 'bandwidthMode')
                modeKey = sprintf('mode_%s', txParams.bandwidthMode);

                if isfield(rangeStruct, modeKey)
                    range = rangeStruct.(modeKey);
                end

            end

            % Fallback to default or first field
            if isempty(range)

                if isfield(rangeStruct, 'default')
                    range = rangeStruct.default;
                else
                    % Take first field
                    fields = fieldnames(rangeStruct);

                    if ~isempty(fields)
                        range = rangeStruct.(fields{1});
                    end

                end

            end

            if isnumeric(range) && numel(range) == 2
                payloadBits = randi(range);
            end

        end

    end

    txConfig.verbose = false;

    % 生成数据位
    txBits = randi([0, 1], payloadBits, 1);

    % 2. 生成波形
    switch lower(constellation)
        case 'starlink'
            [txWaveform, info, debug] = starlink.upTx(txBits, txConfig);
        case 'oneweb'
            [txWaveform, info, debug] = oneweb.upTx(txBits, txConfig);
        otherwise
            error('Unsupported constellation: %s', constellation);
    end

    % 3. 应用 RF 损伤
    if ~isempty(rfFingerprint)
        % Call package function
        txWaveform = dataGen.signal.impairments(txWaveform, rfFingerprint, info.carrierFrequency, info.sampleRate);
    end

    % 4. 构造输出信息
    txInfo = struct();
    txInfo.sampleRate = info.sampleRate;
    txInfo.carrierFrequency = info.carrierFrequency;
    txInfo.bandwidth = info.bandwidth;
    txInfo.modulation = txParams.modulation;
    txInfo.codeRate = txParams.codeRate;
    txInfo.mcsIndex = txParams.mcsIndex;
    txInfo.channelIndex = txParams.channelIndex;
    txInfo.payloadBits = payloadBits;
    txInfo.payloadLength = length(txBits);
    txInfo.txBits = txBits;

    % Add metadata for channelization
    txInfo.channelSpacing = info.channelSpacing;
    txInfo.numChannels = info.numChannels;
    txInfo.referenceChannelIndex = info.referenceChannelIndex;
    txInfo.frameMeta = debug;

end
