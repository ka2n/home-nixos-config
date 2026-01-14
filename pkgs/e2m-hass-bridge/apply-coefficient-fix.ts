import type { Payload } from "@/payload/payloadType";
import { getDeviceValue, getFirstElNumberType } from "@/util/deviceUtil";
import type { ApiDevice, ApiDeviceProperty } from "echonetlite2mqtt/server/ApiTypes";

/**
 * Apply coefficient fix for powerDistributionBoardMetering
 * echonetlite2mqtt ignores coefficient field, so we need to manually apply it
 * using unitForCumulativeElectricEnergy (EPC 0xC2)
 */
export function applyCoefficientFix(
  apiDevice: ApiDevice,
  property: ApiDeviceProperty,
  payload: Payload
): Payload {
  const needsFix =
    apiDevice.deviceType === "powerDistributionBoardMetering" &&
    (property.name === "normalDirectionCumulativeElectricEnergy" ||
     property.name === "reverseDirectionCumulativeElectricEnergy");

  if (!needsFix) {
    return payload;
  }

  // Determine native value type from schema
  const { data } = property.schema;
  const elNumberType = getFirstElNumberType(data);
  const nativeValue = elNumberType && (!elNumberType.multiple || Number.isInteger(elNumberType.multiple)) ? "int" : "float";

  // Get coefficient from device property (EPC 0xC2)
  // This is a required property according to ECHONET Lite spec
  const coefficient = getDeviceValue<number>(apiDevice, "unitForCumulativeElectricEnergy");

  // Only apply coefficient if it's available
  if (coefficient !== undefined) {
    const precision = Math.max(0, -Math.floor(Math.log10(coefficient)));

    return {
      ...payload,
      native_value: "float",
      suggested_display_precision: precision,
      value_template: `
{% if value | ${nativeValue}(default=None) is not none %}
  {{ (value | ${nativeValue}) * ${coefficient} }}
{% else %}
  None
{% endif %}
`.trim(),
    };
  }

  // If coefficient is not available, don't apply transformation
  // This shouldn't happen as unitForCumulativeElectricEnergy is required by spec
  return payload;
}
