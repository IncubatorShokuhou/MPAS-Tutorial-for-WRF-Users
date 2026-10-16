# 第 9 课：用 Cartopy 绘制 240 km 基线预报

## 本课问题与范围

本课回答两个问题：MPAS 的一维 `nCells` 数据怎样放到地图上？一张平滑天气图又保留了
多少原生网格信息？

这里使用的是第 6 课已经成功运行的 **x1.10242、约 240 km 全球基线预报**，不是第 8 课
的北京 92–25 km 网格。后者目前只完成网格旋转，static 仍受共享资料权限阻塞，也尚未生成
VR 初值和预报。先用已知正确的基线结果学习可视化，可以避免把绘图错误和初始化错误混在
一起。

![240 km 基线预报的 Cartopy 快速天气图](images/beijing_cartopy_t2m.png)

## 三个工具分别做什么

一句话版本：netCDF4 负责取数，Matplotlib 负责画线和填色，Cartopy 负责把经纬度放到
地图投影上。Cartopy **不会自动理解 MPAS 的 cell/edge/vertex 拓扑**。

WRF 是有规则 `i,j` 拓扑的曲线网格，而本例 MPAS 地面场是 `(Time,nCells)`。每个值要与
同一下标的 `latCell/lonCell` 配对，才能知道它位于地球上的哪里。

## 操作一：在第 7 课环境中追加 Cartopy

第 7 课已经在 Git 忽略的 `work/` 中创建环境并安装 NumPy、netCDF4 和 Matplotlib。从
仓库根目录激活它，只追加地图投影库 Cartopy；若跳课阅读，请先执行第 7 课的环境步骤：

```bash
source work/venv-post/bin/activate
python -m pip install cartopy
python -c 'import numpy, netCDF4, matplotlib, cartopy; print(cartopy.__version__)'
```

UXarray 是面向非结构网格的可选 Python 库，本课脚本没有使用它，不需要为了运行本例而
安装。Cartopy 第一次调用 50 m 海岸线和国界时可能下载 Natural Earth 数据。查看缓存目录：

```bash
python - <<'PY'
import cartopy
print(cartopy.config['data_dir'])
PY
```

离线计算节点应先在联网节点触发一次下载，并把缓存复制到可读位置。

## 操作二：先证明两个文件属于同一次模拟

本例 diagnostics 没有经纬度，所以脚本从 `init.nc` 读取坐标。仅检查两个文件都有
10242 个 cell 还不够：两张不同但同尺寸的网格也会通过。MPAS 文件的 `file_id` 和
`parent_id` 可以提供额外的来源链检查：

```bash
python - <<'PY'
from netCDF4 import Dataset

coord = 'work/beijing_240km_2026101500/x1.10242.init.nc'
diag = 'work/beijing_240km_2026101500/diag.2026-10-16_00.00.00.nc'
with Dataset(coord) as grid, Dataset(diag) as data:
    assert len(grid.dimensions['nCells']) == len(data.dimensions['nCells'])
    assert grid.file_id in data.parent_id.splitlines()
    print('same lineage:', grid.file_id, 'nCells =', len(grid.dimensions['nCells']))
PY
```

这项检查比只看文件名可靠；绘图脚本会自动重复同一检查，有来源元数据却不匹配时就终止。
若旧文件缺少 `file_id/parent_id`，它会警告并退化为 `nCells` 检查；此时必须另核对网格
校验和。正式归档还应记录模式版本和配置文件。

## 操作三：画一张真实基线预报图

```bash
python tools/plot_mpas_cartopy.py \
  work/beijing_240km_2026101500/x1.10242.init.nc \
  work/beijing_240km_2026101500/diag.2026-10-16_00.00.00.nc \
  --output work/beijing_240km_2026101500/cartopy_t2m.png

test -s work/beijing_240km_2026101500/cartopy_t2m.png
```

这是 2026-10-15 00 UTC 起报后 24 小时的产品（预报时效简写为 F024）。填色为 2 米温度，黑线为海平面气压，箭头为
10 米风，星号为北京。脚本应打印选中的 cell 数和输出路径。240 km cell 很稀疏，图面的
平滑外观来自绘图插值，不代表北京获得了更高分辨率预报。

