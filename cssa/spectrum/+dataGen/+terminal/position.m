function utPositions = position(constellation, numCandidates)
    % POSITION 生成随机地面终端位置 (dataGen.terminal.position)
    %
    %   utPositions = dataGen.terminal.position('starlink', 100)
    %
    % 输入:
    %   constellation  - 星座名称
    %   numCandidates  - 候选位置数量
    %
    % 输出:
    %   utPositions - N×3 矩阵 [lat, lon, alt]

    phyParams = constellationPhyConfig(constellation);
    coverage = phyParams.serviceCoverage;

    if nargin < 2
        [~, spectrumConfig] = evalc('spectrumMonitorConfig(constellation);');
        numCandidates = spectrumConfig.orbit.DefaultNumUTCandidates;
    end

    % 根据星座服务区域生成位置
    maxLat = coverage.latitudeRange;
    lat = (rand(numCandidates, 1) - 0.5) * 2 * maxLat;
    lon = (rand(numCandidates, 1) - 0.5) * coverage.longitudeRange;

    % 海拔高度
    altRange = coverage.altitudeRange;
    alt = altRange(1) + rand(numCandidates, 1) * (altRange(2) - altRange(1));

    utPositions = [lat, lon, alt];
end

