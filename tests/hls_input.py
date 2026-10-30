"""Exercise built binaries with independently generated and inspected test media."""

import argparse
import functools
import http.server
import json
import pathlib
import subprocess
import tempfile
import threading
import uuid


def run(command, cwd):
    result = subprocess.run(
        command, check=False, cwd=cwd, capture_output=True, text=True, timeout=45
    )
    if result.returncode:
        raise RuntimeError(f"Command failed: {command}\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", help="Docker image to test (Linux host networking)")
    parser.add_argument("--ffmpeg", help="Candidate FFmpeg executable")
    parser.add_argument("--ffprobe", help="Candidate FFprobe executable")
    args = parser.parse_args()
    ffmpeg = args.ffmpeg or ("/ffmpeg" if args.image else "ffmpeg")
    ffprobe = args.ffprobe or ("/ffprobe" if args.image else "ffprobe")

    with tempfile.TemporaryDirectory(prefix="ffmpeg-hls-input-") as temp:
        root = pathlib.Path(temp)
        run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=96x64:rate=10",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:sample_rate=48000",
                "-t",
                "6",
                "-c:v",
                "libx264",
                "-threads",
                "1",
                "-preset",
                "ultrafast",
                "-g",
                "20",
                "-bf",
                "0",
                "-pix_fmt",
                "yuv420p",
                "-c:a",
                "mp2",
                "-b:a",
                "128k",
                "-f",
                "mpegts",
                "source.ts",
            ],
            root,
        )
        (root / "key.key").write_bytes(bytes(range(16)))
        (root / "keyinfo").write_text(f"../key.key\n{root / 'key.key'}\n")
        for kind in ("plain", "encrypted"):
            (root / kind).mkdir()
            key_args = ["-hls_key_info_file", "keyinfo"] if kind == "encrypted" else []
            run(
                [
                    "ffmpeg",
                    "-v",
                    "error",
                    "-i",
                    "source.ts",
                    "-c",
                    "copy",
                    "-f",
                    "hls",
                    "-hls_time",
                    "2",
                    "-hls_list_size",
                    "0",
                    *key_args,
                    f"{kind}/media.m3u8",
                ],
                root,
            )
            (root / kind / "master.m3u8").write_text(
                "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000\nmedia.m3u8\n"
            )

        requested = set()

        class Handler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                requested.add(self.path)
                super().do_GET()

            def log_message(self, *_):
                pass

        handler = functools.partial(Handler, directory=str(root))
        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                docker = (
                    [
                        "docker",
                        "run",
                        "--rm",
                        "--network",
                        "host",
                        "-v",
                        f"{root}:/work",
                        "-w",
                        "/work",
                    ]
                    if args.image
                    else []
                )

                def candidate(binary, options):
                    name = "ffmpeg-hls-test-" + uuid.uuid4().hex
                    command = (
                        [*docker, "--name", name, "--entrypoint", binary, args.image]
                        if args.image
                        else [binary]
                    )
                    try:
                        return run([*command, *options], root)
                    finally:
                        if args.image:
                            # A timed-out Docker client can leave its container running.
                            subprocess.run(
                                ["docker", "rm", "-f", name],
                                check=False,
                                capture_output=True,
                                timeout=15,
                            )

                def metadata(source):
                    # Independently inspect output; --enable-small builds report numeric profiles.
                    return json.loads(
                        run(
                            [
                                "ffprobe",
                                "-v",
                                "error",
                                "-show_streams",
                                "-of",
                                "json",
                                source,
                            ],
                            root,
                        )
                    )["streams"]

                def hashes(source):
                    packets = json.loads(
                        candidate(
                            ffprobe,
                            [
                                "-v",
                                "error",
                                "-select_streams",
                                "v:0",
                                "-show_packets",
                                "-show_entries",
                                "packet=data_hash",
                                "-show_data_hash",
                                "sha256",
                                "-of",
                                "json",
                                source,
                            ],
                        )
                    )["packets"]
                    result = [packet["data_hash"] for packet in packets]
                    assert result and all(
                        value.startswith("SHA256:") for value in result
                    )
                    return result

                original = hashes("source.ts")
                for kind, path in (
                    ("ts", "source.ts"),
                    ("plain", "plain/master.m3u8"),
                    ("encrypted", "encrypted/master.m3u8"),
                ):
                    source = f"http://127.0.0.1:{server.server_port}/{path}"
                    # Match Songloft's restricted gateway input protocols and containers.
                    input_args = [
                        "-http_proxy",
                        "",
                        "-protocol_whitelist",
                        "http,tcp,crypto",
                        "-format_whitelist",
                        "hls,mpegts,mov",
                    ]
                    probe = json.loads(
                        candidate(
                            ffprobe,
                            [
                                "-v",
                                "error",
                                *input_args,
                                "-analyzeduration",
                                "2000000",
                                "-probesize",
                                "2097152",
                                "-show_streams",
                                "-of",
                                "json",
                                source,
                            ],
                        )
                    )
                    assert {stream["codec_name"] for stream in probe["streams"]} == {
                        "h264",
                        "mp2",
                    }, probe
                    output = root / f"output-{kind}"
                    output.mkdir()
                    candidate(
                        ffmpeg,
                        [
                            "-nostdin",
                            "-hide_banner",
                            "-loglevel",
                            "error",
                            *input_args,
                            "-i",
                            source,
                            "-map",
                            "0:v:0",
                            "-map",
                            "0:a:0",
                            "-c:v",
                            "copy",
                            "-c:a",
                            "aac",
                            "-profile:a",
                            "aac_low",
                            "-ac",
                            "2",
                            "-ar",
                            "48000",
                            "-b:a",
                            "128k",
                            "-f",
                            "hls",
                            "-hls_segment_type",
                            "mpegts",
                            "-hls_time",
                            "4",
                            "-hls_list_size",
                            "6",
                            "-hls_delete_threshold",
                            "3",
                            "-hls_flags",
                            "delete_segments+temp_file",
                            "-hls_segment_filename",
                            f"output-{kind}/segment-%09d.ts",
                            f"output-{kind}/playlist.m3u8",
                        ],
                    )
                    playlist = output / "playlist.m3u8"
                    assert playlist.read_text().startswith("#EXTM3U")
                    copied = []
                    for segment in sorted(output.glob("*.ts")):
                        streams = metadata(str(segment.relative_to(root)))
                        video = next(
                            stream
                            for stream in streams
                            if stream["codec_type"] == "video"
                        )
                        audio = next(
                            stream
                            for stream in streams
                            if stream["codec_type"] == "audio"
                        )
                        assert video["codec_name"] == "h264", video
                        assert (
                            audio["codec_name"],
                            audio["profile"],
                            audio["channels"],
                            audio["sample_rate"],
                        ) == ("aac", "LC", 2, "48000"), audio
                        copied.extend(hashes(str(segment.relative_to(root))))
                    assert copied == original, (
                        f"{kind}: compressed video packets changed"
                    )
                    if kind != "ts":
                        assert f"/{kind}/master.m3u8" in requested
                        assert f"/{kind}/media.m3u8" in requested
                        assert any(
                            p.startswith(f"/{kind}/") and p.endswith(".ts")
                            for p in requested
                        )
                    if kind == "encrypted":
                        assert "/key.key" in requested, "AES-128 key was not fetched"
                    print(
                        f"PASS {kind}: probe, HLS output, AAC-LC, unchanged H.264 packet hashes",
                        flush=True,
                    )
            finally:
                server.shutdown()
                thread.join()


if __name__ == "__main__":
    main()
