# EF930 VAB 动态分区与 Payload

## 先判定升级类型

| 包类型 | 识别方式 | 主链路 | 不应混用的概念 |
|---|---|---|---|
| VAB payload OTA | 存在 `payload.bin` | `update_engine`、payload offset、snapshot/COW | 传统 `update-binary` |
| 传统 Recovery OTA | 存在 `update-binary`、`updater-script`，无 `payload.bin` | Recovery、edify、updater | `applyPayloadFromZip` |

## VAB 调查顺序

1. 确认入口：Update.apk、本地 PSS demo、XTMS 网络链路，还是 Recovery。
2. 确认 ZIP 最终内容和 payload metadata offset。
3. 检查 Update.apk 与 PosSystemServiceV3 是否使用相同的最终 ZIP offset 逻辑。
4. 根据首个决定性错误分类，而不是看到“升级失败”就猜签名或 payload。
5. 涉及分区时，再读取 snapshot、COW、metadata 和 dm 映射状态。

## 常见模式

| 现象 | 首要方向 | 需要证据 |
|---|---|---|
| `invalid delta magic` | payload offset 或最终 ZIP 解析 | offset 日志、ZIP metadata、调用点 |
| `kPayloadTimestampError (51)` | 降级时间戳保护 | 当前 `ro.build.date.utc`、payload `max_timestamp` |
| PSS 权限失败 | callerUid、sharedUserId、平台签名、PSS 检查 | Manifest、构建签名、服务日志 |
| source hash mismatch | 增量包基线不匹配 | 当前 slot、包基线、update_engine 日志 |

## snapshot/COW 边界

`super -> dm-linear -> dm-verity -> 文件系统` 是一种常见运行链路。VAB 升级期间可能额外出现 snapshot/COW；COW 可能位于 super 空闲空间或 `/data` 支撑的镜像中，必须以本次设备状态为准。

不要把“升级时为目标 slot 建立临时块映射”说成“目标 slot 已被正常挂载”。更新完成、重启验证和 merge 是不同阶段。具体映射与挂载时序见 `VAB目标槽映射.md`。

### 已确认：正常 VAB 的 payload 写入位置

适用源码：`/home/new_ssd1/caoyixi/workspace/android/ef930_2`；最后源码核对：2026-08-04。

正常 Android 内 VAB 的目标不是“直接写 `system_b-base` 的 real super blocks”：

| snapshot 模式 | update_engine 写入的对象 | base 是否在 OTA 写入期被直接覆盖 |
|---|---|---|
| 非压缩 kernel snapshot | `OpenKernelSnapshotWriter()` 以 `O_RDWR` 打开最终 snapshot device，例如 `/dev/block/mapper/system_b` | 否；dm-snapshot 将写入表示在 COW 中 |
| VABC 压缩 / userspace snapshot | `OpenCompressedSnapshotWriter()` 打开 COW block device，写入 COW operation/data | 否；snapuserd 以后用 COW 构造目标 B 视图并执行 merge |

“写入 B”是对 B 的逻辑块视图写 I/O，不是把 `payload.bin` 原样保存进 COW。payload 操作的 `REPLACE`、`ZERO`、`SOURCE_COPY` 等会产生目标块的新内容或对应的 COW operation；未被覆盖的目标块读取 base。COW 容量在非压缩路径按 payload 的写入 `dst_extents` 计算，而不是先对 A/B 全分区做逐字节 diff。

此结论不适用于 Recovery full OTA 的 direct-write fallback、fastbootd 刷写或显式 re-flash。Recovery full fallback 可以建立不带 `LP_PARTITION_ATTR_UPDATED` 的 target metadata 并直接写真实目标 logical partition，不形成“写 COW 后等待 B 首启 merge”的成功 snapshot 事务。

### 已确认：super COW 与 /data COW 的选择

每个 snapshot 分区独立计算所需 COW 容量：

```text
cow_size = 该分区 payload 操作所需容量（或 VABC manifest estimate）
super_usable = FreeRegions(target metadata) ∩ FreeRegions(current metadata)
cow_partition_size = min(cow_size, super_usable)
cow_file_size = cow_size - cow_partition_size
```

因此一个分区的 COW 可以是：

| 结果 | 后备位置 |
|---|---|
| `cow_partition_size > 0`，`cow_file_size = 0` | 全部为 `super` 的 `<partition>_b-cow` logical partition |
| `cow_partition_size = 0`，`cow_file_size > 0` | 全部为 `/data/gsi/ota/<partition>_b-cow-img.img` backing image |
| 两者都大于 0 | 前段为 super COW，后段为 /data backing image；`MapCowDevices()` 将二者串接为一个 COW block device |

只使用 current 与 target metadata 都认定为空闲的 super 区域，避免把 A 仍在使用、仅因 B 缩小而在 target metadata 中变空闲的范围拿来存 COW。

