# Kayoko

iOS 剪贴板管理器，原仓库 `https://github.com/hech666/Kayoko`。

## 构建

本工作区使用纯 clang 构建（无 Theos/make），通过 `apelin/build.sh` 脚本完成。

```sh
# Apelin 的 apelin_project_build 会运行该脚本
# 脚本输出一个 .deb 到 $APELIN_PACKAGE_DIR
```

### 构建产物

| 目标 | 类型 | filter | 源文件 |
|------|------|--------|--------|
| KayokoCore.dylib | dynamiclib | com.apple.springboard | Tweak/Core/** + Manager/** + Utils/** |
| KayokoHelper.dylib | dynamiclib | com.apple.UIKit | Tweak/Helper/** + Manager/** + Utils/** |
| kayokod | executable | — | Daemon/KayokoDaemon.m |
| KayokoPreferences | bundle | — | Preferences/** + Manager/** + Utils/** |

### 链接依赖

- **系统框架**: UIKit, CoreGraphics, QuartzCore, WebKit, Foundation, Preferences
- **jbroot 库**: libsubstrate, libroothide, libsandy（.tbd 在 `apelin/lib/tweak/`）
- **头文件**: `apelin/include/`（substrate.h, rootless.h, libSandy.h, Preferences/）

### 构建标志

```
-arch arm64e -fobjc-arc -DTHEOS_LEAN_AND_MEAN -Iapelin/include
```

### 注意事项

- `AlertUtil.m` 原使用 `CFUserNotification`（iOS 不可用），已改为空实现（该方法未被调用）
- `KayokoCore.m` 构造函数添加了 `os_log` 标记（subsystem `codes.aurora.kayoko`）
- `PSTableCell` 声明在 `apelin/include/Preferences/PSListController.h`，含 `initWithStyle:reuseIdentifier:specifier:`
- control 文件含 `Replaces: dev.traurige.kayoko`（旧包 ID，同路径文件冲突）
- 包 ID: `codes.aurora.kayoko`，版本 2.0
- 依赖: `firmware (>= 15.0), mobilesubstrate, preferenceloader, com.opa334.libsandy`
