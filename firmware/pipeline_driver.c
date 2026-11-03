#include "pipeline_driver.h"
#include <limits.h>
static int valid(const pipeline_device*d){return d&&d->read&&d->write;}
static void fence_io(void){
#ifdef __riscv
 __asm__ volatile("fence iorw,iorw" ::: "memory");
#else
 __asm__ volatile("" ::: "memory");
#endif
}
static int rd(const pipeline_device*d,uint32_t a,uint32_t*v){return d->read(d->context,a,v)?PIPE_EIO:0;}
static int wr(const pipeline_device*d,uint32_t a,uint32_t v){int e=d->write(d->context,a,v);fence_io();return e?PIPE_EIO:0;}
int pipeline_probe(const pipeline_device*d){uint32_t v;if(!valid(d))return PIPE_EINVAL;if(rd(d,P_ID,&v))return PIPE_EIO;return v==0x56504950u?0:PIPE_EID;}
int pipeline_load(const pipeline_device*d,const int32_t p[27]){
 uint32_t s;if(!valid(d)||!p)return PIPE_EINVAL;
 for(unsigned i=0;i<27;i++){
  if(i<18&&(p[i]<-128||p[i]>127))return PIPE_EINVAL;
  if((i==18||i==19)&&(p[i]<-8388608||p[i]>8388607))return PIPE_EINVAL;
  if((i==20||i==21||i==24||i==25)&&(p[i]<-32768||p[i]>32767))return PIPE_EINVAL;
 }
 if(rd(d,P_STATUS,&s))return PIPE_EIO;
 if(s&P_FAULT)return PIPE_EFAULT;
 if((s&(P_RUNNING|P_BUSY))||!(s&P_IDLE))return PIPE_EBUSY;
 for(unsigned i=0;i<27;i++)if(wr(d,P_COEFF+4*i,(uint32_t)p[i]))return PIPE_EIO;
 if(rd(d,P_STATUS,&s))return PIPE_EIO;
 return (s&P_CONFIGURED)&&!(s&P_CFG_ERROR)?0:PIPE_EIO;
}
int pipeline_run(const pipeline_device*d,uint32_t limit){
 uint32_t s;if(!valid(d))return PIPE_EINVAL;if(rd(d,P_STATUS,&s))return PIPE_EIO;
 if(s&P_FAULT)return PIPE_EFAULT;
 if((s&(P_RUNNING|P_BUSY))||!(s&P_IDLE))return PIPE_EBUSY;
 if(!(s&P_CONFIGURED))return PIPE_EINVAL;
 if(wr(d,P_LIMIT,limit))return PIPE_EIO;
 return wr(d,P_RUN,1);
}
int pipeline_stop(const pipeline_device*d){return valid(d)?wr(d,P_RUN,0):PIPE_EINVAL;}
int pipeline_start(const pipeline_device*d,pipeline_job*out){
 uint32_t s;pipeline_job j;if(!valid(d)||!out)return PIPE_EINVAL;if(rd(d,P_STATUS,&s))return PIPE_EIO;
 if(s&P_FAULT)return PIPE_EFAULT;
 if(s&(P_BUSY|P_DONE))return PIPE_EBUSY;
 if(!(s&P_CONFIGURED))return PIPE_EINVAL;
 if(!(s&P_QUEUED))return PIPE_PENDING;
 if(rd(d,P_NEXT_ID,&j.id)||rd(d,P_SOURCE,&j.source)||rd(d,P_RESULT,&j.result))return PIPE_EIO;
 if(wr(d,P_START,1))return PIPE_EIO;
 *out=j;return 0;
}
int pipeline_collect(const pipeline_device*d,uint32_t expected,pipeline_result*out){
 uint32_t s;pipeline_result r;if(!valid(d)||!out)return PIPE_EINVAL;if(rd(d,P_STATUS,&s))return PIPE_EIO;
 if(s&P_FAULT)return PIPE_EFAULT;
 if(!(s&P_DONE))return PIPE_PENDING;
 if(rd(d,P_LAST_ID,&r.id)||rd(d,P_REASON,&r.reason)||rd(d,P_CYCLES,&r.cycles))return PIPE_EIO;
 if(r.id!=expected)return PIPE_EID;
 if(wr(d,P_IRQ_STATUS,1))return PIPE_EIO;
 *out=r;return r.reason&16?PIPE_EJOB:0;
}
int pipeline_irq_mask(const pipeline_device*d,uint32_t mask){if(!valid(d)||(mask&~7u))return PIPE_EINVAL;return wr(d,P_IRQ_MASK,mask);}
int pipeline_sample(const pipeline_device*d,pipeline_snapshot*out){
 pipeline_snapshot s;uint32_t lo,hi,last;if(!valid(d)||!out)return PIPE_EINVAL;
 if(wr(d,P_SNAPSHOT,1)||rd(d,P_SNAPSHOT,&s.sequence)||rd(d,0x80,&lo)||rd(d,0x84,&hi)||
 rd(d,0x88,&s.captured)||rd(d,0x8c,&s.computed)||rd(d,0x90,&s.displayed)||rd(d,0x94,&s.repeats)||
 rd(d,0x98,&s.errors)||rd(d,0x9c,&s.last_capture)||rd(d,0xa0,&s.last_compute)||rd(d,0xa4,&s.last_display)||rd(d,P_SNAPSHOT,&last))return PIPE_EIO;
 if(last!=s.sequence)return PIPE_EBUSY;
 s.ticks=((uint64_t)hi<<32)|lo;*out=s;return 0;
}
static int rate(uint32_t before,uint32_t after,uint64_t dt,uint32_t hz,uint32_t*out){
 uint64_t scale=(uint64_t)hz*1000,delta=(uint32_t)(after-before);
 if(delta>UINT64_MAX/scale)return PIPE_EINVAL;
 uint64_t r=delta*scale/dt;if(r>UINT32_MAX)return PIPE_EINVAL;*out=(uint32_t)r;return 0;
}
int pipeline_get_rates(const pipeline_snapshot*a,const pipeline_snapshot*b,uint32_t hz,pipeline_rates*out){
 pipeline_rates r;if(!a||!b||!out||!hz||b->ticks<=a->ticks)return PIPE_EINVAL;
 uint64_t dt=b->ticks-a->ticks;
 if(rate(a->captured,b->captured,dt,hz,&r.capture_mfps)||rate(a->computed,b->computed,dt,hz,&r.compute_mfps)||rate(a->displayed,b->displayed,dt,hz,&r.display_mfps))return PIPE_EINVAL;
 *out=r;return 0;
}
int pipeline_source_request(const pipeline_device*d,uint32_t*out){
 uint32_t status,seq;if(!valid(d)||!out)return PIPE_EINVAL;
 if(rd(d,0x74,&status)||rd(d,0x70,&seq))return PIPE_EIO;
 if(status&1)return PIPE_EBUSY;
 if(wr(d,0x70,1))return PIPE_EIO;
 *out=seq;return 0;
}
int pipeline_source_collect(const pipeline_device*d,uint32_t previous,pipeline_source_snapshot*out){
 uint32_t status,lo,hi,end;pipeline_source_snapshot s;if(!valid(d)||!out)return PIPE_EINVAL;
 if(rd(d,0x74,&status))return PIPE_EIO;
 if((status&3)!=2)return PIPE_PENDING;
 if(rd(d,0x70,&s.sequence))return PIPE_EIO;
 if(s.sequence==previous)return PIPE_PENDING;
 if(rd(d,0xb0,&lo)||rd(d,0xb4,&hi)||rd(d,0xb8,&s.observed)||rd(d,0xbc,&s.admitted)||rd(d,0xc0,&s.skipped)||rd(d,0x70,&end)||rd(d,0x74,&status))return PIPE_EIO;
 if(end!=s.sequence||(status&3)!=2)return PIPE_EBUSY;
 if((uint32_t)(s.admitted+s.skipped)!=s.observed)return PIPE_EIO;
 s.ticks=((uint64_t)hi<<32)|lo;*out=s;return 0;
}
int pipeline_source_fps(const pipeline_source_snapshot*a,const pipeline_source_snapshot*b,uint32_t hz,uint32_t*out){
 if(!a||!b||!out||!hz||b->ticks<=a->ticks)return PIPE_EINVAL;
 return rate(a->observed,b->observed,b->ticks-a->ticks,hz,out);
}
static uint32_t bcd_fps(uint32_t m){uint32_t v=m/1000;if(v>99)v=99;return ((v/10)<<4)|(v%10);}
int pipeline_osd_update(const pipeline_device*d,uint32_t raw,const pipeline_rates*r,int skipped){
 uint32_t ready;if(!valid(d)||!r)return PIPE_EINVAL;
 if(rd(d,0xd4,&ready))return PIPE_EIO;
 if(!(ready&1))return PIPE_EBUSY;
 return wr(d,0xd0,0x80000000u|(skipped?0x40000000u:0)|(bcd_fps(raw)<<16)|(bcd_fps(r->compute_mfps)<<8)|bcd_fps(r->display_mfps));
}
