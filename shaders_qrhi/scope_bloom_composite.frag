#version 440
layout(location=0) in vec2 v_uv; layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform Engine { vec4 uTimeRes; vec4 uA; vec4 uB; vec4 uC; vec4 uBg; vec4 uFg1; vec4 uFg2; };
layout(binding=2) uniform sampler2D u_tex; layout(binding=3) uniform sampler2D u_bloom;
layout(std140,binding=1) uniform Params { vec4 _p[3]; };
void main(){ vec4 a=texture(u_tex,v_uv), b=texture(u_bloom,v_uv); fragColor=vec4(a.rgb+b.rgb*clamp(_p[0].x,0.0,2.0),max(a.a,b.a)); }
