# 第 2 课：MPAS 的并行 I/O 到底怎样工作

第 1 课执行 `install_mpas.sh` 时，已经调用过 `install_io_stack.sh`。如果安装顺利，这一课
不必再编译一遍。我们要做的是把各层依赖关系理顺。以后换机器，或者碰到“编译成功、
运行却找错库”的问题，你就知道应该从哪一层查起。

如果只想给其他 MPAS 源码准备一套独立的 I/O 依赖，也可以单独运行本课的安装脚本。

## 先认清每个库负责什么

- **OpenMPI**：启动多个进程并负责进程间通信；其中 MPI-IO 是 MPI 标准规定的并行
  文件接口；
- **zlib**：为 HDF5 和 netCDF-4 提供压缩功能；
- **HDF5**：netCDF-4 所采用的底层存储格式；
- **netCDF-C / netCDF-Fortran**：分别提供 C 和 Fortran 的 netCDF 接口，MPAS 会用到；
- **PnetCDF**：面向 classic 和 CDF5 格式的并行读写后端；
- **PIO（ParallelIO）**：在计算进程和具体文件后端之间分配、组织 I/O 任务；
- **输入输出配置（streams）**：安排 MPAS 读写哪些文件、何时读写。它还会指定某类文件采用
  哪个后端，第 5 课再讲具体写法。

一次写文件的过程可以画成这样。

```text
MPAS 变量 → PIO 组织读写 → netCDF-4/HDF5  ┐
                         └→ PnetCDF          ┴→ MPI-IO → 文件系统
```

netCDF-4/HDF5 和 PnetCDF 是两条可选路径。同一份文件只走其中一条。我们把
它们都编译好，是为了让不同的输入输出配置可以选择合适的文件格式。无论选哪一条路，
所有并行库都必须使用项目自己编译的同一套 OpenMPI。

## 单独安装 I/O 依赖

系统需要预先装好 GCC、G++、GFortran、CMake、Make、curl 和 tar。正式编译前，先在仓库
根目录做一次预演（dry run）：

```bash
./install_io_stack.sh --dry-run
```

它先确认 GCC、G++、GFortran 命令存在，再打印计划；不会下载、创建目录或编译。本机实测
输出如下。

### 这一步留下了什么

```text
MPAS I/O stack configuration
  prefix:    .../MPAS_tutorial/local/io-stack
  downloads: .../MPAS_tutorial/downloads
  builds:    .../MPAS_tutorial/build/io-stack
  compilers: /usr/bin/gcc, /usr/bin/g++, /usr/bin/gfortran
  jobs:      64
```

预演不生成任何文件。路径或并行度不合适，就调整命令行里的 `--prefix`、`--build-dir`、
编译器路径或 `--jobs`。它还不会检查磁盘权限，正式安装前仍要确认目标目录可写。

计划无误后，再从下面三种安装写法中选一种。无参数运行会进入交互模式，一路按 Enter
采用默认值：

```bash
./install_io_stack.sh
```

默认设置是：

- 安装目录：`local/io-stack/`
- 下载缓存：`downloads/`
- 源码和编译目录：`build/io-stack/`
- 编译并行度：当前机器的全部逻辑 CPU

无人值守安装可以这样写：

```bash
./install_io_stack.sh -y --prefix /scratch/$USER/mpas-io -j 64
```

若采用这个自定义前缀，后面的检查命令要把 `IO_ROOT` 设为
`/scratch/$USER/mpas-io`。本教程案例脚本仍按默认的 `local/io-stack` 查找依赖；准备继续
逐课运行时，优先使用默认目录。

也可以明确指定三种编译器：

```bash
./install_io_stack.sh -y \
  --cc /opt/gcc/bin/gcc --cxx /opt/gcc/bin/g++ \
  --fc /opt/gcc/bin/gfortran
```

加上 `--run-tests` 后，脚本会运行各个库自带的测试，耗时会长很多。再次执行安装脚本
时，已经装好的组件会被跳过，下载文件也会继续使用，不必每次从头开始。

### 这一步留下了什么

成功安装的末尾会明确给出统一前缀和需要设置的环境变量。下面模拟的是安装成功后再次
执行脚本的输出；前面的 `Already installed` 表示复用已有结果，安装没有失败：

```text
Already installed: .../local/io-stack/bin/h5pfc
Already installed: .../local/io-stack/bin/nc-config
Already installed: .../local/io-stack/bin/nf-config
Already installed: .../local/io-stack/lib/libpiof.a

I/O stack installation complete: .../local/io-stack
Use it with:
  export PATH=".../local/io-stack/bin:$PATH"
  export LD_LIBRARY_PATH=".../local/io-stack/lib:${LD_LIBRARY_PATH:-}"
```

默认安装后，主要产物集中在同一个前缀中：

