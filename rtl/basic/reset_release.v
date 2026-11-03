`timescale 1ns/1ps
// Common assertion; release only after two edges of THIS clock. Consumers use
// srst_n for asynchronous assertion and local synchronous release. A stopped
// clock cannot release its domain. This is not a transaction cancellation API:
// the same assertion must reset the AXI fabric and every participating domain.
module reset_release(input wire clk,arst_n,output wire srst_n);
 (* async_reg="true", syn_srlstyle="registers" *) reg [1:0] release_q;
 always @(posedge clk or negedge arst_n)
  if(!arst_n)release_q<=2'b00;
  else release_q<={release_q[0],1'b1};
 assign srst_n=release_q[1];
endmodule
