`timescale 1ns/1ps
// Adapter for the existing MIPIRx4LaneFre output contract: frame/line ACTIVE
// HIGH, DE marks a group of four RAW12 samples. Board wiring extracts high
// eight bits; first serialized sample is DAT[47:40], matching legacy byte order.
// RAW output is NOT RGB. EOF is a separate ready/valid event after physical FV
// falls and exact line/frame lengths have been checked. A fault is sticky and
// requires coordinated reset; partial frames must be discarded by the consumer.
module sc2210_raw_capture #(parameter WIDTH=1920,HEIGHT=1080,FIFO_LOG2=9)(
 input wire arst_n,csi_clk,pixel_clk,
 input wire csi_fv,csi_lv,csi_de,input wire [47:0] csi_raw,
 output wire out_valid,input wire out_ready,output wire [7:0] out_raw,
 output wire out_sof,out_eol,out_frame_end,
 output wire source_fault,output wire fault,output reg abort_pulse,
 output reg [31:0] source_frames,output reg [3:0] fault_reason
);
 localparam WORDS=WIDTH/4;
 reg prev_fv,prev_lv;reg [31:0] col,rows;
 reg failed;
 wire fv_rise=csi_fv&&!prev_fv;
 wire line=csi_fv&&csi_lv;
 wire line_fall=prev_lv&&!line;
 wire frame_fall=prev_fv&&!csi_fv;
 wire [31:0] x=fv_rise?0:col,y=fv_rise?0:rows;
 wire data_event=csi_de&&csi_fv&&csi_lv;
 wire [31:0] ended_rows=rows+(line_fall?32'd1:32'd0);
 wire invalid_de=csi_de&&!(csi_fv&&csi_lv);
 wire invalid_word=data_event&&(x>=WORDS||y>=HEIGHT);
 wire invalid_line=line_fall&&(col!=WORDS);
 wire invalid_frame=frame_fall&&(ended_rows!=HEIGHT||(!line_fall&&col!=0));
 wire bad_geometry=invalid_de||invalid_word||invalid_line||invalid_frame;
 wire fifo_wr_ready,fifo_rd_valid,fifo_rd_ready,w_up,r_up;
 wire [35:0] fifo_rd_data;
 wire event_valid=(data_event||frame_fall)&&!failed&&!bad_geometry&&w_up;
 wire [35:0] event_data=frame_fall?{2'b01,2'b00,32'b0}:
  {2'b00,(x==0&&y==0),(x==WORDS-1),csi_raw[11:4],csi_raw[23:16],csi_raw[35:28],csi_raw[47:40]};
 assign source_fault=failed;
 initial if(WIDTH<4||WIDTH%4!=0||HEIGHT<1)$fatal(1,"capture geometry");
 always @(posedge csi_clk or negedge w_up)begin
  if(!w_up)begin prev_fv<=0;prev_lv<=0;col<=0;rows<=0;failed<=0;fault_reason<=0;source_frames<=0;end
  else begin
   prev_fv<=csi_fv;prev_lv<=line;
   if(fv_rise)begin col<=0;rows<=0;end
   if(data_event)col<=x+1;
   if(line_fall)begin col<=0;rows<=rows+1;end
   if(!failed)begin
    if(bad_geometry)begin
     failed<=1;
     if(invalid_de)fault_reason<=1;
     else if(invalid_word)fault_reason<=2;
     else if(invalid_line)fault_reason<=3;
     else fault_reason<=4;
    end else if(event_valid&&!fifo_wr_ready)begin failed<=1;fault_reason<=5;end
    else if(frame_fall)source_frames<=source_frames+1;
   end
  end
 end
 async_packet_fifo #(.WIDTH(36),.LOG2(FIFO_LOG2)) crossing (
  .arst_n(arst_n),.wclk(csi_clk),.rclk(pixel_clk),.w_valid(event_valid),.w_data(event_data),.w_ready(fifo_wr_ready),
  .r_valid(fifo_rd_valid),.r_data(fifo_rd_data),.r_ready(fifo_rd_ready),.w_up(w_up),.r_up(r_up));
 (* async_reg="true" *)reg fault1,fault2;
 reg fault_seen;reg [1:0] lane;
 assign fault=fault2;
 assign out_valid=fifo_rd_valid&&r_up&&!fault2;
 assign out_raw=fifo_rd_data[8*lane+:8];
 assign out_sof=out_valid&&(fifo_rd_data[35:34]==0)&&fifo_rd_data[33]&&(lane==0);
 assign out_eol=out_valid&&(fifo_rd_data[35:34]==0)&&fifo_rd_data[32]&&(lane==3);
 assign out_frame_end=out_valid&&(fifo_rd_data[35:34]==1);
 assign fifo_rd_ready=out_ready&&!fault2&&((lane==3)||(fifo_rd_data[35:34]==1));
 always @(posedge pixel_clk or negedge r_up)begin
  if(!r_up)begin fault1<=0;fault2<=0;fault_seen<=0;lane<=0;abort_pulse<=0;end
  else begin
   fault1<=failed;fault2<=fault1;fault_seen<=fault2;abort_pulse<=fault2&&!fault_seen;
   if(out_valid&&out_ready)begin
    if(out_frame_end||lane==3)lane<=0;else lane<=lane+2'd1;
   end
  end
 end
endmodule
