# 第 8 课：把变分辨率网格旋转到北京

## 本课问题

WRF 用 `ref_lat/ref_lon`、`dx/dy`、`e_we/e_sn` 定义矩形 domain。MPAS-A 的
`namelist.atmosphere` 不生成水平网格，那么“以北京为中心”究竟在哪里设置？

答案是：先准备一个已经包含多边形位置和连接关系的 `grid.nc`，再让模式读取它。可以把
一次 MPAS 真实资料预报分成三层：

```text
几何层：grid.nc       多边形在哪里、谁和谁相邻
地表层：static.nc     每个多边形对应什么地形、土壤和土地利用
天气层：init.nc       某个起报时刻的风、温、湿、压和陆面状态
```

移动加密区会改变地理位置，因此后两层都必须重新生成。

## 四种网格路线

MPAS 的常见选择是：

1. 下载准均匀全球网格：最简单，没有区域中心；
2. 下载全球变分辨率网格并旋转加密区：本课的北京方案；
3. 用 MPAS-Tools（生成、变换和检查 MPAS 网格的工具集合）及其中调用的 JIGSAW，从
   “期望分辨率随位置如何变化”的密度函数生成新网格；
4. 从全球网格裁剪有限区域，并另外制作随时间变化的侧边界条件。

SCVT 是 spherical centroidal Voronoi tessellation，即球面质心 Voronoi 剖分；它是
MPAS 网格的数学类型。JIGSAW 是高级网格生成器。第一次学习不需要自己生成 SCVT，先旋转
官方已收敛的网格，可以把“网格生成质量”和“天气初始化错误”分开。

## 为什么选择 92–25 km 网格

官方 `x4.163842` 有 163842 个 cell，全球背景约 92 km、加密中心约 25 km，加密区跨度
约 60°。`x4` 表示粗细分辨率大约变化四倍，`163842` 是全球 cell 总数，并不是
`e_we × e_sn`。

下图颜色是 `6371 km × sqrt(areaCell)`，只是根据单元面积构造的局地尺度代理，不等于
官方“名义网格间距”的严格定义。点越密、颜色越暗，cell 越小。

![旋转到北京后的 92–25 km 网格；颜色为 cell 面积尺度代理](images/beijing_mesh_resolution.png)

## 操作一：下载并旋转网格

前置条件是已完成第 1–2 课，且能使用 `curl`、Git、Make、项目 netCDF 和含
NumPy/netCDF4/Matplotlib 的 Python。以下命令从仓库根目录运行，会下载约 122 MB 的
压缩包，并在 `work/` 中保留原网格和旋转网格：

```bash
./prepare_beijing_vr_mesh.sh
```

脚本还会获取并编译 MPAS-Tools 的 `grid_rotate`。默认固定在 MPAS-Tools 2.1.0 的提交
`be1954cf369ae0e3aad06cda7283a15f7cb1325e`，并打印解析后的提交号；换机不会悄悄跟随
`main` 漂移。只有明确要验证其他版本时才覆盖它：

```bash
./prepare_beijing_vr_mesh.sh --mpas-tools-revision TAG_OR_COMMIT
```

`grid_rotate` 读取的不是模式 namelist，而是工作目录中的 `namelist.input`：

```fortran
&input
 config_original_latitude_degrees = 0.0
 config_original_longitude_degrees = 0.0
 config_new_latitude_degrees = 39.9042
 config_new_longitude_degrees = 116.4074
 config_birdseye_rotation_counter_clockwise_degrees = 0.0
/
```

前两项选中官方网格原来位于 `(0°, 0°)` 的加密中心，后两项把它移到北京。最后一项是
绕该参考点的鸟瞰旋转；圆形加密区保持 0 即可，非圆形加密区可用它调整朝向。原文件不会
被修改，输出为：

```text
work/beijing_92-25km/beijing.x4.163842.grid.nc
```

## 操作二：验收旋转结果

脚本当前应打印类似：

