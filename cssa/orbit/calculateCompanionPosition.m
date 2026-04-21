function [monitorSatPos, monitorSatVel] = calculateCompanionPosition(commSatPos, commSatVel, separation)
    % CALCULATECOMPANIONPOSITION 计算伴飞卫星位置（简化版）
    %   根据通信卫星位置和速度，计算伴飞卫星在同一轨道平面沿轨道方向偏移后的位置
    %
    % 输入：
    %   commSatPos - 通信卫星位置 [x, y, z] (ECEF, m) - 列向量或行向量
    %   commSatVel - 通信卫星速度 [vx, vy, vz] (ECEF, m/s) - 列向量或行向量
    %   separation - 伴飞距离 (m, 默认5000)
    %
    % 输出：
    %   monitorSatPos - 伴飞卫星位置 [x, y, z] (ECEF, m) - 列向量
    %   monitorSatVel - 伴飞卫星速度 [vx, vy, vz] (ECEF, m/s) - 列向量
    %
    % 说明：
    %   伴飞卫星位于通信卫星的同一轨道平面，沿轨道方向（速度方向）偏移固定距离
    %   本函数为简化版，适用于单时刻计算。如需完整轨道传播，请使用 orbit.generateCompanionFromTLE
    %
    % 参考：
    %   orbit/generateCompanionFromTLE.m - 完整的时序轨道生成

    % 默认参数
    if nargin < 3
        separation = 5000; % 默认5 km
    end

    % 统一为列向量
    commSatPos = commSatPos(:); % 3x1 列向量
    commSatVel = commSatVel(:); % 3x1 列向量

    % 1. 计算轨道方向单位向量
    velNorm = norm(commSatVel);
    velUnit = commSatVel / velNorm;

    % 2. 沿轨道方向偏移（前向偏移，伴飞卫星在通信卫星前方）
    monitorSatPos = commSatPos + velUnit * separation;

    % 3. 伴飞卫星速度与通信卫星相同（同轨道平面，相同轨道参数）
    monitorSatVel = commSatVel;

    % 注：对于短距离伴飞（<10 km），忽略轨道摄动、J2项等高阶效应
    % 实际应用中，长期伴飞可能需要考虑轨道维持

end
