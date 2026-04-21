function params = getStarlinkPhyParams()
    % GETSTARLINKPHYPARAMS Starlink物理层参数
    %
    % 参考文献 (References):
    % [1] US Patent US12003350B1, "Configurable OFDM signal for satellite communications", SpaceX.
    %     - 支持: UW序列结构(128x8), OFDM波形, 导频插入逻辑
    % [2] FCC Filing SAT-LOA-20161115-00118, "Technical Attachment", SpaceX.
    %     - 支持: 频段(14.0-14.5 GHz), 卫星G/T, 极化方式
    % [3] FCC Filing SAT-MOD-20200417-00037, "Technical Attachment", SpaceX (Gen2).
    %     - 支持: 波束特性, 仰角限制
    % [4] FCC OET Authorization for UT (e.g., A4R-UTR-201), Test Reports.
    %     - 支持: 终端发射功率, EIRP限值, 占用带宽(60 MHz)
    % [5] ETSI TR 103 611 V1.1.1, "Satellite IMT systems".
    %     - 支持: 一般Ku波段卫星信道模型参数推断
    %
    % 注意: 部分参数(如具体导频间隔、保护带比例)属于私有协议细节，
    %       此处基于通用OFDM工程实践和仿真需求进行合理推断(Engineering Deduction)。

    params = struct();
    params.constellation = 'starlink';

    % === 频率和带宽 ===
    % [Source: FCC SAT-LOA-20161115-00118, Table A.1]
    params.frequency = 14.25e9; % Ku波段上行中心频率 (Hz)
    params.frequencyRange = [14.0e9, 14.5e9]; % 上行频段 14.0-14.5 GHz

    % === 信道化参数 (Unified Structure) ===
    % [Engineering Deduction based on 500 MHz allocation]
    params.channelization = struct();
    params.channelization.startFreq = 14.0e9;

    params.channelization.modes = struct();

    % Mode 1: 60MHz (Standard)
    % 8 Channels @ 62.5 MHz Spacing
    m60 = struct();
    m60.numChannels = 8;
    m60.channelSpacing = 62.5e6;
    m60.nominalBandwidth = 62.5e6;
    m60.bandwidth = 60e6;
    m60.sampleRate = 67.5e6;
    m60.cpLength = 144;
    m60.pilotSpacing = 12;
    params.channelization.modes.mode_60MHz = m60;

    % Mode 2: 240MHz (Gen2/High Throughput)
    % 2 Channels @ 250 MHz Spacing
    m240 = struct();
    m240.numChannels = 2;
    m240.channelSpacing = 250e6;
    m240.nominalBandwidth = 250e6;
    m240.bandwidth = 240e6;
    m240.sampleRate = 270e6;
    m240.cpLength = 576;
    m240.pilotSpacing = 3;
    params.channelization.modes.mode_240MHz = m240;

    params.channelization.supportedModes = {'mode_60MHz', 'mode_240MHz'};

    % === 用户终端 (UT) 参数 ===
    params.ut = struct();

    % DPD 参数 [Simulation Assumption]
    % 实际硬件会有非线性，仿真中假设典型PA模型系数
    params.ut.dpdCoeffs = [1, 0.1, 0.05];

    % 天线参数
    % [Source: FCC Filing SAT-MOD-20200417-00037]
    % 描述为相控阵(Phased Array)，电扫波束
    params.ut.antennaType = 'phased_array';
    % [Simulation Assumption] 阵列规模基于物理尺寸(~0.5m)和波长(~2cm)推断
    params.ut.arraySize = [40, 32];
    params.ut.numElements = 1280;
    params.ut.elementSpacing = 0.5; % lambda
    params.ut.dishDiameter = 0.48; % [Source: Public Teardowns / Specs] ~19 inches

    % 功率参数
    % [Source: SpaceX Services Inc., FCC File No. SES-LIC-20190211-00216, Technical Attachment Table 2]
    % Consumer UT maximum EIRP ≈ 51 dBW.
    % 注：申报中常给出 EIRP density（例如 dBW/4 kHz），不要写成 dBW/MHz，否则与 51 dBW 总EIRP不一致。
    params.ut.maxTxPower_W = 25.1; % ≈44 dBm conducted (per FCC exhibit HP ESIM)
    params.ut.maxTxPower_dBm = 10 * log10(params.ut.maxTxPower_W * 1000);
    params.ut.maxEIRP = 51.0; % dBW (per FCC attachment)
    params.ut.gainBoresight = params.ut.maxEIRP - (params.ut.maxTxPower_dBm - 30); % ≈37 dBi
    params.ut.gainMaxSlant = 32.2; % Scan loss assumption
    params.ut.beamwidth3dB = 2.5; % [Correction] 0.5m array at 14GHz -> ~2.5 deg beam, not 25
    params.ut.maxGain = 37.2;

    % 极化
    % [Source: FCC Filings]
    % Starlink uses circular polarization (LHCP/RHCP switching)
    params.ut.polarization = 'LHCP';
    
    % 旁瓣特性参数 [Source: ITU-R S.1528, phased array theory]
    % Starlink UT 使用相控阵，典型采用泰勒加权降低旁瓣
    params.ut.sidelobe.peakLevel_dB = -20;  % 第一旁瓣电平相对于峰值 (dB)
    params.ut.sidelobe.envelopeDecay = 25;  % 旁瓣包络衰减斜率 (dB/decade)
    params.ut.sidelobe.farSidelobeLevel_dB = -35;  % 远旁瓣电平 (θ > 20°)
    params.ut.sidelobe.backlobeLevel_dB = -45;  % 背瓣电平 (θ > 90°)
    params.ut.sidelobe.firstNullFactor = 1.22;  % 第一零点角度 ≈ factor * HPBW

    % === 卫星参数 ===
    params.sat = struct();

    % 天线参数
    params.sat.antennaType = 'phased_array';
    params.sat.gainRange = [34, 44]; % dBi
    % [Source: FCC SAT-LOA-20161115-00118, Table A.1]
    % Satellite G/T (Peak) = 17.7 to 22.7 dB/K depending on beam
    params.sat.GTRange = [17.7, 22.7]; % dB/K
    params.sat.antennaGain = 39.0; % Peak receive gain (dBi)
    params.sat.GT = 22.7; % Peak receive G/T (dB/K)
    params.sat.systemTemp = 290; % K
    params.sat.noiseFigure = 1.5; % dB
    params.sat.polarization = 'LHCP';
    params.sat.preferredEbNo = 4.5; % dB
    params.sat.notes = 'Derived from FCC SAT-LOA-20161115-00118 Technical Attachment Table A.1.';
    params.sat.defaultGain = params.sat.antennaGain;
    params.sat.defaultGT = params.sat.GT;
    params.sat.dishDiameter = 1.0; % Effective aperture assumption

    % AGC 参数 [Simulation Logic]
    params.sat.agcTargetLevel = 1.0;

    % === 波形参数 ===
    % [Source: US Patent US12003350B1]
    % Patent describes "Configurable OFDM" with specific UW structures.
    params.waveform = struct();
    params.waveform.type = 'OFDM';

    % [Engineering Deduction: Sampling Rate & FFT]
    % Requirement: 60 MHz Occupied bandwidth.
    % Standard Oversampling: 1.125x (9/8) for anti-aliasing.
    % Sample Rate = 60 * 1.125 = 67.5 MHz.
    % Subcarrier Spacing = 60 MHz / 1024 symbols = 58.59375 kHz.
    % FFT Size = 67.5 MHz / 58.59375 kHz = 1152.
    params.waveform.nfft = 1152;
    params.waveform.nSubcarriers = 1024; % [Source: US12003350B1 implies 1024 symbol blocks]

    % CP Length [Simulation Assumption]
    % 1/8 of FFT is common in LTE/WiFi. 1152 / 8 = 144.
    params.waveform.cpLength = 144;
    params.waveform.cpLength_240MHz = 576; % Scale by 4 for 240MHz mode to maintain duration
    params.waveform.csLength = 0;

    params.waveform.sampleRate_60MHz = 67.5e6;
    params.waveform.sampleRate_240MHz = 270e6;

    % Payload bits 范围 (基于 DVB-S2 LDPC 标准 ETSI EN 302 307)
    % Short frame: 16200 bits, 信息比特 K 范围 3072-14472 (不同码率)
    % Normal frame: 64800 bits, 信息比特 K 范围 16008-58192
    % 60MHz 模式使用 short frame 范围，240MHz 使用扩展范围
    params.waveform.payloadBitsRange = struct( ...
        'mode_60MHz', [4000, 14000], ...   % Short frame: ~QPSK 1/2 到 64QAM 5/6
        'mode_240MHz', [16000, 54000], ... % Normal frame: ~QPSK 1/2 到 64QAM 5/6
        'default', [4000, 12000]);

    % 导频参数 [Simulation Assumption]
    % Typical pilot density for mobile channels is 1/12 (LTE).
    % For 240MHz mode, subcarrier spacing is 4x larger (234kHz), so coherence bandwidth covers fewer subcarriers.
    % We need denser pilots in subcarrier index domain to maintain frequency tracking.
    params.waveform.pilotSpacing = 12; % Default/Legacy
    params.waveform.pilotSpacing_60MHz = 12;
    params.waveform.pilotSpacing_240MHz = 3; % 12 / 4 = 3
    params.waveform.pilotType = 'BPSK';

    % 同步参数
    % [Source: US Patent US12003350B1]
    % "The UW symbol can be... 128 sample BPSK... repeated eight times within a length of 1024 symbols."
    params.waveform.uwLength = 1152; % Physical length (after upsampling 1024->1152)
    params.waveform.uwNominalLength = 1024; % Logical length (symbols)
    params.waveform.uwBaseLength = 128; % Base sequence length
    params.waveform.uwPoly = [7 4 3 2 0]; % PN8 [Simulation Assumption for specific poly]
    params.waveform.uwInit = [1 0 0 0 0 0 1];

    params.waveform.ceLength = 1152;
    % 信道估计（CE）符号配置，使用确定性的QPSK PN序列，便于接收端重构并估计全局相位
    params.waveform.ce = struct();
    params.waveform.ce.poly = [10 3 0];
    params.waveform.ce.init = [1 zeros(1, 9)];
    params.waveform.ce.modOrder = 4; % QPSK
    params.waveform.syncThresholdMultiplier = 3;
    params.waveform.fallbackSyncThresholdMultiplier = 2;

    % === 编码参数 ===
    params.coding = struct();
    params.coding.type = 'LDPC';
    % [Source: ETSI TR 103 611 / Industry Standard]
    % DVB-S2/S2X is the de facto standard for satellite broadband.
    params.coding.standard = 'DVB-S2';
    params.coding.supportedRates = [1/2, 2/3, 5/6];

    % 扰码参数 [Simulation Assumption]
    params.coding.scramblerPoly = [1 zeros(1, 13) 1 1];
    params.coding.scramblerInit = [1 0 1 0 1 0 1 0 1 0 1 0 1 0 1];

    % 交织参数
    params.coding.interleaverType = 'block';

    % === MCS 参数表 ===
    % [Simulation Assumption based on DVB-S2X spectral efficiencies]
    %     MCS | 调制阶数 | 码率 | 所需Eb/N0(dB) | 频谱效率
    params.mcsTable = [
                       1, 2, 1/2, 2.0, 0.5; % BPSK 1/2
                       2, 2, 2/3, 3.5, 0.67; % BPSK 2/3
                       3, 4, 1/2, 5.0, 1.0; % QPSK 1/2
                       4, 4, 2/3, 6.5, 1.33; % QPSK 2/3
                       5, 16, 1/2, 9.0, 2.0; % 16QAM 1/2
                       6, 16, 2/3, 11.0, 2.67; % 16QAM 2/3
                       7, 64, 2/3, 15.0, 4.0; % 64QAM 2/3
                       8, 64, 5/6, 18.0, 5.0; % 64QAM 5/6
                       ];

    %% ========== 发射机默认配置 ==========
    params.defaultTxConfig = struct();
    params.defaultTxConfig.mcs = 3; % QPSK, 1/2码率
    params.defaultTxConfig.channelIndex = 1;
    params.defaultTxConfig.txPower = params.ut.maxTxPower_dBm;
    params.defaultTxConfig.beamAngle = [0, 45];
    params.defaultTxConfig.enableCFR = false;
    params.defaultTxConfig.enableDPD = false;
    params.defaultTxConfig.pilotPowerBoost = 0;
    params.defaultTxConfig.verbose = true;
    params.defaultTxConfig.enableRotation = true;

    % CFR参数
    params.cfrThreshold_dB = 3.5;

    %% ========== 数据生成相关配置 ==========
    params.channelIndexRange = [1, 8];

    params.serviceCoverage = struct();
    params.serviceCoverage.latitudeRange = 70;
    params.serviceCoverage.longitudeRange = 360;
    params.serviceCoverage.altitudeRange = [0, 500];

    %% ========== 神经接收机推荐参数 ==========
    % Deprecated: neuralRx struct has been removed. Parameters moved to spectrumMonitorConfig.m

end
