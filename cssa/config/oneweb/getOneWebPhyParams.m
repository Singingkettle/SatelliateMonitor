function params = getOneWebPhyParams()
    % GETONEWEBPHYPARAMS OneWeb物理层参数
    %
    % 参考文献 (References):
    % [1] FCC IBFS File No. SAT-LOI-20160428-00041, "Technical Narrative", WorldVu Satellites Limited (OneWeb).
    %     - 支持: 轨道参数(1200km, 87.9°), 频段(Ku/Ka), 波束覆盖
    % [2] ETSI TR 103 611 V1.1.1 (2018-09), "Satellite Earth Stations and Systems (SES); Satellite IMT systems".
    %     - 支持: SC-FDMA波形参数, 20 MHz载波带宽, 1200子载波
    % [3] R&S Application Card, "Generate OneWeb-Compliant Signals for Receiver Tests".
    %     - 支持: SC-FDMA, 20 MHz带宽, QPSK/16QAM/64QAM
    % [4] "OneWeb System Overview", ITU Filing USASAT-NGSO-3.
    %     - 支持: 卫星G/T, EIRP限值
    % [5] "OneWeb User Terminal Specifications", various public technical analyses.
    %     - 支持: 终端天线类型, 频段范围
    %
    % 注意: 部分参数(如具体导频图样、私有协议头)属于非公开细节，
    %       此处基于LTE SC-FDMA标准和通用卫星通信工程实践进行合理推断(Engineering Deduction)。

    params = struct();
    params.constellation = 'oneweb';

    % === 频率和带宽 ===
    % [Source: FCC SAT-LOI-20160428-00041]
    % User Uplink: 14.0-14.5 GHz (Ku-band)
    params.frequency = 14.25e9; % Ku波段上行中心频率 (Hz)
    params.frequencyRange = [14.0e9, 14.5e9];

    % [Source: ETSI TR 103 611 / R&S App Card]
    % OneWeb uplink uses SC-FDMA with 20 MHz carrier bandwidth.

    % === 信道化参数 ===
    % [Engineering Deduction]
    % 500 MHz uplink spectrum (14.0-14.5 GHz) divided by 20 MHz carriers.
    % Assuming some guard band, ~24 channels possible, but often channelized in 50 MHz blocks.
    % Here we assume a 50 MHz channel spacing grid for simulation.
    params.channelization = struct();
    params.channelization.startFreq = 14.0e9;

    params.channelization.modes = struct();

    % Mode 1: 20MHz (Standard)
    m20 = struct();
    m20.numChannels = 10; % 500 MHz / 50 MHz = 10 channels
    m20.channelSpacing = 50e6; % 50 MHz spacing
    m20.nominalBandwidth = 20e6;
    m20.bandwidth = 20e6; % 载波带宽 (Hz)
    m20.sampleRate = 30.72e6;
    m20.cpLength = 160;

    params.channelization.modes.mode_20MHz = m20;
    params.channelization.supportedModes = {'mode_20MHz'};

    % === 用户终端 (UT) 参数 ===
    params.ut = struct();

    % DPD 参数 [Simulation Assumption]
    params.ut.dpdCoeffs = [1, 0.08, 0.02];

    % 天线参数
    % [Source: OneWeb Technical Narrative]
    % UT uses Phased Array antennas for beam steering.
    params.ut.antennaType = 'phased_array';
    % [Simulation Assumption] Size estimated from commercial UT specs (~30-50cm)
    params.ut.arraySize = [32, 32];
    params.ut.numElements = 1024;
    params.ut.elementSpacing = 0.5;
    params.ut.dishDiameter = 0.36; % ~36cm effective aperture

    % 功率参数
    % [Source: OneWeb NGSO Filing, FCC File No. SAT-LOI-20160428-00041, Attachment A]
    % User terminal peak EIRP ≈ 42 dBW with 30-35 cm aperture.
    params.ut.maxTxPower_W = 10.0; % ≈40 dBm conducted
    params.ut.maxTxPower_dBm = 10 * log10(params.ut.maxTxPower_W * 1000);
    params.ut.maxEIRP = 42.0; % dBW
    params.ut.gainBoresight = params.ut.maxEIRP - (params.ut.maxTxPower_dBm - 30); % ≈32 dBi
    params.ut.gainMaxSlant = 28.0; % Scan loss assumption
    params.ut.beamwidth3dB = 3.5; % [Engineering Deduction] 0.36m @ 14GHz
    params.ut.maxGain = params.ut.gainBoresight;

    % 极化
    % [Source: FCC SAT-LOI-20160428-00041]
    % OneWeb uses RHCP for Uplink.
    params.ut.polarization = 'RHCP';

    % 旁瓣特性参数 [Source: ITU-R S.1528, phased array theory]
    % OneWeb UT 使用相控阵，假设中等加权
    params.ut.sidelobe.peakLevel_dB = -18;  % 第一旁瓣电平相对于峰值 (dB)
    params.ut.sidelobe.envelopeDecay = 25;  % 旁瓣包络衰减斜率 (dB/decade)
    params.ut.sidelobe.farSidelobeLevel_dB = -32;  % 远旁瓣电平 (θ > 20°)
    params.ut.sidelobe.backlobeLevel_dB = -42;  % 背瓣电平 (θ > 90°)
    params.ut.sidelobe.firstNullFactor = 1.22;  % 第一零点角度 ≈ factor * HPBW

    % === 卫星参数 ===
    params.sat = struct();

    % 天线参数
    % [Source: FCC SAT-LOI-20160428-00041]
    % 16 beams per satellite, 1080x1080km coverage.
    % Non-steerable "push-broom" beams (fixed relative to satellite body).
    params.sat.antennaType = 'phased_array'; % Modeled as array for gain pattern
    params.sat.gainRange = [30, 38]; % dBi
    % [Source: ITU Filing USASAT-NGSO-3]
    % G/T ~ 15-20 dB/K
    params.sat.GTRange = [15.0, 20.0]; % dB/K
    params.sat.antennaGain = 35.0; % Peak receive gain (dBi)
    params.sat.GT = 20.0; % Peak receive G/T (dB/K)
    params.sat.systemTemp = 350; % K
    params.sat.noiseFigure = 2.0; % dB
    params.sat.polarization = 'RHCP';
    params.sat.preferredEbNo = 5.0; % dB
    params.sat.notes = 'Derived from FCC SAT-LOI-20160428-00041 Technical Narrative Attachment A.';
    params.sat.defaultGain = params.sat.antennaGain;
    params.sat.defaultGT = params.sat.GT;
    params.sat.dishDiameter = 0.8; % Effective aperture
    
    % AGC 参数 [Simulation Logic]
    params.sat.agcTargetLevel = 1.0;

    % === 波形参数 (基于LTE SC-FDMA标准) ===
    % [Source: ETSI TR 103 611 / R&S Technical Docs]
    % OneWeb uplink is compliant with LTE SC-FDMA (DFT-s-OFDM).
    params.waveform = struct();
    params.waveform.type = 'SC-FDMA';
    params.waveform.nfft = 2048; % LTE 20 MHz standard
    params.waveform.nSubcarriers = 1200; % 1200 active subcarriers (18 MHz occupied)
    params.waveform.nRB = 100; % 100 Resource Blocks
    params.waveform.subcarrierSpacing = 15e3; % 15 kHz
    params.waveform.cpLength = 160; % Normal CP (first symbol)
    params.waveform.cpLengthOther = 144; % Normal CP (other symbols)
    params.waveform.symbolsPerSlot = 7;
    params.waveform.slotsPerSubframe = 2;
    params.waveform.subframeDuration = 1e-3; % 1 ms
    params.waveform.sampleRate = 30.72e6; % LTE 20 MHz standard sampling rate
    % Payload bits 范围 (基于 LTE SC-FDMA TBS 表, 3GPP TS 36.213)
    % 20MHz (100 PRB) 单子帧 TBS 范围: 2216 ~ 75376 bits
    % 考虑实际 burst 时长和多子帧聚合，取合理工作范围
    % 低 MCS (QPSK): ~2000-8000 bits
    % 中 MCS (16QAM): ~8000-25000 bits  
    % 高 MCS (64QAM): ~25000-50000 bits
    params.waveform.payloadBitsRange = struct('mode_20MHz', [2000, 25000]);

    % 导频参数 (LTE DMRS)
    % [Source: 3GPP TS 36.211]
    % SC-FDMA DMRS is Zadoff-Chu sequence.
    params.waveform.pilotType = 'DMRS';
    params.waveform.dmrsSymbolIndices = [4, 11]; % 0-based: 3, 10. 1-based: 4, 11.
    params.waveform.srsEnabled = true;
    params.waveform.dmrs = struct();
    params.waveform.dmrs.rootSequenceIndex = 1;
    params.waveform.dmrs.cyclicShift = 0;
    params.waveform.dmrs.groupHopping = false;
    params.waveform.dmrs.sequenceHopping = false;
    params.waveform.dmrs.deltaSS = 0;

    % 同步参数
    % [Engineering Deduction]
    % LTE uses PRACH for initial access, but for continuous transmission simulation,
    % we assume a UW-like preamble or DMRS-based sync.
    % Here we configure a UW for simulation simplicity/robustness in burst mode.
    params.waveform.prachEnabled = true;
    params.waveform.prachFormat = 0;
    params.waveform.dmrsSequence = 'Zadoff-Chu';
    params.waveform.uwLength = 2048; % Matches FFT size
    params.waveform.syncThresholdMultiplier = 5;

    % UW 生成参数 (PN序列) [Simulation Assumption]
    params.waveform.uwPoly = [9 4 0];
    params.waveform.uwInit = [1 0 0 1 1 0 1 0 1];

    % CE 生成参数 (PN序列) [Simulation Assumption]
    params.waveform.cePoly = [11 2 0];
    params.waveform.ceInit = ones(11, 1);

    % === 编码参数 ===
    params.coding = struct();
    % [Source: ETSI TR 103 611]
    % Suggests Turbo codes (LTE standard) or LDPC (5G/DVB-S2).
    % Simulation uses LDPC (DVB-S2 standard) for robustness and performance,
    % although legacy OneWeb terminals might use LTE Turbo.
    params.coding.type = 'LDPC';
    params.coding.standard = 'DVB-S2';
    params.coding.constraintLength = 0; % Not used for LDPC
    params.coding.trellis = []; % Not used for LDPC
    params.coding.supportedRates = [1/2, 2/3, 3/4, 5/6];
    params.coding.crcLength = 0; % LDPC usually includes BCH or similar

    % 扰码参数 [Source: ETSI TR 103 611 Annex A]
    params.coding.scramblerPoly = [1 zeros(1, 10) 1 0 1]; % 1 + D^11 + D^2
    params.coding.scramblerInit = [1 0 1 1 0 1 0 1 0 0 1 0 1];

    % 交织参数
    params.coding.interleaverType = 'block';

    % === MCS 参数表 (基于LTE标准) ===
    % [Source: 3GPP TS 36.213]
    %     MCS | 调制阶数 | 码率 | 所需Eb/N0(dB) | 频谱效率
    params.mcsTable = [
                       1, 2, 1/2, 2.5, 0.5; % BPSK 1/2 (Robust)
                       2, 4, 1/2, 4.5, 1.0; % QPSK 1/2
                       3, 4, 2/3, 6.0, 1.33; % QPSK 2/3 (Standard)
                       4, 4, 3/4, 7.0, 1.5; % QPSK 3/4
                       5, 16, 1/2, 9.5, 2.0; % 16QAM 1/2
                       6, 16, 2/3, 11.5, 2.67; % 16QAM 2/3
                       7, 16, 3/4, 13.0, 3.0; % 16QAM 3/4
                       8, 64, 2/3, 16.0, 4.0; % 64QAM 2/3
                       9, 64, 3/4, 17.5, 4.5; % 64QAM 3/4
                       10, 64, 5/6, 19.0, 5.0; % 64QAM 5/6
                       ];

    %% ========== 发射机默认配置 ==========
    params.defaultTxConfig = struct();
    params.defaultTxConfig.mcs = 1; % QPSK, 2/3
    params.defaultTxConfig.channelIndex = 4;
    params.defaultTxConfig.txPower = 33; % 33 dBm (2W)
    params.defaultTxConfig.beamAngle = [0, 35];
    params.defaultTxConfig.enableCFR = false;
    params.defaultTxConfig.enableDPD = false;
    params.defaultTxConfig.verbose = true;

    % CFR参数
    params.cfrThreshold_dB = 4.0;

    %% ========== 数据生成相关配置 ==========
    params.channelIndexRange = [1, 10];

    params.serviceCoverage = struct();
    params.serviceCoverage.latitudeRange = 90;
    params.serviceCoverage.longitudeRange = 360;
    params.serviceCoverage.altitudeRange = [0, 500];

    %% ========== 神经接收机推荐参数 ==========
    % Deprecated: neuralRx struct has been removed. Parameters moved to spectrumMonitorConfig.m

end
