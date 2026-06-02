// src/data_recorder.cpp
#include "data_recorder.h"
#include <Arduino.h>

// ===== Ring buffer lưu dữ liệu IMU raw =====
static int16_t buf_ax[RECORDER_BUFFER_SIZE];
static int16_t buf_ay[RECORDER_BUFFER_SIZE];
static int16_t buf_az[RECORDER_BUFFER_SIZE];
static uint8_t buf_label[RECORDER_BUFFER_SIZE]; // 0=normal, 1=impact
static uint32_t buf_count = 0;
static uint32_t buf_head = 0; // vị trí ghi tiếp theo

void recorder_init()
{
    buf_count = 0;
    buf_head = 0;
    for (uint32_t i = 0; i < RECORDER_BUFFER_SIZE; i++)
    {
        buf_label[i] = 0;
    }
    Serial.println("[RECORDER] Khoi tao xong. Dung luong: 5 giay @ 1000Hz");
    Serial.println("[RECORDER] Gui 'r' de xuat du lieu, 'c' de xoa, 'i' de danh dau va cham");
}

void recorder_push(int16_t ax, int16_t ay, int16_t az)
{
    buf_ax[buf_head] = ax;
    buf_ay[buf_head] = ay;
    buf_az[buf_head] = az;
    buf_label[buf_head] = 0; // mặc định là normal

    buf_head = (buf_head + 1) % RECORDER_BUFFER_SIZE;
    if (buf_count < RECORDER_BUFFER_SIZE)
    {
        buf_count++;
    }
}

void recorder_mark_impact(uint32_t preMs, uint32_t postMs)
{
    if (buf_count == 0)
    {
        Serial.println("[RECORDER] Buffer rong, khong the danh dau");
        return;
    }

    // Giả sử sample rate 1000Hz => 1ms = 1 sample
    uint32_t preSamples = preMs;
    uint32_t postSamples = postMs;
    uint32_t totalSamples = preSamples + postSamples;

    if (totalSamples > buf_count)
    {
        totalSamples = buf_count;
        preSamples = totalSamples / 2;
        postSamples = totalSamples - preSamples;
    }

    // head hiện tại là vị trí "hiện tại" (sample mới nhất vừa được push)
    // Đánh dấu preSamples samples TRƯỚC head và postSamples samples SAU head

    // Đánh dấu các mẫu trước đó (đi ngược từ head-1)
    for (uint32_t i = 1; i <= preSamples && i <= buf_count; i++)
    {
        uint32_t idx = (buf_head - i + RECORDER_BUFFER_SIZE) % RECORDER_BUFFER_SIZE;
        buf_label[idx] = 1;
    }

    // Đánh dấu các mẫu sắp tới (head là mẫu tiếp theo sẽ ghi)
    uint32_t marked = 0;
    uint32_t idx = buf_head;
    while (marked < postSamples && marked < RECORDER_BUFFER_SIZE)
    {
        buf_label[idx] = 1;
        idx = (idx + 1) % RECORDER_BUFFER_SIZE;
        marked++;
    }

    Serial.printf("[RECORDER] Da danh dau %u ms truoc + %u ms sau la IMPACT (label=1)\n",
                  (unsigned)preMs, (unsigned)postMs);
}

void recorder_dump_to_serial()
{
    if (buf_count == 0)
    {
        Serial.println("[RECORDER] Khong co du lieu de xuat");
        return;
    }

    // Đếm số mẫu impact
    uint32_t impactCount = 0;
    uint32_t normalCount = 0;
    for (uint32_t i = 0; i < buf_count; i++)
    {
        if (buf_label[i] == 1)
            impactCount++;
        else
            normalCount++;
    }

    Serial.println("\n╔══════════════════════════════════════════╗");
    Serial.println("║   DU LIEU TRAINING - COPY VAO CODE      ║");
    Serial.println("╚══════════════════════════════════════════╝");
    Serial.printf("// Tong: %u normal + %u impact\n\n", (unsigned)normalCount, (unsigned)impactCount);

    // In ax[]
    Serial.print("const int16_t rec_ax[] = {");
    for (uint32_t i = 0; i < buf_count; i++)
    {
        if (i > 0)
            Serial.print(", ");
        if (i % 20 == 0)
            Serial.println();
        Serial.print(buf_ax[i]);
    }
    Serial.println("};\n");

    // In ay[]
    Serial.print("const int16_t rec_ay[] = {");
    for (uint32_t i = 0; i < buf_count; i++)
    {
        if (i > 0)
            Serial.print(", ");
        if (i % 20 == 0)
            Serial.println();
        Serial.print(buf_ay[i]);
    }
    Serial.println("};\n");

    // In az[]
    Serial.print("const int16_t rec_az[] = {");
    for (uint32_t i = 0; i < buf_count; i++)
    {
        if (i > 0)
            Serial.print(", ");
        if (i % 20 == 0)
            Serial.println();
        Serial.print(buf_az[i]);
    }
    Serial.println("};\n");

    // In label[]
    Serial.print("const uint8_t rec_label[] = {");
    for (uint32_t i = 0; i < buf_count; i++)
    {
        if (i > 0)
            Serial.print(", ");
        if (i % 40 == 0)
            Serial.println();
        Serial.print((int)buf_label[i]);
    }
    Serial.println("};\n");

    Serial.printf("// const int REC_SAMPLES = %u;\n", (unsigned)buf_count);
    Serial.println("╔══════════════════════════════════════════╗");
    Serial.println("║   KET THUC DU LIEU                      ║");
    Serial.println("╚══════════════════════════════════════════╝\n");
}

uint32_t recorder_count()
{
    return buf_count;
}

void recorder_clear()
{
    buf_count = 0;
    buf_head = 0;
    for (uint32_t i = 0; i < RECORDER_BUFFER_SIZE; i++)
    {
        buf_label[i] = 0;
    }
    Serial.println("[RECORDER] Da xoa toan bo buffer");
}
