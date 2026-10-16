# MPAS 学习地图

## 怎样使用这套教程

目标读者熟悉 WRF，但从未使用 MPAS。不要把 MPAS 当作“换了网格的 `wrf.exe`”。每课
开头的问题只是学习目标：先读完名词解释和 WRF 类比，再执行最小操作并用文件、维度和
日志验收，最后才独立回答“费曼检查”。能不用术语向另一个 WRF 用户讲清楚，才算掌握。

真实资料流程有两条输入支线，`static` 并不是由 GFS 产生：

```text
grid.nc + WPS_GEOG ─────────→ static.nc ─┐
                                         ├─→ init.nc ─→ MPAS-A ─→ output
GFS GRIB2 ─→ ungrib ─→ FILE:* ──────────┘

graph.info.part.N（cell 到 N 个进程的分工表）─→ 并行运行
```

## 推荐顺序

| 课次 | 内容 | 学完应能解释 |
|---:|---|---|
| [0](00_wrf_to_mpas.md) | WRF 到 MPAS 的认知迁移 | 哪些经验能迁移，哪些直觉必须重建？ |
| [1](01_compile_mpas.md) | 编译 MPAS-A | 初始化器与预报程序为何分开？ |
| [2](02_io_stack.md) | MPI 与并行 I/O 栈 | 为什么 MPAS 不只依赖 PnetCDF？ |
| [3](03_grid_fundamentals.md) | 网格基础 | 为什么 namelist 中没有 `dx/e_we`？ |
| [4](04_wps_ungrib.md) | GFS 与 WPS intermediate（ungrib 输出格式） | 为什么 MPAS 流程只需要 `ungrib`？ |
| [5](05_namelists_and_streams.md) | namelist 与 streams | “怎么算”和“读写什么”如何分工？ |
| [6](06_initialization_and_forecast.md) | 初值与 24 小时预报 | `grid/static/FILE/init` 如何连接？ |
| [7](07_output_and_beijing_timeseries.md) | 输出与北京站点 | 如何解释 `nCells/nEdges/nVertices`？ |
| [8](08_variable_resolution_mesh.md) | 北京加密网格 | 如何移动加密区，哪些文件必须重做？ |
| [9](09_cartopy_visualization.md) | Cartopy 快速绘图 | 投影、绘图插值和原生网格有何区别？ |

第 0–7 课的可运行主线使用 240 km 全球网格；某些概念段落会预告后面的变分辨率参数。
第 9 课也故意继续使用这套已经验证的 240 km 输出学习绘图，避免把可视化错误与尚未完成
的北京 VR 初始化混在一起。

## 当前完成状态

| 工作流 | 状态 | 可验证结果 |
|---|---|---|
| GCC/GFortran + MPI/I/O + MPAS-A | 已完成 | 两个 MPAS executable 可运行 |
| GFS → ungrib → 240 km init | 已完成 | 9 个 `FILE:*` 和 `x1.10242.init.nc` |
| 240 km、24 小时全球预报 | 已完成 | 5 个 history、9 个 diagnostics、1 个 restart |
| 北京 92–25 km 网格旋转 | 已完成 | 最近 cell 距北京约 10 km |
| 北京网格 static | 权限阻塞 | 当前账号不能读取 WPS_GEOG 子目录 tile |
| 北京 VR 初值与预报 | 尚未实现 | 不能复用硬编码 x1 网格的运行脚本 |
| Cartopy 天气图 | 已完成 | 使用 240 km 基线的 24 小时（F024）输出 |

这个状态表很重要：“网格文件已生成”不等于“static 已生成”，更不等于“VR 预报已跑通”。

## 三个学习阶段

### 阶段一：建立一条可复现基线

第 0–7 课用粗网格依次验证编译、GFS 解码、初值、模式积分和输出读取。240 km 不适合北京
精细天气预报，但文件小、运行快，能把接口问题逐个暴露出来。

### 阶段二：理解 MPAS 的网格优势

第 8 课将官方 92–25 km 全球网格的加密中心旋转到北京，并明确区分几何网格、static 和
气象初值。共享 WPS_GEOG 权限解决后，再补全 VR 初值与正式积分。第 9 课先用已完成的粗
网格输出建立可靠的 Cartopy 后处理基线，未来可原样迁移到同网格配对正确的 VR 输出。

### 阶段三：后续专题

以下内容是路线图，不是当前已经存在的课程：周期 SST、restart 接续、有限区域与侧边界
条件（LBC）、用 UXarray 分析原生非结构网格、守恒重映射、资料同化，以及实验性的大气
化学方向 CheMPAS-A/MUSICA。完成 MPAS-A 主线后才进入 E3SM、MPAS-Ocean 和耦合模式。

## 每课验收模板

1. 输入文件来自哪里，时间、网格和来源链是否匹配？
2. 本步骤改变的是几何、静态地表、天气状态还是仅仅显示方式？
3. 哪个文件维度、变量、日志行或图能证明成功？
4. 如果换日期、网格或 MPI task 数，必须同步修改哪些 namelist、streams 和分区文件？
5. 哪些结论只是当前教学案例成立，哪些才是 MPAS 的通用规则？
