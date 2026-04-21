function [elevation, azimuth] = calculateAngles(utPos, satPos)
    % CALCULATEANGLES 计算仰角和方位角
    %
    % 输入:
    %   utPos      - 用户终端位置 [lat, lon, alt]
    %   satPos     - 卫星位置 [x, y, z] (ECEF)
    %
    % 输出:
    %   elevation  - 仰角 (度)
    %   azimuth    - 方位角 (度)

    % 调用 MATLAB 官方 lla2ecef 函数
    utECEF = lla2ecef(utPos)';  % 官方API返回行向量，转为列向量
    satPosCol = satPos(:);      % 确保卫星位置是列向量
    relPos = satPosCol - utECEF;

    lat = utPos(1) * pi / 180;
    lon = utPos(2) * pi / 180;

    R = [-sin(lon), cos(lon), 0;
         -sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat);
         cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat)];

    % relPos已经是列向量（3x1），直接相乘
    enu = R * relPos(:);
    e = enu(1);
    n = enu(2);
    u = enu(3);

    elevation = atan2d(u, sqrt(e ^ 2 + n ^ 2));
    azimuth = atan2d(e, n);

end
