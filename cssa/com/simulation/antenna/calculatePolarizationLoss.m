function loss_dB = calculatePolarizationLoss(polarization, constellation)
    % CALCULATEPOLARIZATIONLOSS 极化损失计算
    %
    %   loss_dB = calculatePolarizationLoss(polarization, constellation)
    %
    % 功能：
    %   计算发射与接收极化不匹配导致的功率损失
    %
    % 输入:
    %   polarization   - 实际极化方式 ('LHCP'/'RHCP'/'Linear')
    %   constellation  - 星座类型 ('starlink'/'oneweb')
    %
    % 输出:
    %   loss_dB - 极化损失 (dB)
    %             匹配: 0 dB
    %             失配: 3 dB (正交极化)

    % 从配置文件获取该星座的预期极化方式
    phyParams = constellationPhyConfig(constellation);
    expectedPol = phyParams.ut.polarization;

    if strcmpi(polarization, expectedPol)
        loss_dB = 0; % 极化匹配
    else
        loss_dB = 3; % 极化失配损失3dB
    end

end
