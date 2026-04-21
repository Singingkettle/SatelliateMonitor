function [txWaveform, txInfo] = tx(txParams, rfFingerprint, constellation)
    % TX 原子发射操作 (dataGen.link.tx)
    %
    %   [txWaveform, txInfo] = dataGen.link.tx(txParams, rfFingerprint, constellation)
    %
    % 功能：
    %   最底层的发射信号生成，不依赖任何高级结构体
    %   可被数据生成和数字孪生直接调用
    %
    % 输入:
    %   txParams      - 发射参数结构体，必须包含:
    %       .txPower      - 发射功率 (W)
    %       .modulation   - 调制方式
    %       .codeRate     - 编码率
    %       .numInfoBits  - 信息比特数 (可选，默认20000)
    %       .channelIndex - 子信道索引 (可选)
    %       .bandwidthMode - 带宽模式 (可选)
    %   rfFingerprint - RF指纹 (可为空)
    %   constellation - 星座名称
    %
    % 输出:
    %   txWaveform - 发射波形 (复信号)
    %   txInfo     - 发射参数信息
    %
    % 示例 (数字孪生调用):
    %   params.txPower = 0.5;
    %   params.modulation = 'QPSK';
    %   params.codeRate = 0.5;
    %   [wfm, info] = dataGen.link.tx(params, [], 'starlink');

    % 参数验证
    if ~isfield(txParams, 'txPower')
        error('tx:MissingTxPower', '必须指定发射功率 txPower');
    end
    
    if ~isfield(txParams, 'modulation')
        txParams.modulation = 'QPSK';
    end
    
    if ~isfield(txParams, 'codeRate')
        txParams.codeRate = 0.5;
    end
    
    if ~isfield(txParams, 'numInfoBits')
        txParams.numInfoBits = 20000;
    end

    % 调用底层信号生成
    [txWaveform, txInfo] = dataGen.signal.uplink(txParams, rfFingerprint, constellation);
end

