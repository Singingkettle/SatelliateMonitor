function jam = white(signalLen, totalEnergy)
    % WHITE 白噪声持续干扰策略
    %
    %   jam = jamming.strategy.white(signalLen, totalEnergy)
    %
    % 输入:
    %   signalLen    - 信号长度 (采样点)
    %   totalEnergy  - 总干扰能量
    %
    % 输出:
    %   jam - 干扰信号向量
    %
    % 特点:
    %   - 100% 占空比
    %   - 能量均匀分布在整个观察窗口
    %   - 基线方法，能效最低
    
    arguments
        signalLen (1,1) double {mustBePositive}
        totalEnergy (1,1) double {mustBeNonnegative}
    end
    
    avgPower = totalEnergy / signalLen;
    jam = sqrt(avgPower/2) * (randn(signalLen, 1) + 1j * randn(signalLen, 1));
end

