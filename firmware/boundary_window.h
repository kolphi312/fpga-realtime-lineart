#ifndef BOUNDARY_WINDOW_H
#define BOUNDARY_WINDOW_H
#include "pipeline_driver.h"
/* Version 2 telemetry (flags bit 11). No changed sensor/clock/threshold.
 * A counter transition brackets the LAST completed capture in (old.t,new.t].
 * For two such transitions, elapsed is in [end.lo-start.hi,end.hi-start.lo].
 * Atomic snapshot count and ticks are sampled together by the existing RTL.
 * Bounds use nominal SYS_HZ; they do not calibrate the oscillator. */
typedef struct {
 pipeline_snapshot last;
 uint64_t start_lo,start_hi,end_hi,dt_min,dt_max;
 uint32_t have,last_source,source_base,have_source,source_done;
 uint32_t started,done,invalid,first_count,frames,error_base,errors,skipped;
} boundary_window;
static void boundary_source(boundary_window*m,const pipeline_source_snapshot*p,uint32_t hz){
 if(m->source_done||m->invalid)return;
 if(!hz||(uint32_t)(p->admitted+p->skipped)!=p->observed){m->invalid=1;return;}
 if(!m->started){m->source_base=p->skipped;m->have_source=1;}
 m->last_source=p->skipped;m->skipped=p->skipped-m->source_base;
 /* End source accounting one whole nominal second after the capture endpoint.
  * This is a wider, independently timestamped source window, not an equality
  * assertion between raw/capture counters. Startup skips are excluded. */
 if(m->done&&p->ticks>=m->end_hi&&(p->ticks-m->end_hi)>=hz)m->source_done=1;
}
static void boundary_sample(boundary_window*m,const pipeline_snapshot*p,uint32_t hz){
 uint32_t step;
 if(m->done||m->invalid)return;
 if(!hz){m->invalid=1;return;}
 if(!m->have){m->last=*p;m->have=1;return;}
 if(p->ticks<=m->last.ticks){m->invalid=1;return;}
 step=p->captured-m->last.captured;
 if(step>120u){m->invalid=1;return;} /* reset/backward/implausible jumps */
 if(step&&m->have_source&&p->ticks>=2u*(uint64_t)hz&&p->captured>=2u){
  if(!m->started){
   m->start_lo=m->last.ticks;m->start_hi=p->ticks;m->first_count=p->captured;
   m->error_base=m->last.errors;m->started=1;
  }else{
   m->frames=p->captured-m->first_count;
   if(m->frames>=3600u){
    if(m->last.ticks<=m->start_hi){m->invalid=1;return;}
    m->dt_min=m->last.ticks-m->start_hi;m->dt_max=p->ticks-m->start_lo;
    m->end_hi=p->ticks;m->errors=p->errors-m->error_base;m->done=1;
   }
  }
 }
 m->last=*p;
}
static uint32_t boundary_flags(const boundary_window*m){
 uint32_t f=0x800u;
 if(m->done)f|=1u;
 if(m->source_done)f|=2u;
 if(m->invalid)f|=4u;
 if(m->skipped)f|=8u;
 if(m->errors)f|=16u;
 if(m->frames>4095u||m->skipped>4095u||m->errors>4095u)f|=512u;
 return f;
}
static uint32_t boundary_value(const boundary_window*m,uint32_t page){
 uint32_t v;page&=15u;
 if(page==0)v=boundary_flags(m);
 else if(page==1)v=m->frames;
 else if(page<=7)v=m->done?(uint32_t)(m->dt_max>>((page-2u)*12u))&4095u:0;
 else if(page<=13)v=m->done?(uint32_t)(m->dt_min>>((page-8u)*12u))&4095u:0;
 else if(page==14)v=m->skipped;
 else v=m->errors;
 return v>4095u?4095u:v;
}
static uint32_t boundary_gpio(const boundary_window*m,uint32_t page,uint32_t completed){
 return (((page&15u)<<12)|boundary_value(m,page))<<8|2u|((completed&1u)<<2);
}
#endif
