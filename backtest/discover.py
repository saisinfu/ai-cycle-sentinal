"""Find DBnomics series codes for the finance signals (FRED is blocked from CI)."""
import json, urllib.request, urllib.parse
def get(u):
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=40) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e)}
B = "https://api.db.nomics.world/v22"
out = []
p = get(f"{B}/providers")
out.append("providers with FRED/ICE/MOODY: " + str([x["code"] for x in p.get("providers", {}).get("docs", []) if any(k in x["code"].upper() for k in ("FRED", "ICE", "MOOD", "FED", "BIS"))]))
d = get(f"{B}/providers/FED")
out.append("FED datasets: " + json.dumps(d.get("category_tree", d)[:40] if isinstance(d.get("category_tree"), list) else str(d)[:1500]))
for ds, q in [("H15", "10-year"), ("H15", "2-year"), ("H15", "federal funds effective"), ("H15", "3-month treasury bill"), ("H15", "Baa"),
              ("H8", "loans and leases in bank credit all commercial banks seasonally adjusted"), ("CHGDEL", "credit card delinquency"),
              ("CHGDEL", "delinquency rate credit cards seasonally adjusted")]:
    r = get(f"{B}/series/FED/{ds}?q={urllib.parse.quote(q)}&observations=0&limit=12")
    docs = r.get("series", {}).get("docs", []) if "series" in r else []
    out.append(f"--- {ds} q='{q}' found {r.get('series', {}).get('num_found', r.get('error'))}")
    for x in docs:
        out.append(f"  {x.get('series_code')} | {x.get('series_name')[:150]} | {x.get('@frequency')}")
for q in ["BAMLH0A0HYM2", "high yield option-adjusted spread", "Moody's Baa corporate bond yield"]:
    r = get(f"{B}/search?q={urllib.parse.quote(q)}&limit=8")
    out.append(f"--- search '{q}': " + str([(x.get('provider_code'), x.get('code'), x.get('name', '')[:80], x.get('nb_matching_series')) for x in r.get('results', {}).get('docs', [])]))
open("backtest/results/discover.log", "w").write("\n".join(out))
print("\n".join(out))
