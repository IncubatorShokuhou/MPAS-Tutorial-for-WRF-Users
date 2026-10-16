# 第 6 课：生成初值并完成 24 小时 MPAS-A 预报

## 先把 WRF 经验翻译准确

MPAS-A 的 `init_atmosphere_model` 可以分阶段承担 WRF 流程中多项工作的职责：

```text
WRF:   geogrid.exe       metgrid.exe + real.exe       wrf.exe
          |                       |                      |
MPAS: grid -> static       static + FILE -> init   atmosphere_model
             \____________ init_atmosphere_model ______/
```

这里不是说 MPAS 把所有 WPS 都替代了：第 4 课的 `ungrib.exe` 仍负责解码 GRIB2。
静态阶段近似于 geogrid 的职责；气象水平插值、垂直坐标建立和完整模式状态初始化，则同时
具有 metgrid 与 real.exe 的一些职责。

## 先定义本课四种输入

运行任何命令前，先能解释每个文件：

| 输入 | 内容 | 本案例来源 |
|---|---|---|
| `x1.10242.static.nc` | 网格几何加地形、土地利用等静态场 | 官方 240 km static 包 |
| `FILE:2026-10-15_00` | GFS 起报时刻的规则经纬网气象场 | 第 4 课 ungrib |
| `x1.10242.graph.info.part.16` | 10242 个 cell 到 16 个 MPI ranks 的分工 | 官方网格包 |
| namelist + streams | 算法开关与文件管道 | 运行脚本按第 5 课规则生成 |

`prepare_beijing_case.sh` 下载的 static 已经包含原网格几何与静态字段，所以基线不再读取
环境变量 `WPS_GEOG` 指向的静态资料。等第 8 课旋转北京加密网格后，cell 落到新的经纬度，
才必须从 WPS_GEOG 串行重建 static。

默认案例是 2026-10-15 00 UTC、24 小时、3 小时 GFS 间隔。`run_beijing_case.sh` 会读取
第 4 课生成的 `case.env`，据此写 start time、run duration 和 first-guess interval；因此
另一个日期也能沿用同一套 x1.10242 流程。它仍是 **x1 网格专用脚本**，不能直接运行第
8 课的 x4 北京网格。

## 两次“初始化”为什么要分开

完整真实资料流程是：

```text
阶段 A：grid.nc + WPS_GEOG  -> static.nc       每张网格一次，必须 1 MPI task
阶段 B：static.nc + FILE:<起报有效时刻> -> init.nc  每个起报时刻一次，可以并行
```

本案例下载现成 static，因此只执行阶段 B。分开运行的意义是：换起报日期只重做 init，
不必再次读取庞大的静态地理资料。

## 水平和垂直方向分别发生什么

`FILE:2026-10-15_00` 是 1440×721 的 0.25°规则经纬网。初始化器先把风、温、湿、压和
陆面状态水平插值到 10242 个 Voronoi cells，再建立 MPAS 垂直坐标：

- `config_nfglevels=38`：GFS first-guess records，包含等压层和 surface/sea-level 特殊层；
- `config_nvertlevels=55`：55 个 MPAS 模式质量层，并有 56 个层界面；
- `config_ztop=30000`：几何高度约 30 km 的模式顶，不是“30 km 分辨率”或“100 hPa 顶”。

初值也不是简单复制 GFS 数组：水平风要转换为 MPAS edge 法向速度，地面气压要与新的
地形协调，水汽、土壤状态、海温和海冰也要填入同一个可积分状态。

## 第一步：确认第 4 课的产物

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

预期仍是第 4 课的九个连续 `FILE:*` 和 ungrib successful completion。不要在输入缺失时
靠修改 namelist 绕过检查。

## 第二步：生成 `init.nc`

这里的 `NTASKS=16` 是 16 个 MPI 进程，不是 16 个 OpenMP 线程。它必须匹配
`.part.16`，并且运行环境需要实际分配至少相应 CPU 资源。

```bash
NTASKS=16 ./run_beijing_case.sh init
```

脚本会链接项目自编译的 `mpas_init_atmosphere` 和所需运行表，生成
`namelist.init_atmosphere`、`streams.init_atmosphere`，再调用项目自己的 OpenMPI。
它不会执行 static 阶段；数据流是：

```text
x1.10242.static.nc + FILE:2026-10-15_00
                     + graph.info.part.16
                     -> x1.10242.init.nc
```

### 初值验收

先要求日志明确结束且没有错误：

```bash
LOG="$CASE_DIR/log.init_atmosphere.0000.out"
grep -E 'Finished running|Warning messages|Error messages|Critical error messages' "$LOG"
```

本基线预期是：

```text
Finished running the init_atmosphere core
Warning messages = 0
Error messages = 0
Critical error messages = 0
```

再证明文件的网格、垂直层和时间正确：

