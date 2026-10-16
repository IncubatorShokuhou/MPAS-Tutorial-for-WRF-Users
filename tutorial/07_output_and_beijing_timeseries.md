# 第 7 课：理解输出并提取北京预报

## 本课问题

WRF 的站点提取通常是“找到最近的 `south_north, west_east`”。MPAS 文件里只有一列
`nCells`，那么北京在哪里？本课要建立的直觉是：**下标只是编号，位置必须由网格坐标和
拓扑解释**。

前置条件是已经完成第 6 课的 240 km 基线预报，并从仓库根目录执行本课命令。先确认：

```bash
test -s work/beijing_240km_2026101500/x1.10242.init.nc
ls work/beijing_240km_2026101500/diag.*.nc
```

再创建独立后处理环境；后续课程复用它，模式编译环境不会被 Python 包污染：

```bash
python3 -m venv work/venv-post
source work/venv-post/bin/activate
python -m pip install --upgrade pip
python -m pip install numpy netCDF4 matplotlib
python -c 'import numpy, netCDF4, matplotlib'
```

第 9 课只会在这个环境中追加 Cartopy。重新打开终端后，先再次执行 `source` 激活环境。

## 先认识 cell、edge 和 vertex

MPAS-A 使用 C-grid 交错，即标量位于多边形 cell 中心，预报风速位于边上并只保存法向
分量。可以把一个多边形想成一间房：

```text
vertex -------- edge -------- vertex
   \          法向风 u          /
    \                        /
     \      cell 中心       /
      \  温度、压力、水汽  /
       vertex -- edge -- vertex
```

- `cell` 是多边形中心，标量和重建后的诊断风通常位于这里；
- `edge` 是两个 cell 的公共边，模式预报风 `u` 是该边的法向速度；
- `vertex` 是多条边的交点，涡度等变量可能位于这里。

因此，WRF 常见的地面变量维度 `(Time, south_north, west_east)`，在本案例中通常变为
`(Time, nCells)`。三维 cell 标量通常为 `(Time, nCells, nVertLevels)`，而模式风 `u`
为 `(Time, nEdges, nVertLevels)`。不能拿最近 cell 的整数下标去读取 edge 或 vertex 变量。

## 输出内容由 streams 决定

文件名前缀不是内容的永久定义。下面只是本案例当前 `streams.atmosphere` 和
`stream_list.*` 的配置：

| 文件 | 本案例内容 | 本案例频率 | 用途 |
|---|---|---:|---|
| `history.*.nc` | 网格坐标及较完整的二维、三维场 | 6 小时 | 科研分析与完整状态检查 |
| `diag.*.nc` | 2 米温度、10 米风、海平面气压、等压面场和降水等 | 3 小时 | 高频诊断产品 |
| `restart.*.nc` | 恢复积分所需的检查点状态 | 24 小时 | restart，不是普通绘图产品 |

变量清单和频率都可以修改，所以先检查文件，不要凭文件名猜：

```bash
grep -n 'output_interval' work/beijing_240km_2026101500/streams.atmosphere
local/io-stack/bin/ncdump -h \
  work/beijing_240km_2026101500/diag.2026-10-15_00.00.00.nc | less
```

本案例的 `diag` 没有重复保存 `latCell/lonCell`。坐标要从**同一网格、同一下标顺序**的
`init.nc` 或 `history` 读取。其他 streams 配置也可以选择把坐标写入 diagnostics；这不是
NetCDF 格式限制。

## 找到距离北京最近的 cell

脚本用球面大圆距离比较北京与所有 `latCell/lonCell`，而不是直接比较经纬度平方差：
`indexToCellID` 是“数组位置到全局 cell ID”的映射，因此脚本会同时报告零起点数组下标
和文件中保存的全局 ID，绝不假定二者只差 1。

```bash
python tools/analyze_beijing.py work/beijing_240km_2026101500
```

