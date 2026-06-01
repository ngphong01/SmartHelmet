// ============================================================
// SMART HELMET CONTROLLER - Web Bluetooth App
// ============================================================

const SERVICE_UUID = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const CHAR_TX_UUID = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // NOTIFY (mũ -> app)
const CHAR_RX_UUID = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // WRITE  (app -> mũ)

let bleDevice    = null;
let bleServer    = null;
let txChar       = null; // characteristic NOTIFY
let rxChar       = null; // characteristic WRITE
let map          = null;
let marker       = null;
let lastLat       = 0;
let lastLon       = 0;
let gpsValid      = false;
let impactActive  = false;

// =========================
// KHỞI TẠO BẢN ĐỒ
// =========================

function initMap() {
  map = L.map('map', {
    attributionControl: false,
    zoomControl: true
  }).setView([21.0278, 105.8342], 13); // Mặc định: Hà Nội

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    // attribution: '© OpenStreetMap'
  }).addTo(map);

  // Tạo marker nhưng chưa thêm vào map
  marker = L.marker([0, 0], {
    icon: L.divIcon({
      className: 'helmet-marker',
      html: '<div style="font-size:32px">🪖</div>',
      iconSize: [40, 40],
      iconAnchor: [20, 20]
    })
  });
}

// =========================
// KẾT NỐI BLE
// =========================

async function connectToHelmet() {
  const btn = document.getElementById('btn-connect');
  btn.disabled = true;
  btn.innerHTML = '<span class="btn-icon">⏳</span> Đang quét BLE...';

  try {
    bleDevice = await navigator.bluetooth.requestDevice({
      filters: [{ name: 'SmartHelmet' }],
      optionalServices: [SERVICE_UUID]
    });

    updateStatus('connecting', 'Đang kết nối...');

    bleServer = await bleDevice.gatt.connect();
    const service = await bleServer.getPrimaryService(SERVICE_UUID);

    // TX = Notify (mũ gửi dữ liệu lên app)
    txChar = await service.getCharacteristic(CHAR_TX_UUID);
    await txChar.startNotifications();
    txChar.addEventListener('characteristicvaluechanged', onDataReceived);

    // RX = Write (app gửi lệnh xuống mũ)
    rxChar = await service.getCharacteristic(CHAR_RX_UUID);

    // Lắng nghe sự kiện ngắt kết nối
    bleDevice.addEventListener('gattserverdisconnected', onDisconnected);

    // Gửi lệnh START
    await sendCommand('START');

    updateStatus('connected', 'Đã kết nối');
    document.getElementById('connect-panel').classList.add('hidden');
    document.getElementById('dashboard').classList.remove('hidden');

    if (!map) initMap();

  } catch (err) {
    console.error('Lỗi BLE:', err);
    updateStatus('disconnected', 'Chưa kết nối');
    btn.disabled = false;
    btn.innerHTML = '<span class="btn-icon">🔗</span> Kết nối Mũ Bảo Hiểm';

    if (err.name === 'NotFoundError') {
      alert('Không tìm thấy thiết bị SmartHelmet.\nHãy chắc chắn mũ đang bật nguồn và trong phạm vi Bluetooth.');
    } else if (err.name !== 'AbortError') {
      alert('Lỗi kết nối: ' + err.message);
    }
  }
}

// =========================
// XỬ LÝ DỮ LIỆU NHẬN ĐƯỢC
// =========================

function onDataReceived(event) {
  const decoder = new TextDecoder('utf-8');
  const text = decoder.decode(event.target.value);
  logRaw(text);

  try {
    const data = JSON.parse(text);
    if (data.type === 'telemetry') {
      updateTelemetry(data);
    }
  } catch (e) {
    // Không phải JSON hợp lệ, bỏ qua
  }
}

function updateTelemetry(data) {
  // GPS
  if (data.gps && data.gps.lat && data.gps.lon) {
    lastLat = data.gps.lat;
    lastLon = data.gps.lon;
    gpsValid = true;
    updateMap(lastLat, lastLon);
    document.getElementById('gps-age').textContent = '🟢 Live';
  } else {
    document.getElementById('gps-age').textContent = '⏳ Đang chờ GPS...';
  }

  // Stats
  if (data.impact) {
    document.getElementById('stat-peak-g').textContent = data.impact.peak_g.toFixed(2);
    document.getElementById('stat-ai-p').textContent = (data.impact.ai_p * 100).toFixed(1);
  }
  if (data.gps) {
    document.getElementById('stat-sats').textContent = data.gps.satellites || '--';
    document.getElementById('stat-speed').textContent = data.gps.speed_kmh.toFixed(1);
  }

  // Impact Alert
  if (data.impact && data.impact.detected === true && !impactActive) {
    impactActive = true;
    showImpactAlert(data);
    // Tự động ẩn sau 30 giây
    setTimeout(() => {
      document.getElementById('impact-alert').classList.add('hidden');
      impactActive = false;
    }, 30000);
  }
}

