# 第 1 课：用 GCC/GFortran 编译 MPAS

MPI、I/O 库和 MPAS-A 8.4.2 都从源码装进项目目录。机器上如果已经有 MPI，这次也不用。
换服务器时重跑安装脚本，编译器和库仍是同一套。

## 动手前先检查系统工具

第 0 课的流程看过之后，先确认 GCC、G++、GFortran、CMake、Make、curl、tar、Git
都能找到。

```bash
command -v gcc g++ gfortran cmake make curl tar git
```

每个命令应打出一条路径。缺哪个就先装哪个。编译要几个小时，中途才发现缺工具很亏。

### 这一步留下了什么

在本机上，这组检查得到的是下面这些路径。你的 GCC 或 CMake 也可能装在 `/opt` 等其他
位置；关键是八行都有结果。

```text
/usr/bin/gcc
/usr/bin/g++
/usr/bin/gfortran
/usr/bin/cmake
/usr/bin/make
/usr/bin/curl
/usr/bin/tar
/usr/bin/git
```

`command -v` 只查命令，这一步不写文件。缺行就先装工具。编译器不在默认路径时，
后面的安装命令用 `--cc/--cxx/--fc` 写绝对路径。

编完以后，先看这三个文件在不在。

```text
local/io-stack/bin/mpirun
local/mpas-8.4.2/bin/mpas_init_atmosphere
local/mpas-8.4.2/bin/mpas_atmosphere
```

## 为什么会得到两个 MPAS 程序

MPAS 有一套公共框架。解哪类方程，由挂上去的核心程序（core）决定。编大气模式时
得到两个可执行文件。

- `mpas_init_atmosphere`：读取网格、静态资料和外部气象资料，制作模式初值；
- `mpas_atmosphere`：读取初值并向前积分，作用大致相当于 WRF 的 `wrf.exe`。

初始化程序不能代替 `ungrib.exe`。GFS 的 GRIB2 文件要先由 `ungrib.exe` 解码成 WPS
中间格式，然后才能交给 MPAS 初始化程序。若用 WRF 作类比，第一次运行初始化程序大致
相当于 `geogrid.exe`，把地理资料插值到网格上；第二次运行大致相当于 `metgrid.exe` 加
`real.exe`，把气象场插值到同一张网格并制作初值。
`ungrib.exe` 仍由 WPS 提供。

案例目录里还会出现 `init_atmosphere_model` 和 `atmosphere_model`。它们只是上面两个
安装文件的软链接，采用了官方文档常见的名称。

## 为什么这些依赖库要一起编译

依赖按这个顺序编。

```text
OpenMPI → zlib → HDF5 → PnetCDF → netCDF-C → netCDF-Fortran → PIO → MPAS-A
```

MPAS 把并行读写任务交给 PIO（ParallelIO，并行 I/O 调度库）。PIO 可以选用
netCDF-4/HDF5 或 PnetCDF 作为文件读写后端，MPI 则负责进程通信和并行文件访问。
所以 netCDF-4/HDF5 和 PnetCDF 都要留在依赖里。第 2 课会逐层说明这些库的作用。

这里还要认识一个容易引起麻烦的词：ABI，即二进制接口。它规定编译后的程序怎样传递
参数、怎样组织内存。两个库即使名字和版本看起来都对，只要分别用了不同的 Fortran
编译器或不同的 MPI，仍可能在链接或运行时出错。这些库因此必须用同一套编译器和
同一套 MPI 依次构建。

## 开始安装

在仓库根目录选一种写法。三种是同一件事，不要连着跑三遍。第一次想逐项看提示，
用交互方式。

```bash
./install_mpas.sh
```

交互提示出现后一路按 Enter，会采用以下默认目录：`local/` 用来安装软件，`build/`
保存编译目录，`downloads/` 保存下载文件，`MPAS-Model/` 保存 MPAS 源码。

不想逐项确认时，加 `-y`。

```bash
./install_mpas.sh -y
```

脚本默认用全部逻辑 CPU 并行编译。请在计算节点运行，不要占满共用登录节点。`--jobs`
控制的是编译时同时执行多少个任务，与以后预报使用多少个 MPI 进程没有关系。

依赖、源码和 MPAS 要装到别的目录，并且用 32 路编译时，写成这样。

```bash
./install_mpas.sh -y --io-prefix /data/mpas/deps \
  --mpas-source /data/mpas/MPAS-Model \
  --mpas-prefix /data/mpas/install --jobs 32
```

后续教学脚本目前按仓库内的默认前缀 `local/io-stack`、`local/mpas-8.4.2` 查找程序。若准备
逐课照做，建议先使用默认目录；采用上面的自定义前缀时，还需要同步调整案例脚本中的路径。

若要指定编译器，可使用 `--cc`、`--cxx` 和 `--fc`，参数值写编译器的绝对路径。全部参数
可用 `./install_mpas.sh --help` 查看。除编译器以外，不要让系统 MPI 或 Conda MPI 混入
`PATH` 和 `LD_LIBRARY_PATH`。

