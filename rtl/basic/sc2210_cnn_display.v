`timescale 1ns/1ps
// Synthesizable live pipeline. Four source/result pairs; automatic capture and
// CNN launch after configuration, repeat-held display at refresh boundaries.
// enable gates NEW capture commands only; drain CNN/display after enable=0.
// All faults except safely drained display failure require coordinated reset.
// Config is a direct handshake port, not yet a RISC-V/APB software interface.
module sc2210_cnn_display #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,W=640,H=480,CFA=1,
 parameter X0=0,Y0=120,DISPLAY_LOG2=11
)(
 input wire arst_n,clk,csi_clk,pix_clk,enable,
 input wire csi_fv,csi_lv,csi_de,input wire [47:0] csi_raw,
 input wire cfgvalid,input wire [5:0] cfgaddr,input wire [31:0] cfgdata,
 output wire cfgready,configured,cfgerror,
 input wire raster_start,raster_de,raster_hs,raster_vs,input wire [11:0] raster_x,raster_y,
 output wire [23:0] rgb,output wire de,hs,vs,
 output wire fault,display_done,display_bad,display_held,output wire [31:0] displayed_id,
 output wire [3:0] m_arid,
 output wire [31:0] m_araddr,
 output wire [7:0] m_arlen,
 output wire [2:0] m_arsize,
 output wire [1:0] m_arburst,
 output wire m_arvalid,
 input wire m_arready,
 input wire [3:0] m_rid,
 input wire [1:0] m_rresp,
 input wire [127:0] m_rdata,
 input wire m_rlast,
 input wire m_rvalid,
 output wire m_rready,
 output wire [3:0] m_awid,
 output wire [31:0] m_awaddr,
 output wire [7:0] m_awlen,
 output wire [2:0] m_awsize,
 output wire [1:0] m_awburst,
 output wire m_awvalid,
 input wire m_awready,
 output wire [127:0] m_wdata,
 output wire [15:0] m_wstrb,
 output wire m_wlast,
 output wire m_wvalid,
 input wire m_wready,
 input wire [3:0] m_bid,
 input wire [1:0] m_bresp,
 input wire m_bvalid,
 output wire m_bready
);
 wire [7:0] s_arid;
 wire [63:0] s_araddr;
 wire [15:0] s_arlen;
 wire [5:0] s_arsize;
 wire [3:0] s_arburst;
 wire [1:0] s_arvalid;
 wire [1:0] s_arready;
 wire [7:0] s_rid;
 wire [3:0] s_rresp;
 wire [255:0] s_rdata;
 wire [1:0] s_rlast;
 wire [1:0] s_rvalid;
 wire [1:0] s_rready;
 wire [7:0] s_awid;
 wire [63:0] s_awaddr;
 wire [15:0] s_awlen;
 wire [5:0] s_awsize;
 wire [3:0] s_awburst;
 wire [1:0] s_awvalid;
 wire [1:0] s_awready;
 wire [255:0] s_wdata;
 wire [31:0] s_wstrb;
 wire [1:0] s_wlast;
 wire [1:0] s_wvalid;
 wire [1:0] s_wready;
 wire [7:0] s_bid;
 wire [3:0] s_bresp;
 wire [1:0] s_bvalid;
 wire [1:0] s_bready;
 wire rst_n;reset_release sys_reset(.clk(clk),.arst_n(arst_n),.srst_n(rst_n));
 localparam N=W*H;
 wire csi=csi_clk,fv=csi_fv,lv=csi_lv,dein=csi_de;wire [47:0] raw=csi_raw;
 wire cp,np,dp,cr,nr,dr,cbusy,nbusy,dbusy,owner_error;wire [1:0] cb,nb,db;
 wire [31:0] ca,ci,ns,nd,ni,ds,dd,di;wire [11:0] pair_states;
 wire cwready,cwbusy,cwlock,cwgood,cwbad;wire [3:0] cwreason;wire [31:0] cwid;
 wire nnready,nnbusy,nndone,nnok,nnlock;wire [3:0] nnreason;wire [31:0] nnid;
 wire rdlock,release_pair,capture_fault,bayer_fault;wire [8:0] high_water;wire [31:0] overflows;
 wire read_busy,write_busy;wire [3:0] fault_flags;
 wire fatal_all=(|fault_flags)||cwlock||nnlock||rdlock||capture_fault||bayer_fault||cwbad||(nndone&&!nnok);
 assign fault=fatal_all||owner_error;
 assign cp=enable&&cwready&&configured&&!fault;
 assign np=nnready&&configured&&!fault;
 wire capfire=cp&&cr,nnfire=np&&nr,dispfire=dp&&dr;
 axi_video_arbiter dut(.halt_new(1'b0),.clk(clk),
  .rst_n(rst_n),
  .s_arid(s_arid),
  .s_araddr(s_araddr),
  .s_arlen(s_arlen),
  .s_arsize(s_arsize),
  .s_arburst(s_arburst),
  .s_arvalid(s_arvalid),
  .s_arready(s_arready),
  .s_rid(s_rid),
  .s_rresp(s_rresp),
  .s_rdata(s_rdata),
  .s_rlast(s_rlast),
  .s_rvalid(s_rvalid),
  .s_rready(s_rready),
  .s_awid(s_awid),
  .s_awaddr(s_awaddr),
  .s_awlen(s_awlen),
  .s_awsize(s_awsize),
  .s_awburst(s_awburst),
  .s_awvalid(s_awvalid),
  .s_awready(s_awready),
  .s_wdata(s_wdata),
  .s_wstrb(s_wstrb),
  .s_wlast(s_wlast),
  .s_wvalid(s_wvalid),
  .s_wready(s_wready),
  .s_bid(s_bid),
  .s_bresp(s_bresp),
  .s_bvalid(s_bvalid),
  .s_bready(s_bready),
  .m_arid(m_arid),
  .m_araddr(m_araddr),
  .m_arlen(m_arlen),
  .m_arsize(m_arsize),
  .m_arburst(m_arburst),
  .m_arvalid(m_arvalid),
  .m_arready(m_arready),
  .m_rid(m_rid),
  .m_rresp(m_rresp),
  .m_rdata(m_rdata),
  .m_rlast(m_rlast),
  .m_rvalid(m_rvalid),
  .m_rready(m_rready),
  .m_awid(m_awid),
  .m_awaddr(m_awaddr),
  .m_awlen(m_awlen),
  .m_awsize(m_awsize),
  .m_awburst(m_awburst),
  .m_awvalid(m_awvalid),
  .m_awready(m_awready),
  .m_wdata(m_wdata),
  .m_wstrb(m_wstrb),
  .m_wlast(m_wlast),
  .m_wvalid(m_wvalid),
  .m_wready(m_wready),
  .m_bid(m_bid),
  .m_bresp(m_bresp),
  .m_bvalid(m_bvalid),
  .m_bready(m_bready),
  .read_busy(read_busy),
  .write_busy(write_busy),
  .fault_flags(fault_flags));

paired_frame_owner #(.BANKS(4),.INPUT_BASE(32'hff0),.RESULT_BASE(32'h800ff0),.STRIDE(32'h140000),.FRAME_BYTES(N*4)) owner(.clk(clk),.rst_n(rst_n),.fatal_bus(fatal_all),.cap_request(cp),.cap_ready(cr),.cap_bank(cb),.cap_addr(ca),.cap_id(ci),.cap_done(cwgood||cwbad),.cap_ok(cwgood),.cap_done_id(cwid),.cnn_request(np),.cnn_ready(nr),.cnn_bank(nb),.cnn_src(ns),.cnn_dst(nd),.cnn_id(ni),.cnn_done(nndone),.cnn_ok(nnok),.cnn_done_id(nnid),.disp_request(dp),.disp_ready(dr),.disp_bank(db),.disp_src(ds),.disp_dst(dd),.disp_id(di),.disp_release(release_pair),.disp_release_id(displayed_id),.cap_busy(cbusy),.cnn_busy(nbusy),.disp_busy(dbusy),.protocol_error(owner_error),.states(pair_states));
sc2210_command_store #(.IW(IW),.IH(IH),.CX(CX),.CY(CY),.CW(CW),.CH(CH),.OW(W),.OH(H),.CFA(CFA)) capture(.clk(clk),.csi_clk(csi),.csi_fv(fv),.csi_lv(lv),.csi_de(dein),.csi_raw(raw),.capture_fault(capture_fault),.bayer_fault(bayer_fault),.high_water(high_water),.overflow_frames(overflows),.rst_n(rst_n),.cmd_valid(capfire),.cmd_ready(cwready),.cmd_base(ca),.cmd_id(ci),.busy(cwbusy),.locked(cwlock),.frame_good(cwgood),.frame_bad(cwbad),.reason(cwreason),.frame_id(cwid),.awid(s_awid[0+:4]),.awaddr(s_awaddr[0+:32]),.awlen(s_awlen[0+:8]),.awsize(s_awsize[0+:3]),.awburst(s_awburst[0+:2]),.awvalid(s_awvalid[0]),.awready(s_awready[0]),.wdata(s_wdata[0+:128]),.wstrb(s_wstrb[0+:16]),.wlast(s_wlast[0]),.wvalid(s_wvalid[0]),.wready(s_wready[0]),.bid(s_bid[0+:4]),.bresp(s_bresp[0+:2]),.bvalid(s_bvalid[0]),.bready(s_bready[0]));
cnn2_axi #(.W(W),.H(H)) cnn(.clk(clk),.rst_n(rst_n),.cmd_valid(nnfire),.cmd_ready(nnready),.src_base(ns),.dst_base(nd),.cmd_id(ni),.busy(nnbusy),.done(nndone),.ok(nnok),.locked(nnlock),.reason(nnreason),.result_id(nnid),.cfg_valid(cfgvalid),.cfg_addr(cfgaddr),.cfg_data(cfgdata),.cfg_ready(cfgready),.configured(configured),.cfg_error(cfgerror),.arid(s_arid[0+:4]),.araddr(s_araddr[0+:32]),.arlen(s_arlen[0+:8]),.arsize(s_arsize[0+:3]),.arburst(s_arburst[0+:2]),.arvalid(s_arvalid[0]),.arready(s_arready[0]),.rid(s_rid[0+:4]),.rresp(s_rresp[0+:2]),.rdata(s_rdata[0+:128]),.rlast(s_rlast[0]),.rvalid(s_rvalid[0]),.rready(s_rready[0]),.awid(s_awid[4+:4]),.awaddr(s_awaddr[32+:32]),.awlen(s_awlen[8+:8]),.awsize(s_awsize[3+:3]),.awburst(s_awburst[2+:2]),.awvalid(s_awvalid[1]),.awready(s_awready[1]),.wdata(s_wdata[128+:128]),.wstrb(s_wstrb[16+:16]),.wlast(s_wlast[1]),.wvalid(s_wvalid[1]),.wready(s_wready[1]),.bid(s_bid[4+:4]),.bresp(s_bresp[2+:2]),.bvalid(s_bvalid[1]),.bready(s_bready[1]));
 paired_frame_display #(.W(W),.H(H),.X0(X0),.Y0(Y0),.FIFO_LOG2(DISPLAY_LOG2),.PREFILL((2*W*H<1024)?2*W*H:1024)) display(
 .arst_n(rst_n),.sys_clk(clk),.pix_clk(pix_clk),.halt_new(1'b0),.pair_request(dp),.pair_ready(dr),.pair_src(ds),.pair_dst(dd),.pair_id(di),.pair_states(pair_states),
 .pair_release(release_pair),.release_id(),.held(display_held),.locked(rdlock),.session_done(display_done),.session_bad(display_bad),.displayed_id(displayed_id),
 .raster_start(raster_start),.raster_de(raster_de),.raster_hs(raster_hs),.raster_vs(raster_vs),.raster_x(raster_x),.raster_y(raster_y),
 .rgb(rgb),.de(de),.hs(hs),.vs(vs),.arid(s_arid[4+:4]),.araddr(s_araddr[32+:32]),.arlen(s_arlen[8+:8]),.arsize(s_arsize[3+:3]),.arburst(s_arburst[2+:2]),.arvalid(s_arvalid[1]),.arready(s_arready[1]),.rid(s_rid[4+:4]),.rresp(s_rresp[2+:2]),.rdata(s_rdata[128+:128]),.rlast(s_rlast[1]),.rvalid(s_rvalid[1]),.rready(s_rready[1]));
endmodule
