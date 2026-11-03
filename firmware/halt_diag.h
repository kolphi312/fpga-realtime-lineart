#ifndef HALT_DIAG_H
#define HALT_DIAG_H
#include <stdint.h>
/* Preserve full why in app_status. GPIO[23:8] publishes all current software
 * reasons (<= 0x624). Fxxx identifies trap causes, EFFF is unrepresentable.
 * Low byte stays EE; unused upper GPIO bits do not control any board function. */
static inline uint32_t halt_gpio_word(uint32_t why){
 uint32_t code=why;
 if((why&0xf0000000u)==0xf0000000u)code=0xf000u|(why&0xfffu);
 else if(why>0xffffu)code=0xefffu;
 return (code<<8)|0xeeu;
}
#endif
