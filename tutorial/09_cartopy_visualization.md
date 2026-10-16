# 第 9 课：用 Cartopy 绘制 MPAS-A

## 先把三个工具分工说清楚

用一句话解释：netCDF4 负责取数，Matplotlib 负责画线和填色，Cartopy 负责把经纬度
放到正确的地图投影上。Cartopy **不会自动理解 MPAS 的 cell/edge/vertex 拓扑**。

这和 WRF-Python 的体验不同。WRF 数据已经近似二维规则数组，而 MPAS 地面场是
`(Time,nCells)`：绘图前必须同时取得每个 cell 的 `latCell/lonCell`。

![北京教学预报 Cartopy 图](images/beijing_cartopy_t2m.png)

## 环境检查

官方 2025 实践教程建议准备 NumPy、netCDF4、Matplotlib、Cartopy 和 UXarray。当前机器
已有前四项：

```bash
python - <<'PY'
import numpy, netCDF4, matplotlib, cartopy
print(numpy.__version__, netCDF4.__version__, matplotlib.__version__, cartopy.__version__)
PY
```

Cartopy 第一次调用海岸线可能下载 Natural Earth 数据；离线机器应预先准备其缓存目录。

## 画一张真实预报图

```bash
python tools/plot_mpas_cartopy.py \
  work/beijing_240km_2026101500/x1.10242.init.nc \
  work/beijing_240km_2026101500/diag.2026-10-16_00.00.00.nc \
  --output work/beijing_240km_2026101500/cartopy_t2m.png
```

图中填色是 2 米温度，黑线是海平面气压，箭头是 10 米风，星号是北京。脚本特意从
`init.nc` 读取坐标、从 `diag` 读取场，因为精简的 diagnostics 文件不重复保存网格。

## 为什么选 Lambert 投影

数据仍以经纬度交给 Cartopy：

```python
data_crs = ccrs.PlateCarree()
projection = ccrs.LambertConformal(
    central_longitude=115, central_latitude=38)
```

`PlateCarree` 描述**输入坐标是什么**；`LambertConformal` 描述**画布如何投影**。忘记
`transform=data_crs` 是最常见错误，会让数据被当作投影坐标而错位。

这与 WRF 的 `map_proj=lambert` 不同：MPAS 动力计算发生在球面网格上，Lambert 这里只是
可视化选择，不会改变模式网格或数值结果。

## 从 cell 点变成连续色斑

示例用 cell 中心构造 Delaunay 三角剖分，再 `tricontourf`。优点是简单、适合快速天气图；
缺点是它是可视化插值，并非守恒重映射，也没有忠实画出每个 Voronoi 多边形。

根据目的选择方法：

- 快速诊断：cell 中心散点或 `tricontourf`；
- 展示原生网格：根据 `verticesOnCell` 构造 polygon；
- 与规则资料逐点比较：先生成可复用重映射权重；
- 大型原生网格交互分析：考虑 UXarray；
- 面积积分或降水预算：必须使用守恒重映射，不能把图片插值当数值处理。

## 风为什么能直接画

模式三维 `u` 位于 edge，不能直接传给 `quiver`。这里使用 diagnostics 中已经重建到
cell 中心地理方向的 `u10/v10`。同理，等压面风应优先使用 `uzonal_*` 和
`umeridional_*`。

## 费曼检查

1. Cartopy 是否负责把 `nCells` 变成二维数组？——不是。
2. `projection` 和 `transform` 是否是一回事？——前者是目标画布，后者是输入数据坐标系。
3. `tricontourf` 后的温度能否用于守恒面积平均？——不能，它只是绘图插值。
4. 为什么图看起来比 240 km 网格细腻？——连续填色制造了视觉平滑，不增加预报信息。

## 延伸阅读

- [MPAS-A 官方可视化页面](https://www2.mmm.ucar.edu/projects/mpas/site/visualization.html)
- [MPAS-A 用户手册：Visualization](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/visualization.html)
- [官方 2025 实践教程](https://www2.mmm.ucar.edu/projects/mpas/tutorial/StAndrews2025/)
- [MPAS-Plotting Python 示例](https://github.com/mgduda/MPAS-Plotting)
