`timescale 1ns/1ps
// Line-based Conv3x3 1->2, inference BN affine Q8, saturating ReLU8,
// Conv1x1 2->1 Q8. BLACK one-pixel perimeter, exactly W*H outputs.
// No frame RAM. Three rotating Y row memories. All state stops on output stall.
// Coefficients explicitly programmed before start; no trained weights implied.
module cnn2_stream #(parameter W=640,H=480,AW=$clog2(W))(
 input wire clk,rst_n,start,abort,
 input wire cfg_valid,input wire [5:0] cfg_addr,input wire [31:0] cfg_data,
 output wire cfg_ready,configured,output reg cfg_error,
 input wire in_valid,output wire in_ready,input wire [23:0] in_rgb,
 input wire in_sof,in_eol,in_eof,
 output wire out_valid,input wire out_ready,output wire [23:0] out_rgb,
 output wire out_sof,out_eol,out_eof,
 output wire busy,output reg done,fault,output wire [3:0] debug_state
);
 localparam IDLE=0,LOAD=1,PREP=2,RL=3,RC=4,RR=5,MUL=6,SUM=7,AFF=8,ACT=9,MIX=10,OUT=11;
 reg [3:0] state;
 assign debug_state=state;
 reg [26:0] mask;
 reg signed [7:0] weights[0:17];
 reg signed [23:0] bias0,bias1;
 reg signed [15:0] alpha0,alpha1,mix0,mix1;
 reg signed [31:0] beta0,beta1,mix_bias;
 integer i;
 wire signed [31:0] cd=cfg_data;
 wire cfg_range=(cfg_addr<18)?(cd>=-128&&cd<=127):
  ((cfg_addr==18||cfg_addr==19)?(cd>=-8388608&&cd<=8388607):
  ((cfg_addr==20||cfg_addr==21||cfg_addr==24||cfg_addr==25)?(cd>=-32768&&cd<=32767):(cfg_addr<27)));
 assign cfg_ready=state==IDLE;
 assign configured=&mask;
 reg [31:0] lx,ly,ox,oy;
 reg [1:0] bank;
 reg [7:0] row0[0:W-1],row1[0:W-1],row2[0:W-1];
 reg [7:0] r0,r1,r2;
 wire [9:0] lum={2'b0,in_rgb[23:16]}+{1'b0,in_rgb[15:8],1'b0}+{2'b0,in_rgb[7:0]};
 wire [AW-1:0] read_addr=(state==RL)?(ox-1):((state==RC)?ox:(ox+1));
 wire [7:0] top=(bank==0)?r1:((bank==1)?r2:r0);
 wire [7:0] mid=(bank==0)?r2:((bank==1)?r0:r1);
 wire [7:0] bot=(bank==0)?r0:((bank==1)?r1:r2);
 reg [7:0] a0,a1,a3,a4,a6,a7;
 reg signed [16:0] products[0:17];
 wire signed [31:0] p[0:17];
 genvar g;generate for(g=0;g<18;g=g+1)begin:EXT assign p[g]={{15{products[g][16]}},products[g]};end endgenerate
 reg signed [31:0] acc0,acc1;
 wire signed [47:0] scale0=acc0*alpha0,scale1=acc1*alpha1;
 reg signed [48:0] affine0,affine1;
 reg [7:0] feature0,feature1,pixel;
 wire signed [24:0] mixp0=$signed({1'b0,feature0})*mix0,mixp1=$signed({1'b0,feature1})*mix1;
 wire signed [33:0] mixed={{9{mixp0[24]}},mixp0}+{{9{mixp1[24]}},mixp1}+{{2{mix_bias[31]}},mix_bias};
 function [7:0] relu8(input signed [48:0] v);
  begin if(v<0)relu8=0;else if(v>=49'sd65280)relu8=255;else relu8=v[15:8];end
 endfunction
 assign busy=state!=IDLE;
 assign in_ready=state==LOAD&&!abort&&!fault;
 assign out_valid=state==OUT&&!abort&&!fault;
 assign out_rgb={pixel,pixel,pixel};
 assign out_sof=(ox==0&&oy==0);assign out_eol=ox==W-1;assign out_eof=ox==W-1&&oy==H-1;
 wire take=in_valid&&in_ready;
 wire bad=take&&((in_sof!=(lx==0&&ly==0))||(in_eol!=(lx==W-1))||(in_eof!=(lx==W-1&&ly==H-1)));
 initial if(W<3||H<3||AW<$clog2(W))$fatal(1,"CNN geometry");
 // Synchronous read. LOAD and read phases are disjoint: no RAM collision rule.
 always @(posedge clk)begin
  if(take&&!bad)case(bank)0:row0[lx[AW-1:0]]<=lum[9:2];1:row1[lx[AW-1:0]]<=lum[9:2];2:row2[lx[AW-1:0]]<=lum[9:2];endcase
  if(state==RL||state==RC||state==RR)begin r0<=row0[read_addr];r1<=row1[read_addr];r2<=row2[read_addr];end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;mask<=0;cfg_error<=0;fault<=0;done<=0;lx<=0;ly<=0;ox<=0;oy<=0;bank<=0;
   bias0<=0;bias1<=0;alpha0<=0;alpha1<=0;beta0<=0;beta1<=0;mix0<=0;mix1<=0;mix_bias<=0;
   for(i=0;i<18;i=i+1)begin weights[i]<=0;products[i]<=0;end
   a0<=0;a1<=0;a3<=0;a4<=0;a6<=0;a7<=0;acc0<=0;acc1<=0;affine0<=0;affine1<=0;feature0<=0;feature1<=0;pixel<=0;
  end else begin
   done<=0;cfg_error<=0;
   if(cfg_valid)begin
    if(!cfg_ready||!cfg_range)cfg_error<=1;
    else begin
     mask[cfg_addr]<=1;
     if(cfg_addr<18)weights[cfg_addr]<=cfg_data[7:0];
     else case(cfg_addr)
      18:bias0<=cfg_data[23:0];19:bias1<=cfg_data[23:0];20:alpha0<=cfg_data[15:0];21:alpha1<=cfg_data[15:0];
      22:beta0<=cfg_data;23:beta1<=cfg_data;24:mix0<=cfg_data[15:0];25:mix1<=cfg_data[15:0];26:mix_bias<=cfg_data;
     endcase
    end
   end
   case(state)
    IDLE:if(start)begin
     fault<=!configured;
     if(configured)begin state<=LOAD;lx<=0;ly<=0;ox<=0;oy<=0;bank<=0;end
    end
    LOAD:if(take)begin
     if(lx==W-1)begin
      lx<=0;
      if(ly<2)begin ly<=ly+1;bank<=bank+1;end
      else begin state<=PREP;ox<=0;oy<=(ly==2)?0:ly-1;end
     end else lx<=lx+1;
    end
    PREP:if(ox==0||ox==W-1||oy==0||oy==H-1)begin pixel<=0;state<=OUT;end else state<=RL;
    RL:state<=RC;
    RC:begin a0<=top;a3<=mid;a6<=bot;state<=RR;end
    RR:begin a1<=top;a4<=mid;a7<=bot;state<=MUL;end
    MUL:begin
     for(i=0;i<2;i=i+1)begin
      products[i*9+0]<=$signed({1'b0,a0})*weights[i*9+0];products[i*9+1]<=$signed({1'b0,a1})*weights[i*9+1];products[i*9+2]<=$signed({1'b0,top})*weights[i*9+2];
      products[i*9+3]<=$signed({1'b0,a3})*weights[i*9+3];products[i*9+4]<=$signed({1'b0,a4})*weights[i*9+4];products[i*9+5]<=$signed({1'b0,mid})*weights[i*9+5];
      products[i*9+6]<=$signed({1'b0,a6})*weights[i*9+6];products[i*9+7]<=$signed({1'b0,a7})*weights[i*9+7];products[i*9+8]<=$signed({1'b0,bot})*weights[i*9+8];
     end
     state<=SUM;
    end
    SUM:begin
     acc0<=((p[0]+p[1])+(p[2]+p[3]))+((p[4]+p[5])+(p[6]+p[7]))+p[8]+{{8{bias0[23]}},bias0};
     acc1<=((p[9]+p[10])+(p[11]+p[12]))+((p[13]+p[14])+(p[15]+p[16]))+p[17]+{{8{bias1[23]}},bias1};state<=AFF;
    end
    AFF:begin affine0<={scale0[47],scale0}+{{17{beta0[31]}},beta0};affine1<={scale1[47],scale1}+{{17{beta1[31]}},beta1};state<=ACT;end
    ACT:begin feature0<=relu8(affine0);feature1<=relu8(affine1);state<=MIX;end
    MIX:begin pixel<=relu8({{15{mixed[33]}},mixed});state<=OUT;end
    OUT:if(out_ready)begin
     if(ox==W-1)begin
      ox<=0;
      if(oy==H-1)begin state<=IDLE;done<=1;end
      else if(oy==0||oy==H-2)begin oy<=oy+1;state<=PREP;end
      else begin ly<=ly+1;bank<=(bank==2)?0:bank+1;state<=LOAD;end
     end else begin
      ox<=ox+1;
      if(ox>=1&&ox<W-2&&oy>0&&oy<H-1)begin
       // Reuse the two overlapping columns, fetch only the new right column.
       // RR captures the old right column as centre before the RAM read updates.
       a0<=a1;a3<=a4;a6<=a7;state<=RR;
      end else state<=PREP;
     end
    end
    default:begin state<=IDLE;fault<=1;end
   endcase
   if(abort||bad)begin state<=IDLE;fault<=bad;done<=0;end
  end
 end
endmodule
