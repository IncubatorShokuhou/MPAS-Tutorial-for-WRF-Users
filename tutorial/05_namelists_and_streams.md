# 第 5 课：把 MPAS 的 namelist、streams 和并行分区读明白

## 这一课为什么值得慢下来读

先做完第 3 课的网格和第 4 课的 `FILE:*`。这一课不跑模式，只读第 6 课将要生成的
四个配置文件。

WRF 用户第一次看 MPAS，常不知道一个参数该写进哪个文件。读完应能判断它属于计算方法、
文件读写、输出变量，还是 MPI 进程划分。

## 先分清三类配置文件

WRF 的大部分设置挤在 `namelist.input` 里。MPAS-A 把计算和文件读写拆开。

- **namelist**：Fortran 格式的参数文件，设置时间步、物理方案和预处理阶段等“怎么算”的
  问题；
- **streams**：XML 格式的输入输出配置，说明读哪个文件、写哪个文件、多久写一次；
- **变量清单（stream list）**：纯文本文件，列出某个输出文件中需要保存哪些变量。

沿用 WRF 的找法也行。计算参数去 namelist，输入输出文件去 streams，增减变量去清单。

本教程有两个 MPAS 可执行程序，它们各读一对配置文件。

| 程序 | 计算参数 | 输入输出设置 | 会生成什么 |
|---|---|---|---|
| `init_atmosphere_model` | `namelist.init_atmosphere` | `streams.init_atmosphere` | `static.nc` 或 `init.nc` |
| `atmosphere_model` | `namelist.atmosphere` | `streams.atmosphere` | 历史场、诊断场、重启文件 |

第 8 课还会看到 `grid_rotate/namelist.input`。那是网格旋转工具自己的参数文件，不属于
上面两个 MPAS 核心程序，别把它们混在一起。

## 一个输入输出流管什么

MPAS 把一组同时读入或写出的变量归在一个输入输出流（stream）里。下面这段设置的是初值
输入：模式冷启动时读取一次，之后不再重复读取。

```xml
<immutable_stream name="input"
                  type="input"
                  filename_template="x1.10242.init.nc"
                  input_interval="initial_only" />
```

`immutable_stream` 所包含的必需变量由源码中的变量登记表（Registry）固定。虽然必需变量
不能随意删，文件名和读写间隔仍可修改。

普通的 `<stream>` 更灵活，可以用 `<file>` 引一份变量清单，也可以用 `<var>` 单独
加减变量。诊断场的一段是这样。

```xml
<stream name="diagnostics"
        type="output"
        filename_template="diag.$Y-$M-$D_$h.$m.$s.nc"
        output_interval="3:00:00">
    <file name="stream_list.atmosphere.diagnostics"/>
</stream>
```

文件名中的 `$Y...$s` 会按模拟时刻替换成年、月、日、时、分、秒；输出哪些变量，由
`stream_list.atmosphere.diagnostics` 决定。修改 streams 不需要重新编译程序。

## MPI 进程数为什么要对应 `.part.N`

WRF 网格有规则的 `i,j` 下标，可以沿两个方向切成若干块。MPAS 网格没有这样的矩形
下标。它把每个网格单元（cell）看成一个节点，把相邻关系看成节点之间的连线，再交给
METIS 划分。

```text
grid/static/init 中的连接关系
             |
         graph.info          网格单元邻接图
             |
        METIS 划成 N 份
             |
    graph.info.part.N        每个网格单元分给哪个 MPI 进程
```

用 `mpiexec -n 16` 就必须有 `.part.16`。namelist 只写共同前缀。

```fortran
&decomposition
 config_block_decomp_file_prefix = 'x1.10242.graph.info.part.'
/
```

运行 `mpiexec -n 16` 时，MPAS 会在这个前缀后面自动补上 `16`，最后读取
`x1.10242.graph.info.part.16`。这里的数字表示 **MPI 进程数**，不是线程数、计算节点数，
也不是每个节点的核数。

第 6 课使用的官方网格包已经带有 `.part.16`。只有所需进程数没有对应分区文件时，才要
用 METIS 重新划分。静态地理资料插值采用串行运行，不需要 `.part.1`。

