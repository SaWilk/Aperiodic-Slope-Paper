# -*- coding: utf-8 -*-
"""
aperiodic_fooof_01_run_fooof_from_psd.py

Runs FOOOFGroup on Welch PSD .mat files exported from MATLAB (incl. -v7.3 HDF5 .mat).
Writes BIDS-ish derivatives outputs under:
  .../derivatives/08_fooof/sub-XXX/

NEW:
- Optional skipping of already-processed subjects/conditions via CLI flags.

Examples:
  # default: DO NOT skip (recompute + overwrite)
  python aperiodic_fooof_01_run_fooof_from_psd.py

  # skip if BOTH open+closed outputs already exist for a subject
  python aperiodic_fooof_01_run_fooof_from_psd.py --skip-existing

  # skip per-condition (skip open if open output exists; still run closed if missing)
  python aperiodic_fooof_01_run_fooof_from_psd.py --skip-existing --skip-mode per_condition

  # only run a subset of subjects
  python aperiodic_fooof_01_run_fooof_from_psd.py --subjects sub-080 sub-081 sub-136 --skip-existing
"""

from __future__ import annotations

from pathlib import Path
import json
import argparse

import numpy as np
import h5py
from scipy.io import loadmat, savemat
from fooof import FOOOFGroup


# -------------------------- USER CONFIG ---------------------------------

DERIV_ROOT = Path(r"Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives")
PSD_ROOT   = DERIV_ROOT / "07_psd_welch"
OUT_ROOT   = DERIV_ROOT / "08_fooof"

FREQ_RES_TAG = "0p50"         # corresponds to 0.50 Hz
FREQ_RANGE   = (1.0, 45.0)

FOOOF_SETTINGS = dict(
    peak_width_limits=(1.0, 12.0),
    max_n_peaks=6,
    min_peak_height=0.1,
    peak_threshold=2.0,
    aperiodic_mode="fixed",   # "fixed" slope+offset; consider "knee" if you want knee
    verbose=False,
)

SAVE_JSON = True
SAVE_MAT  = True


# -------------------------- I/O HELPERS ---------------------------------

def _as_1d(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x)
    return np.squeeze(x).astype(float)

def _ensure_freq_by_chan(psd: np.ndarray, freqs: np.ndarray) -> np.ndarray:
    """Ensure PSD shape is [nFreq x nChan]."""
    psd = np.asarray(psd, dtype=float)
    if psd.ndim != 2:
        raise ValueError(f"PSD must be 2D [freq x chan], got shape {psd.shape}")
    nF = freqs.size
    if psd.shape[0] == nF:
        return psd
    if psd.shape[1] == nF:
        return psd.T
    raise ValueError(f"PSD shape {psd.shape} does not match freqs length {nF}")

def load_mat_any(path: Path) -> dict:
    """
    Load MATLAB .mat from:
      - scipy.io.loadmat for <=v7.2
      - h5py for -v7.3 (HDF5)
    Returns a dict mapping variable names to numpy arrays where possible.
    """
    path = Path(path)
    try:
        data = loadmat(path, squeeze_me=False, struct_as_record=False)
        data = {k: v for k, v in data.items() if not k.startswith("__")}
        return data
    except NotImplementedError:
        data = {}
        with h5py.File(path, "r") as f:
            for key in f.keys():
                obj = f[key]
                if isinstance(obj, h5py.Dataset):
                    data[key] = np.array(obj)
                else:
                    # ignore MATLAB structs/groups (meta) safely
                    pass
        return data

def safe_mkdir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)

def pick_subject_dirs(psd_root: Path) -> list[Path]:
    return sorted([p for p in psd_root.glob("sub-*") if p.is_dir()])


# -------------------------- FOOOF HELPERS -------------------------------

def run_fooof_group(freqs: np.ndarray, psd_f_by_ch: np.ndarray):
    """
    Fit FOOOFGroup across channels (each channel = one spectrum).
    Returns: exps, offsets, r2, error, fg, info
    """
    fg = FOOOFGroup(**FOOOF_SETTINGS)

    # FOOOF expects spectra shape [nSpectra x nFreq]
    spectra = psd_f_by_ch.T  # [nChan x nFreq]

    fg.fit(freqs, spectra, FREQ_RANGE)

    exps    = fg.get_params("aperiodic_params", "exponent")
    offsets = fg.get_params("aperiodic_params", "offset")
    r2      = fg.get_params("r_squared")
    err     = fg.get_params("error")

    info = {
        "freq_range": list(map(float, FREQ_RANGE)),
        "aperiodic_mode": FOOOF_SETTINGS.get("aperiodic_mode", "fixed"),
        "backend": "fooof",
        "n_channels": int(spectra.shape[0]),
        "n_freqs": int(freqs.size),
    }
    return exps, offsets, r2, err, fg, info

def save_json_results(exps, offsets, r2, err, meta: dict, out_json: Path) -> None:
    payload = dict(meta)
    payload.update(
        exps=np.asarray(exps).tolist(),
        offsets=np.asarray(offsets).tolist(),
        r2=np.asarray(r2).tolist(),
        error=np.asarray(err).tolist(),
    )
    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")


# -------------------------- SKIP LOGIC ----------------------------------

def output_paths_for(sub: str, out_sub_dir: Path):
    """Return expected output paths per condition."""
    out = {}
    for cond in ("open", "closed"):
        out[cond] = {
            "mat":  out_sub_dir / f"{sub}_desc-fooof_cond-{cond}.mat",
            "json": out_sub_dir / f"{sub}_desc-fooof_cond-{cond}_results.json",
        }
    return out

