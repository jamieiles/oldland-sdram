module bridge_testbench();

reg clk = 1'b0;

always #1 clk = ~clk;

reg [31:0] h_addr = 32'h8000bee0;
reg [31:0] h_wdata = 32'hdeadbeef;
wire [31:0] h_rdata;
reg h_wr_en = 1'b0;
reg [3:0] h_bytesel = 4'b1111;
wire h_compl;

wire [31:0] b_addr;
wire [15:0] b_wdata;
reg [15:0] b_rdata = 16'hf00d;
wire b_wr_en;
wire [1:0] b_bytesel;
reg b_compl = 1'b0;

bridge_32_16 the_bridge(.clk(clk),
			.h_addr(h_addr),
			.h_wdata(h_wdata),
			.h_rdata(h_rdata),
			.h_wr_en(h_wr_en),
			.h_bytesel(h_bytesel),
			.h_compl(h_compl),
			.b_addr(b_addr),
			.b_wdata(b_wdata),
			.b_rdata(b_rdata),
			.b_wr_en(b_wr_en),
			.b_bytesel(b_bytesel),
			.b_compl(b_compl));

reg [15:0] read_val = 16'h0101;

always @(posedge clk) begin
	if (|b_bytesel) begin
		#10 b_compl <= 1'b1;
		b_rdata <= read_val;
		read_val <= read_val + 1'b1;
		#2 b_compl <= 1'b0;
	end
end

always @(posedge clk) begin
	if (h_compl) begin
		if (h_rdata != 32'h01020101)
			$display("ERROR: invalid data read back (%x)", h_rdata);
		$finish;
	end
end

initial begin
	$dumpfile("bridge.vcd");
	$dumpvars(0, bridge_testbench);
	#500 $finish;
end

endmodule
