%% 启动卫星终端认知与干扰防御平台
%
% 功能:
%   启动数字孪生可视化平台，提供：
%   - 卫星场景3D可视化
%   - 实时信号检测与识别演示
%   - 干扰策略评估仿真
%
% 使用方法:
%   cd('项目根目录');
%   runTwinPlatform
%
% 或直接双击运行此脚本

%% 获取项目根目录并添加路径
thisFile = mfilename('fullpath');
if isempty(thisFile)
    % 如果 mfilename 返回空，使用当前目录
    projectRoot = pwd;
else
    toolsDir = fileparts(thisFile);
    projectRoot = fileparts(toolsDir);
end

% 切换到项目根目录
cd(projectRoot);

% 添加路径
addpath(genpath(fullfile(projectRoot, 'cssa')));
addpath(fullfile(projectRoot, 'tools'));

%% 启动平台
fprintf('\n');
fprintf('╔════════════════════════════════════════════════════════════╗\n');
fprintf('║     启动卫星终端认知与干扰防御平台                         ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n');
fprintf('\n');

% 启动
twin.launch();
