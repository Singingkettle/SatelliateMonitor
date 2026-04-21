# `data/` — 外部输入数据 (不纳入版本控制)

整个 `data/` 目录在 `.gitignore` 中被排除, 因为里面是 **可重新获取的外部数据**, 体积大且与版本无关。

## 目录结构 (运行时需要的最小集合)

```
data/
└─ TLE/
   ├─ starlink/      # *.tle, 单星一个文件 (建议 ≥ 100 个)
   └─ oneweb/        # *.tle, 单星一个文件 (建议 ≥ 100 个)
```

每个 `.tle` 文件存放 **一颗卫星的 3 行 TLE** (1 行卫星名 + 2 行轨道根数), 例如:

```
STARLINK-1008
1 44714U 19074B   26098.12190329  .00063954  00000+0  18981-2 0  9998
2 44714  53.1553  41.5837 0003190 131.3970 228.7307 15.34226723353385
```

## 推荐获取来源

| 星座 | 数据源 | 说明 |
| ---- | ------ | ---- |
| Starlink | <https://celestrak.org/NORAD/elements/gp.php?GROUP=starlink&FORMAT=tle> | Celestrak 周更聚合 TLE |
| OneWeb   | <https://celestrak.org/NORAD/elements/gp.php?GROUP=oneweb&FORMAT=tle>  | 同上 |
| 通用     | <https://www.space-track.org/>                                          | 官方源, 需注册 |

## 把聚合 TLE 拆成「单星一文件」的 PowerShell 一键脚本

```powershell
$src   = 'gp_starlink.tle'                   # Celestrak 下载下来的聚合文件
$dst   = 'data/TLE/starlink'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$lines = Get-Content $src
for ($i = 0; $i -lt $lines.Count; $i += 3) {
    $name = $lines[$i].Trim()
    $safe = ($name -replace '[\\/:*?"<>|]', '_')
    $path = Join-Path $dst "$safe.tle"
    $lines[$i..($i+2)] | Set-Content -Encoding ASCII $path
}
```

OneWeb 同理, 把 `starlink` 替换为 `oneweb`。

## 项目代码对 TLE 的依赖

- 加载入口: `cssa\+twin\+app\TestFlowPanel.m :: loadOneRandomSat`,
  `cssa\+twin\+app\Session2TestFlowPanel.m :: loadRandomSats`,
  `cssa\+twin\+app\Session3TestFlowPanel.m :: loadOneRandomSat`
- 路径硬约定: `<projectRoot>\data\TLE\<starlink|oneweb>\*.tle`
- 找不到 TLE 时, 会回退到一组写死的开普勒参数 (能跑通但卫星位置不真实)

> 提示: 至少各放 **30 个** `.tle`, 否则 Session 2 的 `30 颗卫星 × 10 SNR × 10 Doppler × 2 星座 = 6000 cells` 验收测试无法构造完整数据集。
