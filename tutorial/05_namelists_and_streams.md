# 第 5 课：读懂 MPAS namelist、streams 与并行分区

## 本课前置与产物

先完成第 3 课的网格解剖和第 4 课的 `FILE:*` 解码。本课不运行模式，而是读懂第 6 课
即将自动生成的四个配置文件；学完后，你应能从一个参数判断它控制计算、文件管道、变量
清单还是 MPI 分工。

## 先建立控制文件的心智模型

WRF 用户容易把所有设置都去 `namelist.input` 中找。MPAS-A 把“计算方法”和“文件读写”
分开：

- **namelist**：Fortran namelist，决定怎么算，例如时间步、物理套件和预处理阶段；
- **streams**：XML 文件，决定从哪个文件读、向哪个文件写、多久写一次；
- **stream list**：纯文本变量清单，决定可修改输出流中包含哪些变量。

一句话记忆：**namelist 是算法开关，streams 是文件管道，stream list 是装箱清单。**

本教程有两个 MPAS 可执行程序，它们各读一对配置文件：

| 程序 | 计算配置 | I/O 配置 | 本教程产物 |
|---|---|---|---|
| `init_atmosphere_model` | `namelist.init_atmosphere` | `streams.init_atmosphere` | `static.nc` 或 `init.nc` |
| `atmosphere_model` | `namelist.atmosphere` | `streams.atmosphere` | history、diagnostics、restart |

第 8 课还会使用 `grid_rotate/namelist.input`，但那是独立网格工具的配置，不要与上述两个
模式 core 的 namelist 混为一谈。

## `streams` 中的“流”是什么

一个 **stream** 是一起读或写的一组 MPAS 变量。下面这个输入流表示：仅在冷启动时，
从指定文件读取一次模式必需的初值。

```xml
<immutable_stream name="input"
                  type="input"
                  filename_template="x1.10242.init.nc"
                  input_interval="initial_only" />
```

`immutable_stream` 的必需字段集合由源码 Registry（MPAS 的变量与配置登记表）固定，但
文件名和读写间隔仍可修改。
普通 `<stream>` 的变量集合也可在运行时用 `<file>` 或 `<var>` 修改。例如：

```xml
<stream name="diagnostics"
        type="output"
        filename_template="diag.$Y-$M-$D_$h.$m.$s.nc"
        output_interval="3:00:00">
    <file name="stream_list.atmosphere.diagnostics"/>
</stream>
```

这里 `$Y...$s` 按模拟时刻展开；变量清单来自
`stream_list.atmosphere.diagnostics`。修改 streams 不需要重新编译。

## `graph.info.part.N` 先定义再使用

MPAS cell 没有规则的 `i,j` 矩形块，因此 MPI 不能像 WRF 那样直接沿两个数组方向切分。
把每个 cell 看成图节点、相邻关系看成图的边：

```text
grid/static/init 中的连接关系
             |
         graph.info          cell 邻接图
             |
        METIS 划成 N 份
             |
    graph.info.part.N        每个 cell 属于哪个 MPI rank
```

用 `mpiexec -n 16` 就必须有 `.part.16`。namelist 只写共同前缀：

```fortran
&decomposition
 config_block_decomp_file_prefix = 'x1.10242.graph.info.part.'
/
```

MPAS 根据本次 MPI task 数自动追加 `16`。文件后缀表示 **MPI 进程数**，不是线程数、节点
数或每节点核数。第 6 课使用的官方网格包已经提供 `.part.16`；只有缺少所需 N 时才用
METIS 重新划分。串行静态插值只有一个 task，不需要 `.part.1`。

## `namelist.init_atmosphere`：同一程序的两个阶段

`config_init_case` 说明要制作哪类文件：

- `7`：从 GFS 等真实资料生成完整初值；
- `8`：生成 SST 和海冰的周期更新文件；
- `9`：生成有限区域的侧边界文件。

所以“真实资料一律使用 case 7”并不准确；**当前生成冷启动初值的步骤**使用 case 7。
case 7 只处理 `config_start_time`，而 case 8/9 才会遍历 start 到 stop 的多个时次。

### 阶段 A：`grid.nc` 变成 `static.nc`

