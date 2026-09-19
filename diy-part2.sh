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

# If this patch was already applied, skip.
if "refresh-core.sh" not in text:
    lines = text.splitlines()

    install_start = None
    install_end = None

    # Try the classic block name first.
    for i, line in enumerate(lines):
        s = line.strip()
        if s == "define Package/luci-app-openclash/install":
            install_start = i
            break

    # Some newer OpenClash dev Makefiles may use a more generic block layout.
    if install_start is None:
        for i, line in enumerate(lines):
            s = line.strip()
            if s.startswith("define Package/") and "luci-app-openclash" in s and "install" in s:
                install_start = i
                break

    if install_start is None:
        print("INFO: OpenClash install definition not found, skipping patch.")
        raise SystemExit(0)

    for i in range(install_start + 1, len(lines)):
        if lines[i].strip() == "endef":
            install_end = i
            break

    if install_end is None:
        print("INFO: OpenClash install terminator not found, skipping patch.")
        raise SystemExit(0)

    # Add package-private copy so the post-install hook can overwrite the runtime core.
    install_lines = [
        "",
        "\t# Keep a package-private copy for the post-install core refresh hook.",
        "\t$(INSTALL_DIR) $(1)/usr/share/openclash/core",
        "\t$(INSTALL_BIN) ./root/etc/openclash/core/clash_meta $(1)/usr/share/openclash/core/clash_meta",
    ]
    lines[install_end:install_end] = install_lines
    text = "\n".join(lines) + "\n"

    text += """

define Package/luci-app-openclash/postinst
#!/bin/sh

# Do not touch the build root while the image is being assembled.
if [ -n "$${IPKG_INSTROOT}" ]; then
    exit 0
fi

SRC="/usr/share/openclash/core/clash_meta"
DST="/etc/openclash/core/clash_meta"

if [ -f "$${SRC}" ]; then
    mkdir -p /etc/openclash/core
    rm -f "$${DST}"
    cp -f "$${SRC}" "$${DST}"
    chmod 0755 "$${DST}"
fi

exit 0
endef
"""
    path.write_text(text, encoding="utf-8")
PY_PATCH
else
    echo "WARN: OpenClash Makefile not found at $OC_MAKEFILE"
    find package -path '*openclash*' -maxdepth 6 -print 2>/dev/null || true
fi

# welcome test
