// src/train_on_device.cpp
#include <Arduino.h>
#include <math.h>

#include "train_on_device.h"
#include "training_data.h"
#include "fft_features.h"
#include "ml_model.h"

void run_offline_training(LogisticModel& model) {
    const int WIN_N  = 512;
    const int STEP   = WIN_N / 2;   // overlap 50%
    const int EPOCHS = 4;           // ít epoch + LR nhỏ → ổn định hơn

    // MPU6500: ±4g → 8192 LSB / g
    const float ACCEL_SENS = 8192.0f;

    if (TRAIN_SAMPLES < WIN_N) {
        Serial.println("[LOI][AI] Khong du du lieu train");
        return;
    }

    float g[WIN_N];
    float fft_feat[5];
    float feat[FEAT_DIM];  // FEAT_DIM = 8 (5 FFT + 3 accel cuối)

    Serial.print("[AI] So mau train = ");
    Serial.println(TRAIN_SAMPLES);
    Serial.println("[AI][RUN] Bat dau train tren ESP32");

    for (int epoch = 0; epoch < EPOCHS; ++epoch) {
        Serial.print("[AI] Vong train ");
        Serial.println(epoch);

        for (int start = 0; start + WIN_N <= TRAIN_SAMPLES; start += STEP) {
            int end      = start + WIN_N;
            int last_idx = end - 1;

            // 1) Tính norm g[n] từ dữ liệu SCALED (raw / ACCEL_SENS)
            for (int i = 0; i < WIN_N; ++i) {
                int idx = start + i;

                float ax = (float)train_ax[idx] / ACCEL_SENS;
                float ay = (float)train_ay[idx] / ACCEL_SENS;
                float az = (float)train_az[idx] / ACCEL_SENS;

                g[i] = sqrtf(ax*ax + ay*ay + az*az);
            }

            // 2) FFT → 5 feature tại các tần số đã chọn
            compute_fft_features(g, WIN_N, fft_feat);  // fft_feat[0..4]

            // 3) 3 gia tốc cuối cửa sổ (đã scale về g)
            float ax_last = (float)train_ax[last_idx] / ACCEL_SENS;
            float ay_last = (float)train_ay[last_idx] / ACCEL_SENS;
            float az_last = (float)train_az[last_idx] / ACCEL_SENS;

            // 4) Vector feature FEAT_DIM = 8
            feat[0] = fft_feat[0];
            feat[1] = fft_feat[1];
            feat[2] = fft_feat[2];
            feat[3] = fft_feat[3];
            feat[4] = fft_feat[4];
            feat[5] = ax_last;
            feat[6] = ay_last;
            feat[7] = az_last;

            // 5) Label = nhãn của sample cuối cửa sổ
            int y = (int)train_label[last_idx];

            // 6) Cập nhật model logistic
            logistic_train_step(model, feat, y);
        }
    }

    Serial.println("[OK][AI] Train xong. Vi du w[0]:");
    Serial.println(model.w[0], 6);
}
