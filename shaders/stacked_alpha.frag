#include <flutter/runtime_effect.glsl>

// ImageFilter.shader supplies the input size and video texture.
uniform vec2 uSize;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 colorUV = vec2(uv.x, uv.y * 0.5);
  vec2 alphaUV = vec2(uv.x, uv.y * 0.5 + 0.5);

  vec3 color = texture(uTexture, colorUV).rgb;
  float alpha = texture(uTexture, alphaUV).r;
  fragColor = vec4(color * alpha, alpha);
}