```text
nearest cell=..., distance=10.26 km, area scale=20.28 km
```

再检查维度并绘图：

```bash
local/io-stack/bin/ncdump -h work/beijing_92-25km/beijing.x4.163842.grid.nc \
  | grep -E 'nCells =|nEdges =|nVertices ='

python tools/plot_mesh_resolution.py \
  work/beijing_92-25km/beijing.x4.163842.grid.nc \
  --output work/beijing_92-25km/beijing_mesh_resolution.png
```

预期 `nCells=163842`，最近 cell 距北京约 10 km。面积尺度约 20 km 而网格名称写 25 km
并不矛盾：两者采用不同的几何尺度定义，前者只是 `sqrt(areaCell)` 代理。

## 为什么 graph 分区可以复用

把每个 cell 看成图节点，把相邻关系看成图的边：

- `x4.163842.graph.info` 保存整张 cell 邻接图；
- `x4.163842.graph.info.part.N` 把图划给 `N` 个 MPI task；
- `N` 必须与 `mpiexec -n N` 完全一致。

网格旋转改变 `latCell/lonCell`、三维球面坐标、科氏参数和 edge 地理方向，但没有改变
“哪个 cell 与哪个 cell 相邻”。所以原网格的 `graph.info` 和 `.part.N` 可以复用，而
原来的 `static.nc`、`init.nc` 和预报输出不能复用。

官方包已经提供多个常用划分，先查看而不是重新生成：

```bash
ls work/beijing_92-25km/x4.163842.graph.info.part.*
```

只有所需任务数不在列表中时才需要 METIS。例如系统已经另外安装 `gpmetis` 后，可生成
64-way 划分：

```bash
command -v gpmetis
cd work/beijing_92-25km
gpmetis -minconn -contig -niter=200 x4.163842.graph.info 64
cd ../..
```

本仓库的安装脚本目前不安装 METIS；不要把上面的命令当作默认环境必然可用。

## 操作三：为旋转网格生成 static

静态插值的数据流是：

```text
beijing.grid.nc + WPS_GEOG
              ↓ init_atmosphere_model（仅 1 个 MPI task）
beijing.static.nc
```

先确认共享资料的具体 tile 目录可进入，而不只是能看到顶层目录：

```bash
GEOG_DIR="${GEOG_DIR:-/eds/shared/dm/WPS_GEOG}"
namei -l "$GEOG_DIR/topo_gmted2010_30s/index"
test -r "$GEOG_DIR/topo_gmted2010_30s/index"
```

有权限后运行：

```bash
GEOG_DIR="$GEOG_DIR" ./generate_beijing_vr_static.sh

LOG=work/beijing_92-25km/log.init_atmosphere.0000.out
STATIC=work/beijing_92-25km/beijing.x4.163842.static.nc
grep 'Finished running the init_atmosphere core' "$LOG"
grep -Eq 'Error messages[[:space:]]*=[[:space:]]*0' "$LOG"
grep -Eq 'Critical error messages[[:space:]]*=[[:space:]]*0' "$LOG"
test -s "$STATIC"
local/io-stack/bin/ncdump -h "$STATIC" | grep 'nCells = 163842'

python - <<'PY'
import numpy as np
from netCDF4 import Dataset

path = 'work/beijing_92-25km/beijing.x4.163842.static.nc'
with Dataset(path) as ds:
    assert len(ds.dimensions['nCells']) == 163842
    for name in ('ter', 'landmask', 'ivgtyp', 'isltyp'):
        values = np.ma.asarray(ds.variables[name][:])
        assert values.count() == values.size, f'{name} contains missing values'
        assert np.all(np.isfinite(values)), f'{name} contains non-finite values'
        print(name, values.min(), values.max())
PY
```

`ter`、`landmask`、`ivgtyp` 和 `isltyp` 分别抽查地形、陆海掩膜、主植被类和主土壤类。
只有 finished 标记、零 error、零 critical error、正确 cell 数和关键字段都通过，才算 static
成功；单凭文件存在可能只是程序中途留下的残缺文件。

