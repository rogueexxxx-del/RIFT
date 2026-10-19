#version 440
layout(location=0) in vec2 v_uv; layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform Engine { vec4 uTimeRes; vec4 uA; vec4 uB; vec4 uC; vec4 uBg; vec4 uFg1; vec4 uFg2; };
layout(binding=2) uniform sampler2D u_tex;
layout(std140,binding=1) uniform Params { vec4 _p[3]; };
void main(){ vec2 d=vec2(1.0/max(uTimeRes.z,1.0),1.0/max(uTimeRes.w,1.0)); if(_p[0].y>0.5)d.x=0.0; else d.y=0.0; d*=max(_p[0].x,1.0); vec4 c=texture(u_tex,v_uv)*0.227027; c+=(texture(u_tex,v_uv+d*1.384615)+texture(u_tex,v_uv-d*1.384615))*0.316216; c+=(texture(u_tex,v_uv+d*3.230769)+texture(u_tex,v_uv-d*3.230769))*0.070270; fragColor=c; }
