`timescale 1ns/1ps
// Passive SYS-domain one-shot observer. No control outputs. LIMIT active clocks
// after launch denotes a long task, not necessarily a deadlock. Freeze forever
// until reset, before software's 2-second watchdog can alter downstream state.
// Pixel counts include handshakes on the sampling edge, state/flow are pre-edge.
module job_progress_probe #(parameter LIMIT=96000000)(
 input wire clk,rst_n,launch,busy,input wire [31:0] job_id,
 input wire [19:0] states,flow,input wire input_fire,output_fire,
 output reg frozen,output wire [23:0] page_a,page_b,page_c,page_d,page_id);
 localparam AW=(LIMIT>1)?$clog2(LIMIT):1;
 reg [AW-1:0] age;
 reg [19:0] nin,nout,id_q;
 (* syn_preserve=1 *) reg [19:0] snap_state,snap_flow,snap_in,snap_out,snap_id;
 wire [19:0] in_next=(input_fire&&nin!=20'hfffff)?nin+1'b1:nin;
 wire [19:0] out_next=(output_fire&&nout!=20'hfffff)?nout+1'b1:nout;
 assign page_a={4'ha,snap_state};assign page_b={4'hb,snap_flow};
 assign page_c={4'hc,snap_in};assign page_d={4'hd,snap_out};assign page_id={4'hf,snap_id};
 initial if(LIMIT<1)$fatal(1,"invalid progress threshold");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin frozen<=0;age<=0;nin<=0;nout<=0;id_q<=0;snap_state<=0;snap_flow<=0;snap_in<=0;snap_out<=0;snap_id<=0;end
  else if(!frozen)begin
   if(launch)begin age<=0;nin<=0;nout<=0;id_q<=job_id[19:0];end
   else if(busy)begin
    nin<=in_next;nout<=out_next;
    if(age==LIMIT-1)begin
     frozen<=1;snap_state<=states;snap_flow<=flow;snap_in<=in_next;snap_out<=out_next;snap_id<=id_q;
    end else age<=age+1'b1;
   end else age<=0;
  end
 end
endmodule
