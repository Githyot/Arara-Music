#version 440
// Compiled to fade.frag.qsb with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o fade.frag.qsb fade.frag
// Fades the top and bottom edges of a layer to transparent (lyrics scrolling
// out of view dissolve instead of being cut by the edge).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fadeTop;
    float fadeBottom;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float y = qt_TexCoord0.y;
    float k = smoothstep(0.0, max(fadeTop, 0.0001), y) * (1.0 - smoothstep(1.0 - max(fadeBottom, 0.0001), 1.0, y));
    fragColor = texture(source, qt_TexCoord0) * k * qt_Opacity;
}