### 现场检查分区文件

可以在仓库根目录做一次只读检查。

```bash
CASE_DIR=work/beijing_240km_2026101500
ls -lh "$CASE_DIR/x1.10242.graph.info.part.16"
wc -l "$CASE_DIR/x1.10242.graph.info.part.16"
awk 'NR==1{lo=hi=$1} {if($1<lo)lo=$1; if($1>hi)hi=$1} \
     END{print "rank range:",lo,hi}' \
  "$CASE_DIR/x1.10242.graph.info.part.16"
```

真实输出压成三行。文件大小和权限位会随文件系统略有差别，行数和 rank 范围要对上。

```text
-rw-r----- ... 24K ... x1.10242.graph.info.part.16
10242 .../x1.10242.graph.info.part.16
rank range: 0 15
```

这次检查不会留下新文件。读者可以把 `NTASKS` 改成网格包已经提供的其他 N，但必须同时
选中对应的 `.part.N`；不要编辑分区文件中的整数来“制造”新分区，那会破坏 cell 的
负载分配和连续性。

## `namelist.init_atmosphere`：同一程序的两个阶段

`config_init_case` 是初始化任务编号，说明这次要制作哪类文件。

- `7`：从 GFS 等真实资料生成完整初值；
- `8`：生成海表温度（SST）和海冰的周期更新文件；
- `9`：生成有限区域的侧边界文件。

“真实资料初始化”不能一律写成任务 7。当前要做冷启动初值，用任务 7。
它只处理 `config_start_time` 指定的时刻；任务 8 和任务 9 才会从开始时刻一直处理到结束
时刻。

### 阶段 A：`grid.nc` 变成 `static.nc`

这一阶段读取 WPS_GEOG，把地形、土地利用、土壤类型等资料插值到每个 MPAS 网格单元。
按照官方要求，这一步只用一个 MPI 进程。配置中有三组内容值得留意。

- `dimensions` 中的五个垂直维数暂时都设为 1。这一步不创建大气层、土壤层或 GOCART
  气溶胶气候资料层，只需要给出合法的占位值；`config_gocartlevels` 表示这套气溶胶
  气候资料的垂直层数；
- `config_geog_data_path` 指向静态资料目录；其余 `*_data` 依次选择 MODIS/NOAH 土地利用、
  STATSGO 土壤分类、GMTED2010 地形、MODIS 植被比例和两类反照率资料；这些名称必须与
  WPS_GEOG 中实际安装的数据集匹配；
- `config_static_interp` 打开静态资料插值；
- `config_native_gwd_static` 计算 MPAS 原生网格所需的亚网格地形统计量；
- `config_native_gwd_gsl_static` 对应 GSL 重力波阻力方案所需的另一套地形统计，本例关闭；
- `vertical_grid`、`met_interp`、`input_sst`、`frac_seaice` 分别控制垂直网格、气象场插值、
  周期海温读取和海冰处理，这一步都不做。

下面只摘录本阶段最关键的设置，不能单独复制成完整 namelist。本课只读参数，不运行；
第 8 课会首次介绍并调用 `generate_beijing_vr_static.sh`，由它生成完整配置。

```fortran
&nhyd_model
 config_init_case = 7
/
&dimensions
 config_nvertlevels = 1
 config_nsoillevels = 1
 config_nfglevels = 1
 config_nfgsoillevels = 1
 config_gocartlevels = 1
/
&data_sources
 config_geog_data_path = '/path/to/WPS_GEOG/'
 config_landuse_data = 'MODIFIED_IGBP_MODIS_NOAH'
 config_soilcat_data = 'STATSGO'
 config_topo_data = 'GMTED2010'
 config_vegfrac_data = 'MODIS'
 config_albedo_data = 'MODIS'
 config_maxsnowalbedo_data = 'MODIS'
/
&preproc_stages
 config_static_interp = true
 config_native_gwd_static = true
 config_native_gwd_gsl_static = false
 config_vertical_grid = false
 config_met_interp = false
 config_input_sst = false
 config_frac_seaice = false
/
```

