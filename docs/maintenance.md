# 维护与排障

## 连接与检查

```sh
ssh -p 22 YOUR_ADMIN@NAS_ADDRESS
uname -a
cat /etc.defaults/VERSION
grep platform_name /etc/synoinfo.conf
lsusb -cui
lsmod | grep -E '^mii |usbnet|cdc_ether|rndis_host'
ip -brief addr
```

以下命令的 usb0 必须替换成实际 RNDIS 接口：

```sh
readlink /sys/class/net/usb0/device/driver
cat /sys/class/net/usb0/carrier
ip neigh show dev usb0
sudo dmesg | tail -n 50
```

ip 显示 UNKNOWN 不一定是故障；结合 UP、LOWER_UP、carrier=1 和实际通信判断。

## 文件与校验

| 文件 | SHA-256 |
| --- | --- |
| /lib/modules/rndis_host.ko | b6d5f78c65656cd9a1f3660f6174858833ea27a8476eb9c7786396b68aea6c02 |
| /lib/modules/mii.ko | c9721be03452297f861da957ac6860b6ca30246f76d5d85e083e1602046b6ec4 |
| /lib/modules/cdc_ether.ko | c2fd08495434b92dd616285b60be93b8fb232b052615d942afb1b68e08977a7b |

均针对 4.4.302+ SMP mod_unload；usbnet 保留系统原文件。

其他配置：

- /usr/local/etc/rc.d/rndis-drivers.sh：开机恢复规则并加载模块。
- /usr/local/etc/rndis/99-rndis-auto-up.rules：持久规则副本。
- /etc/udev/rules.d/99-rndis-auto-up.rules：当前生效规则。
- /usr/local/lib/rndis-backup/install-时间-进程号/：每次安装备份。
- /usr/local/lib/rndis-backup/cdc_ether.ko.original：首次保存的旧文件，不会覆盖。它是安装前文件，不保证是厂家原版。

*.was-absent 标记安装前不存在的模块；*.before 是修改前副本。

## 驱动异常

- modprobe 找不到新增模块：本工具使用明确路径 insmod，不重建系统模块索引。可运行 sudo /usr/local/etc/rc.d/rndis-drivers.sh start。
- usbnet 提示 Unknown symbol mii_*：检查 mii 是否先加载。
- bad CDC descriptors：初始实机环境中的原 cdc_ether 无法识别对端，兼容版本解决了问题；检查是否被升级覆盖。
- module verification failed / tainting kernel：第三方未签名模块可能出现提示。检查后续是否成功加载，不能把提示本身当作成功或失败。
- 不要强制加载内核不匹配的模块或强制卸载在用驱动。

## 热插拔规则检查

```sh
sudo udevadm control --reload-rules
sudo udevadm test /sys/class/net/usb0
sudo udevadm trigger --action=add --subsystem-match=net --sysname-match=usb0
sudo udevadm settle --timeout=10
ip -brief link show usb0
```

test 打印规则匹配和预定命令；真正执行依赖 trigger 或实际设备事件。开机脚本也会对当前 RNDIS 接口定向补发 add 事件。

没有网卡时先检查 USB 设备是否出现、驱动是否绑定。DOWN 时可临时执行：

```sh
sudo ip link set dev usb0 up
```

## 设备发现

```sh
sudo ping6 -I usb0 -c 3 -w 5 ff02::1
ip neigh show dev usb0
sudo timeout 15 tcpdump -ni usb0 -e -c 30 'arp or ip or ip6'
```

组播可能收到本机响应；排除自身地址与 MAC。没有回应不证明设备离线。IPv6 链路本地通信必须指定接口作用域。

本项目不自动运行 DHCP。DSM 的 dhclient 可能有厂商扩展，即使设置空租约应用脚本，也不能保证完全不改接口地址。先了解对端网络模式再配置 IPv4。

## 升级

升级前把备份和当前脚本保存到共享文件夹。升级后重新核对平台、DSM、内核和模块校验值。启动脚本的内核字符串检查不能保证所有定制内核兼容；系统升级可能覆盖模块与规则。不要为兼容新内核直接删除检查条件。

## 关闭自动启用

先停用或修改开机脚本中恢复规则的部分，否则重启时会再次安装规则。再将两处 99-rndis-auto-up.rules 移出规则目录，并执行：

```sh
sudo udevadm control --reload-rules
```

关闭规则不会将当前接口自动设为 DOWN。

## 完整回滚

确认管理连接不经 RNDIS 接口，并检查其他 USB 网络设备依赖。选择正确的每次安装备份，停止开机脚本恢复规则，移走两处热插拔规则并 reload-rules。

关闭目标接口后，按以下顺序卸载；任一步因模块被占用失败时先调查，不要强制继续：

```sh
sudo ip link set dev usb0 down
sudo /sbin/rmmod rndis_host
sudo /sbin/rmmod cdc_ether
sudo /sbin/rmmod usbnet
sudo /sbin/rmmod mii
```

卸载成功后：

1. 从所选备份的 *.ko.before 恢复相应 /lib/modules 文件。
2. *.was-absent 表示该文件是本次新增，可移到备份目录。
3. 恢复原启动脚本和规则备份；若原来不存在，则移走本次新增配置。
4. 保留系统原 usbnet.ko。
5. 不要将旧 DSM 的备份直接恢复到升级后的系统。

卸载会中断相关 USB 网络，回滚后原先不受支持的设备可能无法生成网卡。备份目录及日志不要当作可公开分享的数据，提交问题前清除地址、用户名、序列号和凭据。

