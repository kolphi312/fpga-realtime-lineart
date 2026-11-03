`timescale 1ns/1ps
// Single AXI read client. Per row: original W pixels, styled W pixels.
// Two input RGBX images become one 2W x H RGB stream, with no image RAM.
// Completion means the last pixel was accepted AND the row DMA retired.
// A consumer must retain both input banks until good/bad, or coordinated reset
// on locked. A frame_bad consumer must discard the partial output frame.
module paired_split_reader #(parameter W=640,H=480,CREDIT_GATED=0)(
 input wire clk,rst_n,cmd_valid,output wire cmd_ready,
 input wire [31:0] original_base,styled_base,cmd_id,
 output wire busy,locked,output reg frame_good,frame_bad,
 output reg [3:0] reason,output reg [31:0] frame_id,
 output wire out_valid,input wire out_ready,input wire [31:0] burst_credit,output wire [23:0] out_rgb,
 output wire out_sof,out_eol,out_eof,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,
 input wire rlast,rvalid,output wire rready
);
 localparam IDLE=0,ISSUE=1,RUN=2,FINISH=3,LOCK=4;
 localparam [32:0] BYTES=33'd4*W*H;
 reg [2:0] state;reg side;reg [31:0] row,col,orig_addr,style_addr;
 reg pass;
 wire ready,rb,rl,rg,re,rv;wire [3:0] rr;wire [31:0] ri;wire [23:0] rgb;
 wire [32:0] oe={1'b0,original_base}+BYTES,se={1'b0,styled_base}+BYTES;
 wire config_ok=original_base[3:0]==0&&styled_base[3:0]==0&&oe<=33'h100000000&&se<=33'h100000000&&
  (oe<={1'b0,styled_base}||se<={1'b0,original_base});
 assign cmd_ready=state==IDLE&&!rl;
 assign busy=state!=IDLE;assign locked=rl||state==LOCK;
 assign out_valid=state==RUN&&rv;assign out_rgb=rgb;
 assign out_sof=(row==0)&&!side&&(col==0);
 assign out_eol=side&&(col==W-1);
 assign out_eof=(row==H-1)&&out_eol;
 rgb_frame_axi_reader_display #(.FRAME_PIXELS(W),.WIDTH(W),.CREDIT_GATED(CREDIT_GATED)) reader(
  .clk(clk),.rst_n(rst_n),.cmd_valid(state==ISSUE),.cmd_ready(ready),
  .cmd_base(side?style_addr:orig_addr),.cmd_id(frame_id),.busy(rb),.locked(rl),
  .frame_good(rg),.frame_bad(re),.reason(rr),.frame_id(ri),
  .out_valid(rv),.out_ready(state==RUN&&out_ready),.burst_credit(burst_credit),.out_rgb(rgb),.out_sof(),.out_eol(),.out_eof(),
  .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rid(rid),.rresp(rresp),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 initial if(W<4||W%4!=0||H<1||BYTES>33'h100000000)$fatal(1,"split geometry/row alignment");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;side<=0;row<=0;col<=0;orig_addr<=0;style_addr<=0;frame_id<=0;frame_good<=0;frame_bad<=0;reason<=0;pass<=0;end
  else begin
   frame_good<=0;frame_bad<=0;
   case(state)
    IDLE:if(cmd_valid&&cmd_ready)begin
     row<=0;col<=0;side<=0;orig_addr<=original_base;style_addr<=styled_base;frame_id<=cmd_id;
     pass<=config_ok;reason<=config_ok?0:2;state<=config_ok?ISSUE:FINISH;
    end
    ISSUE:if(ready)begin col<=0;state<=RUN;end
    RUN:begin
     if(out_valid&&out_ready)col<=col+1'b1;
     if(re&&!rl)begin pass<=0;reason<=rr;state<=FINISH;end
     if(rg)begin
      if(col!=W||ri!=frame_id)begin pass<=0;reason<=6;state<=LOCK;end
      else if(!side)begin side<=1;state<=ISSUE;end
      else if(row==H-1)state<=FINISH;
      else begin row<=row+1'b1;side<=0;orig_addr<=orig_addr+W*4;style_addr<=style_addr+W*4;state<=ISSUE;end
     end
    end
    FINISH:if(!rb)begin state<=IDLE;if(pass)frame_good<=1;else frame_bad<=1;end
   endcase
   if(rl)begin state<=LOCK;reason<=rr;end
  end
 end
endmodule
