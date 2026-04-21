function loss_dB = calculateRainAttenuation(constellation, freq_GHz, elevation_deg, ~, weatherCond)
    % CALCULATERAINATTENUATION 降雨衰减计算
    % 基于ITU-R P.838简化模型
    %
    % 输入:
    %   constellation  - 星座类型
    %   freq_GHz       - 频率 (GHz)
    %   elevation_deg  - 仰角 (度)
    %   weatherCond    - 天气条件
    %
    % 输出:
    %   loss_dB        - 降雨衰减 (dB)

    % 降雨衰减（简化ITU-R P.838/P.618风格）：对Ku段保守但防爆高
    % 映射雨强 R_001 近似：
    switch lower(weatherCond)
        case {'heavy_rain'}
            R = 25; % mm/h，接近ITU-R P.837全球0.01%分位
        case {'rain'}
            R = 12; % mm/h，代表典型中雨
        case {'light_rain'}
            R = 3; % mm/h
        otherwise
            R = 0;
    end

    if R <= 0
        loss_dB = 0;
        return;
    end

    % 近似k, alpha（水平极化Ku段经验值范围内）
    f = max(10, min(20, freq_GHz));
    k = 0.017 * f ^ 0.84; % 经验拟合
    alpha = 1.0 - 0.003 * (f - 10);

    gamma_r = k * R ^ alpha; % dB/km 比特定衰减

    % 有效路径长度（使用等效雨层高度 ~4 km）
    h_r = 3.0; % km，全球平均等效雨层高度
    L_eff = h_r / max(0.15, sind(max(1, elevation_deg)));

    % 路径缩减系数（简化抑制过高衰减）
    r = 1 / (1 + 0.3 * L_eff);

    loss_dB = min(20.0, gamma_r * L_eff * r);

end
