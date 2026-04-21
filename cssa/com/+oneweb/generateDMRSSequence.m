function seq = generateDMRSSequence(nSubcarriers, dmrsCfg, slotIndex, symbolIndex)
    %GENERATEDMRSSEQUENCE Generate OneWeb/LTE-style DMRS (Zadoff-Chu) sequence.
    %
    %   seq = generateDMRSSequence(nSubcarriers, dmrsCfg)
    %   seq = generateDMRSSequence(..., slotIndex, symbolIndex)
    %
    %   Inputs:
    %       nSubcarriers - Number of occupied subcarriers (M_sc^{RS})
    %       dmrsCfg      - Struct with ZC parameters:
    %                        .rootSequenceIndex (default 1, must be coprime with nSubcarriers)
    %                        .cyclicShift      (n_cs in [0,7], default 0)
    %                        .groupHopping     (bool, default false - not implemented)
    %                        .sequenceHopping  (bool, default false - not implemented)
    %                        .deltaSS          (default 0, reserved for hopping)
    %       slotIndex    - Optional slot index (0-based) for future hopping support
    %       symbolIndex  - Optional SC-FDMA symbol index within slot
    %
    %   Output:
    %       seq          - Column vector (nSubcarriers x 1) with unit-magnitude DMRS
    %
    %   Notes:
    %       - Implements the base Zadoff-Chu CAZAC definition per 3GPP TS 36.211 §5.5
    %       - Group/sequence hopping hooks are reserved; current implementation keeps
    %         a fixed root and cyclic shift unless future configs enable them.

    if nargin < 2 || isempty(dmrsCfg)
        dmrsCfg = struct();
    end

    if nargin < 3 || isempty(slotIndex)
        slotIndex = 0; % Reserved for future hopping support
    end

    if nargin < 4 || isempty(symbolIndex)
        symbolIndex = 0; % Reserved for future cyclic shift hopping
    end

    rootIndex = getFieldOr(dmrsCfg, 'rootSequenceIndex', 1);
    rootIndex = mod(rootIndex, nSubcarriers);

    if rootIndex == 0
        rootIndex = 1;
    end

    if gcd(rootIndex, nSubcarriers) ~= 1
        rootIndex = findNextCoprime(rootIndex, nSubcarriers);
    end

    m = (0:nSubcarriers - 1).';
    seq = exp(-1j * pi * rootIndex .* m .* (m + 1) / nSubcarriers);

    cyclicShift = getFieldOr(dmrsCfg, 'cyclicShift', 0);

    if cyclicShift ~= 0
        % LTE定义 n_cs -> alpha = π/6 * n_cs (N_cs=12)
        alpha = (pi / 6) * cyclicShift;
        seq = seq .* exp(1j * alpha * m);
    end

    if isfield(dmrsCfg, 'groupHopping') && dmrsCfg.groupHopping
        warning('generateDMRSSequence:GroupHoppingNotImplemented', ...
        'Group hopping is not implemented; using fixed root sequence.');
    end

    if isfield(dmrsCfg, 'sequenceHopping') && dmrsCfg.sequenceHopping
        warning('generateDMRSSequence:SequenceHoppingNotImplemented', ...
        'Sequence hopping is not implemented; using fixed root sequence.');
    end

    % 归一化（理论上ZC序列幅度恒为1，此处防止数值误差）
    seq = seq ./ sqrt(mean(abs(seq) .^ 2));
end

function value = getFieldOr(structIn, fieldName, defaultValue)

    if isfield(structIn, fieldName)
        value = structIn.(fieldName);
    else
        value = defaultValue;
    end

end

function nextRoot = findNextCoprime(startValue, modulus)
    nextRoot = startValue;

    for k = 1:modulus

        if gcd(nextRoot, modulus) == 1
            return;
        end

        nextRoot = nextRoot + 1;

        if nextRoot >= modulus
            nextRoot = 1;
        end

    end

    % Fallback: if no coprime found (should not happen), default to 1
    nextRoot = 1;
end
