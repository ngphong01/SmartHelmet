// src/train_on_device.cpp
#include <Arduino.h>
#include <math.h>

#include "train_on_device.h"
#include "training_data.h"
#include "impact_data.h"
#include "fft_features.h"
#include "ml_model.h"

// Helper: train trên 1 dataset (ax, ay, az, label, numSamples)
static void train_on_dataset(LogisticModel &model,
                             const int16_t *ax_arr, const int16_t *ay_arr, const int16_t *az_arr,
                             const uint8_t *label_arr, int numSamples,
                             int WIN_N, int STEP, float ACCEL_SENS)
{
    float g_buf[WIN_N];
    float fft_feat[5];
    float feat[FEAT_DIM];

    for (int start = 0; start + WIN_N <= numSamples; start += STEP)
    {
        int end = start + WIN_N;
        int last_idx = end - 1;

        // 1) Tính norm g[n]
        for (int i = 0; i < WIN_N; ++i)
        {
            int idx = start + i;
            float ax = (float)ax_arr[idx] / ACCEL_SENS;
            float ay = (float)ay_arr[idx] / ACCEL_SENS;
            float az = (float)az_arr[idx] / ACCEL_SENS;
            g_buf[i] = sqrtf(ax * ax + ay * ay + az * az);
        }

        // 2) FFT → 5 feature
        compute_fft_features(g_buf, WIN_N, fft_feat);

        // 3) 3 gia tốc cuối cửa sổ
        float ax_last = (float)ax_arr[last_idx] / ACCEL_SENS;
        float ay_last = (float)ay_arr[last_idx] / ACCEL_SENS;
        float az_last = (float)az_arr[last_idx] / ACCEL_SENS;

        // 4) Vector feature FEAT_DIM = 8
        feat[0] = fft_feat[0];
        feat[1] = fft_feat[1];
        feat[2] = fft_feat[2];
        feat[3] = fft_feat[3];
        feat[4] = fft_feat[4];
        feat[5] = ax_last;
        feat[6] = ay_last;
        feat[7] = az_last;

        // 5) Label
        int y = (int)label_arr[last_idx];

        // 6) Cập nhật model
        logistic_train_step(model, feat, y);
    }
}

void run_offline_training(LogisticModel &model)
{
    const int WIN_N = 512;
    const int STEP = WIN_N / 2; // overlap 50%
    const int EPOCHS = 5;       // tăng epoch để model học tốt hơn

    const float ACCEL_SENS = 8192.0f;

    if (TRAIN_SAMPLES < WIN_N)
    {
        Serial.println("[LOI][AI] Khong du du lieu train (normal)");
        return;
    }

    Serial.print("[AI] Du lieu NORMAL: ");
    Serial.print(TRAIN_SAMPLES);
    Serial.print(" mau (label=0)");

    if (IMPACT_SAMPLES >= WIN_N)
    {
        Serial.print(" | IMPACT: ");
        Serial.print(IMPACT_SAMPLES);
        Serial.println(" mau (label=1)");
    }
    else
    {
        Serial.println(" | IMPACT: KHONG DU (can >= 512 mau)");
    }

    Serial.println("[AI][RUN] Bat dau train tren ESP32...");

    for (int epoch = 0; epoch < EPOCHS; ++epoch)
    {
        Serial.print("[AI] Vong train ");
        Serial.print(epoch + 1);
        Serial.print("/");
        Serial.println(EPOCHS);

        // Train trên dữ liệu NORMAL (label=0)
        train_on_dataset(model, train_ax, train_ay, train_az, train_label,
                         TRAIN_SAMPLES, WIN_N, STEP, ACCEL_SENS);

        // Train trên dữ liệu IMPACT (label=1) nếu có đủ
        if (IMPACT_SAMPLES >= WIN_N)
        {
            train_on_dataset(model, impact_ax, impact_ay, impact_az, impact_label,
                             IMPACT_SAMPLES, WIN_N, STEP, ACCEL_SENS);
        }
    }

    Serial.println("[OK][AI] Train xong. Vi du tham so:");
    Serial.print("  b = ");
    Serial.println(model.b, 6);
    for (int i = 0; i < FEAT_DIM; ++i)
    {
        Serial.print("  w[");
        Serial.print(i);
        Serial.print("] = ");
        Serial.println(model.w[i], 6);
    }
}
