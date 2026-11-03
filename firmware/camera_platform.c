#include "camera_platform.h"
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define I2C_BASE 0xf8016000u
#define MTIME 0xf8b0bff8u
volatile camera_status sensor_status;
static uint32_t load(uint32_t address){
#ifdef CAMERA_PLATFORM_TEST
 extern uint32_t camera_test_load(uint32_t);
 return camera_test_load(address);
#else
 uint32_t v=REG(address);__asm__ volatile("fence iorw,iorw":::"memory");return v;
#endif
}
static int read_i2c(void*c,uint32_t a,uint32_t*v){(void)c;*v=load(I2C_BASE+a);return 0;}
static int write_i2c(void*c,uint32_t a,uint32_t v){
 (void)c;
#ifdef CAMERA_PLATFORM_TEST
 extern void camera_test_store(uint32_t,uint32_t);
 camera_test_store(I2C_BASE+a,v);
#else
 REG(I2C_BASE+a)=v;__asm__ volatile("fence iorw,iorw":::"memory");
#endif
 return 0;
}
static int ticks(void*c,uint64_t*out){
 (void)c;
 for(unsigned retry=0;retry<8;retry++){
  uint32_t hi=load(MTIME+4),lo=load(MTIME),after=load(MTIME+4);
  if(hi==after){*out=((uint64_t)hi<<32)|lo;return 0;}
 }
 return -1;
}
static int delay_ticks(void*c,uint32_t duration){
 uint64_t begin,now;if(ticks(c,&begin))return -1;
 for(unsigned polls=0;polls<2000000u;polls++){
  if(ticks(c,&now)||now<begin)return -1;
  if(now-begin>=duration)return 0;
 }
 return -1;
}
int camera_platform_initialize(void){
 camera_i2c bus={0,read_i2c,write_i2c,ticks,delay_ticks,96000000u,0,0,0};
 return sc2210_initialize(&bus,&sensor_status);
}
