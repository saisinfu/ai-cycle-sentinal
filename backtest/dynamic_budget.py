"""Does 'invest less near the high, more after a fall' beat plain monthly DCA?

Every month 1 unit of new money arrives. Plain DCA invests it. A dynamic rule invests
base x multiplier, where the multiplier depends on how far the asset sits below its
52-week high (or its 200-day average); money not invested waits in a cash reserve that
earns the 3-month T-bill rate and is spent when the multiplier is above 1. Total money
contributed is identical, so the comparison is fair: terminal value and money-weighted
return (IRR) of the same contributions.

Run: python backtest/dynamic_budget.py [--synthetic]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finance_backtest as fb  # noqa: E402

ASSETS = ["SPY", "QQQ", "SMH", "XLF", "XLV", "XLP", "JPM", "AVGO", "KLAC", "ETN", "GLD"]

# (drawdown threshold in %, multiplier): first row whose threshold the drawdown is above wins
RULES = {
    "gentle": {"by": "dd", "steps": [(-5, 0.8), (-10, 1.0), (-20, 1.5), (-30, 2.0), (-999, 3.0)], "cap": None,
               "th": "ใกล้จุดสูงสุดลง 0.8 เท่า · ย่อ 10–20% ลง 1.5 เท่า · ย่อ 20–30% ลง 2 เท่า · ย่อเกิน 30% ลง 3 เท่า"},
    "gentle_cap6": {"by": "dd", "steps": [(-5, 0.8), (-10, 1.0), (-20, 1.5), (-30, 2.0), (-999, 3.0)], "cap": 6,
                    "th": "แบบ gentle แต่เงินสำรองเกิน 6 เดือนของงบฐานให้ลงทุนส่วนเกินทันที"},
    "strong": {"by": "dd", "steps": [(-5, 0.6), (-10, 1.0), (-20, 2.0), (-30, 3.0), (-999, 4.0)], "cap": None,
               "th": "ใกล้จุดสูงสุดลง 0.6 เท่า · ย่อ 10–20% ลง 2 เท่า · ย่อ 20–30% ลง 3 เท่า · ย่อเกิน 30% ลง 4 เท่า"},
    "dip_only": {"by": "dd", "steps": [(-10, 0.9), (-20, 1.5), (-999, 2.5)], "cap": 6,
                 "th": "ปกติลง 0.9 เท่า (กันไว้ 10%) · ย่อ 10–20% ลง 1.5 เท่า · ย่อเกิน 20% ลง 2.5 เท่า · สำรองไม่เกิน 6 เดือน"},
    "ma200": {"by": "ma", "steps": [(10, 0.7), (0, 1.0), (-10, 1.5), (-999, 2.5)], "cap": None,
              "th": "เทียบเส้นเฉลี่ย 200 วัน: สูงกว่า 10% ลง 0.7 เท่า · ต่ำกว่า 0–10% ลง 1.5 เท่า · ต่ำกว่าเกิน 10% ลง 2.5 เท่า"},
}


def multiplier(x: float, steps) -> float:
    for th, m in steps:
        if x > th:
            return m
    return steps[-1][1]


def run(price_m: pd.Series, sig: pd.Series, rf: pd.Series, rule: dict | None) -> dict:
    """price_m: month-end total-return price; sig: signal known at that month-end."""
    rets = (price_m.shift(-1) / price_m - 1).dropna()
    H = C = 0.0
    vals, reserve_share = [], []
    for d in rets.index:
        C += 1.0
        if rule is None:
            spend = C
        else:
            m = multiplier(float(sig.loc[d]), rule["steps"])
            spend = min(C, m)
            if rule["cap"] is not None and C - spend > rule["cap"]:
                spend = C - rule["cap"]
        H += spend
        C -= spend
        H *= 1 + rets.loc[d]
        C *= 1 + (rf.get(d, 0.0) or 0.0) / 1200
        vals.append(H + C)
        reserve_share.append(C / (H + C) if H + C > 0 else 0)
    v = pd.Series(vals, rets.index)
    n = len(rets)
    return {"terminal": float(v.iloc[-1]), "irr": fb.irr_monthly(n, float(v.iloc[-1])), "months": n,
            "max_dd": float((v / v.cummax() - 1).min()), "avg_reserve_share": float(np.mean(reserve_share)),
            "end_reserve": float(C), "from": str(rets.index[0].date()), "to": str(rets.index[-1].date())}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true")
    args = ap.parse_args()

    if args.synthetic:
        rng = np.random.default_rng(3)
        idx = pd.date_range("1999-01-01", "2026-10-30", freq="B")
        daily = {a: pd.Series(np.exp(np.cumsum(rng.normal(0.0004, 0.015, len(idx)))) * 50, idx) for a in ASSETS}
        rf = pd.Series(2.0, pd.date_range("1999-01-31", "2026-10-31", freq="ME"))
    else:
        daily = fb.prices_yahoo(ASSETS + ["^IRX"])
        irx = daily.pop("^IRX", None)
        rf = irx.resample("ME").last() if irx is not None else pd.Series(dtype=float)

    out = {"generated": pd.Timestamp.utcnow().isoformat(), "synthetic": args.synthetic, "assets": {}, "rules": {k: v["th"] for k, v in RULES.items()}}
    for a, s in daily.items():
        s = s.dropna()
        hi = s.rolling(252, min_periods=120).max()
        dd = (s / hi - 1) * 100
        ma = (s / s.rolling(200, min_periods=150).mean() - 1) * 100
        pm = s.resample("ME").last()
        ddm, mam = dd.resample("ME").last(), ma.resample("ME").last()
        ok = ddm.notna() & mam.notna()
        pm, ddm, mam = pm[ok], ddm[ok], mam[ok]
        if len(pm) < 60:
            continue
        rfa = rf.reindex(pm.index).ffill().fillna(0)
        base = run(pm, ddm, rfa, None)
        row = {"from": base["from"], "to": base["to"], "months": base["months"], "plain_irr": round(base["irr"] * 100, 2),
               "plain_dd": round(base["max_dd"] * 100, 1), "rules": {}}
        for name, rule in RULES.items():
            res = run(pm, ddm if rule["by"] == "dd" else mam, rfa, rule)
            row["rules"][name] = {"irr_diff_pp": round((res["irr"] - base["irr"]) * 100, 2),
                                  "terminal_ratio": round(res["terminal"] / base["terminal"], 3),
                                  "avg_reserve_share": round(res["avg_reserve_share"] * 100, 1),
                                  "max_dd": round(res["max_dd"] * 100, 1)}
        out["assets"][a] = row
        print(a, row["from"], {k: v["irr_diff_pp"] for k, v in row["rules"].items()}, flush=True)

    summary = {}
    for name in RULES:
        diffs = [r["rules"][name]["irr_diff_pp"] for r in out["assets"].values()]
        if diffs:
            summary[name] = {"median_irr_diff_pp": round(float(np.median(diffs)), 2), "min": round(min(diffs), 2),
                             "max": round(max(diffs), 2), "share_beating_plain": round(float(np.mean([d > 0 for d in diffs])), 2)}
    out["summary"] = summary
    fb.OUT.mkdir(parents=True, exist_ok=True)
    (fb.OUT / "dynamic_budget.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(json.dumps(summary, indent=1))
    if not args.synthetic:
        add_to_app_summary(out)


def add_to_app_summary(res: dict) -> None:
    target = fb.ROOT / "data" / "backtest.json"
    if not target.exists():
        return
    d = json.loads(target.read_text())
    rows = []
    for a, r in res["assets"].items():
        rows.append({"label": a, "from": r["from"][:7], "plain_irr": r["plain_irr"],
                     **{k: v["irr_diff_pp"] for k, v in r["rules"].items()}})
    d["dynamic_budget"] = {"generated": res["generated"], "rules": res["rules"], "summary": res["summary"], "assets": rows}
    target.write_text(json.dumps(d, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
