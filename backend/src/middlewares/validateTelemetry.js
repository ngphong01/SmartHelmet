// npm i ajv ajv-formats
const Ajv = require('ajv/dist/2020');
const addFormats = require('ajv-formats');
const schema = require('../schemas/telemetry.schema.json');

const ajv = new Ajv({ allErrors: true, removeAdditional: true });
addFormats(ajv);
const validate = ajv.compile(schema);

module.exports = function validateTelemetry(req, res, next) {
  const apiKey = req.get('x-api-key');
  const expected = process.env.API_KEY;
  if (!expected || apiKey !== expected) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const ok = validate(req.body);
  if (!ok) {
    return res.status(400).json({
      error: 'invalid_payload',
      details: validate.errors?.map(e => `${e.instancePath || '/'} ${e.message}`),
    });
  }
  return next();
};
