# SPDX-License-Identifier: GPL-3.0-only
#
# Ethernet port LED control for the CLX S20P: a UCI-driven shell tool that writes
# the RTL8221B and MT7531 LED registers through mdio-tools, plus its LuCI page.
# Not using luci.mk on purpose: the page has no translatable strings of its own
# (the image is zh_cn) and the tooling is board specific.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ethled
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-only
PKG_MAINTAINER:=likz0421

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-ethled
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Ethernet port LED control (S20P)
  DEPENDS:=@TARGET_mediatek_filogic +luci-base +mdio-tools
endef

define Package/luci-app-ethled/description
 Turn the front-panel LEDs of the S20P network ports on and off and choose which
 link speeds light them. lan6 and the 2.5G WAN port are RTL8221B PHYs; lan1-lan5
 are the internal PHYs of the MT7531AE switch. The register map comes from the
 kernel PHY drivers in the build tree, and the settings live in /etc/config/ethled.
endef

define Package/luci-app-ethled/conffiles
/etc/config/ethled
endef

define Package/luci-app-ethled/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/ethled $(1)/usr/sbin/ethled

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/ethled.config $(1)/etc/config/ethled

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/ethled.init $(1)/etc/init.d/ethled

	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/ethled.hotplug $(1)/etc/hotplug.d/iface/20-ethled

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/ethled
	$(INSTALL_DATA) ./root/htdocs/luci-static/resources/view/ethled/main.js \
		$(1)/www/luci-static/resources/view/ethled/main.js

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-ethled.json \
		$(1)/usr/share/luci/menu.d/luci-app-ethled.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-ethled.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-ethled.json
endef

$(eval $(call BuildPackage,luci-app-ethled))