这一阶段把 WPS_GEOG 的地形、土地利用、土壤类型等贴到每个 MPAS cell 上。官方要求
只用一个 MPI task。先定义即将看到的三组设置：

- `dimensions` 中五个垂直维数暂设为 1，因为这里不创建大气、土壤或 GOCART 气溶胶
  垂直层，只需合法占位；其中 `config_gocartlevels` 正是气溶胶气候资料的垂直维数；
- `config_geog_data_path` 指向静态资料目录；其余 `*_data` 依次选择 MODIS/NOAH 土地利用、
  STATSGO 土壤分类、GMTED2010 地形、MODIS 植被比例和两类反照率资料；这些名称必须与
  WPS_GEOG 中实际安装的数据集匹配；
- `config_static_interp` 打开静态插值，`config_native_gwd_static` 打开原生 MPAS 网格上的
  亚网格地形统计；`config_native_gwd_gsl_static` 是另一套 GSL 地形拖曳统计，本基线关闭。
  `vertical_grid`、`met_interp`、`input_sst`、`frac_seaice` 分别控制建立垂直网格、插值
  气象初猜、读取周期 SST 和处理海冰，本阶段全部关闭。

因此关键设置必须完整成对关闭/打开：

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

对应 streams 必须是：

```xml
<immutable_stream name="input" type="input"
                  filename_template="mesh.grid.nc"
                  input_interval="initial_only" />
<immutable_stream name="output" type="output"
                  filename_template="mesh.static.nc"
                  packages="initial_conds"
                  output_interval="initial_only" />
```

240 km 基线直接下载官方 `x1.10242.static.nc`，所以第 6 课会跳过阶段 A。第 8 课旋转
北京加密网格后，地理位置发生变化，才会实际执行本阶段。

### 阶段 B：`static.nc + FILE:<起报有效时刻>` 变成 `init.nc`

先把这一阶段的新键翻译成人话：

- `config_nvertlevels=55` 和 `config_nsoillevels=4` 是输出模式的质量层与土壤层；
  `config_nfglevels=38` 和 `config_nfgsoillevels=4` 是当前 GFS intermediate 中的
  first-guess records 与土壤层。38 包含等压层及 surface/sea-level 特殊层，不等于
  38 个等压面；55 个质量层对应 56 个层界面；
- `config_met_prefix` 指向 case 7 的气象初猜。`config_sfc_prefix` 是 case 8 的 SST/海冰
  输入前缀，本阶段关闭 `input_sst`，所以不会读取它；`config_use_spechumd=false` 表示
  当前 Vtable 提供 RH，由初始化器推导水汽；
- `config_start_time` 选择要读取的起报有效时刻；case 7 不遍历时间，所以
  `config_stop_time` 保持同一时刻。`config_fg_interval=10800` 描述外部资料相隔 3 小时，
  主要供之后遍历多时次的 case 8/9 使用；
- `config_ztop` 是 30 km 模式顶。`config_hybrid_coordinate=true` 启用地形跟随到定高面的
  混合垂直坐标，`config_hybrid_top_z` 指定坐标面完全转为定高面的高度；
- 预处理开关与阶段 A 相反：关闭静态插值和两类地形统计，打开垂直网格、气象插值和
  分数海冰处理。`config_frac_seaice` 采用更低海冰阈值处理部分覆冰，而不是读取周期 SST。

当前 GFS/Vtable 组合因此使用：

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

若换 ERA5、不同 GFS 产品或不同 Vtable，不能盲抄 `38/4`，应先用第 4 课的
`rd_intermediate` 和初始化日志核对。

这一阶段的 streams 把 official static 当输入，把完整初值当输出：

```xml
<immutable_stream name="input" type="input"
                  filename_template="x1.10242.static.nc"
                  input_interval="initial_only" />
<immutable_stream name="output" type="output"
                  filename_template="x1.10242.init.nc"
                  packages="initial_conds"
                  output_interval="initial_only" />
```

虽然第 4 课生成九个 `FILE:*`，case 7 在这里仅按 `config_start_time` 读取来自 GFS f000
的起报有效时刻文件；`config_stop_time`、
`config_fg_interval` 和其余时次将在 case 8/9 才发挥作用。

## `namelist.atmosphere`：先掌握 240 km 基线

