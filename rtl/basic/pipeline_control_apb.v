`timescale 1ns/1ps
// Supervisor for the paired live pipeline, not an arbitrary-address DMA API.
// CPU + AXI + pipeline reset must be coordinated; STOP never aborts live AXI.
module pipeline_control_apb #(parameter [31:0] SYS_HZ=96000000)(
 input wire clk,rst_n,psel,penable,pwrite,input wire [11:0] paddr,input wire [31:0] pwdata,
 output reg [31:0] prdata,output wire pready,output reg pslverr,output wire irq,
 output reg run_enable,output wire launch_valid,input wire launch_ready,queue_ready,compute_busy,work_idle,fault,
 input wire [31:0] next_source,next_result,next_id,
 input wire capture_started,capture_good,compute_done,compute_good,display_done,display_bad,
 input wire [31:0] capture_id,compute_id,display_id,input wire [3:0] compute_reason,
 output wire cfg_valid,output wire [5:0] cfg_addr,output wire [31:0] cfg_data,
 input wire cfg_ready,configured,cfg_error,
 output wire source_request,input wire source_ready,source_done,input wire [95:0] source_data,
 output wire osd_valid,output wire [31:0] osd_data,input wire osd_ready
);
 reg pending,cfg_fault,display_seen,last_error;
 reg [2:0] events,irq_mask;reg [3:0] last_reason;
 reg [31:0] captured,computed,displayed,repeats,tasks,errors,last_cap,last_cnn,last_disp,elapsed,last_cycles;
 reg [63:0] ticks;
 reg source_valid;reg [31:0] source_seq;reg [95:0] source_values;reg [63:0] source_time;
 reg [31:0] reserved,run_reserved,capture_limit;
 reg [26:0] cfg_mask;
 wire configuration_valid=configured&&(&cfg_mask)&&!cfg_fault;
 reg [31:0] snapshot_seq,s_cap,s_cnn,s_disp,s_rep,s_err,s_last_cap,s_last_cnn,s_last_disp;
 reg [63:0] s_ticks;
 wire access=psel&&penable;wire active=pending||compute_busy;
 wire cfg_sel=paddr>=12'h100&&paddr<=12'h168&&paddr[1:0]==0;
 assign cfg_addr=(paddr-12'h100)>>2;assign cfg_data=pwdata;
 wire signed [31:0] value=pwdata;
 wire range_ok=cfg_addr<18?(value>=-128&&value<=127):
  ((cfg_addr==18||cfg_addr==19)?(value>=-8388608&&value<=8388607):
  ((cfg_addr==20||cfg_addr==21||cfg_addr==24||cfg_addr==25)?(value>=-32768&&value<=32767):cfg_addr<27));
 assign pready=1;assign irq=|(events&irq_mask);assign launch_valid=pending;
 assign source_request=access&&pwrite&&paddr==12'h070&&!pslverr;
 assign osd_valid=access&&pwrite&&paddr==12'h0d0&&!pslverr;
 assign osd_data=pwdata;
 wire bcd_ok=pwdata[23:20]<=9&&pwdata[19:16]<=9&&pwdata[15:12]<=9&&pwdata[11:8]<=9&&pwdata[7:4]<=9&&pwdata[3:0]<=9;
// Keep configuration admission independent of the shared PSLVERR mux.
 // START readiness contains !cfg_valid; feeding that mux back forms a
 // structural combinational cycle even though register selects are exclusive.
 wire cfg_reject=run_enable||active||!work_idle||fault||!cfg_ready||!range_ok;
 assign cfg_valid=access&&pwrite&&cfg_sel&&!cfg_reject;
 always @*begin
  prdata=0;pslverr=0;
  if(pwrite)begin
   if(cfg_sel)pslverr=cfg_reject;
   else case(paddr)
    12'h008:pslverr=|pwdata[31:1]||(pwdata[0]&&(!configuration_valid||fault||run_enable||!work_idle||pending));
    12'h00c:pslverr=pwdata!=1||active||!launch_ready||!queue_ready||!configuration_valid||fault||events[0];
    12'h010,12'h014:pslverr=|pwdata[31:3];
    12'h060:pslverr=pwdata!=1;
    12'h070:pslverr=pwdata!=1||!source_ready||source_done;
    12'h0d0:pslverr=!osd_ready||(|pwdata[29:24])||!bcd_ok;
    12'h054:pslverr=run_enable||active||!work_idle||fault;
    default:pslverr=1;
   endcase
  end else case(paddr)
   12'h000:prdata=32'h56504950;
   12'h004:prdata={24'b0,events[0],cfg_fault,work_idle,fault,configuration_valid,queue_ready,active,run_enable};
   12'h008:prdata={31'b0,run_enable};12'h00c:prdata=0;
   12'h010:prdata={29'b0,irq_mask};12'h014:prdata={29'b0,events};
   12'h018:prdata=next_id;12'h01c:prdata=next_source;12'h020:prdata=next_result;
   12'h024:prdata=last_cnn;12'h028:prdata={27'b0,last_error,last_reason};12'h02c:prdata=last_cycles;
   12'h030:prdata=captured;12'h034:prdata=computed;12'h038:prdata=displayed;12'h03c:prdata=repeats;
   12'h040:prdata=last_cap;12'h044:prdata=last_disp;12'h048:prdata=tasks;12'h04c:prdata=errors;
   12'h050:prdata=reserved;12'h054:prdata=capture_limit;
   12'h058:prdata=SYS_HZ;12'h060:prdata=snapshot_seq;
   12'h070:prdata=source_seq;12'h074:prdata={30'b0,source_valid,!source_ready};
   12'h0b0:prdata=source_time[31:0];12'h0b4:prdata=source_time[63:32];
   12'h0b8:prdata=source_values[95:64];12'h0bc:prdata=source_values[63:32];12'h0c0:prdata=source_values[31:0];
   12'h0d0:prdata=0;12'h0d4:prdata={31'b0,osd_ready};
   12'h080:prdata=s_ticks[31:0];12'h084:prdata=s_ticks[63:32];
   12'h088:prdata=s_cap;12'h08c:prdata=s_cnn;12'h090:prdata=s_disp;12'h094:prdata=s_rep;
   12'h098:prdata=s_err;12'h09c:prdata=s_last_cap;12'h0a0:prdata=s_last_cnn;12'h0a4:prdata=s_last_disp;
   default:pslverr=1;
  endcase
  if(!access)pslverr=0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   run_enable<=0;pending<=0;cfg_fault<=0;display_seen<=0;last_error<=0;events<=0;irq_mask<=0;last_reason<=0;
   captured<=0;computed<=0;displayed<=0;repeats<=0;tasks<=0;errors<=0;last_cap<=0;last_cnn<=0;last_disp<=0;
   elapsed<=0;last_cycles<=0;ticks<=0;snapshot_seq<=0;s_ticks<=0;s_cap<=0;s_cnn<=0;s_disp<=0;s_rep<=0;s_err<=0;
   reserved<=0;run_reserved<=0;capture_limit<=0;
   cfg_mask<=0;source_valid<=0;source_seq<=0;source_values<=0;source_time<=0;
   s_last_cap<=0;s_last_cnn<=0;s_last_disp<=0;
  end else begin
   ticks<=ticks+1;
   if(source_request)source_valid<=0;
   if(source_done)begin source_values<=source_data;source_time<=ticks;source_seq<=source_seq+1;source_valid<=1;end
   if(active)elapsed<=elapsed+1;
   if(pending&&launch_ready)pending<=0;
   if(cfg_error)cfg_fault<=1;
   // First write after a complete set opens a new 27-word transaction. Until
   // all slots have been replaced, an old core mask must not permit START/RUN.
   if(cfg_valid)cfg_mask<=(&cfg_mask)?(27'd1<<cfg_addr):(cfg_mask|(27'd1<<cfg_addr));
   if(access&&pwrite&&!pslverr)case(paddr)
    12'h008:begin run_enable<=pwdata[0];if(pwdata[0])run_reserved<=0;end
    12'h00c:begin pending<=1;elapsed<=0;end
    12'h010:irq_mask<=pwdata[2:0];
    12'h054:capture_limit<=pwdata;
    12'h014:events<=events&~pwdata[2:0];
    12'h060:begin
     snapshot_seq<=snapshot_seq+1;s_ticks<=ticks;s_cap<=captured;s_cnn<=computed;s_disp<=displayed;s_rep<=repeats;s_err<=errors;
     s_last_cap<=last_cap;s_last_cnn<=last_cnn;s_last_disp<=last_disp;
    end
   endcase
   if(capture_started)begin
    reserved<=reserved+1;run_reserved<=run_reserved+1;
    if(capture_limit!=0&&run_reserved+1>=capture_limit)run_enable<=0;
   end
   if(capture_good)begin captured<=captured+1;last_cap<=capture_id;end
   // Event set wins W1C on the same cycle. No software-clearable AXI lock.
   if(compute_done)begin
    events[0]<=1;tasks<=tasks+1;last_cnn<=compute_id;last_reason<=compute_reason;last_error<=!compute_good;last_cycles<=elapsed;
    if(compute_good)computed<=computed+1;else errors<=errors+1;
   end
   if(display_done)begin
    events[1]<=1;
    if(!display_bad)begin
     if(!display_seen||display_id!=last_disp)begin displayed<=displayed+1;last_disp<=display_id;display_seen<=1;end
     else repeats<=repeats+1;
    end
   end
   if(fault)events[2]<=1;
  end
 end
endmodule
