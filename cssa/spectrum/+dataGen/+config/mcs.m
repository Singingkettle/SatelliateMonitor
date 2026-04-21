function table = mcs(constellation)
    % MCS 获取星座调制编码方案表 (dataGen.config.mcs)
    %
    %   table = dataGen.config.mcs(constellation)
    %
    % 功能：
    %   从星座物理层配置中提取MCS表，并转换为可读格式
    %
    % 输入:
    %   constellation - 星座名称 ('starlink' / 'oneweb')
    %
    % 输出:
    %   table - Cell 数组 {N×2}，每行为 {ModulationName, CodeRate}
    %           调制名称: 'BPSK', 'QPSK', '16QAM', '64QAM' 等

    phyParams = constellationPhyConfig(constellation);
    rawTable = phyParams.mcsTable;

    % 转换为 Cell 格式: { ModulationName, CodeRate }
    numRows = size(rawTable, 1);
    table = cell(numRows, 2);

    for i = 1:numRows
        modOrder = rawTable(i, 2);
        codeRate = rawTable(i, 3);

        switch modOrder
            case 2
                modName = 'BPSK';
            case 4
                modName = 'QPSK';
            case 16
                modName = '16QAM';
            case 64
                modName = '64QAM';
            otherwise
                modName = sprintf('%dQAM', modOrder);
        end

        table{i, 1} = modName;
        table{i, 2} = codeRate;
    end

end
