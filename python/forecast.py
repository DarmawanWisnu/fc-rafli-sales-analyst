"""
forecast.py — Retail Sales & Demand Forecasting (Production Script)
====================================================================
Proyek  : FC Raffa Rafli — Retail Analytics Portfolio
Input   : data/processed/vw_daily_kpi.csv
Output  : data/processed/forecast_daily.csv
          data/processed/forecast_model_evaluation.csv
Horizon : 28 hari (2026-02-01 → 2026-02-28)
Models  : Mean, Naive, Seasonal Naive 7D, MA7, Holt-Winters, SARIMA
Metric  : WAPE (Weighted Absolute Percentage Error) — dipilih karena
          dataset memiliki zero-sales days sehingga MAPE tidak valid.
====================================================================
"""

import sys
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

import warnings
warnings.filterwarnings('ignore')

import os
import numpy as np
import pandas as pd
from statsmodels.tsa.holtwinters import ExponentialSmoothing
from statsmodels.tsa.statespace.sarimax import SARIMAX

# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR  = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
DATA_DIR     = os.path.join(PROJECT_DIR, 'data', 'processed')

INPUT_FILE      = os.path.join(DATA_DIR, 'vw_daily_kpi.csv')
OUTPUT_FORECAST = os.path.join(DATA_DIR, 'forecast_daily.csv')
OUTPUT_EVAL     = os.path.join(DATA_DIR, 'forecast_model_evaluation.csv')

HOLDOUT_DAYS    = 28          # Validation: 28 hari terakhir
FORECAST_DAYS   = 28          # Prediksi: 28 hari Feb 2026
SEASONAL_PERIOD = 7           # Musiman mingguan
TARGETS         = ['order_count', 'revenue']


# ═══════════════════════════════════════════════════════════════════
# DATA LOADING
# ═══════════════════════════════════════════════════════════════════
def load_data():
    """
    Load vw_daily_kpi.csv, reindex ke date range lengkap,
    isi zero-sales days dengan 0 (bukan hapus/NULL).
    """
    df = pd.read_csv(INPUT_FILE, parse_dates=['date'])
    df = df.sort_values('date').reset_index(drop=True)

    # Pastikan setiap tanggal ada (reindex complete date range)
    full_range = pd.date_range(df['date'].min(), df['date'].max(), freq='D')
    df = (df.set_index('date')
            .reindex(full_range)
            .rename_axis('date')
            .reset_index())

    # Fill zero-sales days
    df['order_count'] = df['order_count'].fillna(0).astype(int)
    df['revenue']     = df['revenue'].fillna(0.0).astype(float)

    n_days  = len(df)
    n_zeros = (df['order_count'] == 0).sum()
    date_min = df['date'].min().date()
    date_max = df['date'].max().date()

    print(f"✅ Data loaded: {n_days} hari ({date_min} → {date_max})")
    print(f"   Zero-sales days: {n_zeros}")
    return df


# ═══════════════════════════════════════════════════════════════════
# TRAIN / TEST SPLIT (HOLDOUT — BUKAN RANDOM!)
# ═══════════════════════════════════════════════════════════════════
def split_holdout(df, holdout_days=HOLDOUT_DAYS):
    """
    Time-series TIDAK BOLEH di-split random.
    Holdout: train = awal, test = N hari terakhir.
    """
    cutoff = len(df) - holdout_days
    train = df.iloc[:cutoff].copy()
    test  = df.iloc[cutoff:].copy()
    print(f"✅ Holdout split:")
    print(f"   Train: {len(train)} hari ({train['date'].min().date()} → {train['date'].max().date()})")
    print(f"   Test:  {len(test)} hari ({test['date'].min().date()} → {test['date'].max().date()})")
    return train, test


# ═══════════════════════════════════════════════════════════════════
# EVALUATION METRICS
# ═══════════════════════════════════════════════════════════════════
def calc_mae(actual, predicted):
    """Mean Absolute Error."""
    return np.mean(np.abs(actual - predicted))

