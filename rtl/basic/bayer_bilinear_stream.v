`timescale 1ns/1ps
// RAW8 -> RGB888, bilinear, exactly WIDTH*HEIGHT outputs. One-pixel BLACK
// perimeter; interior is centred at the original pixel coordinate. CFA:
// 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR at (0,0). Hardware CFA still needs confirmation.
// Input is a ready/valid token stream; EOF is a separate token. Output is a
// non-backpressured pixel stream plus a separate EOF pulse. Faults require reset.
module bayer_bilinear_stream #(
 parameter WIDTH=1920,HEIGHT=1080,CFA=1,AW=$clog2(WIDTH)
)(input wire clk,rst_n,input wire in_valid,output wire in_ready,
 input wire [7:0] in_raw,input wire in_sof,in_eol,in_frame_end,in_abort,
 output reg out_valid,out_sof,out_eol,out_frame_end,output reg [23:0] out_rgb,
 output reg fault,out_abort,output reg [3:0] reason);
 localparam RX=0,BOTTOM=1,END_FRAME=2;
 reg [1:0] state;reg active,flush;
 reg [31:0] x,y,bx;
 reg [7:0] mem0[0:WIDTH-1],mem1[0:WIDTH-1];
 reg [7:0] rd0,rd1,raw_q;
 reg wv,wp;reg [AW-1:0] wa;reg [7:0] wd;
 reg qv,qr;reg [31:0] qx,qy;
 reg [7:0] tl,tc,ml,mc,bl,bc;
 wire [7:0] tr=qy[0]?rd1:rd0,mr=qy[0]?rd0:rd1,br=raw_q;
 wire [9:0] cross_sum={2'b0,tc}+{2'b0,ml}+{2'b0,mr}+{2'b0,bc};
 wire [9:0] diag_sum={2'b0,tl}+{2'b0,tr}+{2'b0,bl}+{2'b0,br};
 wire [8:0] hsum={1'b0,ml}+{1'b0,mr},vsum={1'b0,tc}+{1'b0,bc};
 // qx,qy are the bottom-right tap. Centre parity is each parity inverted.
 localparam [1:0] CFA_BITS=CFA;
 wire [1:0] phase={(~qy[0])^CFA_BITS[1],(~qx[0])^CFA_BITS[0]};
 reg [23:0] interpolated;
 always @* case(phase)
  0:interpolated={mc,cross_sum[9:2],diag_sum[9:2]};
  1:interpolated={hsum[8:1],mc,vsum[8:1]};
  2:interpolated={vsum[8:1],mc,hsum[8:1]};
  3:interpolated={diag_sum[9:2],cross_sum[9:2],mc};
 endcase
 assign in_ready=(state==RX)&&!flush&&!fault&&!in_abort;
 wire take=in_valid&&in_ready;
 wire bad_pixel=(x>=WIDTH||y>=HEIGHT||in_sof!=(!active)||in_eol!=(x==WIDTH-1));
 wire bad_end=(!active||x!=0||y!=HEIGHT||in_sof||in_eol);
 wire malformed=take&&(in_frame_end?bad_end:bad_pixel);
 wire accept_pixel=take&&!in_frame_end&&!bad_pixel;
 initial if(WIDTH<4||HEIGHT<3||CFA<0||CFA>3||AW<$clog2(WIDTH))$fatal(1,"Bayer parameters");
 // Read old rows first, then write that pixel ONE CLOCK LATER. Consecutive
 // addresses differ, so correctness does not depend on same-address RAM
 // read/write collision behaviour (which Efinity may map as READ_UNKNOWN).
 always @(posedge clk)begin
  if(accept_pixel)begin rd0<=mem0[x[AW-1:0]];rd1<=mem1[x[AW-1:0]];raw_q<=in_raw;end
  if(wv&&rst_n&&!fault&&!in_abort)begin
   if(wp)mem1[wa]<=wd;else mem0[wa]<=wd;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=RX;active<=0;flush<=0;x<=0;y<=0;bx<=0;wv<=0;wp<=0;wa<=0;wd<=0;
   qv<=0;qr<=0;qx<=0;qy<=0;tl<=0;tc<=0;ml<=0;mc<=0;bl<=0;bc<=0;
   out_valid<=0;out_sof<=0;out_eol<=0;out_frame_end<=0;out_rgb<=0;fault<=0;out_abort<=0;reason<=0;
  end else begin
   out_valid<=0;out_sof<=0;out_eol<=0;out_frame_end<=0;out_abort<=0;qv<=0;wv<=0;
   if(!fault)begin
    if(qv)begin
     if(!qr)begin
      if(qx==0)begin tl<=0;ml<=0;bl<=0;end
      else begin tl<=tc;ml<=mc;bl<=bc;end
      tc<=tr;mc<=mr;bc<=br;
     end
     if(qy>=1&&(qr||qx>=1))begin
      out_valid<=1;out_rgb<=(qr||qy==1||qx==1)?24'b0:interpolated;
      out_sof<=(!qr&&qy==1&&qx==1);out_eol<=qr;
     end
    end
    if(accept_pixel)begin
     active<=1;wv<=1;wp<=y[0];wa<=x[AW-1:0];wd<=in_raw;
     qv<=1;qr<=0;qx<=x;qy<=y;
     if(x==WIDTH-1)begin x<=0;y<=y+1;flush<=1;end else x<=x+1;
    end
    if(flush)begin qv<=1;qr<=1;qx<=WIDTH;qy<=y-1;flush<=0;end
    if(take&&in_frame_end&&!bad_end)begin state<=BOTTOM;bx<=0;end
    if(state==BOTTOM)begin
     out_valid<=1;out_rgb<=0;out_sof<=0;out_eol<=(bx==WIDTH-1);
     if(bx==WIDTH-1)state<=END_FRAME;else bx<=bx+1;
    end
    if(state==END_FRAME)begin out_frame_end<=1;state<=RX;active<=0;x<=0;y<=0;end
    if(in_abort||malformed)begin
     fault<=1;out_abort<=1;reason<=in_abort?1:(in_frame_end?3:2);
     out_valid<=0;out_sof<=0;out_eol<=0;out_frame_end<=0;qv<=0;wv<=0;flush<=0;
    end
   end
  end
 end
endmodule
