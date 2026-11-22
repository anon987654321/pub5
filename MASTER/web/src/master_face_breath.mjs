
/**
 * master_face_breath.mjs
 * Promotes the dot-field settle and breath mechanics into the live stipple system.
 * Respects magic_hex budget: no new colors, only motion, brightness, and air.
 * Wires SETTLE_MS and the solid --solo mark (left eye) into the WebGL render loop.
 */
import { sampleZone, SETTLE_MS, SOLO_PROBABILITY } from '../public/face_zones.mjs';

export function installBreathMechanics(stippleSystem) {
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const settleStart = performance.now();
  
  // Hook into the stipple system's particle update loop
  stippleSystem.addParticleHook((particle, i, time) => {
    const elapsed = time - settleStart;
    const t = reduced ? 1.0 : Math.min(1.0, elapsed / SETTLE_MS);
    
    // Smoothstep ease: t^2(3-2t)
    const ease = t * t * (3 - 2 * t);
    
    // 1. Settle Mechanics: drift from scattered field to face zone
    const target = sampleZone(i, '3d');
    particle.x = particle.sx + (target.x - particle.sx) * ease;
    particle.y = particle.sy + (target.y - particle.sy) * ease;
    particle.z = particle.sz + (target.z - particle.sz) * ease;
    
    // 2. Breath Mechanics: slow scale oscillation on settled dots
    if (t > 0.95) {
      const breathPhase = Math.sin(time * 0.001 + i * 0.01) * 0.02;
      particle.scale = 1.0 + breathPhase;
    }
    
    // 3. Solo Mark: one solid left-eye disc among the stipple
    // Uses existing --solo token, no new colors added.
    if (target.zoneName === "eye" && target.side < 0 && Math.random() < SOLO_PROBABILITY) {
      particle.isSolo = true;
      particle.shape = "square"; // Deliberate contrast against stipple circles
    }
  });
}
