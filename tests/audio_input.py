"""Verify the compact FFmpeg and FFprobe with AAC, WavPack, and DSD/DST DSDIFF."""

import argparse
import hashlib
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import urllib.request
import uuid

DST_URL = "https://fate-suite.ffmpeg.org/dst/dst-64fs44-2ch.dff"
DST_SHA256 = "29d305bd19731ce079324ed14ac17254f254115d7787b5646a943e367b238ed0"


def run(command, root):
    return subprocess.run(
        command, cwd=root, check=True, capture_output=True, timeout=90
    ).stdout


def dff_chunk(fourcc, data):
    return struct.pack(">4sQ", fourcc, len(data)) + data + b"\0" * (len(data) % 2)


def build_dsd():
    properties = (
        b"SND "
        + dff_chunk(b"FS  ", struct.pack(">I", 2822400))
        + dff_chunk(b"CHNL", struct.pack(">H", 2) + b"SLFTSRGT")
        + dff_chunk(b"CMPR", b"DSD \x0enot compressed")
    )
    return dff_chunk(
        b"FRM8",
        b"DSD "
        + dff_chunk(b"FVER", bytes([1, 5, 0, 0]))
        + dff_chunk(b"PROP", properties)
        + dff_chunk(b"DSD ", b"\x69\x96" * 352800),
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--ffprobe")
    parser.add_argument("--dst-fixture", type=pathlib.Path)
    args = parser.parse_args()
    run_id = os.environ.get("CODEX_TEST_RUN_ID", uuid.uuid4().hex[:10])
    ffmpeg = args.ffmpeg or ("/ffmpeg" if args.image else "ffmpeg")
    ffprobe = args.ffprobe or ("/ffprobe" if args.image else "ffprobe")
    with tempfile.TemporaryDirectory(prefix="ffmpeg-audio-") as temp:
        root = pathlib.Path(temp)
        for extension, codec, muxer in [
            ("aac", "aac", "adts"),
            ("wv", "wavpack", "wv"),
        ]:
            run(
                [
                    "ffmpeg",
                    "-v",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "sine=frequency=440:sample_rate=44100:duration=1",
                    "-c:a",
                    codec,
                    "-f",
                    muxer,
                    f"source.{extension}",
                ],
                root,
            )
        (root / "raw.dff").write_bytes(build_dsd())
        if args.dst_fixture:
            dst = args.dst_fixture.read_bytes()
        else:
            with urllib.request.urlopen(DST_URL, timeout=40) as response:
                dst = response.read(100_000)
        if hashlib.sha256(dst).hexdigest() != DST_SHA256:
            raise ValueError("Unexpected FFmpeg FATE DST sample digest")
        (root / "dst.dff").write_bytes(dst)

        def candidate(binary, *options):
            if not args.image:
                return run([binary, *options], root)
            name = f"codex-tmp-{run_id}-{uuid.uuid4().hex[:10]}"
            try:
                return run(
                    [
                        "docker",
                        "run",
                        "--rm",
                        "--name",
                        name,
                        "--label",
                        "com.openai.codex.managed=true",
                        "--label",
                        f"com.openai.codex.run={run_id}",
                        "--volume",
                        f"{root}:/work",
                        "--workdir",
                        "/work",
                        "--entrypoint",
                        binary,
                        args.image,
                        *options,
                    ],
                    root,
                )
            finally:
                subprocess.run(
                    ["docker", "rm", "--force", name],
                    check=False,
                    capture_output=True,
                    timeout=15,
                )

        for source, expected_codec in [
            ("source.aac", "aac"),
            ("source.wv", "wavpack"),
            ("raw.dff", "dsd_msbf"),
            ("dst.dff", "dst"),
        ]:
            probe = json.loads(
                candidate(
                    ffprobe, "-v", "error", "-show_streams", "-of", "json", source
                )
            )
            assert probe["streams"][0]["codec_name"] == expected_codec, probe
            output = f"{source}.mp3"
            candidate(
                ffmpeg,
                "-v",
                "error",
                "-i",
                source,
                "-map",
                "0:a:0",
                "-c:a",
                "libmp3lame",
                "-ar",
                "44100",
                "-ac",
                "2",
                output,
            )
            # Independently decode the entire output and verify the reported frame count.
            data = json.loads(
                run(
                    [
                        "ffprobe",
                        "-v",
                        "error",
                        "-count_frames",
                        "-show_streams",
                        "-of",
                        "json",
                        output,
                    ],
                    root,
                )
            )["streams"][0]
            assert data["codec_name"] == "mp3" and data["channels"] == 2, data
            assert int(data["nb_read_frames"]) > 1, data
            print(f"{source} ({expected_codec}): probe and MP3 decode passed")


if __name__ == "__main__":
    main()
