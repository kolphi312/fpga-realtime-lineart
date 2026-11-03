`timescale 1ns/1ps
// Passive SYS-domain observation. Never drives or gates AXI. Freeze once at
// software halt publication, after watchdog STOP/masking (accepted AXI may drain).
module axi_timeout_probe(input wire clk,rst_n,trigger,
 input wire [3:0] awid,arid,bid,rid,
 input wire awv,awr,wv,wr,wl,bv,br,arv,arr,rv,rr,rl,av,ard,at,
 output reg frozen,output wire [23:0] page_c,page_d);
 reg [9:0] nr,nw;reg [19:0] flags,counts;
 assign page_c={4'hc,flags};assign page_d={4'hd,counts};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin frozen<=0;nr<=0;nw<=0;flags<=0;counts<=0;end
  else if(!frozen)begin
   if(trigger)begin
    frozen<=1;
    flags<={1'b1,at,ard,av,rid[0],bid[0],arid[0],awid[0],rl,rr,rv,arr,arv,br,bv,wl,wr,wv,awr,awv};
    counts<={nw,nr};
   end else begin
    if(arv&&arr&&arid==0&&nr!=10'h3ff)nr<=nr+1'b1;
    if(awv&&awr&&awid==1&&nw!=10'h3ff)nw<=nw+1'b1;
   end
  end
 end
endmodule
