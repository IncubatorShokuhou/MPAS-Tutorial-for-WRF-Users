# 第 0 课：把 WRF 知识迁移到 MPAS-A

## 先用一句人话讲明白

WRF 是在一张投影后的方格纸上算天气；MPAS-A 是在整个球面铺满大小可变的多边形后
算天气。动力和物理仍然是熟悉的大气模式问题，真正需要重建的是你对**水平网格、预处理
和输出下标**的直觉。

![WRF 到 MPAS 工作流对照](images/wrf_mpas_workflow.svg)

## 用你熟悉的 WRF 作翻译

| 你在 WRF 中做的事 | MPAS-A 对应做法 | 最重要的差异 |
|---|---|---|
| `geogrid.exe` 定义 domain | 选择或生成 `grid.nc` | 网格在 namelist 运行前已经存在 |
| `namelist.wps` 写中心、格距、格点数 | `grid_rotate/namelist.input` 移动加密区 | 不能用 `e_we/e_sn` 定义 MPAS 全球网格 |
| `ungrib.exe` 解码 GFS | 仍使用 `ungrib.exe` | 这是两套流程最相似的一步 |
| `metgrid.exe` 插值气象场 | `init_atmosphere_model` | 同时建立 MPAS 垂直网格 |
| `wrfinput_d01` | `*.init.nc` | 包含非结构网格上的完整初值 |
| `wrfbdy_d01` | 全球模式不需要；有限区域用 `lbc.*.nc` | 全球网格没有侧边界 |
| `namelist.input` | `namelist.atmosphere` + `streams.atmosphere` | 计算配置和 I/O 配置分开 |
| `(south_north, west_east)` | `nCells/nEdges/nVertices` | 不存在规则 `i,j` |

## 只记住四种文件

把整个真实资料预报压缩成四个名词：

1. `grid.nc`：空白多边形地球仪，只含几何与连接关系；
2. `static.nc`：给地球仪贴上地形、土壤和土地利用；
3. `FILE:*`：WPS 解码出的规则经纬度气象资料；
4. `init.nc`：把 GFS 和 static 合并并插值到 MPAS 网格后的起报状态。

模型运行只需把 `init.nc` 随时间向前积分；周期 SST、重启和有限区域 LBC 是之后增加的
能力，不要在第一次运行时同时学习。

## 费曼检查：你能讲回来吗？

读完本课，试着不用术语回答：

1. 为什么在 `namelist.atmosphere` 里找不到 `dx` 和 `e_we`？
2. 为什么旋转北京加密区后，`graph.info.part.64` 能复用而 `static.nc` 不能？
3. 为什么 MPAS 的模式风 `u` 不能直接当成 WRF 的 `U`？

如果答不出来，答案分别是：网格已预先生成；旋转不改变邻接关系但改变地理位置；MPAS
的 `u` 是 edge 法向速度，而不是固定东西方向速度。

## 学习路线

先跑 240 km 全球网格，目的是验证工具链；再跑北京 92–25 km 变分辨率网格，目的是
学习 MPAS 的真正优势；最后才进入有限区域、资料同化和化学。每一课都应能回答三个问题：
“输入是什么、程序改变了什么、输出如何证明它成功”。
