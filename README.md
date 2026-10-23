# MPAS Tutorial for WRF Users

笔记面向已经会 WRF、刚开始跑 MPAS 的人。先用 GCC/GFortran 把模式和库编出来。
GFS 解码放在编译之后，接着做初值，再积分 24 小时。然后是北京加密网格。
区域裁剪和 JIGSAW 自定义网格放在那之后。最后一课用 Python 把 240 km 预报画成图。

每一步都写了为什么要这样做，命令可以直接复制。跑完对日志、文件和图，不要只看
进程有没有退出。

## 推荐学习顺序

| 课次 | 主题 | 学完能够回答 |
|---|---|---|
| [0](tutorial/00_wrf_to_mpas.md) | WRF 到 MPAS | 哪些 WRF 经验还能用，哪些不能照搬？ |
| [1](tutorial/01_compile_mpas.md) | 编译 MPAS-A | 两个可执行程序分别做什么？ |
| [2](tutorial/02_io_stack.md) | MPI 与并行输入输出库 | 为什么不只依赖 PnetCDF？ |
| [3](tutorial/03_grid_fundamentals.md) | 下载并画出真实网格 | 为什么 namelist 里没有 `dx/e_we`？ |
| [4](tutorial/04_wps_ungrib.md) | GFS 与 WPS | 为什么只需要 `ungrib`？ |
| [5](tutorial/05_namelists_and_streams.md) | namelist 与 streams | “怎么算”和“读写什么”如何分开？ |
| [6](tutorial/06_initialization_and_forecast.md) | 初值与预报 | `grid/static/FILE/init` 如何连接？ |
| [7](tutorial/07_output_and_beijing_timeseries.md) | 输出诊断 | `nCells/nEdges/nVertices` 如何取数？ |
| [8](tutorial/08_variable_resolution_mesh.md) | 北京加密网格 | 如何设置真正的“北京中心”？ |
| [9](tutorial/09_custom_mesh.md) | 选择与制作网格 | 没有 Domain Wizard，区域该怎么划？ |
| [10](tutorial/10_cartopy_visualization.md) | Cartopy | 如何正确投影非结构网格？ |

## 先用 240 km 粗网格跑通一遍

```bash
./install_mpas.sh
./install_wps.sh -y
./prepare_beijing_case.sh
cd work/beijing_240km_2026101500 && ./ungrib.exe && cd ../..
NTASKS=16 ./run_beijing_case.sh all

python3 -m venv work/venv-post
source work/venv-post/bin/activate
python -m pip install --upgrade pip
python -m pip install numpy netCDF4 matplotlib
python tools/analyze_beijing.py work/beijing_240km_2026101500
```

## 再试北京 92–25 km 加密网格

第一条命令可以直接运行。第二条会做静态地理场。当前账号读不了 WPS_GEOG 的部分
子目录，这一步还没跑通。

```bash
./prepare_beijing_vr_mesh.sh
./generate_beijing_vr_static.sh
```

换一套完整的地理资料时，把路径指过去。

```bash
GEOG_DIR=/path/to/WPS_GEOG ./generate_beijing_vr_static.sh
```

编译产物、输入资料和预报结果都放在 Git 不跟踪的目录里。换机器时重新跑脚本。