源码锚点：`target/system/core/fs_mgr/libsnapshot/partition_cow_creator.cpp` 的 `GetCowSize()`、`Run()`；`target/system/core/fs_mgr/libsnapshot/snapshot.cpp` 的 `CreateUpdateSnapshotsInternal()`、`MapCowDevices()`、`OpenKernelSnapshotWriter()`、`OpenCompressedSnapshotWriter()`。

## 三类持久对象不要混淆

| 位置或对象 | 保存的是什么 | 不是什么 |
|---|---|---|
| `/metadata/ota/state` | 更新总状态，例如 `Initiated`、`Unverified` | 不是 system/vendor 的内容 |
| `/metadata/ota/snapshots/system_b` 等 | 每个 snapshot 的 `SnapshotStatus` 控制记录：名称、状态、device/snapshot/COW 大小、分配进度、压缩标志等 | 不是 `system_b` 文件系统，也不是 COW 数据本身 |
| `/data/gsi/ota/*-cow-img.img` 或 super 中 COW extents | COW 块数据的后备空间；file-backed COW 通过 ImageManager 映射成块设备 | 不是 `/data` 已被 Recovery 当作普通可随意删除的目录 |
| `super` 的 LP metadata | `system_a`、`system_b` 等逻辑分区各自指向哪些 physical extents，以及 `UPDATED` 等属性 | 不是 dm 设备本身 |

在 EF930 的原始失败日志中，Recovery 能 `unmap` dm/snapshot 设备，却被 `ImageManager::DeleteBackingImage()` 拒绝删除 `/data` backed image。源码先检查 image 是否仍被映射，随后在 Recovery 默认拒绝删除，因为文件系统可能复用已释放的底层块。源码：`target/system/core/fs_mgr/libfiemap/image_manager.cpp:268-285`。这解释了“能 unmap”不等于“能安全删除 COW 文件”。

## block mapping 不是 mount

Android 内 OTA 的 `MapUpdateSnapshot()` 得到的是一个临时块设备路径。`OpenKernelSnapshotWriter()` 以 `O_RDWR` 打开该路径并交给 payload writer 写块；没有把 B 槽的 ext4/erofs 文件系统挂载为 `/system`。源码：`target/system/core/fs_mgr/libsnapshot/snapshot.cpp:3601-3631`、`3725-3750`。

正常 VAB 只有在重启选中 B 槽后，first-stage init 才重建所需逻辑/snapshot 映射，随后的挂载流程才使用 B 视图。`InitiateMerge()` 只允许在全局状态仍为 `Unverified` 且当前处于 target slot 时开始，因此它不等待 Android Framework 的 boot-completed；Recovery 的 full direct-write fallback 不形成这笔成功的 snapshot 事务，因此不应把它描述为“写 COW 后在 B 首启 merge”。

## EF930_2 的 VAB 状态

状态：已确认，适用源码工作区 `/home/new_ssd1/caoyixi/workspace/android/ef930_2`；最后源码核对日期：2026-08-03。

| 阶段 | 已确认的状态 | 不应得出的结论 |
|---|---|---|
| A 槽运行、payload 写入中 | `update_engine` 可通过 `MapUpdateSnapshot()` 临时映射目标 B 的块设备并进行块 I/O | 目标 B 文件系统已被 mount |
| payload/postinstall 成功、尚未重启 | `FinishedSnapshotWrites()` 写入 `snapshot-boot` 和 `Unverified`；postinstall 成功后设置下次启动槽，并调用 `UnmapAllPartitions()` | B 已被作为 `/system_b` 或根目录使用 |
| 重启并从 B 启动 | first-stage init 调用 `CreateLogicalAndSnapshotPartitions()`，重建逻辑分区/snapshot 块设备，再由挂载流程使用 B 的视图 | B 已完成 merge，或物理上已是独立完整拷贝 |
| B 启动后的 merge | `InitiateMerge()` 要求状态为 `Unverified`、当前处于 target slot，且 snapshot 块设备已映射；它不等待 Android Framework 的 boot-completed | 可以在仍运行 A 时把 COW 直接 merge 到共享旧范围 |

`snapshot-boot` 在 `Initiated -> Unverified` 切换前写入，既供 first-stage init 判断 snapshot 启动路径，也用于识别回滚。其存在时，不能把名义上仍为 `Initiated` 的状态简单当作可安全删除的纯写入中事务。

源码锚点：

- `target/system/core/fs_mgr/libsnapshot/snapshot.cpp`：`MapUpdateSnapshot()`、`FinishedSnapshotWrites()`、`InitiateMerge()`。
- `target/system/update_engine/payload_consumer/postinstall_runner_action.cc`：成功后 `FinishUpdate()`、设置下一启动槽、`UnmapAllPartitions()`。
- `target/system/core/init/first_stage_mount.cpp`：`CreateLogicalAndSnapshotPartitions()`。

## Update.apk 的 ZIP payload 进度

状态：已确认，适用源码工作区 `/home/new_ssd1/caoyixi/workspace/android/ef930_2`；源码、合并 target-files 和设备日志核对日期：2026-08-03。

