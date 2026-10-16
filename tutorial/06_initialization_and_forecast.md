# 第 6 课：制作初值，跑完第一次 24 小时预报

## 先从熟悉的 WRF 流程说起

WRF 从静态地理资料走到正式积分，要依次经过 `geogrid.exe`、`metgrid.exe`、`real.exe`
和 `wrf.exe`。MPAS 的程序划分不一样。`init_atmosphere_model` 分两次运行，承担其中多项
准备工作：

```text
WRF:   geogrid.exe       metgrid.exe + real.exe       wrf.exe
          |                       |                      |
MPAS: grid -> static       static + FILE -> init   atmosphere_model
             \____________ init_atmosphere_model ______/
```

这并不是说 MPAS 完全不用 WPS。第 4 课已经运行过 `ungrib.exe`，GRIB2 仍由它解码。
MPAS 的静态资料制作，大致对应 `geogrid.exe` 所做的事；气象场水平插值、垂直坐标建立
和完整初值制作，则合并了 `metgrid.exe` 与 `real.exe` 的部分职责。

## 开始之前，把四类输入认全

不要急着敲命令，先确认自己知道每个文件从哪里来、有什么用：

| 输入 | 内容 | 本案例来源 |
|---|---|---|
| `x1.10242.static.nc` | 网格几何加地形、土地利用等静态场 | 官方 240 km 静态资料包 |
| `FILE:2026-10-15_00` | GFS 起报时刻的规则经纬网气象场 | 第 4 课运行 `ungrib.exe` 后生成 |
| `x1.10242.graph.info.part.16` | 把 10242 个网格单元分给 16 个 MPI 进程 | 官方网格包 |
| namelist + streams | 计算参数与输入输出设置 | 运行脚本按第 5 课规则生成 |

`prepare_beijing_case.sh` 下载的 static 文件，已经包含这张网格的几何信息、地形和土地
利用等静态场。因此，这个 240 km 算例不再读取环境变量 `WPS_GEOG` 指向的资料。第 8 课
把北京加密网格旋转到新的位置后，网格单元的经纬度随之改变，那时必须从 WPS_GEOG
重新制作 static，而且这一步要串行运行。

默认算例从 2026-10-15 00 UTC 起报，积分 24 小时，GFS 间隔为 3 小时。
`run_beijing_case.sh` 会读取第 4 课生成的 `case.env`，自动填写起报时刻、积分时长和
气象初猜资料间隔。因此，换一个日期后仍可沿用同一套 x1.10242 操作。要注意，这个脚本
目前只适用于 x1 网格，不能直接拿来运行第 8 课的 x4 北京网格。

## 为什么要把准备工作分成两步

完整的真实资料初始化分为两步：

```text
阶段 A：grid.nc + WPS_GEOG  -> static.nc       每张网格一次，必须用 1 个 MPI 进程
阶段 B：static.nc + FILE:<起报有效时刻> -> init.nc  每个起报时刻一次，可以并行
```

本例已经下载了现成的 static 文件，所以只执行阶段 B。两步分开的好处很实际：以后只换
起报日期时，重新制作 init 即可，不必每次都读取体积庞大的静态地理资料。

## GFS 资料怎样变成 MPAS 初值

`FILE:2026-10-15_00` 采用 1440×721 的 0.25°规则经纬网。初始化程序先把风、温、湿、
气压和陆面状态水平插值到 10242 个 Voronoi 网格单元，再建立 MPAS 垂直坐标：

- `config_nfglevels=38`：为气象初猜资料预留最多 38 个不同层次。本例日志实际报告
  `Found 34 levels in the first-guess data`，所以 38 是容量，不是资料的实际层数；
- `config_nvertlevels=55`：55 个 MPAS 模式质量层，并有 56 个层界面；
- `config_ztop=30000`：几何高度约 30 km 的模式顶，不是“30 km 分辨率”或“100 hPa 顶”。

制作初值并不是把 GFS 数组原样复制过去。水平风要转换为 MPAS 网格边上的法向速度；
地面气压要与新网格上的地形相协调；水汽、土壤状态、海温和海冰也要一起整理成模式能够
直接积分的状态。

## 第一步：检查第 4 课留下的文件

从仓库根目录检查，不满足就先重新执行准备与 ungrib：

