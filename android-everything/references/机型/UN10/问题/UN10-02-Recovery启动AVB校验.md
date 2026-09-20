# UN10 Recovery 启动的 AVB 分支与本地镜像校验失败

状态：已确认  
适用范围：Recovery 无 kernel 路径、顶层 vbmeta 校验、解锁后的 ERROR_VERIFICATION 继续规则  
创建日期：2026-08-05

## 问题摘要

| 字段 | 内容 |
|---|---|
| 现象 | 将本地 `m recoveryimage` 产物单独刷入 Recovery 后，设备在锁定状态下停留于开机图并重启；执行 `flashing unlock` 后，同一 Recovery 可以启动。 |
| 首个决定性错误 | 2026-08-05 从设备 `/dev/block/by-name/logfs` 只读提取的 ABL `UEFILOG1.TXT` 与 `UEFILOG4.TXT` 均记录：`recovery: Hash of data does not match digest in descriptor.` |
| 已确认原因 | 当前 UN10 Recovery 无 kernel。ABL 在 Recovery 模式下使用 `boot` 作为 kernel 来源、将 `recovery` 作为 ramdisk；AVB2 的常规路径读取顶层 `vbmeta`，再用其中的 hash descriptor 校验 `recovery`。本地 Recovery 内容与设备保留的顶层 `vbmeta` 描述符不匹配。 |
| 未确认部分 | 未在本轮直接导出并计算当前设备 `recovery`、`vbmeta` 原始分区哈希；日志已经确认“当前设备实际内容与 descriptor 不匹配”，但需要在下次具备受保护 shell 的 Recovery 会话中按同一启动周期补充镜像级比对。 |
| 安全处置边界 | 不为取证修改锁状态、刷写或重启设备。锁定设备应只启动同一发布物中相互匹配且顶层 `vbmeta` 已签名的镜像集合；修改 Recovery 后需同步生成/签署匹配的顶层 `vbmeta`，不能只单刷 `recovery.img`。 |

## 证据链

| 顺序 | 事实或日志 | 结论边界 | 证据位置 |
|---|---|---|---|
| 1 | 当前产品源码设 `ENABLE_AB := false`、`BOARD_AVB_ENABLE := true`，并设 `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true`。 | 说明该工作区的默认产品配置是非 A/B AVB2、Recovery 构建时不含 kernel；仍须以运行日志确认实际 ABL 分支。 | `target/device/qcom/bengal_515/BoardConfig.mk:27,205`；`bengal_515.mk:10,26`。 |
| 2 | ABL 的 `UEFILOG1.TXT`、`UEFILOG4.TXT` 均有 `Fastboot=0, Recovery:1`、`Booting into Recovery Mode via Boot`，之后有 `BootLinux: TC_mark PartitionName = boot`。 | `Booting into Recovery Mode via Boot` 仅在 `Info->BootIntoRecovery && IsRecoveryHasNoKernel()` 时打印，证明运行时进入了 Recovery 无 kernel 分支，而不是 Recovery 自带 kernel 分支。 | 2026-08-05 只读提取的 `logfs`；`VerifiedBoot.c:2253-2260`、`BootLinux.c:2017-2024`。 |
| 3 | ABL 通过 Recovery header v3+ 且 `kernel_size == 0` 设置 `RecoveryHasNoKernel`。 | “无 kernel”是镜像 header 的运行时属性；不可仅由存在独立 `recovery` 分区或 `AVBf` footer 推断。 | `VerifiedBoot.c:2182-2186`。 |
| 4 | `LoadImageAndAuthVB2()` 中，只有 `!IsRecoveryHasNoKernel()` 的 Recovery 分支才会在非 A/B 时加入 `AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION`。当前分支不满足该条件；其后常规路径将 `recovery` 加入请求分区，并调用 `avb_slot_verify()`。 | 当前 UN10 不采用 Recovery 自身 footer 作为顶层 AVB 元数据，而是走常规顶层 `vbmeta` 路径。 | `VerifiedBoot.c:1502-1515,1625-1645`。 |
| 5 | libavb 未收到 `NO_VBMETA_PARTITION` 时执行“usual path, load `vbmeta`”；收到该标志时才逐个从 requested partition 加载 VBMeta。 | 顶层 `vbmeta` 与镜像尾部内嵌 VBMeta 是两条不同信任元数据路径，不能因为镜像有 footer 就假定实际选择 footer。 | `avb_slot_verify.c:1543-1589`。 |
| 6 | 当前 UEFI 日志先记录 `vbmeta`、`vbmeta_system`，再记录 `recovery: Hash of data does not match digest in descriptor.`，之后仍到达 `BootLinux`。设备属性同时显示 `ro.boot.flash.locked=0`、`ro.boot.vbmeta.device_state=unlocked`、`ro.boot.verifiedbootstate=orange`。 | 设备实际已进行顶层 metadata 解析和 Recovery hash 比对；因已解锁，`ERROR_VERIFICATION` 被允许继续启动。 | 2026-08-05 设备只读属性和 `logfs`；`VerifiedBoot.c:1415,1430-1432,1658-1668`；`avb_slot_verify.c:521-526`。 |
| 7 | 当前 ABL 日志打印 `XGD_CHECK_IMG not enable`。 | 本次失败不是已启用的 XGD 尾部 ECC 自定义校验造成；不能据此推断其他 ABL 版本也禁用了该检查。 | 2026-08-05 `UEFILOG1.TXT`、`UEFILOG4.TXT`；当前源码 `BootLinux.c` 的对应编译禁用分支。 |

