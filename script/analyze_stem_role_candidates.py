#!/usr/bin/env python3
"""実Guitar/Piano Stemへ劣化模擬を適用し、専用解析候補の識別力を測る。

依存はPython標準ライブラリ、NumPy、ffmpeg/ffprobeだけ。製品DSPは変更しない。
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from pathlib import Path

import numpy as np


FRAME_SIZE = 4096
HOP_SIZE = 1024
SILENCE_FLOOR_DB = -70.0
EPSILON = 1e-12


def load_audio(path: Path) -> tuple[np.ndarray, int]:
    probe = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels", "-of", "json", str(path),
        ],
        text=True,
    )
    stream = json.loads(probe)["streams"][0]
    sample_rate = int(stream["sample_rate"])
    channels = int(stream["channels"])
    raw = subprocess.check_output(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path),
            "-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(channels),
            "-ar", str(sample_rate), "pipe:1",
        ]
    )
    samples = np.frombuffer(raw, dtype="<f4")
    if samples.size == 0 or samples.size % channels:
        raise ValueError(f"音声をFloat32へ読み込めません: {path}")
    return samples.reshape(-1, channels).astype(np.float64), sample_rate


def write_audio(path: Path, audio: np.ndarray, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "f32le", "-ar", str(sample_rate), "-ac", str(audio.shape[1]),
            "-i", "pipe:0", "-c:a", "pcm_f32le", str(path),
        ],
        stdin=subprocess.PIPE,
    )
    process.communicate(audio.astype("<f4", copy=False).tobytes())
    if process.returncode:
        raise RuntimeError(f"劣化模擬WAVを書き出せません: {path}")


def frame_starts(frame_count: int) -> np.ndarray:
    if frame_count <= FRAME_SIZE:
        return np.array([0], dtype=np.int64)
    starts = list(range(0, frame_count - FRAME_SIZE + 1, HOP_SIZE))
    last = frame_count - FRAME_SIZE
    if starts[-1] != last:
        starts.append(last)
    return np.asarray(starts, dtype=np.int64)


def framed(audio: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    starts = frame_starts(audio.shape[0])
    frames = np.zeros((starts.size, FRAME_SIZE, audio.shape[1]), dtype=np.float64)
    for index, start in enumerate(starts):
        end = min(audio.shape[0], start + FRAME_SIZE)
        frames[index, : end - start] = audio[start:end]
    return frames, starts


def overlap_add(
    frames: np.ndarray,
    starts: np.ndarray,
    frame_count: int,
    *,
    frames_are_windowed: bool = False,
) -> np.ndarray:
    window = np.hanning(FRAME_SIZE)
    result = np.zeros((frame_count, frames.shape[2]), dtype=np.float64)
    weights = np.zeros(frame_count, dtype=np.float64)
    for frame, start in zip(frames, starts, strict=True):
        valid = min(FRAME_SIZE, frame_count - int(start))
        contribution = frame[:valid] if frames_are_windowed else frame[:valid] * window[:valid, None]
        result[start : start + valid] += contribution
        weights[start : start + valid] += window[:valid]
    covered = weights > EPSILON
    result[covered] /= weights[covered, None]
    return result


def db(value: np.ndarray | float) -> np.ndarray | float:
    return 20.0 * np.log10(np.maximum(value, 1e-12))


def frequency_range(sample_rate: int, lower: float, upper: float) -> slice:
    step = sample_rate / FRAME_SIZE
    lower_bin = max(1, int(math.floor(lower / step)))
    upper_bin = min(FRAME_SIZE // 2 + 1, int(math.ceil(upper / step)))
    return slice(lower_bin, max(lower_bin + 1, upper_bin))


def estimate_fundamental(power: np.ndarray, sample_rate: int) -> float:
    step = sample_rate / FRAME_SIZE
    lower = max(1, int(math.ceil(50.0 / step)))
    upper = min(power.size - 1, int(math.floor(1200.0 / step)))
    best_bin = 0
    best_score = 0.0
    for candidate in range(lower, upper + 1):
        score = 0.0
        harmonic = 1
        while candidate * harmonic < power.size and candidate * harmonic * step <= 12000.0:
            center = candidate * harmonic
            local = power[max(1, center - 1) : min(power.size, center + 2)].sum()
            score += local / math.sqrt(harmonic)
            harmonic += 1
        if score > best_score:
            best_score = score
            best_bin = candidate
    return best_bin * step if best_score > EPSILON else 0.0


def harmonic_metrics(power: np.ndarray, sample_rate: int) -> tuple[float, float]:
    frequency_step = sample_rate / FRAME_SIZE
    full_range = frequency_range(sample_rate, 50.0, 12000.0)
    total = power[full_range].sum()
    if total <= EPSILON:
        return 0.0, 0.0
    fundamental = estimate_fundamental(power, sample_rate)
    if fundamental <= 0:
        return 0.0, 0.0

    harmonic_energy = 0.0
    harmonic = 1
    while harmonic * fundamental <= 12000.0:
        center = int(round(harmonic * fundamental / frequency_step))
        harmonic_energy += power[max(1, center - 1) : min(power.size, center + 2)].sum()
        harmonic += 1

    region = power[full_range]
    if region.size < 3:
        return min(1.0, harmonic_energy / total), 0.0
    local_peaks = np.flatnonzero(
        (region[1:-1] > region[:-2])
        & (region[1:-1] >= region[2:])
        & (region[1:-1] >= region.max() * 0.01)
    ) + full_range.start + 1
    if local_peaks.size == 0:
        return min(1.0, harmonic_energy / total), 0.0
    peak_frequencies = local_peaks * frequency_step
    nearest = np.maximum(1.0, np.round(peak_frequencies / fundamental)) * fundamental
    deviations = np.abs(peak_frequencies - nearest) / nearest
    weights = power[local_peaks]
    inharmonicity = float(np.sum(deviations * weights) / max(np.sum(weights), EPSILON))
    return min(1.0, harmonic_energy / total), inharmonicity


def active_mask(rms_db: np.ndarray) -> tuple[np.ndarray, float]:
    finite = rms_db[np.isfinite(rms_db)]
    if finite.size == 0 or float(np.max(finite)) < -100.0:
        return np.zeros_like(rms_db, dtype=bool), SILENCE_FLOOR_DB
    threshold = max(SILENCE_FLOOR_DB, float(np.percentile(finite, 95)) - 36.0)
    return rms_db >= threshold, threshold


def select_onsets(values: np.ndarray, active: np.ndarray, sample_rate: int) -> list[int]:
    active_values = values[active]
    if active_values.size < 3 or float(np.max(active_values)) <= EPSILON:
        return []
    threshold = float(np.percentile(active_values, 80))
    minimum_distance = max(1, int(round(0.15 * sample_rate / HOP_SIZE)))
    candidates = np.flatnonzero(
        active
        & (values >= threshold)
        & (values >= np.r_[values[0], values[:-1]])
        & (values >= np.r_[values[1:], values[-1]])
    )
    selected: list[int] = []
    for candidate in candidates:
        if not selected or candidate - selected[-1] >= minimum_distance:
            selected.append(int(candidate))
        elif values[candidate] > values[selected[-1]]:
            selected[-1] = int(candidate)
    return selected


def median_or_zero(values: list[float] | np.ndarray) -> float:
    array = np.asarray(values, dtype=np.float64)
    finite = array[np.isfinite(array)]
    return float(np.median(finite)) if finite.size else 0.0


def analyze(audio: np.ndarray, sample_rate: int) -> dict[str, float | int]:
    frames, _ = framed(audio)
    rms = np.sqrt(np.mean(np.square(frames), axis=(1, 2)) + EPSILON)
    rms_db = db(rms)
    active, threshold = active_mask(rms_db)
    duration = audio.shape[0] / sample_rate
    if not np.any(active):
        return {
            "duration_seconds": duration,
            "activity_threshold_dbfs": threshold,
            "active_fraction": 0.0,
            "active_frame_count": 0,
            "onset_energy_p90": 0.0,
            "attack_crest_p90_db": 0.0,
            "harmonic_energy_ratio_median": 0.0,
            "inharmonicity_median": 0.0,
            "spectral_centroid_median_hz": 0.0,
            "rolloff85_median_hz": 0.0,
            "high_band_ratio_median": 0.0,
            "high_band_ratio_p90": 0.0,
            "low_band_ratio_median": 0.0,
            "mid_band_ratio_median": 0.0,
            "tail_rms_ratio_median_db": -240.0,
            "tail_low_ratio_median_db": -240.0,
            "tail_mid_ratio_median_db": -240.0,
            "tail_high_ratio_median_db": -240.0,
            "double_decay_slope_delta_median_db_per_second": 0.0,
            "stereo_side_ratio": 0.0,
            "stereo_correlation": 1.0,
            "detected_onsets": 0,
        }

    window = np.hanning(FRAME_SIZE)
    channel_spectra = np.fft.rfft(frames * window[None, :, None], axis=1)
    channel_magnitude = np.abs(channel_spectra)
    power = np.mean(np.square(channel_magnitude), axis=2)
    magnitude = np.sqrt(power)
    phase = np.angle(channel_spectra)

    complex_onset = np.zeros(frames.shape[0], dtype=np.float64)
    for index in range(2, frames.shape[0]):
        predicted = channel_magnitude[index - 1] * np.exp(
            1j * (2.0 * phase[index - 1] - phase[index - 2])
        )
        complex_onset[index] = np.sum(np.abs(channel_spectra[index] - predicted)) / max(
            np.sum(channel_magnitude[index]) + np.sum(channel_magnitude[index - 1]), EPSILON
        )
    onset_energy = complex_onset * rms
    peak = np.max(np.abs(frames), axis=(1, 2))
    crest_db = db(peak / np.maximum(rms, EPSILON))

    harmonic_ratios: list[float] = []
    inharmonicities: list[float] = []
    centroids: list[float] = []
    rolloffs: list[float] = []
    high_ratios: list[float] = []
    low_ratios: list[float] = []
    mid_ratios: list[float] = []
    frequencies = np.fft.rfftfreq(FRAME_SIZE, 1.0 / sample_rate)
    high_range = frequency_range(sample_rate, 6000.0, 18000.0)
    audible_range = frequency_range(sample_rate, 20.0, min(20000.0, sample_rate / 2))
    band_powers = {
        "low": power[:, frequency_range(sample_rate, 80.0, 500.0)].sum(axis=1),
        "mid": power[:, frequency_range(sample_rate, 500.0, 4000.0)].sum(axis=1),
        "high": power[:, frequency_range(sample_rate, 4000.0, 12000.0)].sum(axis=1),
    }
    for index in np.flatnonzero(active):
        frame_power = power[index]
        harmonic_ratio, inharmonicity = harmonic_metrics(frame_power, sample_rate)
        harmonic_ratios.append(harmonic_ratio)
        inharmonicities.append(inharmonicity)
        audible_power = frame_power[audible_range]
        total = max(float(audible_power.sum()), EPSILON)
        centroids.append(float(np.sum(frequencies[audible_range] * audible_power) / total))
        cumulative = np.cumsum(audible_power)
        rolloff_index = min(
            int(np.searchsorted(cumulative, cumulative[-1] * 0.85)),
            audible_power.size - 1,
        )
        rolloffs.append(float(frequencies[audible_range][rolloff_index]))
        high_ratios.append(float(frame_power[high_range].sum() / total))
        low_ratios.append(float(band_powers["low"][index] / total))
        mid_ratios.append(float(band_powers["mid"][index] / total))

    onsets = select_onsets(onset_energy, active, sample_rate)
    tail_start = max(1, int(round(0.25 * sample_rate / HOP_SIZE)))
    tail_end = max(tail_start + 1, int(round(0.80 * sample_rate / HOP_SIZE)))
    late_start = max(tail_start + 1, int(round(0.40 * sample_rate / HOP_SIZE)))
    late_end = max(late_start + 2, int(round(1.00 * sample_rate / HOP_SIZE)))
    tail_rms: list[float] = []
    tail_bands: dict[str, list[float]] = {"low": [], "mid": [], "high": []}
    slope_delta: list[float] = []
    frame_seconds = HOP_SIZE / sample_rate
    for onset in onsets:
        if onset + tail_end >= rms.size:
            continue
        reference_rms = max(float(np.max(rms[onset : onset + 2])), EPSILON)
        tail_rms.append(float(db(np.median(rms[onset + tail_start : onset + tail_end]) / reference_rms)))
        for name, values in band_powers.items():
            reference = max(float(np.max(values[onset : onset + 2])), EPSILON)
            ratio = math.sqrt(max(float(np.median(values[onset + tail_start : onset + tail_end])), EPSILON) / reference)
            tail_bands[name].append(float(db(ratio)))
        if onset + late_end < rms.size:
            early_y = np.asarray(db(rms[onset : onset + late_start]), dtype=np.float64)
            late_y = np.asarray(db(rms[onset + late_start : onset + late_end]), dtype=np.float64)
            early_x = np.arange(early_y.size) * frame_seconds
            late_x = np.arange(late_y.size) * frame_seconds
            if early_y.size >= 3 and late_y.size >= 3:
                early_slope = float(np.polyfit(early_x, early_y, 1)[0])
                late_slope = float(np.polyfit(late_x, late_y, 1)[0])
                slope_delta.append(late_slope - early_slope)

    left = audio[:, 0]
    right = audio[:, 1]
    mid = (left + right) * 0.5
    side = (left - right) * 0.5
    mid_energy = float(np.sum(np.square(mid)))
    side_energy = float(np.sum(np.square(side)))
    if np.std(left) > EPSILON and np.std(right) > EPSILON:
        correlation = float(np.corrcoef(left, right)[0, 1])
    else:
        correlation = 1.0

    return {
        "duration_seconds": duration,
        "activity_threshold_dbfs": threshold,
        "active_fraction": float(np.mean(active)),
        "active_frame_count": int(np.count_nonzero(active)),
        "onset_energy_p90": float(np.percentile(onset_energy[active], 90)),
        "attack_crest_p90_db": float(np.percentile(crest_db[active], 90)),
        "harmonic_energy_ratio_median": median_or_zero(harmonic_ratios),
        "inharmonicity_median": median_or_zero(inharmonicities),
        "spectral_centroid_median_hz": median_or_zero(centroids),
        "rolloff85_median_hz": median_or_zero(rolloffs),
        "high_band_ratio_median": median_or_zero(high_ratios),
        "high_band_ratio_p90": float(np.percentile(high_ratios, 90)) if high_ratios else 0.0,
        "low_band_ratio_median": median_or_zero(low_ratios),
        "mid_band_ratio_median": median_or_zero(mid_ratios),
        "tail_rms_ratio_median_db": median_or_zero(tail_rms),
        "tail_low_ratio_median_db": median_or_zero(tail_bands["low"]),
        "tail_mid_ratio_median_db": median_or_zero(tail_bands["mid"]),
        "tail_high_ratio_median_db": median_or_zero(tail_bands["high"]),
        "double_decay_slope_delta_median_db_per_second": median_or_zero(slope_delta),
        "stereo_side_ratio": side_energy / max(mid_energy + side_energy, EPSILON),
        "stereo_correlation": correlation,
        "detected_onsets": len(onsets),
    }


def gain_overlap_add(audio: np.ndarray, gains: np.ndarray) -> np.ndarray:
    frames, starts = framed(audio)
    frames *= gains[:, None, None]
    return overlap_add(frames, starts, audio.shape[0])


def attack_reduction(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    return spectral_process(audio, sample_rate, "attack_reduction")


def tail_gate(audio: np.ndarray, sample_rate: int) -> np.ndarray:
    frames, _ = framed(audio)
    rms = np.sqrt(np.mean(np.square(frames), axis=(1, 2)) + EPSILON)
    active, _ = active_mask(np.asarray(db(rms)))
    if not np.any(active):
        return np.zeros_like(audio)
    window = np.hanning(FRAME_SIZE)
    spectra = np.fft.rfft(frames * window[None, :, None], axis=1)
    magnitude = np.abs(spectra)
    positive_flux = np.zeros(frames.shape[0], dtype=np.float64)
    positive_flux[1:] = np.maximum(magnitude[1:] - magnitude[:-1], 0).sum(axis=(1, 2))
    onsets = select_onsets(positive_flux * rms, active, sample_rate)
    gains = np.ones(rms.size, dtype=np.float64)
    tail_start = max(1, int(round(0.25 * sample_rate / HOP_SIZE)))
    tail_end = max(tail_start + 1, int(round(0.80 * sample_rate / HOP_SIZE)))
    for onset in onsets:
        lower = min(gains.size, onset + tail_start)
        upper = min(gains.size, onset + tail_end)
        gains[lower:upper] = np.minimum(gains[lower:upper], 0.12)
    # 後続の新しいattackは、直前のtail gateより優先して保持する。
    for onset in onsets:
        gains[onset : min(gains.size, onset + tail_start)] = 1.0
    return gain_overlap_add(audio, gains)


def spectral_process(audio: np.ndarray, sample_rate: int, mode: str) -> np.ndarray:
    frames, starts = framed(audio)
    window = np.hanning(FRAME_SIZE)
    spectra = np.fft.rfft(frames * window[None, :, None], axis=1)
    frequencies = np.fft.rfftfreq(FRAME_SIZE, 1.0 / sample_rate)
    if mode == "attack_reduction":
        magnitudes = np.abs(spectra)
        phases = np.angle(spectra)
        smoothed = magnitudes.copy()
        for frame_index in range(1, smoothed.shape[0]):
            previous = smoothed[frame_index - 1]
            rising = magnitudes[frame_index] > previous
            smoothed[frame_index][rising] = (
                previous[rising]
                + 0.18 * (magnitudes[frame_index][rising] - previous[rising])
            )
        spectra = smoothed * np.exp(1j * phases)
    elif mode == "high_reduction":
        gain = np.ones(frequencies.size, dtype=np.float64)
        transition = (frequencies > 4000.0) & (frequencies < 8000.0)
        gain[transition] = 1.0 - 0.88 * (frequencies[transition] - 4000.0) / 4000.0
        gain[frequencies >= 8000.0] = 0.12
        spectra *= gain[None, :, None]
    elif mode == "band_balance":
        gain = np.ones(frequencies.size, dtype=np.float64)
        transition = (frequencies > 350.0) & (frequencies < 700.0)
        gain[transition] = 1.0 - 0.72 * (frequencies[transition] - 350.0) / 350.0
        gain[(frequencies >= 700.0) & (frequencies <= 5000.0)] = 0.28
        transition = (frequencies > 5000.0) & (frequencies < 7000.0)
        gain[transition] = 0.28 + 0.72 * (frequencies[transition] - 5000.0) / 2000.0
        spectra *= gain[None, :, None]
    elif mode == "harmonic_reduction":
        for frame_index in range(spectra.shape[0]):
            power = np.mean(np.square(np.abs(spectra[frame_index])), axis=1)
            fundamental = estimate_fundamental(power, sample_rate)
            if fundamental <= 0:
                continue
            harmonic = 1
            while harmonic * fundamental <= 12000.0:
                center = int(round(harmonic * fundamental * FRAME_SIZE / sample_rate))
                lower = max(1, center - 1)
                upper = min(spectra.shape[1], center + 2)
                spectra[frame_index, lower:upper, :] *= 0.25
                harmonic += 1
    else:
        raise ValueError(mode)
    processed = np.fft.irfft(spectra, n=FRAME_SIZE, axis=1)
    return overlap_add(processed, starts, audio.shape[0], frames_are_windowed=True)


def degradations(audio: np.ndarray, sample_rate: int) -> dict[str, np.ndarray]:
    mono = np.mean(audio, axis=1, keepdims=True)
    return {
        "identity": audio.copy(),
        "silence": np.zeros_like(audio),
        "near_silence": audio * 1e-4,
        "attack_reduction": attack_reduction(audio, sample_rate),
        "harmonic_reduction": spectral_process(audio, sample_rate, "harmonic_reduction"),
        "tail_gate": tail_gate(audio, sample_rate),
        "high_reduction": spectral_process(audio, sample_rate, "high_reduction"),
        "band_balance": spectral_process(audio, sample_rate, "band_balance"),
        "mono": np.repeat(mono, audio.shape[1], axis=1),
    }


def relative_change(clean: float, degraded: float) -> float | None:
    if not math.isfinite(clean) or not math.isfinite(degraded) or abs(clean) <= EPSILON:
        return None
    return (degraded - clean) / abs(clean)


def temporal_series(audio: np.ndarray, sample_rate: int) -> dict[str, np.ndarray | list[int]]:
    frames, _ = framed(audio)
    rms = np.sqrt(np.mean(np.square(frames), axis=(1, 2)) + EPSILON)
    active, _ = active_mask(np.asarray(db(rms)))
    window = np.hanning(FRAME_SIZE)
    spectra = np.fft.rfft(frames * window[None, :, None], axis=1)
    magnitude = np.abs(spectra)
    phase = np.angle(spectra)
    power = np.mean(np.square(magnitude), axis=2)
    onset = np.zeros(frames.shape[0], dtype=np.float64)
    for index in range(2, frames.shape[0]):
        predicted = magnitude[index - 1] * np.exp(
            1j * (2.0 * phase[index - 1] - phase[index - 2])
        )
        onset[index] = np.sum(np.abs(spectra[index] - predicted)) / max(
            np.sum(magnitude[index]) + np.sum(magnitude[index - 1]), EPSILON
        )
    onset_energy = onset * rms
    bands = {
        "low": power[:, frequency_range(sample_rate, 80.0, 500.0)].sum(axis=1),
        "mid": power[:, frequency_range(sample_rate, 500.0, 4000.0)].sum(axis=1),
        "high": power[:, frequency_range(sample_rate, 4000.0, 12000.0)].sum(axis=1),
    }
    return {
        "rms": rms,
        "active": active,
        "onset_energy": onset_energy,
        "onsets": select_onsets(onset_energy, active, sample_rate),
        **bands,
    }


def matched_temporal_comparison(
    clean_audio: np.ndarray,
    degraded_audio: np.ndarray,
    sample_rate: int,
) -> dict[str, float | int]:
    clean = temporal_series(clean_audio, sample_rate)
    degraded = temporal_series(degraded_audio, sample_rate)
    onsets = list(clean["onsets"])
    tail_start = max(1, int(round(0.25 * sample_rate / HOP_SIZE)))
    tail_end = max(tail_start + 1, int(round(0.80 * sample_rate / HOP_SIZE)))

    clean_onset: list[float] = []
    degraded_onset: list[float] = []
    clean_tail: dict[str, list[float]] = {"rms": [], "low": [], "mid": [], "high": []}
    degraded_tail: dict[str, list[float]] = {"rms": [], "low": [], "mid": [], "high": []}
    for onset in onsets:
        if onset + tail_end >= len(clean["rms"]):
            continue
        clean_onset.append(float(clean["onset_energy"][onset]))
        degraded_onset.append(float(degraded["onset_energy"][onset]))
        for name in clean_tail:
            clean_values = np.asarray(clean[name], dtype=np.float64)
            degraded_values = np.asarray(degraded[name], dtype=np.float64)
            if name == "rms":
                clean_reference = max(float(np.max(clean_values[onset : onset + 2])), EPSILON)
                degraded_reference = max(float(np.max(degraded_values[onset : onset + 2])), EPSILON)
                clean_ratio = float(np.median(clean_values[onset + tail_start : onset + tail_end])) / clean_reference
                degraded_ratio = float(np.median(degraded_values[onset + tail_start : onset + tail_end])) / degraded_reference
            else:
                clean_reference = max(float(np.max(clean_values[onset : onset + 2])), EPSILON)
                degraded_reference = max(float(np.max(degraded_values[onset : onset + 2])), EPSILON)
                clean_ratio = math.sqrt(max(float(np.median(clean_values[onset + tail_start : onset + tail_end])), EPSILON) / clean_reference)
                degraded_ratio = math.sqrt(max(float(np.median(degraded_values[onset + tail_start : onset + tail_end])), EPSILON) / degraded_reference)
            clean_tail[name].append(float(db(clean_ratio)))
            degraded_tail[name].append(float(db(degraded_ratio)))

    clean_onset_median = median_or_zero(clean_onset)
    degraded_onset_median = median_or_zero(degraded_onset)
    result: dict[str, float | int] = {
        "matched_onset_count": len(clean_onset),
        "onset_energy_clean_median": clean_onset_median,
        "onset_energy_degraded_median": degraded_onset_median,
        "onset_energy_relative_decrease": (
            (clean_onset_median - degraded_onset_median) / abs(clean_onset_median)
            if abs(clean_onset_median) > EPSILON else 0.0
        ),
    }
    for name in clean_tail:
        clean_value = median_or_zero(clean_tail[name])
        degraded_value = median_or_zero(degraded_tail[name])
        result[f"tail_{name}_clean_median_db"] = clean_value
        result[f"tail_{name}_degraded_median_db"] = degraded_value
        result[f"tail_{name}_decrease_db"] = clean_value - degraded_value
    return result


def evaluate_discrimination(
    clean: dict[str, float | int],
    cases: dict[str, dict[str, float | int]],
    paired: dict[str, dict[str, float | int]],
) -> dict[str, dict[str, object]]:
    checks = {
        "silence_activity": ("silence", "active_fraction", "maximum", 0.001),
        "near_silence_activity": ("near_silence", "active_fraction", "maximum", 0.001),
        "attack": ("attack_reduction", "onset_energy_relative_decrease", "paired_minimum", 0.15),
        "harmonic_body": ("harmonic_reduction", "harmonic_energy_ratio_median", "relative_decrease", 0.15),
        "inharmonicity": ("harmonic_reduction", "inharmonicity_median", "relative_increase", 0.15),
        "tail_low": ("tail_gate", "tail_low_decrease_db", "paired_minimum", 0.5),
        "tail_mid": ("tail_gate", "tail_mid_decrease_db", "paired_minimum", 0.5),
        "tail_high": ("tail_gate", "tail_high_decrease_db", "paired_minimum", 0.5),
        "two_stage_decay": ("tail_gate", "double_decay_slope_delta_median_db_per_second", "absolute_change", 1.0),
        "high_detail": ("high_reduction", "high_band_ratio_p90", "relative_decrease", 0.60),
        "broadband_balance": ("band_balance", "mid_band_ratio_median", "relative_decrease", 0.30),
        "stereo": ("mono", "stereo_side_ratio", "relative_decrease", 0.95),
    }
    result: dict[str, dict[str, object]] = {}
    for label, (case, metric, rule, threshold) in checks.items():
        if rule == "paired_minimum":
            clean_value = float(paired[case][metric])
            degraded_value = clean_value
            amount = clean_value
            passed = amount >= threshold
        else:
            clean_value = float(clean[metric])
            degraded_value = float(cases[case][metric])
        if rule == "maximum":
            amount = degraded_value
            passed = degraded_value <= threshold
        elif rule == "relative_decrease":
            amount = None if abs(clean_value) <= EPSILON else (clean_value - degraded_value) / abs(clean_value)
            passed = amount is not None and amount >= threshold
        elif rule == "relative_increase":
            amount = None if abs(clean_value) <= EPSILON else (degraded_value - clean_value) / abs(clean_value)
            passed = amount is not None and amount >= threshold
        elif rule == "absolute_change":
            amount = abs(degraded_value - clean_value)
            passed = amount >= threshold
        elif rule != "paired_minimum":
            raise ValueError(rule)
        result[label] = {
            "case": case,
            "metric": metric,
            "clean": clean_value,
            "degraded": degraded_value,
            "rule": rule,
            "required": threshold,
            "observed": amount,
            "passed": bool(passed),
        }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", required=True, choices=("guitar", "piano"))
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    audio, sample_rate = load_audio(args.input)
    if audio.shape[1] != 2:
        raise ValueError("Guitar/Piano解析はstereo入力だけを受け付けます")
    clean = analyze(audio, sample_rate)
    degraded_audio = degradations(audio, sample_rate)
    cases = {name: analyze(value, sample_rate) for name, value in degraded_audio.items()}
    paired = {
        name: matched_temporal_comparison(audio, value, sample_rate)
        for name, value in degraded_audio.items()
    }
    if args.output_dir:
        write_audio(args.output_dir / "clean.wav", audio, sample_rate)
        for name, value in degraded_audio.items():
            write_audio(args.output_dir / f"{name}.wav", value, sample_rate)

    payload = {
        "role": args.role,
        "input": str(args.input.resolve()),
        "sample_rate": sample_rate,
        "channels": audio.shape[1],
        "frame_size": FRAME_SIZE,
        "hop_size": HOP_SIZE,
        "activity_floor_dbfs": SILENCE_FLOOR_DB,
        "clean": clean,
        "degradations": cases,
        "paired_comparisons": paired,
        "relative_changes": {
            case: {
                metric: relative_change(float(clean[metric]), float(values[metric]))
                for metric in clean
                if isinstance(clean[metric], (float, int))
            }
            for case, values in cases.items()
        },
        "discrimination": evaluate_discrimination(clean, cases, paired),
    }
    encoded = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)


if __name__ == "__main__":
    main()