静态阶段必须串行运行。脚本为最小 25 km 教学案例把三个超采样参数都显式设为 1，以限制
取样和运行成本；这是一项教学选择，不是所有网格的最佳值。三者职责不同：

- `config_supersample_factor`：MODIS 最大雪反照率和月反照率；
- `config_lu_supersample_factor`：土地利用分类；
- `config_30s_supersample_factor`：30 秒地形、土壤分类及 FPAR 植被比例等。

超采样是从高分辨率 tile 中取更多子样本，不会把 25 km 动力网格变成 30 秒网格。
MPAS 8.4.2 的 `config_supersample_factor` 默认值是 3，另外两项默认 1；正式试验若关心反照率
或复杂下垫面，应比较更高取样因子对 static 场和耗时的影响，而不是机械沿用本例。

> 当前验证状态（2026-10-16）：北京网格旋转已经成功；本站默认的
> `/eds/shared/dm/WPS_GEOG` 顶层可见，但当前账号不能读取 `topo_gmted2010_30s/index`，因此 static
> 生成尚未完成。需要共享资料管理员授予只读和目录进入权限。本文不把该步骤写成已成功。

## static 之后还缺什么

目前 `run_beijing_case.sh` 硬编码的是 `x1.10242` 基线网格，**不能**用来运行这张 x4
北京网格。权限解决后，完整 VR 预报还需要单独完成：

1. 复用第 4 课的 `FILE:*`，以北京 `static.nc` 为输入生成新的 `init.nc`；
2. 在 `streams.init_atmosphere` 中把 input/output 指向北京 static/init 文件；
3. 用存在的 `.part.N` 运行气象场插值和模式积分；
4. 在 `namelist.atmosphere` 中按最细区域设置时间步和混合尺度；
5. 在 `streams.atmosphere` 中指向北京 init 文件并设置输出频率。

关键模式参数的起始值为：

```fortran
&nhyd_model
 config_dt = 150.0
 config_start_time = '2026-10-15_00:00:00'
 config_run_duration = '1_00:00:00'
 config_len_disp = 25000.0
/
&decomposition
 config_block_decomp_file_prefix = 'x4.163842.graph.info.part.'
/
```

`config_dt≈5–6 × 最细公里数` 只是经验起点；输出间隔应能被时间步整除。CFL（库朗数）
衡量一个时间步内信息跨越多少个网格尺度，最终要根据 CFL、速度极值和日志稳定性决定
是否减小时间步。`config_len_disp` 使用最细名义间距，而不是全球平均
92 km。计划中的 25 km VR 基线应先沿用 `mesoscale_reference` 的积云参数化，不能因为
图看起来细就假定深对流已被显式解析。

## 本课验收

- 已生成 163842-cell 的北京旋转网格，最近 cell 距北京约 10 km；
- 能解释 `.part.N` 中的 N 与 MPI task 数的关系；
- 能解释为何 graph 分区可复用而 static 不可复用；
- static 需要 finished、零 error/critical error、`nCells=163842` 和关键静态字段共同验收；
  当前机器因权限尚未通过此门；
- 不声称已经完成北京 VR 初值或预报。

## 费曼复述

试着把网格想成转动一只已经画好多边形的足球：为什么转动后邻居名单不变，山地和科氏
参数却变了？为什么最细区只占一部分，全球时间步仍由它控制？如果能用“几何层、地表层、
天气层”分别回答，就掌握了 MPAS 变分辨率网格初始化的核心。

## 参考

- [官方 MPAS-A 网格列表](https://www2.mmm.ucar.edu/projects/mpas/site/downloads/meshes.html)
- [官方旋转与图划分说明](https://www2.mmm.ucar.edu/projects/mpas/mpas_website/build/html/users_guide/preparing_meshes.html)
- [官方初始化 namelist 参数](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/appA_init_namelist.html)
