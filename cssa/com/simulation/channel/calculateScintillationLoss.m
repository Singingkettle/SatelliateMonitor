function loss_dB = calculateScintillationLoss(~, freq_GHz, elevation_deg)
    % CALCULATESCINTILLATIONLOSS 闪烁损耗计算
    % 基于ITU-R P.618简化模型
    %
    % 输入:
    %   freq_GHz       - 频率 (GHz)
    %   elevation_deg  - 仰角 (度)
    %
    % 输出:
    %   loss_dB        - 闪烁损耗 (dB)

    % 闪烁损耗（P.618启发的温和Ku段近似，晴空通常<1 dB）
    f = max(10, min(20, freq_GHz));
    sigma_ref = 0.5; % dB，参考仰角
    m = 1 / max(0.2, sind(max(5, elevation_deg)));
    loss_dB = 0.3 + 0.2 * randn; % 均值0.3 dB，轻微波动
    loss_dB = loss_dB * (f / 12) ^ 0.2 * m ^ 0.3;
    loss_dB = max(0, min(2.0, loss_dB));

end
