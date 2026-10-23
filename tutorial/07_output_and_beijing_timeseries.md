# 第 7 课：从 MPAS 输出中找到北京

用 WRF 提取站点时，我们通常先找最近的 `south_north, west_east`。到了 MPAS，规则的
二维下标消失了，变量沿 `nCells` 这一维存放。数组序号本身不带经纬度；要找到北京，还得
同时读取 `latCell/lonCell`。

## 动手前先检查文件和 Python 环境

下面的命令都从仓库根目录运行。请先完成第 6 课的 240 km 教学预报，并确认初值和诊断
输出确实存在：

```bash
test -s work/beijing_240km_2026101500/x1.10242.init.nc
ls -lh work/beijing_240km_2026101500/x1.10242.init.nc \
  work/beijing_240km_2026101500/diag.2026-10-{15,16}_00.00.00.nc
```

当前案例的真实终端输出如下。`init.nc` 是坐标和初始状态来源，两个 `diag` 分别是起报和
F024 时刻；中间还有 7 个三小时时次，这里省略：

```console
$ ls -lh work/beijing_240km_2026101500/x1.10242.init.nc \
>   work/beijing_240km_2026101500/diag.2026-10-{15,16}_00.00.00.nc
-rw-r-----+ ...  11M ... diag.2026-10-15_00.00.00.nc
-rw-r-----+ ...  11M ... diag.2026-10-16_00.00.00.nc
-rw-r-----+ ... 173M ... x1.10242.init.nc
```

这些 NetCDF 是模式生成的结果，平时只读。需要换起报时间、输出间隔或变量清单时，应修改
生成它们的 namelist/streams 配置并重新运行。

如果你在第 3 课亲手画过网格，`work/venv-post` 已经建好了；否则，下面第一条命令会创建
它。这个环境专门放后处理所需的 Python 包，不会影响编译 MPAS 时使用的库。重复执行创建
命令不会覆盖已有环境。

```bash
python3 -m venv work/venv-post
source work/venv-post/bin/activate
python -m pip install --upgrade pip
python -m pip install numpy netCDF4 matplotlib
python -c 'import numpy, netCDF4, matplotlib; print("Python post-processing imports: OK")'
```

成功时最后一条只打印：

```console
$ python -c 'import numpy, netCDF4, matplotlib; print("Python post-processing imports: OK")'
Python post-processing imports: OK
```

生成的 `work/venv-post/` 是可删除、可重建的本机环境，不应提交到 Git，也不要从另一台机器
直接复制其中的二进制包；换机后重新创建并安装依赖。

第 10 课还会在这里安装地图绘图库 Cartopy。以后重新打开终端，先运行
`source work/venv-post/bin/activate`，再做后处理。

## 一个下标为什么不能到处用

MPAS-A 采用 C 网格交错。英文资料把网格单元称为 cell，边称为 edge，顶点称为 vertex。
这三类位置各有各的数组：

```text
顶点 -------- 边 -------- 顶点
   \          法向风 u          /
    \                        /
     \    网格单元中心     /
      \  温度、压力、水汽  /
       顶点 ---- 边 ---- 顶点
```

- 温度、压力、水汽等标量通常放在网格单元中心；
- 模式直接预报的风 `u` 放在边上，保存的是垂直于这条边的风速分量；
- 涡度等变量可能放在顶点上。

WRF 常见的地面变量维度是 `(Time, south_north, west_east)`；本例中的 MPAS 地面变量通常是
`(Time, nCells)`。三维标量一般是 `(Time, nCells, nVertLevels)`，模式风 `u` 则是
`(Time, nEdges, nVertLevels)`。因此，某个网格单元的下标不能直接拿去读取边或顶点
变量。

## `history` 和 `diag` 里究竟有什么

MPAS 的输出由输出流配置文件 `streams.atmosphere` 和变量清单 `stream_list.*` 决定。
文件名只是当前配置下的习惯，不能永远代表固定内容。本例的设置如下：

| 文件 | 本例写出的内容 | 输出间隔 | 常见用途 |
|---|---|---:|---|
| `history.*.nc` | 网格坐标以及较完整的二维、三维场 | 6 小时 | 科研分析、检查模式状态 |
| `diag.*.nc` | 2 米温度、10 米风、海平面气压、等压面场和降水等 | 3 小时 | 高频天气诊断 |
| `restart.*.nc` | 继续积分所需的完整状态 | 24 小时 | 断点续算，不是普通绘图文件 |

先查看配置和文件头，再决定读取哪个变量：

