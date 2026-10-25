#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uSeed;
uniform float uDark;
uniform vec3 uPaper;
uniform vec3 uInk;
uniform vec3 uClay;
uniform vec3 uSage;
uniform vec3 uOchre;
uniform vec3 uBloom0;
uniform vec3 uBloom1;
uniform vec3 uBloom2;
uniform vec3 uBloom3;
uniform float uSettle;
uniform vec4 uTiming0;
uniform vec4 uTiming1;
uniform vec4 uTiming2;
uniform vec4 uTiming3;

out vec4 fragColor;

// A hash without trigonometry keeps the grain stable at every repaint.
float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * .1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 cell = floor(p);
  vec2 f = fract(p);
  vec2 w = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(cell), hash(cell + vec2(1, 0)), w.x),
    mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1)), w.x),
    w.y
  );
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = .53;
  const mat2 turn = mat2(.8, -.6, .6, .8);
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = turn * p * 2.06 + vec2(13.2, 7.1);
    amplitude *= .48;
  }
  return value;
}

// Wet edges meander at several scales; concentration gathers inside their
// ragged boundary. There are no geometric rings or stroked paths.
float bloomMask(vec2 p, vec3 bloom, vec2 warp, float salt, float phase,
                float settled) {
  float unit = min(uSize.x, uSize.y);
  vec2 local = (p - bloom.xy / unit) / (bloom.z / unit);
  // Compact opening dabs spread into the full, original silhouette at rest.
  local /= mix(.40, 1.0, settled);
  local += warp * .32;
  float angle = atan(local.y, local.x);
  float edge = .82 + .11 * sin(angle * 3.0 + phase)
    + .07 * sin(angle * 5.0 - phase * .7);
  float distance = length(local * vec2(1.0, 1.06));
  float shore = edge - distance + (salt - .5) * .085;
  float feather = mix(.11, .065, settled);
  return smoothstep(-feather, feather, shore);
}

// A broad brush moves from the outside edge towards the open paper. The
// advancing head has uneven bristles; pixels behind it retain their pigment.
// x is deposited paint, y is the transient, heavily loaded wet brush edge.
vec2 paintPass(vec2 p, vec3 bloom, vec2 warp, float salt, float progress,
               float turn) {
  float unit = min(uSize.x, uSize.y);
  vec2 local = (p - bloom.xy / unit) / (bloom.z / unit);
  vec2 direction = normalize(uSize * .5 - bloom.xy);
  direction = normalize(direction * (1.0 - abs(turn) * .7)
    + vec2(-direction.y, direction.x) * turn);
  vec2 normal = vec2(-direction.y, direction.x);
  float across = dot(local, normal);
  float bristles = .014 * sin(across * 94.0 + uSeed.x)
    + (salt - .5) * .075;
  float bend = .22 * sin(across * 2.8 + uSeed.y) + dot(warp, direction) * .2;
  // Begin just beyond the incoming corner: about 8 px on a 390 px viewport.
  // A little initial velocity lets pigment creep in without a long blank wait.
  vec2 edge = mix(uSize, vec2(0.0), step(vec2(0.0), direction));
  vec2 entry = (edge - bloom.xy) / bloom.z;
  float contact = dot(entry, direction) - unit * .02 / bloom.z;
  float sweep = mix(progress, smoothstep(0.0, 1.0, progress), .65);
  float head = mix(contact, max(contact, 1.55), sweep);
  // Grow the bristle irregularity after contact, keeping the start offscreen.
  float texture = smoothstep(0.0, .12, progress);
  float distance = dot(local, direction) + (bend + bristles) * texture - head;
  float touching = smoothstep(0.0, .015, progress);
  float laid = (1.0 - smoothstep(-.045, .08, distance)) * touching;
  laid = mix(laid, 1.0, smoothstep(.94, 1.0, progress));
  float wet = exp(-abs(distance) * 17.0) * touching
    * (1.0 - smoothstep(.8, 1.0, progress));
  return vec2(laid, wet);
}

// Each color gets an initial wash and a differently angled cross-stroke.
// Scheduling comes from a stable integer seed stream in Dart, not GPU noise.
// x: coverage, y: loaded edge, z: wash progress, w: temporary glaze tint.
vec4 batchedPass(vec2 p, vec3 bloom, vec2 warp, float salt,
                 vec4 timing, float phase) {
  float wash = clamp((uSettle - timing.x) / timing.y, 0.0, 1.0);
  float glaze = clamp((uSettle - timing.z) / timing.w, 0.0, 1.0);
  float turn = hash(vec2(phase, uSeed.y)) < .5 ? -1.0 : 1.0;
  vec2 first = paintPass(p, bloom, warp, salt, wash, 0.0);
  vec2 crossStroke = paintPass(p, bloom, warp, salt, glaze, turn);
  float wet = max(first.y, crossStroke.y * .9);
  float glazeTint = crossStroke.x * (1.0 - smoothstep(.90, 1.0, uSettle));
  return vec4(first.x, wet, wash, glazeTint);
}

