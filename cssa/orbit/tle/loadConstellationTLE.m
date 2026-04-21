function tleData = loadConstellationTLE(constellation, varargin)
    % LOADCONSTELLATIONTLE 加载星座TLE数据
    %
    % 输入：
    %   constellation - 星座类型 ('starlink' / 'oneweb')
    %
    % 输出：
    %   tleData - TLE数据结构数组

    % 找到项目根目录（相对于此脚本）
    scriptPath = fileparts(mfilename('fullpath'));
    projectRoot = fullfile(scriptPath, '..', '..', '..');

    baseDir = fullfile(projectRoot, 'data', 'TLE');

    if strcmp(constellation, 'starlink')
        tleDir = fullfile(baseDir, 'starlink');
        tlePattern = '*.tle';
    elseif strcmp(constellation, 'oneweb')
        tleDir = fullfile(baseDir, 'oneweb');
        tlePattern = '*.tle';
    else
        error('不支持的星座类型: %s', constellation);
    end

    % 查找TLE文件
    tleFiles = dir(fullfile(tleDir, tlePattern));

    if isempty(tleFiles)
        error('未找到TLE文件，目录: %s, 模式: %s', tleDir, tlePattern);
    end

    % 解析可选参数
    loadFullTLE = false;

    if ~isempty(varargin)
        parser = inputParser;
        addParameter(parser, 'LoadFullTLE', true, @(x) islogical(x) || isnumeric(x));
        parse(parser, varargin{:});
        loadFullTLE = logical(parser.Results.LoadFullTLE);
    end

    % 读取TLE数据
    numFiles = numel(tleFiles);
    tleData(numFiles, 1) = struct('TLEFile', '', 'Name', '');

    for i = 1:numFiles
        tleFile = fullfile(tleDir, tleFiles(i).name);

        tleData(i).TLEFile = tleFile; % 保存TLE文件路径
        tleData(i).Name = stripExtension(tleFiles(i).name);

        if loadFullTLE
            tle = tleread(tleFile);

            tleData(i).SatelliteNumber = getFieldWithFallback(tle, {'SatelliteNumber', 'SatelliteCatalogNumber'}, 0);
            tleData(i).Epoch = getFieldWithFallback(tle, {'Epoch'}, NaT);
            tleData(i).Inclination = getFieldWithFallback(tle, {'Inclination'}, 0);
            tleData(i).RAAN = getFieldWithFallback(tle, {'RAAN', 'RightAscensionOfAscendingNode'}, 0);
            tleData(i).Eccentricity = getFieldWithFallback(tle, {'Eccentricity'}, 0);
            tleData(i).ArgumentOfPerigee = getFieldWithFallback(tle, {'ArgumentOfPerigee', 'ArgumentOfPeriapsis'}, 0);
            tleData(i).MeanAnomaly = getFieldWithFallback(tle, {'MeanAnomaly'}, 0);
            tleData(i).MeanMotion = getFieldWithFallback(tle, {'MeanMotion'}, 0);
            tleData(i).TLE = tle; 
        end

    end

    fprintf('  已加载 %d 个TLE数据文件\n', length(tleData));

end

function name = stripExtension(filename)
    dotIdx = find(filename == '.', 1, 'last');

    if isempty(dotIdx)
        name = filename;
    else
        name = filename(1:dotIdx - 1);
    end

end

function value = getFieldWithFallback(structObj, fieldNames, defaultValue)

    if nargin < 3
        defaultValue = [];
    end

    value = defaultValue;

    for idx = 1:numel(fieldNames)
        fieldName = fieldNames{idx};

        if isfield(structObj, fieldName)
            value = structObj.(fieldName);
            return;
        end

    end

end
