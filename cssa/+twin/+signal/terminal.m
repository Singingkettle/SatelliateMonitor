function terminalPos = terminal(scenario, commSatellite, constellation, ~, config)
    % TERMINAL 为数字孪生场景生成终端位置
    %
    %   基于通信卫星，搜索一个能够与卫星建立有效通信的地面终端位置
    %   改进版：优先在卫星星下点附近搜索，提高成功率
    %
    % 输入:
    %   scenario      - satelliteScenario 对象
    %   commSatellite - 通信卫星对象
    %   constellation - 星座名称 ('starlink', 'oneweb')
    %   ~             - 保留参数（兼容旧接口）
    %   config        - 配置结构体 (可选)
    %
    % 输出:
    %   terminalPos - 终端位置 [lat, lon, alt]
    
    if nargin < 5
        config = struct();
    end
    
    if ~isfield(config, 'numCandidates')
        config.numCandidates = 500;
    end
    
    % 获取场景时间范围
    startTime = scenario.StartTime;
    stopTime = scenario.StopTime;
    duration = seconds(stopTime - startTime);
    
    % 获取最小仰角
    minElev = getMinElevation(constellation);
    
    % 初始化星下点位置（稍后在循环中会更新）
    satSubpoint = [0, 0]; %#ok<NASGU>
    hasSubpoint = false; %#ok<NASGU>
    
    % 鲁棒的时间采样：确保在场景有效时间范围内
    % 关键：对于短周期场景，使用场景中间时间点（更稳定）
    if duration < 1
        % 非常短的场景：使用中间时间点（确保在有效范围内）
        timeOffsets = [duration / 2];
    elseif duration < 10
        % 短场景：在起始、中间时间点采样
        timeOffsets = [0, duration/2, duration * 0.9];
    else
        % 正常场景：多点采样
        numTimeSlots = min(20, max(1, floor(duration / 3)));
        % 确保 timeOffsets 在 [0, duration] 范围内
        margin = min(3, duration * 0.1);  % 边界留余量（最多10%或3秒）
        timeOffsets = linspace(margin, duration - margin, numTimeSlots);
    end
    
    fprintf('[Terminal] 场景时长=%.3fs, 采样点数=%d\n', duration, length(timeOffsets));
    
    bestTerminal = [];
    bestElevation = 0;
    
    for tIdx = 1:length(timeOffsets)
        % 确保 testTime 在有效范围内
        offsetSec = max(0, min(timeOffsets(tIdx), duration));
        testTime = startTime + seconds(offsetSec);
        
        % 确保不超出 stopTime
        if testTime > stopTime
            testTime = stopTime;
        end
        
        try
            % 获取卫星 ECEF 位置（用于仰角计算）
            [satPosVel, ~] = states(commSatellite, testTime, 'CoordinateFrame', 'ecef');
            % states 返回 [x; y; z; vx; vy; vz] 或 [x; y; z]
            satPos = satPosVel(1:3, 1);  % 取位置部分，确保是 3x1 列向量
            
            % 获取卫星地理坐标（用于生成星下点附近候选位置）
            [geoState, ~] = states(commSatellite, testTime, 'CoordinateFrame', 'geographic');
            % geographic 返回 [lat; lon; alt; vlat; vlon; valt] 或 [lat; lon; alt]
            satLat = geoState(1, 1);
            satLon = geoState(2, 1);
            satAlt = geoState(3, 1);  % 卫星高度 (m)
            satSubpoint = [satLat, satLon];
            hasSubpoint = true;
            
            % 调试输出：显示卫星位置信息
            if tIdx == 1
                fprintf('[Terminal] 时间: %s (偏移%.3fs)\n', datestr(testTime), offsetSec);
                fprintf('[Terminal] 卫星: ECEF=[%.0f, %.0f, %.0f]km, 地理=[%.2f°, %.2f°, %.0fkm]\n', ...
                    satPos(1)/1000, satPos(2)/1000, satPos(3)/1000, satLat, satLon, satAlt/1000);
            end
        catch ME
            fprintf('[Terminal] 获取卫星状态失败 (t=%.3fs): %s\n', offsetSec, ME.message);
            continue;
        end
        
        % 生成候选终端位置（优先在星下点附近）
        candidates = generateCandidatesNearSubpoint(constellation, config.numCandidates, satSubpoint, hasSubpoint);
        
        % 首先验证星下点的仰角（应该接近90°）
        if tIdx == 1
            subpointPos = [satSubpoint(1), satSubpoint(2), 0];
            try
                [subpointElev, ~, subpointRange] = calculateLinkGeometry(subpointPos, satPos);
                fprintf('[Terminal] 验证星下点仰角: [%.2f°, %.2f°] -> 仰角=%.1f°, 距离=%.0fkm\n', ...
                    subpointPos(1), subpointPos(2), subpointElev, subpointRange/1000);
            catch ME
                fprintf('[Terminal] 星下点仰角计算失败: %s\n', ME.message);
            end
        end
        
        % 找最佳仰角位置
        maxElevThisRound = 0;
        for i = 1:size(candidates, 1)
            candidatePos = candidates(i, :);
            try
                [elev, ~, ~] = calculateLinkGeometry(candidatePos, satPos);
                if isfinite(elev) && elev > maxElevThisRound
                    maxElevThisRound = elev;
                end
                if elev > bestElevation && elev >= minElev
                    bestElevation = elev;
                    bestTerminal = candidatePos;
                end
            catch
                % 忽略计算失败的候选位置
                continue;
            end
        end
        
        % 第一轮调试输出
        if tIdx == 1
            fprintf('[Terminal] 星下点=[%.2f°, %.2f°], 本轮最大仰角=%.1f°, 目标仰角>%d°\n', ...
                satSubpoint(1), satSubpoint(2), maxElevThisRound, minElev);
        end
        
        if bestElevation > 45
            break;
        end
    end
    
    if isempty(bestTerminal)
        error('twin:signal:NoValidTerminal', ...
            '无法找到与卫星建链的终端位置（仰角>%d°）', minElev);
    end
    
    terminalPos = bestTerminal;
    fprintf('[Terminal] 位置: [%.2f°, %.2f°], 仰角=%.1f°\n', ...
        terminalPos(1), terminalPos(2), bestElevation);
