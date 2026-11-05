#version 440
// Compiled to tint.frag.qsb with: qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o tint.frag.qsb tint.frag
// Recolors a symbolic icon: keeps its alpha, replaces the color (like GTK does).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 color;
};
layout(binding = 1) uniform sampler2D src;
void main() {
    float a = texture(src, qt_TexCoord0).a * color.a * qt_Opacity;
    fragColor = vec4(color.rgb * a, a);
}
