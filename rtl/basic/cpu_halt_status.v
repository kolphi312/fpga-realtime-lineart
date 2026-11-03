`timescale 1ns/1ps
// Normal CPU state may publish a 12-bit metric plus page tag. Fatal ED/EE
// has priority. A/B/C/D remain independent and are never hidden by metrics.
module cpu_halt_status(input wire [23:0] gpio_word,flags,output wire [23:0] status);
 assign status=(gpio_word[7:0]==8'hed)?{8'he1,gpio_word[23:8]}:
              (gpio_word[7:0]==8'hee && (|gpio_word[23:8])) ?
               {8'he0,gpio_word[23:8]} :
              ((gpio_word[7:0]==8'h02 || gpio_word[7:0]==8'h06) && (|gpio_word[23:8])) ?
               {4'h7,gpio_word[23:20],4'h0,gpio_word[19:8]} : flags;
endmodule
