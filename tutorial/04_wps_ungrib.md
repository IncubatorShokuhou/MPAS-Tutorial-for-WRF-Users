# 第 4 课：借用 WPS 的 `ungrib`，把 GFS 交给 MPAS

## MPAS 为什么还要用 WPS

做过 WRF 的读者，对 `ungrib.exe` 肯定不陌生。GFS 下载回来是 GRIB2 文件，先由
`ungrib.exe` 解码，再交给 `metgrid.exe`。到了 MPAS，这个开头没有变：MPAS 的初始化
程序也不直接读取 GRIB2，所以仍要借用 WPS 的 `ungrib.exe`。

不过，MPAS 只借用 WPS 的“解码”部分。下面四样东西要先认清：

- **`ungrib.exe`**：读取 GRIB/GRIB2，并写成 WPS 中间格式；
- **Vtable**：告诉 `ungrib.exe` 每个 GRIB 参数号该叫什么。例如温度写成 `TT`，风写成
  `UU`、`VV`。本例使用 GFS 0.25° pgrb2 产品，其中既有等压面场，也有地面和陆面场，
  因此选择 `Vtable.GFS`；
- **`GRIBFILE.AAA`**：`link_grib.csh` 为原始 GFS 文件建立的软链接。文件没有复制，只是
  换成了 `ungrib.exe` 认识的短名称；
- **WPS 中间格式**：`ungrib.exe` 的输出。文件里有变量、层次、有效时刻和 GFS 自己的
  经纬网信息，此时还没有插值到 MPAS 网格。

这一段处理可以画成：

```text
GFS GRIB2 --ungrib.exe + Vtable.GFS--> FILE:YYYY-MM-DD_HH
                                               |
                                      尚未插值到 MPAS 网格
```

用 WRF 的经验看，分岔点就在 `ungrib.exe` 后面。WRF 接着运行 `metgrid.exe`；MPAS 则
由 `init_atmosphere_model` 完成水平插值和初值制作。所以换一张 MPAS 网格，不必重新
运行 `ungrib.exe`；换了 GFS 起报时次或资料产品，通常就要重新运行。

本例不会调用 WPS 的另外两个程序。`geogrid.exe` 用来制作 WRF 的规则区域网格，
`metgrid.exe` 负责向 WRF 网格插值；MPAS 有自己的网格和初始化程序，用不上它们。

## 编译 WPS 前先检查环境

以下命令都在仓库根目录执行。编译 WPS 还要用到 `autoreconf` 和 Python 3；建立 GFS
软链接时要用 C shell。正式编译前，先把这些命令逐个检查一遍：

```bash
command -v gcc g++ gfortran autoreconf cmake curl git make python3 tar csh
```

### 这一步留下了什么

这是一次只读检查，不会生成文件。正常终端输出是一组可执行文件路径；路径可以因机器而异，
但不能缺行：

```text
/usr/bin/gcc
/usr/bin/g++
/usr/bin/gfortran
/usr/bin/autoreconf
/usr/bin/cmake
...
/usr/bin/tar
/usr/bin/csh
```

若有缺项，请安装相应软件或整理 `PATH`。编译器装在非标准位置时，使用安装脚本的
`--cc/--cxx/--fc` 参数；`csh` 则可通过环境变量 `CSH=/path/to/csh` 指定。

如果找不到 `csh`，请先安装，不能拿 Bash 直接运行 `link_grib.csh`。已经安装、但不在
`PATH` 中时，可以这样指定：

```bash
CSH=/path/to/csh ./prepare_beijing_case.sh
```

第 1 课若已经使用 `--with-wps`，下面这一步可以跳过：

```bash
./install_wps.sh -y
```

在默认安装中，本项目自己编译的 OpenMPI 和 netCDF 都放在 `local/io-stack`。换到另一台
机器后，可以用下面的完整命令重建：

```bash
./install_wps.sh -y -j "$(nproc)" \
  --mpi-prefix "$PWD/local/io-stack" \
  --netcdf-prefix "$PWD/local/io-stack" \
  --grib2-prefix "$PWD/local/grib2" \
  --prefix "$PWD/local/wps-4.6.0"
```

脚本会从源码编译 zlib、libpng、JasPer 和 WPS。几个依赖库会按 `-j` 指定的并行度编译。
WPS 4.6.0 的 Fortran 模块若并行编译容易互相抢占，因此脚本对 WPS 本身采用串行编译。
`ungrib.exe` 本来也是串行程序，运行时不要加 `mpirun`。

默认只编译 MPAS 会用到的 `ungrib.exe` 和检查工具，不会顺带编译一套 WRF。只有同时还要
运行 WRF 的 `geogrid.exe`、`metgrid.exe`，才需要加入
`--full-wps --wrf-dir /path/to/WRF`。所有选项可用 `./install_wps.sh --help` 查看。

