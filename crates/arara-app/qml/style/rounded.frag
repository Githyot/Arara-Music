#version 440
// Compiled to rounded.frag.qsb with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o rounded.frag.qsb rounded.frag
// Rounded-square mask for cover art, anti-aliased (Qt Quick's clip is always square).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
};
layout(binding = 1) uniform sampler2D src;
void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 h = size * 0.5;
    float r = min(radius, min(h.x, h.y));
    vec2 q = abs(p - h) - (h - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float a = 1.0 - smoothstep(-0.75, 0.75, d);
    fragColor = texture(src, qt_TexCoord0) * a * qt_Opacity;
}
