function loss_dB = calculateAtmosphericLoss(constellation, freq_GHz, elevation_deg, ~)
    % CALCULATEATMOSPHERICLOSS 大气气体吸收计算
    % 基于ITU-R P.676近似模型
    %
    % 输入:
    %   constellation  - 星座类型
    %   freq_GHz       - 频率 (GHz)
    %   elevation_deg  - 仰角 (度)
    %
    % 输出:
    %   loss_dB        - 大气衰减 (dB)

    % 大气气体吸收（近似ITU-R P.676）：Ku段晴空通常< 1 dB
    % 使用简洁经验式：随频率与仰角变化
    f = max(10, min(20, freq_GHz));
    a0 = 0.04; % 10 GHz 近地仰角参考 (dB)
    a1 = 0.03; % 频率斜率 (dB/GHz)
    A_zenith = a0 + a1 * (f - 10); % 天顶方向气体吸收
    m_elev = 1 / max(0.15, sind(max(1, elevation_deg))); % 简化气象气团系数
    loss_dB = min(3.0, A_zenith * m_elev); % 限幅防止过大

end
