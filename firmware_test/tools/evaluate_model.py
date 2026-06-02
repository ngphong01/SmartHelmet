"""
=============================================================================
 evaluate_model.py — Đánh giá toàn diện mô hình Logistic Regression
 cho phát hiện va chạm mũ bảo hiểm thông minh
=============================================================================
Chạy: python evaluate_model.py

Đầu ra:
  - Confusion Matrix (heatmap)
  - Precision, Recall, F1-score
  - ROC Curve + AUC
  - Precision-Recall Curve
  - So sánh với 2 baseline (peak_g threshold, Random Forest)
  - Error Analysis: false positive / false negative cases
=============================================================================
"""
import numpy as np
import matplotlib
matplotlib.use('Agg')  # non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns
import warnings
warnings.filterwarnings('ignore', category=FutureWarning)
warnings.filterwarnings('ignore', category=UserWarning, module='sklearn')
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_val_score
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    confusion_matrix, classification_report,
    roc_curve, auc, precision_recall_curve,
    f1_score, precision_score, recall_score
)
import os
import sys

# =========================================================================
# CONFIG
# =========================================================================
OUTPUT_DIR = "docs/ml_evaluation"
RANDOM_SEED = 42
TEST_SIZE = 0.15
VAL_SIZE = 0.15  # from remaining after test split

os.makedirs(OUTPUT_DIR, exist_ok=True)

# =========================================================================
# 1. TẠO DỮ LIỆU TỪ IMPACT_DATA.CPP
# =========================================================================
def load_impact_data():
    """
    Đọc dữ liệu từ impact_data.cpp (đã được generate bằng Python).
    Vì không import trực tiếp .cpp, ta dùng script tools/generate_impact_data.py
    để tạo dữ liệu, hoặc import trực tiếp từ file đã generate.
    
    Fallback: tự generate synthetic data mô phỏng đúng cấu trúc.
    """
    print("[1/7] Dang tao du lieu...")

    np.random.seed(RANDOM_SEED)

    # --- IMPACT samples (~2445 samples, 2.4s @ 1000Hz) ---
    n_impact = 2445

    # Mô phỏng impact: spike gia tốc lớn rồi giảm dần
    t_impact = np.linspace(0, 1.0, 100)  # 100ms spike
    spike = 3.5 * np.exp(-t_impact / 0.02) * np.sin(t_impact * 100)

    impact_ax = np.concatenate([
        np.random.normal(0, 0.15, 200),  # baseline
        spike * 8192,                     # spike (raw LSB)
        np.random.normal(0, 0.3, n_impact - 300)  # after
    ])[:n_impact]
    impact_ay = np.concatenate([
        np.random.normal(0, 0.15, 200),
        spike * 0.4 * 8192,
        np.random.normal(0, 0.3, n_impact - 300)
    ])[:n_impact]
    impact_az = np.concatenate([
        np.random.normal(1.0, 0.1, 200),
        spike * 0.5 * 8192,
        np.random.normal(1.0, 0.2, n_impact - 300)
    ])[:n_impact]

    # --- NON-IMPACT samples (normal riding, ~5000 samples) ---
    n_normal = 5000
    normal_ax = np.random.normal(0, 0.12, n_normal)
    normal_ay = np.random.normal(0, 0.12, n_normal)
    normal_az = np.random.normal(1.0, 0.08, n_normal)

    # Thêm một số rung động (ổ gà, phanh gấp)
    n_bump = 500
    bump_t = np.linspace(0, 0.3, 30)
    bump = 1.2 * np.exp(-bump_t / 0.05)
    bump_idx = np.random.choice(n_normal, n_bump, replace=False)
    for idx in bump_idx:
        if idx + 30 < n_normal:
            normal_ax[idx:idx+30] += bump * np.random.uniform(0.5, 1.5)
            normal_ay[idx:idx+30] += bump * np.random.uniform(-0.5, 0.5)

    # --- Tính features ---
    def compute_features(ax, ay, az, win_size=512, step=256):
        """Tính 8 features: 5 FFT bands + 3 accel (giống firmware)"""
        n = len(ax)
        n_windows = (n - win_size) // step + 1
        if n_windows <= 0:
            return np.zeros((0, 8))

        features = np.zeros((n_windows, 8))
        for i in range(n_windows):
            start = i * step
            end = start + win_size

            # Gia tốc tổng hợp
            gmag = np.sqrt(ax[start:end]**2 + ay[start:end]**2 + az[start:end]**2)

            # FFT 5 dải tần
            fft = np.abs(np.fft.rfft(gmag))
            n_fft = len(fft)
            # Chia thành 5 dải: DC-50Hz, 50-100, 100-200, 200-300, 300-500
            bands = [
                (0, int(n_fft * 50 / 500)),
                (int(n_fft * 50 / 500), int(n_fft * 100 / 500)),
                (int(n_fft * 100 / 500), int(n_fft * 200 / 500)),
                (int(n_fft * 200 / 500), int(n_fft * 300 / 500)),
                (int(n_fft * 300 / 500), int(n_fft * 500 / 500)),
            ]
            for j, (lo, hi) in enumerate(bands):
                lo = max(0, min(lo, n_fft-1))
                hi = max(lo+1, min(hi, n_fft))
                features[i, j] = np.mean(fft[lo:hi]) if hi > lo else 0

            # 3 accel cuối
            features[i, 5] = ax[end-1]
            features[i, 6] = ay[end-1]
            features[i, 7] = az[end-1]

        return features

    print("  Dang tinh features...")
    X_impact = compute_features(impact_ax, impact_ay, impact_az)
    X_normal = compute_features(normal_ax, normal_ay, normal_az)

    y_impact = np.ones(len(X_impact))
    y_normal = np.zeros(len(X_normal))

    X = np.vstack([X_impact, X_normal])
    y = np.hstack([y_impact, y_normal])

    print(f"  Tong: {len(X)} samples (impact={len(X_impact)}, normal={len(X_normal)})")
    print(f"  Ty le impact: {y.mean()*100:.1f}%")

    return X, y

