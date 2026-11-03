`timescale 1ns/1ps
// Passive observer for this arbiter's subset: one outstanding per direction,
// address handshake before data, owner0 capture writes / CNN reads, owner1 ignored.
// Exact channel sums (no overflow at 640x480), NOT a pixel-order proof or CRC.
module frame_integrity_probe #(
 parameter integer PIXELS=640*480,
 parameter [31:0] BASE=32'hff0,STRIDE=32'h140000
)(input wire clk,rst_n,
 input wire awvalid,awready,input wire [3:0] awid,input wire [31:0] awaddr,input wire [7:0] awlen,
 input wire wvalid,wready,input wire [127:0] wdata,input wire [15:0] wstrb,input wire wlast,
 input wire arvalid,arready,input wire [3:0] arid,input wire [31:0] araddr,input wire [7:0] arlen,
 input wire rvalid,rready,input wire [127:0] rdata,input wire [3:0] rid,input wire rlast,
 output wire [23:0] page,output reg failed);
 localparam integer BEATS=PIXELS/4;
 reg [31:0] wr[0:3],wg[0:3],wb[0:3];reg [3:0] valid;
 reg [31:0] ws_r,ws_g,ws_b,rs_r,rs_g,rs_b;
 reg [31:0] wn,rn,wa,ra,passes;reg [1:0] bank_w,bank_r;
 reg owner_w,owner_r,live_w,live_r;reg [8:0] wl,rl;
 reg [23:0] error_page;
 reg [2:0] awbank,arbank;reg awstart,arstart;integer i;
 function [31:0] sum4(input [127:0] d,input integer off);
 begin sum4={24'b0,d[off+:8]}+{24'b0,d[off+32+:8]}+{24'b0,d[off+64+:8]}+{24'b0,d[off+96+:8]};end endfunction
 wire [31:0] wnr=ws_r+sum4(wdata,0),wng=ws_g+sum4(wdata,8),wnb=ws_b+sum4(wdata,16);
 wire [31:0] rnr=rs_r+sum4(rdata,0),rng=rs_g+sum4(rdata,8),rnb=rs_b+sum4(rdata,16);
 assign page=failed?error_page:{4'h9,passes[19:0]};
 always @*begin
  awbank=4;arbank=4;awstart=0;arstart=0;
  for(integer k=0;k<4;k=k+1)begin
   if(awaddr>=BASE+k*STRIDE&&awaddr<BASE+k*STRIDE+PIXELS*4)begin awbank=k;awstart=awaddr==BASE+k*STRIDE;end
   if(araddr>=BASE+k*STRIDE&&araddr<BASE+k*STRIDE+PIXELS*4)begin arbank=k;arstart=araddr==BASE+k*STRIDE;end
  end
 end
 // Detailed first write fault: E6 mask; E7 overlap; E8 no active AW;
 // E9 bank mismatch; EA address discontinuity; EB data without frame;
 // EC exhausted burst; ED wrong WLAST. Payload is mask/count/address as below.
 task mark_write_error(input [3:0] kind,input [15:0] detail);
 begin if(!failed)begin failed<=1;error_page<={4'he,kind,detail};end end endtask
 task mark_error(input [3:0] kind);
 begin if(!failed)begin failed<=1;error_page<={4'he,kind,passes[15:0]};end end endtask
 initial if(PIXELS<4||PIXELS%4||PIXELS>16777215)$fatal(1,"integrity size");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   failed<=0;error_page<=0;passes<=0;valid<=0;ws_r<=0;ws_g<=0;ws_b<=0;rs_r<=0;rs_g<=0;rs_b<=0;
   wn<=0;rn<=0;wa<=0;ra<=0;bank_w<=0;bank_r<=0;owner_w<=0;owner_r<=0;live_w<=0;live_r<=0;wl<=0;rl<=0;
   for(i=0;i<4;i=i+1)begin wr[i]<=0;wg[i]<=0;wb[i]<=0;end
  end else begin
   if(awvalid&&awready)begin
    owner_w<=awid==0;wl<={1'b0,awlen}+9'd1;
    if(awid==0)begin
     if(awbank==4)mark_error(1);
     else if(awstart)begin
      if(live_w)mark_write_error(7,wn[15:0]);
      bank_w<=awbank[1:0];valid[awbank[1:0]]<=0;ws_r<=0;ws_g<=0;ws_b<=0;wn<=0;wa<=awaddr;live_w<=1;
     end else if(!live_w)mark_write_error(8,awaddr[15:0]);
     else if(awbank[1:0]!=bank_w)mark_write_error(9,{12'd0,bank_w,awbank[1:0]});
     else if(awaddr!=wa)mark_write_error(10,awaddr[15:0]);
    end
   end
   if(wvalid&&wready&&owner_w)begin
    if(!live_w)mark_write_error(11,wn[15:0]);
    else if(wl==0)mark_write_error(12,wn[15:0]);
    else if(wlast!=(wl==1))mark_write_error(13,{6'd0,wlast,wl});
    else if(wstrb!=16'hffff)mark_write_error(6,wstrb);
    wl<=wl-1'b1;wa<=wa+16;wn<=wn+1;ws_r<=wnr;ws_g<=wng;ws_b<=wnb;
    if(wn==BEATS-1)begin
     wr[bank_w]<=wnr;wg[bank_w]<=wng;wb[bank_w]<=wnb;valid[bank_w]<=1;live_w<=0;
    end
   end
   if(arvalid&&arready)begin
    owner_r<=arid==0;rl<={1'b0,arlen}+9'd1;
    if(arid==0)begin
     if(arbank==4)mark_error(3);
     else if(arstart)begin
      if(live_r)mark_error(3);
      if(!valid[arbank[1:0]])mark_error(4);
      bank_r<=arbank[1:0];rs_r<=0;rs_g<=0;rs_b<=0;rn<=0;ra<=araddr;live_r<=1;
     end else if(!live_r||arbank[1:0]!=bank_r||araddr!=ra)mark_error(3);
    end
   end
   if(rvalid&&rready&&owner_r)begin
    if(!live_r||rl==0||rlast!=(rl==1)||rid!=0)mark_error(3);
    rl<=rl-1'b1;ra<=ra+16;rn<=rn+1;rs_r<=rnr;rs_g<=rng;rs_b<=rnb;
    if(rn==BEATS-1)begin
     live_r<=0;
     if(!valid[bank_r])mark_error(4);
     else if(rnr!=wr[bank_r]||rng!=wg[bank_r]||rnb!=wb[bank_r])mark_error(5);
     else passes<=passes+1;
    end
   end
  end
 end
endmodule
