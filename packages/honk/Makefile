# SPDX-License-Identifier: GPL-3.0-only
#
# honk-core for S20P: the official OpenWrt package in daeuniverse/openwrt-packages
# compiles honk from source (pinned Rust nightly for the eBPF object, bpf-linker,
# CMake cross wrappers for BoringSSL and SQLite). That toolchain does not belong in
# a firmware build, so this Makefile installs the upstream prebuilt static musl
# binary instead, while files/ (init script, UCI config, config.dae) stays the
# upstream one copied by scripts/diy-part1.sh.
#
# The -full build embeds the doona dashboard (native-ui implies native-api) and
# enables clash-api, mimalloc and rprx, which is what upstream's own recipe builds.

# $(CURDIR) points at the buildroot root and $(MAKEFILE_LIST) grows with every
# included file, so the package directory has to be resolved before the first
# include; files/ (the upstream init script and configs) is referenced through it.
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
PKG_VERSION:=0.1.0_beta4
PKG_RELEASE:=1

HONK_TAG:=v0.1.0-beta.4
HONK_ARCH:=aarch64-unknown-linux-musl-full
PKG_SOURCE:=honk-core-$(HONK_TAG)-$(HONK_ARCH).tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/$(HONK_TAG)/
PKG_HASH:=121c94f3a30091c5550ae503ddf7bce118def08ddc301a7f8ffa740f956476d0
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
HONK_UNPACK_DIR:=honk-core-$(HONK_TAG)-$(HONK_ARCH)

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine (honk-core) with embedded UI
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  # The image kernel is built with DEBUG_INFO_BTF=y, so /sys/kernel/btf/vmlinux
  # exists and upstream's vmlinux-btf dependency is not needed here.
  # jsonfilter is used by the init script to inspect the running services.
  DEPENDS:=@aarch64 +libstdcpp +kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +jsonfilter +v2ray-geoip +v2ray-geosite
endef

define Package/honk/description
 honk is an eBPF transparent proxy engine whose core binary embeds its eBPF
 object and needs kernel BTF for CO-RE relocations. This build uses the
 upstream aarch64 static musl release with the Clash API, the native API and
 the embedded doona dashboard. The service is disabled by default; enable it
 in LuCI after adding nodes and routing rules.
endef

define Build/Prepare
	gzip -dc $(DL_DIR)/$(PKG_SOURCE) | $(HOST_TAR) -C $(PKG_BUILD_DIR) -xf -
	[ -s "$(PKG_BUILD_DIR)/$(HONK_UNPACK_DIR)/honk-core" ] || { \
		echo "ERROR: honk-core is missing from the downloaded archive"; exit 1; }
	$(Build/Patch)
endef

define Build/Compile
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

define Package/honk/postinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT}" ] || exit 0
/etc/init.d/honk enabled && /etc/init.d/honk restart
exit 0
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/$(HONK_UNPACK_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/$(HONK_UNPACK_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_DIR)/files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_DIR)/files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) $(PKG_DIR)/files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	printf '%s\n' '/etc/honk/data/' > $(1)/lib/upgrade/keep.d/honk
	# v2ray-geoip/geosite install the files under /usr/share/v2ray. honk's
	# find_dat looks in /usr/share/honk before /usr/share/dae.
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))
