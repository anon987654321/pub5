
/**
 * Shared face zone definitions for MASTER face systems.
 * Resolves the Y-axis inversion between the 2D dot-field prototype (top-negative)
 * and the 3D live stipple system (top-positive).
 */

const ZONE_RANGES = [
  { name: "eye", max: 0.17, zone3d: 1 },
  { name: "brow", max: 0.29, zone3d: 2 },
  { name: "mouth", max: 0.40, zone3d: 3 },
  { name: "nose", max: 0.50, zone3d: 4 },
  { name: "skin", max: 1.0, zone3d: 6 } // 0, 5, 6 mapped to general skin/rim
];

export function sampleZone(i, space = '3d', salt = 1) {
  const rand = (idx, s) => {
    const v = Math.sin(idx * 12.9898 + s * 78.233) * 43758.5453;
    return v - Math.floor(v);
  };

  const q = rand(i, salt);
  const r = rand(i, salt + 1);
  const side = rand(i, salt + 2) < 0.5 ? -1 : 1;

  let x, y, z, zone, zoneName;
  if (q < 0.17) {
    const a = r * Math.PI * 2;
    const radius = 0.18 + rand(i, salt + 3) * 0.105;
    x = side * 0.31 + Math.cos(a) * radius;
    y = 0.17 + Math.sin(a) * radius * 0.56; // 3D top-positive
    z = 0.20 + rand(i, salt + 4) * 0.012;
    zoneName = "eye"; zone = 1;
  } else if (q < 0.29) {
    const a = Math.PI * (0.14 + r * 0.72);
    x = side * (0.30 + r * 0.11);
    y = 0.38 + Math.cos(a) * 0.13;
    z = 0.16;
    zoneName = "brow"; zone = 2;
  } else if (q < 0.40) {
    const a = r * Math.PI * 2;
    x = Math.cos(a) * (0.21 + 0.045 * Math.sin(a * 2));
    y = -0.32 + Math.sin(a) * 0.06;
    z = 0.21 + Math.abs(Math.cos(a)) * 0.012;
    zoneName = "mouth"; zone = 3;
  } else if (q < 0.50) {
    x = (rand(i, salt + 5) - 0.5) * 0.045;
    y = 0.15 - r * 0.48;
    z = 0.23 + r * 0.03;
    zoneName = "nose"; zone = 4;
  } else {
    const xx = r * 2 - 1;
    const yy = rand(i, salt + 6) * 2 - 1;
    const taper = 0.73 - Math.max(0, -yy) * 0.18;
    const edge = Math.sqrt(Math.max(0.04, 1 - xx * xx * 0.82 - yy * yy * 0.56));
    x = xx * taper;
    y = yy * 0.91;
    z = 0.16 * edge + rand(i, salt + 7) * 0.012;
    zoneName = yy > 0.48 ? "hair" : yy < -0.42 ? "chin" : "skin";
    zone = yy > 0.48 ? 0 : yy < -0.42 ? 5 : 6;
  }

  if (space === '2d') {
    // Flip Y for the 2D prototype (top-negative, bottom-positive)
    y = -y + 0.05; // slight offset adjustment to match prototype's -0.12 eye Y
  }

  return { x, y, z: space === '3d' ? z : 0, zone, zoneName, side };
}

export const SETTLE_MS = 5200;
export const SOLO_PROBABILITY = 0.9;
