`timescale 1ns/1ps
// Two read clients + two write clients, one outstanding burst per direction.
// Client 0/1 occupy low/high vector slices. AR and AW arbitrate independently.
// Burst ownership survives all backpressure; W stays owned until B completes.
// Local IDs are restored; bus IDs are owner 0/1. No read/write reordering.
// Intended subset: 128-bit, aligned INCR bursts, compliant stable masters.
// Protocol fault blocks the affected response/beat and new grants. The other
// already-granted direction may drain. Only coordinated fabric reset recovers.
module axi_video_arbiter(
 input wire clk,rst_n,halt_new,
 input wire [7:0] s_arid,input wire [63:0] s_araddr,input wire [15:0] s_arlen,
 input wire [5:0] s_arsize,input wire [3:0] s_arburst,input wire [1:0] s_arvalid,output wire [1:0] s_arready,
 output wire [7:0] s_rid,output wire [3:0] s_rresp,output wire [255:0] s_rdata,
 output wire [1:0] s_rlast,s_rvalid,input wire [1:0] s_rready,
 input wire [7:0] s_awid,input wire [63:0] s_awaddr,input wire [15:0] s_awlen,
 input wire [5:0] s_awsize,input wire [3:0] s_awburst,input wire [1:0] s_awvalid,output wire [1:0] s_awready,
 input wire [255:0] s_wdata,input wire [31:0] s_wstrb,input wire [1:0] s_wlast,s_wvalid,output wire [1:0] s_wready,
 output wire [7:0] s_bid,output wire [3:0] s_bresp,output wire [1:0] s_bvalid,input wire [1:0] s_bready,
 output wire [3:0] m_arid,output wire [31:0] m_araddr,output wire [7:0] m_arlen,
 output wire [2:0] m_arsize,output wire [1:0] m_arburst,output wire m_arvalid,input wire m_arready,
 input wire [3:0] m_rid,input wire [1:0] m_rresp,input wire [127:0] m_rdata,
 input wire m_rlast,m_rvalid,output wire m_rready,
 output wire [3:0] m_awid,output wire [31:0] m_awaddr,output wire [7:0] m_awlen,
 output wire [2:0] m_awsize,output wire [1:0] m_awburst,output wire m_awvalid,input wire m_awready,
 output wire [127:0] m_wdata,output wire [15:0] m_wstrb,output wire m_wlast,m_wvalid,input wire m_wready,
 input wire [3:0] m_bid,input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
 output wire read_busy,write_busy,output reg [3:0] fault_flags
);
 localparam IDLE=0,ADDR=1,DATA=2,RESP=3,LOCK=4;
 reg [2:0] rs,ws;reg ro,wo,rnext,wnext;
 reg [3:0] rlocal,wlocal;reg [8:0] rleft,wleft;
 wire r_id_bad=rs==DATA&&m_rvalid&&(m_rid!={3'b0,ro});
 wire r_last_bad=rs==DATA&&m_rvalid&&(m_rlast!=(rleft==1));
 wire w_last_bad=ws==DATA&&s_wvalid[wo]&&(s_wlast[wo]!=(wleft==1));
 wire b_id_bad=ws==RESP&&m_bvalid&&(m_bid!={3'b0,wo});
 wire r_bad=r_id_bad||r_last_bad;
 wire stop_new=halt_new||(|fault_flags)||r_bad||w_last_bad||b_id_bad;
 assign read_busy=rs!=IDLE;assign write_busy=ws!=IDLE;
 assign m_arid={3'b0,ro};assign m_araddr=s_araddr[ro*32+:32];assign m_arlen=s_arlen[ro*8+:8];
 assign m_arsize=s_arsize[ro*3+:3];assign m_arburst=s_arburst[ro*2+:2];
 assign m_arvalid=rs==ADDR&&s_arvalid[ro];
 assign s_arready=(rs==ADDR&&m_arready)?(2'b01<<ro):0;
 assign s_rid={2{rlocal}};assign s_rresp={2{m_rresp}};assign s_rdata={2{m_rdata}};assign s_rlast={2{m_rlast}};
 assign s_rvalid=(rs==DATA&&!r_bad&&m_rvalid)?(2'b01<<ro):0;
 assign m_rready=rs==DATA&&!r_bad&&s_rready[ro];
 assign m_awid={3'b0,wo};assign m_awaddr=s_awaddr[wo*32+:32];assign m_awlen=s_awlen[wo*8+:8];
 assign m_awsize=s_awsize[wo*3+:3];assign m_awburst=s_awburst[wo*2+:2];
 assign m_awvalid=ws==ADDR&&s_awvalid[wo];
 assign s_awready=(ws==ADDR&&m_awready)?(2'b01<<wo):0;
 assign m_wdata=s_wdata[wo*128+:128];assign m_wstrb=s_wstrb[wo*16+:16];assign m_wlast=s_wlast[wo];
 assign m_wvalid=ws==DATA&&!w_last_bad&&s_wvalid[wo];
 assign s_wready=(ws==DATA&&!w_last_bad&&m_wready)?(2'b01<<wo):0;
 assign s_bid={2{wlocal}};assign s_bresp={2{m_bresp}};
 assign s_bvalid=(ws==RESP&&!b_id_bad&&m_bvalid)?(2'b01<<wo):0;
 assign m_bready=ws==RESP&&!b_id_bad&&s_bready[wo];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rs<=IDLE;ws<=IDLE;ro<=0;wo<=0;rnext<=0;wnext<=0;rlocal<=0;wlocal<=0;rleft<=0;wleft<=0;fault_flags<=0;end
  else begin
   case(rs)
    IDLE:if((|s_arvalid)&&!stop_new)begin
     ro<=(s_arvalid==2'b11)?rnext:s_arvalid[1];rs<=ADDR;
    end
    ADDR:if(m_arvalid&&m_arready)begin rlocal<=s_arid[ro*4+:4];rleft<={1'b0,m_arlen}+9'd1;rs<=DATA;end
    DATA:if(m_rvalid&&m_rready)begin
     rleft<=rleft-1'b1;if(rleft==1)begin rs<=IDLE;rnext<=!ro;end
    end
   endcase
   case(ws)
    IDLE:if((|s_awvalid)&&!stop_new)begin
     wo<=(s_awvalid==2'b11)?wnext:s_awvalid[1];ws<=ADDR;
    end
    ADDR:if(m_awvalid&&m_awready)begin wlocal<=s_awid[wo*4+:4];wleft<={1'b0,m_awlen}+9'd1;ws<=DATA;end
    DATA:if(m_wvalid&&m_wready)begin wleft<=wleft-1'b1;if(wleft==1)ws<=RESP;end
    RESP:if(m_bvalid&&m_bready)begin ws<=IDLE;wnext<=!wo;end
   endcase
   if(r_bad)begin rs<=LOCK;fault_flags[0]<=fault_flags[0]||r_id_bad;fault_flags[1]<=fault_flags[1]||r_last_bad;end
   if(w_last_bad)begin ws<=LOCK;fault_flags[2]<=1;end
   if(b_id_bad)begin ws<=LOCK;fault_flags[3]<=1;end
  end
 end
endmodule
