`timescale 1ns/1ps
// clk_sys inputs only. CPU reset is NOT connected to DMA reset.
// Before first ready: wait. After arming: any loss is sticky quarantine.
// Only the board/fabric coordinated reset clears the quarantine. Never time
// out and pretend that an AXI transaction completed or release a held bank.
module pipeline_lifecycle(
 input wire clk,rst_n,memory_ready,cpu_reset,
 output wire halt_new,fault,output wire [31:0] status
);
 reg armed;reg [1:0] reasons;
 wire [1:0] observed=armed?{cpu_reset,!memory_ready}:2'b00;
 assign fault=(|reasons)||(|observed);
 assign halt_new=!armed||!memory_ready||cpu_reset||fault;
 assign status={16'h4c43,6'b0,(reasons|observed),3'b0,cpu_reset,memory_ready,halt_new,fault,armed};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin armed<=0;reasons<=0;end
  else begin
   if(memory_ready&&!cpu_reset&&!fault)armed<=1;
   reasons<=reasons|observed;
  end
 end
endmodule
