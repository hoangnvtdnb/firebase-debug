/** Suy luận kiểu từ chuỗi logcat (Firebase Bundle không gửi metadata type). */
function inferValueType(raw) {
  const s = String(raw).trim();
  if (s === "") return "string";
  if (s === "true" || s === "false") return "boolean";
  if (s === "null") return "null";
  if (/^-?\d+$/.test(s)) return "int";
  if (/^-?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$/.test(s) || /^-?\d+[eE][+-]?\d+$/.test(s)) {
    return "double";
  }
  return "string";
}

function normalizeParamValue(raw) {
  if (raw !== null && typeof raw === "object" && raw.value !== undefined) {
    return {
      value: String(raw.value),
      valueType: raw.valueType || inferValueType(raw.value),
    };
  }
  const value = String(raw);
  return { value: value, valueType: inferValueType(value) };
}

function normalizeEventParams(params) {
  if (!params || typeof params !== "object") return {};
  const out = {};
  for (const key of Object.keys(params)) {
    out[key] = normalizeParamValue(params[key]);
  }
  return out;
}

function paramDisplayValue(entry) {
  return entry && typeof entry === "object" ? entry.value : String(entry);
}
