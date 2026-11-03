#ifndef PIPELINE_IRQ_H
#define PIPELINE_IRQ_H
#include "pipeline_driver.h"
/* Verified against this project's generated SoC, not a generic PLIC map. */
enum { VIDEO_IRQ=16, PLIC_BASE=0xf8c00000u, PLIC_PRIORITY=0x40,
 PLIC_ENABLE=0x2000, PLIC_THRESHOLD=0x200000, PLIC_CLAIM=0x200004 };
enum { IRQ_EUNEXPECTED=-32, IRQ_EORPHAN=-33, IRQ_ESTORM=-34, IRQ_ECONFIG=-35, IRQ_ETIMEOUT=-36 };
typedef struct {
 const pipeline_device *video,*plic; /* PLIC callbacks take offsets from PLIC_BASE. */
 volatile uint32_t active,expected,ready,claims,empty,unexpected,last_claim;
 volatile int error;
 volatile pipeline_result result;
} pipeline_irq_context;
/* All APIs except service are called with CPU external interrupts disabled.
 * Single owner, no nested interrupts. Init only on a coordinated clean startup.
 * Never clears hardware locks, never aborts an accepted AXI operation. */
int pipeline_irq_init(pipeline_irq_context*,const pipeline_device*,const pipeline_device*);
int pipeline_irq_start(pipeline_irq_context*,pipeline_job*);
int pipeline_irq_take(pipeline_irq_context*,pipeline_result*);
void pipeline_irq_service(pipeline_irq_context*);
int pipeline_irq_watchdog(pipeline_irq_context*,uint64_t elapsed,uint64_t limit);
#endif
