function overlaps = overlap(newLabel, existingLabel)
    % OVERLAP 检查两个 burst 是否时频重叠 (dataGen.burst.overlap)
    %
    %   overlaps = dataGen.burst.overlap(newLabel, existingLabel)
    %
    % 输入:
    %   newLabel      - 新 burst 的标签
    %   existingLabel - 已存在 burst 的标签
    %
    % 输出:
    %   overlaps - 是否重叠 (true/false)

    % 时间重叠检测
    t1Start = newLabel.signalStart;
    t1End = newLabel.signalEnd;
    t2Start = existingLabel.signalStart;
    t2End = existingLabel.signalEnd;

    tOverlap = max(0, min(t1End, t2End) - max(t1Start, t2Start));

    % 频率重叠检测
    f1C = newLabel.centerFreq + newLabel.freqOffset;
    f1Bw = newLabel.bandwidth;
    f2C = existingLabel.centerFreq + existingLabel.freqOffset;
    f2Bw = existingLabel.bandwidth;

    f1Min = f1C - f1Bw / 2;
    f1Max = f1C + f1Bw / 2;
    f2Min = f2C - f2Bw / 2;
    f2Max = f2C + f2Bw / 2;

    fOverlap = max(0, min(f1Max, f2Max) - max(f1Min, f2Min));

    % 判断冲突
    timeConflict = (tOverlap > 0);
    freqConflict = (fOverlap > 1e4); % > 10kHz

    overlaps = timeConflict && freqConflict;
end

