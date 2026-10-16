# 第 1 课：用 GCC/GFortran 从源码编译 MPAS-A

## 先用一句人话讲明白

这一课不是“得到一个 MPAS 程序”，而是得到两个共享同一数值框架的程序：
`mpas_init_atmosphere` 负责把外部资料变成模式状态，`mpas_atmosphere` 负责积分。类比
WRF，前者覆盖了部分 WPS/real.exe 职责，后者才接近 `wrf.exe`。

本项目以 MPAS-Atmosphere 8.4.2 为基线。安装顺序是 GCC/G++/GFortran → OpenMPI → zlib/HDF5 → netCDF-C/Fortran → Parallel-NetCDF → PIO → MPAS。除编译器外，其余组件都由脚本从源码构建，避免混用系统 MPI、Conda 库和不同编译器 ABI。

## 为什么暂时不编译 WPS

MPAS 的 `init_atmosphere_model` 负责静态场、垂直网格及初始/边界场插值。若预报使用 GFS GRIB2 数据，通常只需要 WPS 的 `ungrib.exe` 把 GRIB2 转为 WPS intermediate 文件；`geogrid.exe` 和 `metgrid.exe` 并不是 MPAS 流程的一部分。因此先完成 MPAS 本体，后续数据准备课程再单独编译 WPS/ungrib 及其 GRIB2 依赖。

## 一键安装

在项目根目录运行：

```bash
./install_mpas.sh
```

逐项直接按 Enter，即安装到本项目的 `local/`、`build/`、`downloads/` 和 `MPAS-Model/`。脚本默认使用机器全部逻辑 CPU，并用完整 PIO 栈。非交互式安装：

```bash
./install_mpas.sh -y
```

自定义位置和并行度示例：

```bash
./install_mpas.sh -y --io-prefix /data/mpas/deps \
  --mpas-source /data/mpas/MPAS-Model \
  --mpas-prefix /data/mpas/install --jobs 32
```

用 `./install_mpas.sh --help` 查看所有参数。可用 `--cc`、`--cxx`、`--fc` 指定编译器绝对路径。

## 构建方式与验证

OpenMPI 和 Parallel-NetCDF 使用正式发行版的 Autoconf 流程；其他支持成熟 CMake 流程的组件优先使用 CMake。MPAS 8.4.2 同时构建 `mpas_atmosphere` 和 `mpas_init_atmosphere`，并链接 PIO。默认执行冒烟测试；添加 `--run-tests` 会运行依赖库测试。添加 `--with-wps` 还会安装 `ungrib.exe`。

成功后脚本会打印环境变量。也可检查：

```bash
local/io-stack/bin/mpirun --version
local/io-stack/bin/pnetcdf-config --all
ls local/mpas-8.4.2/bin/{mpas_atmosphere,mpas_init_atmosphere}
```

不要在安装时激活会覆盖 `PATH` 或 `LD_LIBRARY_PATH` 的 Conda MPI 环境。

## 费曼检查

- 为什么换机器时必须连 MPI 和 I/O 库一起重编？因为 Fortran 模块和并行库 ABI 必须
  来自同一工具链，仅复制 executable 并不可靠。
- 为什么有两个 MPAS executable？初始化和时间积分是两个独立 core，不是 debug/release
  两个版本。
- 怎样证明编译成功？不仅看文件存在，还要检查其动态链接库来自本项目的 `local/`。
