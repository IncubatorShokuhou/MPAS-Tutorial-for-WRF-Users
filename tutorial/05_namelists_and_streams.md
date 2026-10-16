# 第 5 课：系统理解 MPAS namelist 与 streams

## 三种配置文件各管什么

MPAS 没有一份包办所有工作的 namelist：

- `grid_rotate/namelist.input`：移动网格加密区；
- `namelist.init_atmosphere`：静态场、垂直网格、GFS 插值和预处理阶段；
- `namelist.atmosphere`：动力、物理、时步、重启和并行 I/O；
- `streams.*`：读写哪些文件、变量、格式和时间频率。

换句话说，namelist 决定“怎么算”，streams 决定“读写什么”。文件名通常不在
namelist 中修改。

## `namelist.init_atmosphere`

### `&nhyd_model`

真实资料固定使用 `config_init_case=7`。`config_start_time` 必须与 GFS intermediate
文件时间一致。case 8 用于周期 SST/海冰，case 9 用于有限区域侧边界，不能混用。

### `&dimensions`

`config_nvertlevels=55` 是 MPAS 输出层数；`config_nfglevels=38` 是当前 GFS intermediate
的输入层数。前者可由实验设计选择，后者必须与输入文件匹配。土壤输入和模式均为 4 层。

### `&data_sources`

关键项为：

```fortran
config_geog_data_path = '/eds/shared/dm/WPS_GEOG/'
config_met_prefix = 'FILE'
config_fg_interval = 10800
```

`config_met_prefix` 对应 `FILE:YYYY-MM-DD_HH`；三小时 GFS 间隔是 10800 秒。

### `&preproc_stages`

静态场阶段只打开：

```fortran
config_static_interp = true
config_native_gwd_static = true
```

气象初值阶段关闭上述两项，打开：

```fortran
config_vertical_grid = true
config_met_interp = true
config_frac_seaice = true
```

分两次运行能让同一网格的 static 文件被不同日期反复使用。

### `&decomposition` 和 `&io`

`config_block_decomp_file_prefix` 只写到 `.part.`，程序会按 MPI 任务数追加后缀。
`config_pio_num_iotasks=0` 表示所有任务参与 I/O；大规模作业才需要专门调优 I/O tasks
和 stride，不能机械复制其他机器参数。

## `namelist.atmosphere`

### 最先修改的 `&nhyd_model`

北京 92–25 km 网格建议从以下值开始：

```fortran
&nhyd_model
 config_dt = 150.0
 config_start_time = '2026-10-15_00:00:00'
 config_run_duration = '1_00:00:00'
 config_len_disp = 25000.0
/
```

`config_dt` 由最细网格控制；`config_len_disp` 是显式水平混合尺度，也按最细名义间距
设置。`config_start_time` 必须匹配 `init.nc`，duration 格式为 `DD_hh:mm:ss`。

### 其他常用组

- `&decomposition`：网格分区文件前缀；任务数改变时要有对应 `.part.N`。
- `&limited_area`：全球模拟保持 `config_apply_lbcs=false`。
- `&restart`：冷启动为 false；从 restart 接续才设 true，并匹配重启时刻。
- `&physics`：`mesoscale_reference` 是当前基线套件；25 km 仍使用积云参数化。
- `&damping`：高层阻尼和声波相关参数，初学时保留版本默认值。
- `&io`：控制 PIO 布局，不控制输出变量清单。

## `streams.atmosphere`

输入流要指向正确初值：

```xml
<immutable_stream name="input" type="input"
 filename_template="beijing.x4.163842.init.nc"
 input_interval="initial_only" />
```

history 和 diagnostics 的 `output_interval` 分别控制输出频率；其变量清单来自
`stream_list.atmosphere.output` 和 `.diagnostics`。输出越频繁、变量越多，I/O 和磁盘
成本越高。大文件应选择 `pnetcdf,cdf5` 或 `netcdf4`，避免经典 netCDF 单变量 4 GB
限制。

## 修改配置时的检查顺序

1. 网格文件名与 cell 数是否正确；
2. MPI 任务数是否存在对应 `.part.N`；
3. `init.nc` 时间是否等于 `config_start_time`；
4. `config_dt` 和 `config_len_disp` 是否按最细网格设置；
5. physics suite 与网格尺度是否匹配；
6. streams 文件名、间隔和变量表是否正确；
7. 最后检查日志的 warning、error 和 critical error 计数。

完整选项应以当前版本自动生成的默认 namelist 和
[官方 Appendix B](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appB_model_namelist.html)
为准，不要直接套用旧版本博客中的参数。

## 费曼检查

把配置想成餐厅：namelist 是烹饪方法，streams 是进货单和出菜单，`stream_list` 是每份
菜单包含哪些菜。修改 `output_interval` 为什么不在 namelist？因为它改变的是 I/O 闹钟，
不是动力过程。修改 physics suite 为什么不能只改 streams？因为它改变实际计算方案。
