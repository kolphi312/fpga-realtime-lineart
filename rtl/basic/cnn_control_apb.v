`timescale 1ns/1ps
// APB3, same clk as accelerator. Exactly one accepted access per APB transfer.
// Status/IRQ describe safe DMA completion, never mere compute completion.
module cnn_control_apb(
 input wire clk,rst_n,input wire psel,penable,pwrite,input wire [11:0] paddr,input wire [31:0] pwdata,
 output reg [31:0] prdata,output wire pready,output reg pslverr,output wire irq,
 output wire cmd_valid,input wire cmd_ready,output reg [31:0] src_base,dst_base,job_id,
 input wire busy,done,ok,locked,input wire [3:0] reason,input wire [31:0] result_id,
 output wire cfg_valid,output wire [5:0] cfg_addr,output wire [31:0] cfg_data,
 input wire cfg_ready,configured,cfg_error
);
 reg pending,complete,error,irq_enable,cfg_fault;
 reg [3:0] last_reason;reg [31:0] last_id,cycles,last_cycles,completed_count,good_count;
 wire active=pending||busy;wire access=psel&&penable;
 wire cfg_sel=(paddr>=12'h100&&paddr<=12'h168&&paddr[1:0]==0);
 assign cfg_addr=(paddr-12'h100)>>2;assign cfg_data=pwdata;
 wire signed [31:0] value=pwdata;
 wire range_ok=(cfg_addr<18)?(value>=-128&&value<=127):
  ((cfg_addr==18||cfg_addr==19)?(value>=-8388608&&value<=8388607):
  ((cfg_addr==20||cfg_addr==21||cfg_addr==24||cfg_addr==25)?(value>=-32768&&value<=32767):(cfg_addr<27)));
 assign cfg_valid=access&&pwrite&&cfg_sel&&!pslverr;
 assign cmd_valid=pending;assign pready=1;assign irq=irq_enable&&complete;
 always @*begin
  prdata=0;pslverr=0;
  if(pwrite)begin
   if(cfg_sel)pslverr=active||!cfg_ready||!range_ok;
   else case(paddr)
    12'h008,12'h00c,12'h010:pslverr=active||locked;
    12'h014:pslverr=(|pwdata[31:2])||(pwdata[0]&&(active||locked||!cmd_ready));
    12'h018:pslverr=|pwdata[31:1];
    default:pslverr=1;
   endcase
  end else case(paddr)
   12'h000:prdata=32'h434e4e32;
   12'h004:prdata={26'b0,cfg_fault,configured,locked,error,complete,active};
   12'h008:prdata=src_base;12'h00c:prdata=dst_base;12'h010:prdata=job_id;
   12'h014:prdata=0;12'h018:prdata={31'b0,irq_enable};
   12'h01c:prdata=last_id;12'h020:prdata={28'b0,last_reason};12'h024:prdata=last_cycles;
   12'h028:prdata=completed_count;12'h02c:prdata=good_count;
   default:pslverr=1;
  endcase
  if(!access)pslverr=0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pending<=0;complete<=0;error<=0;irq_enable<=0;cfg_fault<=0;src_base<=0;dst_base<=0;job_id<=0;
   last_id<=0;last_reason<=0;cycles<=0;last_cycles<=0;completed_count<=0;good_count<=0;
  end else begin
   if(pending&&cmd_ready)pending<=0;
   if(active)cycles<=cycles+1;
   if(cfg_error)cfg_fault<=1;
   if(access&&pwrite&&!pslverr)case(paddr)
    12'h008:src_base<=pwdata;12'h00c:dst_base<=pwdata;12'h010:job_id<=pwdata;
    12'h018:irq_enable<=pwdata[0];
    12'h014:begin
     if(pwdata[1])begin complete<=0;error<=0;cfg_fault<=0;end
     if(pwdata[0])begin pending<=1;cycles<=0;complete<=0;error<=0;end
    end
   endcase
   // Completion wins a simultaneous ACK: the new event must remain visible.
   if(done)begin
    complete<=1;error<=!ok;last_id<=result_id;last_reason<=reason;last_cycles<=cycles;
    completed_count<=completed_count+1;if(ok)good_count<=good_count+1;
   end
  end
 end
endmodule
