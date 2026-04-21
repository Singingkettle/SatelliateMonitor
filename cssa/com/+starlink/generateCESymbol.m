function ceFreqDomain = generateCESymbol(nSubcarriers, ceCfg)
    %GENERATECESYMBOL Deterministic QPSK CE symbol for Starlink uplink
    %
    % ceFreqDomain = starlink.generateCESymbol(nSubcarriers, ceCfg)
    %
    % Inputs:
    %   nSubcarriers - Number of occupied subcarriers (1024 for 60 MHz mode)
    %   ceCfg        - Struct with PN configuration:
    %                    .poly      - Polynomial (descending powers) for PN generator
    %                    .init      - Initial conditions (length = degree)
    %                    .modOrder  - Modulation order (default QPSK, i.e., 4)
    %
    % Output:
    %   ceFreqDomain - Column vector (nSubcarriers x 1) with deterministic QPSK symbols

    arguments
        nSubcarriers (1, 1) {mustBePositive, mustBeInteger}
        ceCfg struct
    end

    if ~isfield(ceCfg, 'modOrder') || isempty(ceCfg.modOrder)
        ceCfg.modOrder = 4; % QPSK
    end

    bitsPerSymbol = log2(ceCfg.modOrder);
    numBits = nSubcarriers * bitsPerSymbol;

    pn = comm.PNSequence( ...
        'Polynomial', ceCfg.poly, ...
        'InitialConditions', ceCfg.init, ...
        'SamplesPerFrame', numBits, ...
        'OutputDataType', 'double');

    ceBits = pn();
    ceFreqDomain = qammod(ceBits, ceCfg.modOrder, ...
        'InputType', 'bit', 'UnitAveragePower', true);
end
