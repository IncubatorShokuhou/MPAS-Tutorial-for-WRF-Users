# 编译 MPAS 完整 I/O 依赖栈

MPAS 不只依赖 Parallel-NetCDF。常见的完整构建还需要 MPI、zlib、HDF5、
netCDF-C、netCDF-Fortran 和 PIO。仓库根目录的 `install_io_stack.sh` 会按依赖
顺序从源码编译这些组件，并保证所有并行库使用同一套项目内 OpenMPI。

## 默认安装

系统只需预装 GCC/G++/GFortran、CMake、Make、curl 和 tar。直接运行：

```bash
./install_io_stack.sh
```

在终端中无参数运行会进入交互模式；一路回车即可使用默认目录：

- 安装前缀：`local/io-stack/`
- 下载缓存：`downloads/`
- 源码和构建树：`build/io-stack/`
- 并行度：机器检测到的全部逻辑 CPU

非交互安装示例：

```bash
./install_io_stack.sh -y --prefix /scratch/$USER/mpas-io -j 64
```

指定另一套 GCC 工具链：

```bash
./install_io_stack.sh -y \
  --cc /opt/gcc/bin/gcc --cxx /opt/gcc/bin/g++ \
  --fc /opt/gcc/bin/gfortran
```

先用 `--dry-run` 检查路径和编译器；`--run-tests` 会运行各库测试，但耗时明显
增加。重复执行是安全的：已安装组件会跳过，下载归档也会复用。

## 组件和版本

构建顺序固定为 OpenMPI 4.1.8、zlib 1.3.1、HDF5 1.14.6、
Parallel-NetCDF 1.15.0、netCDF-C 4.9.3、netCDF-Fortran 4.6.2、PIO 2.6.6。
能稳定使用 CMake 的项目均采用 CMake；OpenMPI 和 Parallel-NetCDF 按上游支持
采用 Autotools。HDF5 启用 parallel I/O 和 Fortran，netCDF-C 同时启用 HDF5
parallel4 与 PnetCDF。

## 使用和验证

```bash
export IO_ROOT="$PWD/local/io-stack"
export PATH="$IO_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$IO_ROOT/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$IO_ROOT:${CMAKE_PREFIX_PATH:-}"
export NETCDF="$IO_ROOT"
export PNETCDF="$IO_ROOT"

mpifort --showme
nc-config --all
nf-config --all
pnetcdf-config --all
```

配置 MPAS 时把 `CMAKE_PREFIX_PATH` 指向此统一前缀，并启用 PIO。不要混用系统
MPI 编译的 HDF5/netCDF；即使能链接，也可能在运行时崩溃。
