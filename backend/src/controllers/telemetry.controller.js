const { setCurrentPosition } = require('../services/position.service');
const { createIncident } = require('../services/incident.service');
const sockets = require('../sockets');
const { sendTelegramAlert } = require('../utils/telegram');
const Telemetry = require('../models/telemetry.model'); // optional

async function ingestTelemetry(req, res, next) {
  try {
    const { schema_version, helmet_id, device_type, gps, impact, time, ts, firmware } = req.body || {};
    const { lat, lon, speed_kmh = 0 } = gps || {};
    const impactDetected = !!impact?.detected;

    const telemetryDoc = {
      schema_version,
      helmet_id,
      device_type,
      gps,
      impact,
      firmware,
      time,
      ts,
    };

    try {
      await Telemetry.create({
        helmet_id,
        lat,
        lon,
        speed: speed_kmh,
        impact_detected: impactDetected,
        ts: time?.utc ?? ts,
      });
    } catch {}

    const pos = await setCurrentPosition(helmet_id, {
      lat,
      lon,
      speed: speed_kmh,
      ts: new Date(time?.utc ?? ts),
    });
    sockets.emitPosition({ helmet_id, ...pos });

    if (impactDetected) {
      await sendTelegramAlert(lat, lon);
      const incident = await createIncident({ helmet_id, lat, lon, ts: new Date(time?.utc ?? ts) });
      sockets.emitIncident(incident);
    }

    res.json({ ok: true, telemetry: telemetryDoc });
  } catch (e) { next(e); }
}

module.exports = { ingestTelemetry };
