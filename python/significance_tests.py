"""
Significance checks for the Olist retention analysis.

Reads the CSVs you exported from pgAdmin (delivery, review score, category
results from 05_return_drivers.sql) and tests whether the differences in
90-day return rate are bigger than random noise.

Usage (run from the repo root, with your exported CSVs inside ./results/):
    pip install pandas scipy
    python python/significance_tests.py

Outputs are printed and also saved to ./results/python_outputs/.
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

RESULTS = Path("results")
OUT = RESULTS / "python_outputs"
OUT.mkdir(parents=True, exist_ok=True)

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 20)


# ---------------------------------------------------------------- helpers
def load(required):
    """Find the exported CSV that has the required columns (filename doesn't matter)."""
    for path in sorted(RESULTS.glob("*.csv")):
        try:
            cols = set(pd.read_csv(path, nrows=0).columns.str.strip().str.lower())
        except Exception:
            continue
        if set(required) <= cols:
            df = pd.read_csv(path)
            df.columns = df.columns.str.strip().str.lower()
            print(f"[loaded {path.name}]")
            return df
    raise FileNotFoundError(
        f"No CSV in {RESULTS.resolve()} has the columns {sorted(required)}"
    )


def wilson(k, n):
    """95% Wilson confidence interval for a rate, returned in percent."""
    ci = stats.binomtest(int(k), int(n)).proportion_ci(
        confidence_level=0.95, method="wilson"
    )
    return ci.low * 100, ci.high * 100


def compare(k1, n1, k2, n2):
    """Rate1 - rate2 in percentage points, 95% CI, and Fisher exact p-value."""
    p1, p2 = k1 / n1, k2 / n2
    diff = p1 - p2
    se = np.sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    _, p = stats.fisher_exact([[k1, n1 - k1], [k2, n2 - k2]])
    return diff * 100, (diff - 1.96 * se) * 100, (diff + 1.96 * se) * 100, p


def chi_square(df):
    """Do return rates differ across ALL groups? (chi-square test of homogeneity)"""
    table = np.array([df["returned"], df["customers"] - df["returned"]])
    chi2, p, dof, _ = stats.chi2_contingency(table)
    return chi2, dof, p


def cochran_armitage(x, n, r):
    """Trend test: does the return rate move steadily with an ordered score?"""
    x, n, r = (np.asarray(a, dtype=float) for a in (x, n, r))
    total, returned = n.sum(), r.sum()
    pbar = returned / total
    t = np.sum(x * (r - n * pbar))
    var = pbar * (1 - pbar) * (np.sum(n * x**2) - np.sum(n * x) ** 2 / total)
    z = t / np.sqrt(var)
    return z, 2 * stats.norm.sf(abs(z))


def bh_adjust(p):
    """Benjamini-Hochberg adjustment for multiple comparisons."""
    p = np.asarray(p, dtype=float)
    n = len(p)
    order = np.argsort(p)
    ranked = p[order] * n / (np.arange(n) + 1)
    adj = np.minimum.accumulate(ranked[::-1])[::-1]
    out = np.empty(n)
    out[order] = np.minimum(adj, 1)
    return out


def show_p(p):
    return "<0.0001" if p < 0.0001 else f"{p:.4f}"


# ---------------------------------------------------- 1. delivery lateness
print("\n=== 1. DELIVERY: on time vs late first delivery ===")
d = load({"delivery", "customers", "returned"})
is_on_time = d["delivery"].str.contains("on time", case=False)
k_on, n_on = d.loc[is_on_time, "returned"].sum(), d.loc[is_on_time, "customers"].sum()
k_late, n_late = d.loc[~is_on_time, "returned"].sum(), d.loc[~is_on_time, "customers"].sum()

print(f"On time or early: {k_on}/{n_on} = {100 * k_on / n_on:.2f}%")
print(f"Late (any):       {k_late}/{n_late} = {100 * k_late / n_late:.2f}%")
diff, lo, hi, p = compare(k_on, n_on, k_late, n_late)
print(f"Difference (on time - late): {diff:.2f} pts, 95% CI [{lo:.2f}, {hi:.2f}], p = {show_p(p)}")
chi2, dof, p_all = chi_square(d)
print(f"Chi-square across all 4 delivery buckets: chi2 = {chi2:.2f}, dof = {dof}, p = {show_p(p_all)}")
extra = n_late * (k_on / n_on - k_late / n_late)
print(f"If late customers returned like on-time ones: about {extra:.0f} extra returners")


# ------------------------------------------------------- 2. review score
print("\n=== 2. REVIEW SCORE of the first order ===")
r = load({"review_score", "customers", "returned"}).dropna(subset=["review_score"])
r["review_score"] = r["review_score"].astype(int)
r = r.sort_values("review_score")
r["return_rate_pct"] = 100 * r["returned"] / r["customers"]
r[["ci_low", "ci_high"]] = [wilson(k, n) for k, n in zip(r["returned"], r["customers"])]
print(r[["review_score", "customers", "returned", "return_rate_pct", "ci_low", "ci_high"]].round(2).to_string(index=False))

chi2, dof, p_all = chi_square(r)
print(f"\nChi-square across scores: chi2 = {chi2:.2f}, dof = {dof}, p = {show_p(p_all)}")
z, p_trend = cochran_armitage(r["review_score"], r["customers"], r["returned"])
print(f"Trend test (rate rises with score): z = {z:.2f}, p = {show_p(p_trend)}")

low = r[r["review_score"] <= 2]
high = r[r["review_score"] == 5]
diff, lo, hi, p = compare(
    high["returned"].sum(), high["customers"].sum(), low["returned"].sum(), low["customers"].sum()
)
print(f"5-star vs 1-2 star: {diff:.2f} pts, 95% CI [{lo:.2f}, {hi:.2f}], p = {show_p(p)}")


# -------------------------------------------------------------- 3. category
print("\n=== 3. CATEGORY of the first order ===")
c = load({"category", "customers", "returned"}).copy()
chi2, dof, p_all = chi_square(c)
print(f"Chi-square across {len(c)} categories: chi2 = {chi2:.1f}, dof = {dof}, p = {show_p(p_all)}")

total_n, total_k = c["customers"].sum(), c["returned"].sum()
rows = []
for _, row in c.iterrows():
    k, n = int(row["returned"]), int(row["customers"])
    k_rest, n_rest = total_k - k, total_n - n
    ci_lo, ci_hi = wilson(k, n)
    _, _, _, p = compare(k, n, k_rest, n_rest)
    rows.append(
        {
            "category": row["category"],
            "customers": n,
            "returned": k,
            "return_rate_pct": 100 * k / n,
            "ci_low": ci_lo,
            "ci_high": ci_hi,
            "rest_rate_pct": 100 * k_rest / n_rest,
            "p_value": p,
        }
    )
cat = pd.DataFrame(rows)
cat["p_adj_bh"] = bh_adjust(cat["p_value"])


def verdict(row):
    if row["p_adj_bh"] >= 0.05:
        return "no clear difference"
    return "higher than rest" if row["return_rate_pct"] > row["rest_rate_pct"] else "lower than rest"


cat["verdict"] = cat.apply(verdict, axis=1)
cat = cat.sort_values("return_rate_pct", ascending=False)
print("\nEach category vs all other categories (p adjusted for 22 comparisons, BH):")
print(cat.round(4).to_string(index=False))

cat.to_csv(OUT / "category_significance.csv", index=False)
r.to_csv(OUT / "review_score_significance.csv", index=False)
print(f"\nSaved tables to {OUT.resolve()}")
print("\nReminder: these tests show differences are unlikely to be noise, "
      "not that the factor CAUSES returns.")
