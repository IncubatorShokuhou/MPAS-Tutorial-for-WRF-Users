# 第 3 课：理解 MPAS 网格并设计北京案例

## “北京为中心”在 MPAS 中是什么意思

WRF 常用投影后的矩形网格，需要中心点、水平格点数和格距。MPAS-A 使用球面上的
Voronoi 多边形非结构网格；全球网格没有边界，也没有传统意义上的“区域中心”。因此
中心点只在**变分辨率网格**中表示最高分辨率区的位置。

本教程采用两步走：

1. 先用全球准均匀 `x1.10242` 网格（约 240 km、10242 个单元）跑通全流程，
   预报结果仍可提取北京附近，但不能描述城市尺度天气。
2. 再将官方 `x4.163842`（背景约 92 km、中心约 25 km）加密区从
   `(0°, 0°)` 旋转到北京 `(39.9042°N, 116.4074°E)`。这才是“北京中心网格”。

网格越细，时间步越短，计算量和输出量越大。25 km 适合天气尺度学习，不等于城市级
预报；若要 3 km 对流分辨率，应在流程验证后再使用更密网格。区域有限域还要每 3 小时
生成侧边界条件，初学阶段先使用全球网格可少一个误差来源。

## 本仓库的基线案例

案例固定使用共享盘完整时次：

- GFS：`/eds/shared/energy/gfs/gfs.20261015/00/atmos/`
- 时段：2026-10-15 00 UTC 至 2026-10-16 00 UTC，每 3 小时
- 静态地理数据：`/eds/shared/dm/WPS_GEOG`
- 网格：官方 `x1.10242` 240-km 全球网格

准备工作目录和 GFS 软链接（不会复制约 5 GB 的 GRIB2）：

```bash
./prepare_beijing_case.sh
cd work/beijing_240km_2026101500
./ungrib.exe
tail -n 20 logfile.log
ls FILE:*
```

应得到九个 `FILE:YYYY-MM-DD_HH`。脚本拒绝缺失、空文件和 `.tmp` 文件。

官方静态文件让第一个案例快速可复现。若要亲自从共享 `WPS_GEOG` 重建静态场，下一课
会使用 `config_geog_data_path='/eds/shared/dm/WPS_GEOG/'`；静态插值只需对每张网格执行
一次。

## 下一阶段的北京加密网格

官方变分辨率网格的加密区默认在 `(0°,0°)`，可用 `grid_rotate` 移到北京；旋转只改变
地理坐标，不改变单元连接关系，所以原有图划分仍可使用。之后再重新生成 static、初值
和预报。有限区域方案则用 MPAS-Limited-Area 从全球网格裁剪，适合后续专章，不作为
首次运行路径。

## 参考

- [MPAS-A 官方网格下载与说明](https://www2.mmm.ucar.edu/projects/mpas/mpas_website/build/html/access_code/meshes.html)
- [官方网格准备指南](https://www2.mmm.ucar.edu/projects/mpas/mpas_website/build/html/users_guide/preparing_meshes.html)
- [官方真实资料初始化流程](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)

## 费曼检查

试着向一个 WRF 用户解释：`x1.10242` 中的 10242 为什么不是 `e_we × e_sn`？因为它是
覆盖球面的 cell 总数，没有规则行列。为什么全球 240 km 案例仍能提取北京？因为北京
落在某个全球 cell 中；“没有北京中心”不等于“没有北京”。