### 这一步留下了什么

安装成功时，终端最后会出现类似下面几行：

```text
WPS installation complete: /path/to/MPAS_tutorial/local/wps-4.6.0
Load this installation with:
  export PATH="/path/to/MPAS_tutorial/local/wps-4.6.0/bin:$PATH"
```

仓库中的安装结果可概括为。

```text
local/wps-4.6.0/
└── bin/
    ├── ungrib                 # 普通可执行文件，约 714 KiB
    ├── ungrib.exe -> ungrib  # 软链接，兼容 WPS 的传统名称
    ├── rd_intermediate        # 普通可执行文件，检查中间格式
    ├── link_grib.csh -> ...   # 指向 WPS 源码脚本的软链接
    └── ...                    # 省略本课用不到的辅助程序

local/grib2/                   # zlib、libpng、JasPer 的头文件和库
src/WPS-4.6.0/                # WPS 4.6.0 源码树
build/、downloads/             # 可重建的编译目录和源码缓存，可能较大
```

换机器时通常只需要改编译器路径、安装前缀和 `-j`；不要手工修改 `local/wps-4.6.0/bin`
中的二进制文件。若终端没有打印 `WPS installation complete`，即使目录中残留了旧的
`ungrib.exe`，也不能据此断定这次编译成功。

## 本例用哪一批 GFS

本课使用共享盘中一批完整的 GFS 起报资料：

- 起报时刻：2026-10-15 00 UTC；
- 输入：`f000, f003, ..., f024`，共 9 个文件；`f000` 是起报时刻，`f024` 是第 24 小时；
- 有效时段：2026-10-15 00 UTC 至 2026-10-16 00 UTC；
- 间隔：3 小时，即 10800 秒；
- 工作目录：`work/beijing_240km_2026101500`。

后面的命令都按这批资料来写。脚本带有 2026-10-15 这一教学默认值，也允许用参数覆盖。
准备脚本会把开始时刻、结束时刻、资料间隔和 WPS_GEOG 路径写入案例目录中的 `case.env`，
第 6 课运行时还会读取它。

如果换一个起报日期，最好另建一个案例目录，并让资料准备、`ungrib.exe` 和模式运行都
使用这个新目录。仅仅修改 namelist，目录里的 `FILE:*` 仍是旧日期，前后就对不上了。

## 建立 GFS 链接，写好 `namelist.wps`

运行：

```bash
./prepare_beijing_case.sh
```

脚本先下载并解压官方 240 km 网格包，再检查 WPS 程序、GFS 目录和九个 GFS 文件，最后
准备 `GRIBFILE.*`、`Vtable`、`ungrib.exe` 和一份最简 `namelist.wps`。所以即使后面的
GFS 检查失败，`downloads/` 和案例目录中也可能已经留下网格文件；修正资料路径后可以复用。

### 这一步留下了什么

脚本本身的终端回显很短：

```text
Prepared /path/to/MPAS_tutorial/work/beijing_240km_2026101500
Next: cd '/path/to/MPAS_tutorial/work/beijing_240km_2026101500' && ./ungrib.exe
```

真正重要的是目录。以下只列关键文件，不展开全部分区文件：

```text
work/beijing_240km_2026101500/
├── GRIBFILE.AAA -> /eds/shared/.../gfs.t00z.pgrb2.0p25.f000  # 软链接
├── ...
├── GRIBFILE.AAI -> /eds/shared/.../gfs.t00z.pgrb2.0p25.f024  # 软链接
├── Vtable -> /path/to/MPAS_tutorial/src/WPS-4.6.0/.../Vtable.GFS       # 软链接
├── ungrib.exe -> /path/to/MPAS_tutorial/local/wps-4.6.0/bin/ungrib    # 软链接
├── namelist.wps                         # 普通文本；脚本重写
├── case.env                             # 普通文本；脚本重写
├── x1.10242.grid.nc                     # 普通 NetCDF，约 14 MiB
├── x1.10242.static.nc                   # 普通 NetCDF，约 19 MiB
├── x1.10242.graph.info                  # 普通文本，约 551 KiB
└── x1.10242.graph.info.part.16          # 普通文本，约 24 KiB
```

`GRIBFILE.*` 只有链接本身，不是九份 GFS 副本；删掉链接不会删除共享盘原数据，反过来更
不能去修改或删除链接指向的共享文件。`namelist.wps` 和 `case.env` 是脚本生成物，再次运行
脚本会覆盖它们。换日期、起报时次、时长或目录时，应使用 `--date`、`--cycle`、
`--forecast-hours`、`--interval-hours`、`--case-dir` 等参数，不要先手改这两个生成文件。

