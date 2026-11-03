`timescale 1ns/1ps
// One stable request toggle per accepted capture command. Admit at the next
// physical frame rising edge only; never truncate an admitted frame on STOP.
// All domains and AXI must share coordinated reset. Counters are CSI-domain
// diagnostics; do NOT sample the binary buses directly from software.
module csi_frame_admission(
 input wire arst_n,clk,csi_clk,grant,output wire grant_ready,
 input wire fv,lv,de,input wire [47:0] raw,
 output wire out_fv,out_lv,out_de,output wire [47:0] out_raw,
 output reg [31:0] observed,admitted,skipped,output reg protocol_error
);
 wire sys_up,csi_up;
 reset_release sr(.clk(clk),.arst_n(arst_n),.srst_n(sys_up));
 reset_release cr(.clk(csi_clk),.arst_n(arst_n),.srst_n(csi_up));
 reg request,ack;
 (* async_reg="true",syn_srlstyle="registers" *)reg req1,req2;
 (* async_reg="true",syn_srlstyle="registers" *)reg ack1,ack2;
 reg previous_fv,seen_idle,active;
 wire start=seen_idle&&fv&&!previous_fv;
 wire take=start&&(req2!=ack);
 wire passing=csi_up&&(active||take);
 assign grant_ready=sys_up&&(request==ack2)&&!protocol_error;
 assign out_fv=fv&&passing;assign out_lv=lv&&passing;assign out_de=de&&passing;
 assign out_raw=raw;
 always @(posedge clk or negedge sys_up)begin
  if(!sys_up)begin request<=0;ack1<=0;ack2<=0;protocol_error<=0;end
  else begin
   ack1<=ack;ack2<=ack1;
   if(grant)begin if(grant_ready)request<=!request;else protocol_error<=1;end
  end
 end
 always @(posedge csi_clk or negedge csi_up)begin
  if(!csi_up)begin req1<=0;req2<=0;ack<=0;previous_fv<=0;seen_idle<=0;active<=0;observed<=0;admitted<=0;skipped<=0;end
  else begin
   req1<=request;req2<=req1;previous_fv<=fv;
   if(!fv)begin seen_idle<=1;active<=0;end
   if(start)begin
    observed<=observed+1;active<=take;
    if(take)begin ack<=req2;admitted<=admitted+1;end
    else skipped<=skipped+1;
   end
  end
 end
endmodule
