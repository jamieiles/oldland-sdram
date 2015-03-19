module test_pattern_gen(input wire pattern_sel,
			input wire [31:2] addr,
			output wire [31:0] data);

reg [31:0] out = 32'b0;

always @(*) begin
	if (!pattern_sel)
		out = addr + 1;
	else
		out = addr[2] ? 32'haa5555aa : 32'h55aaaa55;
end

assign data = out;

endmodule
