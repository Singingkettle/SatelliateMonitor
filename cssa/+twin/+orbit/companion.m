function [positionTT, velocityTT] = companion(scenario, refSatellite, separationKm, sampleTimeSeconds)
    % COMPANION 根据参考卫星生成伴飞卫星轨道数据
    %
    % 直接使用已加载的卫星对象，无需重新创建场景或从TLE加载
    %
    % 输入参数:
    %   - scenario: satelliteScenario 对象
    %   - refSatellite: 参考卫星对象 (matlabshared.satellitescenario.Satellite)
    %   - separationKm: 沿轨道方向的分离距离 (km)，正值领先，负值落后
    %   - sampleTimeSeconds: 采样步长 (秒)，可选，默认1秒
    %
    % 输出参数:
    %   - positionTT: 位置 timetable (ECEF, 米)
    %   - velocityTT: 速度 timetable (ECEF, 米/秒)
    %
    % 示例:
    %   [posTT, velTT] = twin.orbit.companion(model.Scenario, model.CommSatellite, 5, 1);
    %   companionSat = satellite(scenario, posTT, velTT, 'Name', 'Companion');

    if nargin < 4 || isempty(sampleTimeSeconds)
        sampleTimeSeconds = 1;
    end

    % 验证输入
    if ~isa(scenario, 'satelliteScenario')
        error('twin:orbit:companion:InvalidScenario', ...
            'scenario 必须是 satelliteScenario 对象');
    end
    
    if ~isa(refSatellite, 'matlabshared.satellitescenario.Satellite')
        error('twin:orbit:companion:InvalidInput', ...
            'refSatellite 必须是 satellite 对象');
    end
    
    if ~isvalid(refSatellite)
        error('twin:orbit:companion:InvalidSatellite', ...
            'refSatellite 对象无效');
    end

    % 从场景获取时间范围
    startTime = scenario.StartTime;
    stopTime = scenario.StopTime;

    % 生成采样时刻序列
    timeStep = seconds(sampleTimeSeconds);
    times = startTime:timeStep:stopTime;
    
    if times(end) < stopTime
        times(end + 1) = stopTime;
    end
    
    N = numel(times);

    % 提取参考卫星的状态
    posRef = zeros(N, 3);
    velRef = zeros(N, 3);
    
    for i = 1:N
        [pos_i, vel_i] = states(refSatellite, times(i), 'CoordinateFrame', 'ECEF');
        posRef(i, :) = pos_i(:)';
        velRef(i, :) = vel_i(:)';
    end

    % 计算平均轨道速度
    vNorm = vecnorm(velRef, 2, 2);
    meanVelocity = mean(vNorm);

    % 计算时间偏移
    separationM = separationKm * 1000.0;
    timeOffset = separationM / meanVelocity;

    % 生成伴飞卫星的采样时刻
    companionTimes = times + seconds(timeOffset);

    % 提取伴飞卫星的位置和速度
    posComp = zeros(N, 3);
    velComp = zeros(N, 3);

    for i = 1:N
        try
            [pos_i, vel_i] = states(refSatellite, companionTimes(i), 'CoordinateFrame', 'ECEF');
            posComp(i, :) = pos_i(:)';
            velComp(i, :) = vel_i(:)';
        catch
            % 超出时间范围时使用参考卫星状态
            posComp(i, :) = posRef(i, :);
            velComp(i, :) = velRef(i, :);
        end
    end

    % 构造 timetable
    positionTT = timetable(times(:));
    positionTT.Position = posComp;

    velocityTT = timetable(times(:));
    velocityTT.Velocity = velComp;
end