def calc_rmse(actual, predicted):
    """Root Mean Squared Error."""
    return np.sqrt(np.mean((actual - predicted) ** 2))

def calc_wape(actual, predicted):
    """
    Weighted Absolute Percentage Error.
    Lebih baik dari MAPE karena tidak error saat actual = 0.
    WAPE = Σ|actual - predicted| / Σ|actual|
    """
    denom = np.sum(np.abs(actual))
    if denom == 0:
        return np.inf
    return np.sum(np.abs(actual - predicted)) / denom


# ═══════════════════════════════════════════════════════════════════
# BASELINE MODELS
# ═══════════════════════════════════════════════════════════════════
def predict_mean_baseline(train_vals, n):
    """Prediksi = rata-rata historis. Model paling sederhana."""
    return np.full(n, train_vals.mean())

def predict_naive(train_vals, n):
    """Prediksi = nilai terakhir diulang."""
    return np.full(n, train_vals[-1])

def predict_seasonal_naive(train_vals, n, period=SEASONAL_PERIOD):
    """Prediksi = nilai minggu terakhir diulang secara siklik."""
    last_season = train_vals[-period:]
    reps = int(np.ceil(n / period))
    return np.tile(last_season, reps)[:n]

def predict_ma7(train_vals, n):
    """Prediksi = rata-rata 7 hari terakhir."""
    return np.full(n, train_vals[-7:].mean())


# ═══════════════════════════════════════════════════════════════════
# STATISTICAL MODELS
# ═══════════════════════════════════════════════════════════════════
def predict_holt_winters(train_vals, n, period=SEASONAL_PERIOD):
    """
    Exponential Smoothing / Holt-Winters.
    Additive trend + additive seasonality (period=7).
    Cocok untuk data dengan pola musiman mingguan.
    """
    idx = pd.date_range('2000-01-01', periods=len(train_vals), freq='D')
    series = pd.Series(train_vals, index=idx)
    try:
        model = ExponentialSmoothing(
            series,
            trend='add',
            seasonal='add',
            seasonal_periods=period,
            initialization_method='estimated'
        ).fit(optimized=True)
        pred = model.forecast(n).values
        return np.maximum(pred, 0), model
    except Exception as e:
        print(f"   ⚠️ Holt-Winters error: {e}")
        return None, None


def predict_sarima(train_vals, n, period=SEASONAL_PERIOD):
    """
    SARIMA (Seasonal ARIMA) — Model time-series utama.
    Grid search parameter (p,d,q)(P,D,Q,7) berdasarkan AIC terbaik.
    """
    idx = pd.date_range('2000-01-01', periods=len(train_vals), freq='D')
    series = pd.Series(train_vals, index=idx)

    best_aic   = np.inf
    best_model = None
    best_label = None

    # Grid search parameter — dibatasi agar tidak terlalu lambat
    orders = [(1,1,1), (0,1,1), (1,0,1), (1,1,0), (0,1,0)]
    seasonal_orders = [(1,1,1,period), (0,1,1,period), (1,0,1,period)]

    for order in orders:
        for s_order in seasonal_orders:
            try:
                m = SARIMAX(
                    series,
                    order=order,
                    seasonal_order=s_order,
                    enforce_stationarity=False,
                    enforce_invertibility=False
                ).fit(disp=False, maxiter=200)
                if m.aic < best_aic:
                    best_aic   = m.aic
                    best_model = m
                    best_label = f"({order[0]},{order[1]},{order[2]})({s_order[0]},{s_order[1]},{s_order[2]},{period})"
            except:
                pass

    if best_model is not None:
        fc = best_model.get_forecast(n)
        pred = np.maximum(fc.predicted_mean.values, 0)
        ci   = fc.conf_int(alpha=0.05)
        print(f"   SARIMA best: {best_label}, AIC={best_aic:.0f}")
        return pred, best_model, ci
    else:
        print("   ⚠️ SARIMA: tidak ada model valid")
        return None, None, None


