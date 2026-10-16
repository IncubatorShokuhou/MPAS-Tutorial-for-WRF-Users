# 第 8 课：正确设置北京变分辨率网格

## 与 WRF 的根本差别

WRF 用 `ref_lat/ref_lon`、`dx/dy`、`e_we/e_sn` 和地图投影生成规则矩形 domain。
MPAS 的 `namelist.atmosphere` **不生成水平网格**。水平坐标、单元面积、邻接关系和
edge 方向已经写在 `grid.nc` 中，模式只是读取它。

因此 MPAS 网格设计分为四种路线：

1. 下载准均匀全球网格：最简单，没有中心点；
2. 下载全球变分辨率网格并旋转加密区：本教程的北京方案；
3. 用 MPAS-Tools/JIGSAW 设计新的密度函数并生成 SCVT：高级路线；
4. 从全球网格裁剪有限区域：需额外制作侧边界条件。

## 为什么选择 92–25 km

官方 `x4.163842` 有 163842 个 cell，背景约 92 km、加密中心约 25 km，加密区跨度
约 60°。它比 240 km 教学网格有意义，又不会立刻进入百万级单元。`x4` 表示约四倍
分辨率变化，`163842` 是 cell 总数；文件名不是 WRF 的格点尺寸声明。

![旋转到北京后的变分辨率网格](images/beijing_mesh_resolution.png)

## 把加密中心移动到北京

官方网格的加密中心在 `(0°,0°)`。运行：

```bash
./prepare_beijing_vr_mesh.sh
```

核心配置不是 MPAS 模式 namelist，而是 `grid_rotate` 的 `namelist.input`：

```fortran
&input
 config_original_latitude_degrees = 0.0
 config_original_longitude_degrees = 0.0
 config_new_latitude_degrees = 39.9042
 config_new_longitude_degrees = 116.4074
 config_birdseye_rotation_counter_clockwise_degrees = 0.0
/
```

前两项指定原网格中的参考点，后两项指定移动后的目标。最后一项使网格绕目标点作
“鸟瞰”旋转，圆形加密区通常保持 0；椭圆形区域可用它调整长轴方向。

输出是 `work/beijing_92-25km/beijing.x4.163842.grid.nc`。原文件不会修改。

绘制东亚范围的 cell 面积尺度，检查加密区位置：

```bash
python tools/plot_mesh_resolution.py \
  work/beijing_92-25km/beijing.x4.163842.grid.nc \
  --output work/beijing_92-25km/beijing_mesh_resolution.png
```

## 旋转后哪些东西能复用

旋转改变 `latCell/lonCell`、笛卡尔坐标、科氏参数和 edge 方向等地理量，但不改变
cell 的邻接图。因此：

- `x4.163842.graph.info` 和 `graph.info.part.N` 可以直接复用；
- 原始 `static.nc`、`init.nc` 和气象输出绝对不能复用；
- 必须从 `/eds/shared/dm/WPS_GEOG` 为旋转后网格重新插值静态场；
- 必须重新用 GFS 制作初始场。

从本机共享地理资料生成新的 static 文件：

```bash
./generate_beijing_vr_static.sh
tail -n 30 work/beijing_92-25km/log.init_atmosphere.0000.out
```

官方要求静态插值使用一个 MPI task；这一阶段主要受地理数据读取限制。脚本设置
`config_supersample_factor=1`，因为 25 km 网格不需要为 30 秒资料做额外超采样。
生成的 `beijing.x4.163842.static.nc` 可供同一张北京网格的不同起报时次重复使用。

若脚本报告无法读取 `topo_gmted2010_30s/index`，先检查共享目录权限：

```bash
namei -l /eds/shared/dm/WPS_GEOG/topo_gmted2010_30s/index
```

当前账号必须对每个数据子目录具有读取和进入权限。只看得到 `WPS_GEOG` 顶层目录并不
代表 MPAS 能读 tile；应由共享资料管理员添加只读 ACL 或把账号加入相应数据组，不要
复制一份数百 GB 数据来绕过权限。

MPI 进程数必须与 `.part.N` 后缀完全一致。若网格包没有所需的 N，用 METIS 执行：

```bash
gpmetis -minconn -contig -niter=200 x4.163842.graph.info 64
```

## 分辨率、时间步和可信尺度

25 km 是最细的**名义网格间距**，不是所有 cell 的固定边长。`areaCell` 是单位球面
上的面积，`6371 km × sqrt(areaCell)` 可用于直观检查局部尺度，但不等于官方名义间距
定义。模式时间步由最细区控制：经验起点约为
每 1 km 使用 6 秒，因此 25 km 可从 `config_dt=150` 秒开始。稳定性不足时应减小，不能
因为全球大部分区域较粗就采用 92 km 对应的时间步。

25 km 仍需积云参数化，不能显式解析深对流；通常可解释的有效尺度也比网格间距更粗。

## 参考

- [官方 MPAS-A 网格列表](https://www2.mmm.ucar.edu/projects/mpas/site/downloads/meshes.html)
- [官方旋转与图划分说明](https://www2.mmm.ucar.edu/projects/mpas/mpas_website/build/html/users_guide/preparing_meshes.html)

## 费曼检查

旋转网格像转动一个已经画好经纬网的足球：多边形邻居没变，所以图分区能复用；每块
多边形落到的山地、海洋和科氏参数变了，所以 static 和 init 必须重做。若你能解释为何
时间步看北京最细区而不是全球平均分辨率，就掌握了变分辨率积分的基本约束。
