# EF930 VAB 目标槽映射

状态：已确认，适用源码工作区 `/home/new_ssd1/caoyixi/workspace/android/ef930_2`；最后源码核对日期：2026-08-03。

## 三个必须区分的对象

| 对象 | 含义 | 是否等于“系统正在使用 B” |
|---|---|---|
| LP metadata 中的 `system_b` | B 槽逻辑分区对 `super` 物理 extents 的描述；旧范围可暂时与 A 共用物理 extents | 否，metadata 是持久化描述 |
| dm 块设备映射 | `system_b-base`、COW、snapshot 层组合出的可读写块设备 | 否，可只被 update_engine 打开用于块 I/O |
| 文件系统挂载 | first-stage/`fs_mgr` 将重建的 B 块设备挂载为根目录、`/system`、`/vendor` 等 | 是，设备已实际从 B 启动 |

## 严格时序

```text
T0  A 正常运行
    运行时挂载来自 A；B 没有被挂载。

T1  update_engine 在 A 中写 VAB OTA
    临时映射目标 B 的 snapshot 块设备，按 payload 写块。
    这是 block I/O，不是 mount B 的文件系统。

T2  update_engine 成功、提示 reboot，但仍运行 A
    snapshot 状态、COW、B 的 LP metadata、snapshot-boot 被持久化。
    postinstall 调用 UnmapAllPartitions()，临时 dm 映射被解除。
    B 没有被挂载；只留下将来可重建的 B 视图。

T3  重启并选择 B
    first-stage init 先重建 B 的 dm-linear base、COW、snapshot 设备，
    然后挂载 B 的系统分区视图。

T4  B 首次启动并建立 target snapshot 映射后 merge
    COW 中的新块逐步落实到 B 的 base extents；完成清理后不再需要 snapshot/COW。
```

## base 与 COW

有 snapshot 状态时，`MapPartitionWithSnapshot()` 先创建 `system_b-base`。它是 B 的 LP metadata 指向的真实 `super` 块；旧范围可以仍与 A 共用，扩容范围可以是新分配的 B extents。随后映射 COW，再创建 snapshot 设备。读取某个逻辑块时，COW 中有该块的新版本则优先返回 COW；没有覆盖时才读取 base。

因此，“B 视图由 base + COW 构成”只适用于 B 的 snapshot 块设备已经被重建之后。OTA 成功但尚未重启时，磁盘上有重建材料，却没有已经挂载、对 Android 运行时可见的 B 文件系统。

压缩/VABC snapshot 可能经过 `dm-user`/`snapuserd`；非压缩 snapshot 会走普通 snapshot 映射。两者的块设备组合不同，但“写入时临时映射、成功后解除、B 首启时重建并挂载”的边界不变。

### 已确认：不是 A/B 两套系统同时运行

最后源码核对：2026-08-04。

在 A 运行时，A 的根系统继续使用 `system_a`。update_engine 可以临时建立 `system_b-base`、COW 和 `system_b` 的 dm 块设备并向其写入；这只是同一内核中的第二条 block I/O 路径，不代表 B 的 init、zygote、SystemUI 或应用已经启动。

成功 OTA 后，`PostinstallRunnerAction::CompletePostinstall()` 会完成 `FinishUpdate()`、设置下一启动槽，再调用 `UnmapAllPartitions()` 解除 update_engine 临时映射。重启后 A 的进程和挂载已结束；B 的 first-stage init 才重新建立 B 的 logical/snapshot devices，再进入 B 的挂载流程。

若包声明 postinstall，目标分区可以在 A 仍运行时被只读临时挂载到 `/postinstall` 供检查或脚本执行；这也不是 B 系统启动。

### 已确认：merge 的真正落点

“merge 到真正的 `system_b` 分区”容易造成误解。不存在一份独立于 `system_b-base` 的隐藏 physical `system_b` 拷贝：

```text
system_b          = B 的最终逻辑块设备视图
system_b-base     = B metadata 描述的 real super physical extents
system_b-cow      = 仍未落实到 base 的目标变化
```

在 OTA 写入期，若 B 的逻辑块需要不同于 base 的内容，B 视图经 COW 返回新内容；base 可能仍是旧 A 数据，或甚至是 A 的另一个源分区旧数据。`FinishedSnapshotWrites()` 完成后状态为 `Unverified`，此时仍未重启 B。重启进入 target B 且 first-stage 已建立映射后，`InitiateMerge()` 才允许开始 merge：它要求全局更新状态为 `Unverified` 且当前槽为 `Target`，不等待 Android Framework 的 boot-completed。非 userspace snapshot 会把 dm table 切换为 `snapshot-merge`；userspace snapshot 则通知 `snapuserd` 启动/恢复 merge。

merge 逐步把 COW 的最终 B 内容落实到 B metadata 对应的 base physical extents。该 extent 在升级前可能被 A metadata 命名为 `system_a`、`vendor_a` 或其他源分区的一部分；physical extent 本身没有 `_a`/`_b` 名称。merge 完成后删除 snapshot status、COW logical partition 和 /data backing image，普通的 B logical partition mapping 继续使用已经更新的 base。

源码锚点：`target/system/core/fs_mgr/libsnapshot/snapshot.cpp` 的 `MapPartitionWithSnapshot()`、`OpenSnapshotWriter()`、`InitiateMerge()`、`SwitchSnapshotToMerge()`；`target/system/update_engine/payload_consumer/postinstall_runner_action.cc` 的 `CompletePostinstall()`；`target/system/core/init/first_stage_mount.cpp` 的 `CreateSnapshotPartitions()`。

## Recovery direct-write 与普通 VAB 的差别

普通 Android 内 VAB 成功链路是“snapshot/COW 写入 -> `Unverified` -> 重启 B 并重建映射 -> merge”。EF930 Recovery 若无法完成本次 snapshot 准备，full OTA 允许转为 direct-write：它创建没有 `LP_PARTITION_ATTR_UPDATED` 的目标逻辑分区 metadata，随后写入实际 B 逻辑分区；这笔 fallback 不会成为等待 B 首启 merge 的正常 snapshot 事务。

`SnapshotStatus` 仍可能在 fallback 时短暂保留，但它不是“继续启用旧 COW”的命令。`MapUpdateSnapshot()` 必须先读取状态文件；接着 `MapPartitionWithSnapshot()` 发现目标分区缺少 `UPDATED`，输出 `Detected re-flashing of partition, will skip snapshot`，并返回普通 target 设备。源码：`target/system/core/fs_mgr/libsnapshot/snapshot.cpp:2376-2433`、`3601-3631`。

因此 re-flash 的判定来源是 LP metadata 的 `UPDATED` 位，不是 `/metadata/ota/snapshots/<name>` 文件内容。删除这些状态文件会让映射函数在到达 re-flash 判断前失败，正是第一版 Recovery 深度清理补丁不能沿用于 `CancelUpdate()` 的原因。

## 源码锚点与重新验证

- `target/system/core/fs_mgr/libsnapshot/snapshot.cpp:2416-2567`：创建 base、映射 COW、创建 snapshot 或 userspace snapshot。
- `target/system/core/fs_mgr/libsnapshot/snapshot.cpp:3601-3631`：更新期间映射目标 snapshot。
- `target/system/update_engine/payload_consumer/postinstall_runner_action.cc:431-454`：成功后解除临时映射。
- `target/system/core/init/first_stage_mount.cpp:394-415`：first-stage 重建 snapshot 分区后进入挂载流程。

动态分区 metadata、内核 snapshot driver、VABC 配置、init first-stage 或 fs_mgr 实现变化后，必须基于当前源码和设备状态重新确认。
