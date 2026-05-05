# FolderCompare

一个用于 macOS 的文件夹对比工具，支持：

- 对比两个文件夹中的文件路径与大小
- 展示路径和大小都一致的文件
- 展示路径一致但大小不同的文件
- 展示大小一致但路径不同的文件
- 展示仅存在于左侧或右侧文件夹的文件
- 提供树状结构和扁平结构两种视图

## 构建

```bash
swift build
```

## 打包为 macOS 应用

```bash
./scripts/package_app.sh
```

生成结果位于 `dist/FolderCompare.app`。