end

function candidates = generateCandidatesNearSubpoint(constellation, n, satSubpoint, hasSubpoint)
    % 在卫星星下点附近生成候选位置，大大提高找到有效终端的概率
    %
    % 策略：
    %   - 首先包含星下点本身（仰角应该是90°）
    %   - 70% 的候选位置在星下点附近（半径30°内）
    %   - 30% 的候选位置在更大范围随机分布
    
    switch lower(constellation)
        case 'starlink'
            latRange = [-57, 57];
            maxCoverageRadius = 25;  % Starlink 覆盖半径约 ~2500km，对应约25°
        case 'oneweb'
            latRange = [-87, 87];
            maxCoverageRadius = 30;  % OneWeb 轨道更高，覆盖更大
        otherwise
            latRange = [-60, 60];
            maxCoverageRadius = 25;
    end
    
    if hasSubpoint
        % 首先添加星下点本身和附近几个确定性位置
        subpointLat = min(max(satSubpoint(1), latRange(1)), latRange(2));
        subpointLon = satSubpoint(2);
        
        % 确定性候选位置（星下点及其附近）
        deterministicCandidates = [
            subpointLat, subpointLon, 0;              % 星下点
            subpointLat + 5, subpointLon, 0;          % 北偏5°
            subpointLat - 5, subpointLon, 0;          % 南偏5°
            subpointLat, subpointLon + 5, 0;          % 东偏5°
            subpointLat, subpointLon - 5, 0;          % 西偏5°
            subpointLat + 10, subpointLon, 0;         % 北偏10°
            subpointLat - 10, subpointLon, 0;         % 南偏10°
        ];
        % 限制确定性候选位置的纬度
        deterministicCandidates(:, 1) = min(max(deterministicCandidates(:, 1), latRange(1)), latRange(2));
        % 经度环绕
        deterministicCandidates(:, 2) = mod(deterministicCandidates(:, 2) + 180, 360) - 180;
        
        nDeterministic = size(deterministicCandidates, 1);
        nRemaining = n - nDeterministic;
        
        % 70% 的剩余候选位置在星下点附近
        nNearby = round(nRemaining * 0.7);
        nRandom = nRemaining - nNearby;
        
        % 在星下点附近生成（使用高斯分布，标准差为覆盖半径的1/3）
        nearbyLats = satSubpoint(1) + randn(nNearby, 1) * (maxCoverageRadius / 3);
        nearbyLons = satSubpoint(2) + randn(nNearby, 1) * (maxCoverageRadius / 3);
        
        % 限制纬度范围
        nearbyLats = min(max(nearbyLats, latRange(1)), latRange(2));
        % 经度环绕
        nearbyLons = mod(nearbyLons + 180, 360) - 180;
        
        nearbyCandidates = [nearbyLats, nearbyLons, zeros(nNearby, 1)];
        
        % 剩余随机分布
        randomLats = latRange(1) + (latRange(2) - latRange(1)) * rand(nRandom, 1);
        randomLons = -180 + 360 * rand(nRandom, 1);
        randomCandidates = [randomLats, randomLons, zeros(nRandom, 1)];
        
        candidates = [deterministicCandidates; nearbyCandidates; randomCandidates];
    else
        % 没有星下点信息，全部随机生成
        lats = latRange(1) + (latRange(2) - latRange(1)) * rand(n, 1);
        lons = -180 + 360 * rand(n, 1);
        candidates = [lats, lons, zeros(n, 1)];
    end
end

function minElev = getMinElevation(constellation)
    switch lower(constellation)
        case 'starlink'
            minElev = 25;
        case 'oneweb'
            minElev = 20;
        otherwise
            minElev = 25;
    end
end
