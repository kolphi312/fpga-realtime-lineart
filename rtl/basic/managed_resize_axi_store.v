`timescale 1ns/1ps
// One producer and one consumer. Bank READY comes only from a fully drained
// writer result. A locked writer retains WRITING ownership until reset.
module managed_resize_axi_store #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,OW=640,OH=480,
 parameter FIFO_LOG2=8,MAX_BEATS=16,BANKS=4,INDEX_W=$clog2(BANKS),
 parameter [31:0] POOL_BASE=32'h01000000,BANK_STRIDE=32'h00200000
)(
 input wire clk,rst_n,cmd_valid,output wire cmd_ready,input wire [31:0] cmd_id,
 input wire in_valid,in_sof,in_eol,in_frame_end,in_abort,input wire [23:0] in_rgb,
 input wire read_request,output wire read_ready,output wire [INDEX_W-1:0] read_bank,
 output wire [31:0] read_addr,read_frame_id,input wire read_release,
 output wire [31:0] writing_addr,output wire [BANKS*2-1:0] bank_states,
 output wire busy,locked,frame_good,frame_bad,output wire [3:0] reason,output wire [31:0] frame_id,
 output wire [FIFO_LOG2:0] high_water,output wire [31:0] overflow_frames,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
 wire pool_ready,store_ready,pool_error,store_locked,wb,rb;
 wire [INDEX_W-1:0] writing_bank;
 assign cmd_ready=pool_ready&&store_ready;
 assign locked=pool_error||store_locked;
 frame_bank_owner #(.BANKS(BANKS),.INDEX_W(INDEX_W),.POOL_BASE(POOL_BASE),.BANK_STRIDE(BANK_STRIDE),.FRAME_BYTES(OW*OH*4)) owner (
  .clk(clk),.rst_n(rst_n),.write_request(cmd_valid&&store_ready),.write_frame_id(cmd_id),
  .write_ready(pool_ready),.write_bank(writing_bank),.write_addr(writing_addr),
  .write_done(frame_good||(frame_bad&&!store_locked)),.write_ok(frame_good),
  .read_request(read_request),.read_ready(read_ready),.read_bank(read_bank),.read_addr(read_addr),.read_frame_id(read_frame_id),.read_release(read_release),
  .protocol_error(pool_error),.writer_busy(wb),.reader_busy(rb),.bank_states(bank_states));
 resize_axi_store #(.IW(IW),.IH(IH),.CX(CX),.CY(CY),.CW(CW),.CH(CH),.OW(OW),.OH(OH),.FIFO_LOG2(FIFO_LOG2),.MAX_BEATS(MAX_BEATS)) store (
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid&&pool_ready),.cmd_ready(store_ready),.cmd_base(writing_addr),.cmd_id(cmd_id),
  .in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),.in_frame_end(in_frame_end),.in_abort(in_abort),.in_rgb(in_rgb),
  .busy(busy),.locked(store_locked),.frame_good(frame_good),.frame_bad(frame_bad),.reason(reason),.frame_id(frame_id),
  .high_water(high_water),.overflow_frames(overflow_frames),
  .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
endmodule
