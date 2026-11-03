`timescale 1ns/1ps
// Passive diagnostics: earliest SYS-domain observation, not a global CDC order.
// RAW reason is held sticky in its source domain. Wait four SYS cycles after
// fault before snapshotting its two-stage synchronized value. Other reasons
// are sampled at the original observation, so later errors cannot replace them.
module first_fault_probe(input wire clk,rst_n,input wire [15:0] causes,
 input wire [3:0] raw_reason_async,bayer_reason,capture_reason,cnn_reason,axi_flags,
 output wire [23:0] page_a,page_b);
 (* async_reg="true",syn_srlstyle="registers" *) reg [3:0] raw1,raw2;
 reg seen,ready;reg [2:0] settle;
 reg [15:0] first_mask;
 reg [3:0] raw_q,bayer_q,capture_q,cnn_q,axi_q;
 assign page_a={4'ha,first_mask,ready?4'he:4'h0};
 assign page_b={4'hb,axi_q,cnn_q,capture_q,raw_q,bayer_q};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin raw1<=0;raw2<=0;seen<=0;ready<=0;settle<=0;first_mask<=0;
   raw_q<=0;bayer_q<=0;capture_q<=0;cnn_q<=0;axi_q<=0;end
  else begin
   raw1<=raw_reason_async;raw2<=raw1;
   if(!seen&&(|causes))begin seen<=1;first_mask<=causes;settle<=4;
    bayer_q<=bayer_reason;capture_q<=capture_reason;cnn_q<=cnn_reason;axi_q<=axi_flags;end
   if(seen&&!ready)begin
    if(settle==1)begin raw_q<=raw2;ready<=1;settle<=0;end
    else settle<=settle-1'b1;
   end
  end
 end
endmodule
