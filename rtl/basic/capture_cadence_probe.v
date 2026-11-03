`timescale 1ns/1ps
// Passive SYS-domain period measurement. Arm only after CPU sensor setup/RUN.
// First complete periods latch permanently until reset; display may read later.
// C = line period in SYS cycles, D = frame period in 16 SYS cycles.
// Synchronizer quantization is +/- one SYS cycle; not a loss/FPS certification.
module capture_cadence_probe(input wire clk,rst_n,arm,input wire fv_async,lv_async,
 output wire [23:0] page_c,page_d);
 (* async_reg="true",syn_srlstyle="registers" *)reg [1:0] fv_sync,lv_sync;
 reg fv_old,lv_old,armed,frame_seen,line_seen,line_done,frame_done;
 reg [31:0] ticks,last_frame,last_line;
 reg [19:0] line_period,frame_period;
 wire fr=fv_sync[1]&&!fv_old,lr=lv_sync[1]&&!lv_old;
 wire [31:0] ld=ticks-last_line,fd=ticks-last_frame;
 assign page_c={4'hc,line_period};assign page_d={4'hd,frame_period};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   fv_sync<=0;lv_sync<=0;fv_old<=0;lv_old<=0;armed<=0;
   ticks<=0;last_frame<=0;last_line<=0;frame_seen<=0;line_seen<=0;
   line_done<=0;frame_done<=0;line_period<=0;frame_period<=0;
  end else begin
   fv_sync<={fv_sync[0],fv_async};lv_sync<={lv_sync[0],lv_async};
   fv_old<=fv_sync[1];lv_old<=lv_sync[1];ticks<=ticks+1'b1;
   if(arm)armed<=1;
   if(armed)begin
    if(fr)begin
     if(frame_seen&&!frame_done)begin
      frame_period<=(|fd[31:24])?20'hfffff:fd[23:4];frame_done<=1;
     end
     last_frame<=ticks;frame_seen<=1;line_seen<=0;
    end
    if(!fv_sync[1])line_seen<=0;
    if(lr&&fv_sync[1]&&!line_done)begin
     // fr has priority: never compare two lines across a frame boundary.
     if(line_seen&&!fr)begin line_period<=(|ld[31:20])?20'hfffff:ld[19:0];line_done<=1;end
     last_line<=ticks;line_seen<=1;
    end
   end
  end
 end
endmodule
