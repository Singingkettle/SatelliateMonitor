function [elevation, azimuth, range] = calculateLinkGeometry(utPosition, satPosition_ECEF)
    % CALCULATELINKGEOMETRY 计算链路几何参数
    %
    % 输入：
    %   utPosition - 地面终端位置 [lat, lon, alt] (度, 度, 米)
    %   satPosition_ECEF - 卫星位置 [x, y, z] (ECEF, m) - 列向量或行向量
    %
    % 输出：
    %   elevation - 仰角 (度)
    %   azimuth - 方位角 (度)
    %   range - 距离 (米)

    % 地面终端位置转ECEF
    utPosition_ECEF = lla2ecef(utPosition)';  % 官方API返回行向量，转为列向量

    % 统一为列向量（兼容 propagateTLE 返回的列向量）
    satPosition_ECEF = satPosition_ECEF(:); % 3x1 列向量
    utPosition_ECEF = utPosition_ECEF(:); % 3x1 列向量

    % 计算距离向量
    rangeVector = satPosition_ECEF - utPosition_ECEF;
    range = norm(rangeVector);

    % 转换到本地ENU坐标系
    [xEast, yNorth, zUp] = ecef2enu(satPosition_ECEF(1), satPosition_ECEF(2), satPosition_ECEF(3), ...
        utPosition(1), utPosition(2), utPosition(3), wgs84Ellipsoid);

    % 计算仰角和方位角
    elevation = rad2deg(atan2(zUp, sqrt(xEast ^ 2 + yNorth ^ 2)));
    azimuth = rad2deg(atan2(xEast, yNorth));

    % 确保方位角在[0, 360)范围内
    if azimuth < 0
        azimuth = azimuth + 360;
    end

end
