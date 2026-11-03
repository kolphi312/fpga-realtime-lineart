`timescale 1ns/1ps
// Synchronous RAM read plus a held output register. Capacity includes the
// output register: exactly 2**LOG2 words, no dependence on read-during-write.
module rgb_sync_fifo #(parameter LOG2=8,WIDTH=24)(
 input wire clk,rst_n,in_valid,output wire in_ready,input wire [WIDTH-1:0] in_data,
 output reg out_valid,input wire out_ready,output wire [WIDTH-1:0] out_data,
 output wire [LOG2:0] occupancy
);
 localparam DEPTH=1<<LOG2;
 reg [WIDTH-1:0] mem[0:DEPTH-1];
 reg [WIDTH-1:0] read_q;
 reg [LOG2-1:0] wp,rp;
 reg [LOG2:0] mem_count;
 wire consume=out_valid&&out_ready;
 assign occupancy=mem_count+out_valid;
 assign in_ready=(occupancy<DEPTH)||consume;
 wire push=in_valid&&in_ready;
 wire fetch=(mem_count!=0)&&(!out_valid||out_ready);
 assign out_data=read_q;
 // RAM and its read register deliberately have no asynchronous reset.
 // Valid/count reset prevents old contents becoming accepted pixels.
 always @(posedge clk)begin
  if(rst_n&&push)mem[wp]<=in_data;
  if(rst_n&&fetch)read_q<=mem[rp];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wp<=0;rp<=0;mem_count<=0;out_valid<=0;end
  else begin
   if(push)wp<=wp+1'b1;
   if(fetch)begin rp<=rp+1'b1;out_valid<=1;end else if(consume)out_valid<=0;
   case({push,fetch})
    2'b10:mem_count<=mem_count+1'b1;
    2'b01:mem_count<=mem_count-1'b1;
    default:mem_count<=mem_count;
   endcase
  end
 end
 initial if(LOG2<1||LOG2>16||WIDTH<1)$fatal(1,"invalid FIFO parameters");
endmodule