`case.env` 保存后续脚本要复用的元数据。按当前版本脚本重新准备本例后，完整内容如下；
最前面的两个路径会按你的仓库位置自动填写：

```text
export MPAS_TUTORIAL_ROOT=/path/to/MPAS_tutorial
export CASE_DIR=/path/to/MPAS_tutorial/work/beijing_240km_2026101500
export DATE=20261015
export CYCLE=00
export START_TIME=2026-10-15_00:00:00
export STOP_TIME=2026-10-16_00:00:00
export FORECAST_HOURS=24
export INTERVAL_HOURS=3
export WPS_GEOG=/eds/shared/dm/WPS_GEOG
```

这两个路径是绝对路径，所以换机器后应重新运行准备脚本，让它生成适合新目录的
`case.env`，不要把旧文件原样搬过去。

重跑准备脚本时，它还会重新解压官方包，覆盖同名的 grid、static、graph 和分区文件，并
重建输入链接与两份配置；但它**不会清理**旧的 `FILE:*`、`init.nc`、history、diag 或
日志。换日期时务必把日期写进新目录名，例如：

```bash
DATE=20261016
./prepare_beijing_case.sh --date "$DATE" --cycle 00 \
  --forecast-hours 24 --interval-hours 3 \
  --case-dir "$PWD/work/beijing_240km_${DATE}00"
```

只有共享盘确实存在该时次 GFS 时，这个示例才会成功。自定义时还应让
`--forecast-hours` 能被 `--interval-hours` 整除；否则结束时刻没有对应的 `FILE:*`，
后续验收会出现“时间写到了，资料却没到”的断裂。

先别急着运行。花半分钟看一眼输入是否齐全：

```bash
find work/beijing_240km_2026101500 -maxdepth 1 \
  -type l -name 'GRIBFILE.*' | wc -l
readlink work/beijing_240km_2026101500/Vtable
sed -n '1,40p' work/beijing_240km_2026101500/namelist.wps
```

三个命令的输出依次是链接数、Vtable 的绝对目标路径和 namelist 内容。前两项应类似。

```text
9
/path/to/MPAS_tutorial/src/WPS-4.6.0/ungrib/Variable_Tables/Vtable.GFS
```

`namelist.wps` 的内容应与下面一致：

```fortran
&share
 start_date = '2026-10-15_00:00:00'
 end_date = '2026-10-16_00:00:00'
 interval_seconds = 10800
/
&ungrib
 out_format = 'WPS'
 prefix = 'FILE'
/
```

`start_date` 和 `end_date` 给出要处理的有效时刻范围；`interval_seconds=10800` 表示资料
每 3 小时一份；`prefix='FILE'` 决定输出文件以 `FILE:` 开头。这个前缀必须与下一课的
`config_met_prefix='FILE'` 相同。`case.env` 也保存了这组时间信息，后面制作初值和运行
预报时就不必再手抄一次，少一个写错日期的机会。

如果手工操作，无非是把九个 GFS 文件按时间顺序交给 `link_grib.csh`，把
`Vtable.GFS` 链接成固定名称 `Vtable`，再写好上面的 namelist。这里推荐使用脚本，因为
通配符很容易把 `.tmp` 文件也带进去，或者悄悄漏掉一个预报时次。

## 运行 `ungrib.exe`

输入已经验收后再执行：

```bash
cd work/beijing_240km_2026101500
./ungrib.exe
ls -1 FILE:*
cd ../..
```

运行时，主要时间花在读取九个 0.25°全球文件上。紧接着的 `ls` 应列出：

```text
FILE:2026-10-15_00
FILE:2026-10-15_03
...
FILE:2026-10-16_00
```

### 这一步留下了什么

`ungrib.exe` 的详细信息写进 `logfile.log`，终端不一定滚动很多内容。省略每行开头的时间戳
后，日志末尾的关键两行是：

```text
****  Done deleting temporary files.
*** Successful completion of program ungrib.exe ***
```

案例目录新增的 `FILE:*` 和 `logfile.log` 都是普通文件：

```text
work/beijing_240km_2026101500/
├── FILE:2026-10-15_00    # 普通二进制中间文件，约 781 MiB
├── FILE:2026-10-15_03    # 普通二进制中间文件，约 781 MiB
├── ...
├── FILE:2026-10-16_00    # 普通二进制中间文件，约 781 MiB
└── logfile.log           # 普通文本日志，实测约 260 KiB
```

