`timescale 1ns/1ps
// Normalized acquisition stream, single clock, NO backpressure to camera.
// SOF accompanies first pixel; EOL accompanies last pixel of every input row.
// frame_end is an independent acquisition event (may accompany last pixel).
// A resize EOF alone NEVER publishes a frame. At least 3 idle clocks are
// required after frame_end, for output drain and result publication.
// Output pixels are speculative until frame_good. This is NOT a DDR commit:
// the writer must also wait for all successful AXI write responses.
module resize_frame_guard #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,OW=640,OH=480
)(
 input wire clk,rst_n,
 input wire in_valid,in_sof,in_eol,in_frame_end,in_abort,
 input wire [23:0] in_rgb,
 input wire sink_ready,
 output wire out_valid,out_sof,out_eol,out_eof,
 output wire [23:0] out_rgb,
 output reg [31:0] frame_id,
 output reg frame_good,frame_bad,
 output reg [7:0] reason,
 output reg [31:0] good_count,bad_count,
 output wire busy
);
 localparam IDLE=0,RUN=1,DRAIN1=2,DRAIN2=3;
 localparam E_MARKER=1,E_GEOMETRY=2,E_SHORT=3,E_SINK=4,E_ABORT=5,E_OUTPUT=6,E_BUSY=7;
 reg [1:0] state;
 reg [31:0] x,y,pixels,outputs,out_col,seq;
 reg saw_eof;
 wire start=(state==IDLE)&&in_valid&&in_sof;
 wire step=(state==RUN)||start;
 wire [31:0] px=start?0:x, py=start?0:y;
 wire [31:0] count_in=start?0:pixels;
 wire geom_bad=in_valid&&step&&((count_in>=IW*IH)||(py>=IH)||(in_eol!=(px==IW-1)));
 wire marker_bad=(in_sof&&!in_valid)||(in_eol&&!in_valid)||((state==RUN)&&in_sof);
 wire end_bad=in_frame_end&&step&&((count_in+(in_valid?1:0))!=IW*IH);
 wire raw_valid,raw_sof,raw_eol,raw_eof,raw_error;
 wire [23:0] raw_rgb;
 wire receiving=(state!=IDLE);
 wire sink_bad=receiving&&raw_valid&&!sink_ready;
 wire busy_bad=(state==DRAIN1||state==DRAIN2)&&(in_valid||in_sof||in_eol||in_frame_end);
 wire fatal_now=geom_bad||marker_bad||end_bad||sink_bad||in_abort||busy_bad;
 resize_nn_stream #(.IN_W(IW),.IN_H(IH),.CROP_X(CX),.CROP_Y(CY),.CROP_W(CW),.CROP_H(CH),.OUT_W(OW),.OUT_H(OH)) core (
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid&&step&&!fatal_now),.in_sof(start&&!fatal_now),.in_rgb(in_rgb),
  .out_valid(raw_valid),.out_sof(raw_sof),.out_eol(raw_eol),.out_eof(raw_eof),.out_rgb(raw_rgb),.protocol_error(raw_error));
 // The core's sticky error may reflect a deliberately aborted frame; this
 // wrapper owns per-frame validation and resynchronizes the core at next SOF.
 wire out_bad;
 assign out_valid=receiving&&raw_valid&&!fatal_now&&!out_bad;
 assign out_sof=out_valid&&raw_sof;
 assign out_eol=out_valid&&raw_eol;
 assign out_eof=out_valid&&raw_eof;
 assign out_rgb=raw_rgb;
 assign busy=(state!=IDLE);
 assign out_bad=receiving&&raw_valid&&(
   outputs>=OW*OH || raw_sof!=(outputs==0) || raw_eol!=(out_col==OW-1) || raw_eof!=(outputs==OW*OH-1));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=IDLE;x<=0;y<=0;pixels<=0;outputs<=0;out_col<=0;saw_eof<=0;seq<=0;frame_id<=0;
   frame_good<=0;frame_bad<=0;reason<=0;good_count<=0;bad_count<=0;
  end else begin
   frame_good<=0;frame_bad<=0;
   if(start)begin
    frame_id<=seq;seq<=seq+1;outputs<=0;out_col<=0;saw_eof<=0;reason<=0;state<=RUN;
   end
   if(in_valid&&step)begin
    pixels<=count_in+1;
    if(px==IW-1)begin x<=0;y<=py+1;end else begin x<=px+1;y<=py;end
   end
   if(receiving&&raw_valid)begin
    outputs<=outputs+1;out_col<=(out_col==OW-1)?0:out_col+1;
    if(raw_eof)saw_eof<=1;
   end
   if(in_frame_end&&step)state<=DRAIN1;
   if(state==DRAIN1)state<=DRAIN2;
   if(state==DRAIN2&&!fatal_now&&!out_bad)begin
    state<=IDLE;
    if(outputs==OW*OH&&saw_eof)begin frame_good<=1;good_count<=good_count+1;end
    else begin frame_bad<=1;bad_count<=bad_count+1;reason<=E_OUTPUT;end
   end
   if((step||receiving)&&(fatal_now||out_bad))begin
    state<=IDLE;frame_good<=0;frame_bad<=1;bad_count<=bad_count+1;
    if(in_abort)reason<=E_ABORT;
    else if(marker_bad)reason<=E_MARKER;
    else if(geom_bad)reason<=E_GEOMETRY;
    else if(end_bad)reason<=E_SHORT;
    else if(sink_bad)reason<=E_SINK;
    else if(busy_bad)reason<=E_BUSY;
    else reason<=E_OUTPUT;
   end
   // Stray input outside a frame cannot create a successful frame. Report
   // each malformed beat, so bad_count is rejected transactions, not FPS.
   if(state==IDLE&&!start&&(in_valid||in_sof||in_eol||in_frame_end||in_abort))begin
    frame_bad<=1;bad_count<=bad_count+1;reason<=E_MARKER;
   end
  end
 end
endmodule
