
/**
 * Deep merge utility for configuration objects with key deletion support
 * Use "__DELETE__" as value to delete a key
 */
function deepMerge<T extends Record<string, any>>(target: T, source: Partial<T>): T {
  const result = { ...target };

  for (const key in source) {
    if (source.hasOwnProperty(key)) {
      const sourceValue = source[key];
      const targetValue = result[key];

      // Special marker to delete keys
      if (sourceValue === "__DELETE__") {
        delete result[key];
        continue;
      }

      if (sourceValue === null || sourceValue === undefined) {
        continue;
      }

      if (
        typeof sourceValue === "object" &&
        !Array.isArray(sourceValue) &&
        typeof targetValue === "object" &&
        !Array.isArray(targetValue) &&
        targetValue !== null
      ) {
        result[key] = deepMerge(targetValue, sourceValue);
      } else {
        result[key] = sourceValue;
      }
    }
  }

  return result;
}

/**
 * Load configuration override from JSON file
 * Environment variable: DEVICE_CONFIG_OVERRIDE_PATH
 */
function loadConfigOverride(): Partial<Record<ManufacturerCode, DeviceConfig>> {
  const overridePath = process.env.DEVICE_CONFIG_OVERRIDE_PATH;

  if (!overridePath) {
    return {};
  }

  try {
    const content = readFileSync(overridePath, "utf-8");
    const override = JSON.parse(content) as Partial<Record<ManufacturerCode, DeviceConfig>>;
    console.log(`[deviceConfig] Loaded configuration override from: ${overridePath}`);
    return override;
  } catch (error) {
    console.error(`[deviceConfig] Failed to load configuration override from ${overridePath}:`, error);
    return {};
  }
}

/**
 * Shallow merge with deletion support for payload merging
 * Use "__DELETE__" as value to delete a key
 */
export function mergePayloadWithDelete<T extends Record<string, any>>(
  base: T,
  override: Partial<T>
): T {
  const result = { ...base };

  for (const key in override) {
    if (override.hasOwnProperty(key)) {
      const value = override[key];

      // Special marker to delete keys
      if (value === "__DELETE__") {
        delete result[key];
      } else {
        result[key] = value;
      }
    }
  }

  return result;
}

// Apply configuration override
const configOverride = loadConfigOverride();
for (const manufacturer in configOverride) {
  const manufacturerCode = manufacturer as ManufacturerCode;
  const existing = (ManufacturerDeviceConfig as Record<string, DeviceConfig>)[manufacturerCode] || {};
  (ManufacturerDeviceConfig as Record<string, DeviceConfig>)[manufacturerCode] = deepMerge(existing, configOverride[manufacturerCode]!);
}