streams 里，网格输入和静态文件输出是这两段。官方模板里还有地表更新、侧边界等
条件输出；本阶段的开关不会启用它们。

```xml
<immutable_stream name="input" type="input"
                  filename_template="mesh.grid.nc"
                  input_interval="initial_only" />
<immutable_stream name="output" type="output"
                  filename_template="mesh.static.nc"
                  packages="initial_conds"
                  output_interval="initial_only" />
```

240 km 教学网格已经配有官方 `x1.10242.static.nc`，所以第 6 课会跳过阶段 A。第 8 课
把加密网格旋转到北京以后，网格单元的经纬度发生变化，那时才真正运行这一步。

### 当前基线已经有的文件

240 km 基线没有在本机重跑阶段 A。第 4 课的准备脚本直接解压了官方成果。
目录里是两个普通 NetCDF。

```text
work/beijing_240km_2026101500/
├── x1.10242.grid.nc     # 仅网格几何与拓扑，约 14 MiB
└── x1.10242.static.nc   # 同一网格加静态地理场，约 19 MiB
```

这两个文件不是软链接，也不是脚本临时配置。跑基线时不要修改它们；只换起报日期时可以
原样复用。若换成旋转后的北京网格，则必须从新的 `grid.nc` 生成新的 `static.nc`，不能
为了省时间把这里的 x1 static 改名冒充。

### 阶段 B：`static.nc + FILE:<起报有效时刻>` 变成 `init.nc`

先按用途把参数分成垂直层、资料来源和预处理开关三组。

- `config_nvertlevels=55` 和 `config_nsoillevels=4` 分别指定 MPAS 的大气质量层数和土壤
  层数；`config_nfglevels=38` 为气象初猜资料预留最多 38 个不同层次，必须不小于输入
  文件中的实际层次数。本例日志显示实际读到 34 层，所以 38 是容量，不是资料层数；
  `config_nfgsoillevels=4` 对应四层土壤资料；55 个质量层对应 56 个层界面；
- `config_gocartlevels=30` 为 GOCART 气溶胶气候资料预留 30 个垂直层；
- `config_met_prefix` 指定任务 7 所用气象初猜文件的前缀。`config_sfc_prefix` 是任务 8
  的 SST、海冰文件前缀；本阶段关闭了 `input_sst`，所以暂时不会读取。当前 Vtable 提供
  相对湿度 RH，因此设置 `config_use_spechumd=false`，让初始化程序据此计算水汽；
- `config_start_time` 指定起报有效时刻。任务 7 只处理一个时刻，所以
  `config_stop_time` 与它相同。`config_fg_interval=10800` 表示外部资料相隔 3 小时，
  主要在以后运行任务 8、任务 9 时使用；
- `config_ztop` 把模式顶设在约 30 km 高度。`config_hybrid_coordinate=true` 启用混合
  垂直坐标：低层随地形起伏，向上逐渐过渡为定高面；`config_hybrid_top_z` 指定完全转为
  定高面的高度；
- 预处理开关与阶段 A 相反：关闭静态插值和两类地形统计，打开垂直网格、气象插值和
  分数海冰处理。`config_frac_seaice` 使用较低的海冰阈值处理部分覆冰；它并不负责读取
  周期更新的 SST。

针对本例这套 GFS 和 Vtable，关键设置抄在下面。仍是节选，不能单独存成可运行的
namelist。完整文件以 `run_beijing_case.sh` 生成的版本为准。

```fortran
&nhyd_model
 config_init_case = 7
 config_start_time = '2026-10-15_00:00:00'
 config_stop_time  = '2026-10-15_00:00:00'
/
&dimensions
 config_nvertlevels = 55
 config_nsoillevels = 4
 config_nfglevels = 38
 config_nfgsoillevels = 4
 config_gocartlevels = 30
/
&data_sources
 config_met_prefix = 'FILE'
 config_sfc_prefix = 'FILE'
 config_fg_interval = 10800
 config_use_spechumd = false
/
&vertical_grid
 config_ztop = 30000.0
 config_hybrid_coordinate = true
 config_hybrid_top_z = 30000.0
/
&preproc_stages
 config_static_interp = false
 config_native_gwd_static = false
 config_native_gwd_gsl_static = false
 config_vertical_grid = true
 config_met_interp = true
 config_input_sst = false
 config_frac_seaice = true
/
```