```bash
CASE_DIR=work/beijing_240km_2026101500
test -s "$CASE_DIR/x1.10242.static.nc"
test -s "$CASE_DIR/x1.10242.graph.info.part.16"
test -s "$CASE_DIR/FILE:2026-10-15_00"
test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'FILE:*' | wc -l)" -eq 9
```

若检查失败，执行：

```bash
./prepare_beijing_case.sh
(cd work/beijing_240km_2026101500 && ./ungrib.exe)
```

完成后应有第 4 课所说的九个连续 `FILE:*`，日志中还应出现
`Successful completion of program ungrib.exe`。输入文件没准备好时，不要试图修改
namelist 绕过检查。

## 第二步：生成 `init.nc`

这里的 `NTASKS=16` 表示 16 个 MPI 进程，不是 16 个 OpenMP 线程。它必须与
`.part.16` 对应，作业也要实际申请足够的 CPU 资源。

```bash
NTASKS=16 ./run_beijing_case.sh init
```

脚本会链接本项目编译的 `mpas_init_atmosphere` 和所需查找表，生成
`namelist.init_atmosphere`、`streams.init_atmosphere`，再调用本项目自己编译的
OpenMPI。它不会重新制作 static；这一步实际读取和写出的文件如下：

```text
x1.10242.static.nc + FILE:2026-10-15_00
                     + graph.info.part.16
                     -> x1.10242.init.nc
```

### 检查初值是否合格

先看日志。程序必须明确结束，而且不能有错误：

```bash
LOG="$CASE_DIR/log.init_atmosphere.0000.out"
grep -E 'Finished running|Warning messages|Error messages|Critical error messages' "$LOG"
grep 'Found .* levels in the first-guess data' "$LOG"
```

本例应看到：

```text
Finished running the init_atmosphere core
Warning messages = 0
Error messages = 0
Critical error messages = 0
Found 34 levels in the first-guess data
```

然后检查网格大小、垂直层数和起报时间。`xtime` 是 NetCDF 文件中记录模拟有效时刻的
字符变量，可以类比 WRF 文件中的 `Times`：

```bash
local/io-stack/bin/ncdump -h "$CASE_DIR/x1.10242.init.nc" \
  | sed -n '/dimensions:/,/variables:/p' | head -25
local/io-stack/bin/ncdump -v xtime \
  "$CASE_DIR/x1.10242.init.nc" | tail -8
local/io-stack/bin/ncdump -v nominalMinDc \
  "$CASE_DIR/x1.10242.init.nc" | tail -8
```

应看到 `nCells=10242`、`nVertLevels=55`、`nVertLevelsP1=56`、`nSoilLevels=4`，
`xtime=2026-10-15_00:00:00`，以及 `nominalMinDc=240000 m`。只有这些信息都对，才能
说明初始化确实使用了正确的网格、时刻和垂直层。单看“文件已经生成，而且体积不小”，
远远不够。

这时不妨顺手看看脚本写出的配置文件，把第 5 课讲过的参数逐项对上：

```bash
sed -n '1,180p' "$CASE_DIR/namelist.init_atmosphere"
sed -n '1,160p' "$CASE_DIR/streams.init_atmosphere"
```

## 第三步：从冷启动积分 24 小时

初值验收通过后执行：

```bash
NTASKS=16 ./run_beijing_case.sh forecast
```

这条命令在前台运行。等它返回时，模式已经结束。随后查看日志末尾：

```bash
tail -n 50 "$CASE_DIR/log.atmosphere.0000.out"
```

如果想实时查看进度，请另开一个终端，运行：

```bash
tail -f work/beijing_240km_2026101500/log.atmosphere.0000.out
```

模式结束后按 Ctrl-C 退出。不要把 `tail -f` 直接接在前台预报命令后面，否则它会等到
预报已经结束才启动，然后一直不返回。

240 km 教学算例使用 `config_dt=1200 s`，24 小时共走 72 个动力大步。历史场 history
每 6 小时输出一次，诊断场 diagnostics 每 3 小时输出一次。这两个间隔写在
`streams.atmosphere`，不在 namelist 中。

### 检查预报是否完整

先检查日志中的结束标记和错误计数：

```bash
LOG="$CASE_DIR/log.atmosphere.0000.out"
grep -E 'Finished running|Warning messages|Error messages|Critical error messages' "$LOG"
```

