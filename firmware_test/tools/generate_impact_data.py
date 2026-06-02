#!/usr/bin/env python3
"""Sinh dữ liệu va chạm tổng hợp cho MPU6500 (±4g, 8192 LSB/g)"""

import math
import random
import os

# ===== THAM SỐ =====
ACCEL_SENS = 8192.0  # LSB/g cho ±4g
SAMPLE_RATE = 1000   # Hz
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "impact_data.cpp")

# ===== HÀM SINH IMPACT =====
def generate_impact(direction='front', peak_g=4.0, duration_ms=30, ring_ms=80):
    """
    Sinh dữ liệu cho 1 lần va chạm.
    direction: 'front' (ax), 'side' (ay), 'top' (az), 'all' (cả 3 trục)
    peak_g: đỉnh gia tốc (g)
    duration_ms: thời gian xung chính (ms)
    ring_ms: thời gian dao động sau va chạm (ms)
    """
    total = 50 + duration_ms + ring_ms  # 50ms trước impact + impact + ringing
    ax, ay, az = [], [], []
    
    for i in range(total):
        t_ms = i - 50  # 0 = thời điểm impact
        
        # Trạng thái nền: ax~0, ay~0, az~1g (trọng lực)
        base_ax = random.gauss(0, 0.02)
        base_ay = random.gauss(0, 0.02)
        base_az = 1.0 + random.gauss(0, 0.03)
        
        # Xung va chạm
        if t_ms >= 0:
            # Gaussian pulse
            sigma = duration_ms / 3.0
            pulse = peak_g * math.exp(-0.5 * (t_ms / sigma) ** 2)
            
            # Ringing sau va chạm
            if t_ms > duration_ms:
                ring_t = t_ms - duration_ms
                ring_decay = math.exp(-ring_t / (ring_ms * 0.4))
                ring_freq = 80.0  # Hz
                pulse = peak_g * 0.3 * ring_decay * math.sin(2 * math.pi * ring_freq * ring_t / 1000.0)
        else:
            pulse = 0.0
        
        # Phân phối pulse theo hướng
        noise = random.gauss(0, 0.05)
        if direction == 'front':
            impact_ax = pulse + noise
            impact_ay = noise * 0.3
            impact_az = noise * 0.3
        elif direction == 'side':
            impact_ax = noise * 0.3
            impact_ay = pulse + noise
            impact_az = noise * 0.3
        elif direction == 'top':
            impact_ax = noise * 0.3
            impact_ay = noise * 0.3
            impact_az = -pulse + noise  # hướng xuống
        elif direction == 'all':
            impact_ax = pulse * 0.7 + noise
            impact_ay = pulse * 0.5 + noise
            impact_az = pulse * 0.4 + noise
        
# Tổng gia tốc, giới hạn ±4g (clamp về int16_t range)
        total_ax = max(-4.0, min(4.0, base_ax + impact_ax))
        total_ay = max(-4.0, min(4.0, base_ay + impact_ay))
        total_az = max(-4.0, min(4.0, base_az + impact_az))

        # Chuyển sang raw int16, clamp vào [-32767, 32767]
        ax.append(max(-32767, min(32767, int(total_ax * ACCEL_SENS))))
        ay.append(max(-32767, min(32767, int(total_ay * ACCEL_SENS))))
        az.append(max(-32767, min(32767, int(total_az * ACCEL_SENS))))
    
    return ax, ay, az

# ===== SINH NHIỀU TÌNH HUỐNG =====
random.seed(42)
all_ax, all_ay, all_az = [], [], []

# 1. Va chạm trực diện mạnh (ô tô, xe máy) - 5 lần
for _ in range(5):
    peak = random.uniform(3.0, 4.0)
    ax, ay, az = generate_impact('front', peak_g=peak, duration_ms=25, ring_ms=60)
    all_ax.extend(ax); all_ay.extend(ay); all_az.extend(az)

# 2. Ngã ngang (té sang bên) - 4 lần
for _ in range(4):
    peak = random.uniform(2.5, 3.8)
    ax, ay, az = generate_impact('side', peak_g=peak, duration_ms=30, ring_ms=70)
    all_ax.extend(ax); all_ay.extend(ay); all_az.extend(az)

# 3. Va chạm từ trên (vật rơi trúng) - 3 lần
for _ in range(3):
    peak = random.uniform(2.0, 3.5)
    ax, ay, az = generate_impact('top', peak_g=peak, duration_ms=20, ring_ms=50)
    all_ax.extend(ax); all_ay.extend(ay); all_az.extend(az)

# 4. Va chạm đa hướng (lộn vòng) - 3 lần
for _ in range(3):
    peak = random.uniform(2.5, 4.0)
    ax, ay, az = generate_impact('all', peak_g=peak, duration_ms=35, ring_ms=80)
    all_ax.extend(ax); all_ay.extend(ay); all_az.extend(az)

# 5. Va chạm nhẹ (va quẹt) - 3 lần
for _ in range(3):
    peak = random.uniform(1.5, 2.5)
    ax, ay, az = generate_impact('front', peak_g=peak, duration_ms=15, ring_ms=40)
    all_ax.extend(ax); all_ay.extend(ay); all_az.extend(az)

N = len(all_ax)
labels = [1] * N  # Tất cả là impact

print(f"Generated {N} impact samples ({N/1000:.1f}s @ {SAMPLE_RATE}Hz)")

# ===== GHI FILE C++ =====
def write_array(f, name, data, values_per_line=20):
    f.write(f"const int16_t {name}[{len(data)}] = {{\n")
    for i in range(0, len(data), values_per_line):
        f.write("    " + ", ".join(str(v) for v in data[i:i+values_per_line]))
        if i + values_per_line < len(data):
            f.write(",\n")
        else:
            f.write("\n")
    f.write("};\n\n")

def write_label_array(f, name, data, values_per_line=40):
    f.write(f"const uint8_t {name}[{len(data)}] = {{\n")
    for i in range(0, len(data), values_per_line):
        f.write("    " + ", ".join(str(v) for v in data[i:i+values_per_line]))
        if i + values_per_line < len(data):
            f.write(",\n")
        else:
            f.write("\n")
    f.write("};\n\n")

with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
    f.write('// Auto-generated impact training data\n')
    f.write('// MPU6500 ±4g, 8192 LSB/g, 1000Hz\n')
    f.write('// Cac tinh huong: va cham truc dien, nga ngang, vat roi, da huong, va quet\n')
    f.write(f'// Total: {N} samples ({N/1000:.1f}s)\n')
    f.write('\n#include "impact_data.h"\n\n')
    f.write(f'const int IMPACT_SAMPLES = {N};\n\n')
    write_array(f, 'impact_ax', all_ax)
    write_array(f, 'impact_ay', all_ay)
    write_array(f, 'impact_az', all_az)
    write_label_array(f, 'impact_label', labels)

print(f"Written to {OUTPUT_FILE}")
print(f"IMPACT_SAMPLES = {N}")
