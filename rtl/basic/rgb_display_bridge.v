`timescale 1ns/1ps
// One requested frame at a time. Source and pixel domains reset together.
// Raster never stalls. On underflow/marker error, black the remainder and drain
// to EOF/ABORT. Missing terminal or locked AXI deliberately prevents completion.
// session_done, NOT DMA frame_good, is the display ownership completion event.
// Request/complete toggles and FIFO Gray buses need board-level CDC constraints.
module rgb_display_bridge #(
 parameter WIDTH=640,HEIGHT=480,X0=640,Y0=300,FIFO_LOG2=10,PREFILL=0
)(
 input wire arst_n,sys_clk,pix_clk,
 output reg request_valid,input wire request_ready,
 output reg busy,session_done,session_bad,
 input wire in_valid,output wire in_ready,output wire [31:0] in_space,input wire [23:0] in_rgb,
 input wire in_sof,in_eol,in_eof,input wire in_abort,
 input wire raster_start,raster_de,raster_hs,raster_vs,
 input wire [11:0] raster_x,raster_y,
 output reg [23:0] rgb,output reg de,hs,vs
);
 wire wup,rup,fwready,frvalid,frready;wire [27:0] frdata;
 reg accepted,closed,abort_pending;
 reg req_toggle,done_toggle,done_bad,done_ack;
 (* async_reg="true" *) reg req_s1,req_s2,done_s1,done_s2;
 (* async_reg="true" *) reg ack_p1,ack_p2;
 (* async_reg="true" *) reg closed_p1,closed_p2;
 wire [FIFO_LOG2:0] available;
 wire [FIFO_LOG2:0] free_slots;
 reg req_seen,done_seen;
 assign in_ready=busy&&accepted&&!closed&&!abort_pending&&!in_abort&&fwready;
 assign in_space=busy&&accepted&&!closed&&!abort_pending&&!in_abort ? free_slots : 32'd0;
 wire fwvalid=(abort_pending||(in_valid&&in_ready));
 wire [27:0] fwdata=abort_pending?{4'b1000,24'b0}:{1'b0,in_sof,in_eol,in_eof,in_rgb};
 async_packet_fifo #(.WIDTH(28),.LOG2(FIFO_LOG2)) fifo(
  .arst_n(arst_n),.wclk(sys_clk),.rclk(pix_clk),.w_valid(fwvalid),.w_data(fwdata),.w_ready(fwready),
  .r_valid(frvalid),.r_data(frdata),.r_ready(frready),.w_up(wup),.r_up(rup),.r_level(available),.w_space(free_slots));
 always @(posedge sys_clk or negedge wup)begin
  if(!wup)begin
   req_s1<=0;req_s2<=0;done_s1<=0;done_s2<=0;req_seen<=0;done_seen<=0;done_ack<=0;
   request_valid<=0;busy<=0;session_done<=0;session_bad<=0;accepted<=0;closed<=0;abort_pending<=0;
  end else begin
   req_s1<=req_toggle;req_s2<=req_s1;done_s1<=done_toggle;done_s2<=done_s1;session_done<=0;
   if(req_s2!=req_seen)begin
    req_seen<=req_s2;request_valid<=1;busy<=1;accepted<=0;closed<=0;abort_pending<=0;
   end
   if(request_valid&&request_ready)begin request_valid<=0;accepted<=1;end
   // Abort is a terminal FIFO token, ordered after all previously accepted pixels.
   // Use only for a safely drained DMA error. A locked bus must NOT be aborted here.
   if(in_abort&&busy&&accepted&&!closed)begin abort_pending<=1;closed<=1;end
   if(abort_pending&&fwready)abort_pending<=0;
   if(in_valid&&in_ready&&in_eof)closed<=1;
   if(done_s2!=done_seen)begin
    done_seen<=done_s2;done_ack<=done_s2;session_done<=1;session_bad<=done_bad;
    busy<=0;accepted<=0;request_valid<=0;
   end
  end
 end
 localparam IDLE=0,SHOW=1,DRAIN=2,WAIT_ACK=3;
 reg [1:0] state;
 reg [31:0] count;
 wire in_window=raster_de&&(raster_x>=X0)&&(raster_x<X0+WIDTH)&&(raster_y>=Y0)&&(raster_y<Y0+HEIGHT);
 wire expected_sof=(raster_x==X0)&&(raster_y==Y0);
 wire expected_eol=(raster_x==X0+WIDTH-1);
 wire expected_eof=expected_eol&&(raster_y==Y0+HEIGHT-1);
 wire markers_ok=(frdata[26]==expected_sof)&&(frdata[25]==expected_eol)&&(frdata[24]==expected_eof);
 wire terminal=frdata[27]||frdata[24];
 // If the prefix is too short, defer the WHOLE window, not a few pixels.
 // A closed source permits short/error frames to drain to EOF/ABORT. closed
 // clears before acceptance/new FIFO writes; synchronization precedes fresh
 // FIFO head visibility, preventing an old close from admitting a new prefix.
 wire admitted=(available>=PREFILL)||closed_p2;
 wire consume_window=(count!=0)||(expected_sof&&admitted);
 assign frready=rup&&((state==DRAIN)||((state==SHOW)&&in_window&&consume_window));
 initial if(PREFILL<0||PREFILL>(1<<FIFO_LOG2))$fatal(1,"invalid display prefill");
 initial if(WIDTH<1||HEIGHT<1||X0<0||Y0<1||X0+WIDTH>4096||Y0+HEIGHT>4096)$fatal(1,"display geometry; Y0 must allow request prefetch");
 always @(posedge pix_clk or negedge rup)begin
  if(!rup)begin
   ack_p1<=0;ack_p2<=0;closed_p1<=0;closed_p2<=0;req_toggle<=0;done_toggle<=0;done_bad<=0;state<=IDLE;count<=0;
   rgb<=0;de<=0;hs<=0;vs<=0;
  end else begin
   ack_p1<=done_ack;ack_p2<=ack_p1;closed_p1<=closed;closed_p2<=closed_p1;
   rgb<=0;de<=raster_de;hs<=raster_hs;vs<=raster_vs;
   if(state==WAIT_ACK&&ack_p2==done_toggle)state<=IDLE;
   if(state==IDLE&&raster_start)begin req_toggle<=~req_toggle;state<=SHOW;count<=0;end
   if(state==SHOW&&in_window&&consume_window)begin
    if(!frvalid)begin if(count!=0)state<=DRAIN;end
    else begin
     count<=count+1;
     if(frdata[27]||!markers_ok)begin
      if(terminal)begin done_bad<=1;done_toggle<=~done_toggle;state<=WAIT_ACK;end
      else state<=DRAIN;
     end else begin
      rgb<=frdata[23:0];
      if(expected_eof)begin done_bad<=(count!=WIDTH*HEIGHT-1);done_toggle<=~done_toggle;state<=WAIT_ACK;end
     end
    end
   end
   // Before the first pixel, keep prefetch pending until a complete window starts.
   // After output starts, a skipped window/frame boundary still forces drain.
   if(state==SHOW&&raster_start&&(count!=0))state<=DRAIN;
   if(state==DRAIN&&frvalid&&frready&&terminal)begin
    done_bad<=1;done_toggle<=~done_toggle;state<=WAIT_ACK;
   end
  end
 end
endmodule
