# Mino1 memleakd 产品集成与提交

状态：部分确认  
适用范围：Mino1 A13 agenew 产品配置、运行开关、feature 属性、SELinux 与 Git 提交流程  
创建日期：2026-09-07

## 模块边界

| 项目 | 内容 |
|---|---|
| 用户可见能力 | 产品包含 `memleakd` 时，上层可通过只读 feature 属性判断 binary 是否存在；运行时另由 `persist.xgd.memleak.enable` 控制是否启用监测 |
| 涉及层次 | A13 `agenew` 产品配置、native `memleakd`、init/SELinux、memtrack HAL、系统日志导出和测试工具 |
| 不覆盖的范围 | 不在 memleakd 中新增直接读取 PVR/ION 节点的接口；本页也不把最新产品配置自动等同于已完成编译或设备验证 |
| 证据来源 | Mino1 A13 源码/Git 当前工作区、Mino1 设备 `MIN1W300049` 的历史实测、memleakd 日志与已有 GPU 专题 |

## 已确认链路

| 环节 | 已确认事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| 产品编译开关 | `/home/new_ssd1/caoyixi/workspace/android/mino1/A13/agenew/mssi_project/AGN_H1504TQ_GO_XGD/SystemConfig.mk` 中 `MSSI_HAVE_MEMLEAKD_FEATURE = yes`；该值为 `no` 时用于量产去掉 `memleakd` | 已确认 | 2026-09-07 通过 Linux 原生工作区读取；产品配置、构建入口或目标产品变化后重新核对 |
| 产品包与 feature 属性 | 同目录 `device.mk` 根据 `MSSI_HAVE_MEMLEAKD_FEATURE` 条件加入 `PRODUCT_PACKAGES += memleakd`，并生成 `ro.xgd.have_memleakd_feature=1`；关闭时生成 `=0` | 已确认 | 2026-09-07 当前工作区读取；需通过实际构建产物和 `getprop` 再验证最终镜像 |
| AEE 配置边界 | `SystemConfig.mk` 中 `MSSI_MTK_AEE_SUPPORT` 保持为 `no`；AEE 不属于 memleakd feature，提交前不能把它作为附带改动 | 已确认 | 2026-09-07 当前提交 `a491a7e` 与父提交差异核对；若出现 AEE 行变化，应在暂存前清理 |
| 运行时启停 | `persist.xgd.memleak.enable=1` 是运行时启用约定；`ro.xgd.have_memleakd_feature` 只表示产品是否携带 binary，不能替代运行时开关 | 部分确认 | 该约定来自 memleakd 集成方案；需要在目标镜像启动后用 `getprop`、init 日志和进程状态重新核验 |
| 内存采集 | memleakd 已验证采集 CPU `statm`/`RssAnon`/`VmSwap`、FD、进程状态和 GPU memtrack 分类；GPU 通过 memtrack HAL 获取 GL/GRAPHICS 归属，不在 daemon 中新增 PVR/ION 直读 | 已确认 | `MIN1W300049` 历史设备验证与 `A13/vendor/nexgo/external/MiscProject/memleakd` 源码；HAL、驱动或输出 schema 变化后重新验证 |
| GPU 风险与证据 | GPU 风险保留 `OBSERVING/LOW/MEDIUM/HIGH/RECOVERED`；当前 evidence 主要在首次升级到 MEDIUM/HIGH 时触发，并有单进程冷却时间。`memleak_report.txt` 侧重当前 Active risk，历史样本和事件仍在 CSV 中 | 已确认 | GPU 阈值和 evidence 触发规则见 `专题/图形内存与memtrack.md` 及已有 memleakd 日志；修改策略或报告过滤逻辑后重新回放日志 |
| PID/UID/包名关联 | 进程实例使用 `(pid,start_time)` 作为 `ProcessKey`；PID 被复用时会建立新实例。UID 到包名映射变化不等于历史进程实例被错误复用，需结合 map、lifecycle 和 start_time 判断 | 已确认 | `MIN1W300049` 复现期间 UID map miss 为 0；测试脚本、Android 包管理或映射文件格式变化后重新验证 |
| U 盘日志导出 | U 盘魔数由 `PosSystemServiceV2` 的 `SecurityCheckService` 检测，`LogController` 将 `/data/misc/memleakd` 复制到 U 盘的 `.sys_log/memleakd`；`nxglog` 提供基础设施，但不是该复制逻辑的唯一归属 | 已确认 | 历史源码定位和设备导出分析；服务类名、魔数或导出目录变化后重新检索 |
| 测试 APK | `INSTALL_FAILED_INVALID_APK ... code is missing` 的直接原因是 APK 缺少 `classes.dex`；不能仅凭错误信息归因于 `android_test_helper_app`、签名或文件传输 | 已确认 | 对比测试 APK 与 Soong testcase 产物确认；测试构建规则或 APK 打包流程变化后重新验证 |
| Git 仓库位置 | 产品配置源在 A13 `agenew` 仓库的 `mssi_project/AGN_H1504TQ_GO_XGD/`；2026-09-07 快照中当前分支为 `cyx-mino1-memleakd`、本地与跟踪远端均为 `a491a7e`，工作区干净 | 部分确认 | 2026-09-07 从 `/home/new_ssd1/caoyixi/workspace/android/mino1/A13/agenew` 读取；2026-09-10 已有新的 N82L 分支和远端提交，提交前仍须重新检查 branch、remote、status 和完整 staged diff |
| Git 历史修复 | 曾出现本地分支指向包含 AEE 合并的 `f4deec5`、远端指向 memleakd 提交 `f740180` 的分叉；`git reset --mixed MTK8765_A13/cyx-mino1-memleakd` 只移动本地分支指针并保留工作区修改，不会删除 AEE 提交。随后 amend/强推覆盖远端提交，最后恢复了 AEE 行 | 已确认 | 相关 Git 输出和当前提交历史；遇到同类问题先比较提交图、父提交和 `git diff`，不要直接使用 destructive reset |
| Git 权限问题 | `.git/objects` 可能通过 `.repo/project-objects` 软链接指向由 root 创建的对象目录；用户可读但不可写时，`git add` 会报 `insufficient permission for adding an object` | 已确认 | 已通过对象目录属主/权限定位，并修复后成功暂存；repo 工作区、属主或共享构建流程变化后重新核验 |
| UID map 运行开关 | `PosSystemServiceV2` 当前恢复为无条件发布：`UidPackageMapPublisher.publish()` 不读取 `persist.xgd.memleak.enable`，`system_app` 也不再需要 `get_prop(system_app, memleakd_prop)`。先前的属性判断版本已被回退 | 已确认（源码和提交） | Mino1 源提交 `c42448c`；N82L 分支提交 `e0c0529`；旧属性判断提交 `a283599f`/`67ba8cb9` 已被强制更新覆盖 |
| UID map 生成时机 | PSS 在 `SecurityCheckService.onCreate()` 和包变化广播时都会无条件调用发布逻辑；不再因为 memleakd 属性为 `0` 跳过。关闭 memleakd 不删除已有 map | 已确认（源码和提交） | 2026-09-11 旧镜像上的属性判断行为不适用于新提交；新镜像重启 PSS 或重刷后应重新验证 boot map、包变化更新和 map_misses |
| `map_misses` 统计 | `ApplyPackageMapping()` 仅对 `uid >= 10000` 且未命中 `uid_packages.map` 的进程计入一次，统计粒度是 `(pid,start_time)` 进程实例，不按采样行重复累计；系统 UID 为空包名是预期行为 | 已确认（源码和 CSV） | 2026-09-11 Mino1 因 map 缺失产生 11 个 app UID miss；N82 map 命中，miss 为 0 |
| 平台期风险回退 | `EvaluateCpuRisk()` 明确设计为“窗口完整但不再上涨则降级”：`HIGH -> MEDIUM -> LOW`；已有风险且最近 30 分钟 FD/RSS/anon 稳定时进入 `RECOVERED` | 已确认（源码和 2026-09-11 实机） | 两台设备的测试进程持续保留约 97 MiB 和 165 FDs，但 10 分钟窗不再增长后从 MEDIUM 降回 LOW；这是当前策略的已知行为，不是采样失效 |

