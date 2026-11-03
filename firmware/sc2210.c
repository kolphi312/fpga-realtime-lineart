#include "camera_i2c.h"
static const struct {uint16_t address;uint8_t value;} table[]={
#include "sc2210_table.inc"
};
static int read_reg(camera_i2c*b,volatile camera_status*s,uint16_t a,uint8_t*v){
 s->address=a;int e=camera_read8(b,a,v);if(!e){s->reads++;s->observed=*v;}return e;
}
static int check(camera_i2c*b,volatile camera_status*s,uint16_t a,uint8_t mask,uint8_t expected){
 uint8_t v;s->expected=expected;int e=read_reg(b,s,a,&v);
 return e?e:((v&mask)==expected?0:CAM_EREADBACK);
}
static int identity(camera_i2c*b,volatile camera_status*s){
 uint8_t hi,lo;int e=read_reg(b,s,0x3107,&hi);if(e)return e;
 e=read_reg(b,s,0x3108,&lo);if(e)return e;
 s->id=((uint32_t)hi<<8)|lo;return s->id==0x2210?0:CAM_EID;
}
int sc2210_initialize(camera_i2c*b,volatile camera_status*s){
 if(!s)return CAM_EINVAL;
 *s=(camera_status){0};s->stage=1;int e=camera_bus_init(b);if(e)goto fail;
 e=identity(b,s);if(e)goto fail; /* Never configure a different sensor. */
 s->stage=2;
 for(unsigned i=0;i<sizeof(table)/sizeof(table[0])-1;i++){
  s->address=table[i].address;s->expected=table[i].value;
  e=camera_write8(b,table[i].address,table[i].value);if(e)goto fail;s->writes++;
  if(i==0){
   if(b->delay(b->context,b->hz/200u)){e=CAM_EIO;goto fail;}
   e=identity(b,s);if(e)goto fail;
  }
 }
 s->stage=3;
 /* Mask reserved bits; geometry defaults are also checked explicitly. */
 const uint32_t checks[][3]={{0x0100,1,0},{0x3018,0xe0,0x60},{0x3031,15,8},
  {0x3208,255,7},{0x3209,255,0x80},{0x320a,255,4},{0x320b,255,0x38},
  {0x320c,255,8},{0x320d,255,0x6e},{0x320e,255,4},{0x320f,255,0x58}};
 for(unsigned i=0;i<sizeof(checks)/sizeof(checks[0]);i++){
  e=check(b,s,(uint16_t)checks[i][0],(uint8_t)checks[i][1],(uint8_t)checks[i][2]);if(e)goto fail;
 }
 s->stage=4;s->address=0x100;s->expected=1;
 e=camera_write8(b,0x100,1);if(e)goto disable;s->writes++;
 e=check(b,s,0x100,1,1);if(e)goto disable;
 s->stage=5;return 0;
disable:
 /* A failed final read is not permission to leave streaming enabled. */
 s->cleanup_error=camera_write8(b,0x100,0);
fail:
 s->error=e;if(!s->cleanup_error)s->cleanup_error=b?b->cleanup_error:0;
 return e;
}
