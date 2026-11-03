`timescale 1ns/1ps
// Stable bundled message, committed only when the receiver accepts it. Source
// cannot overwrite it until the returned acknowledgement; coordinate reset.
module frame_mailbox #(parameter WIDTH=32)(
 input wire arst_n,s_clk,s_valid,input wire [WIDTH-1:0] s_data,output wire s_ready,
 input wire d_clk,d_ready,output wire d_valid,output reg [WIDTH-1:0] d_data
);
 wire su,du;reset_release sr(.clk(s_clk),.arst_n(arst_n),.srst_n(su));reset_release dr(.clk(d_clk),.arst_n(arst_n),.srst_n(du));
 reg req,ack,pending,settle;reg [WIDTH-1:0] held;
 (* async_reg="true",syn_srlstyle="registers" *)reg rq1,rq2,ak1,ak2;
 assign s_ready=su&&(req==ak2);assign d_valid=du&&pending;
 always @(posedge s_clk or negedge su)begin
  if(!su)begin req<=0;held<=0;ak1<=0;ak2<=0;end
  else begin ak1<=ack;ak2<=ak1;if(s_valid&&s_ready)begin held<=s_data;req<=!req;end end
 end
 always @(posedge d_clk or negedge du)begin
  if(!du)begin rq1<=0;rq2<=0;ack<=0;pending<=0;settle<=0;d_data<=0;end
  else begin
   rq1<=req;rq2<=rq1;
   if(!pending&&rq2!=ack)begin
    if(!settle)settle<=1;else begin d_data<=held;pending<=1;settle<=0;end
   end
   if(pending&&d_ready)begin pending<=0;ack<=rq2;end
  end
 end
endmodule
