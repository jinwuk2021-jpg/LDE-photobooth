#version 460 core
// Skin smoothing for stills: surface blur (gaussian + colour-distance
// fallback), applied only
// where the face mask is on AND the pixel looks like skin. Runs once per
// photo, before the film look (so the film grain sits on top and the skin
// does not look plastic).

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;          // 0,1  output size in px
uniform float uStrength;     // 2    0..1
uniform sampler2D uTexture;  // photo
uniform sampler2D uBlur;     // the photo, gaussian-blurred at ~1/40 of the face width
uniform sampler2D uMask;     // face mask (white = face skin, holes for eyes / brows / lips)

out vec4 fragColor;

// Soft YCbCr skin-tone gate (covers light to dark skin; rejects most hair,
// sky, foliage and saturated clothes).
float skinTone(vec3 c) {
  float y  = dot(c, vec3(0.299, 0.587, 0.114));
  float cb = 0.5 + dot(c, vec3(-0.168736, -0.331264, 0.5));
  float cr = 0.5 + dot(c, vec3(0.5, -0.418688, -0.081312));
  float gCb = smoothstep(0.27, 0.31, cb) * (1.0 - smoothstep(0.50, 0.54, cb));
  float gCr = smoothstep(0.51, 0.54, cr) * (1.0 - smoothstep(0.69, 0.73, cr));
  float gY  = smoothstep(0.08, 0.16, y);
  return gCb * gCr * gY;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec3 c = texture(uTexture, uv).rgb;
  float m = texture(uMask, uv).r * uStrength;
  if (m < 0.004) {
    fragColor = vec4(c, 1.0);
    return;
  }
  m *= skinTone(c);

  // Surface blur: take the blurred colour where it is close to the pixel
  // (blemishes, pores, uneven tone), back off where it differs a lot (a
  // shadow edge the mask did not cut out).
  vec3 b = texture(uBlur, uv).rgb;
  vec3 d = c - b;
  float w = exp(-dot(d, d) / (2.0 * 0.22 * 0.22));
  // Keep a little of the original texture so skin still looks like skin.
  vec3 outc = mix(c, b + d * 0.2, clamp(m * w, 0.0, 1.0));
  fragColor = vec4(outc, 1.0);
}