如果换成 ERA5、另一种 GFS 产品或另一张 Vtable，不要照抄 `38/4`。先用第 4 课介绍的
`rd_intermediate` 检查中间文件，再从初始化日志中的 `Found ... levels in the
first-guess data` 确认实际层数；预留值不能小于它。

这一阶段的 streams 由官方静态文件读入、完整初值输出两段组成。下面仍是关键节选，实际
模板还保留了只在任务 8、任务 9 或其他开关启用时才生效的条件输出。

```xml
<immutable_stream name="input" type="input"
                  filename_template="x1.10242.static.nc"
                  input_interval="initial_only" />
<immutable_stream name="output" type="output"
                  filename_template="x1.10242.init.nc"
                  packages="initial_conds"
                  output_interval="initial_only" />
```

虽然第 4 课生成了九个 `FILE:*`，这里的任务 7 只按照 `config_start_time` 读取 GFS f000
对应的起报时刻文件。`config_stop_time`、`config_fg_interval` 和其余八个时次，要到
任务 8、任务 9 才真正用上。

第 6 课才会真正跑这一步，并给出终端输出、配置和新增文件。先记住输入输出。
`static.nc` 和起报时刻的 `FILE:*` 是输入，`init.nc` 是输出。日期和资料间隔来自
`case.env`，MPI 进程数由 `NTASKS` 决定。

## `namelist.atmosphere`：先把 240 km 教学算例跑稳

第 6 课实际运行的是准均匀 `x1.10242` 网格，北京 25 km 加密网格此时还没有制作完成。
先看最常用的几组设置。

- `nhyd_model` 设置动力大时间步、起报时刻和积分时长；
- `limited_area` 决定是否读取区域模式的侧边界；
- `decomposition` 指向第 3 课介绍的 MPI 分区文件前缀；
- `restart` 区分冷启动和断点续跑；
- `physics` 选择成套的微物理、积云、边界层和陆面方案，也控制是否从外部资料更新 SST
  和海冰。

本例做全球冷启动，不使用周期海表更新，物理方案选用程序自带的中尺度组合
`mesoscale_reference`。下面只列本例覆盖的关键项，不能拿来替代完整 namelist；实际运行
文件由 `run_beijing_case.sh` 在官方默认配置基础上生成。

```fortran
&nhyd_model
 config_dt = 1200.0
 config_start_time = '2026-10-15_00:00:00'
 config_run_duration = '1_00:00:00'
/
&limited_area
 config_apply_lbcs = false
/
&decomposition
 config_block_decomp_file_prefix = 'x1.10242.graph.info.part.'
/
&restart
 config_do_restart = false
/
&physics
 config_sst_update = false
 config_physics_suite = 'mesoscale_reference'
/
```

`config_dt=1200 s` 表示动力大步长为 20 分钟，24 小时共走 72 步。
`config_start_time` 必须与 `init.nc` 中记录模拟有效时刻的字符变量 `xtime` 相同；它的
作用类似 WRF 文件中的 `Times`。`config_run_duration` 的写法是
`[天数_]时:分:秒`。`config_sst_update=false` 只表示不从外部文件周期更新 SST 和海冰，
陆面与大气本身仍会正常演变。

`config_len_disp` 是 Smagorinsky 水平扩散和三维散度阻尼使用的水平长度尺度。在
MPAS 8.4.2 中，如果没有显式设置，或把它设为 0，程序会采用输入文件中的
`nominalMinDc`。本例会自动读到 240000 m，并写入日志，所以脚本没有再次写死。第 8 课
使用 25 km 变分辨率网格时，我们再讨论为什么必须核对这一项。

## `streams.atmosphere`：初值从哪儿读，结果往哪儿写

本例读一份初值，写出三类文件。时间间隔写在图里。

```text
x1.10242.init.nc ──读取──> atmosphere_model
                              |-- history，历史场，每 6 小时
                              |-- diagnostics，诊断场，每 3 小时
                              `-- restart，重启文件，每 24 小时