def already_done(sub: str, out_sub_dir: Path, require_json: bool) -> dict:
    """
    Return dict: {"open": bool, "closed": bool} whether outputs exist.
    If require_json=True, require both MAT and JSON to count as done.
    """
    paths = output_paths_for(sub, out_sub_dir)
    done = {}
    for cond in ("open", "closed"):
        mat_ok = paths[cond]["mat"].exists()
        if require_json:
            json_ok = paths[cond]["json"].exists()
            done[cond] = mat_ok and json_ok
        else:
            done[cond] = mat_ok
    return done


# -------------------------- MAIN ----------------------------------------

def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--skip-existing",
        action="store_true",
        help="If set, skip subjects/conditions that already have outputs in 08_fooof."
    )
    ap.add_argument(
        "--skip-mode",
        choices=("subject", "per_condition"),
        default="subject",
        help=("How to skip when --skip-existing is set: "
              "'subject' skips whole subject only if BOTH open+closed are done; "
              "'per_condition' skips each condition independently.")
    )
    ap.add_argument(
        "--require-json",
        action="store_true",
        help="If set, count a condition as done only if both .mat and _results.json exist."
    )
    ap.add_argument(
        "--subjects",
        nargs="*",
        default=None,
        help="Optional list of subject folders to process, e.g., sub-080 sub-081. If omitted, process all in 07_psd_welch."
    )
    return ap.parse_args()

def main() -> None:
    args = parse_args()

    safe_mkdir(OUT_ROOT)

    sub_dirs = pick_subject_dirs(PSD_ROOT)
    if not sub_dirs:
        raise RuntimeError(f"No sub-* folders found in: {PSD_ROOT}")

    # Optional subject filter
    if args.subjects:
        wanted = set(args.subjects)
        sub_dirs = [p for p in sub_dirs if p.name in wanted]
        print(f"Filtered to {len(sub_dirs)} subjects via --subjects")

    print(f"Found {len(sub_dirs)} subjects in {PSD_ROOT}")

    for sub_dir in sub_dirs:
        sub = sub_dir.name

        open_mat   = sub_dir / f"{sub}_desc-psd_method-welch_freqres-{FREQ_RES_TAG}_cond-open.mat"
        closed_mat = sub_dir / f"{sub}_desc-psd_method-welch_freqres-{FREQ_RES_TAG}_cond-closed.mat"

        if not open_mat.exists() or not closed_mat.exists():
            print(f"SKIP {sub}: missing PSD mats (open={open_mat.exists()} closed={closed_mat.exists()})")
            continue

        out_sub_dir = OUT_ROOT / sub
        safe_mkdir(out_sub_dir)

        # Skip logic
        if args.skip_existing:
            done = already_done(sub, out_sub_dir, require_json=args.require_json)

            if args.skip_mode == "subject":
                if done["open"] and done["closed"]:
                    print(f"SKIP {sub}: already processed (open+closed)")
                    continue
            # per_condition handled below inside loop

        print(f"--- {sub} ---")

        for cond, mat_path, psd_key in [
            ("open",   open_mat,   "PSDopen"),
            ("closed", closed_mat, "PSDclosed"),
        ]:
            if args.skip_existing and args.skip_mode == "per_condition":
                done = already_done(sub, out_sub_dir, require_json=args.require_json)
                if done[cond]:
                    print(f"  SKIP {sub} {cond}: already processed")
                    continue

            print(f"  Processing {sub} | {cond}")

            data = load_mat_any(mat_path)

            if "freqs" not in data:
                print(f"    SKIP {sub} {cond}: no 'freqs' in {mat_path.name}. Keys={list(data.keys())[:10]}")
                continue
            if psd_key not in data:
                print(f"    SKIP {sub} {cond}: no '{psd_key}' in {mat_path.name}. Keys={list(data.keys())[:10]}")
                continue

            freqs = _as_1d(data["freqs"]).reshape(-1)

            psd_raw = np.array(data[psd_key])
            psd_f_by_ch = _ensure_freq_by_chan(psd_raw, freqs)

            try:
                exps, offsets, r2, err, fg, info = run_fooof_group(freqs, psd_f_by_ch)
            except Exception as e:
                print(f"    FAIL {sub} {cond}: FOOOF fit error: {e}")
                continue

            if SAVE_MAT:
                out_mat = out_sub_dir / f"{sub}_desc-fooof_cond-{cond}.mat"
                savemat(
                    out_mat,
                    {
                        "sub": sub,
                        "cond": cond,
                        "freqs": freqs.astype(float),
                        "exps": np.asarray(exps, dtype=float),
                        "offsets": np.asarray(offsets, dtype=float),
                        "freq_range": np.asarray(FREQ_RANGE, dtype=float),
                        "aperiodic_mode": info["aperiodic_mode"],
                        "backend": info["backend"],
                        "r2": np.asarray(r2, dtype=float),
                        "error": np.asarray(err, dtype=float),
                    },
                )

            if SAVE_JSON:
                out_json = out_sub_dir / f"{sub}_desc-fooof_cond-{cond}_results.json"
                save_json_results(exps, offsets, r2, err, info, out_json)

        print(f"OK {sub}")

    print(f"\nDONE. Outputs in: {OUT_ROOT}")


if __name__ == "__main__":
    main()