# =========================================================================
# 2. TRAIN/TEST SPLIT
# =========================================================================
def split_data(X, y):
    print("\n[2/7] Chia du lieu train/val/test (70/15/15)...")
    
    X_temp, X_test, y_temp, y_test = train_test_split(
        X, y, test_size=TEST_SIZE, random_state=RANDOM_SEED, stratify=y
    )
    val_ratio = VAL_SIZE / (1 - TEST_SIZE)
    X_train, X_val, y_train, y_val = train_test_split(
        X_temp, y_temp, test_size=val_ratio, random_state=RANDOM_SEED, stratify=y_temp
    )

    print(f"  Train: {len(X_train)} ({y_train.mean()*100:.1f}% impact)")
    print(f"  Val:   {len(X_val)} ({y_val.mean()*100:.1f}% impact)")
    print(f"  Test:  {len(X_test)} ({y_test.mean()*100:.1f}% impact)")

    return X_train, X_val, X_test, y_train, y_val, y_test

# =========================================================================
# 3. TRAIN MODELS
# =========================================================================
def train_models(X_train, y_train, X_val, y_val):
    print("\n[3/7] Huan luyen cac mo hinh...")

    # --- Model chính: Logistic Regression ---
    lr = LogisticRegression(
        C=1.0, solver='liblinear',
        max_iter=1000, random_state=RANDOM_SEED
    )
    lr.fit(X_train, y_train)
    lr_train_acc = lr.score(X_train, y_train)
    lr_val_acc = lr.score(X_val, y_val)
    print(f"  Logistic Regression: train={lr_train_acc:.4f}, val={lr_val_acc:.4f}")

    # --- Baseline 1: Random Forest ---
    rf = RandomForestClassifier(
        n_estimators=100, max_depth=10,
        random_state=RANDOM_SEED, n_jobs=-1
    )
    rf.fit(X_train, y_train)
    rf_train_acc = rf.score(X_train, y_train)
    rf_val_acc = rf.score(X_val, y_val)
    print(f"  Random Forest:       train={rf_train_acc:.4f}, val={rf_val_acc:.4f}")

    # --- Baseline 2: Peak-G Threshold ---
    # Sử dụng feature[7] (az) hoặc peak từ window
    # Đây là threshold đơn giản nhất
    peak_thresholds = np.linspace(0.5, 5.0, 50)
    best_thresh = 0
    best_f1 = 0
    for thresh in peak_thresholds:
        preds = (X_val[:, 7] > thresh).astype(int)  # az > threshold
        f1 = f1_score(y_val, preds, zero_division=0)
        if f1 > best_f1:
            best_f1 = f1
            best_thresh = thresh
    print(f"  Peak-G Threshold:    best_thresh={best_thresh:.2f}g, val_f1={best_f1:.4f}")

    return lr, rf, best_thresh

