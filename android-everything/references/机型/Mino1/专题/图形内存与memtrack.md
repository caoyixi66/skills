# Mino1 图形内存与 memtrack

建档状态：部分确认
最后验证：2026-08-20
适用源码：Mino1 A13 system + A12 kernel-4.19 + A13/vendor/nexgo/external/MiscProject/memleakd
证据边界：2026-08-19 在 MIN1W300049 上完成 200 轮冷启动复现；N6Pro 的 PVR 节点格式与 Mino1 同族，但不能自动等同

## 核心区分

- `statm`/`smaps` 统计 CPU 地址空间中的页；`memtrack` 统计 GPU/PVR/DMA-BUF 侧账目。
- `dumpsys meminfo` 会把 memtrack 数值复制到 PSS、RSS、Private Dirty 展示字段，不是 HAL 分别测出的三个值。
- `SMAPS_UNACCOUNTED` 是 HAL 对 framework 的统计声明，framework 不会逐页和 `smaps` 对账。
- 当前 memleakd 只读 `statm`、`RssAnon`、`VmSwap` 和 FD，不读 memtrack，因此无法单独发现 GL/EGL 账目增长。

## 调用链

```text
dumpsys meminfo <pid>
  -> android_os_Debug.cpp:430
  -> libmemtrack memtrack_proc_get(): system/memory/libmemtrack/memtrack.cpp:125
  -> AIDL IMemtrack.getMemory()
  -> vendor memtrack HAL
  -> GL: /proc/pvr/memtrack_stats
  -> GRAPHICS: /proc/ion/clients/clients_summary 或 /proc/dma_heap/rss_pid
```

## 当前 Mino1 HAL 分类

| dumpsys 列 | HAL 类型 | 数据源 | flags |
|---|---|---|---|
| GL mtrack | GL | PVR memtrack_stats | SMAPS_UNACCOUNTED, PRIVATE, NONSECURE |
| EGL mtrack | GRAPHICS | ION/DMA-HEAP | SMAPS_UNACCOUNTED, SHARED, SYSTEM, NONSECURE |
| Other mtrack | OTHER/MULTIMEDIA/CAMERA | 当前 HAL 未填充，通常为 0 | - |

对应源码：`A13/vendor/mediatek/proprietary/hardware/memtrack/aidl/default/Memtrack.cpp:297`。

GL 记录会把 PVR 行中 KMalloc、PTMemoryUMA/LMA、GPUMemLMA/UMA 全部相加；`PRIVATE` 表示 PVR 按客户端 PID 归属，不等于物理页独占。EGL/GRAPHICS 的 `SHARED` 表示图形缓冲区可能跨 App、GPU、SurfaceFlinger、HWC 使用，不等于 framework 已按共享者数量分摊。

## 2026-08-19 复现记录

脚本：`D:\xgd\mino1\wujinquan\repro_800mb_forcestop.sh`，200 轮，SystemUI PID 1372。

| 采样点 | GL mtrack | EGL mtrack | TOTAL RSS |
|---|---|---|---|
| before | 9332 KiB | 433 KiB | 114037 KiB |
| loop_50 | 51516 KiB | 426 KiB | 197426 KiB |
| loop_100 | 90353 KiB | 426 KiB | 239055 KiB |
| loop_150 | 125186 KiB | 426 KiB | 263012 KiB |
| loop_200 | 163131 KiB | 426 KiB | 296077 KiB |
| after | 164276 KiB | 442 KiB | 292066 KiB |

结束后 PVR 原始行：`1372,307328,98304,0,0,167813120`，该行合计与 GL mtrack 基本一致。空闲约 3 分钟后 GL mtrack 仍在约 164326 KiB，未明显回落。

结论边界：已复现 PVR/GL 账目随重复界面操作增长且短时空闲未恢复；尚未证明是永久物理泄漏，仍可能是 PVR deferred free、缓存、驱动账目或真实资源泄漏，需要继续看 `driver_stats` 的 Zombie 字段和恢复窗口。

## 复现/取证命令

```bash
pid=$(pidof com.android.systemui)
cat /proc/pvr/memtrack_stats | awk -F, -v p="$pid" 'NR==1 || $1==p'
dumpsys meminfo "$pid" | grep -E "EGL mtrack|GL mtrack|TOTAL PSS|TOTAL RSS"
cat /proc/pvr/driver_stats | grep -E "AllocGPUMemUMA|ZombieGPUMemUMA|DmaBuf"
cat /proc/$pid/status | grep -E "^VmRSS:|^RssAnon:|^VmSwap:"
cat /proc/$pid/statm
```

在测试前、每 50 轮、结束后和空闲后分别采集。判断要点：

- GL/PVR 与 GPU_UMA 一起涨、EGL 不动，偏向 PVR 侧资源或账目问题。
- 空闲后回落，偏向缓存或延迟释放；空闲后不回落，才可作为泄漏/账目异常候选。
- 杀 PID 后该行消失只证明账目挂在 PID 上，不证明物理页立即归还。

## memleakd 扩展建议

- 增加独立字段：`gl_mtrack_kb`、`graphics_mtrack_kb`、`other_mtrack_kb`。
- 独立风险类型：`GPU_ACCOUNTING_RISK`，不要直接混入普通 RSS 泄漏。
- 按选定 PID 低频查询 memtrack，不应对全部 PID 高频扫描，避免 Binder/HAL 开销。
- 输出 CSV 内部保留 HAL 分类名，报告中可显示为用户熟悉的 EGL/GL mtrack。
