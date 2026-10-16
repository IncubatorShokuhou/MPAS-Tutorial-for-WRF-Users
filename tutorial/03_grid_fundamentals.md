# 第 3 课：理解 MPAS 网格并设计北京案例

## 本课前置与目标

完成第 1 课即可；本课不需要 WPS 或 GFS。你将下载 240 km 教学网格，认识 cell、edge、
vertex 和 MPI 分区文件，并理解“北京为中心”在 MPAS 中究竟指什么。

## 从 WRF 方格换成球面多边形

MPAS 的 SCVT（spherical centroidal Voronoi tessellation，球面质心 Voronoi 剖分）可先
想成铺满足球表面的多边形：每个 **cell** 围绕一个中心，相邻 cell 共用一条 **edge**，
多条 edge 在 **vertex** 相交。

| MPAS 位置 | 存放的典型信息 | 对 WRF 用户的提醒 |
|---|---|---|
| cell | 温度、压力、水汽等标量 | 类似质量点，但没有规则 `i,j` |
| edge | 穿过边的法向风速 | 方向随每条边变化，不固定为东/西 |
| vertex | 涡度等顶点量 | 不能拿 cell 下标直接读取 |

`nCells/nEdges/nVertices` 是三类数组的总长度；`cellsOnCell` 等变量则是邻接表，记录
“谁和谁相邻”。它们共同替代了 WRF 规则网格里隐含的行列关系。

## 准均匀与变分辨率

全球准均匀网格的 cell 大小近似一致，没有必须设置的中心点。变分辨率网格则让 cell
在目标区域逐渐变小；本教程选用的官方网格恰好只有一个圆形加密区，其他设计也可以有
多个或非圆形加密区。

文件名是网格标识，不是 WRF 式尺寸表达式：

- `x1.10242`：约 240 km 的准均匀网格，共 10242 个 cell；
- `x4.163842`：最粗/最细尺度约相差四倍，共 163842 个 cell，官方标称 92–25 km。

这些公里数是名义局地尺度，不是全域固定 `dx`。因此本教程先用 `x1.10242` 跑通流程，
第 8 课才把 `x4.163842` 的加密区移到北京 `(39.9042°N, 116.4074°E)`。

## 下载并解剖基线网格

从仓库根目录只准备网格，不触发尚未学习的 `ungrib`：

```bash
./prepare_beijing_case.sh --mesh-only
CASE="$PWD/work/beijing_240km_2026101500"
local/io-stack/bin/ncdump -h "$CASE/x1.10242.grid.nc" | \
  grep -E 'nCells =|nEdges =|nVertices =|latCell|cellsOnCell'
```

预期维度为 `nCells=10242`、`nEdges=30720`、`nVertices=20480`，并能看到 cell 坐标
`latCell` 和邻接变量 `cellsOnCell`。下载包也带有官方 `x1.10242.static.nc`；它是在这张
网格上已经插值好的地形、土地利用和土壤资料，第 6 课才会使用。

## 首次定义 `graph.info.part.N`

非结构网格没有可直接按矩形切块的行列。为并行计算，先把网格抽象成一张图：一个 cell
是一个图节点，相邻 cell 之间是一条图边。

- `x1.10242.graph.info`：保存整张 cell 邻接图；首行的 `10242 30720` 分别是图节点数
  和图边数，后续每行列出一个 cell 的邻居；
- `x1.10242.graph.info.part.64`：图划分工具 METIS 对上述图的 64 份划分。文件有 10242 行，
  每行的整数 `0…63` 指定对应 cell 由哪个 MPI rank（进程）负责；
- 后缀 `N` 必须与 `mpiexec -n N` 完全一致。它表示运行进程数，不是线程数或网格分辨率。

![MPAS cell、edge、vertex 与 graph.info.part.N 示意](images/mpas_mesh_anatomy.svg)

在当前目录验证：

```bash
head -n 1 "$CASE/x1.10242.graph.info"
wc -l "$CASE/x1.10242.graph.info.part.64"
awk 'NR==1{lo=hi=$1} {if($1<lo)lo=$1; if($1>hi)hi=$1} \
     END{print "rank range:",lo,hi}' "$CASE/x1.10242.graph.info.part.64"
```

应依次看到 `10242 30720`、`10242` 行和 rank 范围 `0 63`。以后看到
`config_block_decomp_file_prefix='x1.10242.graph.info.part.'`，含义就是：MPAS 会把实际
MPI 数附到此前缀上，再读取对应划分文件。

## “北京为中心”到底改变什么

`grid_rotate` 是把**已有**球面网格整体刚性旋转的工具，不负责创造 cell。第 8 课会用它
把官方加密区从 `(0°,0°)` 转到北京。旋转改变每个 cell 的经纬度、科氏参数及 edge
地理方向，却不改变“哪些 cell 互为邻居”，所以原 `graph.info.part.N` 可复用；地形和
土地利用随地理位置变化，因此 `static.nc` 必须重做。

全球网格没有侧边界。以后若裁剪成有限区域，才需 LBC（侧边界条件）；LBC 的更新频率
由外部强迫资料和实验配置决定，并不是 MPAS 固定为三小时。

## 费曼检查

1. `10242` 为什么不是 `e_we × e_sn`？——它是覆盖球面的 cell 总数，没有规则行列。
2. `.part.64` 的每一行和数字分别代表什么？——一行对应一个 cell，数字指定负责它的
   64 个 MPI rank 之一。
3. 为什么旋转后分区可复用而 static 不可复用？——邻接关系未变，实际地理属性已变。

## 参考

- [MPAS-A 官方网格列表](https://www2.mmm.ucar.edu/projects/mpas/site/downloads/meshes.html)
- [官方网格旋转与图划分说明](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/preparing_meshes.html)
