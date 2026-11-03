/* Integration candidate: PLIC16 completion/fault ISR. Foreground retains
 * telemetry; IRQ-disabled build is a distinct polling diagnostic image.
 * Hand-designed dual-polarity Laplacian line-art CNN; NOT trained weights. */
#include "pipeline_driver.h"
#include "pipeline_irq.h"
#include "camera_platform.h"
#include "halt_diag.h"
#include "timeout_diag.h"
#include "performance_window.h"
#include "boundary_window.h"
static boundary_window boundary;
volatile uint32_t legacy_metric_word; /* Preserve original window for debugger audit. */
static perf_window performance;
static timeout_snapshot timeout_info;
#ifndef USE_VIDEO_IRQ
#define USE_VIDEO_IRQ 1
#endif
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define BASE 0xf8101000u
#define GPIO 0xf8015000u
volatile struct {uint32_t magic,state,error,completed,last_id,hz,raw_mfps,observed,admitted,skipped;pipeline_rates rates;} app_status;
volatile struct {uint32_t cause,pc,value;} trap_status;
static int mm_read(void*c,uint32_t a,uint32_t*v){(void)c;*v=REG(BASE+a);__asm__ volatile("fence iorw,iorw":::"memory");return 0;}
static int mm_write(void*c,uint32_t a,uint32_t v){(void)c;REG(BASE+a)=v;return 0;}
static const pipeline_device dev={0,mm_read,mm_write};
static int plic_read(void*c,uint32_t a,uint32_t*v){(void)c;*v=REG(PLIC_BASE+a);__asm__ volatile("fence iorw,iorw":::"memory");return 0;}
static int plic_write(void*c,uint32_t a,uint32_t v){(void)c;REG(PLIC_BASE+a)=v;__asm__ volatile("fence iorw,iorw":::"memory");return 0;}
static const pipeline_device plic={0,plic_read,plic_write};
pipeline_irq_context video_irq;
static uint32_t irq_save(void){uint32_t old;__asm__ volatile("csrrci %0,mstatus,8":"=r"(old)::"memory");return old;}
static void irq_restore(uint32_t old){if(old&8u)__asm__ volatile("csrsi mstatus,8":::"memory");}
static const int32_t coeff[27]={0,-1,0,-1,4,-1,0,-1,0,0,1,0,1,-4,1,0,1,0,0,0,256,256,-512,-512,-2048,-2048,63488};
static void halt(uint32_t why){
 (void)irq_save();__asm__ volatile("csrw mie,zero":::"memory");
 app_status.error=why;app_status.state=0xee;
 REG(GPIO+4)=(why==0x524u && timeout_info.valid)?((timeout_info.code<<8)|0xedu):halt_gpio_word(why);
 (void)pipeline_stop(&dev);for(;;)__asm__ volatile("nop");
}
void platform_trap(uint32_t cause,uint32_t pc,uint32_t value){
 if(USE_VIDEO_IRQ&&cause==0x8000000bu){pipeline_irq_service(&video_irq);return;}
 trap_status.cause=cause;trap_status.pc=pc;trap_status.value=value;halt(0xf0000000u|cause);
}
int main(void){
 uint32_t tries=0,active=0,polls=0,hz;pipeline_job job;pipeline_result result;
 pipeline_snapshot previous,current;
 pipeline_source_snapshot source_previous,source_current;
 pipeline_rates latest_rates={0,0,0};
 uint32_t source_seq=0,source_pending=0,source_seeded=0,source_rate_valid=0,source_stale=0,raw_fps=0,skip_alarm=0,ui_pending=0,rates_valid=0;
 uint64_t source_requested_at=0;
 uint64_t sampled_ticks=0,submit_ticks=0;
 app_status.magic=USE_VIDEO_IRQ?0x42504931u:0x42504d31u;app_status.state=1;REG(GPIO+8)=0xffffffu;REG(GPIO+4)=1;
 /* Board wrapper reads zero MAGIC until DDR calibration/unlock is ready. */
 while(pipeline_probe(&dev)!=0)if(++tries==10000000u)halt(1);
 if(pipeline_load(&dev,coeff)!=0)halt(2);
 if(pipeline_irq_mask(&dev,0)!=0)halt(3);
 if(USE_VIDEO_IRQ&&pipeline_irq_init(&video_irq,&dev,&plic)!=0)halt(14);
 if(mm_read(0,P_HZ,&hz)!=0||hz!=96000000u)halt(4);
 app_status.hz=hz;
 /* Keep video RUN and global MIE clear until sensor ID/config/readback pass. */
 if(camera_platform_initialize()!=0)halt(0x600u+(uint32_t)(-sensor_status.error));
 if(pipeline_sample(&dev,&previous)!=0)halt(5);
 sampled_ticks=previous.ticks;
 if(pipeline_run(&dev,0)!=0)halt(6);
 app_status.state=2;REG(GPIO+4)=2;
 if(USE_VIDEO_IRQ){__asm__ volatile("csrw mie,%0"::"r"(0x800u):"memory");__asm__ volatile("csrsi mstatus,8":::"memory");}
 for(;;){
  int e;
  if(USE_VIDEO_IRQ&&video_irq.error)halt(0x400u+(uint32_t)(-video_irq.error));
  if(active){
   uint32_t saved=irq_save();
   e=USE_VIDEO_IRQ?pipeline_irq_take(&video_irq,&result):pipeline_collect(&dev,job.id,&result);
   irq_restore(saved);
   if(e==PIPE_OK){active=0;app_status.completed++;app_status.last_id=result.id;}
   else if(e!=PIPE_PENDING)halt(0x100u+(uint32_t)(-e));
  }else{
   uint32_t saved=irq_save();
   e=USE_VIDEO_IRQ?pipeline_irq_start(&video_irq,&job):pipeline_start(&dev,&job);
   irq_restore(saved);
   if(e==PIPE_OK){active=1;submit_ticks=sampled_ticks;}else if(e!=PIPE_PENDING)halt(0x200u+(uint32_t)(-e));
  }
  if(++polls==1024){
   polls=0;if(pipeline_sample(&dev,&current)!=0)halt(7);
   boundary_sample(&boundary,&current,hz);
   if(current.ticks<previous.ticks)halt(8);
   sampled_ticks=current.ticks;
   if(USE_VIDEO_IRQ&&active){
    uint32_t saved=irq_save();
    if(current.ticks-submit_ticks>=2u*(uint64_t)hz){
     uint32_t enabled;__asm__ volatile("csrr %0,mie":"=r"(enabled));
     timeout_capture(&timeout_info,&dev,&plic,video_irq.claims,((saved&8u)!=0)&&((enabled&0x800u)!=0));
    }
    e=pipeline_irq_watchdog(&video_irq,current.ticks-submit_ticks,2u*(uint64_t)hz);
    irq_restore(saved);if(e!=PIPE_OK)halt(0x500u+(uint32_t)(-e));
   }
   if(source_pending){
    e=pipeline_source_collect(&dev,source_seq,&source_current);
    if(e==PIPE_OK){
     source_pending=0;source_stale=0;
     if(source_seeded){
      if(pipeline_source_fps(&source_previous,&source_current,hz,&raw_fps)!=0)halt(10);
      if((uint32_t)(source_current.skipped-source_previous.skipped)!=0)skip_alarm=1;
      source_rate_valid=1;ui_pending=1;
     }
     perf_source(&performance,&source_current,hz);
     boundary_source(&boundary,&source_current,hz);
     source_previous=source_current;source_seeded=1;
     app_status.raw_mfps=raw_fps;app_status.observed=source_current.observed;
     app_status.admitted=source_current.admitted;app_status.skipped=source_current.skipped;
    }else if(e!=PIPE_PENDING&&e!=PIPE_EBUSY)halt(11);
    if(source_pending&&current.ticks-source_requested_at>2u*(uint64_t)hz){source_stale=1;performance.invalid=1;raw_fps=0;source_rate_valid=1;ui_pending=1;}
   }
   /* Baseline after first completed frame excludes deliberate startup skips. */
   if(!source_pending&&app_status.completed&&(!source_seeded||current.ticks-source_previous.ticks>=hz)){
    e=pipeline_source_request(&dev,&source_seq);
    if(e==PIPE_OK){source_pending=1;source_requested_at=current.ticks;}
    else if(e!=PIPE_EBUSY)halt(12);
   }
   if(current.ticks-previous.ticks>=app_status.hz){
    pipeline_rates rates;if(pipeline_get_rates(&previous,&current,app_status.hz,&rates)!=0)halt(9);
    perf_system(&performance,&current,hz);
    legacy_metric_word=perf_gpio(&performance,(uint32_t)(current.ticks/hz/2u)&15u,app_status.completed);
    app_status.rates=rates;latest_rates=rates;rates_valid=1;ui_pending=1;previous=current;REG(GPIO+4)=boundary_gpio(&boundary,(uint32_t)(current.ticks/hz/2u)&15u,app_status.completed);
   }
   if(ui_pending&&rates_valid&&source_rate_valid){
    e=pipeline_osd_update(&dev,raw_fps,&latest_rates,skip_alarm||source_stale);
    if(e==PIPE_OK)ui_pending=0;else if(e!=PIPE_EBUSY)halt(13);
   }
  }
 }
}
