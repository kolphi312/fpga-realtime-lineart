`timescale 1ns/1ps
// Presentation build: live RGB only, no periodic synthetic frame insertion.
// Same ports as the isolated diagnostic mux; capture handshake is untouched.
module capture_pattern_mux #(parameter W=640,H=480)(
 input wire clk,rst_n,start,input wire [31:0] job_id,input wire pixel_fire,
 input wire [23:0] in_rgb,output wire [23:0] out_rgb);
 assign out_rgb=in_rgb;
endmodule
