`timescale 1ns/1ps
// A pair reserves one source bank and one result bank for its entire lifetime.
// safe *_done means DMA has drained ALL transactions, including final B.
// Display owns BOTH banks until release. No latest-frame substitution/drop.
// All interfaces synchronous; reset MUST be coordinated with the AXI fabric.
module paired_frame_owner #(
 parameter BANKS=4,IW=$clog2(BANKS),
 parameter [31:0] INPUT_BASE=32'h01000000,RESULT_BASE=32'h02000000,
 parameter [31:0] STRIDE=32'h00200000,FIRST_ID=0,
 parameter FRAME_BYTES=640*480*4
)(
 input wire clk,rst_n,fatal_bus,
 input wire cap_request,output wire cap_ready,output wire [IW-1:0] cap_bank,
 output wire [31:0] cap_addr,cap_id,input wire cap_done,cap_ok,input wire [31:0] cap_done_id,
 input wire cnn_request,output wire cnn_ready,output wire [IW-1:0] cnn_bank,
 output wire [31:0] cnn_src,cnn_dst,cnn_id,input wire cnn_done,cnn_ok,input wire [31:0] cnn_done_id,
 input wire disp_request,output wire disp_ready,output wire [IW-1:0] disp_bank,
 output wire [31:0] disp_src,disp_dst,disp_id,input wire disp_release,input wire [31:0] disp_release_id,
 output reg cap_busy,cnn_busy,disp_busy,output reg protocol_error,
 output wire [BANKS*3-1:0] states
);
 localparam FREE=0,CAP=1,QUEUED=2,CNN=3,READY=4,DISPLAY=5;
 localparam CW=$clog2(BANKS+1);
 reg [2:0] state[0:BANKS-1];reg [31:0] ids[0:BANKS-1],next_id;
 reg [IW-1:0] cq[0:BANKS-1],dq[0:BANKS-1],ch,ct,dh,dt,cb,nb,db;
 reg [CW-1:0] cn,dn;
 reg found,duplicate;reg [IW-1:0] free_bank;
 integer i;
 wire [BANKS-1:0] free_bits,id_match;
 genvar q;generate for(q=0;q<BANKS;q=q+1)begin:F
  assign free_bits[q]=state[q]==FREE;assign id_match[q]=state[q]!=FREE&&ids[q]==next_id;
 end endgenerate
 always @*begin
  found=0;free_bank=0;duplicate=0;
  for(integer j=0;j<BANKS;j=j+1)begin
   if(free_bits[j]&&!found)begin found=1;free_bank=j;end
   if(id_match[j])duplicate=1;
  end
 end
 wire invalid=(cap_done&&(!cap_busy||cap_done_id!=ids[cb]))||
  (cnn_done&&(!cnn_busy||cnn_done_id!=ids[nb]))||
  (disp_release&&(!disp_busy||disp_release_id!=ids[db]));
 wire stop=protocol_error||fatal_bus||invalid;
 assign cap_ready=!stop&&!cap_busy&&found&&!duplicate;
 assign cnn_ready=!stop&&!cnn_busy&&(cn!=0);
 assign disp_ready=!stop&&!disp_busy&&(dn!=0);
 assign cap_bank=cap_busy?cb:free_bank;
 assign cnn_bank=cnn_busy?nb:((cn!=0)?cq[ch]:0);
 assign disp_bank=disp_busy?db:((dn!=0)?dq[dh]:0);
 assign cap_id=cap_busy?ids[cb]:next_id;
 assign cnn_id=ids[cnn_bank];assign disp_id=ids[disp_bank];
 assign cap_addr=INPUT_BASE+cap_bank*STRIDE;
 assign cnn_src=INPUT_BASE+cnn_bank*STRIDE;assign cnn_dst=RESULT_BASE+cnn_bank*STRIDE;
 assign disp_src=INPUT_BASE+disp_bank*STRIDE;assign disp_dst=RESULT_BASE+disp_bank*STRIDE;
 genvar g;generate for(g=0;g<BANKS;g=g+1)begin:S assign states[g*3+:3]=state[g];end endgenerate
 wire ca=cap_request&&cap_ready,na=cnn_request&&cnn_ready,da=disp_request&&disp_ready;
 wire ce=cap_done&&cap_ok,ne=cnn_done&&cnn_ok;
 localparam [63:0] IE=64'd1*INPUT_BASE+64'd1*BANKS*STRIDE,RE=64'd1*RESULT_BASE+64'd1*BANKS*STRIDE;
 initial if(BANKS<2||BANKS>8||IW<$clog2(BANKS)||STRIDE<FRAME_BYTES||FRAME_BYTES<1||
  INPUT_BASE[3:0]!=0||RESULT_BASE[3:0]!=0||STRIDE[3:0]!=0||IE>64'h100000000||RE>64'h100000000||
  !(IE<=RESULT_BASE||RE<=INPUT_BASE))$fatal(1,"invalid paired pools");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   for(i=0;i<BANKS;i=i+1)begin state[i]<=FREE;ids[i]<=0;cq[i]<=0;dq[i]<=0;end
   next_id<=FIRST_ID;ch<=0;ct<=0;dh<=0;dt<=0;cn<=0;dn<=0;cb<=0;nb<=0;db<=0;
   cap_busy<=0;cnn_busy<=0;disp_busy<=0;protocol_error<=0;
  end else if(!protocol_error)begin
   if(fatal_bus||invalid)protocol_error<=1;
   else begin
    if(ca)begin cb<=free_bank;ids[free_bank]<=next_id;next_id<=next_id+1'b1;state[free_bank]<=CAP;cap_busy<=1;end
    if(cap_done)begin
     cap_busy<=0;state[cb]<=cap_ok?QUEUED:FREE;
     if(cap_ok)begin cq[ct]<=cb;ct<=(ct==BANKS-1)?0:ct+1'b1;end
    end
    if(na)begin nb<=cq[ch];state[cq[ch]]<=CNN;cnn_busy<=1;ch<=(ch==BANKS-1)?0:ch+1'b1;end
    if(cnn_done)begin
     cnn_busy<=0;state[nb]<=cnn_ok?READY:FREE;
     if(cnn_ok)begin dq[dt]<=nb;dt<=(dt==BANKS-1)?0:dt+1'b1;end
    end
    if(da)begin db<=dq[dh];state[dq[dh]]<=DISPLAY;disp_busy<=1;dh<=(dh==BANKS-1)?0:dh+1'b1;end
    if(disp_release)begin state[db]<=FREE;disp_busy<=0;end
    case({ce,na})2'b10:cn<=cn+1'b1;2'b01:cn<=cn-1'b1;default:cn<=cn;endcase
    case({ne,da})2'b10:dn<=dn+1'b1;2'b01:dn<=dn-1'b1;default:dn<=dn;endcase
   end
  end
 end
endmodule
