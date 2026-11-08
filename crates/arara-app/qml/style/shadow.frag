#version 440
// Compiled to shadow.frag.qsb with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o shadow.frag.qsb shadow.frag
// Soft drop shadow for a rounded rectangle (a real blur look, no stacked rings).
// The item is bigger than the box by `margin` on every side; `offsetY` moves the box down.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // item size in px
    float margin;   // space around the box
    float radius;   // box corner radius
    float blur;     // blur radius in px
    float offsetY;  // box shift down
    float strength; // peak alpha
};
void main() {
    vec2 p = qt_TexCoord0 * size - vec2(0.0, offsetY);
    vec2 h = size * 0.5;
    vec2 bh = h - vec2(margin);
    float r = min(radius, min(bh.x, bh.y));
    vec2 q = abs(p - h) - (bh - vec2(r));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    // gaussian-like falloff around the edge: ~half strength at the edge itself
    float t = clamp((d + blur * 0.5) / (blur * 1.5), 0.0, 1.0);
    float a = (1.0 - t) * (1.0 - t) * (1.0 - t * 0.5);
    a = a * a * (3.0 - 2.0 * a);
    fragColor = vec4(0.0, 0.0, 0.0, 1.0) * a * strength * qt_Opacity;
}
