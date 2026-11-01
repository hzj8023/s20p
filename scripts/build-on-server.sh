#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_URL=${REPO_URL:-https://github.com/chasey-dev/immortalwrt-mt798x-rebase}
REPO_BRANCH=${REPO_BRANCH:-25.12}
REPO_COMMIT=${REPO_COMMIT:-9f397975c7b47ce6986a6e39529d2f72fd5c729d}
LAN_IP=${LAN_IP:-10.1.1.1}
DEFAULT_THEME=${DEFAULT_THEME:-lucent}
WIFI_COMBO=${WIFI_COMBO:-7673-20260601}
JOBS=${JOBS:-2}
OPENWRT_DIR="$ROOT/openwrt"

if [ "$(id -u)" -eq 0 ]; then
	echo "Do not build as root."
	exit 1
fi

if [ ! -d "$ROOT/scripts" ] || [ ! -f "$ROOT/configs/s20p.config" ]; then
	echo "Run this script from the build repo: bash scripts/build-on-server.sh"
	exit 1
fi

for cmd in git make gcc python3 rsync unzip zip pahole; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Missing build dependency: $cmd"
		echo "Install the OpenWrt build environment first:"
		echo "  sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'"
		exit 1
	fi
done

echo "==> disk"
df -h "$ROOT"
AVAIL_KB=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
if [ "$AVAIL_KB" -lt $((40 * 1024 * 1024)) ]; then
	echo "ERROR: at least 40GB free is recommended."
	exit 1
fi

echo "==> memory"
free -h

if [ ! -d "$OPENWRT_DIR/.git" ]; then
	echo "==> clone source"
	git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$OPENWRT_DIR"
	if git -C "$OPENWRT_DIR" fetch --depth 1 origin "$REPO_COMMIT"; then
		git -C "$OPENWRT_DIR" checkout --detach "$REPO_COMMIT"
	else
		echo "WARNING: pinned source commit is not fetchable; using branch HEAD"
	fi
else
	echo "==> using existing source: $OPENWRT_DIR"
	git -C "$OPENWRT_DIR" log -1 --oneline
fi

chmod +x "$ROOT/scripts/diy-part1.sh" "$ROOT/scripts/diy-part2.sh"

echo "==> third-party packages"
"$ROOT/scripts/diy-part1.sh"

echo "==> feeds update"
cd "$OPENWRT_DIR"
./scripts/feeds update -a

echo "==> S20P fixes and defaults"
LAN_IP="$LAN_IP" DEFAULT_THEME="$DEFAULT_THEME" "$ROOT/scripts/diy-part2.sh"

echo "==> feeds install"
./scripts/feeds install -a

echo "==> load config"
cp "$ROOT/configs/s20p.config" .config

if [ "$WIFI_COMBO" = "7672-20240823" ]; then
	sed -i 's/^CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673=y/# CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7673 is not set/' .config
	sed -i 's/^CONFIG_MTK_MT_WIFI_MT7986_20260601=y/# CONFIG_MTK_MT_WIFI_MT7986_20260601 is not set/' .config
	sed -i 's|^CONFIG_MTK_MT_WIFI_FIRMWARE_PATH_MT7986=.*|CONFIG_MTK_MT_WIFI_FIRMWARE_PATH_MT7986="mt7986-fw-20240823"|' .config
	{
		echo 'CONFIG_MTK_MT_WIFI_DRIVER_VERSION_7672=y'
		echo 'CONFIG_MTK_MT_WIFI_MT7986_20240823=y'
	} >> .config
fi

make defconfig

grep -q '^CONFIG_TARGET_MULTI_PROFILE=y$' .config || {
	echo "ERROR: multi-profile is not enabled"
	exit 1
}

grep -q '^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_clx_s20p=y$' .config || {
	echo "ERROR: clx_s20p device is not selected"
	exit 1
}

grep -q '^VERSION_NUMBER:=25.12.6$' include/version.mk || {
	echo "ERROR: firmware version pin is missing"
	exit 1
}

grep -q 'ssid="hanzi"' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh || {
	echo "ERROR: default WiFi SSID is missing"
	exit 1
}

grep -q 'key=hanziwawa' package/mtk/applications/mtwifi-cfg/files/mtwifi.sh || {
	echo "ERROR: default WiFi key is missing"
	exit 1
}

