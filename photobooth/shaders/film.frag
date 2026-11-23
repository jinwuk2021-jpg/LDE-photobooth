#version 460 core
// Film look: 3D LUT + halation + grain + vignette + light leak.
// Used both as a live ImageFilter on the preview and offscreen on export.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // 0,1  (set automatically by ImageFilter.shader)
uniform float uLutSize;    // 2
uniform float uGrain;      // 3   0..1
uniform float uGrainSize;  // 4   pixels per grain cell
uniform float uVignette;   // 5   0..1
uniform float uHalation;   // 6   0..1
uniform float uLeak;       // 7   0..1
uniform float uSeed;       // 8
uniform float uMono;       // 9   1 = black & white
uniform float uFast;       // 10  1 = live preview: halation from 4 directions instead of 8 (half the reads)
uniform sampler2D uTexture;  // input (preview / photo)
uniform sampler2D uLut;      // (n*n) x n strip, x = r + b*n, y = g

out vec4 fragColor;

vec3 applyLut(vec3 c) {
  float n = uLutSize;
  c = clamp(c, 0.0, 1.0);
  float b = c.b * (n - 1.0);
  float b0 = floor(b);
  float b1 = min(b0 + 1.0, n - 1.0);
  float f = b - b0;
  float x = (c.r * (n - 1.0) + 0.5) / (n * n);
  float y = (c.g * (n - 1.0) + 0.5) / n;
  vec3 s0 = texture(uLut, vec2(x + b0 / n, y)).rgb;
  vec3 s1 = texture(uLut, vec2(x + b1 / n, y)).rgb;
  return mix(s0, s1, f);
}

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32 + uSeed);
  return fract(p.x * p.y);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec4 src = texture(uTexture, uv);
  vec3 c = src.rgb;

  // Halation: red-orange bloom bleeding from bright light sources.
  if (uHalation > 0.0) {
    vec3 glow = vec3(0.0);
    float r = 0.012 * max(uSize.x, uSize.y);
    float taps = 8.0;
    if (uFast > 0.5) {
      // Same average from the four diagonals: the preview runs this on every camera frame.
      taps = 4.0;
      for (int i = 0; i < 4; i++) {
        float a = float(i) * 1.570796 + 0.785398;
        vec2 o = vec2(cos(a), sin(a)) * r / uSize;
        vec3 s = texture(uTexture, uv + o).rgb;
        vec3 s2 = texture(uTexture, uv + o * 2.2).rgb;
        glow += max(s - 0.78, 0.0) + 0.6 * max(s2 - 0.78, 0.0);
      }
    } else {
      for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398;
        vec2 o = vec2(cos(a), sin(a)) * r / uSize;
        vec3 s = texture(uTexture, uv + o).rgb;
        vec3 s2 = texture(uTexture, uv + o * 2.2).rgb;
        glow += max(s - 0.78, 0.0) + 0.6 * max(s2 - 0.78, 0.0);
      }
    }
    float g = luma(glow) / taps;
    c += vec3(1.0, 0.32, 0.12) * g * 3.2 * uHalation;
  }

  c = applyLut(c);

  // Light leak: a warm wash from one edge, position picked by the seed.
  if (uLeak > 0.0) {
    vec2 origin = vec2(fract(uSeed * 0.37) < 0.5 ? 0.0 : 1.0, fract(uSeed * 0.71));
    float d = distance(uv, origin);
    float leak = smoothstep(0.75, 0.0, d) * uLeak;
    c = mix(c, c + vec3(0.55, 0.22, 0.05), leak);
  }

  // Vignette.
  vec2 v = uv - 0.5;
  float vig = 1.0 - uVignette * smoothstep(0.25, 0.75, dot(v, v) * 1.6);
  c *= vig;

  // Grain: cell noise, strongest in the midtones.
  if (uGrain > 0.0) {
    vec2 cell = floor(frag / max(uGrainSize, 1.0));
    float n = hash(cell) - 0.5;
    float l = luma(c);
    float weight = 1.0 - abs(l - 0.5) * 1.4;
    c += n * uGrain * 0.22 * max(weight, 0.15);
  }

  if (uMono > 0.5) {
    c = vec3(luma(c));
  }

  fragColor = vec4(clamp(c, 0.0, 1.0) * src.a, src.a);
}
