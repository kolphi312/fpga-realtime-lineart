`timescale 1ns/1ps
// Sync -> back porch -> active -> front porch. Coordinates valid only with DE.
module video_raster #(
 parameter HA=1920,HF=88,HS=44,HB=148,VA=1080,VF=4,VS=5,VB=36,
 parameter H_POL=1,V_POL=1
)(input wire clk,rst_n,output wire frame_start,de,hs,vs,output wire [11:0] x,y);
 localparam HT=HA+HF+HS+HB,VT=VA+VF+VS+VB;
 reg [11:0] h,v;
 assign frame_start=(h==0)&&(v==0);
 assign de=(h>=HS+HB)&&(h<HS+HB+HA)&&(v>=VS+VB)&&(v<VS+VB+VA);
 assign x=de?h-(HS+HB):0;assign y=de?v-(VS+VB):0;
 assign hs=(h<HS)?H_POL:!H_POL;assign vs=(v<VS)?V_POL:!V_POL;
 initial if(HA<1||VA<1||HT>4096||VT>4096||HS<1||VS<1)$fatal(1,"raster parameters");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin h<=0;v<=0;end
  else if(h==HT-1)begin h<=0;v<=(v==VT-1)?0:v+1'b1;end
  else h<=h+1'b1;
 end
endmodule
