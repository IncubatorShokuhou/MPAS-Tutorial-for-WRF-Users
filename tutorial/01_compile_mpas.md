# 第 1 课：用 GCC/GFortran 编译 MPAS

这一课要从源码编译 MPI、I/O 依赖库和 MPAS-A 8.4.2。所有内容都装在项目目录里，不借用
机器上现成的 MPI。这样换到另一台服务器时，只要重新执行安装脚本，就能得到来源清楚、
彼此匹配的一套环境。

## 动手前先检查系统工具

请先读完第 0 课，再检查 GCC、G++、GFortran、CMake、Make、curl、tar 和 Git：

```bash
command -v gcc g++ gfortran cmake make curl tar git
```

每个命令都应该返回一条路径。缺哪一个，就先请管理员安装哪一个，不要等到几个小时的
编译中途才发现工具不全。

编译完成后，最重要的三个文件是：

```text
local/io-stack/bin/mpirun
local/mpas-8.4.2/bin/mpas_init_atmosphere
local/mpas-8.4.2/bin/mpas_atmosphere
```

## 为什么会得到两个 MPAS 程序

MPAS 有一套公共框架，具体求解什么问题，由挂在框架上的核心程序（core）决定。本项目
编译大气模式时，会生成两个可执行程序：

- `mpas_init_atmosphere`：读取网格、静态资料和外部气象资料，制作模式初值；
- `mpas_atmosphere`：读取初值并向前积分，作用大致相当于 WRF 的 `wrf.exe`。

初始化程序不能代替 `ungrib.exe`。GFS 的 GRIB2 文件要先由 `ungrib.exe` 解码成 WPS
中间格式，然后才能交给 MPAS 初始化程序。若用 WRF 作类比，第一次运行初始化程序可以
把地理资料插值到网格上；第二次运行再把气象场插值到同一张网格并制作初值。
`ungrib.exe` 仍由 WPS 提供。

案例目录里还会出现 `init_atmosphere_model` 和 `atmosphere_model`。它们只是上面两个
安装文件的软链接，采用了官方文档常见的名称，并不是另外编译出的程序。

## 为什么这些依赖库要一起编译

完整的编译顺序如下：

```text
OpenMPI → zlib → HDF5 → PnetCDF → netCDF-C → netCDF-Fortran → PIO → MPAS-A
```

MPAS 把并行读写任务交给 PIO（ParallelIO，并行 I/O 调度库）。PIO 可以选用
netCDF-4/HDF5 或 PnetCDF 作为文件读写后端，MPI 则负责进程通信和并行文件访问。
所以，MPAS 绝不只依赖 PnetCDF。第 2 课会逐层说明这些库的作用。

这里还要认识一个容易引起麻烦的词：ABI，即二进制接口。它规定编译后的程序怎样传递
参数、怎样组织内存。两个库即使名字和版本看起来都对，只要分别用了不同的 Fortran
编译器或不同的 MPI，仍可能在链接或运行时出错。因此，这些库必须用同一套编译器和
同一套 MPI 依次构建。

## 开始安装

在仓库根目录执行：

```bash
./install_mpas.sh
```

交互提示出现后一路按 Enter，会采用以下默认目录：`local/` 用来安装软件，`build/`
保存编译目录，`downloads/` 保存下载文件，`MPAS-Model/` 保存 MPAS 源码。

如果不想逐项确认，可以这样运行：

```bash
./install_mpas.sh -y
```

脚本默认用全部逻辑 CPU 并行编译。请在计算节点运行，不要占满共用登录节点。`--jobs`
控制的是编译时同时执行多少个任务，与以后预报使用多少个 MPI 进程没有关系。

下面这个例子把依赖库、源码和 MPAS 安装到指定目录，并用 32 路并行编译：

```bash
./install_mpas.sh -y --io-prefix /data/mpas/deps \
  --mpas-source /data/mpas/MPAS-Model \
  --mpas-prefix /data/mpas/install --jobs 32
```

若要指定编译器，可使用 `--cc`、`--cxx` 和 `--fc`，参数值写编译器的绝对路径。全部参数
可用 `./install_mpas.sh --help` 查看。除编译器以外，不要让系统 MPI 或 Conda MPI 混入
`PATH` 和 `LD_LIBRARY_PATH`。

上游提供 CMake 构建方式的库优先使用 CMake；OpenMPI 和 PnetCDF 则按照上游给出的
`configure`、`make` 步骤编译。脚本默认只做一次两进程 MPI 启动检查。若加上
`--run-tests`，还会
运行依赖库自身的测试，所需时间会明显增加。若准备继续学习第 4 课，可以加
`--with-wps`，同时安装 `ungrib.exe`。

## 编译结束后不要急着往下走

先让当前终端使用刚编译好的库：

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

不要只看最后一条编译命令是否返回 0。真正需要确认的是：程序启动时找到的 MPI 和 I/O
库，确实是我们刚刚编译的这一套。

## 用自己的话讲一遍

1. 为什么换机器时不能只复制一个 `mpas_atmosphere`？
2. 两个 MPAS 可执行程序为什么不是调试版和正式版？
3. 为什么 `--jobs 64` 不等于预报时使用 64 个 MPI 进程？

回答时，把“编译时用了什么”“运行时加载什么”“预报时启动多少进程”分开，不要把三件事
混在一起。
