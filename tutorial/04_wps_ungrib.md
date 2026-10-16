# 第 4 课：用 WPS `ungrib` 为 MPAS 解码 GFS

## 本课只解决一个问题

GFS 文件采用 GRIB2 格式，而 MPAS-A 初始化程序不直接读取 GRIB2。画数据流之前先定义
其中的四个组件：

- **`ungrib.exe`**：WPS 中负责解码 GRIB/GRIB2 的程序，本课把它当作格式翻译器；
- **Vtable**：GRIB 参数号到 `TT`、`UU`、`VV`、`RH`、`PSFC` 等字段名的翻译表，本案例
  的 GFS 0.25° pressure-level 产品使用 `Vtable.GFS`；
- **`GRIBFILE.AAA`**：`link_grib.csh` 为原始 GRIB2 文件建立的短名称软链接，原数据
  不会被复制；
- **WPS intermediate**：`ungrib.exe` 的输出格式，保存字段、层次、有效时刻和原始
  经纬网描述，但还不知道最终 MPAS 网格。

于是本课的“翻译”过程是：

```text
GFS GRIB2 --ungrib.exe + Vtable.GFS--> FILE:YYYY-MM-DD_HH
                                               |
                                      尚未插值到 MPAS 网格
```

把它类比成 WRF 最容易理解：WRF 和 MPAS 都可以使用 `ungrib.exe`；区别出现在下一步。
WRF 用 `metgrid.exe`，MPAS 用 `init_atmosphere_model`。因此，换一张 MPAS 网格不需要
重新 ungrib，但换 GFS 时次或产品通常需要。

WPS 的另外两个程序不参与本案例：`geogrid.exe` 为 WRF 定义规则 domain，
`metgrid.exe` 向 WRF 网格插值；MPAS 都不调用它们。

## 前置条件与 WPS 安装

以下命令均从仓库根目录运行。WPS 构建还需要 `autoreconf` 和 Python 3；准备 GFS 链接时
需要 C shell。长时间编译前先检查所有换机依赖：

```bash
command -v gcc g++ gfortran autoreconf cmake curl git make python3 tar csh
```

若找不到 csh，应先安装它，不能改用 Bash 执行 `link_grib.csh`；若 csh 不在 `PATH`，可用
`CSH=/path/to/csh ./prepare_beijing_case.sh` 指定。若第 1 课已经使用 `--with-wps`，可跳过
安装：

```bash
./install_wps.sh -y
```

换机时，项目自编译的 OpenMPI 和 netCDF 都位于统一前缀 `local/io-stack`：

```bash
./install_wps.sh -y -j "$(nproc)" \
  --mpi-prefix "$PWD/local/io-stack" \
  --netcdf-prefix "$PWD/local/io-stack" \
  --grib2-prefix "$PWD/local/grib2" \
  --prefix "$PWD/local/wps-4.6.0"
```

脚本从源码构建 zlib、libpng、JasPer 和 WPS。依赖库使用请求的并行度；WPS 4.6.0
的 Fortran module 目标存在并行竞态，所以脚本只把 WPS 自身串行编译。`ungrib.exe`
也是串行程序，运行它时不要加 `mpirun`。

默认安装只构建 MPAS 所需的 ungrib 与检查工具，不会为此额外编译 WRF。只有还要运行
WRF 的 geogrid/metgrid 时，才使用 `--full-wps --wrf-dir /path/to/WRF`；全部选项可用
`./install_wps.sh --help` 查看。

## 定义本教程的固定基线

本课使用共享盘中的一个完整 GFS cycle：

- cycle：2026-10-15 00 UTC；
- 输入：`f000, f003, ..., f024`，共 9 个文件；
- 有效时段：2026-10-15 00 UTC 至 2026-10-16 00 UTC；
- 间隔：3 小时，即 10800 秒；
- 工作目录：`work/beijing_240km_2026101500`。

后文命令均使用这个默认基线，但脚本并未把日期写死：准备脚本把开始、结束、资料间隔和
WPS_GEOG 路径写入案例目录的 `case.env`，第 6 课的运行脚本会读取它。换日期时必须使用
新的案例目录，并让准备、ungrib 和运行三个步骤指向同一目录；只改 namelist 还不够。

## 准备 GRIB 链接与 `namelist.wps`

运行：

```bash
./prepare_beijing_case.sh
```

脚本会检查九个 GFS 文件、下载后续需要的官方 240 km 网格包，并在案例目录中创建
`GRIBFILE.*`、`Vtable`、`ungrib.exe` 和最小 `namelist.wps`。先验收输入，而不是立刻
运行程序：

