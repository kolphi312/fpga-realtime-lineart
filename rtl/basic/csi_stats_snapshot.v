`timescale 1ns/1ps
// Request/acknowledge snapshot of a coherent CSI-domain bundle. Held source
// payload remains constant until the NEXT request. Ack gets two synchronizer
// stages plus a settle cycle before sampling. Physical bus max-delay/skew and
// synchronizer constraints are mandatory; RTL simulation is not CDC signoff.
module csi_stats_snapshot(
 input wire arst_n,clk,csi_clk,request,output wire ready,output reg done,
 input wire [31:0] observed,admitted,skipped,
 output reg [95:0] result
);
 wire su,cu;reset_release sr(.clk(clk),.arst_n(arst_n),.srst_n(su));reset_release cr(.clk(csi_clk),.arst_n(arst_n),.srst_n(cu));
 reg req,ack,busy,settle;reg [95:0] held;
 (* async_reg="true",syn_srlstyle="registers" *)reg rq1,rq2,ak1,ak2;
 assign ready=su&&!busy;
 always @(posedge csi_clk or negedge cu)begin
  if(!cu)begin rq1<=0;rq2<=0;ack<=0;held<=0;end
  else begin rq1<=req;rq2<=rq1;if(rq2!=ack)begin held<={observed,admitted,skipped};ack<=rq2;end end
 end
 always @(posedge clk or negedge su)begin
  if(!su)begin req<=0;ak1<=0;ak2<=0;busy<=0;settle<=0;done<=0;result<=0;end
  else begin
   ak1<=ack;ak2<=ak1;done<=0;
   if(request&&ready)begin req<=!req;busy<=1;settle<=0;end
   else if(busy&&ak2==req)begin
    if(!settle)settle<=1;else begin result<=held;done<=1;busy<=0;settle<=0;end
   end
  end
 end
endmodule
