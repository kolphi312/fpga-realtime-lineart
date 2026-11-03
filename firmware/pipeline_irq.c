#include "pipeline_irq.h"
static void barrier(void){
#ifdef __riscv
 __asm__ volatile("fence iorw,iorw":::"memory");
#else
 __asm__ volatile("":::"memory");
#endif
}
static int read_reg(const pipeline_device*d,uint32_t a,uint32_t*v){int e=d->read(d->context,a,v);barrier();return e?PIPE_EIO:0;}
static int write_reg(const pipeline_device*d,uint32_t a,uint32_t v){int e=d->write(d->context,a,v);barrier();return e?PIPE_EIO:0;}
static void fail(pipeline_irq_context*c,int e){
 if(!c->error)c->error=e;
 /* Mask first: a persistent FAULT event cannot be cleared by W1C. */
 (void)write_reg(c->plic,PLIC_ENABLE,0);
 (void)pipeline_irq_mask(c->video,0);
 (void)pipeline_stop(c->video);
}
static int finish(pipeline_irq_context*c,uint32_t id){
 /* Every successful nonzero claim must be completed, including fatal ones. */
 if(write_reg(c->plic,PLIC_CLAIM,id)){fail(c,PIPE_EIO);return PIPE_EIO;}
 return 0;
}
int pipeline_irq_init(pipeline_irq_context*c,const pipeline_device*v,const pipeline_device*p){
 uint32_t s,readback;
 if(!c||!v||!v->read||!v->write||!p||!p->read||!p->write)return PIPE_EINVAL;
 *c=(pipeline_irq_context){0};c->video=v;c->plic=p;
 if(write_reg(p,PLIC_ENABLE,0)||pipeline_irq_mask(v,0)){fail(c,PIPE_EIO);return c->error;}
 if(read_reg(v,P_STATUS,&s)){fail(c,PIPE_EIO);return c->error;}
 if((s&(P_RUNNING|P_BUSY|P_DONE|P_FAULT))||!(s&P_IDLE)){fail(c,IRQ_ECONFIG);return c->error;}
 if(write_reg(v,P_IRQ_STATUS,7)||write_reg(p,PLIC_PRIORITY,1)||write_reg(p,PLIC_THRESHOLD,0)){
  fail(c,PIPE_EIO);return c->error;
 }
 /* Discard stale gateway state only while the source is masked and idle. */
 for(unsigned i=0;i<8;i++){
  uint32_t id;
  if(read_reg(p,PLIC_CLAIM,&id)){fail(c,PIPE_EIO);return c->error;}
  if(!id)break;
  if(finish(c,id))return c->error;
  if(id!=VIDEO_IRQ||i==7){fail(c,id!=VIDEO_IRQ?IRQ_EUNEXPECTED:IRQ_ESTORM);return c->error;}
 }
 if(pipeline_irq_mask(v,5)||write_reg(p,PLIC_ENABLE,1u<<VIDEO_IRQ)){fail(c,PIPE_EIO);return c->error;}
 if(read_reg(p,PLIC_PRIORITY,&readback)||readback!=1||read_reg(p,PLIC_THRESHOLD,&readback)||readback!=0||
    read_reg(p,PLIC_ENABLE,&readback)||readback!=(1u<<VIDEO_IRQ)||read_reg(v,P_IRQ_MASK,&readback)||readback!=5){
  fail(c,IRQ_ECONFIG);return c->error;
 }
 return PIPE_OK;
}
int pipeline_irq_start(pipeline_irq_context*c,pipeline_job*out){
 if(!c||!out)return PIPE_EINVAL;
 if(c->error)return c->error;
 if(c->active||c->ready)return PIPE_EBUSY;
 int e=pipeline_start(c->video,out);
 if(e==PIPE_OK){c->expected=out->id;barrier();c->active=1;}
 return e;
}
int pipeline_irq_take(pipeline_irq_context*c,pipeline_result*out){
 if(!c||!out)return PIPE_EINVAL;
 if(c->error)return c->error;
 if(!c->ready)return PIPE_PENDING;
 *out=c->result;barrier();c->ready=0;return PIPE_OK;
}
int pipeline_irq_watchdog(pipeline_irq_context*c,uint64_t elapsed,uint64_t limit){
 if(!c||!limit)return PIPE_EINVAL;
 if(c->error)return c->error;
 if(c->active&&!c->ready&&elapsed>=limit)fail(c,IRQ_ETIMEOUT);
 return c->error;
}
void pipeline_irq_service(pipeline_irq_context*c){
 if(c->error)return;
 for(unsigned attempt=0;attempt<8;attempt++){
  uint32_t id,events;
  if(read_reg(c->plic,PLIC_CLAIM,&id)){fail(c,PIPE_EIO);return;}
  if(!id){c->empty++;return;}
  c->claims++;c->last_claim=id;
  if(id!=VIDEO_IRQ){c->unexpected++;fail(c,IRQ_EUNEXPECTED);(void)finish(c,id);return;}
  if(read_reg(c->video,P_IRQ_STATUS,&events)){fail(c,PIPE_EIO);(void)finish(c,id);return;}
  if(events&4u){fail(c,PIPE_EFAULT);(void)finish(c,id);return;}
  if(events&1u){
   pipeline_result r={0};
   if(!c->active||c->ready){fail(c,IRQ_EORPHAN);(void)finish(c,id);return;}
   int e=pipeline_collect(c->video,c->expected,&r);
   if(e!=PIPE_OK){fail(c,e==PIPE_PENDING?IRQ_EORPHAN:e);(void)finish(c,id);return;}
   c->result=r;c->active=0;barrier();c->ready=1;
  }
  /* A delayed/spurious gateway claim with no enabled event is harmless;
   * display-only events are intentionally left for foreground diagnostics. */
  if(finish(c,id))return;
 }
 fail(c,IRQ_ESTORM);
}
