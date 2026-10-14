# 8311 WAS-110 固件构建器（CN 维护版）

为 MaxLinear PRX126 方案的 XGS-PON / XG-PON SFP 光猫棒（WAS-110 及同方案的棒子）构建 8311 社区固件。

维护者：Hikaru (i@rua.moe)

这个仓库来自 [djGrrr/8311-was-110-firmware-builder](https://github.com/djGrrr/8311-was-110-firmware-builder)（原版），以及在它基础上做国内适配的 [xiao-k233/8311-was-110-firmware-builder](https://github.com/xiao-k233/8311-was-110-firmware-builder)（KillerZ）。xiao-k233 的仓库已于 2026 年归档，现在由 Hikaru 接着维护。

"8311" 是 BELL 的 leet 写法，跟华为没有关系。社区资料见 [pon.wiki](https://pon.wiki/) 和 [8311 Discord](https://pon.wiki/discord/)。

## 版本

版本号沿用 xiao-k233 的 `<上游版本>-CN<n>` 格式，tag 不带 `v`。上游 djGrrr 目前最新是 2.8.3，有新版本时这里跟进，并从 CN1 重新编号。

### 2.8.3-CN5

基于 2.8.3-CN4。

- **omcid 崩溃后自动重启**：omcid 崩溃后不能原地恢复。procd 重新拉起的 omcid 建不好 LCT 的流量捕获，管理口看着是 up 的，实际不通；处于 O5 的棒子会一直掉线，只能断电恢复。现在 procd 通过 `8311-omcid-supervise.sh` 运行 omcid。omcid 被信号杀死时（崩溃，或被 OOM 杀掉），在 `/ptconf/8311/omcid-crash.log` 记一行，然后重启：
  - 试启动期间立即重启，下一次启动的是已提交的分区；
  - 其他情况下，开机不满 10 分钟就等到满 10 分钟再重启，所以即使一开机就崩溃，也至少 10 分钟才重启一次；
  - 连续 3 次因此重启，且两次重启之间 omcid 都没能运行满 30 分钟，就不再重启，交给 procd 处理。

  以下情况交给 procd 重新拉起，不重启：
  - 正常停止（SIGTERM）：转发给 omcid，omcid 5 秒内不退出就 SIGKILL，和以前 procd 的行为一样；
  - 普通退出码；
  - 存在 failsafe 标记；
  - 设置了 `8311_omcid_crash_reboot=0`。

  另外，procd 按启动命令给输出打日志标签，所以 omcid 的日志在 syslog 里的标签从 `omcid[pid]` 变成了 `8311-omcid-supervise.sh[pid]`，按标签筛日志时要用新名字。
- **试启动自动回退**：用 `img_activate` 试启动另一个分区时，同一个 omcid 要连续 2 分钟可达才算成功，否则在时限内（默认 10 分钟，至少是 failsafe 延迟再加 3 分钟）自动重启回 `commit_bank`。
  - 可达的判断是 omcid 在运行，并且 ping 主机（`8311_ping_ip`，默认是管理网关）回应 ping 或 ARP。
  - 提交了该分区，或者出现 failsafe 标记，守卫就结束。
  - `8311_trial_timeout` 可以调整时限，设为 `0` 关闭守卫。
  - 只能处理系统已经启动到 rc.local 之后的故障，比如 omcid、LCT、管理不通；内核本身起不来的情况管不到。
- **远程 syslog**：新增 `8311_syslog_server`，填写 `主机` 或 `主机:端口`，走 UDP，默认端口 514，端口非法时按 514 处理。开机生成配置时就会生效，不需要等外部去补配置。LCT 建立之前产生的日志（开机后大约 1 分钟内）发不出去，只保留在本机的 `logread` 里。
- **修复 pingd 刷屏**：CN 版的 pingd 每 7 秒往 syslog 和串口各写一条 `Starting ping to`，能占到日志总量的四成多。现在只在目标地址变化时写。
- **降低常驻脚本的 CPU 占用**：
  - `8311-vlansd.sh` 原来每 5 秒运行一次 VLAN 解析（要通过 OMCI 管道查询 omcid），还要调用 10 次 `fw_printenv`，稳定状态下占单核 CPU 约 5%，比 omcid 自己还多。现在每轮只读一次环境变量；VLAN 信息每分钟刷新一次，fix-vlans 运行后也会立即刷新；omcid 不在运行时不刷新，免得卡在 OMCI 管道上。
  - `8311-rx_los.sh` 原来每秒 fork 一次 `cat` 读 GPIO，现在改用 shell 内建的 `read`。
- **修复状态页**：
  - `/tmp/8311-vlans` 不存在时（开机早期，或者 `8311_fix_vlans=0` 时一直如此），PON 状态接口返回 500。
  - VLAN 信息里同一张表的 VLAN 号之间没有分隔符，例如 `4143454640`，现在显示为 `41 43 45 46 40`。
- **修复网页设置**：
  - "Fix VLANs" 的默认值显示为 OMCI MIB 模式，但脚本把未设置当作关闭，所以在新棒子上选择默认项保存后其实没有生效。现在默认值改为关闭，与实际行为一致。
  - syslog 地址和 SFP 日期两个输入框的格式校验正则，在浏览器里是非法的，会被直接忽略，现已修正。
- 登录提示和网页页脚里的仓库地址改为本仓库。

### 2.8.3-CN4

基于 2.8.3-CN3（e01d1f0），只修了一个问题。

- **omcid 开机约 24.86 天后崩溃**：`omci_timeout.c` 把定时器到期时间存成 32 位开机毫秒数，并用有符号比较。开机接近 2^31 ms 时，超时跨过这个点的定时器会被立即触发并空转。带 IPTV 组播的线路会因此在 `omcitm` 线程段错误。之后每过 2^32 ms（约 49.7 天）会再遇到一次。补丁改的是 `mods/binary-mods.sh` 里 omcid 的 4 条指令。

  验证方法：用 `LD_PRELOAD` 把 omcid 看到的时钟拨到边界前 5 分钟，原版会空转，补丁版正常；2^32 回绕处也测过。

### 2.8.3-CN3 及更早

见 [xiao-k233 的 Release](https://github.com/xiao-k233/8311-was-110-firmware-builder/releases)。注意：那边 2.8.3-CN3 的安装包在 2025-12-31 被替换成了一个未发布的构建（`2.8.3-CN3-regidfix_basic_4324d7e`），它和最初的 2.8.3-CN3（`e01d1f0`）不同。本仓库以最初的 e01d1f0 为准。

## 本仓库新增的 fwenv

前两项可以在网页 "8311 配置" 里修改，`8311_trial_timeout` 只能用 `fw_setenv` 设置。用 `fw_setenv` 时建议执行两次，两份环境都写到。完整的 fwenv 列表见网页配置页和 [djGrrr 的 README](https://github.com/djGrrr/8311-was-110-firmware-builder)。

| fwenv | 默认 | 作用 |
| --- | --- | --- |
| `8311_syslog_server` | 空 | 远程 syslog，`主机` 或 `主机:端口`（UDP，默认 514） |
| `8311_omcid_crash_reboot` | `1` | omcid 崩溃后重启，设为 `0` 关闭 |
| `8311_trial_timeout` | `600` | 试启动时多少秒内必须连续 2 分钟可达，否则回退；最多 3600，至少 failsafe 延迟加 180；`0` 关闭 |

`8311_ntp_servers` 是原来就有的。`/etc` 每次开机都会重新生成，所以 NTP、syslog 这类设置只有写在 fwenv 里才能保留。

## 刷机

PRX126 棒子有 A、B 两组 kernel / bootcore / rootfs，升级只写当前不在用的那一组。坏了能否救回来，全靠另一组还完好，所以**不要直接把新固件设为 commit**。先试启动，确认没问题再提交：

```sh
# 1. 上传后校验，再写入非活动分区。会问两次：安装选 y，"Update commit_bank" 选 n
8311-firmware-upgrade.sh --validate /tmp/local-upgrade.tar
8311-firmware-upgrade.sh --install /tmp/local-upgrade.tar

# 2. 只从新分区启动一次（假设新分区是 B）
fw_setenv img_activate B; fw_setenv img_activate B
reboot

# 3. 确认版本（/etc/8311_version）、PON 进入 O5、上网 / IPTV / 语音都正常，然后提交
fw_setenv commit_bank B; fw_setenv commit_bank B
```

- 试启动期间重启一次，就会回到原来的 `commit_bank`。CN5 起还有自动回退：管理不可达，或者 omcid 崩溃，都会自动重启回去。
- 提交以后要回退，把 `commit_bank` 改回旧分区再重启即可。
- 写入前可以先把非活动分区备份下来：`cat /dev/ubi0_4 /dev/ubi0_5 /dev/ubi0_6`，卷号用 `ubinfo -a` 确认。
- 除非你清楚自己在做什么，不要碰 U-Boot、`ubootconfig`、`calibration`、`gphyfirmware` 这几个分区。

## 构建

构建需要两份原厂镜像，仓库里没有，也不要提交进来（`stock/` 已加入 `.gitignore`）。原厂镜像由 djGrrr 在 [8311 Discord](https://pon.wiki/discord/) 提供（`stock-2024-11-06.7z`）：

| 文件 | sha256 |
| --- | --- |
| `V1.0.19_unofficial_WAS_110_PRX126_local.img` | `584066a6fd3d718fd0caea2dfc4ab01ffae287ed3ebc78e6b04daabb19c7c64c` |
| `PTXG_CX_V0.03/kernel.bin` | `d66b24cf873cc1071a3aa2d155bf677f503f10d221513e469083f8a591f6b96c` |
| `PTXG_CX_V0.03/bootcore.bin` | `e99e25332bdcb3c9b0447abad1be9b1e54511b6bda99f2b51ae2499db5b905a4` |
| `PTXG_CX_V0.03/rootfs.img` | `5df5839296d7c2b1a69fa3bd6b2e42ee866a561dc962c33bc73a431530793115` |

把它们放到 `stock/` 下，然后：

```sh
git submodule update --init
docker/build.sh 2.8.3-CN5          # 产物在 out/
```

也可以在 Linux 上直接运行 `./build.sh -i stock/V1.0.19_unofficial_WAS_110_PRX126_local.img -I stock/PTXG_CX_V0.03 --basic --release -V <版本>`，需要的工具见 `docker/Dockerfile`。macOS 自带的 awk 跑不了 `extract.sh`，请用 Docker。

构建是可复现的：`docker/Dockerfile` 锁定了基础镜像的 digest 和 snapshot.debian.org 的日期（mksquashfs 的版本会影响 rootfs 的字节）。用上面的原厂镜像在这个环境里重编 2.8.3-CN3，得到的 kernel、bootcore、rootfs 与当时刷进设备的分区逐字节相同。

`binary-mods.sh` 只在原厂文件哈希匹配时打补丁。补丁打完会校验结果哈希，不一致就让构建失败。但如果原厂文件本身不对，它会**静默跳过**补丁。所以别用已经改过的 8311 发布包当原厂件。

## 分支

| 分支 | 说明 |
| --- | --- |
| `master` | 当前维护线，基于 2.8.3-CN3 |
| `archive/xiao-unreleased` | xiao-k233 在 CN3 之后提交、没有发布的改动，包括 reg_id 处理方式的修改、子模块组播 VLAN 的修改等。这里**没有采用**：其中 reg_id 的改动会让 regID 为空时发给 OLT 的注册 ID 从 36 个 `0x30` 变成 36 个 `0x00` |
| 其他 | 从 xiao-k233 仓库原样保留 |

## 已知问题

- CN3 的 `get_8311_reg_id_hex` / `_set_8311_reg_id_hex` 会把十六进制字符串再按文本编码一次。`8311_reg_id` 为空时，实际发出的是 36 个 ASCII `0`。已经在用的线路靠这个值注册成功，所以没有改。需要设置 PLOAM 密码的话，请先确认实际写入的值：`uci get gpon.ploam.regID`。
- `libifxos` 的 `IFXOS_ElapsedTimeMSecGet(ref)` 在 32 位毫秒计数回绕时算错了经过的时间。目前没观察到影响（2^32 回绕测试正常），所以没有打补丁。

## 捐助

如果这个固件对你有帮助，欢迎捐助：

- 加密货币（EVM 地址）：`0xdb61B2aD59bdF2A066B7fC9F00f86c3EBc4856B4`

## 作者与致谢

- Hikaru (i@rua.moe)：2.8.3-CN4 起的维护，包括 omcid 定时器修复、崩溃自动重启、试启动自动回退、远程 syslog
- [djGrrr](https://github.com/djGrrr) 和 8311 社区：原版构建器、补丁和原厂镜像
- [xiao-k233 / KillerZ](https://github.com/xiao-k233)：国内适配（VLAN、组播、中文界面等）

上游仓库没有附带许可证文件。使用和分发时请遵守原作者与固件厂商的相关条款。
