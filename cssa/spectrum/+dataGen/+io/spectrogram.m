function imgColor = spectrogram(x, path, config, imgSize)
    % SPECTROGRAM 保存 IQ 数据的语谱图 (dataGen.io.spectrogram)
    %
    % 对应旧函数: generateSpectrogramImage
    %
    % 输入:
    %   x          - 复基带信号（IQ数据）
    %   path       - 保存路径 (可选)
    %   config     - 配置结构体 (包含 NFFT, WindowLength 等)
    %   imgSize    - 输出图像尺寸 [height, width], 默认 [640, 640]
    %                注意: Height=Time, Width=Freq
    %
    % 输出:
    %   imgColor   - RGB图像矩阵

    if nargin < 4 || isempty(imgSize), imgSize = [640, 640]; end

    % 确保输入是一维向量
    if ~isvector(x)
        error('saveSpectrogram:InvalidSignal', '输入信号必须是一维向量。');
    end

    x = x(:);

    % 提取 STFT 参数
    stftParams = struct();

    if isstruct(config)
        % 支持直接传入 struct 或嵌套在 SpectrumProcessing 中
        if isfield(config, 'broadband') && isfield(config.broadband, 'processing')
            src = config.broadband.processing;
        elseif isfield(config, 'processing')
            src = config.Processing;
        else
            src = config;
        end

        if isfield(src, 'windowLength'), stftParams.windowLength = src.windowLength; end
        if isfield(src, 'overlap'), stftParams.overlap = src.overlap; end
        if isfield(src, 'nfft'), stftParams.nfft = src.nfft; end
        if isfield(src, 'windowType'), stftParams.windowType = src.windowType; end
    end

    % 默认参数逻辑 (参照 generateSpectrogramImage)
    if ~isfield(stftParams, 'windowType') || isempty(stftParams.windowType)
        stftParams.windowType = 'hann';
    end

    % WindowLength / NFFT 默认值处理
    if ~isfield(stftParams, 'windowLength') || isempty(stftParams.windowLength)

        if isfield(stftParams, 'nfft') && ~isempty(stftParams.nfft)
            stftParams.windowLength = stftParams.nfft;
        else
            stftParams.windowLength = 2048;
        end

    end

    if ~isfield(stftParams, 'nfft') || isempty(stftParams.nfft)
        stftParams.nfft = stftParams.windowLength;
    end

    if ~isfield(stftParams, 'overlap') || isempty(stftParams.overlap)
        stftParams.overlap = max(0, round(stftParams.windowLength * 0.75));
    end

    % 构建窗口
    windowLength = max(8, round(stftParams.windowLength));
    overlap = min(max(round(stftParams.overlap), 0), windowLength - 1);
    nfft = max(windowLength, round(stftParams.nfft));

    switch lower(string(stftParams.windowType))
        case {'hann', 'hanning'}
            window = hann(windowLength);
        case 'hamming'
            window = hamming(windowLength);
        case 'blackman'
            window = blackman(windowLength);
        otherwise
            window = hann(windowLength); % Default fallback
    end

    % 生成谱图
    % spectrogram 输出 P 维度: (Frequency x Time)
    % 'centered' 使得 0Hz 在中心 (如果是 complex 输入)
    % 'psd' 返回功率谱密度
    [~, ~, ~, P] = spectrogram(x, window, overlap, nfft, 'centered', 'psd');

    % 转换为对数刻度 (dB) 并转置
    % 转置后维度: (Time x Frequency)
    % P' -> Rows=Time, Cols=Frequency
    P_dB = 10 * log10(abs(P') + eps);

    % 缩放像素值到 [0,1] 并调整大小
    % imresize 会保持长宽比意义: rows -> Height (Time), cols -> Width (Frequency)
    % 使用 'nearest' 插值 (参照旧代码)
    im = imresize(rescale(P_dB), imgSize, 'nearest');

    % 转换为 RGB
    % flipud 翻转上下 (Rows)
    % 原始 P' 的 Row 1 是 Time Start (t=0)
    % 图像默认 Row 1 是 Top
    % flipud 后: Top 是 Time End, Bottom 是 Time Start (t=0)
    % 这样符合坐标系: Y轴向上增加代表时间增加
    imgUint8 = im2uint8(im);

    % 使用 parula colormap (参照旧代码)
    imgColor = im2uint8(flipud(ind2rgb(imgUint8, parula(256))));

    % 保存
    if nargin >= 2 && ~isempty(path)
        % 确保目录存在
        d = fileparts(path);
        if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
        imwrite(imgColor, path);
    end

end
