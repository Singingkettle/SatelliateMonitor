function gain_dBi = calculateActualTxGain(constellation, nominalGain, elevation, azimuth)
    % CALCULATEACTUALTXGAIN 计算考虑扫描损失的实际发射增益
    %
    % 输入:
    %   constellation  - 星座类型
    %   nominalGain    - 标称增益 (dBi)
    %   elevation       - 仰角 (度)
    %   azimuth         - 方位角 (度)
    %
    % 输出:
    %   gain_dBi        - 实际增益 (dBi)

    scanAngle = acosd(cosd(elevation) * cosd(azimuth));

    switch lower(constellation)
        case 'starlink'

            if scanAngle <= 1
                gain_dBi = nominalGain;
            else
                gainLoss = (37.2 - 32.2) * min(scanAngle / 60, 1);
                gain_dBi = nominalGain - gainLoss;
            end

        case 'oneweb'

            if scanAngle <= 1
                gain_dBi = nominalGain;
            else
                gainLoss = 3.0 * min(scanAngle / 45, 1);
                gain_dBi = nominalGain - gainLoss;
            end

        otherwise
            gain_dBi = nominalGain;
    end

end
