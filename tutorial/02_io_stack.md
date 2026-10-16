# 第 2 课：打开 MPAS 并行 I/O 栈的黑箱

## 本课前置与定位

第 1 课的一键脚本已经调用了 `install_io_stack.sh`；若安装成功，本课不要求重复编译。
这里把黑箱拆开，使你换机器或排查链接错误时知道每一层负责什么。也可以只运行本课脚本，
得到一套可供其他 MPAS 源码使用的独立 I/O 前缀。

## 先认识图中的每一层

- **OpenMPI**：启动多个进程并提供通信；其中 MPI-IO 是 MPI 标准定义的并行文件接口；
- **zlib**：为 HDF5/netCDF-4 提供压缩；
- **HDF5**：netCDF-4 使用的底层层次化存储；
- **netCDF-C / netCDF-Fortran**：MPAS 使用的 C、Fortran 数据接口；
- **PnetCDF**：面向 classic/CDF5 格式的并行后端；
- **PIO（ParallelIO）**：在计算进程和具体文件后端之间组织数据。
- **streams**：MPAS 的 I/O 清单和调度配置，决定某类文件使用哪个后端；第 5 课再学习
  它的完整语法。

## 一次写文件经过哪些层

```text
MPAS 变量 → PIO 调度 → netCDF-4/HDF5  ┐
                    └→ PnetCDF          ┴→ MPI-IO → 文件系统
```

netCDF-4/HDF5 与 PnetCDF 是两条可选择的后端，不表示一次写文件必定依次穿过两者。完整
构建同时提供它们，让 streams 可以按文件用途选择。所有并行层必须使用项目自己的同一套
OpenMPI。

## 默认安装

系统只需预装 GCC/G++/GFortran、CMake、Make、curl 和 tar：

```bash
./install_io_stack.sh
```

一路回车采用以下默认值：

- 安装前缀：`local/io-stack/`
- 下载缓存：`downloads/`
- 源码与构建树：`build/io-stack/`
- 编译并行度：当前机器全部逻辑 CPU

无人值守与自定义编译器示例：

```bash
./install_io_stack.sh -y --prefix /scratch/$USER/mpas-io -j 64

./install_io_stack.sh -y \
  --cc /opt/gcc/bin/gcc --cxx /opt/gcc/bin/g++ \
  --fc /opt/gcc/bin/gfortran
```

先用 `--dry-run` 查看脚本解析出的目录、编译器和命令；它不编译，也不等价于完整的权限
与依赖测试。`--run-tests` 会运行各库测试，耗时明显增加。重复执行会跳过已有组件并复用
下载归档。

## 组件版本与构建顺序

脚本依次构建 OpenMPI 4.1.8、zlib 1.3.1、HDF5 1.14.6、PnetCDF 1.15.0、
netCDF-C 4.9.3、netCDF-Fortran 4.6.2、PIO 2.6.6。支持成熟 CMake 流程的项目使用
CMake；OpenMPI 和 PnetCDF 使用上游 Autotools。HDF5 启用 parallel I/O 和 Fortran，
netCDF-C 同时启用 parallel4 与 PnetCDF。

## 使用与逐层验收

`mpifort` 是 MPI 提供的 Fortran 包装编译器：它在 GFortran 命令外自动加 MPI 头文件和
库。`nf-config`、`nc-config`、`pnetcdf-config` 分别报告三个已安装接口的配置。

```bash
export IO_ROOT="$PWD/local/io-stack"
export PATH="$IO_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$IO_ROOT/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$IO_ROOT:${CMAKE_PREFIX_PATH:-}"
export NETCDF="$IO_ROOT"
export PNETCDF="$IO_ROOT"

command -v mpifort
mpifort --showme:command
nc-config --has-parallel4
nc-config --has-pnetcdf
nf-config --version
pnetcdf-config --version
```

预期依次看到项目内 `local/io-stack/bin/mpifort`、底层 GFortran、两个 `yes`、
netCDF-Fortran 4.6.2 和 PnetCDF 1.15.0。再检查最终 executable：

```bash
ldd local/mpas-8.4.2/bin/mpas_atmosphere | \
  grep -E 'mpi|netcdf|hdf5|pio|not found'
```

`ldd` 用来查看程序运行时实际寻找哪些动态库；`libnetcdff.so` 是 netCDF-Fortran 动态库。
路径应来自统一前缀，`not found` 或系统 MPI 与项目 netCDF 混用都必须先修复。

## 费曼检查

为什么同时安装 HDF5 和 PnetCDF，却说它们是替代后端？因为完整工具箱要支持多种输出
格式，而某一个 stream 只选择其中一条路径。为什么 `mpifort` 的来源重要？因为它决定
随后每个并行库编译进哪套 MPI ABI。
