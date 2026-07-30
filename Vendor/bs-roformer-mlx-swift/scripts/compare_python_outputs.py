#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf


STEMS = ("bass", "drums", "other", "vocals", "guitar", "piano")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("swift_directory", type=Path)
    parser.add_argument("python_directory", type=Path)
    parser.add_argument("--python-prefix", default="")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = {}
    for stem in STEMS:
        swift_audio, swift_rate = sf.read(
            args.swift_directory / f"{stem}.wav",
            dtype="float32",
            always_2d=True,
        )
        python_name = f"{args.python_prefix}({stem})_BS-Roformer-SW.wav"
        python_audio, python_rate = sf.read(
            args.python_directory / python_name,
            dtype="float32",
            always_2d=True,
        )
        if swift_rate != python_rate or swift_audio.shape != python_audio.shape:
            raise ValueError(
                f"{stem}: format mismatch "
                f"{swift_rate}/{swift_audio.shape} != {python_rate}/{python_audio.shape}"
            )
        difference = swift_audio - python_audio
        report[stem] = {
            "sample_rate": int(swift_rate),
            "frames": int(swift_audio.shape[0]),
            "channels": int(swift_audio.shape[1]),
            "max_absolute_difference": float(np.max(np.abs(difference))),
            "rmse": float(np.sqrt(np.mean(difference * difference))),
            "python_rms": float(np.sqrt(np.mean(python_audio * python_audio))),
            "correlation": float(
                np.corrcoef(swift_audio.ravel(), python_audio.ravel())[0, 1]
            ),
        }

    serialized = json.dumps(report, ensure_ascii=False, indent=2)
    print(serialized)
    if args.output:
        args.output.write_text(serialized + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
