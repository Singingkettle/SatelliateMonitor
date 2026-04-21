function [satPos_ECEF, satVel_ECEF] = propagateTLE(tleInfo, simTime)
    % PROPAGATETLE TLE轨道传播
    %
    % 输入：
    %   tleInfo - TLE信息结构体，包含TLEFile字段（文件路径）
    %             （可选：Epoch, MeanMotion等字段用于备用模型）
    %   simTime - 仿真时刻 (datetime)
    %
    % 输出：
    %   satPos_ECEF - 卫星位置 [x, y, z] (ECEF, m)
    %   satVel_ECEF - 卫星速度 [vx, vy, vz] (ECEF, m/s)
    %
    % 说明：
    %   使用SGP4模型传播TLE数据
    %   如果SGP4传播失败（卫星已衰变、时间超出范围等），自动使用简化开普勒模型
    %
    % 备注：修复satelliteScenario时间范围问题，确保包含TLE历元时间

    % 使用MATLAB Satellite Communications Toolbox的sgp4函数
    % 如果没有该工具箱，可以使用简化的开普勒轨道模型

    try
        % 方法1：使用Satellite Communications Toolbox
        % 先读取TLE文件获取历元时间，确保时间范围合适
        if ~isfield(tleInfo, 'Epoch') || isempty(tleInfo.Epoch)
            % 如果tleInfo中没有Epoch，从TLE文件读取
            try
                tleStruct = tleread(tleInfo.TLEFile);
                if isfield(tleStruct, 'Epoch') && ~isempty(tleStruct.Epoch)
                    tleEpoch = tleStruct.Epoch;
                else
                    % 如果读取失败，使用simTime附近的时间范围
                    tleEpoch = simTime;
                end
            catch
                % 如果tleread失败，使用simTime
                tleEpoch = simTime;
            end
        else
            tleEpoch = tleInfo.Epoch;
        end
        
        % 确保时间范围包含TLE历元时间和仿真时间
        % 时间范围：[min(simTime, tleEpoch) - 1天, max(simTime, tleEpoch) + 1天]
        timeStart = min(simTime, tleEpoch) - days(1);
        timeEnd = max(simTime, tleEpoch) + days(1);
        
        % 创建临时场景，确保时间范围足够大
        sc = satelliteScenario(timeStart, timeEnd, 60);
        
        % 加载卫星（使用TLE文件路径）
        sat = satellite(sc, tleInfo.TLEFile);

        % 获取ECEF坐标系下的位置和速度
        % states返回 3x1x1 数组，需要用 (:) 展开为列向量
        [pos_ecef, vel_ecef] = states(sat, simTime, 'CoordinateFrame', 'ecef');
        satPos_ECEF = pos_ecef(:);
        satVel_ECEF = vel_ecef(:);

    catch ME
        % 方法2：简化的开普勒轨道模型（备用）
        % 只对"decayed"或"无法传播"等错误使用警告，其他错误直接抛出
        errorMsg = getReport(ME, 'basic');
        isDecayedError = contains(errorMsg, 'decayed', 'IgnoreCase', true) || ...
                         contains(errorMsg, 'Unable to continue', 'IgnoreCase', true) || ...
                         contains(errorMsg, 'Unable to calculate', 'IgnoreCase', true);
        
        if isDecayedError
            warning('propagateTLE:SatelliteDecayed', ...
                'SGP4传播失败（卫星已衰变或时间超出范围），使用简化开普勒模型: %s', errorMsg);
        else
            % 其他错误（如文件不存在等）直接抛出
            rethrow(ME);
        end

        % 轨道参数
        % 安全处理缺失字段
        if ~isfield(tleInfo, 'MeanMotion') || tleInfo.MeanMotion == 0
            error('propagateTLE:MissingField', 'TLE数据缺少 MeanMotion 字段，无法使用简化模型。');
        end

        if ~isfield(tleInfo, 'Eccentricity'), tleInfo.Eccentricity = 0; end
        if ~isfield(tleInfo, 'Inclination'), tleInfo.Inclination = 0; end
        if ~isfield(tleInfo, 'RAAN'), tleInfo.RAAN = 0; end
        if ~isfield(tleInfo, 'ArgumentOfPerigee'), tleInfo.ArgumentOfPerigee = 0; end

        a = (398600.4418 / (tleInfo.MeanMotion * 2 * pi / 86400) ^ 2) ^ (1/3) * 1000; % 半长轴 (m)
        e = tleInfo.Eccentricity;
        i = deg2rad(tleInfo.Inclination);
        Omega = deg2rad(tleInfo.RAAN);
        omega = deg2rad(tleInfo.ArgumentOfPerigee);

        % 计算当前时刻的平近点角
        if ~isfield(tleInfo, 'Epoch') || isempty(tleInfo.Epoch)
            tleInfo.Epoch = simTime;
        end

        dt = seconds(simTime - tleInfo.Epoch);
        n = tleInfo.MeanMotion * 2 * pi / 86400; % 平均角速度 (rad/s)
        M = deg2rad(tleInfo.MeanAnomaly) + n * dt;
        M = mod(M, 2 * pi);

        % 求解开普勒方程（牛顿迭代）
        E = M;

        for iter = 1:10
            E = M + e * sin(E);
        end

        % 真近点角
        nu = 2 * atan2(sqrt(1 + e) * sin(E / 2), sqrt(1 - e) * cos(E / 2));

        % 轨道半径
        r = a * (1 - e * cos(E));

        % 轨道坐标系下的位置和速度
        x_orb = r * cos(nu);
        y_orb = r * sin(nu);
        z_orb = 0;

        vx_orb = -sqrt(398600.4418e9 / a) * sin(E) / (1 - e * cos(E));
        vy_orb = sqrt(398600.4418e9 / a) * sqrt(1 - e ^ 2) * cos(E) / (1 - e * cos(E));
        vz_orb = 0;

        % 旋转矩阵：轨道坐标系 → ECI
        R3_Omega = [cos(Omega) -sin(Omega) 0; sin(Omega) cos(Omega) 0; 0 0 1];
        R1_i = [1 0 0; 0 cos(i) -sin(i); 0 sin(i) cos(i)];
        R3_omega = [cos(omega) -sin(omega) 0; sin(omega) cos(omega) 0; 0 0 1];
        R_orb2eci = R3_Omega * R1_i * R3_omega;

        % ECI位置和速度
        pos_ECI = R_orb2eci * [x_orb; y_orb; z_orb];
        vel_ECI = R_orb2eci * [vx_orb; vy_orb; vz_orb];

        % ECI转ECEF（简化，忽略岁差章动）
        theta_GMST = mod(280.4606 + 360.9856473662 * dt / 86400, 360);
        theta_GMST = deg2rad(theta_GMST);

        R_eci2ecef = [cos(theta_GMST) sin(theta_GMST) 0;
                      -sin(theta_GMST) cos(theta_GMST) 0;
                      0 0 1];

        satPos_ECEF = R_eci2ecef * pos_ECI;
        satVel_ECEF = R_eci2ecef * vel_ECI;

        % 加上地球自转的影响
        omega_earth = 7.2921159e-5; % 地球自转角速度 (rad/s)
        satVel_ECEF = satVel_ECEF + cross([0; 0; omega_earth], satPos_ECEF);
    end

end
