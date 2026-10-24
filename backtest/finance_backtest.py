"""Backtest of the finance-sector rules in config/sectors.json.

Scores every month since the data allows with the same formula the app uses
(clamped linear 0-100 per signal, weighted sum, 70/40 bands with a +-3 dead-band),
then asks four questions:

1. Forward returns by zone: is the next 6/12 months better in EXPANSION than in DIGESTION?
2. Strategy: does following the allocation rules beat plain monthly DCA?
3. Calibration: what would anchors look like if set from history (10th/90th pct)?
4. Robustness: how much do results move with other weights, smoothing, no dead-band?

Usage:  python backtest/finance_backtest.py            (downloads FRED + Yahoo data)
        python backtest/finance_backtest.py --synthetic (offline smoke test)
Outputs go to backtest/results/.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "backtest" / "results"
CONFIG = ROOT / "config" / "sectors.json"

X_TH, D_TH, BAND = 70.0, 40.0, 3.0
FRED_IDS = ["T10Y2Y", "BAMLH0A0HYM2", "BAA10Y", "TOTLL", "DRCCLACBS", "FEDFUNDS", "TB3MS"]
TICKERS = ["XLF", "KBE", "JPM", "GS", "V", "SPY", "^BKX"]
EPISODES_MIN_DD = 0.25


# ----------------------------------------------------------------------------- data

def _get(url: str, tries: int = 4) -> str:
    import socket
    import urllib.request
    socket.setdefaulttimeout(40)
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (backtest)"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode("utf-8")
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(3 * (i + 1))
    raise RuntimeError(f"download failed: {url}: {last}")


def fred(series_id: str) -> pd.Series:
    cached = ROOT / "backtest" / "cache" / f"{series_id}.csv"
    if cached.exists() and cached.stat().st_size > 100:
        txt = cached.read_text()
    else:
        txt = _get(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}")
    df = pd.read_csv(io.StringIO(txt))
    df.columns = ["date", series_id]
    df["date"] = pd.to_datetime(df["date"])
    s = pd.to_numeric(df[series_id], errors="coerce")
    s.index = df["date"]
    return s.dropna()


def prices_yahoo(tickers: list[str]) -> dict[str, pd.Series]:
    import yfinance as yf
    out = {}
    for t in tickers:
        for attempt in range(3):
            try:
                print(f"yahoo {t} ...", flush=True)
                df = yf.download(t, start="1985-01-01", auto_adjust=True, progress=False, threads=False, timeout=30)
                if df is not None and len(df) > 0:
                    close = df["Close"]
                    if isinstance(close, pd.DataFrame):
                        close = close.iloc[:, 0]
                    out[t] = close.dropna()
                    break
            except Exception as e:  # noqa: BLE001
                print(f"yahoo {t} attempt {attempt}: {e}", file=sys.stderr)
            time.sleep(3)
    return out


def synthetic() -> tuple[dict[str, pd.Series], dict[str, pd.Series]]:
    rng = np.random.default_rng(0)
    d = pd.date_range("1985-01-01", "2026-09-30", freq="D")
    m = pd.date_range("1985-01-01", "2026-09-01", freq="MS")
    cyc = np.sin(np.arange(len(d)) / 900)
    f = {
        "T10Y2Y": pd.Series(1 + 1.2 * cyc + rng.normal(0, .1, len(d)), d),
        "BAMLH0A0HYM2": pd.Series(4.5 - 2 * cyc + rng.normal(0, .2, len(d)), d)["1997":],
        "BAA10Y": pd.Series(2.2 - .8 * cyc + rng.normal(0, .1, len(d)), d),
        "TOTLL": pd.Series(np.exp(np.cumsum(0.0002 + 0.0001 * cyc)) * 1000, d).resample("W").last(),
        "DRCCLACBS": pd.Series(3.5 - cyc[::91][: len(pd.date_range('1991-01-01', '2026-06-30', freq='QS'))], pd.date_range("1991-01-01", "2026-06-30", freq="QS")),
        "FEDFUNDS": pd.Series(3 + 2 * np.sin(np.arange(len(m)) / 30), m),
        "TB3MS": pd.Series(3 + 2 * np.sin(np.arange(len(m)) / 30), m),
    }
    p = {}
    for t, start in [("XLF", "1998-12-22"), ("JPM", "1985-01-01"), ("GS", "1999-05-04"), ("V", "2008-03-19"), ("SPY", "1993-01-29"), ("KBE", "2005-11-15")]:
        idx = d[d >= start]
        p[t] = pd.Series(np.exp(np.cumsum(rng.normal(0.0003, 0.015, len(idx)) + 0.0004 * cyc[-len(idx):])) * 20, idx)
    return f, p


# ----------------------------------------------------------------------------- panel

def month_end(s: pd.Series) -> pd.Series:
    return s.resample("ME").last()


def build_panel(f: dict[str, pd.Series]) -> tuple[pd.DataFrame, dict]:
    notes = {}
    curve = month_end(f["T10Y2Y"])

    # Credit spread: ICE HY OAS where FRED has it; earlier months spliced from Moody's Baa-10y
    # through a linear fit on the overlap (FRED only keeps a few years of ICE history).
    hy = month_end(f["BAMLH0A0HYM2"]) if "BAMLH0A0HYM2" in f else pd.Series(dtype=float)
    baa = month_end(f["BAA10Y"])
    both = pd.concat([hy, baa], axis=1, keys=["hy", "baa"]).dropna()
    if len(both) >= 24:
        b, a = np.polyfit(both["baa"], both["hy"], 1)
        corr = float(both.corr().iloc[0, 1])
    else:
        b, a, corr = 2.4, -0.8, float("nan")
    proxy = a + b * baa
    credit = hy.combine_first(proxy)
    notes["credit_spread"] = {
        "hy_history_from": str(hy.index.min().date()) if len(hy) else None,
        "spliced_from_baa10y_before": str(hy.index.min().date()) if len(hy) else "all",
        "fit": f"HY = {a:.2f} + {b:.2f} x BAA10Y (overlap {len(both)} months, corr {corr:.2f})",
    }

    # Loans: year-over-year growth of TOTLL, known about one month later.
    loans = month_end(f["TOTLL"])
    loan_g = (loans.pct_change(12, fill_method=None) * 100).shift(1)
    notes["loan_growth"] = "TOTLL year-over-year %, lagged 1 month (app uses a recent annualized rate)"

    # Delinquency: quarterly, published ~2 months after the quarter ends.
    dq = f["DRCCLACBS"].copy()
    dq.index = dq.index + pd.DateOffset(months=5) - pd.Timedelta(days=1)
    dq = dq.resample("ME").last().ffill()
    notes["delinquency"] = "DRCCLACBS, usable from the end of the 2nd month after each quarter"

    # Fed policy: the app uses a judgement score; history uses a mechanical stand-in.
    ff = f["FEDFUNDS"].copy()
    ff.index = ff.index + pd.offsets.MonthEnd(0)
    d6 = ff.diff(6)
    fed = (50 - 50 * d6 / 1.0).clip(0, 100)
    notes["fed_policy"] = "Proxy: 50 - 50 x (6-month change in fed funds, pp), clamped 0-100. Cutting 1pp = 100, hiking 1pp = 0"

    rf = f["TB3MS"].copy()
    rf.index = rf.index + pd.offsets.MonthEnd(0)

    panel = pd.concat(
        {"yield_curve_10y2y_pct": curve, "hy_oas_pct": credit, "loan_growth_pct": loan_g,
         "cc_delinquency_pct": dq, "fed_policy_score": fed, "rf": rf},
        axis=1,
    )
    panel["rf"] = panel["rf"].ffill()
    panel = panel.dropna(subset=[c for c in panel.columns if c != "rf"])
    panel = panel[panel.index <= pd.Timestamp.today() + pd.offsets.MonthEnd(0)]
    return panel, notes


def monthly_returns(p: dict[str, pd.Series]) -> pd.DataFrame:
    px = pd.concat({k: month_end(v) for k, v in p.items()}, axis=1)
    return px


# ----------------------------------------------------------------------------- scoring

def score(panel: pd.DataFrame, signals: list[dict]) -> tuple[pd.Series, pd.DataFrame]:
    subs = {}
    for s in signals:
        v = panel[s["field"]]
        subs[s["key"]] = ((v - s["worst"]) / (s["best"] - s["worst"]) * 100).clip(0, 100)
    subs = pd.DataFrame(subs)
    w = pd.Series({s["key"]: s["weight"] for s in signals})
    idx = (subs * w).sum(axis=1) / w.sum()
    return idx, subs


def zones(idx: pd.Series, band: float = BAND) -> pd.Series:
    out, prev = [], None
    for x in idx.values:
        if prev is None:
            z = "X" if x >= X_TH else ("W" if x >= D_TH else "D")
        else:
            upper = X_TH - band if prev == "X" else X_TH + band
            lower = D_TH + band if prev == "D" else D_TH - band
            z = "X" if x >= upper else ("D" if x < lower else "W")
        out.append(z)
        prev = z
    return pd.Series(out, idx.index)


def flips(z: pd.Series) -> int:
    return int((z != z.shift()).sum() - 1)


# ----------------------------------------------------------------------------- tests

def forward_table(z: pd.Series, idx: pd.Series, px: pd.Series) -> dict:
    px = px.reindex(z.index)
    f6 = px.shift(-6) / px - 1
    f12 = px.shift(-12) / px - 1
    roll_min = pd.concat([px.shift(-k) for k in range(1, 13)], axis=1).min(axis=1)
    dd12 = roll_min / px - 1
    df = pd.DataFrame({"z": z, "idx": idx, "f6": f6, "f12": f12, "dd12": dd12}).dropna()
    res = {"months": int(len(df)), "from": str(df.index.min().date()) if len(df) else None, "by_zone": {}}
    for code in ["X", "W", "D"]:
        g = df[df.z == code]
        if len(g) == 0:
            continue
        res["by_zone"][code] = {
            "months": int(len(g)),
            "share": round(len(g) / len(df), 3),
            "fwd6_mean": round(float(g.f6.mean()) * 100, 1),
            "fwd12_mean": round(float(g.f12.mean()) * 100, 1),
            "fwd12_median": round(float(g.f12.median()) * 100, 1),
            "fwd12_neg_share": round(float((g.f12 < 0).mean()), 3),
            "worst_dd_next12_mean": round(float(g.dd12.mean()) * 100, 1),
        }
    res["all_fwd12_mean"] = round(float(df.f12.mean()) * 100, 1) if len(df) else None
    res["spearman_idx_fwd12"] = round(float(df[["idx", "f12"]].rank().corr().iloc[0, 1]), 3) if len(df) > 24 else None
    return res


def irr_monthly(n: int, terminal: float) -> float:
    """Annualized money-weighted return for 1 unit invested at the start of each of n months."""
    if n == 0 or terminal <= 0:
        return float("nan")
    lo, hi = -0.99, 1.0
    for _ in range(200):
        r = (lo + hi) / 2
        fv = sum((1 + r) ** (n - k) for k in range(n))
        if fv > terminal:
            hi = r
        else:
            lo = r
    return (1 + r) ** 12 - 1


def simulate(z: pd.Series, rets: pd.DataFrame, rf: pd.Series, rules: dict, mode: str) -> dict:
    """Monthly DCA of 1 unit. rets: next-month total return per ticker (columns = tickers).

    mode 'plain': always split by the EXPANSION weights.
    mode 'rules': follow the zone's rule cell; unspent money goes to cash at the T-bill rate,
                  REDUCE trims holdings once when the zone is entered, cash is redeployed in EXPANSION.
    """
    tickers = list(rets.columns)
    xw = {t: rules["X"].get(t, ["BUY_DCA", 0])[1] / 100 for t in tickers}
    sw = sum(xw.values()) or 1
    xw = {t: v / sw for t, v in xw.items()}
    H = {t: 0.0 for t in tickers}
    C = 0.0
    prev = None
    values, contrib = [], 0
    for date in rets.index:
        zc = z.loc[date]
        contrib += 1
        if mode == "plain":
            for t in tickers:
                H[t] += xw[t]
        else:
            cell = rules[zc]
            spend = 0.0
            for t in tickers:
                act = cell.get(t, ["HOLD", 0])
                if act[0] in ("BUY_DCA", "OVERWEIGHT_DCA", "ACCUMULATE"):
                    H[t] += act[1] / 100
                    spend += act[1] / 100
                if act[0] == "REDUCE_HOLDINGS" and prev != zc and len(act) > 2:
                    cut = H[t] * act[2] / 100
                    H[t] -= cut
                    C += cut
            C += max(0.0, 1 - spend)
            if zc == "X" and C > 0:
                for t in tickers:
                    H[t] += C * xw[t]
                C = 0.0
        prev = zc
        r = rets.loc[date]
        for t in tickers:
            H[t] *= 1 + (0.0 if pd.isna(r[t]) else r[t])
        C *= 1 + (rf.loc[date] if not pd.isna(rf.loc[date]) else 0) / 1200
        values.append(sum(H.values()) + C)
    v = pd.Series(values, rets.index)
    dd = float((v / v.cummax() - 1).min())
    return {"terminal": float(v.iloc[-1]), "contributed": contrib, "irr": irr_monthly(contrib, float(v.iloc[-1])),
            "max_dd": dd, "series": v}


def sector_rules(rules: dict) -> dict:
    """Collapse the 3-stock rule matrix into one 'SECTOR' column with the same money flows."""
    tick = list(rules["X"].keys())
    xw = {t: rules["X"][t][1] / 100 for t in tick}
    sw = sum(xw.values()) or 1
    out = {}
    for zc, cell in rules.items():
        buy = sum(cell[t][1] / 100 for t in tick if cell[t][0] in ("BUY_DCA", "OVERWEIGHT_DCA", "ACCUMULATE"))
        trim = sum(xw[t] / sw * (cell[t][2] if cell[t][0] == "REDUCE_HOLDINGS" and len(cell[t]) > 2 else 0) for t in tick)
        a = ["BUY_DCA", buy * 100] if buy > 0 else (["REDUCE_HOLDINGS", 0, trim] if trim > 0 else ["HOLD", 0])
        out[zc] = {"SECTOR": a}
    return out


def strategy_pair(z, px: pd.DataFrame, rf, rules, start=None) -> dict:
    rets = (px.shift(-1) / px - 1).reindex(z.index)
    rets = rets.dropna(how="any")
    if start is not None:
        rets = rets[rets.index >= start]
    if len(rets) < 24:
        return {}
    zz = z.reindex(rets.index)
    rr = rf.reindex(rets.index)
    plain = simulate(zz, rets, rr, rules, "plain")
    rule = simulate(zz, rets, rr, rules, "rules")
    return {
        "from": str(rets.index.min().date()), "to": str(rets.index.max().date()), "months": len(rets),
        "plain": {k: plain[k] for k in ("terminal", "irr", "max_dd")},
        "rules": {k: rule[k] for k in ("terminal", "irr", "max_dd")},
        "terminal_ratio": rule["terminal"] / plain["terminal"],
        "irr_diff_pp": (rule["irr"] - plain["irr"]) * 100,
        "_series": (plain["series"], rule["series"]),
    }


def episodes(px: pd.Series, z: pd.Series, idx: pd.Series) -> list[dict]:
    px = px.reindex(z.index).dropna()
    out, i, n = [], 0, len(px)
    peak_i = 0
    while i < n:
        if px.iloc[i] >= px.iloc[peak_i]:
            peak_i = i
        dd = px.iloc[i] / px.iloc[peak_i] - 1
        if dd <= -EPISODES_MIN_DD:
            trough_i = i
            while trough_i + 1 < n and px.iloc[trough_i + 1] < px.iloc[trough_i]:
                trough_i += 1
            # extend to the lowest point before recovering to the old peak
            j = trough_i
            while j < n and px.iloc[j] < px.iloc[peak_i]:
                if px.iloc[j] < px.iloc[trough_i]:
                    trough_i = j
                j += 1
            pk, tr = px.index[peak_i], px.index[trough_i]
            window = z[(z.index >= pk - pd.DateOffset(months=24)) & (z.index <= tr)]
            first_d = window[window == "D"].index.min() if (window == "D").any() else None
            first_wd = window[window != "X"].index.min() if (window != "X").any() else None
            out.append({
                "peak": str(pk.date()), "trough": str(tr.date()),
                "drawdown_pct": round((px.loc[tr] / px.loc[pk] - 1) * 100, 1),
                "zone_at_peak": z.loc[pk], "index_at_peak": round(float(idx.loc[pk]), 1),
                "zone_at_trough": z.loc[tr], "index_at_trough": round(float(idx.loc[tr]), 1),
                "first_D_vs_peak_months": None if first_d is None else int(round((first_d - pk).days / 30.44)),
                "first_W_or_D_vs_peak_months": None if first_wd is None else int(round((first_wd - pk).days / 30.44)),
            })
            i = j
            peak_i = min(j, n - 1)
            continue
        i += 1
    return out


def calibrate(panel: pd.DataFrame, signals: list[dict], until=None) -> list[dict]:
    p = panel if until is None else panel[panel.index < until]
    out = []
    for s in signals:
        v = p[s["field"]]
        higher_better = s["best"] > s["worst"]
        lo, hi = float(v.quantile(0.10)), float(v.quantile(0.90))
        c = dict(s)
        c["worst"], c["best"] = (lo, hi) if higher_better else (hi, lo)
        out.append(c)
    return out


def ic_by_signal(subs: pd.DataFrame, px: pd.Series) -> dict:
    f12 = (px.shift(-12) / px - 1).reindex(subs.index)
    df = subs.assign(f12=f12).dropna()
    return {k: round(float(df[[k, "f12"]].rank().corr().iloc[0, 1]), 3) for k in subs.columns}


# ----------------------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(CONFIG.read_text())
    fin = next(s for s in cfg["sectors"] if s["id"] == "finance")
    signals = fin["signals"]
    rules = fin["rules"]

    if args.synthetic:
        f, p = synthetic()
    else:
        f = {}
        for sid in FRED_IDS:
            try:
                print(f"FRED {sid} ...", flush=True)
                f[sid] = fred(sid)
                print(f"FRED {sid}: {f[sid].index.min().date()} -> {f[sid].index.max().date()} ({len(f[sid])})")
            except Exception as e:  # noqa: BLE001
                print(f"FRED {sid} failed: {e}", file=sys.stderr)
        p = prices_yahoo(TICKERS)
        for k, v in p.items():
            print(f"Yahoo {k}: {v.index.min().date()} -> {v.index.max().date()} ({len(v)})")

    panel, notes = build_panel(f)
    px = monthly_returns(p)
    idx, subs = score(panel, signals)
    z = zones(idx)
    rf = panel["rf"]

    sec_rules = sector_rules(rules)
    assets = [a for a in ["XLF", "^BKX", "KBE", "JPM", "SPY"] if a in px.columns]

    def evaluate(sig, label, smooth=False, band=BAND, oos_from=None):
        i, s_ = score(panel, sig)
        if smooth:
            i = i.ewm(span=3, adjust=False).mean()
        zz = zones(i, band)
        row = {"label": label, "flips": flips(zz if oos_from is None else zz[zz.index >= oos_from]),
               "share": {c: round(float((zz == c).mean()), 3) for c in "XWD"}}
        for a in [a for a in ["XLF", "JPM"] if a in px.columns]:
            sp = strategy_pair(zz, px[[a]].rename(columns={a: "SECTOR"}), rf, sec_rules, start=oos_from)
            if sp:
                row[a] = {"irr_diff_pp": round(sp["irr_diff_pp"], 2), "terminal_ratio": round(sp["terminal_ratio"], 3),
                          "dd_rules": round(sp["rules"]["max_dd"] * 100, 1), "dd_plain": round(sp["plain"]["max_dd"] * 100, 1),
                          "from": sp["from"]}
            fp = px[a].reindex(i.index)
            df = pd.DataFrame({"i": i, "f": fp.shift(-12) / fp - 1}).dropna()
            if oos_from is not None:
                df = df[df.index >= oos_from]
            row.setdefault("ic", {})[a] = round(float(df.rank().corr().iloc[0, 1]), 3) if len(df) > 24 else None
        return row, zz, i

    results: dict = {
        "generated": pd.Timestamp.utcnow().isoformat(),
        "synthetic": args.synthetic,
        "panel": {"from": str(panel.index.min().date()), "to": str(panel.index.max().date()), "months": len(panel)},
        "data_coverage": {k: [str(v.index.min().date()), str(v.index.max().date())] for k, v in f.items()},
        "price_coverage": {k: [str(v.index.min().date()), str(v.index.max().date())] for k, v in p.items()},
        "notes": notes,
        "current_rules": {"signals": [{k: s[k] for k in ("key", "weight", "worst", "best")} for s in signals],
                          "sector_level_rules": sec_rules},
        "latest": {"date": str(panel.index[-1].date()), "index": round(float(idx.iloc[-1]), 1), "zone": z.iloc[-1],
                   "values": {k: round(float(panel[k].iloc[-1]), 2) for k in panel.columns}},
        "zone_share": {c: round(float((z == c).mean()), 3) for c in "XWD"},
        "flips": flips(z),
        "forward": {a: forward_table(z, idx, px[a]) for a in assets},
        "signal_ic_fwd12": {a: ic_by_signal(subs, px[a]) for a in assets},
        "episodes": {a: episodes(px[a], z, idx) for a in ["XLF", "JPM", "^BKX"] if a in px.columns},
    }

    # Strategy: sector-level on long series, and the real 3-stock matrix since Visa listed.
    strat = {}
    for a in [a for a in ["XLF", "^BKX", "JPM"] if a in px.columns]:
        sp = strategy_pair(z, px[[a]].rename(columns={a: "SECTOR"}), rf, sec_rules)
        if sp:
            strat[a] = {k: v for k, v in sp.items() if k != "_series"}
    stocks = [t for t in rules["X"] if t in px.columns]
    three = strategy_pair(z, px[stocks], rf, rules) if len(stocks) == len(rules["X"]) else {}
    if three:
        strat["3_stock_matrix"] = {k: v for k, v in three.items() if k != "_series"}
    results["strategy"] = strat

    # Calibration + robustness.
    cal_full = calibrate(panel, signals)
    cal_train = calibrate(panel, signals, until=pd.Timestamp("2010-01-01"))
    variants = []
    base_row, _, _ = evaluate(signals, "current rules")
    variants.append(base_row)
    variants.append(evaluate(signals, "no dead-band", band=0.0)[0])
    variants.append(evaluate(signals, "3-month smoothing", smooth=True)[0])
    variants.append(evaluate(cal_full, "anchors from full-history 10/90 pct (in-sample)")[0])
    variants.append(evaluate(signals, "current rules, 2010+ only", oos_from=pd.Timestamp("2010-01-01"))[0])
    variants.append(evaluate(cal_train, "anchors from pre-2010 data, tested 2010+ (out-of-sample)", oos_from=pd.Timestamp("2010-01-01"))[0])
    # Naive yardstick: price above its 10-month average = EXPANSION, below = DIGESTION.
    for a in [a for a in ["XLF", "JPM"] if a in px.columns]:
        pa = px[a].reindex(z.index)
        tz = pd.Series(np.where(pa > pa.rolling(10).mean(), "X", "D"), z.index)[pa.rolling(10).mean().notna()]
        sp = strategy_pair(tz, px[[a]].rename(columns={a: "SECTOR"}), rf, sec_rules)
        if sp:
            variants.append({"label": f"yardstick: {a} price vs 10-month average", "flips": flips(tz),
                             a: {"irr_diff_pp": round(sp["irr_diff_pp"], 2), "terminal_ratio": round(sp["terminal_ratio"], 3),
                                 "dd_rules": round(sp["rules"]["max_dd"] * 100, 1), "dd_plain": round(sp["plain"]["max_dd"] * 100, 1),
                                 "from": sp["from"]}})
    results["variants"] = variants
    results["calibrated_anchors"] = {
        "full_history": [{k: round(s[k], 2) if isinstance(s[k], float) else s[k] for k in ("key", "worst", "best")} for s in cal_full],
        "pre_2010": [{k: round(s[k], 2) if isinstance(s[k], float) else s[k] for k in ("key", "worst", "best")} for s in cal_train],
    }

    rng = np.random.default_rng(42)
    sens = []
    main_asset = "XLF" if "XLF" in px.columns else assets[0]
    for _ in range(300):
        w = rng.dirichlet(np.ones(len(signals)))
        sig = [dict(s, weight=float(wi)) for s, wi in zip(signals, w)]
        i, _ = score(panel, sig)
        zz = zones(i)
        sp = strategy_pair(zz, px[[main_asset]].rename(columns={main_asset: "SECTOR"}), rf, sec_rules)
        if sp:
            sens.append(sp["irr_diff_pp"])
    if sens:
        sens = np.array(sens)
        results["weight_sensitivity"] = {
            "asset": main_asset, "draws": int(len(sens)),
            "irr_diff_pp_p10": round(float(np.percentile(sens, 10)), 2),
            "irr_diff_pp_median": round(float(np.median(sens)), 2),
            "irr_diff_pp_p90": round(float(np.percentile(sens, 90)), 2),
            "share_beating_plain": round(float((sens > 0).mean()), 3),
        }

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "finance.json").write_text(json.dumps(results, indent=1, default=str))
    pd.DataFrame({"index": idx.round(1), "zone": z}).join(subs.round(1)).join(panel.round(3)).to_csv(OUT / "finance_monthly.csv")
    charts(idx, z, px, strategy_pair(z, px[[main_asset]].rename(columns={main_asset: "SECTOR"}), rf, sec_rules), main_asset)
    print(json.dumps({k: results[k] for k in ("panel", "latest", "zone_share", "flips", "strategy", "variants")}, indent=1, default=str))


def charts(idx, z, px, sp, asset):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colors = {"X": "#00E676", "W": "#FFD600", "D": "#FF5252"}
    fig, (a1, a2, a3) = plt.subplots(3, 1, figsize=(11, 10), sharex=True, gridspec_kw={"height_ratios": [2, 2, 2]})
    for ax in (a1, a2, a3):
        ax.set_facecolor("#1E1E1E")
        ax.tick_params(colors="#A0A0A0")
        for sp_ in ax.spines.values():
            sp_.set_color("#333")
    fig.patch.set_facecolor("#121212")
    a1.plot(idx.index, idx.values, color="#F5F5F5", lw=1)
    a1.axhline(70, color="#00E676", lw=.6, ls="--")
    a1.axhline(40, color="#FF5252", lw=.6, ls="--")
    a1.set_ylabel("Finance index", color="#A0A0A0")
    p = px[asset].reindex(z.index)
    a2.plot(p.index, p.values, color="#F5F5F5", lw=1)
    a2.set_yscale("log")
    a2.set_ylabel(f"{asset} (log, total return)", color="#A0A0A0")
    for ax in (a1, a2):
        start = z.index[0]
        for i in range(1, len(z) + 1):
            if i == len(z) or z.iloc[i] != z.iloc[i - 1]:
                end = z.index[i - 1]
                ax.axvspan(start, end + pd.offsets.MonthEnd(1), color=colors[z.iloc[i - 1]], alpha=.12, lw=0)
                if i < len(z):
                    start = z.index[i]
    if sp:
        plain, rule = sp["_series"]
        a3.plot(plain.index, plain.values, color="#A0A0A0", lw=1.2, label="Plain monthly DCA")
        a3.plot(rule.index, rule.values, color="#00E676", lw=1.2, label="Following the rules")
        a3.set_ylabel("Portfolio value (1/month)", color="#A0A0A0")
        a3.legend(facecolor="#1E1E1E", labelcolor="#F5F5F5", edgecolor="#333")
    fig.tight_layout()
    fig.savefig(OUT / "finance_backtest.png", dpi=110, facecolor=fig.get_facecolor())


if __name__ == "__main__":
    main()
