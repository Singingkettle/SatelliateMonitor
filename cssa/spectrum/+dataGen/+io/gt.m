function gt(imgPath, imgColor, bboxList, classList)
    % GT 保存带有 GT 框的可视化图像 (dataGen.io.gt)
    %
    % 输入:
    %   imgPath: 保存路径
    %   imgColor: RGB 图像矩阵
    %   bboxList: [N x 4] 边界框
    %   classList: {N x 1} 类别名称 (可选)

    if nargin < 4, classList = {}; end

    if isempty(bboxList)
        % 如果没有框，直接保存原图
        imwrite(imgColor, imgPath);
        return;
    end

    outputImage = imgColor;

    % 准备标签
    if isempty(classList)
        labels = repmat({''}, size(bboxList, 1), 1);
    else
        labels = classList;
    end

    try
        % 尝试使用 Computer Vision Toolbox 的 insertObjectAnnotation
        % 这个函数通常用于绘制带有标签的框，且自动处理文字背景，效果较好
        outputImage = insertObjectAnnotation(outputImage, 'rectangle', bboxList, labels, ...
            'LineWidth', 2, 'TextBoxOpacity', 0.8, 'FontSize', 10, 'Color', 'red');
    catch
        % 回退方案：仅使用 insertShape (Vision Toolbox 基础函数)
        try
            outputImage = insertShape(outputImage, 'Rectangle', bboxList, 'LineWidth', 2, 'Color', 'red');
        catch
            % 再次回退：手动在图像上画框 (不推荐，太慢且复杂)
            % 这里仅打印警告并保存原图
            warning('Unable to draw BBox: Computer Vision Toolbox functions not found.');
        end

    end

    % 确保目录存在
    d = fileparts(imgPath);
    if ~isempty(d) && ~exist(d, 'dir'), mkdir(d); end
    
    imwrite(outputImage, imgPath);

end
