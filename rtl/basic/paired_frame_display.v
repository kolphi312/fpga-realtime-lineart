`timescale 1ns/1ps
// Paired-owner consumer: retain source AND result for repeat refreshes. Replace
// only at a new display request when a READY pair exists. Safe release requires
// both the pixel-domain session terminal and a retired AXI command.
// Reset must be coordinated with owner, FIFO and AXI fabric. CDC constraints
// are required on bridge toggles and FIFO Gray pointers at board integration.
module paired_frame_display #(
 parameter W=640,H=480,X0=0,Y0=120,FIFO_LOG2=11,BANKS=4,PREFILL=0
)(
 input wire arst_n,sys_clk,pix_clk,halt_new,
 output wire pair_request,input wire pair_ready,
 input wire [31:0] pair_src,pair_dst,pair_id,input wire [BANKS*3-1:0] pair_states,
 output wire pair_release,output wire [31:0] release_id,
 output reg held,output wire locked,output reg session_done,session_bad,
 output wire [31:0] displayed_id,
 input wire raster_start,raster_de,raster_hs,raster_vs,input wire [11:0] raster_x,raster_y,
 output wire [23:0] rgb,output wire de,hs,vs,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,
 input wire rlast,rvalid,output wire rready
);
 wire up;reset_release reset_sys(.clk(sys_clk),.arst_n(arst_n),.srst_n(up));
 localparam SELECT=0,COMMAND=1,RUN=2;
 reg [1:0] state;reg [31:0] src_q,dst_q,id_q;
 reg dma_seen,display_seen,bad_seen;
 reg queued;
 always @*begin
  queued=0;for(integer j=0;j<BANKS;j=j+1)if(pair_states[j*3+:3]==3'd4)queued=1;
 end
 wire req,reqready,bridge_busy,cmdready,dma_busy,dma_good,dma_bad;
 wire bridge_done,bridge_bad;wire [3:0] reason;wire [31:0] dma_id;
 wire iv,ir,sof,eol,eof;wire [23:0] pixel;
 wire [31:0] space_available;
 wire complete=(state==RUN)&&(dma_seen||dma_good||dma_bad)&&(display_seen||bridge_done)&&!dma_busy&&!locked;
 wire failed=bad_seen||dma_bad||(bridge_done&&bridge_bad);
 assign displayed_id=id_q;assign release_id=id_q;
 assign pair_request=(state==SELECT)&&req&&!held&&!locked&&!halt_new;
 assign pair_release=!locked&&held&&(((state==SELECT)&&req&&queued&&!halt_new)||(complete&&failed));
 assign reqready=(state==COMMAND)&&cmdready&&!locked&&!halt_new;
 always @(posedge sys_clk or negedge up)begin
  if(!up)begin
   state<=SELECT;held<=0;src_q<=0;dst_q<=0;id_q<=0;dma_seen<=0;display_seen<=0;bad_seen<=0;session_done<=0;session_bad<=0;
  end else begin
   session_done<=0;
   if(!locked)begin
    if(state==SELECT&&req&&!halt_new)begin
     if(held)begin if(queued)held<=0;else state<=COMMAND;end
     else if(pair_ready)begin held<=1;src_q<=pair_src;dst_q<=pair_dst;id_q<=pair_id;state<=COMMAND;end
    end
    if(state==COMMAND&&req&&reqready)begin state<=RUN;dma_seen<=0;display_seen<=0;bad_seen<=0;end
    if(state==RUN)begin
     if(dma_good||dma_bad)begin dma_seen<=1;if(dma_bad)bad_seen<=1;end
     if(bridge_done)begin display_seen<=1;if(bridge_bad)bad_seen<=1;end
     if(complete)begin state<=SELECT;session_done<=1;session_bad<=failed;if(failed)held<=0;end
    end
   end
  end
 end
 paired_split_reader #(.W(W),.H(H),.CREDIT_GATED(1)) reader(
  .clk(sys_clk),.rst_n(up),.cmd_valid(req&&(state==COMMAND)&&!locked&&!halt_new),.cmd_ready(cmdready),
  .original_base(src_q),.styled_base(dst_q),.cmd_id(id_q),.busy(dma_busy),.locked(locked),
  .frame_good(dma_good),.frame_bad(dma_bad),.reason(reason),.frame_id(dma_id),
  .out_valid(iv),.out_ready(ir),.burst_credit(space_available),.out_rgb(pixel),.out_sof(sof),.out_eol(eol),.out_eof(eof),
  .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rid(rid),.rresp(rresp),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 rgb_display_bridge #(.WIDTH(2*W),.HEIGHT(H),.X0(X0),.Y0(Y0),.FIFO_LOG2(FIFO_LOG2),.PREFILL(PREFILL)) bridge(
  .arst_n(arst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.request_valid(req),.request_ready(reqready),
  .busy(bridge_busy),.session_done(bridge_done),.session_bad(bridge_bad),
  .in_valid(iv),.in_ready(ir),.in_space(space_available),.in_rgb(pixel),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_abort(dma_bad&&!locked),
  .raster_start(raster_start),.raster_de(raster_de),.raster_hs(raster_hs),.raster_vs(raster_vs),.raster_x(raster_x),.raster_y(raster_y),
  .rgb(rgb),.de(de),.hs(hs),.vs(vs));
endmodule
