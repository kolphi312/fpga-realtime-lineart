#ifndef PERFORMANCE_WINDOW_H
#define PERFORMANCE_WINDOW_H
#include "pipeline_driver.h"
#include <limits.h>
/* Two independently timestamped windows, each >=60 seconds. Freeze first
 * complete window. Their endpoint frame counts are NOT directly comparable.
 * Existing driver uses nominal 96 MHz; external oscillator accuracy is not
 * established by these measurements. No synthetic frames or PASS override. */
typedef struct {
 pipeline_snapshot sys0,last;
 pipeline_source_snapshot src0,src_last;
 uint32_t have_sys,have_src,sys_done,src_done,invalid;
 uint32_t raw_rate,cap_rate,proc_rate,min_proc,seconds;
 uint32_t captured,computed,displayed,observed,admitted,skipped,errors;
} perf_window;
static void perf_system(perf_window*m,const pipeline_snapshot*p,uint32_t hz){
 pipeline_rates r,step;
 if(m->sys_done||m->invalid)return;
 if(!hz){m->invalid=1;return;}
 if(!m->have_sys){m->sys0=*p;m->last=*p;m->have_sys=1;m->min_proc=UINT32_MAX;return;}
 if(pipeline_get_rates(&m->last,p,hz,&step)||pipeline_get_rates(&m->sys0,p,hz,&r)||
    r.capture_mfps>120000u||r.compute_mfps>120000u||r.display_mfps>120000u){m->invalid=1;return;}
 if(step.compute_mfps<m->min_proc)m->min_proc=step.compute_mfps;
 m->last=*p;m->cap_rate=r.capture_mfps;m->proc_rate=r.compute_mfps;
 m->captured=p->captured-m->sys0.captured;m->computed=p->computed-m->sys0.computed;
 m->displayed=p->displayed-m->sys0.displayed;m->errors=p->errors-m->sys0.errors;
 m->seconds=(uint32_t)((p->ticks-m->sys0.ticks)/hz);
 if(p->ticks-m->sys0.ticks>=60u*(uint64_t)hz)m->sys_done=1;
}
static void perf_source(perf_window*m,const pipeline_source_snapshot*p,uint32_t hz){
 uint32_t r;
 if(m->src_done||m->invalid)return;
 if(!hz||(uint32_t)(p->admitted+p->skipped)!=p->observed){m->invalid=1;return;}
 if(!m->have_src){m->src0=*p;m->src_last=*p;m->have_src=1;return;}
 if(p->ticks<=m->src_last.ticks||pipeline_source_fps(&m->src0,p,hz,&r)||r>120000u){m->invalid=1;return;}
 m->raw_rate=r;m->observed=p->observed-m->src0.observed;
 m->admitted=p->admitted-m->src0.admitted;m->skipped=p->skipped-m->src0.skipped;
 m->src_last=*p;
 if(p->ticks-m->src0.ticks>=60u*(uint64_t)hz)m->src_done=1;
}
static uint32_t perf_flags(const perf_window*m){
 uint32_t f=0x400u; /* collecting/present, never confused with empty GPIO */
 if(m->sys_done)f|=1u;
 if(m->src_done)f|=2u;
 if(m->invalid)f|=4u;
 if(m->skipped)f|=8u;
 if(m->errors)f|=16u;
 if(m->src_done&&m->raw_rate<30000u)f|=32u;
 if(m->sys_done&&m->cap_rate<30000u)f|=64u;
 if(m->sys_done&&m->proc_rate<15000u)f|=128u;
 if(m->have_sys&&m->min_proc!=UINT32_MAX&&m->min_proc<15000u)f|=256u;
 if(m->seconds>4095||m->captured>4095||m->computed>4095||m->displayed>4095||
    m->observed>4095||m->admitted>4095||m->skipped>4095||m->errors>4095||
    (m->min_proc!=UINT32_MAX&&m->min_proc/10>4095)||
    m->raw_rate>0xffffff||m->cap_rate>0xffffff||m->proc_rate>0xffffff)f|=512u;
 return f;
}
static uint32_t perf_value(const perf_window*m,uint32_t page){
 uint32_t v;
 switch(page&15u){
 case 0:v=perf_flags(m);break;case 1:v=m->seconds;break;
 case 2:v=m->raw_rate&4095;break;case 3:v=m->raw_rate>>12;break;
 case 4:v=m->cap_rate&4095;break;case 5:v=m->cap_rate>>12;break;
 case 6:v=m->proc_rate&4095;break;case 7:v=m->proc_rate>>12;break;
 case 8:v=m->captured;break;case 9:v=m->computed;break;
 case 10:v=m->observed;break;case 11:v=m->admitted;break;
 case 12:v=m->skipped;break;case 13:v=m->errors;break;
 case 14:v=m->min_proc==UINT32_MAX?0:m->min_proc/10;break;
 default:v=m->displayed;break;
 }
 return v>4095?4095:v;
}
static uint32_t perf_gpio(const perf_window*m,uint32_t page,uint32_t completed){
 return (((page&15u)<<12)|perf_value(m,page))<<8|2u|((completed&1u)<<2);
}
#endif