本机实测时，atmosphere 核心程序正常完成，日志显示 3 条警告、0 个错误、0 个严重错误。
三条已知警告是初值中没有云冰 `qi`、雪 `qs`、霰 `qg` 三种冰相水凝物，程序在这个教学
算例中仍会继续运行。如果你的日志也是 3 条警告，但内容不同，不能只看数量相同就忽略。

接着检查输出文件数量和最后时刻：

```bash
find "$CASE_DIR" -maxdepth 1 -type f -name 'history.*.nc' | sort
find "$CASE_DIR" -maxdepth 1 -type f -name 'diag.*.nc' | sort
find "$CASE_DIR" -maxdepth 1 -type f -name 'restart.*.nc' | sort

test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'history.*.nc' | wc -l)" -eq 5
test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'diag.*.nc' | wc -l)" -eq 9
test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'restart.*.nc' | wc -l)" -eq 1

local/io-stack/bin/ncdump -v xtime \
  "$CASE_DIR/diag.2026-10-16_00.00.00.nc" | tail -8
```

最后一个 `xtime` 应为 `2026-10-16_00:00:00`。前面的 5 个和 9 个文件都把起报时刻那份
算在内。如果重复使用旧的案例目录，请先分清哪些文件是上一次留下的。否则文件数量看似
正确，也可能只是旧文件凑出来的，不能证明这次预报成功。

如果希望制作初值后紧接着运行预报，可以在干净的案例目录中执行：

```bash
NTASKS=16 ./run_beijing_case.sh all
```

第一次学习时，仍建议把两步分开。这样一旦出错，很容易判断问题出在 GFS 制作初值，
还是初值进入正式预报以后。

## 为什么第一次预报不更新海表温度

本例设置 `config_sst_update=false`。因此，起报时刻写入初值的海表温度（SST）和海冰，
在这 24 小时内不会从外部资料更新。这不代表整个地表状态都被固定了：陆面模式、近地层
通量和大气仍会照常演变。

第一次只跑一天，先不加入周期海表更新，可以少引入一组文件和开关。等基本预报跑通后，
再单独检查 SST、海冰更新，排错会清楚得多。

后续制作周期更新资料时，会用任务 8 读取第 4 课的多个 `FILE:*`，生成
`sfc_update.nc`，然后启用海表更新输入和 `config_sst_update=true`。有限区域预报则要用
任务 9 生成各时次的侧边界文件。这些是后续课程的内容，本例尚未启用。

## 几种常见错误怎么查

- `No mesh partition for NTASKS=N`：MPI 进程数与 `.part.N` 不匹配，不是网格文件损坏。
- 找不到 `FILE:<起报有效时刻>`：所选 `CASE_DIR` 的 `case.env`、`config_start_time` 与 `FILE:*`
  不一致，或第 4 课的 ungrib 尚未完成。
- 初值时间与起报时刻不同：同时核对 `xtime`、`config_start_time` 和 streams 中的输入
  文件名。
- 日志出现 CFL（库朗数，衡量一个时间步内信息跨越多少个网格尺度）、NaN 或速度爆炸：
  先核对网格对应的 `config_dt` 和初值，再考虑物理方案。
- 已经出现 `.nc`，但日志没有完成标记：把它视为未写完的文件，不要拿去做后处理。

## 试着用自己的话讲一遍

请向另一位熟悉 WRF 的同事解释：遇到下面四种变化，哪些步骤要重做？

1. 只换起报日期：重新运行 `ungrib.exe` 并制作 init；同一网格的 static 和分区可复用。
2. 只把同一张网格刚性旋转到北京：`FILE:*` 和原分区可复用，但 static、init 必须重做。
3. 换成拓扑和分辨率都不同的另一张网格：`FILE:*` 可复用，static、init 和分区都要与
   新网格配套。
4. 只把 MPI 从 16 改为 32：气象初值和邻接关系都不变，但必须提供同网格的 `.part.32`，
   因为网格要重新分成 32 份。

这四种变化，归根到底是在问：资料时间、网格和进程数改变以后，分别会牵动哪些文件。

## 参考

- [MPAS-A 官方真实资料初始化与运行](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
- [MPAS-A 官方 I/O 配置](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/configuring_io.html)
