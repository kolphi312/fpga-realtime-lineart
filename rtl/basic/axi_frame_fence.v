`timescale 1ns/1ps
// Completion monitor, NOT a DMA writer or AXI protocol validator.
// All events are real handshakes in the AXI clock domain, one frame at a time.
// aw_fire=AWVALID&AWREADY; wl_fire=WVALID&WREADY&WLAST;
// b_fire=BVALID&BREADY for this writer's ID. Bus routing must reject other IDs.
// issue_done means no more AW or W transactions for this frame, including FIFOs.
// source_ok is the frame guard verdict, held until issue_done. Upstream must
// cross that verdict/frame ID into this domain with a proper handshake.
// Protocol misuse locks the monitor until coordinated writer/bus reset: do not
// reuse a bank while old responses might still arrive.
module axi_frame_fence #(parameter CW=8)(
 input wire clk,rst_n,start,
 input wire [31:0] start_id,
 input wire aw_fire,wl_fire,b_fire,
 input wire [1:0] bresp,
 input wire issue_done,source_ok,
 output reg busy,locked,frame_good,frame_bad,
 output reg [31:0] frame_id,
 output reg [3:0] reason,
 output wire [CW-1:0] pending_aw,pending_w
);
 reg [CW-1:0] pa,pw;
 reg closed,bus_error,source_bad,issued;
 wire [CW:0] na={1'b0,pa}+aw_fire-b_fire;
 wire [CW:0] nw={1'b0,pw}+wl_fire-b_fire;
 wire underflow=b_fire&&((pa==0&&!aw_fire)||(pw==0&&!wl_fire));
 wire overflow=na[CW]||nw[CW];
 wire late_issue=closed&&(aw_fire||wl_fire||issue_done);
 wire unmatched_close=issue_done&&(na!=nw);
 wire stray=(!busy&&(aw_fire||wl_fire||b_fire||issue_done))||(start&&busy)||(start&&(aw_fire||wl_fire||b_fire||issue_done));
 wire protocol_fault=stray||(busy&&(underflow||overflow||late_issue||unmatched_close));
 assign pending_aw=pa;assign pending_w=pw;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;locked<=0;frame_good<=0;frame_bad<=0;frame_id<=0;reason<=0;
   pa<=0;pw<=0;closed<=0;bus_error<=0;source_bad<=0;issued<=0;
  end else begin
   frame_good<=0;frame_bad<=0;
   if(!locked)begin
    if(start&&!busy)begin
     busy<=1;frame_id<=start_id;pa<=0;pw<=0;closed<=0;bus_error<=0;source_bad<=0;issued<=0;reason<=0;
    end
    if(busy)begin
     pa<=na[CW-1:0];pw<=nw[CW-1:0];
     if(aw_fire)issued<=1;
     if(b_fire&&bresp!=0)bus_error<=1;
     if(issue_done)begin closed<=1;source_bad<=!source_ok;end
     if((closed||issue_done)&&na==0&&nw==0)begin
      busy<=0;
      if(bus_error||(b_fire&&bresp!=0))begin frame_bad<=1;reason<=2;end
      else if(source_bad||(issue_done&&!source_ok))begin frame_bad<=1;reason<=1;end
      else if(!issued&&!aw_fire)begin frame_bad<=1;reason<=3;end
      else begin frame_good<=1;reason<=0;end
     end
    end
    if(protocol_fault)begin
     busy<=1;locked<=1;frame_good<=0;frame_bad<=1;
     if(stray)reason<=4;
     else if(underflow)reason<=5;
     else if(overflow)reason<=6;
     else if(late_issue)reason<=7;
     else reason<=8;
    end
   end
  end
 end
endmodule
