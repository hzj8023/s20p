#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT/openwrt"

echo "==> drop unused video feed (its packages.adb is often truncated)"
sed -i '/^src-git.* video /d' feeds.conf.default


echo "==> luci-app-lucky (pinned)"
rm -rf package/lucky
git clone --depth 1 https://github.com/gdy666/luci-app-lucky.git package/lucky
if git -C package/lucky fetch --depth 1 origin 295115bd07a6748f4137e1bdf98600bc99625d01; then
	git -C package/lucky checkout --detach 295115bd07a6748f4137e1bdf98600bc99625d01
else
	echo "WARNING: pinned Lucky commit is not fetchable; using branch HEAD"
fi

echo "==> Argon v3.1.1 (备用主题)"
rm -rf package/luci-theme-argon
git clone --depth 1 --branch v3.1.1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
grep -q 'PKG_VERSION:=3.1.1' package/luci-theme-argon/Makefile || { echo "ERROR: Argon is not 3.1.1"; exit 1; }

echo "==> Lucent v3.6.1 (默认主题)"
rm -rf package/luci-theme-lucent
git clone --depth 1 --branch v3.6.1 https://github.com/likz0421/luci-theme-lucent.git package/luci-theme-lucent
grep -q '^PKG_VERSION:=3.6.1$' package/luci-theme-lucent/Makefile || { echo "ERROR: Lucent is not 3.6.1"; exit 1; }
grep -q 'call BuildPackage' package/luci-theme-lucent/Makefile || { echo "ERROR: Lucent Makefile lacks the feed scanner marker"; exit 1; }

echo "==> luci-app-quickfile (same file manager as 24.10)"
rm -rf package/quickfile
git clone --depth 1 https://github.com/sbwml/luci-app-quickfile.git package/quickfile

echo "==> honk + luci apps (daeuniverse/openwrt-packages, pinned)"
rm -rf /tmp/daeuniverse
git clone --depth 1 https://github.com/daeuniverse/openwrt-packages.git /tmp/daeuniverse
if git -C /tmp/daeuniverse fetch --depth 1 origin f7107cf1b7e47fa24c90933207e8dd273f80f11a; then
	git -C /tmp/daeuniverse checkout --detach f7107cf1b7e47fa24c90933207e8dd273f80f11a
else
	echo "WARNING: pinned daeuniverse commit is not fetchable; using branch HEAD"
fi
for p in honk luci-app-honk luci-lib-daeuniverse; do
	rm -rf "package/$p"
	cp -a "/tmp/daeuniverse/$p" package/
	[ -d "package/$p" ] || { echo "ERROR: $p is not in daeuniverse/openwrt-packages"; exit 1; }
done
# upstream builds honk-core from source with a pinned Rust nightly, bpf-linker and
# cross-compiled BoringSSL/SQLite; the firmware build installs the official static
# musl release instead, so only the Makefile is replaced and files/ stays upstream.
rm -f package/honk/build.sh
cp "$ROOT/packages/honk/Makefile" package/honk/Makefile
for f in files/honk.init files/honk.config files/config.dae; do
	[ -f "package/honk/$f" ] || { echo "ERROR: upstream honk $f is missing"; exit 1; }
done

echo "==> luci-app-ethled (S20P 网口指示灯开关)"
rm -rf package/luci-app-ethled
cp -a "$ROOT/packages/luci-app-ethled" package/
for f in files/ethled files/ethled.config files/ethled.init files/ethled.hotplug \
	Makefile root/htdocs/luci-static/resources/view/ethled/main.js \
	root/usr/share/luci/menu.d/luci-app-ethled.json \
	root/usr/share/rpcd/acl.d/luci-app-ethled.json; do
	[ -f "package/luci-app-ethled/$f" ] || { echo "ERROR: luci-app-ethled $f is missing"; exit 1; }
done
grep -q 'call BuildPackage' package/luci-app-ethled/Makefile || { echo "ERROR: luci-app-ethled Makefile lacks BuildPackage call"; exit 1; }

echo "==> package versions"
git -C package/lucky rev-parse --short HEAD
git -C package/luci-theme-argon describe --tags --always
git -C package/luci-theme-lucent describe --tags --always
git -C /tmp/daeuniverse describe --tags --always
