`timescale 1ns/1ps
// Acquisition-to-DDR candidate. Command must be accepted before its frame is
// consumed. A new frame waits in the CSI FIFO until the prior command retires.
// CSI cannot be backpressured: excessive waiting is an explicit capture fault.
// CFA is configurable; CFA=1 is a candidate, not a hardware phase calibration.
module sc2210_rgb_store #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,OW=640,OH=480,CFA=1,
 parameter CAPTURE_LOG2=9,FIFO_LOG2=8,MAX_BEATS=16,BANKS=4,INDEX_W=$clog2(BANKS),
 parameter [31:0] POOL_BASE=32'h01000000,BANK_STRIDE=32'h00200000
)(
 input wire clk,csi_clk,rst_n,input wire csi_fv,csi_lv,csi_de,input wire [47:0] csi_raw,
 input wire cmd_valid,output wire cmd_ready,input wire [31:0] cmd_id,
 input wire read_request,output wire read_ready,output wire [INDEX_W-1:0] read_bank,
 output wire [31:0] read_addr,read_frame_id,input wire read_release,
 output wire [31:0] writing_addr,output wire [BANKS*2-1:0] bank_states,
 output wire busy,locked,frame_good,frame_bad,output wire [3:0] reason,output wire [31:0] frame_id,
 output wire capture_fault,bayer_fault,
 output wire [FIFO_LOG2:0] high_water,output wire [31:0] overflow_frames,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
 wire sys_up;
 reset_release sys_reset(.clk(clk),.arst_n(rst_n),.srst_n(sys_up));
 wire cap_valid,cap_ready,cap_sof,cap_eol,cap_end,cap_abort,source_fault;
 wire [7:0] cap_raw;wire [31:0] source_frames;wire [3:0] cap_reason,bayer_reason;
 wire rgb_valid,rgb_sof,rgb_eol,rgb_end,rgb_abort,bayer_ready;wire [23:0] rgb;
 wire store_ready,store_locked;
 reg command_live,source_closed;
 wire enabled=sys_up&&!command_live&&!capture_fault&&!bayer_fault;
 assign cmd_ready=store_ready&&enabled;
 assign cap_ready=bayer_ready&&command_live&&!source_closed;
 assign locked=store_locked||capture_fault||bayer_fault;
 always @(posedge clk or negedge sys_up)begin
  if(!sys_up)begin command_live<=0;source_closed<=1;end
  else begin
   if(cmd_valid&&cmd_ready)begin command_live<=1;source_closed<=0;end
   if(cap_valid&&cap_ready&&cap_end)source_closed<=1;
   if(frame_good||frame_bad)begin command_live<=0;source_closed<=1;end
  end
 end
 sc2210_raw_capture #(.WIDTH(IW),.HEIGHT(IH),.FIFO_LOG2(CAPTURE_LOG2)) capture (
  .arst_n(rst_n),.csi_clk(csi_clk),.pixel_clk(clk),.csi_fv(csi_fv),.csi_lv(csi_lv),.csi_de(csi_de),.csi_raw(csi_raw),
  .out_valid(cap_valid),.out_ready(cap_ready),.out_raw(cap_raw),.out_sof(cap_sof),.out_eol(cap_eol),.out_frame_end(cap_end),
  .source_fault(source_fault),.fault(capture_fault),.abort_pulse(cap_abort),.source_frames(source_frames),.fault_reason(cap_reason));
 bayer_bilinear_stream #(.WIDTH(IW),.HEIGHT(IH),.CFA(CFA)) demosaic (
  .clk(clk),.rst_n(sys_up),.in_valid(cap_valid&&command_live&&!source_closed),.in_ready(bayer_ready),
  .in_raw(cap_raw),.in_sof(cap_sof),.in_eol(cap_eol),.in_frame_end(cap_end),.in_abort(cap_abort),
  .out_valid(rgb_valid),.out_sof(rgb_sof),.out_eol(rgb_eol),.out_frame_end(rgb_end),.out_rgb(rgb),
  .fault(bayer_fault),.out_abort(rgb_abort),.reason(bayer_reason));
 managed_resize_axi_store #(.IW(IW),.IH(IH),.CX(CX),.CY(CY),.CW(CW),.CH(CH),.OW(OW),.OH(OH),
  .FIFO_LOG2(FIFO_LOG2),.MAX_BEATS(MAX_BEATS),.BANKS(BANKS),.INDEX_W(INDEX_W),.POOL_BASE(POOL_BASE),.BANK_STRIDE(BANK_STRIDE)) store (
  .clk(clk),.rst_n(sys_up),.cmd_valid(cmd_valid&&enabled),.cmd_ready(store_ready),.cmd_id(cmd_id),
  .in_valid(rgb_valid),.in_sof(rgb_sof),.in_eol(rgb_eol),.in_frame_end(rgb_end),.in_abort(rgb_abort),.in_rgb(rgb),
  .read_request(read_request),.read_ready(read_ready),.read_bank(read_bank),.read_addr(read_addr),.read_frame_id(read_frame_id),.read_release(read_release),
  .writing_addr(writing_addr),.bank_states(bank_states),.busy(busy),.locked(store_locked),.frame_good(frame_good),.frame_bad(frame_bad),.reason(reason),.frame_id(frame_id),
  .high_water(high_water),.overflow_frames(overflow_frames),
  .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
endmodule
