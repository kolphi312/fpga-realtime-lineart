`timescale 1ns/1ps
// Read-only consumer of frame_bank_owner. Keep the displayed bank READ-owned
// across refreshes; replace it only when another READY bank exists. No shared
// readers/refcounts. Gate bank availability upstream until DDR is calibrated.
module rgb_frame_display #(
 parameter WIDTH=640,HEIGHT=480,X0=640,Y0=300,FIFO_LOG2=10,BANKS=4
)(
 input wire arst_n,sys_clk,pix_clk,
 output wire bank_request,input wire bank_ready,input wire [31:0] bank_addr,bank_id,
 input wire [BANKS*2-1:0] bank_states,output wire bank_release,
 output reg held,output wire locked,output wire session_done,session_bad,
 output wire [31:0] displayed_id,
 input wire raster_start,raster_de,raster_hs,raster_vs,input wire [11:0] raster_x,raster_y,
 output wire [23:0] rgb,output wire de,hs,vs,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,input wire rlast,rvalid,output wire rready
);
 wire sys_up;
 reset_release sys_reset(.clk(sys_clk),.arst_n(arst_n),.srst_n(sys_up));
 localparam SELECT=0,COMMAND=1,RUN=2;
 reg [1:0] state;reg [31:0] addr_q,id_q;
 reg queued;integer k;
 always @*begin
  queued=0;for(integer j=0;j<BANKS;j=j+1)if(bank_states[j*2+:2]==2'd2)queued=1;
 end
 wire req,reqready,bridge_busy,cmdready,dma_busy,dma_good,dma_bad;
 wire [3:0] reason;wire [31:0] dma_id;wire iv,ir,sof,eol,eof;wire [23:0] pixel;
 assign displayed_id=id_q;
 assign bank_request=(state==SELECT)&&req&&!held&&!locked;
 assign bank_release=!locked&&held&&(((state==SELECT)&&req&&queued)||((state==RUN)&&session_done&&session_bad));
 assign reqready=(state==COMMAND)&&cmdready;
 always @(posedge sys_clk or negedge sys_up)begin
  if(!sys_up)begin state<=SELECT;held<=0;addr_q<=0;id_q<=0;end
  else if(!locked)begin
   if(state==SELECT&&req)begin
    if(held)begin if(queued)held<=0;else state<=COMMAND;end
    else if(bank_ready)begin held<=1;addr_q<=bank_addr;id_q<=bank_id;state<=COMMAND;end
   end
   if(state==COMMAND&&req&&reqready)state<=RUN;
   if(state==RUN&&session_done)begin state<=SELECT;if(session_bad)held<=0;end
  end
 end
 rgb_frame_axi_reader #(.FRAME_PIXELS(WIDTH*HEIGHT),.WIDTH(WIDTH)) reader(
  .clk(sys_clk),.rst_n(sys_up),.cmd_valid(req&&(state==COMMAND)),.cmd_ready(cmdready),.cmd_base(addr_q),.cmd_id(id_q),
  .busy(dma_busy),.locked(locked),.frame_good(dma_good),.frame_bad(dma_bad),.reason(reason),.frame_id(dma_id),
  .out_valid(iv),.out_ready(ir),.out_rgb(pixel),.out_sof(sof),.out_eol(eol),.out_eof(eof),
  .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rid(rid),.rresp(rresp),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready));
 rgb_display_bridge #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.X0(X0),.Y0(Y0),.FIFO_LOG2(FIFO_LOG2)) bridge(
  .arst_n(arst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.request_valid(req),.request_ready(reqready),
  .busy(bridge_busy),.session_done(session_done),.session_bad(session_bad),
  .in_valid(iv),.in_ready(ir),.in_rgb(pixel),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_abort(dma_bad&&!locked),
  .raster_start(raster_start),.raster_de(raster_de),.raster_hs(raster_hs),.raster_vs(raster_vs),.raster_x(raster_x),.raster_y(raster_y),
  .rgb(rgb),.de(de),.hs(hs),.vs(vs));
endmodule
