# MPAS Tutorial

本仓库记录从源码编译 MPAS-Atmosphere、准备网格与 GFS 初始/边界条件、运行预报和分析输出的完整流程。

从[第 1 课：编译 MPAS](tutorial/01_compile_mpas.md)开始，或运行：

```bash
./install_mpas.sh
```

安装脚本会从源码构建 OpenMPI、HDF5、netCDF、Parallel-NetCDF 和 PIO，
再用 CMake 构建 MPAS 的预处理与预报程序。各部分也可单独执行：

- `install_io_stack.sh`：完整并行 I/O 依赖栈；
- `install_mpas.sh`：依赖栈和 MPAS 总入口；
- `install_wps.sh`：WPS `ungrib` 与 GRIB2 依赖。

编译完成后，从[第 4 课：理解 MPAS 网格并设计北京案例](tutorial/04_grid_and_beijing_case.md)
开始真实预报案例，或直接准备案例目录：

```bash
./prepare_beijing_case.sh
```
