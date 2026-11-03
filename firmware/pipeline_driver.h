#ifndef PIPELINE_DRIVER_H
#define PIPELINE_DRIVER_H
#include <stdint.h>
enum { PIPE_OK=0,PIPE_PENDING=1,PIPE_EINVAL=-1,PIPE_EIO=-2,PIPE_EBUSY=-3,PIPE_EFAULT=-4,PIPE_EJOB=-5,PIPE_EID=-6 };
enum { P_ID=0,P_STATUS=4,P_RUN=8,P_START=12,P_IRQ_MASK=16,P_IRQ_STATUS=20,P_NEXT_ID=24,P_SOURCE=28,P_RESULT=32,
 P_LAST_ID=36,P_REASON=40,P_CYCLES=44,P_CAPTURED=48,P_COMPUTED=52,P_DISPLAYED=56,P_REPEATS=60,
 P_RESERVED=80,P_LIMIT=84,P_HZ=88,P_SNAPSHOT=96,P_SNAP_BASE=128,P_COEFF=256 };
enum { P_RUNNING=1,P_BUSY=2,P_QUEUED=4,P_CONFIGURED=8,P_FAULT=16,P_IDLE=32,P_CFG_ERROR=64,P_DONE=128 };
typedef struct { void *context;int (*read)(void*,uint32_t,uint32_t*);int (*write)(void*,uint32_t,uint32_t); } pipeline_device;
typedef struct { uint32_t id,source,result; } pipeline_job;
typedef struct { uint32_t id,reason,cycles; } pipeline_result;
typedef struct { uint64_t ticks;uint32_t sequence,captured,computed,displayed,repeats,errors,last_capture,last_compute,last_display; } pipeline_snapshot;
typedef struct { uint32_t capture_mfps,compute_mfps,display_mfps; } pipeline_rates;
int pipeline_probe(const pipeline_device*);
int pipeline_load(const pipeline_device*,const int32_t[27]);
int pipeline_run(const pipeline_device*,uint32_t capture_limit); /* 0 = continuous */
int pipeline_stop(const pipeline_device*); /* Does not abort an accepted task. */
int pipeline_start(const pipeline_device*,pipeline_job*);
int pipeline_collect(const pipeline_device*,uint32_t expected_id,pipeline_result*);
int pipeline_irq_mask(const pipeline_device*,uint32_t mask);
int pipeline_sample(const pipeline_device*,pipeline_snapshot*);
int pipeline_get_rates(const pipeline_snapshot*,const pipeline_snapshot*,uint32_t clock_hz,pipeline_rates*);
typedef struct {uint64_t ticks;uint32_t sequence,observed,admitted,skipped;} pipeline_source_snapshot;
int pipeline_source_request(const pipeline_device*,uint32_t *previous_sequence);
int pipeline_source_collect(const pipeline_device*,uint32_t previous_sequence,pipeline_source_snapshot*);
int pipeline_source_fps(const pipeline_source_snapshot*,const pipeline_source_snapshot*,uint32_t clock_hz,uint32_t *milli_fps);
int pipeline_osd_update(const pipeline_device*,uint32_t raw_mfps,const pipeline_rates*,int skipped);
/* One software owner. APB callbacks propagate access failure. Platform binding
 * must supply uncached MMIO, actual aperture/IRQ and clock frequency; none are
 * invented here. Reinitialize sample baseline after coordinated CPU/AXI/reset.
 * Sampling reports accepted complete capture frames, not every raw sensor VS. */
#endif
