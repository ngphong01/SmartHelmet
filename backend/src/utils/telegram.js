// backend/src/utils/telegram.js
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

function getTelegramConfig() {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;

  if (!token || !chatId) return null;
  return { token, chatId };
}

const sendTelegramAlert = async (lat, lon) => {
  const cfg = getTelegramConfig();
  if (!cfg) {
    console.warn('Telegram config missing; skip alert.');
    return;
  }

  const mapsUrl = `https://maps.google.com/?q=${lat},${lon}`;
  const message = `
*CẢNH BÁO: VA CHẠM MẠNH!*  
Vị trí: [Mở Google Maps](${mapsUrl})
Thời gian: ${new Date().toLocaleString('vi-VN')}
  `.trim();

  try {
    await fetch(`https://api.telegram.org/bot${cfg.token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: cfg.chatId,
        text: message,
        parse_mode: 'Markdown',
        disable_web_page_preview: false,
      }),
    });
    console.log('ĐÃ GỬI TELEGRAM:', mapsUrl);
  } catch (error) {
    console.error('Lỗi gửi Telegram:', error.message);
  }
};

module.exports = { sendTelegramAlert };