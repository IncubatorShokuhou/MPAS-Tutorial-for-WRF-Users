# 第 7 课：理解输出并提取北京预报

## MPAS 输出不是规则二维数组

WRF 的地面变量通常是 `(Time, south_north, west_east)`；MPAS 的对应变量是
`(Time, nCells)`。`nCells` 没有规则的 `i,j` 含义，每个 cell 的位置由弧度制
`latCell/lonCell` 给出。三维标量通常是 `(Time, nCells, nVertLevels)`，法向风
`u` 则位于 edge，维度为 `(Time, nEdges, nVertLevels)`。

本案例有三类输出：

- `history.*.nc`：完整网格、三维预报状态，每 6 小时；
- `diag.*.nc`：海平面气压、等压面场、2 米温度、10 米风和降水等，每 3 小时；
- `restart.*.nc`：继续积分所需的完整重启状态，不是普通绘图产品。

为减少重复，`diag` 不包含 `latCell/lonCell`。必须从同一网格的 `init.nc` 或 history
读取坐标，并保持相同的 cell 下标；不能把 diagnostics 当作自描述的规则经纬网文件。

## 找到距离北京最近的 cell

脚本使用球面大圆距离，而不是直接比较经纬度平方差：

```bash
python tools/analyze_beijing.py work/beijing_240km_2026101500
```

输出包括：

```text
work/beijing_240km_2026101500/beijing_nearest_cell.csv
work/beijing_240km_2026101500/beijing_nearest_cell.png
```

CSV 保存 cell 索引、实际中心坐标、距北京距离、2 米温度、10 米风、海平面气压和
降水。`indexToCellID` 从 1 开始，而 Python 数组索引从 0 开始，两者不要混用。

## 累计降水与时段降水

MPAS 输出的 `rainc` 和 `rainnc` 分别是对流与非对流累计降水。总累计量为：

```text
rainc + rainnc
```

相邻 diagnostics 文件的差才是三小时降水。脚本对累计量作差，把小于 `10^-9 mm` 的
舍入噪声视为零，并把极小的负值截为零；
生产流程还应识别模式重启导致的累计量归零。240 km 网格会强烈平滑北京地形和局地
降水，所以这里验证的是数据处理流程，不是城市预报能力。

## cell、edge 与 vertex

- 温度、压力和水汽等标量位于 cell；
- 模式预报风 `u` 是 edge 法向分量，不能直接当作东西风；
- diagnostics 中的 `u10/v10` 以及 `uzonal_*/umeridional_*` 已重建到地理方向；
- 涡度等变量可能位于 vertex，不能用 cell 索引直接提取。

后续绘制水平场时，应直接绘制多边形或先用保守/双线性方法重映射到规则网格。最近邻
站点提取适合快速检查，但业务站点产品应考虑多 cell 插值和高度订正。

## 费曼检查

如果把 `vorticity(Time,nVertices)` 用北京最近 cell 的索引读取，代码可能不报错，结果却
为何没有意义？因为 cell 与 vertex 是两套空间位置，恰好同为整数下标不代表同一点。
同理，画风前要先问它位于 edge 还是 cell、是法向分量还是经纬向分量。