## projection 与 transform 不是一回事

脚本中的核心设置是：

```python
import cartopy.crs as ccrs

data_crs = ccrs.PlateCarree()
projection = ccrs.LambertConformal(
    central_longitude=115,
    central_latitude=38,
)
```

`data_crs` 回答“输入的 `lonCell/latCell` 是什么坐标”；`projection` 回答“画布怎样投影”。
把数据交给 `tricontourf`、`contour`、`quiver` 或 `scatter` 时都要写
`transform=data_crs`，否则 Cartopy 会把经纬度数值误当作 Lambert 平面坐标。

这与 WRF 的 `map_proj=lambert` 不同：MPAS 动力计算发生在球面网格上，Lambert 在这里
只改变地图显示，不改变模式网格或数值结果。

## 从离散 cell 到连续色斑

脚本在东亚窗口内根据 cell 中心重新构造 Delaunay 三角形，再用 `tricontourf` 填色。
Delaunay 的意思是“仅根据点坐标重新连三角形”；它没有使用 MPAS 原生
`verticesOnCell/cellsOnCell` 连接关系。

这种做法适合区域快速诊断，但有三个边界：

1. 它是视觉插值，不守恒，也没有增加模式信息；
2. 当前实现是在经纬度平面三角化，只适合本例这种不跨日期变更线、远离极区的区域图；
3. 面积积分、降水预算和模式间定量比较不能读取插值图片上的数值。

不同目标应选择不同工具：

- 快速看天气形势：cell 中心散点或本课 `tricontourf`；
- 展示原生网格：按 `verticesOnCell` 构造 Voronoi polygon；
- 规则网格定量比较：用 ESMF/TempestRemap 等生成并保存重映射权重；
- 大型原生网格交互分析：可另行学习 UXarray；
- 面积或水量守恒：采用守恒重映射并检查源、目标总量。

## 为什么这里的风可以画

模式三维 `u` 位于 edge，只代表 edge 法向速度，不能直接传给地图上的东西、南北风箭头。
本课使用 diagnostics 中已重建到 cell 中心地理方向的 `u10/v10`。等压面风同理，应先用
`ncdump -h` 确认文件确实包含所需的 `uzonal_*` 与 `umeridional_*`，不要只猜变量名：

```bash
local/io-stack/bin/ncdump -h \
  work/beijing_240km_2026101500/diag.2026-10-16_00.00.00.nc \
  | grep -E 'u10|v10|uzonal|umeridional'
```

图中 `10 m s⁻¹` 标尺给出箭头长度参照；精确风速仍应读取变量或第 7 课的 CSV，不能从
经过投影、抽稀和缩放的箭头上反推数值。

## 本课验收

- Python 环境可导入四个必需包；
- `init.file_id` 出现在 `diag.parent_id` 来源链中，且 `nCells` 一致；
- 成功生成非空 `cartopy_t2m.png`，标题时刻为 2026-10-16 00 UTC；
- 能指出这幅图来自 240 km 基线，而不是北京 25 km 加密预报；
- 能解释连续色斑为何不能用于守恒降水预算。

## 费曼复述

1. Cartopy 是否负责把 `nCells` 变成规则二维数组？——不是，它只处理地图坐标与投影。
2. `projection` 和 `transform` 是否是一回事？——前者描述目标画布，后者描述输入坐标。
3. 同样有 163842 个 cell 的原始 x4 网格和北京旋转网格能否混用坐标？——不能，cell
   数相同不代表地理位置相同。
4. 为什么 240 km 图看起来有连续的小尺度色斑？——绘图三角插值制造了视觉连续性，并未
   增加预报信息。

## 延伸阅读

- [MPAS-A 官方可视化页面](https://www2.mmm.ucar.edu/projects/mpas/site/visualization.html)
- [MPAS-A 用户手册：Visualization](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/visualization.html)
- [官方 2025 实践教程](https://www2.mmm.ucar.edu/projects/mpas/tutorial/StAndrews2025/)
- [MPAS-Plotting Python 示例](https://github.com/mgduda/MPAS-Plotting)
