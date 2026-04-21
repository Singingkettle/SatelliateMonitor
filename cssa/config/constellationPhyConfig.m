function phyParams = constellationPhyConfig(constellation)
    % CONSTELLATIONPHYCONFIG 星座物理层配置统一入口
    %
    %   phyParams = constellationPhyConfig(constellation)
    %
    % 功能：
    %   根据星座类型返回对应的物理层参数
    %   统一管理收发参数、波形参数、MCS表等
    %
    % 输入:
    %   constellation - 星座类型 ('starlink' / 'oneweb')
    %
    % 输出:
    %   phyParams - 物理层参数结构体，包含：
    %       .waveform       - 波形参数 (OFDM/SC-FDMA)
    %       .channelization - 信道化参数
    %       .mcsTable       - 调制编码方案表
    %       .ut             - 用户终端参数
    %       .sat            - 卫星参数
    %       .defaultTxConfig - 默认发射配置
    %
    % 参见: getStarlinkPhyParams, getOneWebPhyParams

    switch lower(constellation)
        case 'starlink'
            phyParams = getStarlinkPhyParams();
        case 'oneweb'
            phyParams = getOneWebPhyParams();
        otherwise
            error('不支持的星座类型: %s (支持: starlink, oneweb)', constellation);
    end

end
