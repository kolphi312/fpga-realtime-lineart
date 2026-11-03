`timescale 1ns/1ps
// One job, disjoint source/destination ranges. Safe completion waits for BOTH
// DMA engines; locked AXI never releases ownership, needs coordinated reset.
module cnn2_axi #(parameter W=640,H=480,PROBE_LIMIT=96000000)(
 input wire clk,rst_n,
 input wire cmd_valid,output wire cmd_ready,input wire [31:0] src_base,dst_base,cmd_id,
 output reg busy,done,ok,output wire locked,output reg [3:0] reason,output reg [31:0] result_id,
 input wire cfg_valid,input wire [5:0] cfg_addr,input wire [31:0] cfg_data,
 output wire cfg_ready,configured,cfg_error,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,input wire rlast,rvalid,output wire rready,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready,
 output wire progress_frozen,output wire [23:0] progress_a,progress_b,progress_c,progress_d,progress_id
);
 localparam [32:0] BYTES=33'd4*W*H;
 wire [32:0] se={1'b0,src_base}+BYTES,de={1'b0,dst_base}+BYTES;
 wire valid_range=src_base[3:0]==0&&dst_base[3:0]==0&&se<=33'h100000000&&de<=33'h100000000&&
  (se<={1'b0,dst_base}||de<={1'b0,src_base});
 wire rc,wc,rl,wl,rb,wb,rg,rerr,wg,werr;wire [3:0] rr,wr;wire [31:0] ri,wi;
 wire cv,ci,cs,cl,cf,co,cor,cos,col,cof,c_busy,c_done,c_fault,cc,ce,wready_pixel;wire [23:0] crgb,corgb;
 reg failed,read_end,write_end,core_end,source_sent;
 wire [2:0] rstate,wstate;wire [3:0] cstate;
 assign locked=rl||wl;
 assign cmd_ready=!busy&&!locked&&rc&&wc&&!c_busy&&!cfg_valid;
 wire accept=cmd_valid&&cmd_ready;
 wire launch=accept&&valid_range&&configured;
 assign cfg_ready=!busy&&cc;
 assign cfg_error=(cfg_valid&&!cfg_ready)||ce;
 wire abort_core=busy&&(failed||rerr||locked);
 assign ci=failed||locked||c_fault ? 1'b1:cor;
 wire source_done=busy&&!source_sent&&(failed||rerr||locked||((core_end||c_done)&&(read_end||rg)));
 wire source_ok=!(failed||rerr||locked||c_fault)&&(core_end||c_done)&&(read_end||rg);
 cnn2_stream #(.W(W),.H(H)) core(
  .debug_state(cstate),.clk(clk),.rst_n(rst_n),.start(launch),.abort(abort_core),
  .cfg_valid(cfg_valid&&!busy),.cfg_addr(cfg_addr),.cfg_data(cfg_data),.cfg_ready(cc),.configured(configured),.cfg_error(ce),
  .in_valid(cv&&!failed&&!locked),.in_ready(cor),.in_rgb(crgb),.in_sof(cs),.in_eol(cl),.in_eof(cf),
  .out_valid(co),.out_ready(wready_pixel),.out_rgb(corgb),.out_sof(cos),.out_eol(col),.out_eof(cof),.busy(c_busy),.done(c_done),.fault(c_fault));
 rgb_frame_axi_reader #(.FRAME_PIXELS(W*H),.WIDTH(W),.ROW_BURSTS(1)) reader(.debug_state(rstate),.burst_credit(32'd0),
  .clk(clk),.rst_n(rst_n),.cmd_valid(launch),.cmd_ready(rc),.cmd_base(src_base),.cmd_id(cmd_id),
  .busy(rb),.locked(rl),.frame_good(rg),.frame_bad(rerr),.reason(rr),.frame_id(ri),
  .out_valid(cv),.out_ready(ci),.out_rgb(crgb),.out_sof(cs),.out_eol(cl),.out_eof(cf),
  .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rid(rid),.rresp(rresp),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 rgb_frame_axi_writer #(.FRAME_PIXELS(W*H)) writer(
  .clk(clk),.rst_n(rst_n),.cmd_valid(launch),.cmd_ready(wc),.cmd_base(dst_base),.cmd_id(cmd_id),
  .debug_state(wstate),.s_valid(co&&!failed&&!locked),.s_ready(wready_pixel),.s_rgb(corgb),.source_done(source_done),.source_ok(source_ok),
  .busy(wb),.locked(wl),.frame_good(wg),.frame_bad(werr),.reason(wr),.frame_id(wi),
  .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;done<=0;ok<=0;reason<=0;result_id<=0;failed<=0;read_end<=0;write_end<=0;core_end<=0;source_sent<=0;end
  else begin
   done<=0;
   if(accept)begin
    result_id<=cmd_id;ok<=0;reason<=0;failed<=0;read_end<=0;write_end<=0;core_end<=0;source_sent<=0;
    if(launch)busy<=1;else begin done<=1;reason<=!configured?1:2;end
   end
   if(busy)begin
    if(rg||rerr)read_end<=1;
    if(wg||werr)write_end<=1;
    if(c_done)core_end<=1;
    if(source_done)source_sent<=1;
    // Preserve the initiating error; a deliberately aborted writer is secondary.
    if(rerr)begin failed<=1;if(!failed)reason<=3;end
    if(werr)begin failed<=1;if(!failed&&!rerr)reason<=4;end
    if(c_fault)begin failed<=1;if(!failed&&!rerr&&!werr)reason<=5;end
    if(locked)begin failed<=1;reason<=6;end
    if(read_end&&write_end&&!rb&&!wb&&!locked)begin busy<=0;done<=1;ok<=!failed;end
   end
  end
 end
// Observer has no outputs into the data/control path. Snapshot precedes the
 // software 2-second watchdog; threshold denotes a long job, not a diagnosis.
 job_progress_probe #(.LIMIT(PROBE_LIMIT)) progress_probe(
  .clk(clk),.rst_n(rst_n),.launch(launch),.busy(busy),.job_id(cmd_id),
  .states({1'b1,rstate,cstate,wstate,busy,read_end,write_end,core_end,source_sent,failed,locked,rb,wb}),
  .flow({arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready,cv,ci,co,wready_pixel,c_busy,c_done,c_fault,configured}),
  .input_fire(cv&&ci),.output_fire(co&&wready_pixel&&!failed&&!locked),
  .frozen(progress_frozen),.page_a(progress_a),.page_b(progress_b),.page_c(progress_c),.page_d(progress_d),.page_id(progress_id));
endmodule
