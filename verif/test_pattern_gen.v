module test_pattern_gen(input wire pattern_sel,
			input wire [31:0] addr,
			output wire [15:0] data);

reg [15:0] out = 32'b0;

always @(*) begin
	if (!pattern_sel)
		out = addr + 1;
	else
		out = addr[2] ? 16'haa55 : 16'h55aa;
end

assign data = out;

endmodule