vec3 deposit(vec3 base, vec3 pigment, float mask, float pool,
             float mottling, float granules, float pores, float wetEdge) {
  float concentration = (.29 + pool * .42 + mottling * .2) * mask;
  concentration *= mix(.82, 1.0, smoothstep(.65, 1.0, uSettle));
  concentration *= 1.0 + wetEdge * .65;
  concentration *= 1.0 + (granules - .5) * .4;
  vec3 mineral = mix(pigment, pigment * .58, pool * .42);
  mineral = mix(mineral, uPaper, pores * .18);
  vec3 wet = mix(base, mineral, concentration * mix(1.0, .83, uDark));
  // Fine sediment breaks the color up, rather than floating above it as dots.
  wet += (granules - .5) * mask * .042
    * mix(.7, 1.0, smoothstep(.1, 1.0, uSettle));
  return wet;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  float unit = min(uSize.x, uSize.y);
  vec2 p = pixel / unit;
  vec2 seed = uSeed + vec2(2.7, 8.3);
  vec2 flow = vec2(fbm(p * 2.8 + seed), fbm(p * 2.8 + seed.yx + 9.2));
  vec2 warp = vec2(
    fbm(p * 4.2 + flow * 3.8 + seed + 17.1),
    fbm(p * 4.2 + flow * 3.8 + seed.yx + 31.7)
  ) - .5;
  float mottling = fbm(p * 12.0 + warp * 4.0 + seed);
  float salt = noise(p * 145.0 + warp * 7.0 + seed);
  float granules = noise(p * 240.0 + seed);
  float pores = smoothstep(.62, .84, noise(p * 115.0 + seed.yx));
  float pool = smoothstep(.32, .76, mottling);

  // Uneven, overlapping batches, then drying. Completed washes remain while
  // the later passes add pigment; no wrapping or repeating clock is used.
  vec4 strokeA = batchedPass(p, uBloom0, warp, salt, uTiming0, seed.x);
  vec4 strokeB = batchedPass(p, uBloom1, warp.yx, salt, uTiming1, seed.y + 2.1);
  vec4 strokeC = batchedPass(p, uBloom2, -warp, salt, uTiming2, seed.x + 4.3);
  vec4 strokeD = batchedPass(p, uBloom3, -warp.yx, salt, uTiming3, seed.y + 7.6);
  float a = bloomMask(p, uBloom0, warp, salt, seed.x, strokeA.z) * strokeA.x;
  float b = bloomMask(p, uBloom1, warp.yx, salt, seed.y + 2.1, strokeB.z) * strokeB.x;
  float c = bloomMask(p, uBloom2, -warp, salt, seed.x + 4.3, strokeC.z) * strokeC.x;
  float d = bloomMask(p, uBloom3, -warp.yx, salt, seed.y + 7.6, strokeD.z) * strokeD.x;

  vec3 color = uPaper;
  color = deposit(color, mix(mix(uInk, uSage, flow.x * .4), uOchre, strokeA.w * .22), a,
    pool, mottling, granules, pores, strokeA.y);
  color = deposit(color, mix(mix(uClay, uOchre, flow.y * .38), uInk, strokeB.w * .22), b,
    1.0 - pool, mottling, granules, pores, strokeB.y);
  color = deposit(color, mix(mix(uSage, uInk, flow.y * .6), uClay, strokeC.w * .22), c,
    pool, 1.0 - mottling, granules, pores, strokeC.y);
  color = deposit(color, mix(mix(uOchre, uClay, flow.x * .6), uSage, strokeD.w * .22), d,
    1.0 - pool, mottling, granules, pores, strokeD.y);

  // Weathered, pale blooms interrupt the pigment like water lifting a glaze.
  float lift = smoothstep(.59, .78, fbm(p * 8.0 + flow * 5.0 + seed + 70.0));
  color = mix(color, uPaper, lift * .46);

  // Keep a generous pool of empty paper, including on tablet layouts.
  float center = length((pixel - uSize * .5) / (unit * .74));
  float quiet = 1.0 - smoothstep(.06, 1.0, center);
  color = mix(color, uPaper, quiet * .94);

  // Tiny ochre inclusions follow the pigment. They never animate or sparkle.
  vec2 cell = floor(p * 170.0);
  float fleck = step(.994, hash(cell + seed));
  fleck *= 1.0 - smoothstep(.07, .22,
    length(fract(p * 170.0) - vec2(.45, .5)));
  fleck *= max(max(a, b), max(c, d)) * (1.0 - quiet);
  color = mix(color, mix(uOchre, vec3(.75, .61, .36), .6),
    fleck * .48 * smoothstep(.25, 1.0, uSettle));

  // Fine paper tooth remains visible in the unpainted space, too.
  float tooth = hash(floor(pixel) + seed) - .5;
  color += tooth * mix(.025, .016, uDark);
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
