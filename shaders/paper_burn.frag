#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uSeed;
uniform float uFront;
uniform float uTime;
uniform float uMode;
uniform vec3 uChar;
uniform vec3 uScorch;
// Margin around the sheet that holds its shadow; scorch stays on paper.
uniform float uInset;

out vec4 fragColor;

// Same grain helpers as wabi_sabi.frag: stable across repaints.
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
  for (int i = 0; i < 5; i++) {
    value += amplitude * noise(p);
    p = turn * p * 2.06 + vec2(13.2, 7.1);
    amplitude *= .48;
  }
  return value;
}

// Logical pixels ahead of the flame front; negative values are consumed.
// The sweep runs diagonally from the top-left corner, so the lines read
// first burn first. Noise is in absolute pixels so short and long notes
// share the same ragged edge.
float field(vec2 pixel) {
  vec2 p = pixel / 150.0 + uSeed;
  float coarse = fbm(p) - .5;
  float fine = noise(pixel / 18.0 + uSeed.yx) - .5;
  return pixel.y + pixel.x * .35 + coarse * 150.0 + fine * 14.0 - uFront;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  float d = field(pixel);

  if (uMode < .5) {
    // Alpha mask for the sheet and its words.
    float alpha = smoothstep(0.0, 2.5, d);
    fragColor = vec4(alpha);
    return;
  }

  vec2 inner = min(pixel - uInset, uSize - uInset - pixel);
  float paper = step(0.0, min(inner.x, inner.y));
  float near = smoothstep(-8.0, 0.0, min(inner.x, inner.y));

  float flicker = .65 + .35 * noise(pixel / 22.0 + vec2(uTime * 3.1, -uTime * 2.3));

  // Paper browns well ahead of the flames, unevenly.
  float stain = fbm(pixel / 40.0 + uSeed.yx + 3.0);
  float scorch = (1.0 - smoothstep(4.0, 95.0 + stain * 50.0, d)) * step(0.0, d);
  scorch *= (.55 + .45 * stain) * paper;
  // A thin, brittle black rim right before the edge.
  float charred = (1.0 - smoothstep(1.5, 11.0 + stain * 8.0, d)) * step(-.5, d) * paper;

  vec4 color = vec4(uScorch, 1.0) * scorch * .62;
  color = mix(color, vec4(uChar, 1.0), charred * .92);

  // The glowing edge straddles the front and overhangs the consumed side.
  float ember = exp(-abs(d + 1.5) / 3.2) * flicker;
  float halo = exp(-abs(d + 3.0) / 11.0) * .45 * flicker;
  vec3 hot = mix(vec3(1.0, .30, .05), vec3(1.0, .86, .45), ember);
  float glow = clamp(ember + halo, 0.0, 1.0) * near;
  color = color * (1.0 - glow) + vec4(hot * glow, glow);

  // Pinholes of glowing paper inside the char band.
  float holes = smoothstep(.72, .86, noise(pixel / 7.0 + uSeed * 3.0 + uTime * .4));
  holes *= (1.0 - smoothstep(2.0, 24.0, d)) * step(0.0, d) * flicker * paper;
  color = color * (1.0 - holes) + vec4(vec3(1.0, .55, .15) * holes, holes);

  fragColor = color;
}
