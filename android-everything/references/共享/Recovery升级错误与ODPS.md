# Recovery 升级错误与 ODPS

最后整理：2026-09-04

## 适用范围

本资料用于 N86P、EF930 以及其它采用同类 Recovery OTA 链路的 Android
项目。它记录的是跨机型的错误结果协议和取证边界，不代表某个机型已经完成
源码修改、编译或设备验证。

## 已确认的协议

统一结果使用固定 16 位十六进制字符串：

```text
OODDPPPPPPPPSSSS
```

字段含义：

|字段|长度|含义|
|---|---:|---|
|O|2 位|最终升级状态|
|D|2 位|错误来源或错误字典|
|P|8 位|主错误码或来源程序的原始返回值|
|S|4 位|次错误码，当前主要保存 nonab 的 CauseCode|

第一版错误来源：

|D|名称|P 的含义|
|---|---|---|
|00|无详细码|没有可靠传到 Recovery 的具体数字|
|01|nonab|Recovery 收到的 `ErrorCode`，`S` 可为 `CauseCode`|
|02|SP|Recovery 父进程直接调用 SP 后拿到的原始返回值|
|03|cert|Recovery 父进程直接调用 cert 后拿到的原始返回值|
|04|ab|Recovery 从 status fd 收到的 `update_engine` 错误码|

`D=04` 表示通用 ab 错误域，不是 EF930 专属。`D=01` 统一称为
nonab，不再使用 `legacy` 这个名称。

## 结果传递链路

第一版正式链路为：

```text
Recovery 收集错误
    -> Recovery 生成 ODPS
    -> BCB/misc 中的 XGD 专用结果记录
    -> LK/Bootloader 读取并校验
    -> androidboot.xgd.ota.result
    -> Android 生成 ro.boot.xgd.ota.result
    -> Android 保存 persist.xgd.ota.result
    -> Update App 读取和解析
```

不要把 ODPS 写进普通 BCB 的 `command`、`status`、`recovery` 或 `stage`
字段。Recovery 完成流程时可能清理这些字段。结果记录应使用平台确认的
misc/BCB 专用保留区域，并至少有 magic、version、length、ODPS 和校验值。

Recovery 不直接依赖 `persist.*`。Recovery 阶段可能还没有可靠的数据分区、
属性服务或 SELinux 环境，跨重启结果由 Bootloader 传入
`androidboot.*` 更稳妥。

## Recovery 能看到什么

### nonab

普通 nonab 路径可以复用现有 updater command pipe 中的：

```text
log error: N
log cause: N
```

Recovery 在已有 `log` 命令处理处记录 `ErrorCode` 和 `CauseCode`，不需要
修改每一个 updater 错误点。

### ab

ab 路径只在 Recovery 确实收到结构化数字时记录：

```text
Error applying update: N
```

收到数字后使用 `D=04`。如果只有 `INSTALL_ERROR` 或一段没有数字的文字，
只能使用 `D=00`，不能因为机型是 ab 就猜测错误码。

### SP 和 cert

只有 Recovery 父进程直接调用，并且返回值在父进程中可见时，才能分别使用：

```text
SP   -> D=02
cert -> D=03
```

普通 `update-binary` 子进程内部的 SP/cert 错误，如果没有通过已有命令管道
传回 Recovery，就不属于 Recovery 可可靠统计的信息。

`sys.xgd.sp.err` 不能单独区分 SP 和 cert。两个流程可能共用这个属性名，
因此只能作为旧 UI 或日志线索，不能据此强行选择 `D=02` 或 `D=03`。

## 结果收口原则

Recovery 内部只维护一个本轮结果收集器：

```text
Reset
    -> 记录 nonab ErrorCode/CauseCode
    -> 记录直接可见的 SP/cert 返回值
    -> 记录直接可见的 ab 错误码
    -> 等待自动重试决策结束
    -> 使用最终 InstallResult 生成 ODPS
    -> 只发布一次
```

`INSTALL_RETRY` 是中间状态。还会自动重试时，不发布最终失败结果。重试
次数耗尽或流程最终结束后再发布。`INSTALL_REBOOT` 是控制动作，不能覆盖
真实的安装结果；类似 `sideload_auto_reboot` 的路径应保存真实
`InstallResult`。

第一版不修改：

```text
update-binary
updater-script
libcert_bin
SP 底层引擎
```

也不新增或依赖 `last_xgd_update_detail`。Recovery 没有收到的错误不猜测、
不补造。

## 应用侧解析原则

应用拿到结果后固定按以下顺序处理：

```text
1. 校验是否为 16 位十六进制。
2. 拆出 O、D、P、S。
3. 先解释 O。
4. 只有失败或包损坏时，再解释 D。
5. 按 D 解释 P；只有 D=01 时把 S 当 CauseCode。
6. 未知值保留原始十六进制和十进制，不跨 D 猜含义。
```

P 是 32 位字段。SP 的负数使用补码保存：

```text
-1  -> FFFFFFFF
-5  -> FFFFFFFB
-10 -> FFFFFFF6
```

应用侧正式参考文件是 `OdpsResult.java`。它同时承担三件事：

1. 读取 `ro.boot.xgd.ota.result` 和 `persist.xgd.ota.result`。
2. 检查并拆分 ODPS。
3. 把已确认的错误码转换为用户可读的描述，未知码保留原值。

## 证据和边界

本专题基于 2026-09-04 前的 N86P/EF930 Recovery OTA 方案整理和已有源码
调研。协议文档、Java 示例和 C++ 示例不等同于构建成功或设备验证成功。

重新使用本资料前，应重新确认：

- 当前机型实际使用 nonab 还是 ab。
- updater 的 `log error/cause` 是否经过当前 Recovery 的 command pipe。
- ab 错误是否经过当前 status fd 以结构化数字传递。
- SP/cert 调用是在 Recovery 父进程还是 updater 子进程。
- Bootloader 与 Recovery 是否使用同一份 BCB/misc 记录布局。
- Android 是否真的生成并保存 `ro.boot.*`、`persist.*` 属性。
