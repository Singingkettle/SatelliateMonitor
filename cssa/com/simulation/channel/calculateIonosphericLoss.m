function loss_dB = calculateIonosphericLoss(constellation, freq_GHz, elevation_deg)
    % CALCULATEIONOSPHERICLOSS 电离层损耗计算
    %
    % 输入:
    %   constellation  - 星座类型
    %   freq_GHz       - 频率 (GHz)
    %   elevation_deg  - 仰角 (度)
    %
    % 输出:
    %   loss_dB        - 电离层损耗 (dB)

    % 电离层损耗（主要影响L波段）
    if freq_GHz > 2
        loss_dB = 0; % Ku波段及以上基本不受影响
    else
        % L波段电离层闪烁
        if elevation_deg < 30
            loss_dB = (30 - elevation_deg) * 0.05 * (2 / freq_GHz) ^ 2;
        else
            loss_dB = 0;
        end

    end

end
