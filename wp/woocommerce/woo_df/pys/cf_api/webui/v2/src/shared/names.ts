export function shortName(full: string, zone: string): string {
  if (!zone) return full;
  const lower = full.toLowerCase();
  const zoneLower = zone.toLowerCase();
  if (lower === zoneLower) return "@";
  const suffix = `.${zoneLower}`;
  if (lower.endsWith(suffix)) return full.slice(0, full.length - suffix.length);
  return full;
}

export function zoneSuffix(full: string, zone: string): string {
  if (!zone) return "";
  const short = shortName(full, zone);
  if (short === "@" || short === full) return "";
  return `.${zone}`;
}

/** 与后端 canon_name 一致：短名补 zone 后缀，@ 展开为根域名。 */
export function fullName(name: string, zone: string): string {
  const short = name.trim();
  if (!short || short === "@") return zone;
  if (!zone) return short;
  const low = short.toLowerCase();
  const zoneLow = zone.toLowerCase();
  if (low === zoneLow || low.endsWith(`.${zoneLow}`)) return short;
  if (!short.includes(".")) return `${short}.${zone}`;
  return short;
}
