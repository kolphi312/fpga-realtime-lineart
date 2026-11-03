`timescale 1ns/1ps
// One writer, one reader, explicit ownership. Instantiate separate pools for
// input and result frames. Multiple simultaneous readers require refcounts;
// this module does not silently grant shared ownership.
module frame_bank_owner #(
 parameter BANKS=4,INDEX_W=$clog2(BANKS),
 parameter [31:0] POOL_BASE=32'h01000000,BANK_STRIDE=32'h00200000,
 parameter FRAME_BYTES=640*480*4
)(
 input wire clk,rst_n,
 input wire write_request,input wire [31:0] write_frame_id,
 output wire write_ready,output wire [INDEX_W-1:0] write_bank,output wire [31:0] write_addr,
 input wire write_done,write_ok,
 input wire read_request,output wire read_ready,output wire [INDEX_W-1:0] read_bank,
 output wire [31:0] read_addr,read_frame_id,input wire read_release,
 output reg protocol_error,output reg writer_busy,reader_busy,
 output wire [BANKS*2-1:0] bank_states
);
 localparam FREE=0,WRITING=1,READY=2,READING=3;
 localparam COUNT_W=$clog2(BANKS+1);
 localparam [63:0] POOL_END=64'd1*POOL_BASE+64'd1*BANKS*BANK_STRIDE;
 reg [1:0] state[0:BANKS-1];
 reg [31:0] ids[0:BANKS-1];
 reg [INDEX_W-1:0] queue[0:BANKS-1],head,tail,wb,rb;
 reg [COUNT_W-1:0] count;
 reg free_found;reg [INDEX_W-1:0] free_bank;
 wire [BANKS-1:0] is_free;
 integer i;
 always @*begin
  free_found=0;free_bank=0;
  for(integer j=0;j<BANKS;j=j+1)if(!free_found&&is_free[j])begin free_found=1;free_bank=j;end
 end
 assign write_ready=!protocol_error&&!writer_busy&&free_found;
 assign read_ready=!protocol_error&&!reader_busy&&(count!=0);
 assign write_bank=writer_busy?wb:free_bank;
 assign read_bank=reader_busy?rb:((count!=0)?queue[head]:{INDEX_W{1'b0}});
 assign write_addr=POOL_BASE+write_bank*BANK_STRIDE;
 assign read_addr=POOL_BASE+read_bank*BANK_STRIDE;
 assign read_frame_id=ids[read_bank];
 genvar g;generate for(g=0;g<BANKS;g=g+1)begin:S assign bank_states[g*2+:2]=state[g];assign is_free[g]=(state[g]==FREE);end endgenerate
 wire wa=write_request&&write_ready,ra=read_request&&read_ready;
 wire enqueue=write_done&&writer_busy&&write_ok;
 wire illegal=(write_done&&!writer_busy)||(read_release&&!reader_busy);
 initial if(BANKS<2||BANKS>16||INDEX_W<$clog2(BANKS)||FRAME_BYTES<1||
   BANK_STRIDE<FRAME_BYTES||POOL_BASE[3:0]!=0||BANK_STRIDE[3:0]!=0||POOL_END>64'h100000000)
  $fatal(1,"invalid bank pool configuration");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   for(i=0;i<BANKS;i=i+1)begin state[i]<=FREE;ids[i]<=0;queue[i]<=0;end
   head<=0;tail<=0;count<=0;wb<=0;rb<=0;writer_busy<=0;reader_busy<=0;protocol_error<=0;
  end else if(!protocol_error)begin
   if(illegal)protocol_error<=1;
   else begin
    if(wa)begin state[free_bank]<=WRITING;ids[free_bank]<=write_frame_id;wb<=free_bank;writer_busy<=1;end
    if(write_done)begin
     writer_busy<=0;state[wb]<=write_ok?READY:FREE;
     if(write_ok)begin queue[tail]<=wb;tail<=(tail==BANKS-1)?0:tail+1'b1;end
    end
    if(ra)begin rb<=queue[head];state[queue[head]]<=READING;reader_busy<=1;head<=(head==BANKS-1)?0:head+1'b1;end
    if(read_release)begin state[rb]<=FREE;reader_busy<=0;end
    case({enqueue,ra})
     2'b10:count<=count+1'b1;
     2'b01:count<=count-1'b1;
     default:count<=count;
    endcase
   end
  end
 end
endmodule
