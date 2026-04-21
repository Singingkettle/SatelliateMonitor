function minElev = elevation(constellation)
    % ELEVATION 获取星座最小仰角要求 (dataGen.terminal.elevation)
    %
    %   minElev = dataGen.terminal.elevation('starlink')
    %
    % 输入:
    %   constellation - 星座名称
    %
    % 输出:
    %   minElev - 最小仰角 (度)

    switch lower(constellation)
        case 'starlink'
            minElev = 25;
        case 'oneweb'
            minElev = 20;
        otherwise
            minElev = 25;
            warning('未知星座类型: %s, 使用默认最小仰角: %.0f°', constellation, minElev);
    end
end

