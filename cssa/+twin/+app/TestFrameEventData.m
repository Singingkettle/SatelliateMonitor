classdef TestFrameEventData < event.EventData
    % TESTFRAMEEVENTDATA 通用测试事件数据载体
    %
    %   三个会话共用同一个事件类。各业务通过 Payload (struct) 字段传递任意数据，
    %   接收方按已知字段名解析。
    %
    %   常见 payload 字段约定：
    %     会话 2 TestCellReady:
    %       .CellInfo / .Sample / .Detection / .Snapshot / .Processed / .TotalCells
    %     会话 3 SignalDisplayReady:
    %       .Constellation / .SignalType / .IQData
    %     会话 3 JammingResultReady:
    %       .Constellation / .Results
    %     其它一次性通知 (TestCompleted / AllStepsCompleted) 可不带 payload。

    properties
        Payload struct = struct()
    end

    methods
        function this = TestFrameEventData(payload)
            if nargin >= 1 && ~isempty(payload)
                this.Payload = payload;
            end
        end
    end
end
