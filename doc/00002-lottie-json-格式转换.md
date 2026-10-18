# Lottie 动画格式转换指南：JSON → dotLottie

本文说明如何将 Lottie 动画从 `.json` 格式转换为 `.lottie`（dotLottie）格式，以及转换过程中需要规避的数据损坏风险（源自本项目的实际踩坑记录）。

## 两种格式的区别

| | `.json` | `.lottie`（dotLottie） |
|---|---|---|
| 本质 | 单个动画的 JSON 数据 | ZIP 压缩包（标准 `.zip` 格式） |
| 内容 | 动画数据本身 | `manifest.json` + `animations/*.json`，可含多动画、状态机、图片资源 |
| 体积 | 较大 | 压缩后通常为 JSON 的 20%~30% |
| 适用场景 | 单动画、调试、直接编辑 | 打包分发、多动画复用、状态机 |

`.lottie` 内部结构示例：

```
level-fail.lottie (ZIP)
├── manifest.json                  # 包描述：动画列表、循环节奏等元信息
└── animations/
    └── animation_0.json           # 动画数据（就是原始 JSON 原样存放）
```

`manifest.json` 示例：

```json
{
  "version": "1.0",
  "author": "your-name",
  "generator": "@lottiefiles/dotlottie-cli",
  "animations": [
    { "id": "animation_0", "speed": 1, "loop": true }
  ]
}
```

**核心原则：`.lottie` 只是容器，动画数据必须原样保留。任何"重写" JSON 内部数据的转换器都是不可靠的（见下文）。**

## 推荐方式：官方 CLI 打包

`@lottiefiles/dotlottie-cli` 只做封装、不改动动画数据，是本项目验证过的可靠方式：

```bash
# 单文件转换（Node.js 环境，npx 即用无需安装）
npx @lottiefiles/dotlottie-cli json-to-dotlottie level-fail.json -o level-fail.lottie

# 批量转换
npx @lottiefiles/dotlottie-cli json-to-dotlottie *.json -o output_dir/
```

## 备选方式：手工打包（Python）

不想引入 Node 依赖时，直接用 Python 的 zipfile 即可——dotLottie 本质就是 ZIP：

```python
import json, zipfile

src = "level-fail.json"          # 源动画 JSON
dst = "level-fail.lottie"        # 输出 .lottie

manifest = {
    "version": "1.0",
    "author": "your-name",
    "generator": "manual",
    "animations": [
        {"id": "animation_0", "speed": 1, "loop": True}
    ],
}

with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("manifest.json", json.dumps(manifest))
    with open(src, "rb") as f:
        z.writestr("animations/animation_0.json", f.read())  # 原样写入，不解析不改写
```

多动画打包：`animations/` 下放多个 `*.json`，manifest 的 `animations` 数组逐个登记（`id` 与文件名对应）。

## 在 Godot 中使用

`LottieAnimation` 节点的 `animation_path` 属性直接指向 `.lottie` 文件即可，插件会自动解包并加载（支持 `res://` 与 `user://` 路径）。若包含多动画，通过 manifest 选择（见插件 API 文档 `API.md`）。

## ⚠️ 避免使用"重写型"在线转换器（实际踩坑记录）

### 事故回顾

`test_case/` 下 5 个 `.lottie` 曾由在线工具 **lottietools.online** 转换而来，全部存在数据损坏，导致渲染与源 `.json` 不一致（遮罩膨胀、图形放大）。2026-10-19 已全部修复并验证。

### 损坏模式

该类转换器不是简单打包，而是**重新计算并改写动画数据**：

1. **切线坐标语义改写**（致命）：路径 `i`/`o` 切线被从规范的"相对顶点偏移"改写为"绝对坐标"。渲染器（ThorVG）按规范做 `顶点 + 偏移` 叠加，实际渲染成 `2×顶点 + 切线`，几何整体放大。本例中遮罩区域膨胀近一倍（如 760×738 → 1330×1291）。
2. **空间关键帧切线销毁**：位置关键帧的 `ti`/`to` 被置为 `null`（部分文件 689/785 处），运动轨迹数据永久丢失，无法逆推。
3. **注入非标准字段**：`__complete`、`completed`、`_render` 等运行时内部字段被写入数据。
4. **冗余内联**：`refId` 引用的合成层被复制内联，文件体积翻倍（437KB → 851KB）。

### 为何部分文件"看起来正常"

损坏是**全局性的**，但只有当遮罩扩大后露出相邻内容时才可见（如 cast-atlas 图集的四个象限互相渗色）。"渲染正常"不等于"数据完好"。

### 如何识别损坏

转换后做一次校验（解包比对内嵌 JSON 与源 JSON）：

```bash
unzip level-fail.lottie -d /tmp/check
py -I -c "import json; a=json.load(open('level-fail.json',encoding='utf-8')); b=json.load(open('/tmp/check/animations/animation_0.json',encoding='utf-8')); print('IDENTICAL' if a==b else 'CORRUPTED')"
```

快速指纹：内嵌 JSON 中出现 `__complete` / `_render` / `completed` 字段，或体积明显大于源文件，即为重写型转换器所致。

### 已损坏文件的处理

使用仓库根目录的修复脚本（含指纹检测、类型守卫与源文件交叉验证）：

```bash
py -I fix_lottie_tangents.py damaged.lottie [more.lottie ...]
```

- 切线被改写为绝对坐标的：脚本以 `i -= v` / `o -= v` 逆向公式精确还原；
- `ti`/`to` 被置 `null` 的：数据已丢失，须用源 `.json` 重新打包（见上文推荐方式）。

## 结论

| 需求 | 方案 |
|---|---|
| 日常转换 | `npx @lottiefiles/dotlottie-cli json-to-dotlottie` |
| 无 Node 环境 | Python zipfile 手工打包（数据原样写入） |
| 已损坏的 .lottie | `fix_lottie_tangents.py` 修复或从源 JSON 重建 |
| 在线转换器 | 一律不用；若已用，按上文方法校验 |
