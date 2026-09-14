# Fedora 本机开发

`main` 跟随 `upstream/main`，桌面定制放在 `personal/fedora-niri`。
`origin` 指向个人 fork；`upstream` 指向 `StatIndet/quickshell`。
合并前的本机源码由 `local-before-upstream-20260914` 标记保留。

本分支使用上游显示器和 Gamma 实现，并在显示器页面保留主屏选择及窗口迁移。
独立 nyx-dock、Niri 配置、主题同步脚本与本机服务由另一个本地配置仓库管理。
账号、通知、剪贴板、机器配置及外部运行库不提交到公开仓库。

## 构建和验证

这里沿用已安装在 `~/.local/lib/clavis-runtime` 的 M3Shapes、MapLibre Qt、libcava
和 Quickshell 依赖；这不是面向全新系统的一键安装器。上游 `install.sh` 只用于 Arch。

```bash
export PATH="$HOME/.local/bin:$PATH"
export CMAKE_PREFIX_PATH="$HOME/.local/lib/clavis-runtime${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="$HOME/.local/lib/clavis-runtime/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export QML_IMPORT_PATH="$HOME/.local/lib/clavis-runtime/lib/qml:$HOME/.local/lib/clavis-runtime/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export LD_LIBRARY_PATH="$HOME/.local/lib/clavis-runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QMLFORMAT=/usr/lib64/qt6/bin/qmlformat
export QMLLINT=/usr/lib64/qt6/bin/qmllint
export CMAKE_BUILD_PARALLEL_LEVEL=6

cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local/lib/clavis-runtime" \
  -DCLAVIS_QML_INSTALL_DIR="$HOME/.local/lib/clavis-runtime/lib/qml" \
  -DCMAKE_INSTALL_RPATH="$HOME/.local/lib/clavis-runtime/lib"
cmake --build build
```

按 `AGENTS.md` 选择检查范围。Fedora 上的 `installer_contracts` 含 Arch 专用的
子进程预检；应在 Arch 测试环境中运行，不能把 Fedora 的发行版拒绝当作桌面功能失败。
QML lint 的 advisory 警告应保留数量和日志，不代表没有运行时问题。

## 更新桌面

先在独立 checkout 合并并验证，避免正在运行的源码入口热重载未完成的合并：

```bash
git fetch upstream
git switch personal/fedora-niri
git merge upstream/main
```

桌面源码入口 `~/.config/quickshell/clavis` 指向经过验证的源码目录。
更换该入口前备份原目录；不要用强制链接命令覆盖已有的真实目录。
外部天气图标包在 `assets/icons/weather/meteocons` 中被 Git 忽略，需要保留已有文件。

原生模块可单独安装，不覆盖 Quickshell 配置、用户服务或外部依赖：

```bash
systemctl --user stop clavis-shell.service
cmake --install build --component ClavisNative
systemctl --user start clavis-shell.service
```

安装失败时先恢复备份的原生模块再启动 Shell，避免 QML 和原生接口版本不匹配。
已有输入法、图标主题和 Fedora 的 `key` 启动脚本继续由本机配置管理。
显示器配置位于 Niri 的 `clavis/outputs.kdl`，由主配置在原有位置 include；
主屏偏好单独保存在 Clavis 配置目录中。

验证当前桌面后提交并推送定制分支；不要把机器配置目录一并上传：

```bash
git push -u origin personal/fedora-niri
```
