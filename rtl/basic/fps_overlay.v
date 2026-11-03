`timescale 1ns/1ps
// Rxx Pxx Dxx: raw sensor, processed, distinct-display FPS, supplied by CPU
// in packed BCD. No hidden hardware frame-rate estimate. Red border = skips.
// Select/color pipeline is parallel to the display bridge's one pixel stage.
module fps_overlay(
 input wire clk,rst_n,frame_start,message_valid,input wire [31:0] message,
 input wire de,input wire [11:0] x,y,output reg select,output reg [23:0] color
);
 reg [31:0] live;
 function [14:0] glyph(input [3:0] n);
 begin case(n)
  0:glyph=15'b111_101_101_101_111;1:glyph=15'b010_110_010_010_111;
  2:glyph=15'b111_001_111_100_111;3:glyph=15'b111_001_111_001_111;
  4:glyph=15'b101_101_111_001_001;5:glyph=15'b111_100_111_001_111;
  6:glyph=15'b111_100_111_101_111;7:glyph=15'b111_001_010_010_010;
  8:glyph=15'b111_101_111_101_111;9:glyph=15'b111_101_111_001_111;
  10:glyph=15'b110_101_110_101_101; // R
  11:glyph=15'b110_101_110_100_100; // P
  12:glyph=15'b110_101_101_101_110; // D
  default:glyph=0;
 endcase end endfunction
 reg box,border,ink;reg [3:0] digit;reg [14:0] bits;
 integer dx,dy,cellno,gx,gy;
 always @*begin
  box=de&&live[31]&&x>=8&&x<146&&y>=8&&y<29;
  border=box&&(x==8||x==145||y==8||y==28);ink=0;digit=15;bits=0;
  dx=x-11;dy=y-11;cellno=0;gx=0;gy=0;
  if(box&&dx>=0&&dx<132&&dy>=0&&dy<15)begin
   cellno=dx/12;gx=(dx%12)/3;gy=dy/3;
   case(cellno)
    0:digit=10;1:digit=live[23:20];2:digit=live[19:16];
    4:digit=11;5:digit=live[15:12];6:digit=live[11:8];
    8:digit=12;9:digit=live[7:4];10:digit=live[3:0];default:digit=15;
   endcase
   bits=glyph(digit);if(gx<3)ink=bits[14-gy*3-gx];
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin live<=0;select<=0;color<=0;end
  else begin
   if(frame_start&&message_valid)live<=message;
   select<=box;color<=border?(live[30]?24'hff3030:24'hffffff):(ink?24'hffffff:24'h000000);
  end
 end
endmodule
