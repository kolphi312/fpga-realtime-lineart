#include "camera_i2c.h"
#define SDA 2u
#define SCL 4u
static int rd(camera_i2c*b,uint32_t a,uint32_t*v){return b->read(b->context,a,v)?CAM_EIO:0;}
static int wr(camera_i2c*b,uint32_t a,uint32_t v){return b->write(b->context,a,v)?CAM_EIO:0;}
static int delay(camera_i2c*b){return b->delay(b->context,b->half_ticks)?CAM_EIO:0;}
static int lines(camera_i2c*b,uint32_t release){return wr(b,0x48,release);}
static int wait_scl(camera_i2c*b){
 uint64_t begin,now;uint32_t pins;
 if(b->now(b->context,&begin))return CAM_EIO;
 for(uint32_t i=0;i<100000u;i++){
  if(rd(b,0x44,&pins))return CAM_EIO;
  if(pins&SCL)return 0;
  if(b->now(b->context,&now))return CAM_EIO;
  if(now-begin>=b->timeout_ticks)return CAM_ETIMEOUT;
 }
 return CAM_ETIMEOUT; /* Also finite if the supplied timer stops. */
}
static int sample_sda(camera_i2c*b,uint8_t*v){uint32_t pins;int e=rd(b,0x44,&pins);
 if(!e)*v=(pins&SDA)!=0;
 return e;}
static int rise(camera_i2c*b,uint32_t sda){int e=lines(b,sda|SCL);
 if(!e)e=wait_scl(b);
 if(!e)e=delay(b);
 return e;}
static int start(camera_i2c*b){
 uint8_t high;int e=lines(b,SDA);
 if(!e)e=delay(b);
 if(!e)e=rise(b,SDA);
 if(!e)e=sample_sda(b,&high);
 if(!e&&!high)e=CAM_EBUS;
 if(!e)e=lines(b,SCL);
 if(!e)e=delay(b);
 if(!e)e=lines(b,0);
 return e;
}
static int stop(camera_i2c*b){
 int e=lines(b,0);uint8_t high;
 if(!e)e=delay(b);
 if(!e)e=rise(b,0);
 if(!e)e=lines(b,SDA|SCL);
 if(!e)e=delay(b);
 if(!e)e=sample_sda(b,&high);
 if(!e&&!high)e=CAM_EBUS;
 /* Releasing both lines is mandatory even on timeout. */
 int release=lines(b,SDA|SCL);
 return e?e:release;
}
static int send_bit(camera_i2c*b,int value){
 uint32_t bit=value?SDA:0;uint8_t got;int e=lines(b,bit);
 if(!e)e=delay(b);
 if(!e)e=rise(b,bit);
 if(!e&&value){e=sample_sda(b,&got);
 if(!e&&!got)e=CAM_EBUS;}
 if(!e)e=lines(b,bit);
 return e;
}
static int receive_bit(camera_i2c*b,uint8_t*v){
 int e=lines(b,SDA);
 if(!e)e=delay(b);
 if(!e)e=rise(b,SDA);
 if(!e)e=sample_sda(b,v);
 if(!e)e=lines(b,SDA);
 return e;
}
static int send_byte(camera_i2c*b,uint8_t v){
 for(int i=7;i>=0;i--){int e=send_bit(b,(v>>i)&1);
 if(e)return e;}
 uint8_t nack;int e=receive_bit(b,&nack);
 return e?e:(nack?CAM_ENACK:0);
}
static int address(camera_i2c*b,uint16_t reg){
 int e=start(b);
 if(!e)e=send_byte(b,0x60);
 if(!e)e=send_byte(b,(uint8_t)(reg>>8));
 if(!e)e=send_byte(b,(uint8_t)reg);
 return e;
}
int camera_bus_init(camera_i2c*b){
 if(!b||!b->read||!b->write||!b->now||!b->delay||b->hz!=96000000u)return CAM_EINVAL;
 b->half_ticks=b->hz/100000u; /* at most 50kHz, >=10us each half */
 b->timeout_ticks=b->hz/500u;b->cleanup_error=0;
 const uint32_t init[][2]={{0x48,6},{0x20,0},{0x88,0},{0x8c,0},{0x00,0x500},{0x04,0x500},{0x08,0},{0x0c,0},{0x28,0},{0x2c,0xfffff},{0x30,0},{0x50,960},{0x54,960},{0x58,960}};
 for(unsigned i=0;i<sizeof(init)/sizeof(init[0]);i++)if(wr(b,init[i][0],init[i][1]))return CAM_EIO;
 if(b->delay(b->context,b->hz/200u))return CAM_EIO; /* >2ms power-on guard */
 int e=wait_scl(b);uint8_t high;
 if(!e)e=sample_sda(b,&high);
 if(!e&&!high)e=CAM_EBUS;
 return e;
}
int camera_write8(camera_i2c*b,uint16_t reg,uint8_t v){
 int e=address(b,reg);
 if(!e)e=send_byte(b,v);
 int cleanup=stop(b);b->cleanup_error=cleanup;
 return e?e:cleanup;
}
int camera_read8(camera_i2c*b,uint16_t reg,uint8_t*out){
 if(!out)return CAM_EINVAL;
 uint8_t value=0,bit;int e=address(b,reg);
 if(!e)e=start(b);
 if(!e)e=send_byte(b,0x61);
 for(unsigned i=0;i<8&&!e;i++){e=receive_bit(b,&bit);
 if(!e)value=(uint8_t)((value<<1)|bit);}
 if(!e)e=send_bit(b,1); /* last byte NACK */
 int cleanup=stop(b);b->cleanup_error=cleanup;
 if(!e)e=cleanup;
 if(!e)*out=value;
 return e;
}
