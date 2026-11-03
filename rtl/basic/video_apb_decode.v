`timescale 1ns/1ps
// Relative to the existing SoC external APB aperture F8100000..F810FFFF.
// Legacy style: page 0, only the 32-byte register bank; pipeline: page 1.
// PSEL isolation is mandatory because legacy style_apb decodes only [4:2].
module video_apb_decode(
 input wire [15:0] paddr,input wire psel,penable,pwrite,input wire [31:0] pwdata,
 output wire pready,pslverr,output wire [31:0] prdata,
 output wire [15:0] legacy_addr,output wire legacy_sel,legacy_enable,legacy_write,
 output wire [31:0] legacy_wdata,input wire legacy_ready,legacy_error,input wire [31:0] legacy_rdata,
 output wire [11:0] pipeline_addr,output wire pipeline_sel,pipeline_enable,pipeline_write,
 output wire [31:0] pipeline_wdata,input wire pipeline_ready,pipeline_error,input wire [31:0] pipeline_rdata
);
 wire aligned=paddr[1:0]==0;
 wire hit_legacy=aligned&&paddr[15:5]==0;
 wire hit_pipeline=aligned&&paddr[15:12]==4'h1;
 assign legacy_addr=paddr;assign pipeline_addr=paddr[11:0];
 assign legacy_sel=psel&&hit_legacy;assign pipeline_sel=psel&&hit_pipeline;
 assign legacy_enable=penable;assign pipeline_enable=penable;
 assign legacy_write=pwrite;assign pipeline_write=pwrite;
 assign legacy_wdata=pwdata;assign pipeline_wdata=pwdata;
 assign pready=!psel?1'b1:(hit_legacy?legacy_ready:(hit_pipeline?pipeline_ready:1'b1));
 assign prdata=!psel?32'b0:(hit_legacy?legacy_rdata:(hit_pipeline?pipeline_rdata:32'b0));
 assign pslverr=psel&&penable&&(hit_legacy?legacy_error:(hit_pipeline?pipeline_error:1'b1));
endmodule