# ═══════════════════════════════════════════════════════════════════
# MODEL EVALUATION — COMPARE ALL 6 MODELS
# ═══════════════════════════════════════════════════════════════════
def evaluate_all_models(train, test):
    """
    Evaluasi semua 6 model pada holdout set untuk kedua target.
    Return DataFrame dengan kolom sesuai spesifikasi Master Plan §28.
    """
    val_period = f"{test['date'].min().date()} to {test['date'].max().date()}"
    results = []

    for target in TARGETS:
        tr = train[target].values.astype(float)
        te = test[target].values.astype(float)
        n  = len(te)

        print(f"\n{'═'*55}")
        print(f"  Target: {target}")
        print(f"{'═'*55}")

        # ── Baselines ──
        predictions = {}
        predictions['Mean Baseline']       = predict_mean_baseline(tr, n)
        predictions['Naive Last-Value']    = predict_naive(tr, n)
        predictions['Seasonal Naive 7D']   = predict_seasonal_naive(tr, n)
        predictions['7-Day Moving Average'] = predict_ma7(tr, n)

        # ── Holt-Winters ──
        hw_pred, _ = predict_holt_winters(tr, n)
        if hw_pred is not None:
            predictions['Holt-Winters'] = hw_pred

        # ── SARIMA ──
        sarima_pred, _, _ = predict_sarima(tr, n)
        if sarima_pred is not None:
            predictions['SARIMA'] = sarima_pred

        # ── Evaluate Each ──
        for model_name, pred in predictions.items():
            pred = np.maximum(pred, 0)
            mae  = calc_mae(te, pred)
            rmse = calc_rmse(te, pred)
            wape = calc_wape(te, pred)
            results.append({
                'target':           target,
                'model':            model_name,
                'mae':              round(mae, 2),
                'rmse':             round(rmse, 2),
                'wape_or_smape':    round(wape * 100, 2),  # percentage
                'validation_period': val_period,
                'selected_flag':    False
            })
            print(f"   {model_name:25s}  MAE={mae:>12,.2f}  RMSE={rmse:>12,.2f}  WAPE={wape*100:>6.2f}%")

    eval_df = pd.DataFrame(results)

    # ── Select Best Model (Lowest WAPE) per Target ──
    for target in TARGETS:
        mask = eval_df['target'] == target
        best_idx = eval_df.loc[mask, 'wape_or_smape'].idxmin()
        eval_df.loc[best_idx, 'selected_flag'] = True
        name = eval_df.loc[best_idx, 'model']
        wape = eval_df.loc[best_idx, 'wape_or_smape']
        print(f"\n   🏆 Best for {target}: {name} (WAPE={wape}%)")

    return eval_df


