# Mino1 内核 USB 与 GPIO3

状态：部分确认  
适用范围：MT6739 底座检测 GPIO3、USB 枚举与 pinctrl  
创建日期：2026-08-04

## 资料边界

| 项目 | 内容 |
|---|---|
| 本专题回答的问题 | MT6739 GPIO3 底座检测、pinctrl 配置与无充电触点设备的 ADB 枚举关联 |
| 不覆盖的范围 | 其他 USB/CDC/ADB 故障、GPIO3 的精确内部电阻值、未读取到的板级原理图 |
| 证据来源 | 2026-08-04 `git show 0e384070c`、产品 DTS 与 MTK pinctrl 源码只读检查 |

## 已确认事实

| 方向 | 事实 | 状态 | 证据与重新验证条件 |
|---|---|---|---|
| 底座检测 GPIO | 产品 DTS 的 `ext_base` 节点将 `gpio_dz_det` 定义为 `<&pio 3 0>`，即 pio provider 的 GPIO3 | 已确认 | `A12/kernel-4.19/arch/arm/boot/dts/AGN_H1504TQ_GO_XGD.dts`；板级连线未在本轮核验 |
| GPIO3 修复提交 | 内核提交 `0e384070c84a57efd0d1e4a39118fb495888275f` 为 `&pio` 增加 GPIO3 的 `default` pinctrl 配置 | 已确认 | 2026-08-04 `git show --stat`、DTS diff |
| 配置内容 | 状态包含 `PINMUX_GPIO3__FUNC_GPIO3`、`slew-rate = <0>`、`bias-pull-up = <MTK_PUPD_SET_R1R0_01>`、`input-enable` | 已确认 | 上述提交的 DTS diff；不能从该宏单独推断精确阻值 |
| pinctrl 生效机制 | `pinctrl-0` 引用 GPIO3 状态；MTK pinctrl 解析状态节点的子节点并读取 `pinmux` 与通用 pinconf 属性 | 已确认 | `drivers/pinctrl/devicetree.c`、`drivers/pinctrl/mediatek/pinctrl-mtk-common.c`；适用当前 MT6739 内核基线 |
| 提交声明的影响 | 提交信息将“未配置 GPIO3 上拉输入”与“无充电触点 Mino1 ADB 无法使用”关联 | 部分确认 | 提交说明是源码维护者结论；本轮未以同一硬件条件重新刷机验证 |
| 同提交的 C 类型修正 | `mtk_chg_type_det.c` 将 `ext_base_is_host_mode()` 声明从 `int` 调整为 `bool` | 已确认 | `0e384070c` diff；尚未单独分析运行时影响 |
| 当前工作树是否包含修复提交 | 当前 `A12/kernel-4.19` HEAD 为 `65817556c6389fb7e6f3dacaf6fda921f529b069`，包含 `0e384070c`；产品 DTS 已存在 `gpio3_pins_default`/`gpio3defaultcfg`。该状态由 2026-08-05 从 `e94125e...` 对 `MTK8765_A13/MTK8765-dev` 的 fast-forward 同步得到 | 已确认 | 2026-08-05 `git fetch --prune`、`git merge --ff-only`、祖先检查与限定 DTS 搜索；同步前的 3 个本地 printk 调试改动已导出补丁、模拟重放并恢复，后续变更 HEAD 或 DTS 时重新验证 |

## GPIO3 的 pinctrl hog 机制

当前 DTS 中的 `0e384070c` 代码在 `&pio` 节点自身放置 `pinctrl-names = "default"` 与 `pinctrl-0 = <&gpio3_pins_default>`。这不是普通外设在 probe 前选择状态，而是 pinctrl controller 的 **hog** 配置：

```text
MTK pio driver 注册 pinctrl controller
  -> pinctrl_enable(pctldev)
  -> pinctrl_claim_hogs(pctldev)
  -> create_pinctrl(pio device, pio pctldev)
  -> 查找并选择 "default"
  -> 解析 gpio3defaultcfg / pins_cmd_dat
  -> 配置 GPIO3 的 mux、上拉、输入使能和 slew-rate
  -> ext_base 后续再经 GPIO API 读取 GPIO3
```

| 关系 | hog | 普通 consumer |
|---|---|---|
| DTS 属性所在节点 | pinctrl provider 自身，例如 `&pio` | 使用引脚的设备，例如 `&i2c2` 或理论上的 `&ext_base` |
| 谁触发状态选择 | `pinctrl_enable()` 内的 `pinctrl_claim_hogs()` | 设备核心在对应 consumer driver probe 前绑定其 pinctrl 状态，或 consumer driver 显式选择状态 |
| 何时配置 | pio controller 注册阶段，适用于启动早期必须稳定的 PAD 配置 | consumer 准备使用该硬件时 |
| 当前 GPIO3 修复的意义 | 在 ext_base 首次读取底座检测脚前，预先使 GPIO3 成为稳定上拉输入 | 若改为普通 consumer 方式，需确认 ext_base 的 probe 时序和错误路径 |

通用解析器从 `pinctrl-0` 的 phandle 找到 `gpio3defaultcfg`，再向上查找其所属 controller。hog 场景下，`dt_to_map_one_config()` 收到当前 `hog_pctldev`；父节点到达当前 `pio` 时直接使用它，避免“必须先注册 pio 才能解析 pio 自己的状态”的循环依赖。随后 MTK 的 `mtk_pctrl_dt_node_to_map()` 遍历状态节点 `gpio3defaultcfg` 的子节点 `pins_cmd_dat`，读取 `pinmux` 和通用 pinconf 属性生成硬件映射。

hog 表示“controller 注册时预先选择此状态”，不是对 GPIO3 的永久硬件锁。后续若其他设备错误地选择 GPIO3 的 UART、I2C 等冲突功能，仍可能覆盖或冲突；任何引脚复用结论均需以当前 DTS、驱动和板级用途重新确认。

## 调查与验证

1. 先确认当前源码工作区、产品配置、包或设备状态。
2. 从首个决定性错误或完整调用链开始，区分源码行为、日志事实和剩余假设。
3. 涉及刷机、重启、sideload、清数据或硬件操作时，明确标注需要用户确认的动作。

## 重新验证路径

```text
确认运行内核包含 0e384070c
  -> 确认 GPIO3 状态为 GPIO + input-enable + pull-up
  -> 在无充电触点硬件上观察 ext_base 判定与 USB device 枚举
  -> 再判断 ADB 是否恢复
```

USB 线材、Type-C/充电识别、UDC/gadget、adbd、CDC 配置均可能造成相似的“PC 看不到 ADB”现象；没有上述 GPIO3 和运行日志证据时，不得把它们都归因于本专题。