Update.apk 通过 QSSI system 侧的 `/system/bin/update_engine` 对 ZIP 内的 `payload.bin` 执行 VAB OTA。`UpdateAttempterAndroid::BytesReceived()` 以 `bytes_received / payload.size` 回调进度。ZIP 读取时，fetcher 的 seek offset 是 ZIP 绝对偏移，`base_offset_` 才是 `payload.bin` 起始偏移，因此进度必须使用 payload 相对偏移。

| 场景 | 实际二进制和代码来源 | 进度接收者 | 本问题的处理范围 |
|---|---|---|---|
| Android 内 Update.apk | QSSI target-files 的 `SYSTEM/bin/update_engine`；源码为 `qssi14/system/update_engine` | Binder `IUpdateEngineCallback`，再由 Update.apk 显示 | 功能修复必须保留 |
| Recovery VAB sideload | Recovery 镜像内的 `update_engine_sideload`；源码为 `target/system/update_engine` | `status_fd` 管道到 Recovery 图形进度条 | 仅当要修正 Recovery 进度条提前走满时保留 |
| Windows `adb sideload` 终端 | 主机 `adb.exe` | 主机终端 | 不属于 Android 镜像，不能由本修复改变 |

正常系统与 Recovery 都有 `DownloadAction`、`SeekToOffset()` 和 `ReceivedBytes()`。`DownloadAction` 用 `MultiRangeHttpFetcher` 包装底层 `FileFetcher`；每次开始 range 时，外层以 ZIP 绝对 offset 调用 `SeekToOffset()`。旧逻辑把这个绝对 offset 直接写入 `bytes_received_`，再除以 payload 长度，可能得到大于 `1.0` 的进度。修复为经下界保护的 `bytes_received_ = offset - base_offset_` 后，计数从 payload 相对 offset 开始。

| Android 内 Update.apk 修复文件 | 已确认改动 |
|---|---|
| `qssi14/system/update_engine/download_action.cc` | `SeekToOffset()` 从 `bytes_received_ = offset` 改为经下界保护的 `bytes_received_ = offset - base_offset_` |
| `qssi14/system/update_engine/download_action_android_unittest.cc` | 新增 ZIP 前缀场景单测，断言回调收到 `payload_size / payload_size` |

Recovery 的 `update_engine_sideload` 会通过 `status_fd` 发送 `progress 0.5 0` 和 `set_progress <fraction>`；Recovery UI 接收后把 fraction 限制在 `0.0` 到 `1.0`。因此 Recovery 不显示 133% 数字，但旧逻辑会使当前图形阶段过早走满。Windows 主机 `adb sideload` 的传输百分比属于另一条统计链路，不能用于判定本节修复是否生效。

## QSSI 与 target-files 合并边界

状态：已确认，适用源码工作区 `/home/new_ssd1/caoyixi/workspace/android/ef930_2`；最后核对日期：2026-08-03。

EF930 的 `qssi14` 和 `target` 是 Qualcomm 拆分构建的两套输入树，而不是“目录名与物理分区一一对应”。构建先生成 QSSI framework partial target-files 与 bengal_515 vendor partial target-files，再执行 `merge_target_files`，最后以 merged target-files 生成 OTA。

```text
qssi14 qssi-target_files
  --framework-item-list--> SYSTEM/*, PRODUCT/*, SYSTEM_EXT/*, IMAGES/system.img

target bengal_515-target_files
  --vendor-item-list-----> VENDOR/*, ODM/*, boot/recovery, IMAGES/vendor.img

merge_target_files
  -> merged-qssi_bengal_515-target_files.zip
  -> merged-qssi_bengal_515-ota.zip
```

本次检查中，QSSI target-files 内 `IMAGES/system.img` 与 merged target-files 内同名镜像 SHA-256 相同；target 的 partial target-files 不含 `IMAGES/system.img`。合并完成后，构建脚本将 merged target-files 的 `IMAGES/*.img` 解压到 `target/out/target/product/bengal_515/`，所以该目录出现 `system.img` 是合并产物回落，不证明 system 内容来自 target partial target-files。

源码锚点：

- `target/vendor/qcom/opensource/core-utils/build/build.sh`：选择 QSSI framework target-files、bengal_515 vendor target-files，调用 `merge_target_files` 和 `ota_from_target_files`。
- `target/out/dist/merge_config_system_item_list`：列出 QSSI/framework 项。
- `target/build/make/tools/releasetools/merge/merge_target_files.py`：按 framework/vendor item list 原样提取项目。
- `target/vendor/qcom/opensource/core-utils/build/build.sh`：把 merged `IMAGES/*.img` 解压回 target 的 `$OUT`。

target-files 的完整目录职责、正常 `system.img` 构建与 target-files 重建、`fs_config`/`filesystem_config.txt`、A/B 增量输入和线刷包边界见 `专题/target-files与镜像打包.md`。

## 高风险动作与重新验证

不得自行删除 `/data/gsi/ota`、snapshot 元数据或 COW 文件。更换 fs_mgr/update_engine 分支、VABC 配置、动态分区布局、ZIP 封装、payload 入口或断点续传实现后，重新执行源码与设备日志验证。
