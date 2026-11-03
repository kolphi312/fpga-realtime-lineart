`timescale 1ns/1ps
// Dual-clock memory plus one read-side output register. Both domains MUST be
// reset together via arst_n. Pointer Gray buses require physical CDC constraints.
module async_packet_fifo #(parameter WIDTH=36, LOG2=8)(
 input wire arst_n,wclk,rclk,
 input wire w_valid,input wire [WIDTH-1:0] w_data,output wire w_ready,
 output reg r_valid,output reg [WIDTH-1:0] r_data,input wire r_ready,
 output wire w_up,r_up,output wire [LOG2:0] r_level,w_space
);
 localparam DEPTH=1<<LOG2;
 reg [WIDTH-1:0] mem [0:DEPTH-1];
 reg [LOG2:0] wbin,wgray,rbin,rgray;
 (* async_reg="true" *) reg [LOG2:0] rg1,rg2,wg1,wg2;
 reg full,empty;
 function [LOG2:0] gray_to_bin(input [LOG2:0] g);
  integer i;begin gray_to_bin[LOG2]=g[LOG2];for(i=LOG2-1;i>=0;i=i-1)gray_to_bin[i]=gray_to_bin[i+1]^g[i];end
 endfunction
 // Read-domain conservative occupancy: synchronized write pointer plus the
 // prefetched output register. No new multi-bit CDC path is introduced.
 assign r_level=gray_to_bin(wg2)-rbin+{{LOG2{1'b0}},r_valid};
 // Conservative FREE memory slots in the producer clock domain. A delayed
 // read pointer only underestimates space; no new pointer CDC is introduced.
 wire [LOG2:0] used_w=wbin-gray_to_bin(rg2);
 assign w_space=w_up ? (DEPTH-used_w) : 0;
 reset_release wr_reset(.clk(wclk),.arst_n(arst_n),.srst_n(w_up));
 reset_release rd_reset(.clk(rclk),.arst_n(arst_n),.srst_n(r_up));
 assign w_ready=w_up&&!full;
 wire push=w_valid&&w_ready;
 wire fetch=r_up&&!empty&&(!r_valid||r_ready);
 wire [LOG2:0] wn=wbin+{{LOG2{1'b0}},push};
 wire [LOG2:0] rn=rbin+{{LOG2{1'b0}},fetch};
 wire [LOG2:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 wire [LOG2:0] full_target=rg2 ^ ((1<<LOG2)|(1<<(LOG2-1)));
 initial if(LOG2<2||WIDTH<1)$fatal(1,"FIFO parameters");
 always @(posedge wclk or negedge w_up)begin
  if(!w_up)begin wbin<=0;wgray<=0;rg1<=0;rg2<=0;full<=0;end
  else begin rg1<=rgray;rg2<=rg1;wbin<=wn;wgray<=wgn;full<=(wgn==full_target);end
 end
 always @(posedge rclk or negedge r_up)begin
  if(!r_up)begin rbin<=0;rgray<=0;wg1<=0;wg2<=0;empty<=1;r_valid<=0;end
  else begin
   wg1<=wgray;wg2<=wg1;rbin<=rn;rgray<=rgn;empty<=(rgn==wg2);
   if(fetch)r_valid<=1;else if(r_ready)r_valid<=0;
  end
 end
 // No reset on memory or its read data, permitting true dual-port RAM inference.
 always @(posedge wclk)if(push)mem[wbin[LOG2-1:0]]<=w_data;
 always @(posedge rclk)if(fetch)r_data<=mem[rbin[LOG2-1:0]];
endmodule
