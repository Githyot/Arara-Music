#version 440
// Compiled to circle.frag.qsb with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o circle.frag.qsb circle.frag
// Circular avatar mask with a 1px anti-aliased edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D src;
void main() {
    vec2 d = qt_TexCoord0 - vec2(0.5);
    float r = length(d);
    float aa = fwidth(r);
    float a = 1.0 - smoothstep(0.5 - aa, 0.5, r);
    fragColor = texture(src, qt_TexCoord0) * a * qt_Opacity;
}
