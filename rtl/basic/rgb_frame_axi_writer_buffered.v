`timescale 1ns/1ps
// Capture-only dual burst packer. Fill next bank while current bank performs
// AW/W/B. One outstanding AXI burst, ordered banks, no early frame completion.
// A bank cannot be reused until its B response is accepted. Source failure
// drains packed data and reports failure; wrong BID locks until bus reset.
module rgb_frame_axi_writer_buffered #(
 parameter integer FRAME_PIXELS=640*480,MAX_BEATS=16
)(
 input wire clk,rst_n,cmd_valid,output wire cmd_ready,
 input wire [31:0] cmd_base,cmd_id,
 input wire s_valid,output wire s_ready,input wire [23:0] s_rgb,
 input wire source_done,source_ok,
 output wire busy,output reg locked,frame_good,frame_bad,
 output reg [3:0] reason,output reg [31:0] frame_id,
 output wire [3:0] awid,output wire [31:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,
 output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,
 output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready
);
 localparam IDLE=0,FILL=1,ADDR=2,DATA=3,RESP=4,CLOSE=5,RESULT=6,LOCK=7;
 localparam [32:0] FRAME_BYTES=FRAME_PIXELS*33'd4;
 reg [2:0] state;
 reg [127:0] data_buf[0:2*MAX_BEATS-1];
 // All non-tail beats contain four packed RGBX pixels. Store only the
 // final beat mask per sealed bank, avoiding a dynamically indexed mask RAM.
 reg [15:0] bank_tail_mask[0:1];
 reg [31:0] bank_addr[0:1];reg [8:0] bank_beats[0:1];
 reg [1:0] bank_ready;
 reg fill_bank,send_bank;
 reg [31:0] pack_addr,addr,count;
 reg [10:0] fill_pixels;
 reg [8:0] beats,send_idx;
 reg source_seen,source_pass;
 wire [32:0] end_addr={1'b0,cmd_base}+FRAME_BYTES;
 wire config_ok=(cmd_base[3:0]==0)&&(end_addr<=33'h100000000);
 wire begin_frame=cmd_valid&&cmd_ready;
 wire [12:0] boundary_bytes=13'd4096-{1'b0,pack_addr[11:0]};
 wire [8:0] boundary_beats=boundary_bytes>>4;
 wire [8:0] limit_beats=(boundary_beats<MAX_BEATS)?boundary_beats:MAX_BEATS;
 wire [10:0] limit_pixels={limit_beats,2'b00};
 wire active=(state==FILL||state==ADDR||state==DATA||state==RESP);
 wire pixel_fire=s_valid&&s_ready;
 wire [10:0] fill_next=fill_pixels+pixel_fire;
 wire [31:0] count_next=count+pixel_fire;
 wire [10:0] rounded_fill=fill_next+11'd3;
 wire [31:0] pixel_word={8'b0,s_rgb[7:0],s_rgb[15:8],s_rgb[23:16]};
 wire [9:0] pack_index=(fill_bank?MAX_BEATS:0)+(fill_pixels>>2);
 wire [9:0] send_index=(send_bank?MAX_BEATS:0)+send_idx;
 wire seal=active&&!bank_ready[fill_bank]&&fill_next!=0&&
   ((fill_next==limit_pixels)||(count_next==FRAME_PIXELS)||source_seen||source_done);
 assign cmd_ready=(state==IDLE)&&!locked;
 assign busy=state!=IDLE;
 assign s_ready=active&&!locked&&!bank_ready[fill_bank]&&!source_seen&&count<FRAME_PIXELS;
 assign awid=0;assign awaddr=addr;assign awlen=beats[7:0]-8'd1;
 assign awsize=3'd4;assign awburst=2'b01;assign awvalid=state==ADDR;
 assign wdata=data_buf[send_index];assign wstrb=wlast ? bank_tail_mask[send_bank] : 16'hffff;
 assign wvalid=state==DATA;assign wlast=send_idx==beats-1'b1;
 assign bready=(state==RESP)&&(bid==0);
 wire fence_good,fence_bad,fence_locked,fence_busy;
 wire [3:0] fence_reason;wire [31:0] fence_id;wire [7:0] pa,pw;
 axi_frame_fence fence(
 .clk(clk),.rst_n(rst_n),.start(begin_frame&&config_ok),.start_id(cmd_id),
 .aw_fire(awvalid&&awready),.wl_fire(wvalid&&wready&&wlast),
 .b_fire(bvalid&&bready),.bresp(bresp),.issue_done(state==CLOSE),
 .source_ok(source_seen&&source_pass&&count==FRAME_PIXELS),
 .busy(fence_busy),.locked(fence_locked),.frame_good(fence_good),.frame_bad(fence_bad),
 .frame_id(fence_id),.reason(fence_reason),.pending_aw(pa),.pending_w(pw));
 initial if(FRAME_PIXELS<1||FRAME_BYTES>33'h100000000||MAX_BEATS<1||MAX_BEATS>256)$fatal(1,"buffered writer parameters");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;addr<=0;pack_addr<=0;count<=0;fill_pixels<=0;beats<=1;send_idx<=0;
   fill_bank<=0;send_bank<=0;bank_ready<=0;bank_tail_mask[0]<=16'hffff;bank_tail_mask[1]<=16'hffff;
   source_seen<=0;source_pass<=0;locked<=0;frame_good<=0;frame_bad<=0;reason<=0;frame_id<=0;
  end else begin
   frame_good<=0;frame_bad<=0;
   if(busy&&source_done&&!source_seen)begin
    source_seen<=1;source_pass<=source_ok&&(count_next==FRAME_PIXELS);
   end
   if(pixel_fire)begin
    if(fill_pixels[1:0]==0)begin
     data_buf[pack_index]<={96'b0,pixel_word};
    end else begin
     data_buf[pack_index][fill_pixels[1:0]*32+:32]<=pixel_word;
    end
    fill_pixels<=fill_next;count<=count_next;
   end
   if(seal)begin
    case(fill_next[1:0])
     2'd1:bank_tail_mask[fill_bank]<=16'h000f;
     2'd2:bank_tail_mask[fill_bank]<=16'h00ff;
     2'd3:bank_tail_mask[fill_bank]<=16'h0fff;
     default:bank_tail_mask[fill_bank]<=16'hffff;
    endcase
    bank_addr[fill_bank]<=pack_addr;bank_beats[fill_bank]<=rounded_fill[10:2];bank_ready[fill_bank]<=1;
    pack_addr<=pack_addr+({23'b0,rounded_fill[10:2]}<<4);
    fill_bank<=!fill_bank;fill_pixels<=0;
   end
   case(state)
    IDLE:if(begin_frame)begin
     frame_id<=cmd_id;reason<=0;
     if(!config_ok)begin frame_bad<=1;reason<=2;end
     else begin
      state<=FILL;addr<=cmd_base;pack_addr<=cmd_base;count<=0;fill_pixels<=0;
      source_seen<=0;source_pass<=0;send_idx<=0;fill_bank<=0;send_bank<=0;bank_ready<=0;
     end
    end
    FILL:begin
     if(bank_ready[send_bank])begin addr<=bank_addr[send_bank];beats<=bank_beats[send_bank];send_idx<=0;state<=ADDR;end
     else if(source_seen&&bank_ready==0&&fill_pixels==0)state<=CLOSE;
    end
    ADDR:if(awready)state<=DATA;
    DATA:if(wready)begin if(wlast)state<=RESP;else send_idx<=send_idx+1'b1;end
    RESP:if(bvalid&&bready)begin bank_ready[send_bank]<=0;send_bank<=!send_bank;send_idx<=0;state<=FILL;end
    CLOSE:state<=RESULT;
    RESULT:if(fence_good||fence_bad)begin
     state<=IDLE;frame_good<=fence_good;frame_bad<=fence_bad;reason<=fence_good?0:((fence_reason==2)?3:1);
    end
    default:state<=LOCK;
   endcase
   if(!locked&&((state==RESP&&bvalid&&bid!=0)||fence_locked))begin
    state<=LOCK;locked<=1;frame_good<=0;frame_bad<=1;reason<=5;
   end
  end
 end
endmodule
