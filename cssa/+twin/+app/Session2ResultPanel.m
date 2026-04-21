classdef Session2ResultPanel < matlabshared.application.Component
    % SESSION2RESULTPANEL 会话2 验收结果面板
    %
    %   主面板 (嵌入 GUI 底部):
    %     顶部: 当前 cell 元数据 + 总体/分星座准确率
    %     下方: 左 = 准确率-SNR 曲线, 右 = 准确率-多普勒曲线
    %
    %   弹出窗口 (独立 uifigure, 滚动):
    %     左侧: 当前样本 STFT (原图 + 检测) + 混淆矩阵
    %     右侧: 最近 N 条样本明细 (原图缩略 + 检测缩略 + 元数据)
    %
    %   一切弹窗在 onCellReady 第一次触发时按需创建，避免空窗口阻塞。

    properties (Hidden)
        MainGrid

        % 顶部 — 元数据 + 累积统计
        MetaPanel
        MetaLabels = struct()
        StatStarlinkLabel
        StatOnewebLabel
        StatOverallLabel

        % 底部 — 2 列曲线
        AccSnrAxes
        AccDopAxes

        % 弹出窗口 (样本明细)
        SampleFig
        SampleAxesRaw
        SampleAxesPred
        SampleTitleLabel
        ConfusionAxesPopup
        HistoryGrid              % 历史样本滚动区
        HistoryRows = {}         % 每行 = struct(panel, axRaw, axPred, lblMeta)
        HistoryCapacity = 60     % 最多保留多少历史行
        HistoryCount = 0

        % 状态
        IsInitialized = false
        Plan
        LastSnapshot
        LastMetrics

        % 配色
        BgColor = [0.08 0.08 0.10]
        TextColor = [0.85 0.85 0.85]
        StarlinkColor = [1.00 0.60 0.20]
        OnewebColor = [0.20 0.80 0.60]
        AccentColor = [0.30 0.90 0.40]
    end

    methods
        function this = Session2ResultPanel(varargin)
            this@matlabshared.application.Component(varargin{:});
            this.FigureDocument.Visible = 0;
        end

        function name = getName(~)
            name = '验收结果';
        end

        function tag = getTag(~)
            tag = 'session2result';
        end

        function update(this)
            createUI(this);
        end

        function createUI(this)
            clf(this.Figure);
            this.Figure.Color = this.BgColor;

            this.MainGrid = uigridlayout(this.Figure, [2, 1]);
            this.MainGrid.RowHeight = {'fit', '1x'};
            this.MainGrid.ColumnWidth = {'1x'};
            this.MainGrid.Padding = [6 6 6 6];
            this.MainGrid.RowSpacing = 6;
            this.MainGrid.BackgroundColor = this.BgColor;
            this.MainGrid.Scrollable = 'on';

            this.buildMetaArea();
            this.buildCurvesArea();

            this.IsInitialized = true;
            this.showPlaceholders();
        end

        function buildMetaArea(this)
            this.MetaPanel = uipanel(this.MainGrid, ...
                'Title', '当前 cell 元数据 + 累积准确率（详细样本明细见弹出窗口）', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.AccentColor, ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'BorderType', 'line', 'BorderColor', this.AccentColor);
            grid = uigridlayout(this.MetaPanel, [2, 1]);
            grid.RowHeight = {'fit', 'fit'};
            grid.Padding = [10 4 10 4];
            grid.RowSpacing = 4;
            grid.BackgroundColor = this.BgColor;

            % 第一行：当前 cell 元数据
            metaRow = uigridlayout(grid, [1, 9]);
            metaRow.ColumnWidth = repmat({'1x'}, 1, 9);
            metaRow.Padding = [0 0 0 0];
            metaRow.ColumnSpacing = 6;
            metaRow.BackgroundColor = this.BgColor;

            this.MetaLabels.constellation = this.makeMetaLabel(metaRow, '星座: ---');
            this.MetaLabels.satIdx        = this.makeMetaLabel(metaRow, '卫星: ---');
            this.MetaLabels.channel       = this.makeMetaLabel(metaRow, '信道: ---');
            this.MetaLabels.snrSet        = this.makeMetaLabel(metaRow, 'SNR(设): ---');
            this.MetaLabels.snrMeas       = this.makeMetaLabel(metaRow, 'SNR(实测): ---');
            this.MetaLabels.noiseFloor    = this.makeMetaLabel(metaRow, '噪底: ---');
            this.MetaLabels.doppler       = this.makeMetaLabel(metaRow, 'Doppler: ---');
            this.MetaLabels.pred          = this.makeMetaLabel(metaRow, '预测: ---');
            this.MetaLabels.score         = this.makeMetaLabel(metaRow, '置信度: ---');

            % 第二行：累积统计
            statRow = uigridlayout(grid, [1, 3]);
            statRow.ColumnWidth = {'1x', '1x', '1x'};
            statRow.Padding = [0 0 0 0];
            statRow.BackgroundColor = this.BgColor;

            this.StatStarlinkLabel = uilabel(statRow, ...
                'Text', 'Starlink: ---% (0/0)', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', this.StarlinkColor, ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', this.BgColor);
            this.StatOverallLabel = uilabel(statRow, ...
                'Text', '总体准确率: ---%', ...
                'FontSize', 16, 'FontWeight', 'bold', ...
                'FontColor', this.AccentColor, ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', this.BgColor);
            this.StatOnewebLabel = uilabel(statRow, ...
                'Text', 'OneWeb: ---% (0/0)', ...
                'FontSize', 13, 'FontWeight', 'bold', ...
                'FontColor', this.OnewebColor, ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', this.BgColor);
        end

        function lbl = makeMetaLabel(this, parent, text)
            lbl = uilabel(parent, ...
                'Text', text, 'FontSize', 11, ...
                'FontColor', this.TextColor, ...
                'BackgroundColor', this.BgColor);
        end

        function buildCurvesArea(this)
            % 底部均分两列: 左 SNR 曲线, 右 Doppler 曲线
            curvesPanel = uipanel(this.MainGrid, ...
                'BackgroundColor', this.BgColor, 'BorderType', 'none');
            grid = uigridlayout(curvesPanel, [1, 2]);
            grid.ColumnWidth = {'1x', '1x'};
            grid.Padding = [4 4 4 4];
            grid.ColumnSpacing = 8;
            grid.BackgroundColor = this.BgColor;

            % --- 左: 准确率 vs SNR (Starlink + OneWeb 叠加) ---
            leftHost = uipanel(grid, ...
                'Title', '准确率 vs SNR (Starlink/OneWeb)', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.TextColor, ...
                'FontSize', 11, 'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            leftLayout = uigridlayout(leftHost, [1, 1]);
            leftLayout.Padding = [4 4 4 4];
            leftLayout.BackgroundColor = this.BgColor;
            this.AccSnrAxes = uiaxes(leftLayout);
            this.setupCurveAxes(this.AccSnrAxes, 'SNR (dB)', '识别准确率 (%)');

            % --- 右: 准确率 vs 多普勒 (Starlink + OneWeb 叠加) ---
            rightHost = uipanel(grid, ...
                'Title', '准确率 vs 多普勒 (Starlink/OneWeb)', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.TextColor, ...
                'FontSize', 11, 'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            rightLayout = uigridlayout(rightHost, [1, 1]);
            rightLayout.Padding = [4 4 4 4];
            rightLayout.BackgroundColor = this.BgColor;
            this.AccDopAxes = uiaxes(rightLayout);
            this.setupCurveAxes(this.AccDopAxes, '多普勒 (kHz)', '识别准确率 (%)');
        end

        function setupCurveAxes(this, ax, xlab, ylab)
            ax.Color = [0.08 0.08 0.10];
            ax.XColor = this.TextColor;
            ax.YColor = this.TextColor;
            ax.GridColor = [0.3 0.3 0.3];
            ax.GridAlpha = 0.4;
            ax.XGrid = 'on';
            ax.YGrid = 'on';
            ax.FontSize = 10;
            ax.Box = 'on';
            xlabel(ax, xlab, 'Color', this.TextColor);
            ylabel(ax, ylab, 'Color', this.TextColor);
            ylim(ax, [0, 105]);
        end

        function showPlaceholders(this)
            if ~this.IsInitialized, return; end
            cla(this.AccSnrAxes);
            cla(this.AccDopAxes);
            text(this.AccSnrAxes, 0.5, 0.5, '等待数据 (随测试推进逐步填充)', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Color', [0.4 0.4 0.4], 'FontSize', 12);
            text(this.AccDopAxes, 0.5, 0.5, '等待数据 (随测试推进逐步填充)', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Color', [0.4 0.4 0.4], 'FontSize', 12);
        end

        % ============================================================
        %   接口：流程面板回调
        % ============================================================
        function onPlanReady(this, plan)
            this.Plan = plan;
            this.refreshAxesXLimits();
        end

        function onCellReady(this, evt)
            if ~this.IsInitialized, this.createUI(); end

            p = evt.Payload;

            this.ensureSampleWindow();      % 首次触发时创建弹出窗口
            this.renderSampleInPopup(p);    % 大图 + 历史记录追加
            this.renderMeta(p.CellInfo, p.Sample, p.Detection);

            snap = p.Snapshot;
            this.LastSnapshot = snap;
            this.renderSnapshot(snap);

            % 实时刷新底部曲线 (粗略, 每 25 条 + 末条)
            if mod(p.Processed, 25) == 0 || p.Processed == p.TotalCells
                this.renderConfusionInPopup(snap);
                this.renderQuickCurves();
            end
        end

        function onMetricsFinalized(this, metrics, paths)
            this.LastMetrics = metrics;
            this.renderFinalCurves(metrics);
            this.renderFinalSummary(metrics, paths);
            if ~isempty(this.SampleFig) && isvalid(this.SampleFig)
                this.renderConfusionInPopup(struct('confusionMatrix', metrics.confusionMatrix));
            end
        end

        function reset(this)
            if ~this.IsInitialized, return; end
            this.LastSnapshot = []; this.LastMetrics = []; this.Plan = [];
            this.HistoryRows = {}; this.HistoryCount = 0;
            this.showPlaceholders();
            this.StatStarlinkLabel.Text = 'Starlink: ---% (0/0)';
            this.StatOnewebLabel.Text = 'OneWeb: ---% (0/0)';
            this.StatOverallLabel.Text = '总体准确率: ---%';
            fns = fieldnames(this.MetaLabels);
            for i = 1:numel(fns)
                this.MetaLabels.(fns{i}).Text = strtok(this.MetaLabels.(fns{i}).Text, ':') + ": ---";
            end
            % 不主动关闭弹窗 (由用户决定); 仅清空历史区
            if ~isempty(this.SampleFig) && isvalid(this.SampleFig) && ~isempty(this.HistoryGrid)
                delete(allchild(this.HistoryGrid));
            end
        end
    end

    % ============================================================
    %   弹出样本窗口
    % ============================================================
    methods (Access = private)
        function ensureSampleWindow(this)
            if ~isempty(this.SampleFig) && isvalid(this.SampleFig), return; end

            this.SampleFig = uifigure( ...
                'Name', '会话2 样本检测明细 (滚动查看)', ...
                'Color', this.BgColor, ...
                'Position', [120 80 1080 720]);
            try, this.SampleFig.Icon = ''; catch, end

            root = uigridlayout(this.SampleFig, [1, 2]);
            root.ColumnWidth = {'1.1x', '1x'};
            root.Padding = [8 8 8 8];
            root.ColumnSpacing = 10;
            root.BackgroundColor = this.BgColor;

            % --- 左侧: 当前样本大图 + 混淆矩阵 ---
            leftPanel = uipanel(root, ...
                'BackgroundColor', this.BgColor, 'BorderType', 'none');
            leftGrid = uigridlayout(leftPanel, [3, 1]);
            leftGrid.RowHeight = {28, '1.4x', '1x'};
            leftGrid.Padding = [0 0 0 0];
            leftGrid.RowSpacing = 6;
            leftGrid.BackgroundColor = this.BgColor;

            this.SampleTitleLabel = uilabel(leftGrid, ...
                'Text', '当前样本: 等待第一条数据…', ...
                'FontSize', 12, 'FontWeight', 'bold', ...
                'FontColor', this.AccentColor, ...
                'BackgroundColor', this.BgColor);

            samplePanel = uipanel(leftGrid, ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.TextColor, ...
                'FontSize', 10, 'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34], ...
                'Title', '左: 原始 STFT (640×640) | 右: YOLOX 检测结果');
            sampleGrid = uigridlayout(samplePanel, [1, 2]);
            sampleGrid.ColumnSpacing = 6;
            sampleGrid.Padding = [4 4 4 4];
            sampleGrid.BackgroundColor = this.BgColor;

            rawHost = uipanel(sampleGrid, 'BackgroundColor', [0.05 0.05 0.07], ...
                'BorderType', 'none');
            this.SampleAxesRaw = uiaxes(rawHost, ...
                'Position', [0 0 1 1], 'Units', 'normalized');
            this.setupImageAxes(this.SampleAxesRaw);

            predHost = uipanel(sampleGrid, 'BackgroundColor', [0.05 0.05 0.07], ...
                'BorderType', 'none');
            this.SampleAxesPred = uiaxes(predHost, ...
                'Position', [0 0 1 1], 'Units', 'normalized');
            this.setupImageAxes(this.SampleAxesPred);

            confPanel = uipanel(leftGrid, ...
                'Title', '混淆矩阵 (实时累积, 行=真实, 列=预测)', ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.TextColor, ...
                'FontSize', 10, 'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            confLayout = uigridlayout(confPanel, [1, 1]);
            confLayout.Padding = [4 4 4 4];
            confLayout.BackgroundColor = this.BgColor;
            this.ConfusionAxesPopup = uiaxes(confLayout);
            this.ConfusionAxesPopup.Color = this.BgColor;
            this.ConfusionAxesPopup.XColor = this.TextColor;
            this.ConfusionAxesPopup.YColor = this.TextColor;

            % --- 右侧: 最近 N 条样本滚动列表 ---
            rightPanel = uipanel(root, ...
                'Title', sprintf('样本检测明细 (滚动, 最近 %d 条)', this.HistoryCapacity), ...
                'BackgroundColor', this.BgColor, ...
                'ForegroundColor', this.TextColor, ...
                'FontSize', 11, 'BorderType', 'line', ...
                'BorderColor', [0.30 0.30 0.34]);
            this.HistoryGrid = uigridlayout(rightPanel, [1, 1]);
            this.HistoryGrid.RowHeight = {'fit'};
            this.HistoryGrid.ColumnWidth = {'1x'};
            this.HistoryGrid.Padding = [6 6 6 6];
            this.HistoryGrid.RowSpacing = 4;
            this.HistoryGrid.BackgroundColor = this.BgColor;
            this.HistoryGrid.Scrollable = 'on';

            this.HistoryRows = {};
            this.HistoryCount = 0;
        end

        function renderSampleInPopup(this, payload)
            sample = payload.Sample;
            detection = payload.Detection;
            cellInfo = payload.CellInfo;

            if isempty(sample) || ~isfield(sample, 'stftImage'), return; end

            rawImg = this.toRgb8(sample.stftImage);
            overlayImg = this.drawOverlay(rawImg, detection);

            % 大图
            if isvalid(this.SampleAxesRaw)
                cla(this.SampleAxesRaw);
                image(this.SampleAxesRaw, rawImg);
                axis(this.SampleAxesRaw, 'image', 'off');
                this.SampleAxesRaw.YDir = 'reverse';
            end
            if isvalid(this.SampleAxesPred)
                cla(this.SampleAxesPred);
                image(this.SampleAxesPred, overlayImg);
                axis(this.SampleAxesPred, 'image', 'off');
                this.SampleAxesPred.YDir = 'reverse';
            end

            snrMeas = NaN;
            if isstruct(sample) && isfield(sample, 'meta') && ...
                    isfield(sample.meta, 'snr_meas_burst_dB')
                snrMeas = sample.meta.snr_meas_burst_dB;
            end
            this.SampleTitleLabel.Text = sprintf( ...
                '#%d / %d  ·  %s sat=%d ch=%d  ·  SNR设=%.1f dB / 实测=%.1f dB  ·  Doppler=%+.0f kHz', ...
                payload.Processed, payload.TotalCells, ...
                upper(string(cellInfo.constellation)), cellInfo.satIdx, cellInfo.channelIndex, ...
                cellInfo.snr_dB, snrMeas, cellInfo.doppler_Hz / 1e3);

            % 历史滚动条目
            this.appendHistoryRow(rawImg, overlayImg, payload);
        end

        function appendHistoryRow(this, rawImg, overlayImg, payload)
            if isempty(this.HistoryGrid) || ~isvalid(this.HistoryGrid), return; end

            % 容量管理: 超过则删最旧的
            while numel(this.HistoryRows) >= this.HistoryCapacity
                old = this.HistoryRows{end};
                if isfield(old, 'panel') && isvalid(old.panel)
                    delete(old.panel);
                end
                this.HistoryRows(end) = [];
            end

            this.HistoryCount = this.HistoryCount + 1;

            % 把现有行往下挪 (新行插在第 1 行)
            for k = 1:numel(this.HistoryRows)
                this.HistoryRows{k}.panel.Layout.Row = k + 1;
            end
            this.HistoryGrid.RowHeight = repmat({110}, 1, numel(this.HistoryRows) + 1);

            cellInfo = payload.CellInfo;
            sample = payload.Sample;
            agg = twin.app.Session2TestFlowPanel.aggregateDetection(payload.Detection, cellInfo.constellation);
            isCorrect = strcmpi(agg.predLabel, cellInfo.constellation);

            snrMeas = NaN;
            if isstruct(sample) && isfield(sample, 'meta') && isfield(sample.meta, 'snr_meas_burst_dB')
                snrMeas = sample.meta.snr_meas_burst_dB;
            end

            rowPanel = uipanel(this.HistoryGrid, ...
                'BackgroundColor', [0.10 0.10 0.12], ...
                'BorderType', 'line', ...
                'BorderColor', this.iif(isCorrect, [0.20 0.55 0.30], [0.55 0.20 0.20]));
            rowPanel.Layout.Row = 1;
            rowPanel.Layout.Column = 1;

            rowGrid = uigridlayout(rowPanel, [1, 3]);
            rowGrid.ColumnWidth = {110, 110, '1x'};
            rowGrid.ColumnSpacing = 6;
            rowGrid.Padding = [4 4 4 4];
            rowGrid.BackgroundColor = [0.10 0.10 0.12];

            axR = uiaxes(rowGrid);
            this.setupImageAxes(axR);
            image(axR, rawImg); axis(axR, 'image', 'off'); axR.YDir = 'reverse';

            axP = uiaxes(rowGrid);
            this.setupImageAxes(axP);
            image(axP, overlayImg); axis(axP, 'image', 'off'); axP.YDir = 'reverse';

            metaText = sprintf([ ...
                '#%d/%d   %s sat=%d ch=%d\n' ...
                'SNR 设=%.1f / 实测=%.1f dB    Doppler=%+.0f kHz\n' ...
                '预测: %s   置信度: %.0f%%   %s'], ...
                payload.Processed, payload.TotalCells, ...
                upper(string(cellInfo.constellation)), cellInfo.satIdx, cellInfo.channelIndex, ...
                cellInfo.snr_dB, snrMeas, cellInfo.doppler_Hz / 1e3, ...
                agg.predLabel, agg.topScore * 100, ...
                this.iif(isCorrect, '✓ 正确', '✗ 错误'));

            uilabel(rowGrid, ...
                'Text', metaText, ...
                'FontSize', 10, ...
                'FontColor', this.iif(isCorrect, [0.75 0.95 0.80], [0.95 0.75 0.75]), ...
                'BackgroundColor', [0.10 0.10 0.12], ...
                'VerticalAlignment', 'center');

            entry = struct('panel', rowPanel);
            this.HistoryRows = [{entry}, this.HistoryRows];
        end

        function renderConfusionInPopup(this, snap)
            if isempty(snap) || ~isfield(snap, 'confusionMatrix')
                return;
            end
            if isempty(this.ConfusionAxesPopup) || ~isvalid(this.ConfusionAxesPopup)
                return;
            end
            this.drawConfusion(this.ConfusionAxesPopup, snap.confusionMatrix);
        end
    end

    % ============================================================
    %   底部 2 列曲线
    % ============================================================
    methods (Access = private)
        function refreshAxesXLimits(this)
            if isempty(this.Plan), return; end
            xlim(this.AccSnrAxes, ...
                [this.Plan.SNRGrid_dB(1) - 1, this.Plan.SNRGrid_dB(end) + 1]);
            % 多普勒 X 轴: 取两星座中较大的范围
            dStarMax = this.Plan.DopplerMax_Hz.starlink;
            dOneMax  = this.Plan.DopplerMax_Hz.oneweb;
            xMaxKHz = max(dStarMax, dOneMax) / 1e3 * 1.05;
            xlim(this.AccDopAxes, [-xMaxKHz, xMaxKHz]);
        end

        function renderQuickCurves(~)
            % 占位：进度中曲线由 onMetricsFinalized 统一画
        end

        function renderFinalCurves(this, metrics)
            % 准确率 vs SNR (每个 SNR 点 = 1 个圆点, 折线相连)
            cla(this.AccSnrAxes); hold(this.AccSnrAxes, 'on');
            anyPlotted = false;
            anyPlotted = this.plotMetricCurve(this.AccSnrAxes, metrics.snrGrid_dB, ...
                metrics.snr.starlink, this.StarlinkColor, 'Starlink') | anyPlotted;
            anyPlotted = this.plotMetricCurve(this.AccSnrAxes, metrics.snrGrid_dB, ...
                metrics.snr.oneweb, this.OnewebColor, 'OneWeb') | anyPlotted;
            yline(this.AccSnrAxes, 90, '--', '90%', ...
                'Color', [0.5 0.5 0.5], 'LineWidth', 1.0, ...
                'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
            if anyPlotted
                legend(this.AccSnrAxes, 'Location', 'southeast', ...
                    'TextColor', this.TextColor, 'Color', [0.10 0.10 0.12]);
            end
            ylim(this.AccSnrAxes, [0, 102]);
            hold(this.AccSnrAxes, 'off');

            % 准确率 vs 多普勒 (每个 Doppler 点 = 1 个圆点, 折线相连)
            cla(this.AccDopAxes); hold(this.AccDopAxes, 'on');
            anyPlotted = false;
            anyPlotted = this.plotMetricCurve(this.AccDopAxes, ...
                metrics.dopplerGrid_Hz.starlink / 1e3, ...
                metrics.doppler.starlink, this.StarlinkColor, 'Starlink') | anyPlotted;
            anyPlotted = this.plotMetricCurve(this.AccDopAxes, ...
                metrics.dopplerGrid_Hz.oneweb / 1e3, ...
                metrics.doppler.oneweb, this.OnewebColor, 'OneWeb') | anyPlotted;
            yline(this.AccDopAxes, 90, '--', '90%', ...
                'Color', [0.5 0.5 0.5], 'LineWidth', 1.0, ...
                'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
            if anyPlotted
                legend(this.AccDopAxes, 'Location', 'southeast', ...
                    'TextColor', this.TextColor, 'Color', [0.10 0.10 0.12]);
            end
            ylim(this.AccDopAxes, [0, 102]);
            hold(this.AccDopAxes, 'off');
        end

        function renderFinalSummary(this, metrics, paths)
            try
                fprintf('[Session2 Result] 报告位置: %s\n', paths.outputDir);
            catch
            end
            if isfield(metrics, 'summary') && isfield(metrics.summary, 'overall')
                this.StatOverallLabel.Text = sprintf('总体准确率: %.2f%%', ...
                    metrics.summary.overall.accuracy_pct);
            end
            if isfield(metrics, 'summary') && isfield(metrics.summary, 'starlink')
                this.StatStarlinkLabel.Text = sprintf('Starlink: %.2f%% (%d)', ...
                    metrics.summary.starlink.accuracy_pct, ...
                    metrics.summary.starlink.total);
            end
            if isfield(metrics, 'summary') && isfield(metrics.summary, 'oneweb')
                this.StatOnewebLabel.Text = sprintf('OneWeb: %.2f%% (%d)', ...
                    metrics.summary.oneweb.accuracy_pct, ...
                    metrics.summary.oneweb.total);
            end
        end
    end

    % ============================================================
    %   元数据 & 工具方法
    % ============================================================
    methods (Access = private)
        function renderMeta(this, cellInfo, sample, detection)
            this.MetaLabels.constellation.Text = sprintf('星座: %s', cellInfo.constellation);
            this.MetaLabels.satIdx.Text        = sprintf('卫星: #%d', cellInfo.satIdx);
            this.MetaLabels.channel.Text       = sprintf('信道: %d', cellInfo.channelIndex);
            this.MetaLabels.snrSet.Text        = sprintf('SNR(设): %.1f dB', cellInfo.snr_dB);

            if isstruct(sample) && isfield(sample, 'meta')
                if isfield(sample.meta, 'snr_meas_burst_dB')
                    snrMeas = sample.meta.snr_meas_burst_dB;
                    this.MetaLabels.snrMeas.Text = sprintf('SNR(实测): %.1f dB', snrMeas);
                else
                    this.MetaLabels.snrMeas.Text = 'SNR(实测): N/A';
                end
                if isfield(sample.meta, 'noiseFloor_dB') && isfinite(sample.meta.noiseFloor_dB)
                    this.MetaLabels.noiseFloor.Text = sprintf('噪底: %.1f dBW', sample.meta.noiseFloor_dB);
                else
                    this.MetaLabels.noiseFloor.Text = '噪底: N/A';
                end
            else
                this.MetaLabels.snrMeas.Text = 'SNR(实测): N/A';
                this.MetaLabels.noiseFloor.Text = '噪底: N/A';
            end

            this.MetaLabels.doppler.Text = sprintf('Doppler: %+.0f kHz', cellInfo.doppler_Hz / 1e3);

            agg = twin.app.Session2TestFlowPanel.aggregateDetection(detection, cellInfo.constellation);
            this.MetaLabels.pred.Text  = sprintf('预测: %s', agg.predLabel);
            this.MetaLabels.score.Text = sprintf('置信度: %.0f%%', agg.topScore * 100);
        end

        function renderSnapshot(this, snap)
            if isempty(snap), return; end
            this.StatStarlinkLabel.Text = sprintf('Starlink: %.1f%% (%d/%d)', ...
                snap.starlink.accuracy, snap.starlink.correct, snap.starlink.total);
            this.StatOnewebLabel.Text = sprintf('OneWeb: %.1f%% (%d/%d)', ...
                snap.oneweb.accuracy, snap.oneweb.correct, snap.oneweb.total);
            this.StatOverallLabel.Text = sprintf('总体准确率: %.1f%%', snap.overall.accuracy);
        end

        function plotted = plotMetricCurve(~, ax, xVals, dataStruct, color, name)
            % 简洁: 圆点 + 折线, 不画 CI 竖线 (CI 仍保留在导出 mat/csv)
            % 数据全 NaN (该星座未采集) 时跳过, 避免出现伪坐标轴标记
            plotted = false;
            if isempty(dataStruct), return; end
            acc = dataStruct.accuracy_pct;
            xVals = xVals(:)';  acc = acc(:)';
            valid = ~isnan(acc);
            if ~any(valid), return; end
            plot(ax, xVals(valid), acc(valid), 'o-', ...
                'Color', color, 'MarkerFaceColor', color, ...
                'LineWidth', 1.8, 'MarkerSize', 7, ...
                'DisplayName', name);
            plotted = true;
        end

        function setupImageAxes(~, ax)
            ax.Visible = 'off';
            ax.XTick = [];
            ax.YTick = [];
            ax.XColor = 'none';
            ax.YColor = 'none';
            ax.Color = [0.05 0.05 0.07];
            ax.Box = 'off';
            ax.Position = [0 0 1 1];
            axis(ax, 'off');
        end

        function img8 = toRgb8(~, img)
            if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
            if ~isa(img, 'uint8')
                if max(img(:)) <= 1, img = uint8(img * 255);
                else, img = uint8(img); end
            end
            img8 = img;
        end

        function overlay = drawOverlay(~, rawImg, detection)
            overlay = rawImg;
            if ~isfield(detection, 'bboxes') || isempty(detection.bboxes), return; end
            try
                overlay = insertShape(overlay, 'Rectangle', detection.bboxes, ...
                    'LineWidth', 2, 'Color', 'red');
                if isfield(detection, 'labels') && ~isempty(detection.labels)
                    labels = detection.labels;
                    if iscategorical(labels), labels = cellstr(labels); end
                    if isstring(labels), labels = cellstr(labels); end
                    if ischar(labels), labels = {labels}; end
                    scores = [];
                    if isfield(detection, 'scores'), scores = detection.scores(:)'; end
                    if numel(scores) < numel(labels), scores(end+1:numel(labels)) = 0; end
                    for k = 1:size(detection.bboxes, 1)
                        bb = detection.bboxes(k, :);
                        txt = char(labels{min(k, numel(labels))});
                        txt = regexprep(txt, '(?i)starlink', '星链终端');
                        txt = regexprep(txt, '(?i)oneweb',   '一网终端');
                        txt = sprintf('%s (%.0f%%)', txt, scores(k) * 100);
                        try
                            overlay = insertText(overlay, ...
                                [bb(1), max(1, bb(2) - 5)], txt, ...
                                'FontSize', 18, ...
                                'TextColor', 'white', 'BoxColor', 'red', ...
                                'BoxOpacity', 0.8, ...
                                'AnchorPoint', 'LeftBottom', ...
                                'Font', 'SimHei');
                        catch
                            overlay = insertText(overlay, ...
                                [bb(1), max(1, bb(2) - 5)], txt, ...
                                'FontSize', 18, ...
                                'TextColor', 'white', 'BoxColor', 'red', ...
                                'BoxOpacity', 0.8, ...
                                'AnchorPoint', 'LeftBottom');
                        end
                    end
                end
            catch
            end
        end

        function drawConfusion(this, ax, cm)
            if isempty(cm) || all(cm(:) == 0)
                cla(ax);
                text(ax, 0.5, 0.5, '等待数据', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.4 0.4 0.4], 'FontSize', 14);
                return;
            end

            cmPct = zeros(size(cm));
            for r = 1:size(cm, 1)
                rs = sum(cm(r, :));
                if rs > 0
                    cmPct(r, :) = cm(r, :) / rs * 100;
                end
            end

            cla(ax);
            imagesc(ax, cmPct);
            colormap(ax, parula);
            try, caxis(ax, [0, 100]); catch, end
            ax.XTick = 1:size(cm, 2);
            ax.YTick = 1:size(cm, 1);
            ax.XTickLabel = {'Starlink', 'OneWeb', '漏检/多检'};
            ax.YTickLabel = {'Starlink', 'OneWeb'};
            xlabel(ax, '预测类别', 'Color', this.TextColor);
            ylabel(ax, '真实类别', 'Color', this.TextColor);

            for r = 1:size(cm, 1)
                for c = 1:size(cm, 2)
                    txt = sprintf('%d\n(%.1f%%)', cm(r, c), cmPct(r, c));
                    if cmPct(r, c) > 50, col = [0 0 0]; else, col = [1 1 1]; end
                    text(ax, c, r, txt, ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'middle', ...
                        'Color', col, 'FontSize', 10, 'FontWeight', 'bold');
                end
            end
            axis(ax, 'image');
            ax.Box = 'on';
        end

        function out = iif(~, cond, a, b)
            if cond, out = a; else, out = b; end
        end
    end
end