```bash
sed -n '1,35p' work/beijing_240km_2026101500/streams.atmosphere | \
  grep -n 'output_interval'
local/io-stack/bin/ncdump -h \
  work/beijing_240km_2026101500/diag.2026-10-15_00.00.00.nc | less
local/io-stack/bin/ncdump -h \
  work/beijing_240km_2026101500/diag.2026-10-15_00.00.00.nc | \
  grep -E '^[[:space:]]*(Time =|nCells =|double (mslp|rainc|rainnc|u10|v10|t2m)\()'
```

本案例中，与后文直接相关的真实内容是：

```console
$ sed -n '1,35p' work/beijing_240km_2026101500/streams.atmosphere | grep -n 'output_interval'
16:                  output_interval="1_00:00:00" />
21:        output_interval="6:00:00" >
29:        output_interval="3:00:00" >

$ local/io-stack/bin/ncdump -h \
>   work/beijing_240km_2026101500/diag.2026-10-15_00.00.00.nc | \
>   grep -E '^[[:space:]]*(Time =|nCells =|double (mslp|rainc|rainnc|u10|v10|t2m)\()'
Time = UNLIMITED ; // (1 currently)
nCells = 10242 ;
double mslp(Time, nCells) ;
double rainc(Time, nCells) ;
double rainnc(Time, nCells) ;
double u10(Time, nCells) ;
double v10(Time, nCells) ;
double t2m(Time, nCells) ;
```

第 21、29 行分别对应 history 的 6 小时和 diagnostics 的 3 小时输出；第 16 行是 restart
的 1 天间隔。要永久改变间隔或变量清单，应修改版本控制中的生成脚本/模板后重新运行。
案例目录里的 `streams.atmosphere` 会被运行脚本重新生成，临时手改可能在下次运行时被覆盖；
`stream_list.atmosphere.*` 决定各流包含哪些变量。

本例的 `diag` 文件没有重复写入 `latCell/lonCell`。绘图或提取站点时，应从同一张网格、
并且网格单元顺序完全相同的 `init.nc` 或 `history` 文件读取坐标。也可以修改输出流，让
诊断文件带上坐标；这不是 NetCDF 格式本身的限制。

## 找出离北京最近的网格单元

仓库中的脚本会读取所有 `latCell/lonCell`，计算各网格单元中心到北京的球面大圆距离。
这里不能简单比较经纬度差的平方，因为经度方向的实际距离会随纬度变化。

`indexToCellID` 记录“数组位置对应哪个全局网格单元编号”。脚本会同时给出从 0 开始的
Python 数组下标和文件中的全局编号，不会擅自假定两者只差 1。

```bash
python tools/analyze_beijing.py work/beijing_240km_2026101500
```

脚本会在案例目录中寻找唯一的 `*.init.nc`。如果有多个候选文件，必须通过
`--grid-file 文件名` 指定坐标来源。脚本先比较 `nCells`，再核对 `file_id/parent_id`。
`file_id` 是本文件的标识；`parent_id` 记录生成它时所用父文件的标识。这样可以挡住
“大小相同、实际却是另一张网格”的误配。老文件若没有这两项信息，脚本只能检查网格
单元数并发出警告，这时还应比较网格文件校验值。

本例的实际输出如下。开头的警告说明 diagnostics 没有分桶计数器，并不表示这次短案例
失败；若检测到累计量回卷，脚本会停止：

```console
$ python tools/analyze_beijing.py work/beijing_240km_2026101500
WARNING: diagnostics omit i_rainc, i_rainnc; any detected bucket rollover will stop the analysis.
cell index=3150, cell ID=3151, distance=130.1 km
wrote work/beijing_240km_2026101500/beijing_nearest_cell.csv
wrote work/beijing_240km_2026101500/beijing_nearest_cell.png
```

再检查生成的表格和图片：

```bash
ls -lh work/beijing_240km_2026101500/beijing_nearest_cell.{csv,png}
cut -d, -f1,2,3,4,5,6,7,12 \
  work/beijing_240km_2026101500/beijing_nearest_cell.csv | head -n 3
```

当前目录和 CSV 关键内容为：

```console
$ ls -lh work/beijing_240km_2026101500/beijing_nearest_cell.{csv,png}
-rw-rw----+ ... 2.2K ... beijing_nearest_cell.csv
-rw-rw----+ ... 116K ... beijing_nearest_cell.png

$ cut -d, -f1,2,3,4,5,6,7,12 work/beijing_240km_2026101500/beijing_nearest_cell.csv | head -n 3
time_utc,cell_index_zero_based,cell_id_one_based,cell_latitude_deg,cell_longitude_deg,distance_to_beijing_km,t2m_c,precip_since_previous_output_mm
2026-10-15_00:00:00,3150,3151,40.92212560074218,115.65033397016501,130.07454583326108,7.0370694649071766,
2026-10-15_03:00:00,3150,3151,40.92212560074218,115.65033397016501,130.07454583326108,13.949679289330902,0.0
```

