module counter(input wire clk,
	       output wire [count_width - 1:0] count,
	       input wire reset);

parameter count_width = 8;
parameter count_max = 255;

reg [count_width - 1:0] count_reg = 0;

always @(posedge clk) begin
	if (reset)
		count_reg <= 0;
	else if (count_reg != count_max[count_width - 1:0])
		count_reg <= count_reg + 1'b1;
end

assign count = count_reg;

endmodule