// =========================
// CẬP NHẬT BẢN ĐỒ
// =========================

function updateMap(lat, lon) {
  if (!map) return;
  marker.setLatLng([lat, lon]);
  if (!map.hasLayer(marker)) {
    marker.addTo(map);
  }
  map.setView([lat, lon], map.getZoom() < 15 ? 15 : map.getZoom());
}

function showImpactAlert(data) {
  const alertDiv = document.getElementById('impact-alert');
  alertDiv.classList.remove('hidden');

  const detail = document.getElementById('alert-detail');
  let locText = '';
  if (gpsValid) {
    locText = `Vị trí: <a href="https://maps.google.com/?q=${lastLat},${lastLon}" target="_blank" style="color:#fbbf24">${lastLat.toFixed(5)}, ${lastLon.toFixed(5)}</a>`;
  } else {
    locText = 'Vị trí: Chưa có GPS';
  }

  detail.innerHTML = `
    ${locText}<br>
    AI xác suất: <strong>${(data.impact.ai_p * 100).toFixed(1)}%</strong> ·
    Đỉnh G: <strong>${data.impact.peak_g.toFixed(2)}g</strong>
  `;

  // Rung điện thoại nếu hỗ trợ
  if (navigator.vibrate) {
    navigator.vibrate([200, 100, 200, 100, 500]);
  }
}

// =========================
// GỬI LỆNH
// =========================

async function sendCommand(cmd) {
  if (!rxChar) {
    console.warn('Chưa kết nối BLE');
    return;
  }
  try {
    const encoder = new TextEncoder();
    await rxChar.writeValue(encoder.encode(cmd));
    console.log('[GỬI]', cmd);
  } catch (err) {
    console.error('Lỗi gửi lệnh:', err);
  }
}

function sendAck() {
  sendCommand('ACK');
  // Feedback rung nhẹ
  if (navigator.vibrate) navigator.vibrate(50);

  // Ẩn alert nếu đang hiển thị
  document.getElementById('impact-alert').classList.add('hidden');
  impactActive = false;

  // Flash nút xanh
  const btn = document.querySelector('.ctrl-ack');
  btn.style.background = 'rgba(34,197,94,0.3)';
  setTimeout(() => { btn.style.background = ''; }, 300);
}

function sendSos() {
  // Xác nhận trước khi gửi SOS
  if (!confirm('⚠️ Bạn chắc chắn muốn gửi tín hiệu CỨU HỘ KHẨN CẤP?')) return;

  sendCommand('SOS');
  if (navigator.vibrate) navigator.vibrate([300, 100, 300, 100, 600]);

  const btn = document.querySelector('.ctrl-sos');
  btn.style.background = 'rgba(239,68,68,0.3)';
  setTimeout(() => { btn.style.background = ''; }, 500);

  alert('🆘 Đã gửi tín hiệu SOS đến mũ bảo hiểm!');
}

// =========================
// TRẠNG THÁI & LOG
// =========================

function updateStatus(state, text) {
  const badge = document.getElementById('status-badge');
  badge.className = 'badge ' + state;
  document.getElementById('status-text').textContent = text;
}

function logRaw(text) {
  const log = document.getElementById('raw-log');
  const time = new Date().toLocaleTimeString();
  log.textContent = `[${time}] ${text}`;
}

function onDisconnected() {
  updateStatus('disconnected', 'Mất kết nối');
  document.getElementById('connect-panel').classList.remove('hidden');
  document.getElementById('dashboard').classList.add('hidden');

  bleDevice = null;
  bleServer = null;
  txChar = null;
  rxChar = null;

  document.getElementById('btn-connect').disabled = false;
  document.getElementById('btn-connect').innerHTML =
    '<span class="btn-icon">🔗</span> Kết nối lại';
}

// =========================
// KHỞI TẠO TRANG
// =========================

document.addEventListener('DOMContentLoaded', () => {
  console.log('🪖 SmartHelmet Controller sẵn sàng');
  console.log('📱 Hỗ trợ Web Bluetooth:', !!navigator.bluetooth);

  if (!navigator.bluetooth) {
    document.getElementById('btn-connect').disabled = true;
    document.getElementById('btn-connect').innerHTML =
      '<span class="btn-icon">⚠️</span> Trình duyệt không hỗ trợ BLE';
    document.querySelector('.hint').textContent =
      'Vui lòng dùng Chrome/Edge trên Android, Mac hoặc Windows';
  }
});
