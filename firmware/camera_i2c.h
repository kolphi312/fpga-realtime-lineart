#ifndef CAMERA_I2C_H
#define CAMERA_I2C_H
#include <stdint.h>
enum {CAM_OK=0,CAM_EIO=-1,CAM_ETIMEOUT=-2,CAM_ENACK=-3,CAM_EBUS=-4,CAM_EID=-5,CAM_EREADBACK=-6,CAM_EINVAL=-7};
typedef struct {
 void *context;
 int (*read)(void*,uint32_t,uint32_t*);
 int (*write)(void*,uint32_t,uint32_t);
 int (*now)(void*,uint64_t*);
 int (*delay)(void*,uint32_t);
 uint32_t hz,half_ticks,timeout_ticks;
 int cleanup_error;
} camera_i2c;
/* Existing SoC I2C registers: override drives LOW when a release bit is zero.
 * C owns timing; automatic master is never started, slave responses disabled.
 * One owner; initialization occurs before global interrupts/video RUN. */
int camera_bus_init(camera_i2c*);
int camera_read8(camera_i2c*,uint16_t,uint8_t*);
int camera_write8(camera_i2c*,uint16_t,uint8_t);
typedef struct {uint32_t id,writes,reads,stage,address,expected,observed;int error,cleanup_error;} camera_status;
int sc2210_initialize(camera_i2c*,volatile camera_status*);
#endif
