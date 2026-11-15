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
