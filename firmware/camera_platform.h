#ifndef CAMERA_PLATFORM_H
#define CAMERA_PLATFORM_H
#include "camera_i2c.h"
extern volatile camera_status sensor_status;
int camera_platform_initialize(void);
#endif
