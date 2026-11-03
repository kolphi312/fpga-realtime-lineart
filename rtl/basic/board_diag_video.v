`timescale 1ns/1ps
// DIAGNOSTIC ONLY: independent raster, always-visible status. Individual bits
// are synchronized; this is NOT an atomic bus snapshot or a performance meter.
module board_diag_video #(parameter PAGE_SHIFT=6)(input wire clk,arst_n,input wire [23:0] status_async,page_a_async,page_b_async,page_c_async,page_d_async,
 input wire [23:0] pipeline_rgb,output reg [23:0] rgb,
 output reg de,hs,vs,output wire up);
 reset_release diag_reset(.clk(clk),.arst_n(arst_n),.srst_n(up));
 (* async_reg="true",syn_srlstyle="registers" *) reg [119:0] s1,s2;
 (* syn_srlstyle="registers" *) reg [119:0] s3;
 wire fs,rd,rh,rv;wire [11:0] x,y;
 video_raster #(.HA(1280),.HF(110),.HS(40),.HB(220),.VA(720),.VF(5),.VS(5),.VB(20)) raster(
 .clk(clk),.rst_n(up),.frame_start(fs),.de(rd),.hs(rh),.vs(rv),.x(x),.y(y));
 reg [8:0] frames;reg [23:0] live;
 function [14:0] glyph(input [3:0] n);
 begin case(n)
  0:glyph=15'b111_101_101_101_111;1:glyph=15'b010_110_010_010_111;
  2:glyph=15'b111_001_111_100_111;3:glyph=15'b111_001_111_001_111;
  4:glyph=15'b101_101_111_001_001;5:glyph=15'b111_100_111_001_111;
  6:glyph=15'b111_100_111_101_111;7:glyph=15'b111_001_010_010_010;
  8:glyph=15'b111_101_111_101_111;9:glyph=15'b111_101_111_001_111;
  10:glyph=15'b010_101_111_101_101;11:glyph=15'b110_101_110_101_110;
  12:glyph=15'b111_100_100_100_111;13:glyph=15'b110_101_101_101_110;
  14:glyph=15'b111_100_110_100_111;15:glyph=15'b111_100_110_100_100;
 endcase end endfunction
 reg [23:0] c;reg [14:0] g;integer digit,gx,gy;
 always @*begin
  c=24'h102040;g=0;digit=0;gx=0;gy=0;
  // Keep original data path observable, but no image alignment claim in this view.
  if(y>=120&&y<600)c=pipeline_rgb;
  if(y>=620)begin
   case(x[10:8])
    0:c=24'hff0000;1:c=24'h00ff00;2:c=24'h0000ff;
    3:c=24'hffffff;default:c=24'h808080;
   endcase
  end
  if(x>=64&&x<448&&y>=32&&y<72)begin
   digit=(x-64)>>6;gx=((x-64)&63)>>3;gy=(y-32)>>3;
   g=glyph((live>>(20-digit*4))&15);
   if(gx<3&&g[14-gy*3-gx])c=24'hffffff;
  end
  if(y>=88&&y<112&&x>=64&&x<1216)begin
   digit=(x-64)/48;
   c=live[digit]?24'h20ff20:24'hff2020;
   if((x-64)%48>=40)c=24'h102040;
  end
  if(x>=1180&&y<64)c=frames[5]?24'hffff00:24'h202040;
  if(x<4||x>=1276||y<4||y>=716)c=24'h00ffff;
 end
 always @(posedge clk or negedge up)begin
  if(!up)begin s1<=0;s2<=0;s3<=0;live<=0;frames<=0;rgb<=0;de<=0;hs<=0;vs<=0;end
  else begin
   s1<={page_d_async,page_c_async,page_b_async,page_a_async,status_async};s2<=s1;s3<=s2;
   if(fs)begin
    case((frames>>PAGE_SHIFT)&7)
     1:live<=s3[47:24];2:live<=s3[71:48];3:live<=s3[95:72];4:live<=s3[119:96];default:live<=s3[23:0];
    endcase
    frames<=frames+1'b1;
   end
   rgb<=rd?c:24'd0;de<=rd;hs<=rh;vs<=rv;
  end
 end
endmodule
