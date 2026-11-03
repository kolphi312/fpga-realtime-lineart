#ifndef TIMEOUT_DIAG_H
#define TIMEOUT_DIAG_H
#include "pipeline_driver.h"
typedef struct {uint32_t valid,code,status,events,pending,claims,captured,computed,irq_enabled;} timeout_snapshot;
/* Non-destructive reads only; never reads PLIC CLAIM or acknowledges an event.
 * Called with CPU interrupts disabled, BEFORE watchdog masks source/PLIC.
 * Sequential register observations, not an atomic hardware snapshot. */
static inline int timeout_capture(timeout_snapshot *s,const pipeline_device *v,const pipeline_device *p,uint32_t claims,uint32_t enabled){
 *s=(timeout_snapshot){0};s->claims=claims;s->irq_enabled=enabled;
 if(v->read(v->context,P_STATUS,&s->status)||v->read(v->context,P_IRQ_STATUS,&s->events)||
    p->read(p->context,0x1000u,&s->pending)||v->read(v->context,P_CAPTURED,&s->captured)||
    v->read(v->context,P_COMPUTED,&s->computed))return -1;
 s->code=(s->status&255u)|((s->events&7u)<<8)|(((s->pending>>16)&1u)<<11)|
  ((claims!=0u)<<12)|((s->captured!=0u)<<13)|((s->computed!=0u)<<14)|((enabled!=0u)<<15);
 s->valid=1;return 0;
}
#endif
