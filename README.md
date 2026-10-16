# MPAS-A Tutorial

面向熟悉 WRF、但从未使用 MPAS 的读者：从 GCC/GFortran 源码编译开始，完成 GFS
真实资料预报、北京变分辨率网格原理和 Python/Cartopy 后处理。教程采用“人话解释 → WRF
类比 → 实际命令 → 输出验收 → 费曼检查”的顺序。

## 推荐学习顺序

| 课次 | 主题 | 学完能够回答 |
|---|---|---|
| [0](tutorial/00_wrf_to_mpas.md) | WRF 到 MPAS | 哪些知识能迁移，哪些直觉必须重建？ |
| [1](tutorial/01_compile_mpas.md) | 编译 MPAS-A | 两个 executable 分别做什么？ |
| [2](tutorial/02_io_stack.md) | 并行 I/O 栈 | 为什么不只依赖 PnetCDF？ |
| [3](tutorial/03_grid_fundamentals.md) | 网格基础 | 为什么 namelist 里没有 `dx/e_we`？ |
| [4](tutorial/04_wps_ungrib.md) | GFS 与 WPS | 为什么只需要 `ungrib`？ |
| [5](tutorial/05_namelists_and_streams.md) | Namelist/streams | “怎么算”和“读写什么”如何分开？ |
| [6](tutorial/06_initialization_and_forecast.md) | 初值与预报 | `grid/static/FILE/init` 如何连接？ |
| [7](tutorial/07_output_and_beijing_timeseries.md) | 输出诊断 | `nCells/nEdges/nVertices` 如何取数？ |
| [8](tutorial/08_variable_resolution_mesh.md) | 北京加密网格 | 如何设置真正的“北京中心”？ |
| [9](tutorial/09_cartopy_visualization.md) | Cartopy | 如何正确投影非结构网格？ |

## 最短可运行主线：240 km 基线

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

## 可选实验：北京 92–25 km 网格

下面的第一条命令可运行；第二条生成 static，目前会被本站 WPS_GEOG 子目录权限阻塞，
不属于上面的已验证主线：

```bash
./prepare_beijing_vr_mesh.sh
./generate_beijing_vr_static.sh
```

可用 `GEOG_DIR=/path/to/WPS_GEOG ./generate_beijing_vr_static.sh` 指定另一份完整地理资料。
构建物、输入资料和预报输出均位于 Git 忽略目录，可在换机后由脚本重建。