九个 `FILE:*` 实测合计约 6.9 GiB，是本章最大的新增内容。它们是 **WPS intermediate
二进制格式**。不要用 `ncdump`，通用的 `file` 命令也可能把它误认成别的
格式，内容核验应使用下文的 `rd_intermediate`。它们不能用文本编辑器修改；日期、变量或
Vtable 选错时，应修正输入后重新运行 `ungrib.exe`。磁盘紧张时可以删除 `FILE:*` 后重建，
但不要把 `GRIBFILE.*` 的软链接大小误认为原始 GFS 的实际占用。

## 怎样确认 `ungrib.exe` 真正做对了

不要只看命令有没有返回。先检查日志中的成功标记，再数一遍时次：

```bash
CASE_DIR=work/beijing_240km_2026101500
grep 'Successful completion of program ungrib.exe' "$CASE_DIR/logfile.log"
find "$CASE_DIR" -maxdepth 1 -type f -name 'FILE:*' | sort
test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'FILE:*' | wc -l)" -eq 9
```

文件名齐全还不够，还要看看中间文件里到底有什么。下面的检查工具会顺序读完整个文件，
因此可能要等一会儿。检查结果写入案例目录，之后查找字段会方便一些：

```bash
local/wps-4.6.0/bin/rd_intermediate \
  "$CASE_DIR/FILE:2026-10-15_00" \
  > "$CASE_DIR/intermediate_inventory.txt"
grep -m 1 -A 10 '^FIELD = TT$' "$CASE_DIR/intermediate_inventory.txt"
grep -E '^FIELD = (TT|UU|VV|RH|PSFC|PMSL|SKINTEMP|SM000010|ST000010)$' \
  "$CASE_DIR/intermediate_inventory.txt" | sort -u
```

### 这一步留下了什么

`rd_intermediate` 不修改 `FILE:*`，只新增普通文本
`intermediate_inventory.txt`。其中一段真实输出如下。

```text
FIELD = TT
UNITS = K DESCRIPTION = Temperature
DATE = 2026-10-15_00:00:00 FCST = 0.000000
SOURCE = NCEP GFS Analysis
LEVEL = 200100.000000
I,J DIMS = 1440, 721
IPROJ = 0  PROJECTION = LAT LON
  REF_X, REF_Y = 1.000000, 1.000000
  REF_LAT, REF_LON = 90.000000, 0.000000
  DLAT, DLON = -0.250000, 0.250000
  EARTH_RADIUS = 6371.229492
```

第二条 `grep` 最后应列出九类关键字段；排序后的样子如下。

```text
FIELD = PMSL
FIELD = PSFC
FIELD = RH
FIELD = SKINTEMP
FIELD = SM000010
FIELD = ST000010
FIELD = TT
FIELD = UU
FIELD = VV
```

这份字段清单只是可删除、可重建的检查报告。需要关注的是日期、网格尺寸、层次和字段名；
如果缺字段，应回到 GRIB 产品和 Vtable 这一层处理，不能靠改清单或二进制 `FILE:*` 补上。

本例应显示规则经纬网 `I,J DIMS = 1440,721`、`DLAT/DLON = -0.25/0.25`，有效时刻应为
2026-10-15 00。高空的风、温、湿，地面气压和陆面变量也应齐全。即使九个文件一个不少，
只要缺少制作初值所需的字段，也不能继续。

第 6 课制作起报初值时，只会读取 `FILE:2026-10-15_00`。其余八个时次
留给后续的海表温度（SST）、海冰更新和有限区域侧边界。第 5 课会说明这些任务分别怎样
设置。现在一次解码齐全，是为了以后接着做时不用返工。

## 出错时从哪里查起

- 没有 `GRIBFILE.*`：检查 GFS 路径、文件名和 `link_grib.csh`；后者需要 csh 或 tcsh。
- 缺少某个 `FILE:*`：检查对应的预报时效、`start_date/end_date` 和 `interval_seconds`。
- 日志报告未知/缺失字段：检查 GFS 产品是否真是 0.25° pgrb2，以及 Vtable 是否匹配。
- GRIB2 解码失败：先检查本项目的 JasPer、libpng 和 zlib，不要先怀疑 MPAS 网格。

## 试着用自己的话讲一遍

不用背术语，试着回答：为什么把 240 km 网格换成 25 km 网格以后，这些 `FILE:*` 仍可
继续使用？

沿着数据去向讲最直接：`ungrib.exe` 的输出仍在 GFS 经纬网上，下一步才会插值到 MPAS
网格。再分别假设“只换网格”和“只换起报时间”，答案自然就出来了。

## 参考

- [WPS 官方用户指南：Ungrib](https://www2.mmm.ucar.edu/wrf/site/documentation/users_guide/wps.html)
- [MPAS-A 官方真实资料初始化流程](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
