#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default IP
sed -i 's/192.168.1.1/10.0.0.2/g' package/base-files/files/bin/config_generate
#sed -i '/^VERSION_NUMBER:=$(if/ s/24\.10-SNAPSHOT/24.10-lenyu/' include/version.mk #24.10
#sed -i 's/KERNEL_PATCHVER:=5.15/KERNEL_PATCHVER:=5.10/g' target/linux/x86/Makefile
#sed -i "s/.*PKG_VERSION:=.*/PKG_VERSION:=4.3.9_v1.2.14/" package/lean/qBittorrent-static/Makefile
#sed -i 's/download-ci-llvm = true/download-ci-llvm = false/g' feeds/packages/lang/rust/Makefile

# Ensure an OpenClash upgrade always refreshes the bundled clash_meta core.
# The package normally installs the core at /etc/openclash/core.  When that
# file already exists during sysupgrade, the old file can survive the package
# installation.  Keep a second copy in /usr/share/openclash/core and use a
# post-install hook to replace the runtime copy unconditionally.
OC_MAKEFILE="package/luci-app-openclash/luci-app-openclash/Makefile"
OC_CORE="package/luci-app-openclash/luci-app-openclash/root/etc/openclash/core/clash_meta"

if [ -f "$OC_MAKEFILE" ]; then
    python3 - "$OC_MAKEFILE" <<'PY_PATCH'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "refresh-core.sh" not in text:
    lines = text.splitlines()
    start = None
    end = None

    for i, line in enumerate(lines):
        if line.strip() == "define Package/luci-app-openclash/install":
            start = i
            break

    if start is None:
        raise SystemExit("OpenClash install definition not found")

    for i in range(start + 1, len(lines)):
        if lines[i].strip() == "endef":
            end = i
            break

    if end is None:
        raise SystemExit("OpenClash install definition terminator not found")

    install_lines = [
        "",
        "\t# Keep a package-private copy for the post-install core refresh hook.",
        "\t$(INSTALL_DIR) $(1)/usr/share/openclash/core",
        "\t$(INSTALL_BIN) ./root/etc/openclash/core/clash_meta $(1)/usr/share/openclash/core/clash_meta",
    ]
    lines[end:end] = install_lines
    text = "\n".join(lines) + "\n"

    text += """

define Package/luci-app-openclash/postinst
#!/bin/sh

# Do not touch the build root while the image is being assembled.
if [ -n \"$${IPKG_INSTROOT}\" ]; then
    exit 0
fi

SRC=\"/usr/share/openclash/core/clash_meta\"
DST=\"/etc/openclash/core/clash_meta\"

if [ -f \"$${SRC}\" ]; then
    mkdir -p /etc/openclash/core
    rm -f \"$${DST}\"
    cp -f \"$${SRC}\" \"$${DST}\"
    chmod 0755 \"$${DST}\"
fi

exit 0
endef
"""
    path.write_text(text, encoding="utf-8")
PY_PATCH
fi

# welcome test