## 2026-09-10 Mino1 到 N82L 移植快照

| 仓库 | Mino1 源分支提交 | 从 N82L-dev 基线 cherry-pick 后的提交 |
|---|---|---|
| `A13/vendor/nexgo` | `92501c53c67a1841c7d7330246c38416f53819cf` | `c4fc88f46aa7d8ca3af8770af0fa4b603d7907cf` |
| `A13/agenew` | `a491a7ec08cd08815b5668b5e16005f8cd45c3a0` | `0487a772492963e98a15d32cdda2209829c8ae63` |
| `A13/system/sepolicy` | `00006cd5f04c7f60661235f442b74e3bcc1a8d8f` | `ae3ac74ae6267b9f85884688355e533f805fc5c9` |
| `A13/vendor/nexgo/packages/apps/PosSystemServiceV2` | `a283599f3a9148acc27f874015169007a73d4a2b` | `67ba8cb9f8aa53ac09d6bf83a9843d8f70be322e` |

源分支为 `cyx-mino1-memleakd`，目标分支为 `cyx-n82l-memleakd`。移植时因 `A13/vendor/nexgo`、`A13/agenew` 存在未提交修改，使用临时 worktree 隔离，cherry-pick 后推送，再移除临时 worktree。

`A13/vendor/nexgo` 当前还有未跟踪的 `external/MiscProject/memleaktest/` 和 `packages/apps/MemLeakTest/`，这些没有进入功能提交，也没有被 N82L cherry-pick。若目标分支需要这些测试工具，必须单独纳入提交并重新验证。

## 未覆盖边界

| 项目 | 当前状态 | 所需证据 |
|---|---|---|
| 最新产品配置的构建产物 | 待验证 | 增量构建后检查 `/system/bin/memleakd`、最终 property 文件和包清单 |
| user/userdebug/eng 三种版本 | 待验证 | 分别确认 `MSSI_HAVE_MEMLEAKD_FEATURE`、包是否进入镜像、只读属性值和运行时启停行为 |
| 设备端 feature 属性 | 待验证 | 刷入对应镜像后使用明确设备序列号执行 `getprop ro.xgd.have_memleakd_feature`，并检查 memleakd 进程 |
| init 默认关闭与 OTA 启用 | 待验证 | 核对 init rc、默认 property、OTA 定制包内容和启动日志；不能只凭源码配置推断每次开机都拉起 |
| N82L 构建与设备验证 | 待验证 | 对四个 N82L 分支分别构建 PSS、sepolicy 和产品包，确认 map 随运行时开关生成/跳过，且 Enforcing 下无 `memleakd_prop` AVC |
| GPU 物理资源归属 | 待验证 | 现有 HAL 统计可以证明 GL/GRAPHICS 账目变化，但不能单独证明具体 PVR、DMA-BUF 或驱动分配路径；若需要该层证据，另行设计并评估 SELinux 权限 |