```

核心几段是这些。

```xml
<immutable_stream name="input" type="input"
                  filename_template="x1.10242.init.nc"
                  input_interval="initial_only" />

<stream name="output" type="output"
        filename_template="history.$Y-$M-$D_$h.$m.$s.nc"
        output_interval="6:00:00">
    <file name="stream_list.atmosphere.output"/>
</stream>

<stream name="diagnostics" type="output"
        filename_template="diag.$Y-$M-$D_$h.$m.$s.nc"
        output_interval="3:00:00">
    <file name="stream_list.atmosphere.diagnostics"/>
</stream>
```

重启文件默认每 `1_00:00:00`，也就是每 24 小时写一次。历史场和诊断场在起报时刻也会
写一份，所以 24 小时预报应得到 5 个 history、9 个 diagnostics，以及结束时刻的 1 个
restart。这里不能简单拿 `24/输出间隔` 来计算文件数。

第 6 课会展示这些模板展开后的真实文件名、数量和大小。这里只需分清：想改输出频率就改
streams，想改输出变量就改 stream list；两件事都不属于 namelist 的职责。

## PIO 设置不等于输出设置

`config_pio_num_iotasks` 设置参与读写的 MPI 进程数；设为 0 时，所有进程都参与。
`config_pio_stride` 设置这些读写进程在 MPI 进程序列中的间隔。小算例先采用下面的稳妥
设置。

```fortran
&io
 config_pio_num_iotasks = 0
 config_pio_stride = 1
/
```

专用读写进程数和间隔，主要用于大规模计算时的性能调优。它们不决定输出哪些变量、文件
叫什么或多久写一次；这些内容仍由 streams 控制。

## 运行脚本为什么会覆盖配置

第 6 课每次运行 `run_beijing_case.sh init` 或 `forecast`，都会重新生成 namelist 和
streams，并把默认 stream list 链接到案例目录。基线案例可以直接使用这套做法。若要做
敏感性试验，应另建案例目录，把配置和 stream list 都复制成普通文件，修改后直接用
`mpiexec` 启动 MPAS；再次调用运行脚本会覆盖这些改动。目前脚本还没有“只生成配置、不
启动模式”的选项。

如果继续展开完整的 `streams.*`，还会看到文件名里保留着 `x1.40962` 的 IAU、UGWP 等
条目。这些流都带有 `packages="..."` 条件，只有相应功能包启用时才会读写；当前
`x1.10242` 基线没有启用它们，因此不是漏改网格名，也不需要为它们准备文件。读 streams
时先看 `packages` 和 namelist 开关，再判断一个模板是否生效，不要见到陌生文件名就把
整段 XML 删除。

## 开跑前照着这张清单核对

1. 制作初值时：`static.nc`、起报时刻的 `FILE:*` 和 `config_start_time` 是否一致？
2. MPI：`mpiexec -n N` 是否存在同网格的 `.part.N`？
3. 初值：`nCells`、`nVertLevels`、`xtime` 和 `nominalMinDc` 是否符合设计？
4. 运行预报时：输入文件名是否正是刚生成的 `init.nc`？
5. namelist：时间步、积分时长、全球或区域、冷启动或重启等设置是否正确？
6. streams：输出间隔和变量清单是否满足需要？
7. 日志：程序是否明确完成，错误和严重错误的数量是否为 0？

## 试着用自己的话讲一遍

只把诊断场从每 3 小时改成每小时，改 `streams.atmosphere` 里的 `output_interval`。
计算方法没变。

MPI 从 16 改成 32 时，改 `output_interval` 没用，还要有 `.part.32`，告诉 MPAS
每个网格单元交给哪个进程。动力时间步从 1200 s 改成 600 s，改 namelist，那是积分设置。

## 参考

- [MPAS-A 官方 I/O 配置](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/configuring_io.html)
- [官方真实资料初始化与运行](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
- [Appendix A：初始化 namelist](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appA_init_namelist.html)
- [Appendix B：模式 namelist](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appB_model_namelist.html)
