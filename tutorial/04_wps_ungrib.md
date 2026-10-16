# 第 4 课：用 WPS `ungrib` 为 MPAS 解码 GFS GRIB2

## WPS 在 MPAS 流程中的位置

真实个例通常先下载 GFS 等 GRIB2 气象场，再用 WPS 的 `ungrib.exe`
解码为 **WPS intermediate** 文件；随后由 MPAS-A `init_atmosphere_model`
插值到 MPAS 网格。这里并不运行 WRF。

WPS 的三个主程序用途不同：

- `ungrib.exe`：读取 GRIB1/2，写 WPS intermediate；MPAS 需要的是它。
- `geogrid.exe`：为规则 WRF 网格处理静态地理场。
- `metgrid.exe`：把 intermediate 气象场插值到 WRF 网格。

官方 WPS 4.4+ 提供 `--nowrf` 配置来只编译 ungrib。完整 WPS 的
`geogrid`/`metgrid` 会链接已编译 WRF 的 I/O 库，因而需要匹配的 WRF、
编译器和 netCDF；仅为 MPAS 解码 GFS 不应额外编译 WRF。

## 安装

默认路径都在仓库中，直接运行并按 Enter 接受默认值：

```bash
./install_wps.sh
```

非交互安装（默认使用全部逻辑 CPU）：

```bash
./install_wps.sh -y
```

换机时可显式指定项目内已有的 OpenMPI/netCDF 与安装目录：

```bash
./install_wps.sh -y -j "$(nproc)" \
  --mpi-prefix "$PWD/local/openmpi-4.1.8" \
  --netcdf-prefix "$PWD/local/netcdf" \
  --grib2-prefix "$PWD/local/grib2" \
  --prefix "$PWD/local/wps-4.6.0"
```

脚本从源码安装 zlib、libpng、与 WPS 兼容的 JasPer 1.900.29，然后使用
WPS 的 CMake 构建。zlib、libpng 和 WPS 使用 CMake；旧版 JasPer 不提供
CMakeLists，因此使用其 Autotools 流程。OpenMPI/netCDF 路径来自本项目依赖栈；ungrib 本身是
串行程序，不能用 `mpirun` 加速。查看全部选项：

依赖库会使用 `--jobs` 指定的全部并行度；WPS 4.6.0 的多个目标共享 Fortran
模块输出目录，并行构建存在竞态，因此脚本仅对 WPS 自身使用串行构建。

```bash
./install_wps.sh --help
```

只有确实要运行 WRF 的 `geogrid`/`metgrid` 时才使用：

```bash
./install_wps.sh -y --full-wps --wrf-dir /path/to/installed/WRF
```

## 从 GFS GRIB2 生成 intermediate 文件

进入一个独立工作目录，不要在源码目录里运行。根据 GFS 产品选用相符
的 Vtable（字段不匹配会造成缺变量）：

```bash
mkdir -p work/gfs_ungrib && cd work/gfs_ungrib
ln -s "$OLDPWD/local/wps-4.6.0/bin/ungrib.exe" .
ln -s "$OLDPWD/src/WPS-4.6.0/ungrib/Variable_Tables/Vtable.GFS" Vtable
"$OLDPWD/src/WPS-4.6.0/link_grib.csh" /path/to/gfs/files/gfs.t??z.pgrb2.*
```

复制 WPS 源码中的 `namelist.wps`，至少令时间覆盖 GRIB2 文件，并设置
输出前缀：

```fortran
&share
 start_date = '2026-10-16_00:00:00'
 end_date   = '2026-10-17_00:00:00'
 interval_seconds = 10800
/
&ungrib
 out_format = 'WPS'
 prefix = 'FILE'
/
```

运行后应生成 `FILE:YYYY-MM-DD_HH`：

```bash
./ungrib.exe
tail -n 20 logfile.log
ls FILE:*
```

若日志出现 `Unknown out_format`、缺字段或时间断档，先核对 Vtable、
GFS 产品层次/分辨率、`interval_seconds` 和下载文件是否完整，再进入
MPAS `init_atmosphere` 教程。

## 参考

- [WRF 官方编译文档](https://www2.mmm.ucar.edu/wrf/site/documentation/users_guide/compiling.html)
- [WPS 官方用户指南](https://www2.mmm.ucar.edu/wrf/site/documentation/users_guide/wps.html)

## 费曼检查

`ungrib` 是否知道最终 MPAS 网格？不知道。它只把 GRIB 字段翻译为带经纬度和层次信息
的 intermediate 文件；真正的网格插值由下一步完成。因此更换 MPAS 网格时可以复用
同一批 `FILE:*`，但更换 GFS 产品或 Vtable 时必须重新 ungrib。