上游提供 CMake 构建方式的库优先使用 CMake；OpenMPI 和 PnetCDF 则按照上游给出的
`configure`、`make` 步骤编译。脚本默认只做一次两进程 MPI 启动检查。若加上
`--run-tests`，还会运行依赖库自身的测试，所需时间会明显增加。继续学第 4 课时，
可以加 `--with-wps`，同时安装 `ungrib.exe`。

### 这一步留下了什么

CMake 和 Make 的输出很长，盯末尾的安装摘要就够。下面是装成功之后再跑一次脚本
看到的结尾。第一次运行没有 `already installed`，会刷很多 `Built target` 和
`Installing`。

```text
I/O stack installation complete: .../MPAS_tutorial/local/io-stack
MPAS v8.4.2 is already installed at .../MPAS_tutorial/local/mpas-8.4.2

Installation complete.
I/O stack:    .../MPAS_tutorial/local/io-stack
MPAS source:  .../MPAS_tutorial/MPAS-Model
MPAS install: .../MPAS_tutorial/local/mpas-8.4.2
```

末尾有 `Installation complete`，并且 `local/io-stack/bin/mpirun` 和
`local/mpas-8.4.2/bin` 里的两个 MPAS 程序都在，这一步就算完成。默认目录长这样。

```text
MPAS_tutorial/
├── downloads/                 # 下载归档，可供重装复用
├── build/                     # 临时编译树
│   ├── io-stack/
│   └── mpas-8.4.2-cmake-pio/
├── MPAS-Model/                # v8.4.2 源码
└── local/
    ├── io-stack/
    │   ├── bin/mpirun
    │   ├── bin/mpifort
    │   └── lib/               # MPI、HDF5、netCDF、PnetCDF、PIO 等库
    └── mpas-8.4.2/
        ├── bin/mpas_init_atmosphere
        ├── bin/mpas_atmosphere
        ├── lib/               # MPAS 核心共享库，运行时同样必需
        └── share/MPAS/        # 默认 namelist、streams 和物理查找表
```

安装目录里的 namelist 是上游模板。开头几行是默认日期和时间步。

```fortran
&nhyd_model
    config_time_integration_order = 2
    config_dt = 720.0
    config_start_time = '2010-10-23_00:00:00'
    config_run_duration = '5_00:00:00'
/
```

这些默认日期、时间步和网格分区并不适合北京案例。后面要改的是复制到 `work/` 案例目录
里的副本；不要直接修改 `local/` 下的安装模板，也不要手工改 `bin/` 中的二进制程序。

## 编译结束后不要急着往下走

先让当前终端用刚编好的库。

```bash
export IO_ROOT="$PWD/local/io-stack"
export PATH="$IO_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$IO_ROOT/lib:${LD_LIBRARY_PATH:-}"

command -v mpirun mpifort
mpirun --version
ls -l local/mpas-8.4.2/bin/{mpas_atmosphere,mpas_init_atmosphere}
ldd local/mpas-8.4.2/bin/mpas_atmosphere | grep -E 'local/io-stack|not found'
```

`mpirun` 和 `mpifort` 都应位于当前项目的 `local/io-stack/bin`。两个 MPAS 程序应当存在，
并且具有执行权限。`ldd` 显示的相关动态库应来自 `local/io-stack`；只要出现
`not found`，就说明运行环境还没有准备好。

不要只看最后一条编译命令是否返回 0。真正需要确认的是，程序启动时找到的 MPI 和 I/O
库，确实是我们刚刚编译的这一套。

### 这一步留下了什么

本机这次的关键行抄在下面。内存地址每次都变，对的是路径落在本仓库的
`local/io-stack`。

```text
.../MPAS_tutorial/local/io-stack/bin/mpirun
.../MPAS_tutorial/local/io-stack/bin/mpifort
mpirun (Open MPI) 4.1.8

-rwxr-xr-x ... local/mpas-8.4.2/bin/mpas_atmosphere
-rwxr-xr-x ... local/mpas-8.4.2/bin/mpas_init_atmosphere
libnetcdf.so.22  => .../local/io-stack/lib/libnetcdf.so.22 (...)
libpnetcdf.so.8  => .../local/io-stack/lib/libpnetcdf.so.8 (...)
libmpi.so.40     => .../local/io-stack/lib/libmpi.so.40 (...)
libhdf5.so.310   => .../local/io-stack/lib/libhdf5.so.310 (...)
```

这组命令只改变当前终端的环境变量，不会再生成文件。若出现 `not found`，要改的是
`PATH`、`LD_LIBRARY_PATH` 或安装前缀；不要给缺失的 `.so` 文件随便建软链接。确认无误后，
第 2 课会继续拆解这套 I/O 栈，第 4 课再安装或检查 WPS。

## 用自己的话讲一遍

1. 为什么换机器时不能只拷一个 `mpas_atmosphere`？
2. 两个 MPAS 程序为什么不是调试版和正式版？
3. 为什么 `--jobs 64` 不是预报用 64 个 MPI 进程？

三问分开答。先说编译时链了什么，再说运行时加载什么，最后是预报起多少进程。
