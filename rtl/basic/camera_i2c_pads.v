`timescale 1ns/1ps
// Single master. Efinity GPIO OE is active high; external module has pull-ups.
module camera_i2c_pads(input wire enable,scl_release,sda_release,
 output wire scl_o,scl_oe,sda_o,sda_oe);
 assign scl_o=1'b0;
 assign sda_o=1'b0;
 assign scl_oe=enable&&!scl_release;
 assign sda_oe=enable&&!sda_release;
endmodule
