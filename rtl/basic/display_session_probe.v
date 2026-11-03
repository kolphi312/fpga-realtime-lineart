`timescale 1ns/1ps
// First completed display session, SYS-domain stable evidence, not FPS.
// C40000 = success, C60000 = failure. Capture fault has priority at top mux.
module display_session_probe(input wire clk,rst_n,done,bad,output reg [23:0] page);
 always @(posedge clk or negedge rst_n)
  if(!rst_n)page<=0;
  else if(done&&!page[18])page<={4'hc,1'b0,1'b1,bad,17'd0};
endmodule
