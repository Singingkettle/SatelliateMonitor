function receiverCfg = receiver(options, spectrumConfig)
    % RECEIVER 解析接收机配置 (dataGen.config.receiver)
    %
    %   receiverCfg = dataGen.config.receiver(options, spectrumConfig)
    %
    % 功能：
    %   根据选项和配置生成接收机参数，支持多种配置模式：
    %   - monitor: 监测卫星（默认）
    %   - jamming: 干扰评估
    %   - cooperative: 协作接收
    %
    % 此函数可被数据生成和数字孪生共用

    profile = 'monitor';

    if isfield(options, 'receiverProfile') && ~isempty(options.receiverProfile)
        profile = lower(string(options.receiverProfile));
    end

    receiverCfg = struct();
    receiverCfg.profile = char(profile);

    monitorCfg = spectrumConfig.broadband.receiver;

    switch receiverCfg.profile
        case {'cooperative', 'jamming', 'satcom'}
            customCfg = struct();

            if isfield(options, 'receiverConfig') && ~isempty(options.receiverConfig)
                customCfg = options.receiverConfig;
            end

            receiverCfg.rxGain = getFieldOr(customCfg, 'rxGain', monitorCfg.gain14p5GHz);
            receiverCfg.GT = getFieldOr(customCfg, 'gt', monitorCfg.GT);
            receiverCfg.noiseTemp = getFieldOr(customCfg, 'noiseTemp', monitorCfg.systemNoiseTemp);
            receiverCfg.polarization = getFieldOr(customCfg, 'polarization', monitorCfg.polarization);
            receiverCfg.observationBandwidth = getFieldOr(customCfg, 'observationBandwidth', []);
            receiverCfg.injectThermalNoise = getFieldOr(customCfg, 'injectThermalNoise', true);
            receiverCfg.enableRFFingerprint = getFieldOr(customCfg, 'enableRFFingerprint', false);
            receiverCfg.enableDoppler = getFieldOr(customCfg, 'enableDoppler', true);

        otherwise
            % 默认监测模式
            receiverCfg.rxGain = monitorCfg.gain14p5GHz;
            receiverCfg.GT = monitorCfg.GT;
            receiverCfg.noiseTemp = getFieldOr(monitorCfg, 'systemNoiseTemp', 300);
            receiverCfg.polarization = monitorCfg.polarization;
            receiverCfg.observationBandwidth = spectrumConfig.broadband.sampling.bandwidth;
            receiverCfg.injectThermalNoise = false;
            receiverCfg.enableRFFingerprint = true;
            receiverCfg.pointingLossApplied = 0;
            % 伴飞模式：可选的“离轴接收”损耗建模（主要影响发射端主瓣外泄）
            if isfield(spectrumConfig, 'broadband') && isfield(spectrumConfig.broadband, 'companion')
                companionCfg = spectrumConfig.broadband.companion;
                receiverCfg.enableOffBoresightLoss = getFieldOr(companionCfg, 'enableOffBoresightLoss', true);
                receiverCfg.offBoresightLossMethod = getFieldOr(companionCfg, 'offBoresightLossMethod', 'auto');
                receiverCfg.manualOffBoresightLoss = getFieldOr(companionCfg, 'manualOffBoresightLoss', 0.0);
                
                % 旁瓣接收配置
                receiverCfg.enableSidelobeReception = getFieldOr(companionCfg, 'enableSidelobeReception', true);
                receiverCfg.sidelobeProbability = getFieldOr(companionCfg, 'sidelobeProbability', 0.15);
                receiverCfg.antennaPatternModel = getFieldOr(companionCfg, 'antennaPatternModel', 'itu_s1528');
            else
                receiverCfg.enableOffBoresightLoss = true;
                receiverCfg.offBoresightLossMethod = 'auto';
                receiverCfg.manualOffBoresightLoss = 0.0;
                receiverCfg.enableSidelobeReception = true;
                receiverCfg.sidelobeProbability = 0.15;
                receiverCfg.antennaPatternModel = 'itu_s1528';
            end

            % 指向损耗随机化
            if isfield(monitorCfg, 'pointingLossRange_dB') && numel(monitorCfg.pointingLossRange_dB) == 2
                lossRange = monitorCfg.pointingLossRange_dB;

                if lossRange(2) > 0
                    pointingLoss = lossRange(1) + rand() * (lossRange(2) - lossRange(1));
                    receiverCfg.rxGain = receiverCfg.rxGain - pointingLoss;

                    if isfield(receiverCfg, 'GT') && ~isempty(receiverCfg.GT)
                        receiverCfg.GT = receiverCfg.GT - pointingLoss;
                    end

                    receiverCfg.pointingLossApplied = pointingLoss;
                end
            end
    end
end

function value = getFieldOr(structure, fieldName, defaultValue)
    if isstruct(structure) && isfield(structure, fieldName) && ~isempty(structure.(fieldName))
        value = structure.(fieldName);
    else
        value = defaultValue;
    end
end