```bash
find work/beijing_240km_2026101500 -maxdepth 1 \
  -type l -name 'GRIBFILE.*' | wc -l
readlink work/beijing_240km_2026101500/Vtable
sed -n '1,40p' work/beijing_240km_2026101500/namelist.wps
```

第一个命令应输出 `9`。namelist 应等价于：

```fortran
&share
 start_date = '2026-10-15_00:00:00'
 end_date   = '2026-10-16_00:00:00'
 interval_seconds = 10800
/
&ungrib
 out_format = 'WPS'
 prefix = 'FILE'
/
```

`start_date/end_date` 是需要处理的**有效时刻范围**，`interval_seconds` 是相邻输入时次
间隔，`prefix` 决定输出名，也必须与下一课的 `config_met_prefix='FILE'` 对上。
`case.env` 保存相同的时间元数据，避免初始化和预报阶段各写一套互相矛盾的日期。

手工流程的本质只是：把九个 GFS 文件按时间顺序交给 `link_grib.csh`，把
`Vtable.GFS` 链接为固定名称 `Vtable`，再写上面的 namelist。这里优先使用脚本，是为了
避免 glob 混入 `.tmp` 文件或漏掉某个时次。

## 运行 `ungrib.exe`

输入已经验收后再执行：

```bash
cd work/beijing_240km_2026101500
./ungrib.exe
cd ../..
```

运行期间最耗时的是读九个 0.25° 全球文件。完成后应得到：

```text
FILE:2026-10-15_00
FILE:2026-10-15_03
...
FILE:2026-10-16_00
```

## 用证据验收，而不是只看退出码

先确认程序明确报告成功，并且时次不缺：

```bash
CASE_DIR=work/beijing_240km_2026101500
grep 'Successful completion of program ungrib.exe' "$CASE_DIR/logfile.log"
find "$CASE_DIR" -maxdepth 1 -type f -name 'FILE:*' | sort
test "$(find "$CASE_DIR" -maxdepth 1 -type f -name 'FILE:*' | wc -l)" -eq 9
```

还要检查 intermediate 内部，而不只是文件名。下面的工具会顺序读取整个大文件，可能
需要一些时间；输出写进案例目录便于搜索：

```bash
local/wps-4.6.0/bin/rd_intermediate \
  "$CASE_DIR/FILE:2026-10-15_00" \
  > "$CASE_DIR/intermediate_inventory.txt"
grep -m 1 -A 10 'FIELD = TT' "$CASE_DIR/intermediate_inventory.txt"
grep -E '^FIELD = (TT|UU|VV|RH|PSFC|PMSL|SKINTEMP|SM000010|ST000010)' \
  "$CASE_DIR/intermediate_inventory.txt" | sort -u
```

本案例应显示规则经纬网 `I,J DIMS = 1440,721`、`DLAT/DLON = -0.25/0.25`、正确的
2026-10-15 00 有效时刻，并包含高空风温湿、地面气压以及陆面字段。若只有九个文件名，
却缺少初始化所需字段，仍然不能进入下一步。

注意：第 6 课生成起报初值时，只读取 `FILE:2026-10-15_00`。其余八个时次是后续制作
SST/海冰更新或有限区域侧边界时使用的；第 5 课再给这些初始化任务编号。现在全部解码，
是为了建立完整案例。

## 常见失败按数据流定位

- 没有 `GRIBFILE.*`：检查 GFS 路径、文件名和 `link_grib.csh`；后者需要 csh/tcsh。
- 缺某个 `FILE:*`：检查对应 f-hour、`start_date/end_date` 和 `interval_seconds`。
- 日志报告未知/缺失字段：检查 GFS 产品是否真是 0.25° pgrb2，以及 Vtable 是否匹配。
- GRIB2 解码失败：检查本项目的 JasPer、libpng 和 zlib，而不是先怀疑 MPAS 网格。

## 费曼检查

试着不用术语解释：为什么把 240 km 网格换成 25 km 网格可以复用这些 `FILE:*`？

答案应包含两层意思：`ungrib` 只翻译 GFS，输出仍携带 GFS 自己的经纬网；真正把资料
放到 MPAS cell 上的是下一阶段。因此，换 MPAS 网格不用重新翻译 GFS，换起报 cycle
却必须生成一套新 `FILE:*`。

## 参考

- [WPS 官方用户指南：Ungrib](https://www2.mmm.ucar.edu/wrf/site/documentation/users_guide/wps.html)
- [MPAS-A 官方真实资料初始化流程](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
