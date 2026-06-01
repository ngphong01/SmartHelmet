// app/api/index.ts
import * as Location from 'expo-location';
import { API_KEY, API_URL } from '../constants/index';

export const sendImpactToServer = async (data?: { ai_p?: number }) => {
  try {
    console.log('Bắt đầu gửi cứu hộ...', data);

    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      console.log('Quyền vị trí bị từ chối');
      return;
    }

    const location = await Location.getCurrentPositionAsync({});
    const payload = {
      schema_version: 2,
      helmet_id: 'H001',
      device_type: 'helmet',
      gps: {
        lat: location.coords.latitude,
        lon: location.coords.longitude,
        speed_kmh: (location.coords.speed ?? 0) * 3.6,
        satellites: null,
        hdop: null,
      },
      impact: {
        detected: true,
        ai_p: data?.ai_p ?? null,
        peak_g: null,
        confidence: data?.ai_p ?? null,
      },
      firmware: {
        version: '1.0.0',
        build: 'expo-app',
      },
      ts: new Date().toISOString(),
    };

    console.log('Gửi payload tới:', API_URL);
    console.log('Payload:', payload);

    const controller = new AbortController();
    const timeoutMs = 10000;
    const timeoutId = setTimeout(() => {
      console.log(`⏱ Abort fetch sau ${timeoutMs}ms`);
      controller.abort();
    }, timeoutMs);

    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(API_KEY ? { 'x-api-key': API_KEY } : {}),
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (res.ok) {
        console.log('✅ GỬI THÀNH CÔNG LÊN SERVER!');
      } else {
        const text = await res.text().catch(() => '');
        console.log('❌ Server lỗi:', res.status, text);
      }
    } catch (err: any) {
      clearTimeout(timeoutId);

      if (err?.name === 'AbortError') {
        console.error('⛔ Lỗi khi gọi fetch: bị Abort (timeout) – server không trả lời kịp');
      } else {
        console.error('🌐 Lỗi khi gọi fetch (network?):', err?.message || err);
      }
    }
  } catch (error: any) {
    console.error('Gửi thất bại (outer):', error?.message || error);
  }
};
