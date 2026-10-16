# 第 0 课：把 WRF 知识迁移到 MPAS-A

## 本课目标

本课只建立一张全流程地图，不要求运行程序。读完后，你应该能说清楚 WRF 与 MPAS-A
分别在哪里定义水平网格，以及 GFS、静态地理资料和模式初值如何汇合。

## 先用一句人话讲明白

WRF 通常在投影后的矩形方格上计算；本教程先让 MPAS-A 在铺满全球的多边形网格上计算。
动力和物理仍是熟悉的大气模式问题，真正需要重建的是对**水平网格、预处理和空间下标**
的直觉。MPAS-A 也支持从全球网格裁剪有限区域，但那不是第一次运行的起点。

![WRF 到 MPAS 工作流对照](images/wrf_mpas_workflow.svg)

图中最重要的关系是两条独立支路：`grid.nc` 加 WPS_GEOG（WPS 静态地理数据目录）
生成带地表属性的 `static.nc`；GFS 经 `ungrib.exe` 生成 `FILE:*` 中间文件。两者到
制作 `init.nc` 时才汇合，`grid.nc` 并不是 `ungrib.exe` 的输入。

## 先认识三个网格位置

MPAS 网格由多边形组成：一个多边形区域叫 **cell**，两块 cell 的公共边叫 **edge**，
边的交点叫 **vertex**。`nCells`、`nEdges`、`nVertices` 分别是这三类位置的总数，
不是 WRF 的规则行列数。第 3 课会解剖它们，第 7 课再说明变量放在哪类位置。

## 用你熟悉的 WRF 作翻译

| 你在 WRF 中做的事 | MPAS-A 对应做法 | 最重要的差异 |
|---|---|---|
| 用 `geogrid.exe` 定义 domain | 选择或生成 `grid.nc` | 网格在模式 namelist 之前已存在 |
| 写中心、投影、`dx/e_we` | 选择网格；必要时旋转已有加密区 | 不能用 namelist 生成全球网格 |
| 用 `ungrib.exe` 解码 GFS | 仍用 `ungrib.exe` | 这一步不知道最终 MPAS 网格 |
| `metgrid.exe` + `real.exe` | MPAS 初始化器 | 插值到非结构网格并建立垂直状态 |
| `wrfinput_d01` | `*.init.nc` | 保存 MPAS 网格上的起报状态 |
| `wrfbdy_d01` | 全球案例没有对应物 | 闭合球面没有侧边界 |
| `namelist.input` | `namelist.atmosphere` + `streams.atmosphere` | namelist 管计算，streams XML 管读写 |
| `(south_north, west_east)` | `nCells/nEdges/nVertices` | 没有规则 `i,j` |

仓库安装后的初始化器名为 `mpas_init_atmosphere`；案例目录把它链接成官方文档常用的
`init_atmosphere_model`。两者是同一个程序，不是两个处理步骤。

## 四类数据状态文件

1. `grid.nc`：多边形地球仪，保存位置、面积和邻接关系；
2. `static.nc`：在该地球仪上加入地形、土壤和土地利用；
3. `FILE:*`：WPS 从 GFS 解码出的 intermediate（中间格式）气象资料；
4. `init.nc`：把 `static.nc` 和某一时刻的气象资料组合成完整起报状态。

`init.nc` 不是单独运行所需的全部文件。预报脚本还会准备 namelist、streams、物理查找表
和 MPI 网格分工文件；这些名称分别在第 3、5、6 课首次实际使用时定义。全球案例不需要
LBC（lateral boundary conditions，侧边界条件），有限区域案例才需要。

## 费曼检查：只回答本课已经讲过的内容

1. 为什么 `namelist.atmosphere` 里没有 WRF 式的 `dx` 和 `e_we`？
2. 为什么更换 MPAS 网格后，GFS 对应的 `FILE:*` 通常可以复用，而 `static.nc` 不行？
3. 为什么全球 MPAS 案例没有 `wrfbdy_d01` 的对应文件？

答案应分别包含：水平网格已写入 `grid.nc`；`ungrib` 与目标网格无关，而静态场已经插值
到特定网格；全球球面没有侧边界。本课检查只使用上文已经定义的概念。

## 学习路线

先跑 240 km 全球网格以验证工具链，再把 92–25 km 变分辨率网格的加密区移到北京。
每一课都按同一顺序学习：**输入是什么 → 新概念是什么 → 执行什么 → 哪个输出证明成功**。
