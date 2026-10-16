# 第 6 课：从 GFS 生成初值并运行 24 小时预报

## 两次“初始化”不要混淆

MPAS-A 把 WRF 中 `geogrid` 和 `metgrid` 的职责集中在
`init_atmosphere_model`，但推荐分两次运行：

1. `grid.nc + WPS_GEOG → static.nc`：地形、土地利用、土壤类型等；每张网格做一次。
2. `static.nc + FILE:* → init.nc`：把某个时刻的 GFS 插值到 MPAS 水平网格和垂直层。

基线案例使用官方 `x1.10242.static.nc`，跳过耗时的第一步；共享目录
`/eds/shared/dm/WPS_GEOG` 将用于后续北京加密网格，因为旋转后的新网格必须重新生成
静态场。

## 水平与垂直插值

`FILE:2026-10-15_00` 中是规则经纬度 GFS 数据。初始化器先水平插值到 10242 个
Voronoi cell，再将 GFS 等压层转换到 55 层 MPAS 地形跟随混合高度坐标。这里：

- `config_nfglevels=38` 是输入资料层数（包含地面和海平面层）；
- `config_nvertlevels=55` 是输出模式层数；
- `config_ztop=30000` 表示模式顶约 30 km。

初值不能只复制 GFS 风温场：风需要投影到 MPAS edge 法向，地面气压、土壤状态、
水汽和静态地形也必须彼此一致。

## 自动运行

完成上一课的 `ungrib` 后执行：

```bash
NTASKS=16 ./run_beijing_case.sh init
```

脚本使用项目自己编译的 OpenMPI，读取 `x1.10242.graph.info.part.16`，生成：

```text
work/beijing_240km_2026101500/x1.10242.init.nc
```

检查日志时不能只看进程退出码：

```bash
tail -n 30 work/beijing_240km_2026101500/log.init_atmosphere.0000.out
ncdump -h work/beijing_240km_2026101500/x1.10242.init.nc | head -40
```

随后运行冻结 SST 的 24 小时教学预报：

```bash
NTASKS=16 ./run_beijing_case.sh forecast
tail -f work/beijing_240km_2026101500/log.atmosphere.0000.out
```

240 km 网格采用 `config_dt=1200` 秒，每 6 小时输出 history，每 3 小时输出二维
diagnostics。脚本也支持连续执行：

```bash
NTASKS=16 ./run_beijing_case.sh all
```

## 为什么暂时冻结 SST

一天内冻结 SST 对流程教学足够，可把初值问题与周期海温更新问题分开。后续章节将以
`config_init_case=8` 把九个 `FILE:*` 制作成 `sfc_update.nc`，再设置
`config_sst_update=true`。有限区域模拟还要用 case 9 制作每三小时侧边界文件。

## 参考

- [MPAS-A 官方真实资料初始化与运行指南](https://www2.mmm.ucar.edu/projects/mpas/site/documentation/users_guide/running.html)

## 费曼检查

为什么 `static.nc` 能跨日期复用，而 `init.nc` 不能？前者描述固定地表与同一张网格，
后者包含具体起报时刻的大气和陆面状态。为什么 GFS 有几十个等压层，MPAS 却能用 55
层？初始化器做了垂直坐标转换，输入层数与模式层数无需相同，但必须分别配置正确。
