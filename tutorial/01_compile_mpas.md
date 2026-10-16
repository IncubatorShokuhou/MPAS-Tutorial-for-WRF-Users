# 第 1 课：用 GCC/GFortran 从源码编译 MPAS-A

## 本课前置与产物

先读完第 0 课，并确认系统有 GCC、G++、GFortran、CMake、Make、curl、tar 和 Git；Git
用于取得固定版本的 MPAS 源码。开始长时间编译前先验收，任一命令无输出都应先安装：

```bash
command -v gcc g++ gfortran cmake make curl tar git
```

本课会在项目目录内构建自己的 MPI、I/O 库和 MPAS-A 8.4.2，最终得到：

```text
local/io-stack/bin/mpirun
local/mpas-8.4.2/bin/mpas_init_atmosphere
local/mpas-8.4.2/bin/mpas_atmosphere
```

## 为什么有两个 MPAS 程序

MPAS 的 **core（核心）** 是挂接在公共 MPAS 框架上的一个具体求解或预处理组件。本项目
构建两个大气 core：

- `mpas_init_atmosphere`：把网格、静态资料和外部气象资料制成模式初值；
- `mpas_atmosphere`：读取初值并向前积分，作用接近 WRF 的 `wrf.exe`。

初始化器不替代 `ungrib.exe`。后者先把 GRIB2 解码成中间格式；初始化器再完成类似
`geogrid + metgrid + real.exe` 的 MPAS 部分。案例运行时，脚本会为这两个安装文件建立
官方文档常用名称 `init_atmosphere_model` 和 `atmosphere_model` 的软链接。

## 为什么不只编译 PnetCDF

最小心智图是：MPAS 把并行读写请求交给 PIO（ParallelIO 调度层），PIO 再选择
netCDF-4/HDF5 或 PnetCDF 后端；MPI 负责进程通信和并行文件访问。第 2 课会拆开每一层，
本课只需记住它们必须由同一编译器和同一 MPI 构建。

ABI 是“编译后的程序怎样传参数和组织内存”的约定。两个库即使名字相同，若来自不同
Fortran 或 MPI ABI，也可能链接成功却在运行时崩溃。因此脚本按以下顺序从源码构建：

```text
OpenMPI → zlib → HDF5 → PnetCDF → netCDF-C → netCDF-Fortran → PIO → MPAS-A
```

## 一键安装

从仓库根目录运行：

```bash
./install_mpas.sh
```

逐项按 Enter 会使用 `local/`、`build/`、`downloads/` 和 `MPAS-Model/`。无人值守安装：

```bash
./install_mpas.sh -y
```

脚本默认把编译并行度设为全部逻辑 CPU；这应在计算节点而不是拥挤的登录节点执行。
`--jobs` 只控制编译并行度，不是以后预报使用的 MPI 进程数。自定义位置示例：

```bash
./install_mpas.sh -y --io-prefix /data/mpas/deps \
  --mpas-source /data/mpas/MPAS-Model \
  --mpas-prefix /data/mpas/install --jobs 32
```

用 `--cc`、`--cxx`、`--fc` 指定编译器绝对路径；用 `--help` 查看全部参数。除编译器外，
不要让系统 MPI 或 Conda MPI 混入 `PATH`、`LD_LIBRARY_PATH`。

## 构建方法与验收

支持成熟 CMake 流程的组件优先用 CMake；OpenMPI 与 PnetCDF 使用上游 Autotools 流程。
默认只做两进程 MPI 启动检查；`--run-tests` 才会运行耗时的依赖库测试。
`--with-wps` 可继续安装第 4 课所需的 `ungrib.exe`。

安装完成后执行：

```bash
export IO_ROOT="$PWD/local/io-stack"
export PATH="$IO_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$IO_ROOT/lib:${LD_LIBRARY_PATH:-}"

command -v mpirun mpifort
mpirun --version
ls -l local/mpas-8.4.2/bin/{mpas_atmosphere,mpas_init_atmosphere}
ldd local/mpas-8.4.2/bin/mpas_atmosphere | grep -E 'local/io-stack|not found'
```

前两个路径应位于当前项目的 `local/io-stack/bin`，两个 executable 应存在且可执行；
`ldd` 中相关动态库应来自 `local/io-stack`，任何 `not found` 都表示验收失败。不要仅凭
“编译命令返回 0”判断整条运行时依赖链正确。

## 费曼检查

1. 为什么换机器时不能只复制 `mpas_atmosphere`？——它仍依赖同一 ABI 的 MPI/I/O 库。
2. 两个 executable 为什么不是 debug/release 两版？——它们分别负责初始化与积分。
3. `--jobs 64` 为什么不代表预报会用 64 个 MPI 进程？——它只影响构建阶段。
