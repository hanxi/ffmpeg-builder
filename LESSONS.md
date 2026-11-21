# 开发经验

[English](LESSONS.en.md)

## BUILD-001：精简工具的输入能力必须用构建产物验证

- 范围：`--disable-everything` 静态 FFmpeg/FFprobe 与 Songloft HLS 输入；[songloft-org/songloft#541 的反馈](https://github.com/songloft-org/songloft/issues/541#issuecomment-6516328627)，本仓库基线 `58891be59f4141df33b88c400531d42aa23b9d3d`，主仓库基线 `dc762612f5deb0df966b4e273d3d9623d897c4f7`。
- 失败证据：旧配置只启用 HLS muxer，未启用 HLS demuxer 和 crypto 协议。既有 Docker 工具中这两项确实缺失；同一实际源使用系统工具可探测，接回旧工具后，原后端返回「无法探测上游媒体」。新增产物测试在旧镜像中直接 TS 通过、普通 HLS 探测失败，日志 `/tmp/songloft-541-builder-before-final.log`、`/tmp/songloft-541-service-real-before.log`。
- 规则与修复：输出 HLS 不代表能输入 HLS；显式启用 `hls` demuxer 和 `crypto` 协议。系统工具只生成夹具和独立检查输出；推送前使用构建出的 ffprobe/ffmpeg 执行 TS、主列表→子列表→分片、AES-128→密钥完整链路，并验证视频包 SHA-256 逐包不变。
- Done right：Linux amd64，FFmpeg 8.0.1 静态产物的三组测试通过，输出 AAC-LC 双声道 48 kHz；日志 `/tmp/songloft-541-builder-after.log`。系统 FFmpeg 5.1.7 夹具测试、Ruff 和 actionlint v1.7.12 通过。源码下载慢时，本地验证使用 APK 镜像和上游源码缓存，仅替换下载地址，不改编译选项；归档校验与哈希见 `/tmp/songloft-541-source-hashes.txt`，最终构建日志 `/tmp/songloft-541-ffmpeg-build-final.log`。
- 后端验证：不改业务源码，通过隔离 Go overlay 将测试服务换成新工具；HLS 定向测试全部通过，实际第一个源约 7 秒创建会话，HTTP 播放列表、分片、Range、删除和回收通过，输出 H.264 1920×1080 + AAC-LC 双声道 48 kHz。日志 `/tmp/songloft-541-go-new-tools.log`、`/tmp/songloft-541-actual-http.log`；最终工作树与命令见 `/tmp/songloft-541-verification.json`。第三个源在本地网络被上游重置连接，带时效签名的第二个源未验收。
- 发布边界：修复本仓库后仍需推送工具镜像，等待 Songloft 构建同步基础镜像并重建容器。Songloft 的二进制在线升级不会替换 ffmpeg/ffprobe，不能据主程序版本推断工具能力。
- 本地验证阶段 Not run：ARM 产物运行、远端 CI 和 iPhone Safari；amd64 及后端验证不替代这些验收。
- 现有 Songloft Docker 镜像已启用 `dca` 解码器，ffprobe 仍无法打开裸 DTS。Docker 和 Bundle 构建都加入 `dts`、`dtshd` demuxer。用本地生成的 5.1 声道 DTS 验证 Linux amd64 FFmpeg 8.0.1 候选工具，探测成功并输出双声道 MP3。FFmpeg FATE 的 DTS-HD MA 样本也通过探测和转码。[songloft-org/songloft#588](https://github.com/songloft-org/songloft/issues/588) · [FATE 样本](https://fate-suite.ffmpeg.org/dts/dcadec-suite/xll_51_24_48_768.dtshd)
- Seen 2× (2026-10-30, 2026-11-21)。镜像构建、主仓库指针同步及设备验收以对应提交的后续交付记录为准。

## BUILD-002：源码下载的连接重置需要显式、有限重试

- 范围：多架构镜像的源码下载；[dd9a8df 的 CI](https://github.com/hanxi/ffmpeg-builder/actions/runs/41065204390)。
- 失败证据：amd64 构建和三组 HLS 产物测试通过，但 arm/v7 下载 FFmpeg 源码时遭遇连接重置，`curl` 返回 35，整个多架构构建中止；日志 `/tmp/songloft-541-ffmpeg-ci-failed.log`。这是下载失败，不能当成媒体回归或把未发布镜像当成可用包。
- 规则与修复：全部源码下载显式设置 `--retry 5 --retry-all-errors`，使 TLS/连接重置也能重试；同时限制连接、单次下载和重试时间。保留 `--fail`、TLS 校验及成功后才解包的顺序，不用忽略错误来继续构建。
- Done right：本地 TLS 服务首次连接立即中断，旧命令返回 35、仅连接一次；Dockerfile 中提取的新参数重试后成功，连接两次且文件内容完整。日志 `/tmp/songloft-541-curl-retry-check.log`；实际多架构发布结果另按修复提交的 CI 核对。
- Seen 1× (2026-10-30)。状态：构建韧性修复；同一事故不增加 BUILD-001 的次数。

## BUILD-003：Bundle 资产必须先固定 Release 身份再下载

- 范围：多平台 FFmpeg 发布资产与 Bundle 构建解析；本仓库新增 `release-assets.yml`、`scripts/build-release-assets.py` 和父仓库解析器。
- 规则：先按通道读取具体 Release tag，再校验 manifest 的 tag、平台、ABI、大小和 SHA-256；解析结果写入构建记录并供整个矩阵复用。不能在各 job 中直接读取滚动 `latest` URL。
- 正确示例：`ffmpeg-resolution.json` 同时记录 `release_tag`、`source_commit`、`manifest_sha256` 和每项资产摘要；下载后再按摘要校验，缺项或替换立即失败。
- Seen 1× (2026-11-20)。[dev CI](https://github.com/hanxi/ffmpeg-builder/actions/runs/44751699585)已发布十个目标的资产，后端 Bundle CI 校验并复用了同一清单。设备安装与播放另行验收。

### BUILD-004：macOS Release 工具只链接系统动态库

- 证据：Lynx Intel macOS Bundle 构建（Songloft CI `44748954168`）拒绝 FFmpeg 引用的 `libX11.6.dylib`。FFmpeg 编译机自动探测到安装目录的额外库，安装包中没有这些库。
- 规则：关闭 macOS FFmpeg 自动探测，显式启用系统 TLS 和 zlib。发布前用 `otool -L` 检查工具的动态依赖，只接受系统路径。
- Seen 1× (2026-11-20)。
