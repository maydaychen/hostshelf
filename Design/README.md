# App 图标源文件

本目录保存图标原图与生成说明；应用实际资源位于 `Sources/HostShelf/Resources/Assets.xcassets/AppIcon.appiconset/`。

`AppIcon-master.png` 是用户确认的 1254 × 1254 RGBA 原图，由内置 `imagegen` 工具生成。保留青蓝圆角底板、白色主机收纳架和终端提示符，底板外透明；不用于替换界面或菜单栏的 SF Symbols。

运行 `./script/generate_app_icon.sh`，使用系统 `sips` 确定性生成 macOS 的 16、32、128、256、512 点各 1x／2x 图像。Xcode 通过 `project.yml` 中的 `ASSETCATALOG_COMPILER_APPICON_NAME` 编译 AppIcon，并写入应用图标关联；构建不依赖生成工具的原始保存位置。

## 已采用的生成提示词

```text
Design ONE premium, minimal macOS application icon for HostShelf, a lightweight catalog of SSH hosts that opens an external terminal. Deliver a single standalone app icon, 1024 x 1024 square composition, with transparent pixels outside its opaque rounded-square superellipse backplate, approximately 88% of the canvas width. No mockup, no presentation sheet, no alternate concepts. The backplate is deep petrol teal, with very restrained native macOS material depth, a subtle teal highlight from the upper left and deeper navy toward the lower right, a softly beveled edge and a controlled soft shadow. Center one bold ice-white compact host rack / shelf enclosure, almost front-facing and orthographic. The enclosure has two clean thin horizontal server trays in its upper half, with only one simple dark slot per tray and no tiny details. Its lower half is one dark navy terminal panel containing a large, crisp mint-white >_ terminal prompt. The shelf and terminal form ONE integrated, memorable silhouette, generous negative space, strong contrast, thick simple geometry that remains legible at 16 to 32 pixels. Restrained low-relief dimensional icon craftsmanship, precise alignment, rounded corners, no toy-like gloss. The only glyphs allowed are >_. No app name, no letters or other text, no padlock, key, shield, cloud, globe, cables, network diagram, photographic scene, extra objects, or decorative particles. Preserve a clear outer transparent margin around the icon.
```

工具实际输出为 1254 × 1254；提示词中的尺寸是生成要求，入库及编译尺寸以实际文件和资源目录为准。
