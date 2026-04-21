function T_sys = getSystemNoiseTemperature(constellation)
    % GETSYSTEMNOISETEMPERATURE 获取系统噪声温度（从配置文件）
    %
    % 输入:
    %   constellation  - 星座类型
    %
    % 输出:
    %   T_sys          - 系统噪声温度 (K)

    % 从配置文件获取系统噪声温度
    try
        phyParams = constellationPhyConfig(constellation);
        T_sys = phyParams.sat.systemTemp;
    catch
        % 如果配置文件读取失败，使用默认值
        warning('getSystemNoiseTemperature:ConfigFailed', ...
        '无法从配置文件读取系统噪声温度，使用默认值290K');
        T_sys = 290;
    end

end
