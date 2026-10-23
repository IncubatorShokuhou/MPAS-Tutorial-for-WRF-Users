# MPAS Tutorial for WRF Users

这套教程写给 **熟悉 WRF、刚接触 MPAS** 的读者。我们从 GCC/GFortran 编译讲起，接着
处理 GFS 资料、制作初值、完成一次真实预报，再学习北京加密网格和 Python 绘图。

教程不会让你先背命令。每一步都先说明为什么这样做，再给出可以照着运行的命令。运行后
还要查看日志、文件和图，确认结果确实正确。最后，你应该能用自己的话把整个过程讲清楚。

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
| [9](tutorial/09_cartopy_visualization.md) | Cartopy | 如何正确投影非结构网格？ |
| [10](tutorial/10_custom_mesh.md) | 选择与制作网格 | 没有 Domain Wizard，区域该怎么划？ |

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

第一条命令可以直接运行。第二条命令会制作静态地理场，但当前服务器上的账号无权读取
WPS_GEOG 的部分子目录，所以这一步还没有跑通：

```bash
./prepare_beijing_vr_mesh.sh
./generate_beijing_vr_static.sh
```

如果你有另一套完整的地理资料，可以这样指定：

```bash
GEOG_DIR=/path/to/WPS_GEOG ./generate_beijing_vr_static.sh
```

编译产物、输入资料和预报结果都放在 Git 不跟踪的目录里。换机器时重新运行脚本即可。