# ═══════════════════════════════════════════════════════════════════
# GENERATE FINAL 28-DAY FORECAST
# ═══════════════════════════════════════════════════════════════════
def generate_forecast(df, eval_df):
    """
    Re-fit model terpilih pada FULL dataset (153 hari),
    lalu forecast 28 hari ke depan (Feb 2026) + confidence interval.
    """
    dates = pd.date_range('2026-02-01', periods=FORECAST_DAYS, freq='D')
    out = pd.DataFrame({
        'forecast_date':      dates,
        'forecast_horizon_day': range(1, FORECAST_DAYS + 1)
    })

    for target in TARGETS:
        best = eval_df[(eval_df['target'] == target) & (eval_df['selected_flag'])].iloc[0]
        model_name = best['model']
        vals = df[target].values.astype(float)
        n = FORECAST_DAYS

        print(f"   {target} → re-fit {model_name} pada full {len(vals)} hari...")

        # ── Dispatch ke model yang dipilih ──
        if model_name == 'Mean Baseline':
            pred = predict_mean_baseline(vals, n)
            std = np.std(vals)
            lower, upper = pred - 1.96 * std, pred + 1.96 * std

        elif model_name == 'Naive Last-Value':
            pred = predict_naive(vals, n)
            std = np.std(np.diff(vals))
            lower, upper = pred - 1.96 * std, pred + 1.96 * std

        elif model_name == 'Seasonal Naive 7D':
            pred = predict_seasonal_naive(vals, n)
            resid = [vals[i] - vals[i - 7] for i in range(7, len(vals))]
            std = np.std(resid)
            lower, upper = pred - 1.96 * std, pred + 1.96 * std

        elif model_name == '7-Day Moving Average':
            pred = predict_ma7(vals, n)
            std = np.std(vals[-7:])
            lower, upper = pred - 1.96 * std, pred + 1.96 * std

        elif model_name == 'Holt-Winters':
            pred, model = predict_holt_winters(vals, n)
            std = np.std(model.resid)
            lower, upper = pred - 1.96 * std, pred + 1.96 * std

        elif model_name == 'SARIMA':
            pred, model, ci = predict_sarima(vals, n)
            if ci is not None:
                lower = ci.iloc[:, 0].values
                upper = ci.iloc[:, 1].values
            else:
                std = np.std(vals)
                lower, upper = pred - 1.96 * std, pred + 1.96 * std

        # ── Clip negative values ──
        pred  = np.maximum(pred, 0)
        lower = np.maximum(lower, 0)
        upper = np.maximum(upper, 0)

        # ── Assign to output columns ──
        if target == 'order_count':
            out['predicted_order_count'] = np.round(pred).astype(int)
            out['order_lower_bound']     = np.maximum(np.floor(lower), 0).astype(int)
            out['order_upper_bound']     = np.ceil(upper).astype(int)
            out['order_model_name']      = model_name
        else:
            out['predicted_revenue']     = np.round(pred, 2)
            out['revenue_lower_bound']   = np.round(np.maximum(lower, 0), 2)
            out['revenue_upper_bound']   = np.round(upper, 2)
            out['revenue_model_name']    = model_name

    # ── Reorder columns sesuai spec Master Plan §28 ──
    cols = [
        'forecast_date',
        'predicted_order_count', 'predicted_revenue',
        'order_lower_bound',    'order_upper_bound',
        'revenue_lower_bound',  'revenue_upper_bound',
        'order_model_name',     'revenue_model_name',
        'forecast_horizon_day'
    ]
    return out[cols]


# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════
def main():
    print("=" * 60)
    print("  RETAIL SALES & DEMAND FORECASTING")
    print("  FC Raffa Rafli — Retail Analytics Portfolio")
    print("=" * 60)

    # 1. Load data
    df = load_data()

    # 2. Train/test split (holdout)
    train, test = split_holdout(df)

    # 3. Evaluate all 6 models
    eval_df = evaluate_all_models(train, test)

    # 4. Generate 28-day forecast
    print("\n" + "=" * 60)
    print("  GENERATING 28-DAY FORECAST (February 2026)")
    print("=" * 60)
    forecast_df = generate_forecast(df, eval_df)

    # 5. Export CSV
    forecast_df.to_csv(OUTPUT_FORECAST, index=False)
    eval_df.to_csv(OUTPUT_EVAL, index=False)
    print(f"\n✅ Exported: {OUTPUT_FORECAST}")
    print(f"✅ Exported: {OUTPUT_EVAL}")

    # 6. Summary
    print(f"\n{'═'*55}")
    print(f"  📊 FORECAST SUMMARY — February 2026")
    print(f"{'═'*55}")
    print(f"   Total Predicted Orders:  {forecast_df['predicted_order_count'].sum()}")
    print(f"   Total Predicted Revenue: Rp{forecast_df['predicted_revenue'].sum():,.0f}")
    print(f"   Daily Avg Orders:        {forecast_df['predicted_order_count'].mean():.1f}")
    print(f"   Daily Avg Revenue:       Rp{forecast_df['predicted_revenue'].mean():,.0f}")

    for target in TARGETS:
        row = eval_df[(eval_df['target'] == target) & eval_df['selected_flag']].iloc[0]
        print(f"   {target:15s} model: {row['model']} (WAPE={row['wape_or_smape']}%)")

    print("\n🎉 Forecasting selesai!")


if __name__ == '__main__':
    main()
