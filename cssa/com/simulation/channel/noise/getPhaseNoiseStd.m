function std_rad = getPhaseNoiseStd(constellation)
    % GETPHASENOISESTD 获取相位噪声标准差
    %
    %   std_rad = getPhaseNoiseStd(constellation)
    %
    % 功能：
    %   返回星座对应的本振相位噪声RMS值
    %   用于信道模型中的相位噪声注入
    %
    % 输入:
    %   constellation - 星座类型 ('starlink' / 'oneweb')
    %
    % 输出:
    %   std_rad - 相位噪声标准差 (弧度)
    %             Starlink: 0.01 rad (~0.6°)
    %             OneWeb:   0.015 rad (~0.9°)

    switch lower(constellation)
        case 'starlink'
            std_rad = 0.01;
        case 'oneweb'
            std_rad = 0.015;
        otherwise
            std_rad = 0.01;
    end

end
