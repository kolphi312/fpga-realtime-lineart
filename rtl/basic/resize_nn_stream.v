`timescale 1ns/1ps
// One RGB pixel per valid beat, no backpressure. SOF accompanies first pixel.
// Center-sampled nearest-neighbour downscale of an explicit ROI. Output markers
// describe a compact image stream, NOT HDMI HS/VS/DE timings.
module resize_nn_stream #(
    parameter IN_W=1920, IN_H=1080,
    parameter CROP_X=240,CROP_Y=0,CROP_W=1440,CROP_H=1080,
    parameter OUT_W=640,OUT_H=480
)(input wire clk,rst_n,in_valid,in_sof,
  input wire [23:0] in_rgb,
  output reg out_valid,out_sof,out_eol,out_eof,
  output reg [23:0] out_rgb,
  output reg protocol_error);
    localparam DX=2*OUT_W,DY=2*OUT_H;
    localparam X0=CROP_X+CROP_W/DX,Y0=CROP_Y+CROP_H/DY;
    localparam RX0=CROP_W%DX,RY0=CROP_H%DY;
    localparam XSTEP=CROP_W/OUT_W,YSTEP=CROP_H/OUT_H;
    localparam XR=(2*CROP_W)%DX,YR=(2*CROP_H)%DY;
    reg active;
    reg [31:0] ix,iy,ox,oy,nx,ny,rx,ry;
    wire [31:0] cx=in_sof?0:ix, cy=in_sof?0:iy;
    wire [31:0] tx=in_sof?X0:nx, ty=in_sof?Y0:ny;
    wire [31:0] qx=in_sof?0:ox, qy=in_sof?0:oy;
    wire [31:0] erx=(in_sof?RX0:rx)+XR;
    wire [31:0] ery=(in_sof?RY0:ry)+YR;
    initial begin
      if(IN_W<1||IN_H<1||OUT_W<1||OUT_H<1||CROP_X<0||CROP_Y<0||
         CROP_W<OUT_W||CROP_H<OUT_H||CROP_X+CROP_W>IN_W||CROP_Y+CROP_H>IN_H)
          $fatal(1,"Unsupported ROI/downscale parameters");
    end
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin
        active<=0;ix<=0;iy<=0;ox<=0;oy<=0;nx<=X0;ny<=Y0;rx<=RX0;ry<=RY0;
        out_valid<=0;out_sof<=0;out_eol<=0;out_eof<=0;out_rgb<=0;protocol_error<=0;
      end else begin
        out_valid<=0;out_sof<=0;out_eol<=0;out_eof<=0;
        if(in_sof&&!in_valid)protocol_error<=1;
        if(in_valid)begin
          if(in_sof)begin
            if(active)protocol_error<=1;
            active<=1;ox<=0;oy<=0;nx<=X0;ny<=Y0;rx<=RX0;ry<=RY0;
          end
          if(active||in_sof)begin
            if(cx==IN_W-1)begin
              ix<=0;
              if(cy==IN_H-1)begin iy<=0;active<=0;end else iy<=cy+1;
            end else begin ix<=cx+1;iy<=cy;end
            if(cx==tx && cy==ty && qy<OUT_H)begin
              out_valid<=1;out_rgb<=in_rgb;
              out_sof<=(qx==0&&qy==0);out_eol<=(qx==OUT_W-1);
              out_eof<=(qx==OUT_W-1&&qy==OUT_H-1);
              if(qx==OUT_W-1)begin
                ox<=0;oy<=qy+1;nx<=X0;rx<=RX0;
                ny<=ty+YSTEP+(ery>=DY);ry<=ery>=DY?ery-DY:ery;
              end else begin
                ox<=qx+1;nx<=tx+XSTEP+(erx>=DX);rx<=erx>=DX?erx-DX:erx;
              end
            end
          end else protocol_error<=1;
        end
      end
    end
endmodule