## 分支判定规则

### 当前 UN10 的实际路径

```text
Recovery 请求
  -> Recovery header v3+ 且 kernel_size == 0
  -> IsRecoveryHasNoKernel() = true
  -> 以 boot 提供 kernel，recovery 提供 ramdisk
  -> 常规 avb_slot_verify()
  -> 加载顶层 vbmeta
  -> 使用 vbmeta 中的 recovery hash descriptor 校验 recovery
```

这条路径中，顶层 `vbmeta` 的签名和其中的 `recovery` hash descriptor 都参与校验。ABL 是执行验证的一方；`vbmeta` 是它读取的、经受信任公钥验证的元数据，不是两套互斥的验证机制。

### 何时才使用 Recovery 内嵌 VBMeta/footer

在当前 ABL 源码中，必须同时满足以下条件，才会给 `avb_slot_verify()` 传入 `AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION`：

1. AVB2 已启用；
2. `Info->BootIntoRecovery` 为真；
3. `IsBuildUseRecoveryAsBoot()` 为假；
4. `IsRecoveryHasNoKernel()` 为假，即 Recovery 自带 kernel；
5. `Info->MultiSlotBoot` 为假，即非 A/B。

该标志的含义是“不读取独立 `vbmeta` 分区”，不是“不验证”。libavb 会读取 requested `recovery` 分区末尾的 `AVBf` footer，定位其中嵌入的 VBMeta，并改调 `validate_public_key_for_partition("recovery", ...)`。当前 Qualcomm 回调只信任 UserKey 或 `OEMPublicKey`，并将 Recovery 的 rollback index location 设为 1。

若内嵌 VBMeta 的算法为 `NONE`，libavb 返回 `OK_NOT_SIGNED`，随后映射为 `ERROR_VERIFICATION`；这不是“有 footer 就已签名”。锁定状态不能把该结果当作成功，解锁状态才可能因 `ALLOW_VERIFICATION_ERROR` 继续。

## 本次误判与复盘

| 误区 | 为什么会错 | 后续固定检查 |
|---|---|---|
| 把“非 A/B + 独立 Recovery 分区 + 源码存在 `NO_VBMETA_PARTITION`”当成当前运行分支。 | `NO_VBMETA_PARTITION` 前还有 `!IsRecoveryHasNoKernel()` 门槛；该门槛由 Recovery header 运行时决定。 | 先找完整 if 条件，再用 ABL 日志中的唯一分支标记确认运行时值。 |
| 把镜像尾部 `AVBf` footer 说成“Recovery 自己带的签名”。 | footer 是定位内嵌 VBMeta 的容器，不等于其中 VBMeta 已签名；`Algorithm: NONE` 明确表示未签名。 | 同时检查 footer、VBMeta algorithm、签名验证结果、key trust callback。 |
| 把 ABL 验证与 vbmeta 验证说成二选一。 | ABL 是验证执行者；它可以验证顶层 `vbmeta`，也可以在特定分支验证镜像内嵌 VBMeta。 | 描述时明确“谁执行”“元数据在哪里”“公钥由哪个回调信任”。 |
| 用源码默认值直接解释已刷设备。 | 同一源码含多个分支，实际 ABL、锁状态、Recovery header、分区表和发布签名都会改变结果。 | 优先取 `logfs` 的 UEFI 日志；若日志不足，再补设备分区原始比对和实际 ABL 二进制哈希。 |
| 将 fastboot 可写与启动校验通过混为一谈。 | 写入权限和随后 ABL 的启动验证是两个阶段；userdebug/分区策略可允许写入，但锁定状态仍可在启动时拒绝不匹配镜像。 | 每次分别记录“flash 是否允许”“ABL 校验了什么”“是否实际到达 BootLinux”。 |

## 验证与回归

| 验证项 | 结果 | 状态 | 重新验证条件 |
|---|---|---|---|
| 受保护 Recovery shell 下只读采集 `logfs` | 已提取 8 MiB FAT12，解析出五个轮转 `UEFILOG*.TXT`；两个 Recovery 周期出现同一 AVB hash mismatch。 | 已确认 | ABL 版本、`logfs` 格式或持久日志轮转逻辑变化后重新确认。 |
| Recovery 的实际启动分支 | `Booting into Recovery Mode via Boot` 与 `PartitionName = boot` 同时出现，符合 Recovery 无 kernel 分支。 | 已确认 | 修改 Recovery header、`BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE`、ABL 或分区方案后重新确认。 |
| 顶层 `vbmeta` 是否参与当前 Recovery 校验 | 当前分支未设置 `NO_VBMETA_PARTITION`；设备日志出现顶层 `vbmeta` 后出现 `recovery` descriptor hash mismatch。 | 已确认 | 切换 A/B、Recovery-as-boot、Recovery 自带 kernel 或 AVB 实现后重新确认。 |
| 本地 Recovery 与设备 `vbmeta` 的逐字节/摘要关系 | 日志已证明不匹配；当前设备原始分区的独立复算未在本轮完成。 | 部分确认 | 具备只读 shell 时导出当前 `recovery`、`vbmeta`，按 descriptor 的 salt、image size 和 hash algorithm 复算。 |
| 锁定状态的最终失败屏幕/重启策略 | 源码判定为 `EFI_LOAD_ERROR`；本轮未为验证而重新上锁或复现。 | 部分确认 | 仅在用户明确授权且具备可恢复的完整线刷包时验证。 |
