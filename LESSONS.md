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
- Seen 1× (2026-10-30)。状态：本次修复；镜像构建、主仓库指针同步及设备验收以对应提交的后续交付记录为准。
