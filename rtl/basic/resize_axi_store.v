`timescale 1ns/1ps
// Offline integration baseline, ALL ports in one clock domain.
// Start a command BEFORE feeding its first input pixel. No input backpressure.
// Frame verdict is delayed until FIFO pixels have reached the writer; otherwise
// source EOF could be mistaken for a short frame while pixels are still queued.
module resize_axi_store #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,OW=640,OH=480,
 parameter FIFO_LOG2=8,MAX_BEATS=16
)(
 input wire clk,rst_n,cmd_valid,output wire cmd_ready,input wire [31:0] cmd_base,cmd_id,
 input wire in_valid,in_sof,in_eol,in_frame_end,in_abort,input wire [23:0] in_rgb,
 output reg [23:0] capture_page,
 output wire busy,locked,frame_good,frame_bad,output wire [3:0] reason,output wire [31:0] frame_id,
 output reg [FIFO_LOG2:0] high_water,output reg [31:0] overflow_frames,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
 localparam DEPTH=1<<FIFO_LOG2;
 wire [FIFO_LOG2:0] occupancy;
 wire fifo_valid,fifo_ready;
 wire [23:0] fifo_data;
 reg live,capture,verdict_pending,verdict_ok;
 wire writer_ready,pixel_ready,guard_good,guard_bad,guard_busy;
 wire gv,gs,gl,ge;wire [23:0] grgb;wire [31:0] gid,gc,bc;wire [7:0] guard_reason;
 rgb_sync_fifo #(.LOG2(FIFO_LOG2)) queue (
  .clk(clk),.rst_n(rst_n),.in_valid(gv),.in_ready(fifo_ready),.in_data(grgb),
  .out_valid(fifo_valid),.out_ready(pixel_ready),.out_data(fifo_data),.occupancy(occupancy));
 wire deliver_verdict=verdict_pending&&(occupancy==0)&&!gv;
 assign cmd_ready=writer_ready&&!live&&(occupancy==0)&&!guard_busy&&!verdict_pending;
 wire accept_cmd=cmd_valid&&cmd_ready;
 wire [23:0] diagnostic_rgb;
 capture_pattern_mux #(.W(OW),.H(OH)) pattern_mux(.clk(clk),.rst_n(rst_n),
  .start(accept_cmd),.job_id(cmd_id),.pixel_fire(fifo_valid&&pixel_ready),
  .in_rgb(fifo_data),.out_rgb(diagnostic_rgb));
 resize_frame_guard #(.IW(IW),.IH(IH),.CX(CX),.CY(CY),.CW(CW),.CH(CH),.OW(OW),.OH(OH)) guard (
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid&&capture),.in_sof(in_sof&&capture),.in_eol(in_eol&&capture),
  .in_frame_end(in_frame_end&&capture),.in_abort(in_abort&&capture),.in_rgb(in_rgb),.sink_ready(fifo_ready),
  .out_valid(gv),.out_sof(gs),.out_eol(gl),.out_eof(ge),.out_rgb(grgb),.frame_id(gid),
  .frame_good(guard_good),.frame_bad(guard_bad),.reason(guard_reason),.good_count(gc),.bad_count(bc),.busy(guard_busy));
 rgb_frame_axi_writer_buffered #(.FRAME_PIXELS(OW*OH),.MAX_BEATS(MAX_BEATS)) writer (
  .clk(clk),.rst_n(rst_n),.cmd_valid(accept_cmd),.cmd_ready(writer_ready),.cmd_base(cmd_base),.cmd_id(cmd_id),
  .s_valid(fifo_valid),.s_ready(pixel_ready),.s_rgb(diagnostic_rgb),.source_done(deliver_verdict),.source_ok(verdict_ok),
  .busy(busy),.locked(locked),.frame_good(frame_good),.frame_bad(frame_bad),.reason(reason),.frame_id(frame_id),
  .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
 wire [8:0] diag_level=(high_water>511)?9'd511:high_water;
 initial if(FIFO_LOG2<1||FIFO_LOG2>16)$fatal(1,"unsupported FIFO depth");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   high_water<=0;overflow_frames<=0;capture_page<=0;
   live<=0;capture<=0;verdict_pending<=0;verdict_ok<=0;
  end else begin
   if(accept_cmd)begin live<=1;capture<=1;end
   // First invalid-frame event only. guard_reason may be overwritten by
   // subsequent stray pixels; retain the original before downstream draining.
   if(guard_bad&&!capture_page[19])begin
    capture_page<={4'hc,1'b1,guard_reason[2:0],diag_level,
      verdict_ok,busy,awvalid,awready,wvalid,wready,bvalid};
   end
   if(capture&&(guard_good||guard_bad))begin
    capture<=0;verdict_pending<=1;verdict_ok<=guard_good&&!guard_bad;
    if(guard_bad&&guard_reason==4)overflow_frames<=overflow_frames+1;
   end
   if(deliver_verdict)verdict_pending<=0;
   if(frame_good||frame_bad)begin live<=0;capture<=0;end
   if(occupancy>high_water)high_water<=occupancy;
  end
 end
endmodule
