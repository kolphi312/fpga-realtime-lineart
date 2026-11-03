`timescale 1ns/1ps
// DIAGNOSTIC ONLY: independent raster, always-visible status. Individual bits
// are synchronized; this is NOT an atomic bus snapshot or a performance meter.
module board_diag_video_aligned #(parameter PAGE_SHIFT=6)(input wire clk,arst_n,input wire [23:0] status_async,page_a_async,page_b_async,page_c_async,page_d_async,
 input wire [23:0] pipeline_rgb,output reg [23:0] rgb,
 output reg de,hs,vs,output wire up,
 output wire raster_start,raster_de,raster_hs,raster_vs,output wire [11:0] raster_x,raster_y);
 reset_release diag_reset(.clk(clk),.arst_n(arst_n),.srst_n(up));
 (* async_reg="true",syn_srlstyle="registers" *) reg [119:0] s1,s2;
 (* syn_srlstyle="registers" *) reg [119:0] s3;
 reg fs,rd,rh,rv;reg [11:0] x,y;
 video_raster #(.HA(1280),.HF(110),.HS(40),.HB(220),.VA(720),.VF(5),.VS(5),.VB(20)) raster(
 .clk(clk),.rst_n(up),.frame_start(raster_start),.de(raster_de),.hs(raster_hs),.vs(raster_vs),.x(raster_x),.y(raster_y));
 // This is the SOLE raster for pipeline and diagnostic output. The display
 // bridge registers RGB once, so delay matching geometry once before overlay.
 always @(posedge clk or negedge up)begin
  if(!up)begin fs<=0;rd<=0;rh<=0;rv<=0;x<=0;y<=0;end
  else begin fs<=raster_start;rd<=raster_de;rh<=raster_hs;rv<=raster_vs;x<=raster_x;y<=raster_y;end
 end
 reg [8:0] frames;reg [23:0] live,status_live;
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
 function [14:0] title_glyph(input [7:0] ch);
 begin case(ch)
 "O":title_glyph=15'b111_101_101_101_111;
 "R":title_glyph=15'b110_101_110_101_101;
 "I":title_glyph=15'b111_010_010_010_111;
 "G":title_glyph=15'b111_100_101_101_111;
 "N":title_glyph=15'b101_111_111_111_101;
 "A":title_glyph=15'b010_101_111_101_101;
 "L":title_glyph=15'b100_100_100_100_111;
 "E":title_glyph=15'b111_100_110_100_111;
 "T":title_glyph=15'b111_010_010_010_010;
 default:title_glyph=0;
 endcase end endfunction
 localparam [63:0] LEFT_TITLE="ORIGINAL",RIGHT_TITLE="LINE ART";
 reg [23:0] c;reg [14:0] g;integer digit,gx,gy;
 reg [63:0] title;integer tx;
 always @*begin
  c=24'h102040;g=0;digit=0;gx=0;gy=0;title=0;tx=0;
  // Pipeline RGB corresponds exactly to these one-cycle delayed coordinates.
  if(y>=120&&y<600)c=pipeline_rgb;
  // Preserve the real CPU-provided R/P/D FPS box above the diagnostic pages.
  if(x>=8&&x<146&&y>=8&&y<29)c=pipeline_rgb;
  if(y>=64&&y<84&&((x>=256&&x<384)||(x>=896&&x<1024)))begin
   title=x<640?LEFT_TITLE:RIGHT_TITLE;tx=x<640?x-256:x-896;
   digit=tx/16;gx=(tx%16)/4;gy=(y-64)/4;
   g=title_glyph((title>>(56-digit*8))&255);
   if(gx<3&&g[14-gy*3-gx])c=24'he8efff;
  end
  if(x>=64&&x<448&&y>=640&&y<680)begin
   digit=(x-64)>>6;gx=((x-64)&63)>>3;gy=(y-640)>>3;
   g=glyph((live>>(20-digit*4))&15);
   if(gx<3&&g[14-gy*3-gx])c=24'hffffff;
  end
  // Separate right-hand telemetry: left diagnostic pages/faults remain visible.
  if(status_live[23:20]==4'h7 && x>=768&&x<1152&&y>=640&&y<680)begin
   digit=(x-768)>>6;gx=((x-768)&63)>>3;gy=(y-640)>>3;
   g=glyph((status_live>>(20-digit*4))&15);
   if(gx<3&&g[14-gy*3-gx])c=24'hffffff;
  end
  if((y<120||y>=600)&&(x<4||x>=1276||y<4||y>=716))c=24'h00ffff;
 end
 always @(posedge clk or negedge up)begin
  if(!up)begin s1<=0;s2<=0;s3<=0;live<=0;status_live<=0;frames<=0;rgb<=0;de<=0;hs<=0;vs<=0;end
  else begin
   s1<={page_d_async,page_c_async,page_b_async,page_a_async,status_async};s2<=s1;s3<=s2;
   if(fs)begin
    status_live<=s3[23:0];
    case((frames>>PAGE_SHIFT)&7)
     1:live<=s3[47:24];2:live<=s3[71:48];3:live<=s3[95:72];4:live<=s3[119:96];default:live<=s3[23:0];
    endcase
    frames<=frames+1'b1;
   end
   rgb<=rd?c:24'd0;de<=rd;hs<=rh;vs<=rv;
  end
 end
endmodule