脚本在案例目录中自动寻找唯一的 `*.init.nc` 坐标文件；若目录里有多个候选，必须用
`--grid-file 文件名` 明确选择。它还会比较 `nCells`；当 MPAS 文件带有
`file_id/parent_id` 元数据时，会进一步验证来源链并拒绝错配。若旧文件缺少来源元数据，
脚本只能退化为 cell 数检查并明确警告，此时应另核对网格校验和。

当前基线案例应打印近似结果：

```text
cell index=3150, cell ID=3151, distance=130.1 km
wrote .../beijing_nearest_cell.csv
wrote .../beijing_nearest_cell.png
```

检查实际产品：

```bash
head -n 4 work/beijing_240km_2026101500/beijing_nearest_cell.csv
test -s work/beijing_240km_2026101500/beijing_nearest_cell.png
```

`3150` 是本文件中的零起点 Python 数组下标，本案例对应 ID 恰好为 `3151`。最近 cell
离北京约 130 km，也直观说明 240 km 网格只能验证流程。

## 累计降水不能只做一次减法

`rainc` 是累计对流降水，`rainnc` 是累计网格尺度降水，单位都是 mm。在未发生计数器
回卷时，本案例的累计总降水可写为：

```text
rainc + rainnc
```

但 MPAS 默认的 `config_bucket_rainc` 和 `config_bucket_rainnc` 都是 100 mm。超过阈值后，
相应累计量会减去一个 bucket，并增加 `i_rainc` 或 `i_rainnc`。若这些计数变量也有输出，
完整累计量应按下式恢复：

```text
total = (rainc  + config_bucket_rainc  * i_rainc)
      + (rainnc + config_bucket_rainnc * i_rainnc)
```

本案例的 diagnostics 清单没有写出 `i_rainc/i_rainnc`，所以无法在发生 bucket 回卷后恢复
完整累计量。新版教学脚本会发出警告，逐个验证 `xtime` 的 3 小时间隔和相同冷启动时刻，
并在任一降水分量下降时直接停止；它不再把负差静默截成零。若 streams 包含 bucket 计数
变量，脚本会按上式自动恢复累计量。一个正常的 MPAS restart 应延续累计状态，不应被当作
必然归零。

第一个输出时刻没有“前一个文件”，所以 CSV 中首个时段增量留空，而不是虚构为 0。
需要其他输出间隔时，用 `--expected-interval-hours` 明确指定；生产统计仍应始终输出并检查
bucket 计数器。

## 从最近邻走向正式产品

最近邻适合冒烟测试。正式站点产品还要考虑多个 cell 的空间插值、模式地形与站高差异，
并记录采用的插值方法。水平场则可以画原生 Voronoi 多边形，或先用专门工具重映射到规则
经纬网。第 9 课只做快速绘图插值，并会解释它为什么不能替代守恒重映射。

## 本课验收

```bash
find work/beijing_240km_2026101500 -maxdepth 1 -name 'diag.*.nc' | wc -l
find work/beijing_240km_2026101500 -maxdepth 1 -name 'history.*.nc' | wc -l
wc -l work/beijing_240km_2026101500/beijing_nearest_cell.csv
```

- `diag` 恰有 9 个三小时时次，`history` 恰有 5 个六小时时次；
- CSV 共 10 行（1 行表头加 9 个时次），其中 cell 下标、全局 ID 和坐标保持不变；
- 最近 cell 距北京约 130 km，时间序列有 9 行数据；
- 能说明缺少 bucket 计数器时，为何脚本宁可在累计量下降时报错也不能猜测降水增量。

## 费曼复述

请先不用术语回答，再对照答案要点：

1. 为什么一个 `3150` 不能同时表示 cell、edge 和 vertex？
2. 为什么 `diag` 与一个 cell 数相同但来自另一张网格的坐标文件配对，会得到“能画但错误”的图？
3. 为什么 `rainc + rainnc` 的相邻差有时会突然为负？

答案要点：三类位置有独立数组和拓扑；同样长度不代表同一空间位置或下标顺序；累计降水
可能发生 bucket 回卷，也可能错误拼接了不连续时次或冷启动片段。