第 6 课真正运行的是准均匀 `x1.10242` 网格，而不是尚未生成的北京 25 km 网格。最先
理解下面几组。`nhyd_model` 给出动力大时间步、起报时刻和积分时长；`limited_area`
决定是否读取侧边界；`decomposition` 指向第 3 课定义的 MPI 分区前缀；`restart` 区分
冷启动和接续积分；`physics` 选择一组相互匹配的微物理、积云、边界层和陆面方案，并
决定是否从外部文件更新 SST/海冰。当前是全球冷启动且没有周期海表更新，并选择随版本
提供的 `mesoscale_reference` 中尺度物理套件，因此配置为：

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

`config_dt=1200 s` 使 24 小时共有 72 个动力大步。`config_start_time` 必须等于
`init.nc` 的 `xtime`；run duration 格式为 `[天数_]时:分:秒`。`config_sst_update=false`
只表示没有周期 SST/海冰文件；陆面和大气仍会随积分演变。

`config_len_disp` 是最小 cell-to-cell 距离所代表的耗散长度，用于 Smagorinsky 混合和
三维散度阻尼。MPAS 8.4.2 在它未显式设置或为 0 时，从输入文件的 `nominalMinDc` 读取；
基线会自动得到 240000 m，并在日志中报告。因此当前脚本没有再硬编码它。第 8 课使用
25 km 变分辨率网格时，再解释为何要检查或显式指定这一项。

## `streams.atmosphere`：输入与三个输出

基线文件管道是：

```text
x1.10242.init.nc --input--> atmosphere_model
                              |-- history，每 6 小时
                              |-- diagnostics，每 3 小时
                              `-- restart，每 24 小时
```

核心设置如下：

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

restart 流默认每 `1_00:00:00` 写一次。输出包含起报时刻，所以 24 小时案例预期得到 5 个
history、9 个 diagnostics 和结束时刻的 1 个 restart，而不是简单的 `24/间隔` 个。

## PIO 设置不等于输出设置

`config_pio_num_iotasks` 是专职/参与 I/O 的 MPI task 数，0 表示让所有 tasks 参与；
`config_pio_stride` 是 I/O task 在 rank 序列中的间隔。小案例采用安全默认：

```fortran
&io
 config_pio_num_iotasks = 0
 config_pio_stride = 1
/
```

专用 I/O tasks 和 stride 是大规模性能调参；它们不决定变量清单、文件名或输出频率，
后者全部在 streams。

## 脚本生成配置时要注意覆盖

第 6 课的 `run_beijing_case.sh init` 和 `forecast` 会在每次运行前重新生成相应 namelist
与 streams。把案例目录中的文件当作**可检查的生成结果**，不要先手改它再调用脚本，
否则修改会被覆盖。要做自定义实验，应先让脚本生成配置，再编辑文件并直接调用对应
`mpiexec`；后续仓库会把可调参数进一步模板化。

## 运行前按数据流检查

1. init 阶段：`static.nc`、起报 `FILE:*` 和 `config_start_time` 是否一致？
2. MPI：`mpiexec -n N` 是否存在同网格的 `.part.N`？
3. 初值：`nCells`、`nVertLevels`、`xtime` 和 `nominalMinDc` 是否符合设计？
4. forecast：输入流文件名是否就是刚生成的 `init.nc`？
5. namelist：dt、duration、全球/区域、冷启动/重启开关是否正确？
6. streams：输出间隔和变量清单是否满足需求？
7. 日志：是否明确完成，error 和 critical error 是否为 0？

## 费曼检查

假设你只想把 diagnostics 从 3 小时改成 1 小时，应改哪一个文件？应改
`streams.atmosphere` 的 `output_interval`，因为计算方法没有变。若把 MPI 从 16 改成 32，
为什么只改 output interval 没用？因为还必须提供 `.part.32`，那是 cell 到 MPI rank 的
分工表。若把时间步从 1200 s 改成 600 s，则应改 namelist，因为动力积分方式变了。

## 参考

- [MPAS-A 官方 I/O 配置](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/configuring_io.html)
- [官方真实资料初始化与运行](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)
- [Appendix A：初始化 namelist](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appA_init_namelist.html)
- [Appendix B：模式 namelist](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appB_model_namelist.html)
