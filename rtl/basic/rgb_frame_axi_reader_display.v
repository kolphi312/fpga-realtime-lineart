`timescale 1ns/1ps
// One outstanding AXI burst -> backpressured RGB888. Bytes R,G,B,X.
// Successful completion is after the FINAL PIXEL handshake, not merely RLAST.
// RRESP errors drain the current burst and fail; wrong ID or RLAST locks without
// accepting the offending response, requiring a coordinated bus reset.
module rgb_frame_axi_reader_display #(
 parameter FRAME_PIXELS=640*480,WIDTH=640,MAX_BEATS=16,ROW_BURSTS=0,CREDIT_GATED=0,
 parameter [3:0] READ_ID=4'd1
)(input wire clk,rst_n,cmd_valid,output wire cmd_ready,input wire [31:0] cmd_base,cmd_id,
 output wire busy,output reg locked,frame_good,frame_bad,output reg [3:0] reason,output reg [31:0] frame_id,
 output wire out_valid,input wire out_ready,input wire [31:0] burst_credit,output wire [23:0] out_rgb,output wire out_sof,out_eol,out_eof,
 output wire [3:0] arid,output wire [31:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [1:0] rresp,input wire [127:0] rdata,input wire rlast,rvalid,output wire rready);
 localparam IDLE=0,ADDR=1,DATA=2,RESULT=3,LOCK=4,WAIT_ROW=5;
 localparam [32:0] FRAME_BYTES=FRAME_PIXELS*33'd4;
 reg [2:0] state;
 reg [31:0] addr,words_left,pixels,col;
 reg [8:0] beats,received,loaded;
 localparam BAW=(MAX_BEATS>1)?$clog2(MAX_BEATS):1;
 reg [127:0] burst_data[0:MAX_BEATS-1];
 reg [127:0] word_data;reg word_valid,word_last,bad_seen;
 reg [1:0] lane;
 localparam ROW_WORDS=(WIDTH%4==0)?WIDTH/4:1;
 reg [31:0] row_words_left;
 // Finish bursts at row boundaries before a row-based consumer computes.
 // Odd widths use single beats to avoid retaining a multi-beat transaction.
 function [8:0] burst_size(input [31:0] a,left,line_left);
  reg [12:0] span;reg [8:0] n;
  begin
   span=13'd4096-{1'b0,a[11:0]};n=span[12:4];
   if(n>MAX_BEATS)n=MAX_BEATS;
   if(left<n)n=left[8:0];
   if(ROW_BURSTS&&line_left<n)n=line_left[8:0];
   burst_size=n;
  end
 endfunction
 wire [32:0] cmd_end={1'b0,cmd_base}+FRAME_BYTES;
 wire config_ok=cmd_base[3:0]==0&&cmd_end<=33'h100000000;
 wire [31:0] next_addr=addr+({23'b0,beats}<<4);
 wire protocol_bad=(state==DATA)&&(received<beats)&&rvalid&&((rid!=READ_ID)||(rlast!=(received==beats-1'b1)));
 assign cmd_ready=state==IDLE&&!locked;
 assign busy=state!=IDLE;
 assign arid=READ_ID;assign araddr=addr;assign arlen=beats[7:0]-8'd1;
 assign arsize=3'd4;assign arburst=2'b01;assign arvalid=state==ADDR;
 // Entire burst has reserved local storage; downstream pixel stalls never
 // interrupt RREADY during a legal outstanding response burst.
 assign rready=(state==DATA)&&(received<beats)&&!protocol_bad;
 assign out_valid=(state==DATA)&&word_valid&&!bad_seen;
 wire [31:0] px=word_data[32*lane+:32];
 assign out_rgb={px[7:0],px[15:8],px[23:16]};
 assign out_sof=out_valid&&(pixels==0);assign out_eol=out_valid&&(col==WIDTH-1);
 assign out_eof=out_valid&&(pixels==FRAME_PIXELS-1);
 initial if(FRAME_PIXELS<1||FRAME_PIXELS>1073741824||WIDTH<1||MAX_BEATS<1||MAX_BEATS>256)$fatal(1,"reader parameters");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;loaded<=0;addr<=0;words_left<=0;row_words_left<=ROW_WORDS;pixels<=0;col<=0;beats<=0;received<=0;word_data<=0;
   word_valid<=0;word_last<=0;bad_seen<=0;lane<=0;locked<=0;frame_good<=0;frame_bad<=0;reason<=0;frame_id<=0;
  end else begin
   frame_good<=0;frame_bad<=0;
   if(cmd_valid&&cmd_ready)begin
    addr<=cmd_base;frame_id<=cmd_id;words_left<=(FRAME_PIXELS+3)/4;
    beats<=burst_size(cmd_base,(FRAME_PIXELS+3)/4,ROW_WORDS);row_words_left<=ROW_WORDS;received<=0;loaded<=0;pixels<=0;col<=0;word_valid<=0;lane<=0;
    bad_seen<=!config_ok;reason<=config_ok?0:2;state<=config_ok?((ROW_BURSTS||CREDIT_GATED)?WAIT_ROW:ADDR):RESULT;
   end
   // Once ADDR is entered, ARVALID remains asserted until acceptance. Wait
   // BEFORE entering ADDR so the consumer's row-compute pause cannot retain
   // a newly launched burst, without violating VALID stability on stalls.
   // The sole producer reserves enough downstream slots for this ENTIRE
   // burst before asserting ARVALID. The preceding burst has fully drained.
   // Neither available space nor ready can withdraw an asserted ARVALID.
   if(state==WAIT_ROW&&out_ready&&(!CREDIT_GATED||(burst_credit>=({23'b0,beats}<<2))))state<=ADDR;
   if(arvalid&&arready)state<=DATA;
   // Synchronous buffer read. loaded<received excludes same-address read/write
   // collisions; only previously committed beats become pixel words.
   if(state==DATA&&!word_valid&&!bad_seen&&loaded<received)begin
    word_data<=burst_data[loaded[BAW-1:0]];word_valid<=1;
    word_last<=(loaded==beats-1'b1);loaded<=loaded+1'b1;lane<=0;
   end
   if(rvalid&&rready)begin
    received<=received+1'b1;words_left<=words_left-1;
    if(ROW_BURSTS)row_words_left<=(row_words_left==1)?ROW_WORDS:row_words_left-1'b1;
    if(rresp!=0||bad_seen)begin
     bad_seen<=1;reason<=3;word_valid<=0;
     if(received==beats-1'b1)state<=RESULT;
    end else burst_data[received[BAW-1:0]]<=rdata;
   end
   if(out_valid&&out_ready&&!(rvalid&&rready&&rresp!=0))begin
    pixels<=pixels+1;col<=(col==WIDTH-1)?0:col+1;
    if(lane==3||pixels==FRAME_PIXELS-1)begin
     word_valid<=0;lane<=0;
     // Synchronous next-word read on the outgoing word's final pixel.
     // loaded<received excludes simultaneous same-address RAM read/write.
     if(!word_last&&loaded<received&&!bad_seen)begin
      word_data<=burst_data[loaded[BAW-1:0]];word_valid<=1;
      word_last<=(loaded==beats-1'b1);loaded<=loaded+1'b1;
     end
     if(word_last)begin
      if(words_left==0)state<=RESULT;
      else begin addr<=next_addr;beats<=burst_size(next_addr,words_left,row_words_left);received<=0;loaded<=0;state<=(ROW_BURSTS||CREDIT_GATED)?WAIT_ROW:ADDR;end
     end
    end else lane<=lane+2'd1;
   end
   if(state==RESULT)begin
    state<=IDLE;
    if(bad_seen)frame_bad<=1;else frame_good<=1;
   end
   if(protocol_bad)begin locked<=1;state<=LOCK;frame_bad<=1;reason<=(rid!=READ_ID)?4:5;end
  end
 end
endmodule