# =========================================================================
# 4. EVALUATE ON TEST SET
# =========================================================================
def evaluate_on_test(lr, rf, best_thresh, X_test, y_test):
    print("\n[4/7] Danh gia tren tap test...")

    results = {}

    # --- Logistic Regression ---
    y_pred_lr = lr.predict(X_test)
    y_prob_lr = lr.predict_proba(X_test)[:, 1]
    results['lr'] = {
        'pred': y_pred_lr,
        'prob': y_prob_lr,
        'name': 'Logistic Regression'
    }

    # --- Random Forest ---
    y_pred_rf = rf.predict(X_test)
    y_prob_rf = rf.predict_proba(X_test)[:, 1]
    results['rf'] = {
        'pred': y_pred_rf,
        'prob': y_prob_rf,
        'name': 'Random Forest'
    }

    # --- Peak-G Threshold ---
    y_pred_peak = (X_test[:, 7] > best_thresh).astype(int)
    y_prob_peak = X_test[:, 7] / 5.0  # normalize to [0,1] roughly
    results['peak'] = {
        'pred': y_pred_peak,
        'prob': np.clip(y_prob_peak, 0, 1),
        'name': f'Peak-G > {best_thresh:.2f}g'
    }

    for key, res in results.items():
        print(f"\n  --- {res['name']} ---")
        print(classification_report(y_test, res['pred'], target_names=['Normal', 'Impact'], zero_division=0))

    return results

# =========================================================================
# 5. PLOT CONFUSION MATRIX
# =========================================================================
def plot_confusion_matrices(results, y_test):
    print("\n[5/7] Ve confusion matrix...")

    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    
    for ax, (key, res) in zip(axes, results.items()):
        cm = confusion_matrix(y_test, res['pred'])
        sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', ax=ax,
                    xticklabels=['Normal', 'Impact'],
                    yticklabels=['Normal', 'Impact'])
        ax.set_title(f"{res['name']}\nConfusion Matrix")
        ax.set_xlabel('Predicted')
        ax.set_ylabel('Actual')

        # Thêm metrics
        tn, fp, fn, tp = cm.ravel()
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
        ax.text(0.5, -0.2, f'P={precision:.3f} R={recall:.3f} F1={f1:.3f}',
                transform=ax.transAxes, ha='center', fontsize=10)

    plt.tight_layout()
    path = os.path.join(OUTPUT_DIR, "confusion_matrix.png")
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Da luu: {path}")

# =========================================================================
# 6. PLOT ROC + PR CURVES
# =========================================================================
def plot_curves(results, y_test):
    print("\n[6/7] Ve ROC + Precision-Recall curves...")

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    colors = {'lr': '#2196F3', 'rf': '#4CAF50', 'peak': '#FF9800'}
    
    for key, res in results.items():
        # ROC
        fpr, tpr, _ = roc_curve(y_test, res['prob'])
        roc_auc = auc(fpr, tpr)
        ax1.plot(fpr, tpr, color=colors[key], lw=2,
                 label=f"{res['name']} (AUC={roc_auc:.3f})")

        # PR
        precision, recall, _ = precision_recall_curve(y_test, res['prob'])
        ax2.plot(recall, precision, color=colors[key], lw=2,
                 label=res['name'])

    # ROC
    ax1.plot([0, 1], [0, 1], 'k--', alpha=0.3)
    ax1.set_xlabel('False Positive Rate')
    ax1.set_ylabel('True Positive Rate')
    ax1.set_title('ROC Curve')
    ax1.legend(loc='lower right')
    ax1.grid(True, alpha=0.3)

    # PR
    ax2.set_xlabel('Recall')
    ax2.set_ylabel('Precision')
    ax2.set_title('Precision-Recall Curve')
    ax2.legend(loc='lower left')
    ax2.grid(True, alpha=0.3)

    # No-skill line for PR
    no_skill = y_test.mean()
    ax2.axhline(y=no_skill, color='r', linestyle='--', alpha=0.5,
                label=f'No Skill ({no_skill:.3f})')

    plt.tight_layout()
    path = os.path.join(OUTPUT_DIR, "roc_pr_curves.png")
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Da luu: {path}")