CSV 和 PNG 都可以重新生成。换站点用 `--latitude/--longitude`，换文件名前缀用
`--output-prefix`，有多个初值文件时用 `--grid-file`。若数值或图片不合适，应调整输入或
参数后重跑脚本。

`3150` 是从 0 开始的 Python 数组下标；在这份文件里，它恰好对应全局编号 `3151`。
最近的网格单元中心距北京仍有约 130 km。这也提醒我们：240 km 网格适合跑通流程，却不
适合做精细的北京天气预报。

## 累计降水最容易踩的坑

`rainc` 是累计对流降水，`rainnc` 是累计网格尺度降水，单位都是毫米。在计数没有回卷时，
累计总降水就是：

```text
rainc + rainnc
```

但 MPAS 默认把 `config_bucket_rainc` 和 `config_bucket_rainnc` 都设为 100 mm。只要
`config_bucket_update` 不是 `'none'`，模式就会按它设定的间隔检查：累计量超过阈值后，
相应变量会减去一个 100 mm，并把 `i_rainc` 或 `i_rainnc` 加 1。这套做法可以理解为
“分桶计数”。`config_bucket_update` 的默认值是 `'none'`，本例脚本沿用官方默认
namelist 中的这一项，所以这次预报不会触发分桶回卷。如果输出文件包含两个计数变量，
完整累计量应恢复为：

```text
total = (rainc  + config_bucket_rainc  * i_rainc)
      + (rainnc + config_bucket_rainnc * i_rainnc)
```

本例的诊断变量清单没有输出 `i_rainc/i_rainnc`。一旦发生回卷，便无法准确恢复完整累计量。
教学脚本会明确警告，并逐个核对输出有效时刻变量 `xtime` 是否保持 3 小时间隔、是否来自
同一次冷启动；只要发现任一降水分量下降，脚本就会停止，而不是把负值强行改成 0。将来
若在输出流中加入计数变量，脚本会自动按上式恢复累计降水。正常的断点续算会接着累计，
不能一概当作重新归零。

第一个输出时刻没有前一时次可减，所以 CSV 中第一个时段增量留空。若你的输出间隔不是
3 小时，请通过 `--expected-interval-hours` 指定。正式做降水统计时，最好始终输出并检查
这两个计数变量。

## 最近邻只是起点

用最近网格单元提取北京，足以检查模式是否跑通。制作正式站点产品时，还要考虑周围多个
网格单元的空间插值，以及模式地形与真实站高的差异，并记录所用方法。画水平场时，可以直接
显示 MPAS 原生的 Voronoi 多边形，也可以先重映射到规则经纬网。第 10 课采用的是快速绘图
插值，并会说明它为什么不能代替守恒重映射。

## 做完以后怎样验收

```bash
find work/beijing_240km_2026101500 -maxdepth 1 -name 'diag.*.nc' | wc -l
find work/beijing_240km_2026101500 -maxdepth 1 -name 'history.*.nc' | wc -l
wc -l work/beijing_240km_2026101500/beijing_nearest_cell.csv
```

当前真实输出是：

```console
$ find work/beijing_240km_2026101500 -maxdepth 1 -name 'diag.*.nc' | wc -l
9
$ find work/beijing_240km_2026101500 -maxdepth 1 -name 'history.*.nc' | wc -l
5
$ wc -l work/beijing_240km_2026101500/beijing_nearest_cell.csv
10 work/beijing_240km_2026101500/beijing_nearest_cell.csv
```

应该看到以下结果：

- `diag` 有 9 个三小时时次，`history` 有 5 个六小时时次；
- CSV 共 10 行，即 1 行表头加 9 个时次；网格单元下标、全局编号和坐标始终不变；
- 最近网格单元中心距北京约 130 km；
- 你能说明：没有降水分桶计数时，累计量一旦下降，脚本为什么只能报错，不能猜一个增量。

## 合上教程，试着自己讲一遍

1. 为什么 `3150` 不能同时代表网格单元（cell）、边（edge）和顶点（vertex）？
2. 一个 `diag` 文件和一份坐标文件的网格单元数相同，为什么仍可能配错？
3. `rainc + rainnc` 的相邻时次差值为什么可能突然变成负数？