```text
local/io-stack/
├── bin/
│   ├── mpicc
│   ├── mpifort
│   ├── nc-config
│   ├── nf-config
│   └── pnetcdf-config
├── include/                  # C 头文件和 Fortran .mod 文件
└── lib/
    ├── libmpi.so
    ├── libhdf5.so
    ├── libnetcdf.so
    ├── libnetcdff.so
    ├── libpnetcdf.so
    ├── libpioc.a
    ├── libpiof.a
    └── libnetcdf.settings
```

`libnetcdf.settings` 是构建过程自动写出的“体检单”，本项目中的关键内容为：

```text
NetCDF Version:          4.9.3
C Compiler:              .../local/io-stack/bin/mpicc
HDF5 Support:            yes
NC-4 Parallel Support:   yes
PnetCDF Support:         yes
```

`.so`、`.a`、`.mod` 和 `libnetcdf.settings` 都是编译产物。路径或工具链不对时，应整理
shell 环境，或带着正确参数重新执行安装脚本。

## 脚本究竟安装哪些版本

脚本按顺序安装 OpenMPI 4.1.8、zlib 1.3.1、HDF5 1.14.6、PnetCDF 1.15.0、
netCDF-C 4.9.3、netCDF-Fortran 4.6.2 和 PIO 2.6.6。

能够可靠使用 CMake 的项目采用 CMake；OpenMPI 和 PnetCDF 按照各自上游提供的
Autotools 方式构建。HDF5 会开启并行 I/O 和 Fortran 支持，netCDF-C 则同时开启
parallel4 和 PnetCDF 支持。

## 一层一层检查，别只看安装日志最后一行

`mpifort` 是 MPI 提供的 Fortran 包装编译器。调用它时，实际仍由 GFortran 编译，只是
命令中会自动加入 MPI 的头文件和库。`nc-config`、`nf-config`、`pnetcdf-config` 分别
报告 netCDF-C、netCDF-Fortran 和 PnetCDF 的安装信息。

先设置环境变量，再逐项检查：

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

正常情况下，首先会看到项目内的 `local/io-stack/bin/mpifort`，接着看到它调用的
GFortran；两个 netCDF 并行功能检查都应返回 `yes`；版本号应分别包含
netCDF-Fortran 4.6.2 和 PnetCDF 1.15.0。

### 这一步留下了什么

本机实测输出很短，正好可以逐行核对：

```text
.../MPAS_tutorial/local/io-stack/bin/mpifort
/usr/bin/gfortran
yes
yes
4.6.2
PnetCDF 1.15.0
```

这些查询不会生成文件，`export` 也只对当前 shell 生效。若第一行落到 `/usr/bin/mpifort`
或并行功能返回 `no`，先检查 `PATH` 和安装参数，再用同一套编译器与 MPI 重建相关库。

最后检查 MPAS 实际会加载哪些动态库：

```bash
ldd local/mpas-8.4.2/bin/mpas_atmosphere | \
  grep -E 'mpi|netcdf|hdf5|pio|not found'
```

`libnetcdff.so` 是 netCDF-Fortran 的动态库。输出路径都应指向统一的安装目录。如果出现
`not found`，或者系统 MPI 与项目内的 netCDF 混在一起，先不要运行 MPAS，应当回头整理
`PATH` 和 `LD_LIBRARY_PATH`。

### 这一步留下了什么

本项目的 `ldd` 结果包含下面这些关键行；PIO 在这里以静态库链接，因此没有单独的
`libpio.so` 行是正常的。

```text
libnetcdf.so.22 => .../local/io-stack/lib/libnetcdf.so.22 (...)
libpnetcdf.so.8 => .../local/io-stack/lib/libpnetcdf.so.8 (...)
libmpi_mpifh.so.40 => .../local/io-stack/lib/libmpi_mpifh.so.40 (...)
libmpi.so.40 => .../local/io-stack/lib/libmpi.so.40 (...)
libhdf5_hl.so.310 => .../local/io-stack/lib/libhdf5_hl.so.310 (...)
libhdf5.so.310 => .../local/io-stack/lib/libhdf5.so.310 (...)
```

`ldd` 只读取 ELF 程序的依赖表，不会产生新文件。发现混用系统库时，先整理环境变量；仍然
混用，就回到统一前缀重新编译。

## 用自己的话讲一遍

1. 为什么已经安装 HDF5，还要安装 PnetCDF？
2. 为什么同一个文件不会同时依次经过 HDF5 和 PnetCDF？
3. 为什么一定要确认 `mpifort` 来自哪个目录？

回答时不要把 PIO、PnetCDF 和 MPI-IO 当成同一个库。沿着本课的箭头，从 MPAS 变量一路
讲到文件系统，三者各自做什么就清楚了。
