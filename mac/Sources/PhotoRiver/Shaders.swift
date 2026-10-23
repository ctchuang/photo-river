// Metal shaders, compiled at launch with MTLDevice.makeLibrary(source:) so the build needs no Xcode `metal` tool.
// The structs here must match FrameU, Particle and CardU in Renderer.swift.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Frame { float4x4 view; float4x4 proj; float4x4 viewProj; float time; float starTime; float pixelRatio; float pad; };
struct Particle { float4 posPhase; float4 sizeSpeed; };
struct CardU { float4x4 model; float2 size; float opacity; float glow; float radius; float refl; float dim; float pad; };

struct MeshOut { float4 pos [[position]]; float2 uv; };
struct PointOut { float4 pos [[position]]; float size [[point_size]]; float alpha; };

static float gmod(float x, float y) { return x - y * floor(x / y); }

// ---------- background: navy gradient with a soft glow behind the river ----------
vertex MeshOut bg_vertex(uint vid [[vertex_id]]) {
  float2 p = float2(float((vid << 1) & 2), float(vid & 2));
  MeshOut o; o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(p.x, 1.0 - p.y); return o;
}
fragment float4 bg_fragment(MeshOut in [[stage_in]]) {
  float t = in.uv.y;
  float3 top = float3(12, 24, 56) / 255.0, mid = float3(5, 10, 24) / 255.0, bot = float3(2, 4, 10) / 255.0;
  float3 col = t < 0.52 ? mix(top, mid, t / 0.52) : mix(mid, bot, (t - 0.52) / 0.48);
  float d = length((in.uv - float2(0.5, 0.56)) / float2(1.2, 0.6));
  col = mix(col, float3(60, 100, 180) / 255.0, 0.16 * max(0.0, 1.0 - d / 0.6));
  return float4(col, 1.0);
}

// ---------- unit quads (water, cards) ----------
vertex MeshOut mesh_vertex(uint vid [[vertex_id]], constant Frame &f [[buffer(1)]], constant float4x4 &model [[buffer(2)]]) {
  float2 c = float2(float(vid & 1), float((vid >> 1) & 1));
  MeshOut o; o.pos = f.viewProj * model * float4(c - 0.5, 0.0, 1.0); o.uv = c; return o;
}

fragment float4 water_fragment(MeshOut in [[stage_in]], constant Frame &f [[buffer(0)]]) {
  float t = in.uv.y;
  float3 col = mix(float3(3, 6, 14) / 255.0, float3(11, 22, 49) / 255.0, pow(t, 0.55));
  float r = sin(in.uv.x * 900.0 + f.time * 0.6 + sin(in.uv.y * 400.0 + f.time * 0.4) * 2.0) * 0.5 + 0.5;
  col += r * 0.012 * (1.0 - t);
  return float4(col, 1.0);
}

static float roundedBox(float2 p, float2 b, float r) { float2 q = abs(p) - b + r; return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r; }

fragment float4 card_fragment(MeshOut in [[stage_in]], constant CardU &u [[buffer(0)]],
                              texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
  float2 p = (in.uv - 0.5) * u.size;
  float d = roundedBox(p, u.size * 0.5, u.radius);
  float aa = fwidth(d) * 1.4;
  float inside = 1.0 - smoothstep(0.0, aa, d);
  float4 c = tex.sample(s, float2(in.uv.x, 1.0 - in.uv.y));
  float vig = smoothstep(1.0, 0.3, length(in.uv - 0.5) * 1.15);
  c.rgb *= mix(0.82, 1.0, vig) * u.dim;
  float ring = 1.0 - smoothstep(0.0, 0.035 + aa, abs(d + 0.012));
  c.rgb = mix(c.rgb, float3(1.0), ring * u.glow);
  c.rgb += float3(0.06) * smoothstep(0.4, 0.0, in.uv.y) * (1.0 - u.refl);
  float a = inside * u.opacity;
  if (u.refl > 0.5) a *= (1.0 - in.uv.y) * (1.0 - in.uv.y) * 0.105;
  return float4(c.rgb, a);
}

// ---------- points: twinkling stars and drifting dust (bokeh) ----------
vertex PointOut star_vertex(uint vid [[vertex_id]], const device Particle *ps [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
  Particle q = ps[vid];
  float size = q.sizeSpeed.x;
  float tw = 0.65 + 0.35 * sin(f.starTime * (0.6 + size * 0.5) + q.posPhase.w);
  PointOut o; o.pos = f.viewProj * float4(q.posPhase.xyz, 1.0); o.size = size * f.pixelRatio * tw * 1.6; o.alpha = tw; return o;
}
fragment float4 star_fragment(PointOut in [[stage_in]], float2 pc [[point_coord]]) {
  float a = smoothstep(0.5, 0.1, length(pc - 0.5));
  return float4(0.85, 0.9, 1.0, a * in.alpha * 0.9);
}

vertex PointOut dust_vertex(uint vid [[vertex_id]], const device Particle *ps [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
  Particle q = ps[vid];
  float3 p = q.posPhase.xyz; float phase = q.posPhase.w;
  p.x = gmod(p.x - f.time * q.sizeSpeed.y + 35.0, 70.0) - 35.0;
  p.y += sin(f.time * 0.3 + phase) * 0.35;
  float4 mv = f.view * float4(p, 1.0);
  PointOut o; o.pos = f.proj * mv; o.size = q.sizeSpeed.x * f.pixelRatio * (14.0 / -mv.z); o.alpha = 0.5 + 0.5 * sin(f.time * 0.5 + phase); return o;
}
fragment float4 dust_fragment(PointOut in [[stage_in]], float2 pc [[point_coord]]) {
  float a = smoothstep(0.5, 0.0, length(pc - 0.5));
  return float4(0.75, 0.85, 1.0, a * 0.16 * in.alpha);
}
"""
