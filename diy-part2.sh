#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.

# ====================== 你的基础修改 ======================

# 1. 修改默认 IP 为 10.10.0.1
sed -i 's/192.168.1.1/10.0.0.2/g' package/base-files/files/bin/config_generate

# Rust 1.96.0's CI LLVM artifact can return 404. Build LLVM from source instead
# of downloading that artifact; this matches the upstream package's workaround.
RUST_MAKEFILE="feeds/packages/lang/rust/Makefile"
if [ -f "$RUST_MAKEFILE" ]; then
  sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' "$RUST_MAKEFILE"
fi
