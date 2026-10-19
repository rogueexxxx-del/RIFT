#version 440
layout(location=0) in vec2 v_uv;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform Engine {
    vec4 uTimeRes; vec4 uA; vec4 uB; vec4 uC;
    vec4 uBg; vec4 uFg1; vec4 uFg2;
};
layout(binding=2) uniform sampler2D u_tex;
layout(binding=3) uniform sampler2D u_audio_texture;
layout(binding=5) uniform sampler2D u_lut_tex;
layout(binding=6) uniform sampler2D u_feedback_tex;
layout(std140,binding=1) uniform Params { vec4 _p[4]; };
#define mode _p[0].x
#define gain _p[0].y
#define thickness _p[0].z
#define glow _p[0].w
#define decay _p[1].x
#define rotation _p[1].y
#define zoom _p[1].z
#define triggerLevel _p[1].w
#define holdoff _p[2].x
#define colorMode _p[2].y
#define gridOn _p[2].z
#define quality _p[2].w
#define bloomRadius _p[3].x
#define background _p[3].y

float audio(float x, float row) {
    return texture(u_audio_texture, vec2(clamp(x,0.0,1.0),row)).r*2.0-1.0;
}
float cubic(float x, float row) {
    float p=clamp(x,0.0,1.0)*1023.0;
    float i=floor(p), t=fract(p);
    float a=audio((i-1.0)/1023.0,row), b=audio(i/1023.0,row);
    float c=audio((i+1.0)/1023.0,row), d=audio((i+2.0)/1023.0,row);
    return 0.5*((2.0*b)+(-a+c)*t+(2.0*a-5.0*b+4.0*c-d)*t*t+(-a+3.0*b-3.0*c+d)*t*t*t);
}
vec2 stereo(float t) {
    float side=cubic(t,0.625), mid=cubic(t,0.875);
    return vec2(mid+side,mid-side)*0.70710678;
}
float segmentDistance(vec2 p, vec2 a, vec2 b) {
    vec2 q=p-a, d=b-a;
    return length(q-d*clamp(dot(q,d)/max(dot(d,d),1e-7),0.0,1.0));
}
float beam(vec2 p, vec2 a, vec2 b, float width, float speedValue) {
    float d=segmentDistance(p,a,b);
    float sigma=max(width,1.0/min(uTimeRes.z,uTimeRes.w));
    float core=exp(-0.5*d*d/(sigma*sigma));
    return core*mix(1.0,0.45,smoothstep(0.0,0.018,speedValue));
}
vec3 ink(float t, float amp) {
    float mapValue=colorMode<0.5 ? amp : fract(t);
    vec4 custom=texture(u_lut_tex,vec2(mapValue,0.0625));
    if(custom.a>0.01) return custom.rgb;
    vec3 cyan=vec3(0.30,0.88,0.98), lime=vec3(0.78,1.0,0.54);
    if(colorMode<0.5) return vec3(0.45,0.92,1.0);
    return mix(cyan,lime, colorMode<1.5 ? fract(t) : clamp(amp,0.0,1.0));
}
void main() {
    vec2 uv=vec2(v_uv.x,1.0-v_uv.y);
    vec2 p=(uv-0.5)*vec2(uTimeRes.z/uTimeRes.w,1.0);
    float z=max(zoom,0.1);
    float c=cos(rotation), s=sin(rotation);
    p=mat2(c,-s,s,c)*p/z;
    float width=max(thickness,0.1)*0.0015;
    int steps=int(mix(16.0,64.0,clamp(quality,0.0,1.0)));
    float energy=0.0, amp=0.0;
    vec3 trace=vec3(0.0);
    if(mode<0.5) {
        float t=clamp(uv.x+uC.z,0.0,1.0);
        float y=cubic(t,0.375)*gain*0.42;
        float d=abs(p.y-y);
        float sigma=max(width,1.0/min(uTimeRes.z,uTimeRes.w));
        float v=exp(-0.5*d*d/(sigma*sigma));
        energy=v;
        amp=abs(y)*2.0;
        trace=ink(t,amp)*v;
    } else {
        vec2 prev=mode<1.5 ? stereo(0.0) : vec2(cos(0.0),sin(0.0))*cubic(0.0,0.375);
        for(int i=1;i<=96;i++) {
            if(i>steps) break;
            float t=float(i)/float(steps);
            vec2 cur;
            if(mode<1.5) cur=stereo(t);
            else { float a=t*6.2831853; cur=vec2(cos(a),sin(a))*cubic(t,0.375); }
            vec2 a=prev*0.40*gain, b=cur*0.40*gain;
            float e=beam(p,a,b,width,length(b-a));
            energy=max(energy,e);
            trace=max(trace,ink(t,max(abs(cur.x),abs(cur.y)))*e);
            amp=max(amp,max(abs(cur.x),abs(cur.y)));
            prev=cur;
        }
    }
    float graticule=0.0;
    if(gridOn>0.5) {
        vec2 g=fract((uv-0.5)*10.0+0.5);
        graticule=max(1.0-smoothstep(0.0,0.018,min(g.x,1.0-g.x)),1.0-smoothstep(0.0,0.018,min(g.y,1.0-g.y)));
    }
    vec3 bg=vec3(0.0);
    bg=mix(bg,vec3(0.10),graticule*0.20);
    vec2 px=1.0/max(uTimeRes.zw,vec2(1.0));
    vec4 old=texture(u_feedback_tex,uv)*0.5;
    old+=(texture(u_feedback_tex,uv+vec2(px.x,0.0))+texture(u_feedback_tex,uv-vec2(px.x,0.0))
         +texture(u_feedback_tex,uv+vec2(0.0,px.y))+texture(u_feedback_tex,uv-vec2(0.0,px.y)))*0.125;
    float trail=clamp(decay,0.0,0.995);
    vec3 persisted=old.rgb*trail;
    vec3 current=trace*max(glow,0.0);
    vec3 color=max(persisted,current+bg);
    float alpha=background>0.5 ? 1.0 : max(old.a*trail,clamp(energy+graticule*0.2,0.0,1.0));
    fragColor=vec4(color,alpha);
}
