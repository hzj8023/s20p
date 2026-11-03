#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT/openwrt"

echo "==> apply S20P fixes"
git apply "$ROOT/patches/0001-s20p-supported-devices.patch"
git apply "$ROOT/patches/0002-s20p-uboot-envtools.patch"
git apply "$ROOT/patches/0003-s20p-default-wifi.patch"
git apply "$ROOT/patches/0005-s20p-default-wifi-ucode.patch"
git apply "$ROOT/patches/0006-s20p-2.5g-led-config.patch"

echo "==> install RTL8221B C45 LED kernel patch"
cp "$ROOT/patches/735-net-phy-realtek-apply-led-config-on-rtl822xb.patch" \
	target/linux/mediatek/patches-6.12/

echo "==> pin firmware version"
sed -i 's#^VERSION_NUMBER:=$(if $(VERSION_NUMBER),$(VERSION_NUMBER),25.12-SNAPSHOT)$#VERSION_NUMBER:=25.12.6#' include/version.mk
sed -i 's#^VERSION_CODE:=$(if $(VERSION_CODE),$(VERSION_CODE),$(REVISION))$#VERSION_CODE:=s20p-custom#' include/version.mk
grep -q '^VERSION_NUMBER:=25.12.6$' include/version.mk || { echo "ERROR: version number pin failed"; exit 1; }
grep -q '^VERSION_CODE:=s20p-custom$' include/version.mk || { echo "ERROR: version code pin failed"; exit 1; }
grep -E '^(VERSION_NUMBER|VERSION_CODE):=' include/version.mk

echo "==> remove duplicate feed packages"
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/themes/luci-theme-fluent
rm -rf feeds/packages/net/open-app-filter

echo "==> fix nginx config for luci-app-quickfile"
cat > feeds/packages/net/nginx-util/files/nginx.config <<'EOF'

config main global
	option uci_enable 'true'

config server '_lan'
	option server_name '_lan'
	list listen '80 default_server'
	list listen '[::]:80 default_server'
	list include 'conf.d/*.locations'
	option access_log 'off; # logd openwrt'
EOF

echo "==> install Lucky 3.5.0 XiaoJV core Makefile"
cp "$ROOT/packages/lucky/Makefile" package/lucky/lucky/Makefile

echo "==> set LAN IP"
SET_IP="${LAN_IP:-10.1.1.1}"
FLASH_JS=$(find feeds/luci/modules/luci-mod-system -type f -name flash.js | head -n 1)
if [ -n "$FLASH_JS" ]; then
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$SET_IP/g" "$FLASH_JS"
fi
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$SET_IP/g" package/base-files/files/bin/config_generate

echo "==> set default theme and Chinese UI"
THEME="${DEFAULT_THEME:-lucent}"
LUCI_CFG=feeds/luci/modules/luci-base/root/etc/config/luci
if [ -f "$LUCI_CFG" ] && grep -q '^[[:space:]]*option mediaurlbase' "$LUCI_CFG"; then
	sed -i "s#^\(\s*option mediaurlbase\s*\).*#\1/luci-static/$THEME#" "$LUCI_CFG"
	grep -q "mediaurlbase /luci-static/$THEME" "$LUCI_CFG" \
		|| { echo "ERROR: failed to bake default theme into luci config"; exit 1; }
else
	echo "WARNING: mediaurlbase not found in $LUCI_CFG; first-boot uci-defaults will set it"
fi
if [ -f "$LUCI_CFG" ]; then
	sed -i "s#^\(\s*option lang\s*\).*#\1'zh_cn'#" "$LUCI_CFG"
	grep -q "option lang 'zh_cn'" "$LUCI_CFG" \
		|| { echo "ERROR: failed to bake zh_cn language"; exit 1; }
fi
cat > package/base-files/files/etc/uci-defaults/99-set-default-theme <<EOF
#!/bin/sh

THEME="$THEME"

uci set luci.themes.Lucent='/luci-static/lucent'
uci set luci.themes.Argon='/luci-static/argon'

if [ -d "/www/luci-static/\$THEME" ]; then
	uci set luci.main.mediaurlbase="/luci-static/\$THEME"
fi
uci set luci.main.lang='zh_cn'
uci commit luci

exit 0
EOF
chmod 0755 package/base-files/files/etc/uci-defaults/99-set-default-theme

echo "==> set default WiFi SSID/key"
cat > package/base-files/files/etc/uci-defaults/99-set-wifi-defaults <<'EOF'
#!/bin/sh
[ -f /etc/config/wireless ] || exit 0
for s in $(uci -q show wireless | sed -n 's/^\(wireless\.[^.]*\)=wifi-iface$/\1/p'); do
	[ "$(uci -q get "$s.mode")" = "ap" ] || continue
	uci set "$s.ssid=hanzi"
	uci set "$s.encryption=psk2"
	uci set "$s.key=hanziwawa"
done
uci commit wireless
wifi reload >/dev/null 2>&1 || true
exit 0
EOF
chmod 0755 package/base-files/files/etc/uci-defaults/99-set-wifi-defaults

echo "==> reset package feeds to official ImmortalWrt mirror"
cat > package/base-files/files/etc/uci-defaults/99-fix-distfeeds <<'EOF'
#!/bin/sh
FEEDS=/etc/apk/repositories.d/distfeeds.list
BASE=https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT
mkdir -p /etc/apk/repositories.d
cat > "$FEEDS" <<LIST
$BASE/targets/mediatek/filogic/packages/packages.adb
$BASE/packages/aarch64_cortex-a53/base/packages.adb
$BASE/packages/aarch64_cortex-a53/luci/packages.adb
$BASE/packages/aarch64_cortex-a53/packages/packages.adb
$BASE/packages/aarch64_cortex-a53/routing/packages.adb
$BASE/packages/aarch64_cortex-a53/telephony/packages.adb
LIST
exit 0
EOF
chmod 0755 package/base-files/files/etc/uci-defaults/99-fix-distfeeds

echo "==> add fantastic-packages key and feed"
mkdir -p package/base-files/files/etc/apk/keys
cp "$ROOT/packages/fantastic-feed/fantastic-packages-20241123170031.pem" \
	package/base-files/files/etc/apk/keys/fantastic-packages-20241123170031.pem
chmod 0644 package/base-files/files/etc/apk/keys/fantastic-packages-20241123170031.pem
cat > package/base-files/files/etc/uci-defaults/99-add-fantastic-feed <<'EOF'
#!/bin/sh
F=/etc/apk/repositories.d/customfeeds.list
mkdir -p /etc/apk/repositories.d
touch "$F"
for u in \
	https://fantastic-packages.github.io/releases/25.12/packages/aarch64_cortex-a53/packages/packages.adb \
	https://fantastic-packages.github.io/releases/25.12/packages/aarch64_cortex-a53/luci/packages.adb \
	https://fantastic-packages.github.io/releases/25.12/packages/aarch64_cortex-a53/special/packages.adb
do
	grep -qxF "$u" "$F" || echo "$u" >> "$F"
done
exit 0
EOF
chmod 0755 package/base-files/files/etc/uci-defaults/99-add-fantastic-feed

echo "==> ucode crash guards (unregistered functions + POSIX ERE)"
GUARD_DIRS="feeds/luci package/lucky package/luci-theme-argon package/luci-theme-lucent package/quickfile package/luci-app-ethled"
python3 "$ROOT/scripts/ucode_guard.py" $GUARD_DIRS
python3 "$ROOT/scripts/posix_re_check.py" $GUARD_DIRS

echo "==> done: LAN_IP=$SET_IP THEME=$THEME"