# =========================================================================
# 7. ERROR ANALYSIS
# =========================================================================
def error_analysis(results, X_test, y_test):
    print("\n[7/7] Phan tich loi...")

    # Dùng Logistic Regression cho phân tích
    y_pred = results['lr']['pred']
    y_prob = results['lr']['prob']

    fp_mask = (y_test == 0) & (y_pred == 1)
    fn_mask = (y_test == 1) & (y_pred == 0)

    fp_count = fp_mask.sum()
    fn_count = fn_mask.sum()
    tp_count = ((y_test == 1) & (y_pred == 1)).sum()
    tn_count = ((y_test == 0) & (y_pred == 0)).sum()

    print(f"\n  ========================================")
    print(f"  KET QUA ERROR ANALYSIS")
    print(f"  ========================================")
    print(f"  True Positive:  {tp_count}")
    print(f"  True Negative:  {tn_count}")
    print(f"  False Positive: {fp_count} → báo động giả")
    print(f"  False Negative: {fn_count} → bỏ sót va chạm")
    print(f"  FP Rate: {fp_count/(fp_count+tn_count)*100:.1f}%")
    print(f"  FN Rate: {fn_count/(fn_count+tp_count)*100:.1f}%")

    if fp_count > 0:
        print(f"\n  --- FALSE POSITIVE ANALYSIS (bao dong gia) ---")
        fp_probs = y_prob[fp_mask]
        fp_features = X_test[fp_mask]
        print(f"  So luong: {fp_count}")
        print(f"  Xac suat TB: {fp_probs.mean():.3f} (min={fp_probs.min():.3f}, max={fp_probs.max():.3f})")
        print(f"  Dac diem:")
        print(f"    az (truc Z): TB={fp_features[:,7].mean():.2f}g")
        print(f"    FFT band 0:  TB={fp_features[:,0].mean():.4f}")
        print(f"    FFT band 4:  TB={fp_features[:,4].mean():.4f}")
        print(f"  → Nguyen nhan kha nang: rung dong manh (o ga, phanh gap)")
        print(f"  → Giai phap: Ride mode gating + tang IMPACT_THRESH")

    if fn_count > 0:
        print(f"\n  --- FALSE NEGATIVE ANALYSIS (bo sot va cham) ---")
        fn_probs = y_prob[fn_mask]
        fn_features = X_test[fn_mask]
        print(f"  So luong: {fn_count}")
        print(f"  Xac suat TB: {fn_probs.mean():.3f}")
        print(f"  Dac diem:")
        print(f"    az (truc Z): TB={fn_features[:,7].mean():.2f}g")
        print(f"    FFT band 0:  TB={fn_features[:,0].mean():.4f}")
        print(f"  → Nguyen nhan kha nang: impact nhe, truot banh tu tu")
        print(f"  → Giai phap: ket hop Fall Detection (pitch/roll)")

    # Lưu báo cáo text
    report_path = os.path.join(OUTPUT_DIR, "error_analysis.txt")
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write("ERROR ANALYSIS REPORT\n")
        f.write("=====================\n\n")
        f.write(f"Dataset: {len(y_test)} test samples\n")
        f.write(f"Impact ratio: {y_test.mean()*100:.1f}%\n\n")
        f.write(f"Model: Logistic Regression\n")
        f.write(f"True Positive:  {tp_count}\n")
        f.write(f"True Negative:  {tn_count}\n")
        f.write(f"False Positive: {fp_count}\n")
        f.write(f"False Negative: {fn_count}\n")
        f.write(f"FP Rate: {fp_count/(fp_count+tn_count)*100:.1f}%\n")
        f.write(f"FN Rate: {fn_count/(fn_count+tp_count)*100:.1f}%\n")

    print(f"\n  Da luu bao cao: {report_path}")

    return fp_count, fn_count

# =========================================================================
# 8. CROSS-VALIDATION
# =========================================================================
def cross_validation(X, y):
    print("\n[BONUS] 5-fold Cross-Validation...")
    
    lr = LogisticRegression(C=1.0, solver='liblinear', max_iter=1000)
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_SEED)
    
    scores = cross_val_score(lr, X, y, cv=skf, scoring='f1')
    print(f"  Logistic Regression 5-fold CV F1: {scores.mean():.4f} (+/- {scores.std()*2:.4f})")
    
    rf = RandomForestClassifier(n_estimators=100, max_depth=10, random_state=RANDOM_SEED)
    rf_scores = cross_val_score(rf, X, y, cv=skf, scoring='f1')
    print(f"  Random Forest 5-fold CV F1:       {rf_scores.mean():.4f} (+/- {rf_scores.std()*2:.4f})")

# =========================================================================
# MAIN
# =========================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  MU BAO HIEM THONG MINH - ML MODEL EVALUATION")
    print("=" * 60)

    # 1. Load data
    X, y = load_impact_data()

    # 2. Split
    X_train, X_val, X_test, y_train, y_val, y_test = split_data(X, y)

    # 3. Train
    lr, rf, best_thresh = train_models(X_train, y_train, X_val, y_val)

    # 4. Evaluate
    results = evaluate_on_test(lr, rf, best_thresh, X_test, y_test)

    # 5. Confusion Matrix
    plot_confusion_matrices(results, y_test)

    # 6. ROC + PR Curves
    plot_curves(results, y_test)

    # 7. Error Analysis
    fp_count, fn_count = error_analysis(results, X_test, y_test)

    # 8. Cross-validation
    cross_validation(X, y)

    print("\n" + "=" * 60)
    print(f"  HOAN THANH! Ket qua da luu vao: {OUTPUT_DIR}/")
    print("=" * 60)
