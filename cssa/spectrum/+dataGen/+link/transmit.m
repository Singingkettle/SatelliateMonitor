function [txWaveform, txInfo, txParams] = transmit(terminalProfile, constellation, bwMode)
    % TRANSMIT 发射端信号生成 (dataGen.link.transmit)
    %
    %   [txWaveform, txInfo, txParams] = dataGen.link.transmit(terminalProfile, constellation, bwMode)
    %
    % 功能：
    %   生成终端上行发射信号，包含调制、编码、RF损伤等
    %   此函数是高级接口，内部调用原子操作 dataGen.link.tx
    %
    % 输入:
    %   terminalProfile - 终端配置 (由 dataGen.terminal.select/create 生成)
    %   constellation   - 星座名称
    %   bwMode          - 带宽模式
    %
    % 输出:
    %   txWaveform - 发射波形 (复信号)
    %   txInfo     - 发射参数信息
    %   txParams   - 发射配置
    %
    % 参见: dataGen.link.tx (原子操作，供数字孪生直接调用)

    % 验证终端配置
    if ~isfield(terminalProfile, 'initialized') || ~terminalProfile.initialized
        error('transmit:InvalidTerminal', '终端配置无效');
    end

    % 获取物理层参数
    phyParams = constellationPhyConfig(constellation);
    
    if ~isfield(phyParams.channelization.modes, bwMode)
        error('transmit:InvalidMode', '无效的带宽模式 %s', bwMode);
    end

    % 从终端配置提取参数
    rfMeta = terminalProfile.rfMeta;
    txTemplate = terminalProfile.txTemplate;

    % 构建发射参数
    txParams = txTemplate;
    
    % 选择载荷比特数（优先使用规划中的值）
    if isfield(txTemplate, 'numInfoBits') && ~isempty(txTemplate.numInfoBits)
        % 使用规划中指定的 payloadBits
        txParams.numInfoBits = txTemplate.numInfoBits;
    else
        % 回退到随机选择
        payloadBits = selectPayloadBits(phyParams, bwMode);
        if ~isempty(payloadBits)
            txParams.numInfoBits = payloadBits;
        end
    end

    % 调用原子操作
    [txWaveform, txInfo] = dataGen.link.tx(txParams, rfMeta, constellation);
    
    % 附加终端信息到 txInfo
    txInfo.terminalId = terminalProfile.tid;
    txInfo.txPowerBackoff_dB = terminalProfile.txPowerBackoff_dB;
end

%% ==================== 辅助函数 ====================

function payloadBits = selectPayloadBits(phyParams, modeKey)
    % SELECTPAYLOADBITS 根据带宽模式选择载荷比特数
    %
    % 输入:
    %   phyParams - 物理层参数
    %   modeKey   - 带宽模式键名 (如 'mode_60MHz')
    %
    % 输出:
    %   payloadBits - 载荷比特数
    %
    % 说明:
    %   按优先级查找: modeKey -> mode_+modeKey -> 去掉mode_前缀 -> default -> 第一个可用
    if ~isfield(phyParams, 'waveform') || ~isfield(phyParams.waveform, 'payloadBitsRange')
        payloadBits = 20000;
        return;
    end

    rangeStruct = phyParams.waveform.payloadBitsRange;
    candidates = {modeKey};

    if ~startsWith(modeKey, 'mode_')
        candidates{end + 1} = ['mode_' modeKey];
    else
        candidates{end + 1} = modeKey(6:end);
    end
    candidates{end + 1} = 'default';

    payloadRange = [];
    for i = 1:numel(candidates)
        key = candidates{i};
        if isfield(rangeStruct, key)
            payloadRange = rangeStruct.(key);
            break;
        end
    end

    if isempty(payloadRange)
        fields = fieldnames(rangeStruct);
        if ~isempty(fields)
            payloadRange = rangeStruct.(fields{1});
        end
    end

    if isempty(payloadRange)
        payloadBits = 20000;
        return;
    end

    if numel(payloadRange) == 2
        payloadBits = randi(payloadRange);
    else
        payloadBits = payloadRange(1);
    end
end

