# iOS 构建与验证

插件源码、ThorVG 配置、打包逻辑和插件回归用例均在本工程维护。消费项目只接收构建产物，不复制源码或应用额外补丁。

## 构建

需要 macOS、完整 Xcode，以及已经初始化的 `thirdparty/godot-cpp`、`thirdparty/thorvg` 子模块。

```sh
python3 -m venv venv
source venv/bin/activate
python -m pip install meson ninja scons

# 当前真机修复：arm64，Debug 和 Release。
VARIANTS=device ./build_thorvg_ios.sh
VARIANTS=device ./build_extension_ios.sh

# 完整 iOS 包（真机 + arm64/x86_64 模拟器）则省略 VARIANTS。
```

两个脚本默认最低 iOS 版本为 15.0，可用相同的 `MIN_IOS` 覆盖。扩展构建可用 `TARGETS=template_debug` 或 `TARGETS=template_release` 选择单一配置。

SCons 生成的 `.dylib` 和打包临时目录位于项目根目录的 `build/ios/`，不放入插件发布目录。

产物位于：

```text
demo/addons/godot_lottie/bin/ios/libgodot_lottie.ios.template_debug.xcframework/
demo/addons/godot_lottie/bin/ios/libgodot_lottie.ios.template_release.xcframework/
```

`VARIANTS=device` 更新真机切片并保留现有模拟器动态库；默认完整构建会替换全部切片。未重新编译的切片不代表已验证本次源码修复。iOS 使用动态库，在 `SConstruct` 内完整链接 godot-cpp 与 ThorVG；Godot 导出时负责包装成 framework 并签名。不要把不完整的静态库改名为动态库或在消费项目手工拼接库。

ThorVG 必须启用 `lottie,png` 加载器。扩展打包脚本会检查 `THORVG_PNG_LOADER_SUPPORT`，防止再次生成只有矢量内容、缺少内嵌 PNG 的产物。

## 包内资源自动播放

`src/lottie_animation.cpp` 中主线程加载 `res://` 失败时，会镜像 JSON 到 `user://`。必须将实际加载成功的路径传给原生后台渲染线程；线程不能通过普通文件 IO 读取 PCK 中的资源。动画缓存键仍使用原始路径。

回归场景：`demo/tests/packed_playback_test.tscn`。

其 PNG 在初始帧透明、第 15 帧后显示。测试只调用 `play()`，不调用 `seek()` 或 `render_static()`，然后验证像素和帧推进。这样不会因为主线程单帧渲染正常而漏掉后台线程的路径错误。

```sh
godot --path demo res://tests/packed_playback_test.tscn
```

还必须将该场景设为测试包入口，导出并在真机运行，检查 `PACKED_PLAYBACK_TEST PASS` 和 `user://packed-playback-test.png`。只在编辑器或未打包工程中运行，无法覆盖 PCK 路径。

## 拷贝到消费项目

构建完成后，整体替换消费项目中对应的两个 XCFramework 目录，包括生成的 `Info.plist`。若使用 `VARIANTS=device`，其中的模拟器动态库为原有版本，未重新编译。

拷贝后用 SHA-256 比较来源和目标文件，随后在消费项目重新导出、编译、安装，并运行实际页面集成测试。不要继续使用旧导出目录内已经嵌入的 framework 来验证新源码。