grep -q '^CONFIG_TARGET_ROOTFS_INITRAMFS=y$' .config || {
	echo "ERROR: initramfs is not enabled"
	exit 1
}

for sym in CONFIG_KERNEL_DEBUG_INFO_BTF CONFIG_KERNEL_BPF_EVENTS; do
	if ! grep -q "^${sym}=y$" .config; then
		echo "ERROR: ${sym} is not enabled"
		exit 1
	fi
done

for sym in CONFIG_BPF_SYSCALL CONFIG_BPF_JIT; do
	if ! grep -q "^${sym}=y$" target/linux/generic/config-6.12; then
		echo "ERROR: ${sym} missing from generic kernel config"
		exit 1
	fi
done

for pkg in kmod-mt_wifi luci-app-mtwifi-cfg luci-app-lucky lucky luci-theme-lucent luci-theme-argon luci-app-firewall luci-app-package-manager luci-app-upnp luci-app-quickfile quickfile luci-nginx luci-app-diskman kmod-sched-core kmod-sched-bpf kmod-xdp-sockets-diag kmod-veth mdio-tools honk luci-app-honk luci-lib-daeuniverse v2ray-geoip v2ray-geosite luci-app-ethled; do
	if ! grep -q "^CONFIG_PACKAGE_${pkg}=y$" .config; then
		echo "ERROR: package ${pkg} was dropped by make defconfig"
		exit 1
	fi
done

grep -E 'CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_clx_s20p|CONFIG_VERSION_NUMBER|CONFIG_MTK_MT_WIFI_(DRIVER_VERSION|MT7986_202|FIRMWARE_PATH)' .config

echo "==> download"
make download -j"$JOBS"

echo "==> build"
make -j"$JOBS" || make -j1 || make -j1 V=s

echo "==> collect"
cd bin/targets/mediatek/filogic
mkdir -p "$ROOT/out"
cp -v *clx_s20p* "$ROOT/out/"
cp -v config.buildinfo feeds.buildinfo profiles.json sha256sums "$ROOT/out/" 2>/dev/null || true
cd "$ROOT/out"
rm -f sha256sums-s20p.txt
sha256sum * > sha256sums-s20p.txt

UBOOT_ROOT="$ROOT/uboot-pack"
UBOOT_DIR="$UBOOT_ROOT/S20P-25.12.6-uboot"
rm -rf "$UBOOT_ROOT"
mkdir -p "$UBOOT_DIR/firmware" "$UBOOT_DIR/bootloader"
INITRAMFS=$(ls *clx_s20p*-initramfs-kernel.bin 2>/dev/null | head -n1 || true)
SYSUPGRADE=$(ls *clx_s20p*-squashfs-sysupgrade.bin 2>/dev/null | head -n1 || true)
[ -n "$INITRAMFS" ] || { echo "ERROR: initramfs image missing"; exit 1; }
[ -n "$SYSUPGRADE" ] || { echo "ERROR: sysupgrade image missing"; exit 1; }
cp -v "$INITRAMFS" "$UBOOT_DIR/firmware/"
cp -v "$SYSUPGRADE" "$UBOOT_DIR/firmware/"
cp -v *clx_s20p*.manifest "$UBOOT_DIR/firmware/" 2>/dev/null || true
cp -v "$ROOT/uboot-files/"*.bin "$UBOOT_DIR/bootloader/"
cp -v "$ROOT/uboot-files/README-uboot.txt" "$UBOOT_DIR/"
cp -v "$ROOT/uboot-files/lgs-说明.txt" "$UBOOT_DIR/"
(cd "$UBOOT_DIR/firmware" && rm -f sha256sums.txt && sha256sum * > sha256sums.txt)
(cd "$UBOOT_DIR/bootloader" && rm -f sha256sums.txt && sha256sum * > sha256sums.txt)
(cd "$UBOOT_ROOT" && zip -r "$ROOT/out/S20P-25.12.6-uboot.zip" S20P-25.12.6-uboot)
cd "$ROOT/out"
sha256sum S20P-25.12.6-uboot.zip >> sha256sums-s20p.txt

echo "==> done: $ROOT/out"
ls -lh
