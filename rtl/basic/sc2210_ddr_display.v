`timescale 1ns/1ps
// Diagnostic direct path, not CNN or final competition demo. Common reset must
// also reset/drain the AXI fabric. arm is a stable enable after DDR calibration;
// its first full FV starts capture. Do not use arm to cancel an outstanding AXI.
module sc2210_ddr_display #(
 parameter IW=1920,IH=1080,CX=240,CY=0,CW=1440,CH=1080,OW=640,OH=480,CFA=1,
 parameter HA=1920,HF=88,HS=44,HB=148,VA=1080,VF=4,VS=5,VB=36,X0=640,Y0=300,
 parameter CAPTURE_LOG2=9,DISPLAY_LOG2=10,
 parameter [31:0] POOL_BASE=32'h01000000,BANK_STRIDE=32'h00200000
)(input wire clk,csi_clk,pix_clk,rst_n,arm,
 input wire csi_fv,csi_lv,csi_de,input wire [47:0] csi_raw,
 output wire [23:0] rgb,output wire de,hs,vs,
 output wire locked,capture_fault,bayer_fault,output reg [31:0] captured,failed,displayed,display_failed,
 output wire [31:0] display_id,output wire [7:0] bank_states,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,input wire rlast,rvalid,output wire rready
);
 wire sys_up,csi_up,pix_up;
 reset_release sys_reset(.clk(clk),.arst_n(rst_n),.srst_n(sys_up));
 reset_release csi_reset(.clk(csi_clk),.arst_n(rst_n),.srst_n(csi_up));
 reset_release pix_reset(.clk(pix_clk),.arst_n(rst_n),.srst_n(pix_up));
 // Register the calibration expression before crossing to CSI. arm is a
 // stable enable, not an asynchronous cancel. All consumers use this sample.
 reg arm_q;
 always @(posedge clk or negedge sys_up)
  if(!sys_up)arm_q<=0;else arm_q<=arm;
 (* async_reg="true" *) reg arm_c1,arm_c2;
 reg capture_armed;
 always @(posedge csi_clk or negedge csi_up)begin
  if(!csi_up)begin arm_c1<=0;arm_c2<=0;capture_armed<=0;end
  else begin arm_c1<=arm_q;arm_c2<=arm_c1;if(arm_c2&&!csi_fv)capture_armed<=1;end
 end
 wire cr,store_busy,store_locked,fg,fb,rrq,rrdy,release_bank,held,reader_locked,sd,sb;
 wire [31:0] bankaddr,bankid,writing_addr,frame_id;wire [1:0] read_bank;
 wire [3:0] reason;wire [8:0] high_water;wire [31:0] overflow_frames;
 reg [31:0] next_id;
 assign locked=store_locked||reader_locked;
 wire command=sys_up&&arm_q&&!locked;
 always @(posedge clk or negedge sys_up)begin
  if(!sys_up)begin next_id<=0;captured<=0;failed<=0;displayed<=0;display_failed<=0;end
  else begin
   if(command&&cr)next_id<=next_id+1;
   if(fg)captured<=captured+1;if(fb)failed<=failed+1;
   if(sd)begin if(sb)display_failed<=display_failed+1;else displayed<=displayed+1;end
  end
 end
 sc2210_rgb_store #(.IW(IW),.IH(IH),.CX(CX),.CY(CY),.CW(CW),.CH(CH),.OW(OW),.OH(OH),.CFA(CFA),
 .CAPTURE_LOG2(CAPTURE_LOG2),.BANKS(4),.POOL_BASE(POOL_BASE),.BANK_STRIDE(BANK_STRIDE)) camera(
 .clk(clk),.csi_clk(csi_clk),.rst_n(rst_n),.csi_fv(csi_fv&&capture_armed),.csi_lv(csi_lv&&capture_armed),.csi_de(csi_de&&capture_armed),.csi_raw(csi_raw),
 .cmd_valid(command),.cmd_ready(cr),.cmd_id(next_id),.read_request(rrq),.read_ready(rrdy),.read_bank(read_bank),
 .read_addr(bankaddr),.read_frame_id(bankid),.read_release(release_bank),.writing_addr(writing_addr),.bank_states(bank_states),
 .busy(store_busy),.locked(store_locked),.frame_good(fg),.frame_bad(fb),.reason(reason),.frame_id(frame_id),
 .capture_fault(capture_fault),.bayer_fault(bayer_fault),.high_water(high_water),.overflow_frames(overflow_frames),
 .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
 .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready));
 wire rs,rd,rh,rv;wire [11:0] rx,ry;
 video_raster #(.HA(HA),.HF(HF),.HS(HS),.HB(HB),.VA(VA),.VF(VF),.VS(VS),.VB(VB)) raster(
 .clk(pix_clk),.rst_n(pix_up),.frame_start(rs),.de(rd),.hs(rh),.vs(rv),.x(rx),.y(ry));
 rgb_frame_display #(.WIDTH(OW),.HEIGHT(OH),.X0(X0),.Y0(Y0),.FIFO_LOG2(DISPLAY_LOG2)) display(
 .arst_n(rst_n),.sys_clk(clk),.pix_clk(pix_clk),.bank_request(rrq),.bank_ready(rrdy&&arm_q),.bank_addr(bankaddr),.bank_id(bankid),.bank_states(bank_states),
 .bank_release(release_bank),.held(held),.locked(reader_locked),.session_done(sd),.session_bad(sb),.displayed_id(display_id),
 .raster_start(rs),.raster_de(rd),.raster_hs(rh),.raster_vs(rv),.raster_x(rx),.raster_y(ry),.rgb(rgb),.de(de),.hs(hs),.vs(vs),
 .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
 .rid(rid),.rresp(rresp),.rdata(rdata),.rlast(rlast),.rvalid(rvalid),.rready(rready));
endmodule