```bash
local/io-stack/bin/ncdump -h "$CASE_DIR/x1.10242.init.nc" \
  | sed -n '/dimensions:/,/variables:/p' | head -25
local/io-stack/bin/ncdump -v xtime \
  "$CASE_DIR/x1.10242.init.nc" | tail -8
local/io-stack/bin/ncdump -v nominalMinDc \
  "$CASE_DIR/x1.10242.init.nc" | tail -8
```

应看到 `nCells=10242`、`nVertLevels=55`、`nVertLevelsP1=56`、`nSoilLevels=4`，
`xtime=2026-10-15_00:00:00`，以及 `nominalMinDc=240000 m`。这比“文件存在且很大”更能
证明初始化使用了正确网格、时刻和垂直配置。

此时也可以查看脚本实际生成的配置，把第 5 课的概念与文件逐项对应：

```bash
sed -n '1,180p' "$CASE_DIR/namelist.init_atmosphere"
sed -n '1,160p' "$CASE_DIR/streams.init_atmosphere"
```

## 第三步：运行 24 小时冷启动预报

初值验收通过后执行：

```bash
NTASKS=16 ./run_beijing_case.sh forecast
```

命令在前台运行，返回时模式已经结束。完成后查看末尾日志应使用：

```bash
tail -n 50 "$CASE_DIR/log.atmosphere.0000.out"
```

若要实时监控，应在**另一个终端**运行
`tail -f work/beijing_240km_2026101500/log.atmosphere.0000.out`，模式结束后按 Ctrl-C；不要
把 `tail -f` 接在前台 forecast 命令之后，否则只会在预报完成后一直等待。

240 km 基线使用 `config_dt=1200 s`，24 小时共 72 个动力大步。history 每 6 小时、
diagnostics 每 3 小时；这些输出间隔来自 `streams.atmosphere`，不是 namelist。

### 预报验收

第一层证据仍是日志：

```bash
LOG="$CASE_DIR/log.atmosphere.0000.out"
grep -E 'Finished running|Warning messages|Error messages|Critical error messages' "$LOG"
```

本机验证结果是完成 atmosphere core、3 个 warnings、0 errors、0 critical errors。三个已知
warning 是初值文件中没有 `qi`、`qs`、`qg` 三个冰相水凝物变量；这个基线会继续运行。
若 warning 内容不同，不要仅因数量也是 3 就忽略。

第二层证据是输出数量和终止时刻：

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

最终 `xtime` 应为 `2026-10-16_00:00:00`。5 和 9 都包含起报时刻的输出。若复用一个已有
案例目录，先识别旧文件；否则“数量正确”可能只是历史残留，并不能证明本次运行成功。

若希望一次完成两个阶段，可在干净案例中运行：

```bash
NTASKS=16 ./run_beijing_case.sh all
```

学习时仍建议分开执行，因为这样能明确失败发生在 GFS→init 还是 init→forecast。

## 为什么第一例冻结 SST

本案例设置 `config_sst_update=false`，因此起报时刻写入 init 的 SST 和海冰在 24 小时内
不从外部文件更新。这不等于“地表全部冻结”：陆面模式、近地层通量和大气照常演变。
一天教学预报先这样做，可以把初值问题与 surface update 问题分开。

后续周期更新会用 case 8 读取第 4 课的多个 `FILE:*`，生成 `sfc_update.nc`，再启用
surface stream 和 `config_sst_update=true`。有限区域则用 case 9 生成逐时次 LBC；它们是
后续计划，不是当前基线已经启用的功能。

## 常见失败从接口处排查

- `No mesh partition for NTASKS=N`：任务数与 `.part.N` 不匹配，不是网格文件损坏。
- 找不到 `FILE:<起报有效时刻>`：所选 `CASE_DIR` 的 `case.env`、start time 与 `FILE:*`
  不一致，或第 4 课的 ungrib 尚未完成。
- 初值时间与 start time 不同：同时核对 `xtime`、namelist 和 streams 输入文件名。
- 日志出现 CFL（库朗数，衡量一个时间步内信息跨越多少个网格尺度）、NaN 或速度爆炸：
  先核对网格对应的 dt 和初值，再考虑物理方案。
- 有 `.nc` 但没有 finished 标记：把它视为失败的残缺输出，不要进入后处理。

## 费曼检查

向一位 WRF 用户解释下面三个变化分别要重做什么：

1. 只换起报日期：重新 ungrib 并生成 init；同一网格的 static 和分区可复用。
2. 换 MPAS 网格：`FILE:*` 可复用，但 static、init 和网格分区必须匹配新网格。
3. 只把 MPI 从 16 改为 32：气象初值不变，但必须提供同网格的 `.part.32`。

如果能说明每个结论是由“资料时间、地理位置、cell 邻接关系”中的哪一项改变导致的，
就真正理解了 MPAS 初始化，而不是只会运行脚本。

## 参考

- [MPAS-A 官方真实资料初始化与运行](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
- [MPAS-A 官方 I/O 配置](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/configuring_io.html)
